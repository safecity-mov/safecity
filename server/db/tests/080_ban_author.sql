-- L'application — bannir l'auteur d'un danger (§4.3).
--
-- Ce qui compte ici tient en deux phrases : le geste marche, et il ne rend jamais
-- l'identifiant du terminal.

BEGIN;
SELECT no_plan();

INSERT INTO admins (user_id, email) VALUES
  ('dddddddd-0000-0000-0000-00000000000d', 'moderation@example.org');

INSERT INTO devices (id) VALUES
  ('eeeeeeee-0000-0000-0000-00000000000e'),
  ('ffffffff-0000-0000-0000-00000000000f');

CREATE TEMP TABLE cibles AS
SELECT (report_hazard(gen_random_uuid(), 'eeeeeeee-0000-0000-0000-00000000000e'::uuid,
                      'pothole', 48.8100, 2.3100, 3::smallint) ->> 'id')::uuid AS vandale,
       (report_hazard(gen_random_uuid(), 'ffffffff-0000-0000-0000-00000000000f'::uuid,
                      'pothole', 48.8600, 2.3600, 2::smallint) ->> 'id')::uuid AS ancien;

SELECT set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-00000000000d"}', true);

-- --- Le retour ne dit rien de l'auteur ---------------------------------------------------
CREATE TEMP TABLE retour AS
SELECT admin_ban_hazard_author((SELECT vandale FROM cibles), 'signalement inventé') AS r;

SELECT is((SELECT count(*)::int FROM jsonb_object_keys((SELECT r FROM retour)) k
           WHERE k IN ('device_id', 'created_by')),
          0,
          'le retour ne porte aucun identifiant de terminal : c''est tout l''intérêt du détour');

SELECT is((SELECT (r ->> 'events_cancelled')::int FROM retour), 1,
          'le geste du vandale est annulé');
SELECT is((SELECT (r ->> 'hazards_removed')::int FROM retour), 1,
          'et son signalement retiré');

SELECT isnt((SELECT d.banned_at FROM devices d WHERE d.id = 'eeeeeeee-0000-0000-0000-00000000000e'),
            NULL,
            'le terminal est bien banni, sans que la console ait eu à le nommer');

-- --- Deux fois, non ------------------------------------------------------------------------
SELECT throws_ok(
  format('SELECT admin_ban_hazard_author(%L, %L)', (SELECT vandale FROM cibles), 'encore'),
  '23505',
  NULL,
  'bannir deux fois est refusé, plutôt que de rendre des compteurs à zéro'
);

-- --- Passé la fenêtre de 24 h, il n'y a plus d'auteur --------------------------------------
UPDATE hazards SET created_at = now() - interval '25 hours' WHERE id = (SELECT ancien FROM cibles);
UPDATE events  SET created_at = now() - interval '25 hours'
 WHERE hazard_id = (SELECT ancien FROM cibles);
SELECT anonymize_old_events();

SELECT throws_ok(
  format('SELECT admin_ban_hazard_author(%L, %L)', (SELECT ancien FROM cibles), 'trop tard'),
  -- `no_data_found` levé depuis PL/pgSQL sort en P0002, pas en 02000. PostgREST le rend en 404.
  'P0002',
  NULL,
  'passé 24 h le lien est coupé : le bannissement devient impossible, et le dit'
);

-- --- Et le motif reste obligatoire ---------------------------------------------------------
SELECT throws_ok(
  format('SELECT admin_ban_hazard_author(%L, %L)', (SELECT vandale FROM cibles), ' '),
  '23505',
  NULL,
  'un déjà-banni est refusé avant même le motif'
);

SELECT * FROM finish();
ROLLBACK;
