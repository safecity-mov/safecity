-- L'application — 0200 : deux paliers, confirmations pondérées, un signalement vaut N
-- confirmations (amendements §6.1 et §6.2).
--
-- Trois constats après les premières semaines de bêta :
--
-- 1. « Toujours là » et « résolu » sont les deux réponses à la même question, et une seule
--    était pesée. Un « toujours là » depuis le canapé comptait 1 plein dans `confirmations`,
--    qui fait monter le seuil de résolution ; un « résolu » depuis le même canapé pesait 0,25.
--    Il était plus facile d'ancrer un danger à distance que de le retirer à distance.
-- 2. Le palier intermédiaire (50–500 m) ne correspondait à rien de vécu : il avait été posé
--    avant d'avoir vu un seul trajet réel. Deux paliers, « sur place » et « ailleurs », et un
--    seul seuil, à 100 m.
-- 3. Placer le pin, choisir le type et la gravité est le geste lourd : un signalement vaut N
--    confirmations, N réglable dans la console comme les trois seuils du §6.1.
--
-- Ce que ça change dans les données :
--
-- - `hazards.confirmations` (un compte) devient `hazards.confirm_weight` (une somme de poids).
--   Le compte ne servait qu'au seuil et à l'affichage ; le seuil se calcule maintenant sur le
--   poids, et l'affichage a la chronologie du danger, qui montre chaque geste.
-- - Les événements portaient un palier sur trois valeurs, ils en portent un sur deux. Le code
--   3 (« au-delà ») devient 2 ; l'ancien palier 2 (50–500 m) devient « ailleurs » aussi, ce
--   qu'il serait sous la nouvelle règle. Les poids déjà écrits ne bougent pas : le §5 protège
--   les faits — quoi, quand, quel poids — pas le numéro d'un code. Les apps publiées avant
--   cette migration envoient encore 3 pour « loin » : `record_event` le ramène à 2.
--
-- Tout se recalcule depuis le journal en fin de fichier : les poids étaient déjà écrits sur
-- chaque `create` et `confirm`, rien n'est perdu et rien n'est inventé.
--
-- Rejouable, comme les autres : chaque étape vérifie l'état avant d'agir, et les paliers ne
-- sont réécrits qu'une fois — un réglage fait depuis la console ne doit pas être écrasé par
-- une réinstallation du serveur.

---------------------------------------------------------------------------
-- 1. Un signalement vaut N confirmations
---------------------------------------------------------------------------
ALTER TABLE moderation_settings
  ADD COLUMN IF NOT EXISTS report_confirmations int NOT NULL DEFAULT 3
    CHECK (report_confirmations BETWEEN 1 AND 10);

COMMENT ON COLUMN moderation_settings.report_confirmations IS
  'Ce que pèse un signalement dans le poids des confirmations, en confirmations sur place. À 3, '
  'un signalement sur place vaut une voix « résolu » (confirmations_per_resolve_vote), et un '
  'signalement à distance (3 × 1/3) vaut une confirmation sur place. Appliqué au recalcul, '
  'pas figé dans le journal : un réglage vaut pour tout l''historique, comme les seuils du §6.1.';

---------------------------------------------------------------------------
-- 2. Le compte de confirmations devient un poids
---------------------------------------------------------------------------
-- Les deux vues qui lisent la colonne bloqueraient son changement de type ; elles sont
-- recréées plus bas, avec le nouveau nom.
DROP VIEW IF EXISTS hazards_public;
DROP VIEW IF EXISTS admin_hazards;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'hazards'
                AND column_name = 'confirmations') THEN
    ALTER TABLE hazards RENAME COLUMN confirmations TO confirm_weight;
    ALTER TABLE hazards
      ALTER COLUMN confirm_weight TYPE real,
      ALTER COLUMN confirm_weight SET DEFAULT 0;
  END IF;
END
$$;

COMMENT ON COLUMN hazards.confirm_weight IS
  'Somme des poids des gestes « présent » (create × report_confirmations, confirm), non '
  'annulés. Dérivée du journal par recompute_hazard(). C''est sur elle que se calcule le seuil '
  'de résolution (§6.1).';

