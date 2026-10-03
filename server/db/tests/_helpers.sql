-- L'application — utilitaires de test. Créés hors transaction par run-tests.sh, puis supprimés.
-- Ne doivent jamais exister sur une base de production.
CREATE SCHEMA IF NOT EXISTS app_test;

-- Les fonctions naissent fermées depuis 0110 (S2). Ici on les rouvre, pour le schéma de test
-- seulement : les aides `SET role = anon` ne pourraient même pas être créées sans cela —
-- PostgreSQL valide le corps d'une fonction sous ses propres réglages, donc en tant qu'anon,
-- qui doit alors avoir le droit de l'exécuter.
GRANT USAGE ON SCHEMA app_test TO PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_test GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- Décalage en mètres vers le nord (1° de latitude ≈ 111 320 m).
CREATE OR REPLACE FUNCTION app_test.north(lat double precision, meters double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$ SELECT lat + meters / 111320.0; $$;

-- Définition de référence du palier de proximité (§6.2), **hors du schéma public** : elle
-- reçoit une coordonnée de terminal, ce qu'aucune fonction exposée par l'API ne doit faire
-- (§11.1). Elle lit `proximity_tiers`, la table que l'app lit aussi : les tests vérifient
-- ainsi que la règle publiée et la règle appliquée ne peuvent pas diverger.
CREATE OR REPLACE FUNCTION app_test.proximity_tier(
  hazard_geom geometry,
  device_lat  double precision,
  device_lng  double precision
) RETURNS smallint
LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    (SELECT min(t.tier) FROM proximity_tiers t
      WHERE t.max_distance_m IS NOT NULL
        AND device_lat IS NOT NULL AND device_lng IS NOT NULL
        AND ST_DWithin(
              hazard_geom::geography,
              ST_SetSRID(ST_MakePoint(device_lng, device_lat), 4326)::geography,
              t.max_distance_m)),
    (SELECT max(t.tier) FROM proximity_tiers t),
    2::smallint);
$$;

-- Les aides déclarent le palier, comme le fait l'app depuis que le calcul se fait sur
-- l'appareil (§11.1). La correspondance distance → palier est vérifiée à part, par
-- `app_test.proximity_tier()` ci-dessus.

-- Signalement fait sur place : palier 1, poids 1,0 — et il vaut `report_confirmations`
-- confirmations dans `confirm_weight` (§6.1 amendé, 0200).
-- Un terminal vu depuis moins de quinze minutes ne peut pas dire « résolu » (0190). Les aides
-- font naître leurs terminaux vieux d'un jour : les tests du §6 parlent de votes, pas de
-- carence. Celui qui veut un terminal neuf appelle `mark_resolved` directement (160).
CREATE OR REPLACE FUNCTION app_test.aged(p_device uuid)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO devices (id, created_at) VALUES (p_device, now() - interval '1 day')
  ON CONFLICT (id) DO NOTHING;
  SELECT p_device;
$$;

CREATE OR REPLACE FUNCTION app_test.report(
  p_device   uuid,
  p_lat      double precision,
  p_lng      double precision,
  p_severity smallint DEFAULT 2::smallint,
  p_type     text DEFAULT 'pothole'
) RETURNS uuid LANGUAGE sql AS $$
  SELECT (report_hazard(gen_random_uuid(), app_test.aged(p_device), p_type, p_lat, p_lng,
                        p_severity, NULL, 1::smallint) ->> 'id')::uuid;
$$;

CREATE OR REPLACE FUNCTION app_test.confirm_near(p_device uuid, p_hazard uuid)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT confirm_hazard(gen_random_uuid(), p_hazard, app_test.aged(p_device), 1::smallint);
$$;

CREATE OR REPLACE FUNCTION app_test.resolve_near(p_device uuid, p_hazard uuid)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT mark_resolved(gen_random_uuid(), p_hazard, app_test.aged(p_device), 1::smallint);
$$;

-- Gestes émis d'ailleurs : palier 2, poids 1/3 (§6.2 amendé, 0200).
CREATE OR REPLACE FUNCTION app_test.resolve_far(p_device uuid, p_hazard uuid)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT mark_resolved(gen_random_uuid(), p_hazard, app_test.aged(p_device), 2::smallint);
$$;

CREATE OR REPLACE FUNCTION app_test.confirm_far(p_device uuid, p_hazard uuid)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT confirm_hazard(gen_random_uuid(), p_hazard, app_test.aged(p_device), 2::smallint);
$$;

