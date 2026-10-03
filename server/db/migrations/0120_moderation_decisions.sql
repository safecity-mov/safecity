-- L'application — décisions du §6.1 tranchées après l'audit (AUDIT.md, D2 et D4).
--
--   D2      un signalement ne se confirme plus par son auteur. Tant que `created_by` existe,
--           c'est-à-dire pendant 24 heures : au-delà, `anonymize_old_events` a coupé le lien
--           et le serveur ne peut plus le savoir. Même durée de vie que la voix unique de
--           `events_one_per_device`, pour exactement la même raison (§11.2).
--   D4      un danger résolu quitte la carte. Le calque « résolus récemment » disparaît avec
--           son paramètre `include_resolved`, la vue publique et la policy suivent. La
--           console, elle, ne filtre aucun statut : les modérateurs continuent de tout voir.
--
-- Les seuils du §6.1, eux, ont quitté le code et le catalogue pour `moderation_settings`
-- (0010) : une table d'une seule ligne, les mêmes réglages pour tous les types, éditables
-- depuis la console et journalisés comme le catalogue (0070). Il ne reste ici que la
-- démolition, pour les bases qui portent encore les colonnes.
--
-- Rejouable, comme les autres : `make migrate` repasse tous les fichiers.

---------------------------------------------------------------------------
-- Le catalogue n'est plus le lieu des règles de modération
---------------------------------------------------------------------------
-- Il décrit un type de danger — libellé, icône, rayon anti-doublon, durée de vie — pas la
-- façon dont on modère. Les `CHECK` qui bornaient ces colonnes tombent avec elles ; ils sont
-- repris sur `moderation_settings` (AUDIT I4).
ALTER TABLE hazard_types
  DROP COLUMN IF EXISTS min_resolve_votes,
  DROP COLUMN IF EXISTS confirmations_per_resolve_vote,
  DROP COLUMN IF EXISTS max_resolve_votes;