-- Le seuil prend un poids et non plus un compte. La règle ne change pas :
-- seuil = clamp(ceil(poids / N), plancher, plafond), et `ceil` s'occupe des fractions.
DROP FUNCTION IF EXISTS resolve_threshold(int, int, int, int);
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

-- Le recalcul. Repart de la version 0070 (celle qui ignore les gestes annulés) ; la seule
-- nouveauté est `v_confirm_weight`, et le seuil qui se lit dessus. Le retour à `active` après
-- un « confirmer » ne change pas : les votes « résolu » antérieurs au dernier geste « présent »
-- ne comptent plus, quel que soit le palier de ce geste. C'est noté comme question ouverte
-- dans la spec (§6.1) ; on ne la tranche pas ici.
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

---------------------------------------------------------------------------
-- 3. Deux paliers : « sur place » jusqu'à 100 m, « ailleurs » au-delà ou sans position
---------------------------------------------------------------------------
-- Le contrôle de cohérence dit maintenant : exactement deux paliers, le premier avec une
-- distance, le second sans, et le second pas plus lourd que le premier.
CREATE OR REPLACE FUNCTION proximity_tiers_coherent()
RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF (SELECT count(*) FROM proximity_tiers) <> 2
     OR NOT EXISTS (SELECT 1 FROM proximity_tiers WHERE tier = 1)
     OR NOT EXISTS (SELECT 1 FROM proximity_tiers WHERE tier = 2) THEN
    RAISE EXCEPTION 'deux paliers, ni plus ni moins : « sur place » (1) et « ailleurs » (2)'
      USING ERRCODE = 'check_violation';
  END IF;

  IF (SELECT max_distance_m FROM proximity_tiers WHERE tier = 1) IS NULL THEN
    RAISE EXCEPTION 'le premier palier porte une distance : c''est « sur place, jusqu''à »'
      USING ERRCODE = 'check_violation';
  END IF;

  IF (SELECT max_distance_m FROM proximity_tiers WHERE tier = 2) IS NOT NULL THEN
    RAISE EXCEPTION 'le second palier n''a pas de limite : c''est « ailleurs », ou pas de position du tout'
      USING ERRCODE = 'check_violation';
  END IF;

  IF (SELECT weight FROM proximity_tiers WHERE tier = 2)
     > (SELECT weight FROM proximity_tiers WHERE tier = 1) THEN
    RAISE EXCEPTION 'un vote émis de plus loin ne peut pas peser plus lourd'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NULL;
END
$$;

-- La bascule des données, une seule fois : tant que le palier 3 existe, on est dans l'ancien
-- monde. Le contrôle est suspendu le temps de l'écriture — il verrait passer un état à un ou
-- trois paliers — puis remis.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM proximity_tiers WHERE tier = 3) THEN
    ALTER TABLE proximity_tiers DISABLE TRIGGER proximity_tiers_coherent_trigger;
    DELETE FROM proximity_tiers WHERE tier = 3;
    -- 1/3 et non 0,33 : trois gestes à distance valent exactement un geste sur place, ce que
    -- 3 × 0,33 = 0,99 ne donnerait pas au seuil de 1 qui fait passer un danger en `disputed`.
    UPDATE proximity_tiers SET max_distance_m = 100,  weight = 1.0          WHERE tier = 1;
    UPDATE proximity_tiers SET max_distance_m = NULL, weight = 1.0::real / 3 WHERE tier = 2;
    ALTER TABLE proximity_tiers ENABLE TRIGGER proximity_tiers_coherent_trigger;
  END IF;
END
$$;

ALTER TABLE proximity_tiers DROP CONSTRAINT IF EXISTS proximity_tiers_tier_check;
ALTER TABLE proximity_tiers ADD CONSTRAINT proximity_tiers_tier_check CHECK (tier BETWEEN 1 AND 2);

COMMENT ON TABLE proximity_tiers IS
  'Les deux paliers du §6.2 : 1 « sur place », jusqu''à max_distance_m ; 2 « ailleurs, ou sans '
  'position », sans limite. Lue par l''app, qui calcule le palier sur l''appareil : la position '
  'du déclarant ne quitte jamais le téléphone (§11.1).';

