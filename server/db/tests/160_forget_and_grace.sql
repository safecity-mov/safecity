-- L'application — la boucle « résolu, effacer, résolu » ne fait plus disparaître un danger (0190).
BEGIN;
SELECT no_plan();

CREATE TEMP TABLE d (label text PRIMARY KEY, id uuid DEFAULT gen_random_uuid());
INSERT INTO d (label) VALUES ('honnete'), ('tricheur'), ('tricheur2'), ('tricheur3');
CREATE OR REPLACE FUNCTION pg_temp.dev(p text) RETURNS uuid LANGUAGE sql AS
  $$ SELECT id FROM d WHERE label = p $$;

CREATE TEMP TABLE h AS
SELECT app_test.report(pg_temp.dev('honnete'), 48.8566, 2.3522) AS id;

-- --- Un terminal tout neuf attend, et on lui dit combien -----------------------------------
-- Un refus sans exception : la réponse porte le message et le statut 400 (lu par PostgREST
-- dans `response.status`), et la transaction est validée — la ligne `devices` reste.
CREATE TEMP TABLE neuf AS SELECT gen_random_uuid() AS id;
SELECT is(mark_resolved(gen_random_uuid(), (SELECT id FROM h), (SELECT id FROM neuf), 1::smallint) ->> 'message',
          'Ce téléphone vient d''arriver : marquer un danger résolu sera possible dans 15 min.',
          'un terminal vu à l''instant ne peut pas dire « résolu », et le message dit l''attente');
SELECT is(current_setting('response.status', true), '400', 'l''app reçoit un refus, pas un danger');
SELECT is((SELECT count(*) FROM events e WHERE e.hazard_id = (SELECT id FROM h) AND e.type = 'mark_resolved'),
          0::bigint, 'aucun vote enregistré');
SELECT is((SELECT count(*) FROM devices WHERE id = (SELECT id FROM neuf)), 1::bigint,
          'le terminal existe désormais : son quart d''heure court depuis ce premier contact');
SELECT set_config('response.status', '', true);
UPDATE devices SET created_at = now() - interval '14 minutes' WHERE id = (SELECT id FROM neuf);
SELECT is(mark_resolved(gen_random_uuid(), (SELECT id FROM h), (SELECT id FROM neuf), 1::smallint) ->> 'message',
          'Ce téléphone vient d''arriver : marquer un danger résolu sera possible dans 1 min.',
          'à quatorze minutes, il reste une minute');
SELECT set_config('response.status', '', true);
UPDATE devices SET created_at = now() - interval '15 minutes' WHERE id = (SELECT id FROM neuf);
SELECT is(mark_resolved(gen_random_uuid(), (SELECT id FROM h), (SELECT id FROM neuf), 1::smallint) ->> 'message',
          NULL, 'passé le quart d''heure, le vote passe');
SELECT is(coalesce(current_setting('response.status', true), ''), '', 'et la réponse est un danger, statut normal');
SELECT is(app_test.status((SELECT id FROM h)), 'disputed', 'une voix : contesté, pas résolu');

-- Créer et confirmer ne connaissent pas de carence.
CREATE TEMP TABLE neuf2 AS SELECT gen_random_uuid() AS id;
SELECT lives_ok(
  format('SELECT confirm_hazard(gen_random_uuid(), %L, %L, 1::smallint)', (SELECT id FROM h), (SELECT id FROM neuf2)),
  'confirmer reste libre dès le premier geste');
SELECT is(app_test.status((SELECT id FROM h)), 'active',
          'et une confirmation pendant la contestation ramène le danger à actif (§6.1)');

-- --- Effacer ses données retire ses votes ---------------------------------------------------
CREATE TEMP TABLE h2 AS SELECT app_test.report(pg_temp.dev('honnete'), 48.8600, 2.3600) AS id;
SELECT app_test.resolve_near(pg_temp.dev('tricheur'), (SELECT id FROM h2));
SELECT is(app_test.status((SELECT id FROM h2)), 'disputed', 'le tricheur conteste');

CREATE TEMP TABLE oubli AS SELECT forget_device(pg_temp.dev('tricheur')) AS r;
SELECT is((SELECT (r ->> 'votes_withdrawn')::int FROM oubli), 1, 'l''effacement retire son vote');
SELECT is(app_test.status((SELECT id FROM h2)), 'active', 'et le danger redevient actif : le vote ne compte plus');
SELECT is(app_test.weight((SELECT id FROM h2)), 0.00, 'poids de résolution revenu à zéro');

-- La boucle, trois tours : identifiant neuf (vieilli, comme le ferait un tricheur patient),
-- « résolu », effacer. Le danger ne bascule jamais.
SELECT app_test.resolve_near(pg_temp.dev('tricheur2'), (SELECT id FROM h2));
SELECT forget_device(pg_temp.dev('tricheur2'));
SELECT app_test.resolve_near(pg_temp.dev('tricheur3'), (SELECT id FROM h2));
SELECT is(app_test.status((SELECT id FROM h2)), 'disputed',
          'trois tours de boucle : toujours une seule voix qui compte, le danger reste');
SELECT is((SELECT count(*) FROM events e WHERE e.hazard_id = (SELECT id FROM h2) AND e.type = 'mark_resolved'),
          3::bigint, 'les trois votes sont dans le journal…');
SELECT is((SELECT count(*) FROM events e WHERE e.hazard_id = (SELECT id FROM h2) AND e.type = 'mark_resolved'
            AND e.cancelled_at IS NULL), 1::bigint, '… un seul compte encore');

-- --- Les créations restent --------------------------------------------------------------------
SELECT forget_device(pg_temp.dev('honnete'));
SELECT is((SELECT h.status FROM hazards h WHERE h.id = (SELECT id FROM h2)), 'disputed',
          'effacer ses données ne retire pas ses signalements : ce sont des faits sur la rue');
SELECT is((SELECT h.created_by FROM hazards h WHERE h.id = (SELECT id FROM h2)), NULL,
          'seulement le lien avec la personne');

SELECT * FROM finish();
ROLLBACK;