-- Le poids des gestes « présent », arrondi au centième : les poids sont des `real`, et 1/3
-- additionné trois fois ne se compare pas à l'égalité près.
CREATE OR REPLACE FUNCTION app_test.confirm_weight(p_hazard uuid)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT round(h.confirm_weight::numeric, 2) FROM hazards h WHERE h.id = p_hazard;
$$;

CREATE OR REPLACE FUNCTION app_test.status(p_hazard uuid)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT h.status::text FROM hazards h WHERE h.id = p_hazard;
$$;

CREATE OR REPLACE FUNCTION app_test.weight(p_hazard uuid)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT round(h.resolve_weight::numeric, 2) FROM hazards h WHERE h.id = p_hazard;
$$;

-- n devices distincts confirment le danger : sert à faire monter le seuil dynamique (§6.1).
CREATE OR REPLACE FUNCTION app_test.confirm_by(p_hazard uuid, n int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE i int;
BEGIN
  FOR i IN 1..n LOOP
    PERFORM app_test.confirm_near(gen_random_uuid(), p_hazard);
  END LOOP;
END
$$;

-- Exécution sous le rôle `anon` : l'attribut SET est restauré à la sortie de la fonction,
-- ce qui évite de basculer le rôle au milieu d'une session pgTAP.
CREATE OR REPLACE FUNCTION app_test.anon_sees(p_hazard uuid)
RETURNS bigint LANGUAGE sql STABLE SET role = anon AS $$
  SELECT count(h.id) FROM hazards h WHERE h.id = p_hazard;
$$;

CREATE OR REPLACE FUNCTION app_test.anon_sees_any()
RETURNS bigint LANGUAGE sql STABLE SET role = anon AS $$
  SELECT count(h.id) FROM hazards h;
$$;

CREATE OR REPLACE FUNCTION app_test.anon_reads_events()
RETURNS bigint LANGUAGE sql STABLE SET role = anon AS $$
  SELECT count(*) FROM events;
$$;

CREATE OR REPLACE FUNCTION app_test.anon_reads_devices()
RETURNS bigint LANGUAGE sql STABLE SET role = anon AS $$
  SELECT count(*) FROM devices;
$$;

CREATE OR REPLACE FUNCTION app_test.anon_reads_created_by()
RETURNS uuid LANGUAGE sql STABLE SET role = anon AS $$
  SELECT h.created_by FROM hazards h LIMIT 1;
$$;

-- Les annonces (0230) : la vue publique, et la table qu'anon ne doit pas pouvoir lire.
CREATE OR REPLACE FUNCTION app_test.anon_reads_announcements()
RETURNS bigint LANGUAGE sql STABLE SET role = anon AS $$
  SELECT count(*) FROM announcements_public;
$$;

CREATE OR REPLACE FUNCTION app_test.anon_reads_announcements_table()
RETURNS bigint LANGUAGE sql STABLE SET role = anon AS $$
  SELECT count(*) FROM announcements;
$$;

CREATE OR REPLACE FUNCTION app_test.anon_calls_hazard_json(p_hazard uuid)
RETURNS jsonb LANGUAGE sql STABLE SET role = anon AS $$
  SELECT hazard_json(p_hazard);
$$;

-- Et sous le rôle `admin_api`, pour vérifier ce que voit un jeton d'administration.
CREATE OR REPLACE FUNCTION app_test.admin_api_reads_hazards()
RETURNS bigint LANGUAGE sql STABLE SET role = admin_api AS $$
  SELECT count(*) FROM hazards;
$$;

CREATE OR REPLACE FUNCTION app_test.admin_api_reads_events()
RETURNS bigint LANGUAGE sql STABLE SET role = admin_api AS $$
  SELECT count(*) FROM events;
$$;

CREATE OR REPLACE FUNCTION app_test.admin_api_reads_admin_hazards()
RETURNS bigint LANGUAGE sql STABLE SET role = admin_api AS $$
  SELECT count(*) FROM admin_hazards;
$$;

CREATE OR REPLACE FUNCTION app_test.admin_api_reads_audit()
RETURNS bigint LANGUAGE sql STABLE SET role = admin_api AS $$
  SELECT count(*) FROM admin_actions;
$$;

-- Ce qu'un rôle peut exécuter dans `public`, hors pgTAP (installé dans ce schéma pour les
-- tests, jamais en production).
CREATE OR REPLACE FUNCTION app_test.callable_by(p_role text)
RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT coalesce(array_agg(p.proname::text ORDER BY p.proname), '{}')
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND has_function_privilege(p_role, p.oid, 'EXECUTE')
     AND NOT EXISTS (
       SELECT 1 FROM pg_depend d
         JOIN pg_extension x ON x.oid = d.refobjid
        WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
          AND d.deptype = 'e' AND x.extname = 'pgtap');
$$;
