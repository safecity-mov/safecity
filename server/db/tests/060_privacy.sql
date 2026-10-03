-- L'application — §11 minimisation. Ces tests vérifient surtout ce que le système NE fait PAS.
BEGIN;
SELECT no_plan();

CREATE TEMP TABLE h (label text PRIMARY KEY, id uuid);
CREATE TEMP TABLE d (label text PRIMARY KEY, id uuid DEFAULT gen_random_uuid());
INSERT INTO d (label) VALUES ('a'), ('b');

-- --- §11.1 : la position du déclarant n'a nulle part où être écrite -------------------
SELECT hasnt_column('events', 'device_pos', 'events n''a pas de colonne de position du déclarant');
SELECT hasnt_column('events', 'device_lat', 'ni de latitude');
SELECT hasnt_column('events', 'device_lng', 'ni de longitude');
SELECT hasnt_column('events', 'distance_m', 'ni de distance exacte au danger');
SELECT is(
  (SELECT count(*) FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'events' AND c.udt_name = 'geometry'),
  0::bigint, 'aucune géométrie dans le journal d''événements (§6.2)');

-- Le palier est la seule trace de la position du déclarant — et depuis que l'app le calcule
-- elle-même, le RPC n'a même plus de quoi la reconstituer (§11.1).
INSERT INTO h VALUES ('t', NULL);
UPDATE h SET id = (report_hazard(gen_random_uuid(), (SELECT id FROM d WHERE label='a'), 'pothole',
                                 48.8566, 2.3522, 2::smallint, NULL, 1::smallint) ->> 'id')::uuid
 WHERE label = 't';

SELECT is((SELECT e.proximity FROM events e WHERE e.hazard_id = (SELECT id FROM h WHERE label='t')),
          1::smallint, 'un signalement fait sur place enregistre le palier 1, et rien de plus');

-- Signalement sans position : palier 3, badge « signalé à distance » (§6.2).
SELECT is(
  (report_hazard(gen_random_uuid(), (SELECT id FROM d WHERE label='b'), 'pothole',
                 48.8700, 2.3700, 2::smallint) ->> 'reported_remotely')::boolean,
  true, 'un signalement sans position porte le badge « signalé à distance »');

-- --- §11.6 : pleine précision, aucun arrondi -----------------------------------------
CREATE TEMP TABLE precis AS
SELECT (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole',
                      48.95661234567, 2.35223456789, 1::smallint) ->> 'id')::uuid AS id;
SELECT is((SELECT ST_Y(geom) FROM hazards WHERE id = (SELECT id FROM precis)),
          48.95661234567::double precision, 'la latitude traverse le RPC sans perte');
SELECT is((SELECT ST_X(geom) FROM hazards WHERE id = (SELECT id FROM precis)),
          2.35223456789::double precision, 'la longitude aussi');
SELECT is((hazard_json((SELECT id FROM precis)) ->> 'lat')::double precision,
          48.95661234567::double precision, 'et elle ressort intacte du rendu JSON');

-- --- §11.2 : coupure du lien device → actions à 24 heures -----------------------------
SELECT is((SELECT count(*) FROM events e WHERE e.device_id IS NOT NULL), 3::bigint,
          'les événements récents portent encore leur device');

-- La borne compte autant que la coupure : le retrait par le créateur dure 24 h (§6.1),
-- et il lui faut le lien pendant toute cette durée.
UPDATE events SET created_at = now() - interval '23 hours';
UPDATE hazards SET created_at = now() - interval '23 hours';
SELECT lives_ok('SELECT anonymize_old_events()', 'l''anonymisation tourne');
SELECT is((SELECT count(*) FROM events e WHERE e.device_id IS NOT NULL), 3::bigint,
          'à 23 heures le lien tient encore : le retrait par le créateur en dépend');

UPDATE events SET created_at = now() - interval '25 hours';
UPDATE hazards SET created_at = now() - interval '25 hours';
SELECT lives_ok('SELECT anonymize_old_events()', 'l''anonymisation tourne à nouveau');

SELECT is((SELECT count(*) FROM events e WHERE e.device_id IS NOT NULL), 0::bigint,
          'au-delà de 24 heures, plus aucun événement n''est relié à un device (§11.2)');
SELECT is((SELECT count(*) FROM hazards WHERE created_by IS NOT NULL), 0::bigint,
          'ni aucun danger à son créateur : le lien est le même');
SELECT is((SELECT count(*) FROM events), 3::bigint,
          'les événements eux-mêmes sont conservés, horodatage compris (§11.2)');
SELECT is((SELECT count(*) FROM hazards), 3::bigint,
          'et les dangers restent : ce sont des données sur la voirie');

-- --- §11.4 : « Effacer mes données » -------------------------------------------------
CREATE TEMP TABLE h2 AS
SELECT app_test.report((SELECT id FROM d WHERE label='a'), 48.8800, 2.3800) AS id;
SELECT is((SELECT count(*) FROM devices WHERE id = (SELECT id FROM d WHERE label='a')), 1::bigint,
          'le device existe en base');

SELECT lives_ok(
  format($$ SELECT forget_device(%L::uuid) $$, (SELECT id FROM d WHERE label='a')),
  '« Effacer mes données » passe');
SELECT is((SELECT count(*) FROM devices WHERE id = (SELECT id FROM d WHERE label='a')), 0::bigint,
          'le device disparaît');
SELECT is((SELECT count(*) FROM hazards WHERE id = (SELECT id FROM h2)), 1::bigint,
          'mais pas ses signalements (§11.4)');