---------------------------------------------------------------------------
-- D2 — un signalement ne se confirme pas par son auteur
---------------------------------------------------------------------------
-- Créer compte déjà pour une confirmation (`recompute_hazard` agrège `create` et `confirm`).
-- Un auteur qui appuyait ensuite sur « toujours là » en valait donc deux : l'écran annonçait
-- « confirmé 1 fois » sans que personne d'autre ne soit passé, et le seuil de résolution
-- montait d'un cran — un danger gonflé est plus *difficile* à faire disparaître.
--
-- Le contrôle ne peut être que serveur : l'app ignore quels dangers sont les siens, parce que
-- `created_by` n'est jamais exposé (§11). C'est déjà ainsi que fonctionne « retirer mon
-- signalement », dont le bouton s'affiche partout et dont le refus vient d'ici.
--
-- Passé 24 heures, `anonymize_old_events` a mis `created_by` à NULL et la règle s'éteint
-- d'elle-même. C'est assumé : la minimisation prime, et une confirmation isolée gagnée le
-- lendemain ne vaut pas de garder un lien terminal → signalement pour la contredire.
CREATE OR REPLACE FUNCTION confirm_hazard(
  client_id uuid,
  id        uuid,
  device_id uuid,
  proximity smallint DEFAULT 3
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_status hazard_status;
  v_author uuid;
BEGIN
  -- Sérialise les votes concurrents : le quorum du §6.1 se lit sur un journal stable.
  SELECT h.status, h.created_by INTO v_status, v_author
    FROM hazards h WHERE h.id = confirm_hazard.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger % introuvable', confirm_hazard.id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_status IN ('removed', 'archived') THEN
    RAISE EXCEPTION 'danger % non confirmable (statut %)', confirm_hazard.id, v_status
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_author IS NOT NULL AND v_author = confirm_hazard.device_id THEN
    RAISE EXCEPTION 'vous avez signalé ce danger : la confirmation vient des autres'
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM assert_not_banned(confirm_hazard.device_id);
  PERFORM ensure_device(confirm_hazard.device_id);
  -- Un « confirmer » pendant `disputed` ramène à `active` et annule le poids « résolu » :
  -- c'est recompute_hazard() qui l'applique, en ne comptant que les votes postérieurs (§6.1).
  PERFORM record_event(confirm_hazard.client_id, confirm_hazard.id, confirm_hazard.device_id,
                       'confirm', confirm_hazard.proximity);

  RETURN hazard_json(confirm_hazard.id);
END
$$;

---------------------------------------------------------------------------
-- D4 — un danger résolu quitte la carte
---------------------------------------------------------------------------
-- Il y avait deux définitions de « visible » : la carte montrait les résolus sur demande et
-- pendant 30 jours, la vue publique les servait tous, sans limite de date. Une seule
-- définition désormais, la plus stricte : actif ou contesté.
--
-- Ce n'est pas une perte pour le cycle de vie d'un danger. L'anti-doublon de `report_hazard`
-- ne regarde que les dangers actifs et contestés : un trou rebouché sort de la carte, et le
-- jour où il se rouvre, le signalement suivant crée un danger neuf, avec ses propres
-- confirmations. Ce que le calque « résolus récemment » permettait — ressusciter un danger
-- résolu d'un « toujours là » — n'a plus lieu d'être.
--
-- Les résolus restent lisibles dans la console (`admin_hazards` ne filtre aucun statut) et
-- dans le journal, qui ne perd jamais rien (§5).
DROP FUNCTION IF EXISTS hazards_in_bbox(double precision, double precision, double precision,
                                        double precision, text[], smallint, boolean);

CREATE OR REPLACE FUNCTION hazards_in_bbox(
  min_lon      double precision,
  min_lat      double precision,
  max_lon      double precision,
  max_lat      double precision,
  types        text[] DEFAULT NULL,
  -- Gravité *minimale* : le filtre de la carte sert à ne garder que les dangers
  -- au moins aussi graves que le niveau choisi, pas l'inverse (§4.1 F1).
  min_severity smallint DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH visible AS (
    SELECT h.id, h.geom
      FROM hazards h
     WHERE h.geom && ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
       AND h.status IN ('active', 'disputed')
       AND (types IS NULL OR h.type = ANY (types))
       AND (min_severity IS NULL OR h.severity >= min_severity)
     ORDER BY h.severity DESC, h.last_confirmed_at DESC, h.id
     LIMIT 5000
  )
  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    -- Vrai quand le plafond est atteint : la réponse ne décrit alors plus la zone entière,
    -- et le client ne doit ni la mémoriser comme complète ni en déduire une absence.
    'truncated', (SELECT count(*) FROM visible) >= 5000,
    'features', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'type', 'Feature',
          'id', f.id,
          'geometry', ST_AsGeoJSON(f.geom)::jsonb,
          'properties', hazard_json(f.id) - 'lat' - 'lng'
        ))
      FROM visible f), '[]'::jsonb)
  );
$$;

GRANT EXECUTE ON FUNCTION hazards_in_bbox(double precision, double precision, double precision,
                                          double precision, text[], smallint) TO anon;

-- La vue publique et la policy disaient « tout sauf retiré ou archivé » : elles disent
-- maintenant la même chose que la carte.
CREATE OR REPLACE VIEW hazards_public AS
  SELECT h.id, h.type, ST_Y(h.geom) AS lat, ST_X(h.geom) AS lng,
         h.severity, h.status, h.description, h.address,
         h.created_at, h.last_confirmed_at, h.confirmations, h.resolve_weight
    FROM hazards h
   WHERE h.status IN ('active', 'disputed');

DROP POLICY IF EXISTS hazards_read ON hazards;
CREATE POLICY hazards_read ON hazards FOR SELECT TO anon
  USING (status IN ('active', 'disputed'));

NOTIFY pgrst, 'reload schema';
