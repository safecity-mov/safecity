-- L'application — le registre des migrations, et l'état que 0220 garantit après le rejeu du
-- 21/09. run-tests.sh a rejoué 0030 exprès sur la base migrée, puis effacé le registre, avant
-- de relancer migrate.sh : si 0220 ne réparait pas, c'est ici que ça se voit.
BEGIN;
SELECT no_plan();

-- Le registre existe, il commence au début, et personne ne le lit par l'API.
SELECT has_table('schema_migrations');
SELECT is((SELECT min(filename) FROM schema_migrations), '0001_extensions.sql',
          'le registre commence à la première migration');
SELECT is((SELECT count(*) FROM schema_migrations WHERE filename = '0220_repair_after_replay.sql'),
          1::bigint, 'la réparation est inscrite une fois');
SELECT ok(NOT has_table_privilege('anon', 'schema_migrations', 'SELECT'),
          'anon ne lit pas le registre des migrations');
SELECT ok(NOT has_table_privilege('admin_api', 'schema_migrations', 'SELECT'),
          'la console non plus');

-- Les fantômes du rejeu ne sont plus là.
SELECT hasnt_function('public', 'record_event',
       ARRAY['uuid', 'uuid', 'uuid', 'event_type', 'double precision', 'double precision', 'jsonb'],
       'record_event ne prend plus de coordonnées de terminal (0100)');
SELECT hasnt_function('public', 'resolve_threshold', ARRAY['integer', 'integer', 'integer', 'integer'],
       'le seuil se calcule sur un poids, pas sur un compte (0200)');
SELECT has_function('public', 'resolve_threshold', ARRAY['real', 'integer', 'integer', 'integer'],
       'et c''est la seule signature de resolve_threshold');
SELECT has_function('public', 'record_event', ARRAY['uuid', 'uuid', 'uuid', 'event_type', 'smallint', 'jsonb'],
       'record_event prend un palier déclaré');

-- Et la dernière version de chaque objet est bien celle en place.
SELECT is(proximity_weight(2::smallint), (SELECT weight FROM proximity_tiers WHERE tier = 2),
          'proximity_weight lit proximity_tiers, pas des constantes (0030 en avait)');
SELECT ok(position('SET confirmations ' IN pg_get_functiondef('recompute_hazard(uuid)'::regprocedure)) = 0,
          'recompute_hazard écrit confirm_weight, la colonne qui existe (0200)');
SELECT ok(position('report_confirmations' IN pg_get_functiondef('recompute_hazard(uuid)'::regprocedure)) > 0,
          'et pèse un signalement comme N confirmations (0200)');
SELECT ok(NOT has_function_privilege('anon', 'proximity_weight(smallint)', 'EXECUTE'),
          'proximity_weight n''est pas une RPC publique (0110)');

SELECT * FROM finish();
ROLLBACK;