SELECT ok((SELECT created_by FROM hazards WHERE id = (SELECT id FROM h2)) IS NULL,
          'qui ne lui sont simplement plus reliés');

-- --- RLS : ce que voit le rôle public ------------------------------------------------
CREATE TEMP TABLE vis AS SELECT app_test.report(gen_random_uuid(), 48.8900, 2.3900) AS id;

SELECT is(app_test.anon_sees((SELECT id FROM vis)), 1::bigint,
          'anon voit un danger actif');
UPDATE hazards SET status = 'removed' WHERE id = (SELECT id FROM vis);
SELECT is(app_test.anon_sees((SELECT id FROM vis)), 0::bigint,
          'anon ne voit plus un danger retiré (§4.2)');
UPDATE hazards SET status = 'archived' WHERE id = (SELECT id FROM vis);
SELECT is(app_test.anon_sees((SELECT id FROM vis)), 0::bigint,
          'ni un danger archivé');

SELECT throws_ok($$ SELECT app_test.anon_reads_events() $$, '42501', NULL,
                 'anon n''a aucun accès direct au journal d''événements');
SELECT throws_ok($$ SELECT app_test.anon_reads_devices() $$, '42501', NULL,
                 'ni à la table des devices');
SELECT throws_ok($$ SELECT app_test.anon_reads_created_by() $$, '42501', NULL,
                 'ni à la colonne qui relie un danger à son créateur');
SELECT throws_ok($$ SELECT app_test.anon_calls_hazard_json(gen_random_uuid()) $$, '42501', NULL,
                 'ni au rendu brut, qui contournerait la policy');

-- Les droits, vus depuis le catalogue : ce qu'anon peut appeler, et rien d'autre.
SELECT ok(has_function_privilege('anon', 'report_hazard(uuid,uuid,text,double precision,double precision,smallint,text,smallint)', 'EXECUTE'),
          'anon peut signaler');
SELECT ok(has_function_privilege('anon', 'confirm_hazard(uuid,uuid,uuid,smallint)', 'EXECUTE'),
          'anon peut confirmer');
SELECT ok(has_function_privilege('anon', 'mark_resolved(uuid,uuid,uuid,smallint)', 'EXECUTE'),
          'anon peut marquer résolu');
SELECT ok(NOT has_function_privilege('anon', 'recompute_hazard(uuid)', 'EXECUTE'),
          'mais pas recalculer les compteurs à la main');
SELECT ok(NOT has_function_privilege('anon', 'record_event(uuid,uuid,uuid,event_type,smallint,jsonb)', 'EXECUTE'),
          'ni écrire directement dans le journal');
SELECT ok(NOT has_function_privilege('anon', 'anonymize_old_events(interval)', 'EXECUTE'),
          'ni déclencher l''anonymisation');
SELECT ok(has_table_privilege('anon', 'moderation_settings', 'SELECT'),
          'anon lit les seuils du §6.1, comme les paliers de proximité : la règle est publique');
SELECT ok(NOT has_table_privilege('anon', 'moderation_settings', 'UPDATE'),
          'mais ne la règle pas');
SELECT ok(NOT has_table_privilege('anon', 'proximity_tiers', 'UPDATE'),
          'ni les paliers de proximité, qu''il lit pourtant aussi');
SELECT ok(NOT has_table_privilege('anon', 'hazards', 'INSERT'),
          'anon n''écrit jamais en direct dans hazards');
SELECT ok(NOT has_table_privilege('anon', 'events', 'SELECT'),
          'et ne lit jamais le journal');
SELECT ok(NOT has_column_privilege('anon', 'hazards', 'created_by', 'SELECT'),
          'la colonne created_by lui est fermée');
SELECT ok(has_table_privilege('anon', 'announcements_public', 'SELECT'),
          'anon lit les annonces en cours (0230) : c''est un message pour tout le monde');
SELECT ok(NOT has_table_privilege('anon', 'announcements', 'SELECT'),
          'mais pas la table, qui dit qui les a écrites');

-- La liste exacte, et pas seulement des échantillons : c'est l'oubli d'une fonction qui
-- avait laissé `proximity_tier()` — et 800 fonctions PostGIS — en RPC public (AUDIT I3, M10).
-- `st_x` et `st_y` : les seules fonctions PostGIS accordées, parce que `hazards_public` les
-- appelle et qu'une vue exécute ses fonctions avec les droits du lecteur.
SELECT is(app_test.callable_by('anon'),
          ARRAY['confirm_hazard', 'forget_device', 'hazard_detail', 'hazards_in_bbox',
                'mark_resolved', 'remove_own_hazard', 'remove_own_recent_hazards', 'report_hazard',
                'st_x', 'st_y'],
          'anon ne peut appeler que les huit RPC du §8 et deux accesseurs de coordonnées');
SELECT is(app_test.callable_by('admin_api'),
          ARRAY['admin_ban_device', 'admin_ban_hazard_author', 'admin_clear_hazard_description',
                'admin_clear_hazard_icon', 'admin_publish_announcement',
                'admin_set_hazard_icon', 'admin_set_hazard_removed', 'admin_suspect_devices',
                'admin_whoami', 'admin_withdraw_announcement', 'current_admin', 'st_x', 'st_y'],
          'et admin_api, que les fonctions d''administration et les mêmes accesseurs');
SELECT hasnt_function('public', 'proximity_tier',
                      'aucune fonction publique ne reçoit une coordonnée de terminal');

SELECT * FROM finish();
ROLLBACK;
