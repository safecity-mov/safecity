-- L'application — 0220 : réparation après le rejeu du 21/09, et fin du rejeu.
--
-- Ce qui s'est passé. Jusqu'ici, chaque déploiement rejouait **tous** les fichiers de ce
-- dossier, chacun dans sa transaction, sans s'arrêter quand l'un échouait. Le modèle tenait
-- sur un invariant implicite : la dernière migration qui définit un objet doit repasser,
-- parce que les précédentes le réinstallent dans une version périmée. Depuis 0200, six
-- fichiers échouaient à chaque rejeu — 0040, 0060, 0070, 0100, 0110, 0120 parlent d'une
-- colonne `confirmations` ou d'un palier 3 qui n'existent plus — et c'était sans conséquence :
-- annulés en bloc, ils ne changeaient rien. Puis le 21/09/2026, au déploiement de 0210 :
--
--   1. 0030 repasse et réinstalle sa version de `recompute_hazard` (qui écrit
--      `hazards.confirmations`), sa `proximity_weight(tier)` à poids constants, son
--      `proximity_tier` serveur, et deux surcharges d'avant 0100 et 0200.
--   2. 0100 échoue (son INSERT du palier 3 viole la contrainte posée par 0200), donc son
--      `DROP FUNCTION proximity_weight(smallint)` n'a pas lieu.
--   3. 0200 fait `CREATE OR REPLACE FUNCTION proximity_weight(p_tier smallint)` sur une
--      fonction dont le paramètre s'appelle `tier` : PostgreSQL refuse (« cannot change name
--      of input parameter »), 0200 est annulé en entier, et `recompute_hazard` reste celui de
--      0030.
--   4. Chaque geste — signaler, confirmer, résoudre — insère dans `events`, le trigger appelle
--      `recompute_hazard`, qui écrit dans une colonne qui n'existe plus : « column
--      "confirmations" of relation "hazards" does not exist ». PostgREST répond 400, l'app y
--      voit un refus, et jette le geste. Six jours sans un seul événement enregistré.
--
-- Ce fichier remet la **dernière** version de chaque objet que 0030 a écrasé, et retire ce
-- qu'il a fait renaître. Il ne fait rien d'autre : les règles sont celles de 0200, mot pour
-- mot. Il est le premier à être appliqué par `db/migrate.sh`, qui tient désormais un registre
-- (`schema_migrations`) : un fichier appliqué ne se rejoue plus, et le premier échec arrête
-- tout. Sur le VPS, la base d'avant le registre est réputée à 0210 ; seul ce fichier est joué.
--
-- Il reste écrit pour passer deux fois sans dommage : c'est ce que vérifie run-tests.sh, qui
-- rejoue 0030 exprès sur une base migrée, efface le registre, et attend de 0220 qu'il répare.

---------------------------------------------------------------------------
-- 1. Ce que le rejeu a fait renaître disparaît
---------------------------------------------------------------------------
-- L'écriture du journal avec des coordonnées de terminal (avant 0100) ; le seuil sur un
-- compte plutôt qu'un poids (avant 0200) ; la définition de référence du palier dans l'API,
-- qui recevait une position en clair (retirée par 0110, AUDIT I3).
DROP FUNCTION IF EXISTS record_event(uuid, uuid, uuid, event_type, double precision,
                                     double precision, jsonb);
DROP FUNCTION IF EXISTS resolve_threshold(int, int, int, int);
DROP FUNCTION IF EXISTS proximity_tier(geometry, double precision, double precision);

---------------------------------------------------------------------------
-- 2. Le poids d'un palier se lit dans la table (0100, puis 0200)
---------------------------------------------------------------------------
-- DROP puis CREATE, et non CREATE OR REPLACE : c'est précisément le nom du paramètre qui a
-- fait échouer 0200.
DROP FUNCTION IF EXISTS proximity_weight(smallint);
CREATE FUNCTION proximity_weight(p_tier smallint)
RETURNS real
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  -- Un palier inconnu vaut le moins : celui du dernier palier, quel qu'il soit.
  SELECT coalesce(
    (SELECT t.weight FROM proximity_tiers t WHERE t.tier = p_tier),
    (SELECT t.weight FROM proximity_tiers t ORDER BY t.tier DESC LIMIT 1),
    (1.0::real / 3));
$$;
REVOKE ALL ON FUNCTION proximity_weight(smallint) FROM PUBLIC;

---------------------------------------------------------------------------
-- 3. Le seuil prend un poids (0200)
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_threshold(
  confirm_weight                 real,
  min_resolve_votes              int,
  confirmations_per_resolve_vote int DEFAULT 3,
  max_resolve_votes              int DEFAULT 5
) RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT greatest(
           min_resolve_votes,
           least(
             max_resolve_votes,
             ceil(confirm_weight::numeric / greatest(confirmations_per_resolve_vote, 1))::int
           )
         );
$$;

