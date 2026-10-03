-- L'application — fonctions RPC exposées par PostgREST (SPEC §8).
-- « Le client déclare, le serveur décide. » Toute la logique du §6 vit ici.
--
-- Écart assumé avec l'esquisse du §8 : `device_id` est un paramètre explicite de chaque
-- écriture. L'esquisse le laisse implicite (session anonyme Supabase Auth), mais la bêta
-- n'a pas d'auth : l'app envoie l'UUID qu'elle garde en secure storage (§0).
-- `device_pos` est éclaté en `device_lat` / `device_lng`, consommés puis jetés (§11.1).

---------------------------------------------------------------------------
-- Rendu d'un danger
---------------------------------------------------------------------------
-- `created_by` n'est jamais exposé : il relierait publiquement un device à ses signalements.
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
    'confirmations',     h.confirmations,
    'resolve_weight',    h.resolve_weight,
    'resolve_threshold', resolve_threshold(h.confirmations, s.min_resolve_votes,
                                           s.confirmations_per_resolve_vote, s.max_resolve_votes),
    -- Badge « signalé à distance » (§6.2) : dérivé du palier de l'événement de création.
    'reported_remotely', EXISTS (
       SELECT 1 FROM events e
        WHERE e.hazard_id = h.id AND e.type = 'create' AND e.proximity = 3
    )
  )
  FROM hazards h
  CROSS JOIN moderation_settings s
  WHERE h.id = p_hazard AND s.id = 1;
$$;

---------------------------------------------------------------------------
-- POST /rpc/report_hazard
---------------------------------------------------------------------------
-- Retour : l'objet danger, ou { duplicate_of, distance_m, hazard } si un danger actif du
-- même type se trouve dans le rayon anti-doublon du type (§4.1 F2b).
CREATE OR REPLACE FUNCTION report_hazard(
  client_id   uuid,
  device_id   uuid,
  type        text,
  lat         double precision,
  lng         double precision,
  severity    smallint,
  description text DEFAULT NULL,
  device_lat  double precision DEFAULT NULL,
  device_lng  double precision DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_existing  uuid;
  v_geom      geometry(Point, 4326);
  v_radius    int;
  v_enabled   bool;
  v_dup       record;
  v_hazard    uuid;
BEGIN
  -- Rejeu d'une action hors-ligne : on renvoie l'état, jamais un doublon (§10).
  SELECT e.hazard_id INTO v_existing
    FROM events e WHERE e.client_id = report_hazard.client_id;
  IF FOUND THEN
    RETURN hazard_json(v_existing);
  END IF;

  SELECT ht.enabled, ht.dedup_radius_m INTO v_enabled, v_radius
    FROM hazard_types ht WHERE ht.code = report_hazard.type;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'type de danger inconnu : %', report_hazard.type USING ERRCODE = 'foreign_key_violation';
  END IF;
  -- `enabled` pilote la création, jamais l'affichage (§4.3).
  IF NOT v_enabled THEN
    RAISE EXCEPTION 'type de danger désactivé : %', report_hazard.type USING ERRCODE = 'check_violation';
  END IF;

  IF report_hazard.severity NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'gravité hors bornes : %', report_hazard.severity USING ERRCODE = 'check_violation';
  END IF;
  IF char_length(coalesce(report_hazard.description, '')) > 140 THEN
    RAISE EXCEPTION 'commentaire limité à 140 caractères' USING ERRCODE = 'check_violation';
  END IF;

  v_geom := ST_SetSRID(ST_MakePoint(report_hazard.lng, report_hazard.lat), 4326);

  -- Anti-doublon : même type, danger encore visible, dans le rayon du type.
  SELECT h.id,
         round(ST_Distance(h.geom::geography, v_geom::geography)::numeric, 1) AS distance_m
    INTO v_dup
    FROM hazards h
   WHERE h.type = report_hazard.type
     AND h.status IN ('active', 'disputed')
     AND ST_DWithin(h.geom::geography, v_geom::geography, v_radius)
   ORDER BY h.geom <-> v_geom
   LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'duplicate_of', v_dup.id,
      'distance_m',   v_dup.distance_m,
      'hazard',       hazard_json(v_dup.id)
    );
  END IF;

  PERFORM assert_not_banned(report_hazard.device_id);
  PERFORM ensure_device(report_hazard.device_id);

  INSERT INTO hazards (type, geom, severity, description, created_by)
  VALUES (report_hazard.type, v_geom, report_hazard.severity,
          nullif(report_hazard.description, ''), report_hazard.device_id)
  RETURNING hazards.id INTO v_hazard;

  PERFORM record_event(report_hazard.client_id, v_hazard, report_hazard.device_id, 'create',
                       report_hazard.device_lat, report_hazard.device_lng);

  RETURN hazard_json(v_hazard);
