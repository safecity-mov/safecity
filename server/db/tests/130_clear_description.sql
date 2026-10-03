-- L'application — effacer la précision d'un danger (§4.3 amendé, 0150).
BEGIN;
SELECT no_plan();

INSERT INTO admins (user_id, email) VALUES
  ('dddddddd-0000-0000-0000-00000000000d', 'moderation@example.org');

CREATE TEMP TABLE ids AS
SELECT (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 48.8566, 2.3522,
                      2::smallint, 'Encore ce c... de maire', 1::smallint) ->> 'id')::uuid AS insulte,
       (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 48.8600, 2.3600,
                      2::smallint, NULL, 1::smallint) ->> 'id')::uuid AS muet;

-- --- Sans administrateur, rien -----------------------------------------------------------
SELECT throws_ok(
  format('SELECT admin_clear_hazard_description(%L, %L)', (SELECT insulte FROM ids), 'insulte'),
  '42501', NULL, 'réservé aux administrateurs');

SELECT set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-00000000000d"}', true);

-- --- Le texte part, le danger reste --------------------------------------------------------
SELECT is((admin_clear_hazard_description((SELECT insulte FROM ids), 'insulte envers un élu') ->> 'cleared')::boolean,
          true, 'la précision est effacée');
SELECT is((SELECT h.description FROM hazards h WHERE h.id = (SELECT insulte FROM ids)), NULL,
          'plus de texte sur le danger');
SELECT is((SELECT h.status FROM hazards h WHERE h.id = (SELECT insulte FROM ids)), 'active',
          'le danger, lui, est toujours sur la carte');
SELECT is((SELECT count(*) FROM events e WHERE e.hazard_id = (SELECT insulte FROM ids)), 1::bigint,
          'aucun événement ajouté : ce n''est pas un geste collaboratif');

-- --- Le journal garde ce qui a été effacé ------------------------------------------------
SELECT is((SELECT a.snapshot ->> 'description_before' FROM admin_actions a
            WHERE a.action = 'hazard.description.clear' AND a.target = (SELECT insulte FROM ids)::text),
          'Encore ce c... de maire',
          'le texte effacé est dans le journal d''audit, avec le motif');

-- --- Les refus -----------------------------------------------------------------------------
SELECT throws_ok(
  format('SELECT admin_clear_hazard_description(%L, %L)', (SELECT muet FROM ids), 'rien'),
  'P0002', NULL, 'un danger sans précision : rien à effacer, et on le dit');
SELECT throws_ok(
  format('SELECT admin_clear_hazard_description(%L, %L)', (SELECT insulte FROM ids), 'encore'),
  'P0002', NULL, 'effacer deux fois est refusé');
SELECT throws_ok(
  format('SELECT admin_clear_hazard_description(%L, %L)', gen_random_uuid(), 'x'),
  'P0002', NULL, 'danger inconnu');

SELECT * FROM finish();
ROLLBACK;