---------------------------------------------------------------------------
-- 4. Le recalcul depuis le journal (0200)
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION recompute_hazard(p_hazard uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_min_votes      int;
  v_per_vote       int;
  v_max_votes      int;
  v_report_weight  int;
  v_current        hazard_status;
  v_remove_id      bigint;
  v_restore_id     bigint;
  v_confirm_weight real;
  v_last_seen      timestamptz;
  v_reset_id       bigint;
  v_resolve        real;
  v_flags          int;
  v_threshold      int;
  v_status         hazard_status;
BEGIN
  SELECT h.status INTO v_current FROM hazards h WHERE h.id = p_hazard;

  SELECT s.min_resolve_votes, s.confirmations_per_resolve_vote, s.max_resolve_votes,
         s.report_confirmations
    INTO v_min_votes, v_per_vote, v_max_votes, v_report_weight
    FROM moderation_settings s WHERE s.id = 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT
    max(e.id) FILTER (WHERE e.type = 'remove'),
    max(e.id) FILTER (WHERE e.type = 'restore'),
    coalesce(sum(e.weight * CASE e.type WHEN 'create' THEN v_report_weight ELSE 1 END)
               FILTER (WHERE e.type IN ('create', 'confirm')), 0)::real,
    max(e.created_at) FILTER (WHERE e.type IN ('create', 'confirm')),
    max(e.id) FILTER (WHERE e.type IN ('create', 'confirm')),
    count(*)  FILTER (WHERE e.type = 'flag')
  INTO v_remove_id, v_restore_id, v_confirm_weight, v_last_seen, v_reset_id, v_flags
  FROM events e
  WHERE e.hazard_id = p_hazard
    AND e.cancelled_at IS NULL;

  SELECT coalesce(sum(e.weight), 0)::real
    INTO v_resolve
    FROM events e
   WHERE e.hazard_id = p_hazard
     AND e.cancelled_at IS NULL
     AND e.type = 'mark_resolved'
     AND (v_reset_id IS NULL OR e.id > v_reset_id);

  v_threshold := resolve_threshold(v_confirm_weight, v_min_votes, v_per_vote, v_max_votes);

  IF v_remove_id IS NOT NULL AND (v_restore_id IS NULL OR v_restore_id < v_remove_id) THEN
    v_status := 'removed';
  ELSIF v_current = 'archived' THEN
    v_status := 'archived';
  ELSIF v_resolve >= v_threshold THEN
    v_status := 'resolved';
  ELSIF v_resolve >= 1 THEN
    v_status := 'disputed';
  ELSE
    v_status := 'active';
  END IF;

  UPDATE hazards h
     SET confirm_weight    = v_confirm_weight,
         last_confirmed_at = coalesce(v_last_seen, h.last_confirmed_at),
         resolve_weight    = v_resolve,
         flags             = v_flags,
         status            = v_status
   WHERE h.id = p_hazard;
END
$$;
REVOKE ALL ON FUNCTION recompute_hazard(uuid) FROM PUBLIC;

---------------------------------------------------------------------------
-- 5. L'écriture du journal accepte encore le palier 3 des anciennes apps (0200)
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION record_event(
  p_client_id uuid,
  p_hazard_id uuid,
  p_device_id uuid,
  p_type      event_type,
  p_proximity smallint DEFAULT 3,
  p_payload   jsonb DEFAULT NULL
) RETURNS smallint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_tier smallint := coalesce(p_proximity, 3::smallint);
BEGIN
  IF v_tier NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'palier de proximité hors bornes : %' , v_tier USING ERRCODE = 'check_violation';
  END IF;
  v_tier := least(v_tier, 2::smallint);

  INSERT INTO events (client_id, hazard_id, device_id, type, proximity, weight, payload)
  VALUES (p_client_id, p_hazard_id, p_device_id, p_type, v_tier, proximity_weight(v_tier), p_payload)
  ON CONFLICT DO NOTHING;

  RETURN v_tier;
END
$$;
REVOKE ALL ON FUNCTION record_event(uuid, uuid, uuid, event_type, smallint, jsonb) FROM PUBLIC;

---------------------------------------------------------------------------
-- 6. Tout se recalcule depuis le journal, et on vérifie avant de conclure
---------------------------------------------------------------------------
-- Rien n'a été écrit dans `events` pendant la panne, le recalcul ne change donc rien sur le
-- VPS ; il garantit simplement que les compteurs suivent la fonction remise en place.
DO $$
BEGIN
  PERFORM recompute_hazard(h.id) FROM hazards h;
END
$$;

-- Le garde-fou qui manquait le 21/09 : si l'état n'est pas celui attendu, la migration échoue
-- et le déploiement s'arrête là, au lieu de dire « migrations appliquées ».
DO $$
BEGIN
  IF position('SET confirmations ' IN pg_get_functiondef('recompute_hazard(uuid)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'recompute_hazard écrit encore hazards.confirmations';
  END IF;
  IF proximity_weight(2::smallint) IS DISTINCT FROM (SELECT weight FROM proximity_tiers WHERE tier = 2) THEN
    RAISE EXCEPTION 'proximity_weight ne lit pas proximity_tiers';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname IN ('record_event', 'resolve_threshold', 'proximity_tier')
              GROUP BY p.proname HAVING count(*) > 1
             UNION ALL
             SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'proximity_tier') THEN
    RAISE EXCEPTION 'des surcharges d''avant 0100/0110/0200 sont encore là';
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