END
$$;

---------------------------------------------------------------------------
-- POST /rpc/confirm_hazard — « Toujours là » (§4.1 F3)
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION confirm_hazard(
  client_id  uuid,
  id         uuid,
  device_id  uuid,
  device_lat double precision DEFAULT NULL,
  device_lng double precision DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_status hazard_status;
BEGIN
  -- Sérialise les votes concurrents : le quorum du §6.1 se lit sur un journal stable.
  SELECT h.status INTO v_status FROM hazards h WHERE h.id = confirm_hazard.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger % introuvable', confirm_hazard.id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_status IN ('removed', 'archived') THEN
    RAISE EXCEPTION 'danger % non confirmable (statut %)', confirm_hazard.id, v_status
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM assert_not_banned(confirm_hazard.device_id);
  PERFORM ensure_device(confirm_hazard.device_id);
  -- Un « confirmer » pendant `disputed` ramène à `active` et annule le poids « résolu » :
  -- c'est recompute_hazard() qui l'applique, en ne comptant que les votes postérieurs (§6.1).
  PERFORM record_event(confirm_hazard.client_id, confirm_hazard.id, confirm_hazard.device_id,
                       'confirm', confirm_hazard.device_lat, confirm_hazard.device_lng);

  RETURN hazard_json(confirm_hazard.id);
END
$$;

---------------------------------------------------------------------------
-- POST /rpc/mark_resolved — la « suppression » collaborative (§6.1)
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mark_resolved(
  client_id  uuid,
  id         uuid,
  device_id  uuid,
  device_lat double precision DEFAULT NULL,
  device_lng double precision DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_status hazard_status;
BEGIN
  SELECT h.status INTO v_status FROM hazards h WHERE h.id = mark_resolved.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger % introuvable', mark_resolved.id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_status IN ('removed', 'archived') THEN
    RAISE EXCEPTION 'danger % déjà retiré (statut %)', mark_resolved.id, v_status
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM assert_not_banned(mark_resolved.device_id);
  PERFORM ensure_device(mark_resolved.device_id);
  PERFORM record_event(mark_resolved.client_id, mark_resolved.id, mark_resolved.device_id,
                       'mark_resolved', mark_resolved.device_lat, mark_resolved.device_lng);

  RETURN hazard_json(mark_resolved.id);
END
$$;

---------------------------------------------------------------------------
-- POST /rpc/remove_own_hazard — correction d'erreur par le créateur (§6.1)
---------------------------------------------------------------------------
-- Le seul chemin vers `removed` côté utilisateur, et il se ferme au bout de 24 h.
-- C'est lui qui justifie de garder le plancher des votes à 2 plutôt qu'à 1 (§0).
CREATE OR REPLACE FUNCTION remove_own_hazard(
  client_id uuid,
  id        uuid,
  device_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_created_by uuid;
  v_created_at timestamptz;
  v_status     hazard_status;
BEGIN
  SELECT h.created_by, h.created_at, h.status
    INTO v_created_by, v_created_at, v_status
    FROM hazards h WHERE h.id = remove_own_hazard.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger % introuvable', remove_own_hazard.id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_status = 'removed' THEN
    RETURN hazard_json(remove_own_hazard.id);
  END IF;
  IF v_created_by IS NULL OR v_created_by <> remove_own_hazard.device_id THEN
    RAISE EXCEPTION 'seul le créateur peut retirer son signalement' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_created_at < now() - interval '24 hours' THEN
    RAISE EXCEPTION 'délai de retrait de 24 h dépassé ; utilisez « % » à la place',
      (SELECT ht.resolved_label_fr FROM hazards h JOIN hazard_types ht ON ht.code = h.type
        WHERE h.id = remove_own_hazard.id)
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM assert_not_banned(remove_own_hazard.device_id);
  PERFORM record_event(remove_own_hazard.client_id, remove_own_hazard.id,
                       remove_own_hazard.device_id, 'remove');

  RETURN hazard_json(remove_own_hazard.id);
END
$$;

---------------------------------------------------------------------------
-- GET (RPC) /rpc/hazards_in_bbox — alimentation de la carte (§8)
---------------------------------------------------------------------------
-- GeoJSON FeatureCollection. Passer aux tuiles vectorielles ST_AsMVT au-delà de ~5 000 dangers.
-- Le nom d'un paramètre ne peut pas changer par CREATE OR REPLACE : on repart de zéro
-- pour que les migrations restent rejouables.
DROP FUNCTION IF EXISTS hazards_in_bbox(double precision, double precision, double precision,
                                        double precision, text[], smallint, boolean);

CREATE FUNCTION hazards_in_bbox(
  min_lon          double precision,
  min_lat          double precision,
  max_lon          double precision,
  max_lat          double precision,
  types            text[] DEFAULT NULL,
  -- Gravité *minimale* : le filtre de la carte sert à ne garder que les dangers
  -- au moins aussi graves que le niveau choisi, pas l'inverse (§4.1 F1).
  min_severity     smallint DEFAULT NULL,
  include_resolved boolean DEFAULT false
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(jsonb_agg(
      jsonb_build_object(
        'type', 'Feature',
        'id', f.id,
        'geometry', ST_AsGeoJSON(f.geom)::jsonb,
        'properties', hazard_json(f.id) - 'lat' - 'lng'
      )), '[]'::jsonb)
  )
  FROM (
    SELECT h.id, h.geom
      FROM hazards h
     WHERE h.geom && ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
       AND (
             h.status IN ('active', 'disputed')
          -- Calque « résolus récemment » : 30 jours après le vote qui a fait basculer (§6.1).
          OR (include_resolved AND h.status = 'resolved' AND EXISTS (
                SELECT 1 FROM events e
                 WHERE e.hazard_id = h.id AND e.type = 'mark_resolved'
                   AND e.created_at > now() - interval '30 days'))
           )
       AND (types IS NULL OR h.type = ANY (types))
       AND (min_severity IS NULL OR h.severity >= min_severity)
     LIMIT 5000
  ) f;
$$;

---------------------------------------------------------------------------
-- GET (RPC) /rpc/hazard_detail — écran de détail (§4.1 F5)
---------------------------------------------------------------------------
-- L'historique est exposé sans `device_id` : la chronologie d'un danger est publique,
-- le lien entre un device et ses actions ne l'est pas (§11).
CREATE OR REPLACE FUNCTION hazard_detail(id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT hazard_json(hazard_detail.id) || jsonb_build_object(
    'timeline', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'type', e.type, 'proximity', e.proximity, 'created_at', e.created_at)
               ORDER BY e.id)
        FROM events e WHERE e.hazard_id = hazard_detail.id
    ), '[]'::jsonb),
    'photos', coalesce((
      SELECT jsonb_agg(jsonb_build_object('object_key', p.object_key, 'created_at', p.created_at)
               ORDER BY p.created_at)
        FROM photos p WHERE p.hazard_id = hazard_detail.id
    ), '[]'::jsonb)
  )
  WHERE EXISTS (
    SELECT 1 FROM hazards h
     WHERE h.id = hazard_detail.id AND h.status NOT IN ('removed', 'archived')
  );
$$;
