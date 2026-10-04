-- L'application — déclarer son terminal au premier lancement (§6.3 amendé, 0250).
BEGIN;
SELECT no_plan();

CREATE TEMP TABLE h AS
SELECT app_test.report(gen_random_uuid(), 48.8566, 2.3522) AS id;
CREATE TEMP TABLE neuf AS SELECT gen_random_uuid() AS id;

-- --- La déclaration crée la ligne, et le compteur part de là ------------------------------
SELECT ok((declare_device((SELECT id FROM neuf)) ->> 'since')::timestamptz <= now(),
          'déclarer un terminal répond depuis quand il est connu');
SELECT is((SELECT count(*) FROM devices WHERE id = (SELECT id FROM neuf)), 1::bigint,
          'la ligne devices existe, sans aucun geste');
SELECT is((SELECT count(*) FROM events), 1::bigint,
          'et rien dans le journal : déclarer n''est pas un geste');

SELECT is(mark_resolved(gen_random_uuid(), (SELECT id FROM h), (SELECT id FROM neuf), 1::smallint) ->> 'message',
          'Ce téléphone vient d''arriver : marquer un danger résolu sera possible dans 15 min.',
          'déclaré à l''instant : le quart d''heure court déjà');
SELECT set_config('response.status', '', true);

-- --- Redéclarer ne remet pas le compteur à zéro ----------------------------------------------
UPDATE devices SET created_at = now() - interval '15 minutes' WHERE id = (SELECT id FROM neuf);
SELECT ok((declare_device((SELECT id FROM neuf)) ->> 'since')::timestamptz <= now() - interval '14 minutes',
          'redéclarer un terminal connu garde sa date');
SELECT is(mark_resolved(gen_random_uuid(), (SELECT id FROM h), (SELECT id FROM neuf), 1::smallint) ->> 'message',
          NULL, 'quinze minutes après l''ouverture de l''app, le vote passe sans autre geste avant');

-- --- Un terminal bloqué le reste ---------------------------------------------------------
INSERT INTO admins (user_id, email) VALUES ('dddddddd-0000-0000-0000-00000000000d', 'moderation@example.org');
SELECT set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-00000000000d"}', true);
SELECT lives_ok(format('SELECT admin_ban_device(%L, %L)', (SELECT id FROM neuf), 'test'), 'le terminal est bloqué');
SELECT set_config('request.jwt.claims', '', true);
SELECT lives_ok(format('SELECT declare_device(%L)', (SELECT id FROM neuf)), 'le redéclarer ne lève rien');
SELECT isnt((SELECT banned_at FROM devices WHERE id = (SELECT id FROM neuf)), NULL,
            'et ne lève pas le blocage');

-- --- Les refus et les droits --------------------------------------------------------------
SELECT throws_ok('SELECT declare_device(NULL)', '23514', NULL, 'sans identifiant, refus');
SELECT ok(has_function_privilege('anon', 'declare_device(uuid)', 'EXECUTE'),
          'l''app peut appeler declare_device');

SELECT * FROM finish();
ROLLBACK;
