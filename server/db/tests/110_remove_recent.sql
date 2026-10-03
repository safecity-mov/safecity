-- L'application — §11.4 amendé : « Retirer mes signalements récents », d'un coup, aux mêmes
-- conditions que le retrait un par un : les siens, de moins de 24 h, encore sur la carte.
BEGIN;
SELECT no_plan();

CREATE TEMP TABLE d (label text PRIMARY KEY, id uuid DEFAULT gen_random_uuid());
INSERT INTO d (label) VALUES ('auteur'), ('autre');

CREATE TEMP TABLE h (label text PRIMARY KEY, id uuid);
INSERT INTO h VALUES
  ('frais_1', app_test.report((SELECT id FROM d WHERE label='auteur'), 48.8566, 2.3522)),
  ('frais_2', app_test.report((SELECT id FROM d WHERE label='auteur'), 48.8600, 2.3600)),
  ('vieux',   app_test.report((SELECT id FROM d WHERE label='auteur'), 48.8650, 2.3650)),
  ('d_autre', app_test.report((SELECT id FROM d WHERE label='autre'),  48.8700, 2.3700));
UPDATE hazards SET created_at = now() - interval '25 hours'
 WHERE id = (SELECT id FROM h WHERE label='vieux');

-- Un terminal sans signalement récent : rien à retirer, pas d'erreur.
SELECT is((remove_own_recent_hazards(gen_random_uuid()) ->> 'removed')::int, 0,
          'un inconnu ne retire rien, sans erreur');

-- L'auteur retire ses deux signalements récents, et seulement eux.
SELECT is((remove_own_recent_hazards((SELECT id FROM d WHERE label='auteur')) ->> 'removed')::int, 2,
          'deux signalements retirés : les siens, de moins de 24 h');
SELECT is(app_test.status((SELECT id FROM h WHERE label='frais_1')), 'removed', 'le premier est retiré');
SELECT is(app_test.status((SELECT id FROM h WHERE label='frais_2')), 'removed', 'le second aussi');
SELECT is(app_test.status((SELECT id FROM h WHERE label='vieux')), 'active',
          'celui de plus de 24 h reste : la porte est fermée (§6.1)');
SELECT is(app_test.status((SELECT id FROM h WHERE label='d_autre')), 'active',
          'celui d''un autre terminal n''est pas touché');

-- Rien n'est supprimé physiquement, et chaque retrait est tracé.
SELECT is((SELECT count(*) FROM hazards), 4::bigint, 'aucune suppression physique (§5)');
SELECT is((SELECT count(*) FROM events e WHERE e.type = 'remove'
             AND e.device_id = (SELECT id FROM d WHERE label='auteur')), 2::bigint,
          'deux événements remove au journal, portés par le terminal');

-- Rejouer ne fait rien de plus.
SELECT is((remove_own_recent_hazards((SELECT id FROM d WHERE label='auteur')) ->> 'removed')::int, 0,
          'un second appel ne retire plus rien');

-- Après « Effacer mes données », il n'y a plus rien à retirer : le lien est coupé.
INSERT INTO h VALUES ('apres', app_test.report((SELECT id FROM d WHERE label='auteur'), 48.8750, 2.3750));
SELECT lives_ok(format($$ SELECT forget_device(%L::uuid) $$, (SELECT id FROM d WHERE label='auteur')),
                'effacer mes données');
SELECT is((remove_own_recent_hazards((SELECT id FROM d WHERE label='auteur')) ->> 'removed')::int, 0,
          'une fois le lien coupé, le serveur ne sait plus lesquels retirer (§11.4)');
SELECT is(app_test.status((SELECT id FROM h WHERE label='apres')), 'active', 'le signalement reste');

-- Un terminal bloqué ne retire rien. Le blocage est posé directement : c'est la règle qu'on
-- teste, pas le chemin d'administration qui y mène (070_admin.sql s'en charge).
UPDATE devices SET banned_at = now() WHERE id = (SELECT id FROM d WHERE label='autre');
SELECT throws_ok(
  format($$ SELECT remove_own_recent_hazards(%L::uuid) $$, (SELECT id FROM d WHERE label='autre')),
  NULL, NULL, 'un terminal bloqué ne peut plus rien retirer');

SELECT * FROM finish();
ROLLBACK;