-- Un palier inconnu vaut le moins : celui du dernier palier, quel qu'il soit.
CREATE OR REPLACE FUNCTION proximity_weight(p_tier smallint)
RETURNS real
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT coalesce(
    (SELECT t.weight FROM proximity_tiers t WHERE t.tier = p_tier),
    (SELECT t.weight FROM proximity_tiers t ORDER BY t.tier DESC LIMIT 1),
    (1.0::real / 3));
$$;

-- Le journal : le code 3 disparaît du vocabulaire.
UPDATE events SET proximity = 2 WHERE proximity = 3;
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_proximity_check;
ALTER TABLE events ADD CONSTRAINT events_proximity_check CHECK (proximity BETWEEN 1 AND 2);

-- L'écriture accepte encore 3 : c'est ce qu'envoient les apps publiées avant cette migration
-- pour « loin », et c'est le palier 2 d'aujourd'hui. Le défaut reste 3 pour la même raison ;
-- il vaut « ailleurs ». Ce qui n'est pas un palier est toujours refusé.
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

---------------------------------------------------------------------------
-- 4. Ce que voient l'app et la console
---------------------------------------------------------------------------
-- Repart de la version 0110 (M7). `confirmations` reste dans le JSON, arrondi à l'entier, le
-- temps que les apps antérieures à cette migration — qui le lisent comme un entier —
-- soient remplacées : à retirer avec la prochaine version exigée (RELEASE_REQUIRE).
CREATE OR REPLACE FUNCTION hazard_json(p_hazard uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'id',                h.id,
    'type',              h.type,
    'lat',               ST_Y(h.geom),          -- pleine précision, aucun arrondi (§11.6)
    'lng',               ST_X(h.geom),
    'severity',          h.severity,
    'status',            h.status,
    'description',       h.description,
    'address',           h.address,
    'created_at',        h.created_at,
    'last_confirmed_at', h.last_confirmed_at,
    'confirm_weight',    h.confirm_weight,
    'confirmations',     round(h.confirm_weight)::int,   -- compatibilité, voir ci-dessus
    'resolve_weight',    h.resolve_weight,
    'resolve_threshold', resolve_threshold(h.confirm_weight, s.min_resolve_votes,
                                           s.confirmations_per_resolve_vote, s.max_resolve_votes),
    -- Badge « signalé à distance » (§6.2) : dérivé du palier de l'événement de création.
    'reported_remotely', EXISTS (
       SELECT 1 FROM events e
        WHERE e.hazard_id = h.id AND e.type = 'create' AND e.proximity = 2
          AND e.cancelled_at IS NULL
    )
  )
  FROM hazards h
  CROSS JOIN moderation_settings s
  WHERE h.id = p_hazard AND s.id = 1;
$$;

-- Les vues, avec la colonne sous son nouveau nom (0120 et 0110).
CREATE VIEW hazards_public AS
  SELECT h.id, h.type, ST_Y(h.geom) AS lat, ST_X(h.geom) AS lng,
         h.severity, h.status, h.description, h.address,
         h.created_at, h.last_confirmed_at, h.confirm_weight, h.resolve_weight
    FROM hazards h
   WHERE h.status IN ('active', 'disputed');
GRANT SELECT ON hazards_public TO anon;

CREATE VIEW admin_hazards AS
  SELECT h.id, h.type, ST_Y(h.geom) AS lat, ST_X(h.geom) AS lng,
         h.severity, h.status, h.description, h.address, h.source,
         h.created_at, h.last_confirmed_at, h.confirm_weight, h.resolve_weight, h.flags,
         (SELECT count(*) FROM events e WHERE e.hazard_id = h.id) AS events_count
    FROM hazards h
   WHERE current_admin() IS NOT NULL;
GRANT SELECT ON admin_hazards TO admin_api;

---------------------------------------------------------------------------
-- 5. Tout se recalcule depuis le journal
---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM recompute_hazard(h.id) FROM hazards h;
END
$$;

NOTIFY pgrst, 'reload schema';
