-- L'application — création d'un signalement : anti-doublon (§4.1 F2b), idempotence (§10),
-- catalogue (§3, §4.3).
BEGIN;
SELECT no_plan();

-- --- Création nominale --------------------------------------------------------------
SELECT is((SELECT count(*) FROM hazards), 0::bigint, 'la carte démarre vide (§4.4)');

CREATE TEMP TABLE h (label text PRIMARY KEY, id uuid);
INSERT INTO h VALUES ('first', app_test.report(gen_random_uuid(), 48.8566, 2.3522));

SELECT is((SELECT count(*) FROM hazards), 1::bigint, 'un danger est créé');
SELECT is((SELECT status::text FROM hazards), 'active', 'il naît actif');
SELECT is((SELECT round(confirm_weight::numeric, 2) FROM hazards), 3.00,
          'la création vaut trois confirmations sur place (§6.1 amendé)');
SELECT is((SELECT count(*) FROM events WHERE type = 'create'), 1::bigint,
          'et laisse un événement dans le journal');

-- §11.6 : la position est stockée telle quelle, sans arrondi ni bruit.
SELECT is((SELECT ST_Y(geom) FROM hazards), 48.8566::double precision,
          'la latitude est conservée à l''identique');
SELECT is((SELECT ST_X(geom) FROM hazards), 2.3522::double precision,
          'la longitude est conservée à l''identique');

-- --- Anti-doublon (§4.1 F2b) --------------------------------------------------------
CREATE TEMP TABLE dup AS
SELECT report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole',
                     app_test.north(48.8566, 8), 2.3522, 2::smallint) AS r;

SELECT is((SELECT (r ->> 'duplicate_of')::uuid FROM dup),
          (SELECT id FROM h WHERE label = 'first'),
          'à 8 m d''un danger actif du même type : on propose de confirmer, pas de créer');
SELECT ok((SELECT (r ->> 'distance_m')::numeric FROM dup) BETWEEN 7 AND 9,
          'la distance au doublon est renvoyée au client');
SELECT is((SELECT count(*) FROM hazards), 1::bigint, 'aucun doublon n''est créé');

-- 30 m : au-delà du rayon de 15 m, c'est un autre trou.
INSERT INTO h VALUES ('far', app_test.report(gen_random_uuid(), app_test.north(48.8566, 30), 2.3522));
SELECT isnt((SELECT id FROM h WHERE label = 'far'), NULL, 'à 30 m, un second danger est bien créé');
SELECT is((SELECT count(*) FROM hazards), 2::bigint, 'deux dangers distincts');

-- Le rayon ne vaut qu'à type égal.
UPDATE hazard_types SET enabled = true WHERE code = 'debris';
INSERT INTO h VALUES ('debris', app_test.report(gen_random_uuid(), 48.8566, 2.3522, 2::smallint, 'debris'));
SELECT isnt((SELECT id FROM h WHERE label = 'debris'), NULL,
            'un type différent au même endroit n''est pas un doublon');

-- --- Idempotence (§10) --------------------------------------------------------------
-- Rejeu du même client_id, comme le ferait workmanager après une reconnexion.
CREATE TEMP TABLE idem (client_id uuid, first_id uuid, second_id uuid);
INSERT INTO idem (client_id) VALUES (gen_random_uuid());
UPDATE idem SET first_id = (report_hazard(client_id, gen_random_uuid(), 'pothole',
                              app_test.north(48.8566, 500), 2.3522, 3::smallint) ->> 'id')::uuid;
UPDATE idem SET second_id = (report_hazard(client_id, gen_random_uuid(), 'pothole',
                              app_test.north(48.8566, 500), 2.3522, 3::smallint) ->> 'id')::uuid;

SELECT is((SELECT first_id FROM idem), (SELECT second_id FROM idem),
          'rejouer un client_id renvoie le même danger');
SELECT is((SELECT count(*) FROM events WHERE type = 'create'), 4::bigint,
          'et n''ajoute aucun événement');

-- --- Catalogue (§4.3) ---------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT app_test.report(gen_random_uuid(), 48.9, 2.4, 2::smallint, 'lighting') $$,
  '23514', NULL, 'un type désactivé refuse la création');

SELECT throws_ok(
  $$ SELECT app_test.report(gen_random_uuid(), 48.9, 2.4, 2::smallint, 'ufo') $$,
  '23503', NULL, 'un type inconnu est refusé');

SELECT throws_ok(
  $$ SELECT report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 48.9, 2.4, 7::smallint) $$,
  '23514', NULL, 'une gravité hors 1–3 est refusée');

SELECT throws_ok(
  $$ SELECT report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 48.91, 2.41, 2::smallint,
                          repeat('x', 141)) $$,
  '23514', NULL, 'un commentaire de plus de 140 caractères est refusé');

-- Ce qui n'est pas une position est refusé en français, avant PostGIS (AUDIT M1).
SELECT throws_ok(
  $$ SELECT report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 95, 2.4, 2::smallint) $$,
  '23514', NULL, 'une latitude hors bornes est refusée');
SELECT throws_ok(
  $$ SELECT report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', NULL, 2.4, 2::smallint) $$,
  '23514', NULL, 'une latitude absente aussi');
SELECT throws_ok(
  $$ SELECT report_hazard(NULL, gen_random_uuid(), 'pothole', 48.9, 2.4, 2::smallint) $$,
  '23514', NULL, 'et un geste sans identifiant');

-- Le rejeu concurrent d'un même `client_id` doit se sérialiser (AUDIT C6). pgTAP n'a qu'une
-- session : on vérifie au moins que les verrous sont là, dans l'ordre geste puis type.
SELECT ok(position('report_hazard:client:' IN (SELECT p.prosrc FROM pg_proc p WHERE p.proname = 'report_hazard'))
          < position('report_hazard:type:' IN (SELECT p.prosrc FROM pg_proc p WHERE p.proname = 'report_hazard')),
          'report_hazard prend un verrou par geste, puis un par type, toujours dans cet ordre');

-- `enabled` pilote la création, jamais l'affichage : un danger d'un type désactivé
-- après coup reste visible et confirmable (§4.3).
UPDATE hazard_types SET enabled = false WHERE code = 'debris';
SELECT lives_ok(
  format($$ SELECT app_test.confirm_near(gen_random_uuid(), %L::uuid) $$,
         (SELECT id FROM h WHERE label = 'debris')),
  'un danger d''un type désactivé reste confirmable');
SELECT is((SELECT round(confirm_weight::numeric, 2) FROM hazards WHERE id = (SELECT id FROM h WHERE label = 'debris')), 4.00,
          'et sa confirmation pèse : 3 pour le signalement, 1 pour elle');

SELECT * FROM finish();
ROLLBACK;
