-- L'application — les annonces aux personnes qui utilisent l'app (§4.3 amendé, 0230).
--
-- Une phrase : un administrateur peut parler à tout le monde, jamais en douce, jamais sans fin,
-- et l'app ne lit que ce qui est en cours — pas qui l'a écrit.
BEGIN;
SELECT no_plan();

-- --- Décor -------------------------------------------------------------------------------
INSERT INTO admins (user_id, email) VALUES
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'moderation@example.org');

-- --- Sans jeton, rien ---------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT admin_publish_announcement('Bonjour', now() + interval '1 day', 'essai') $$,
  '42501', NULL, 'sans jeton, publier est impossible');

SELECT set_config('request.jwt.claims', '{"sub":"99999999-9999-9999-9999-999999999999"}', true);
SELECT throws_ok(
  $$ SELECT admin_publish_announcement('Bonjour', now() + interval '1 day', 'essai') $$,
  '42501', NULL, 'un jeton qui ne correspond à aucun admin non plus');

SELECT set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a"}', true);

-- --- Ce qui est refusé, avec un message qui le dit ---------------------------------------
SELECT throws_ok(
  $$ SELECT admin_publish_announcement('Bonjour', now() + interval '1 day', '  ') $$,
  '23514', NULL, 'un motif vide est refusé : le journal doit dire pourquoi on annonce');
SELECT throws_ok(
  $$ SELECT admin_publish_announcement('   ', now() + interval '1 day', 'essai') $$,
  '23514', 'Le texte de l''annonce est vide.', 'un texte vide est refusé');
SELECT throws_ok(
  format($$ SELECT admin_publish_announcement(%L, now() + interval '1 day', 'essai') $$, repeat('x', 201)),
  '23514', NULL, 'un texte de plus de 200 caractères est refusé');
SELECT throws_ok(
  $$ SELECT admin_publish_announcement('Bonjour', now() - interval '1 minute', 'essai') $$,
  '23514', 'La date de fin est déjà passée.', 'une date de fin passée est refusée');
SELECT is((SELECT count(*) FROM admin_actions WHERE action LIKE 'announcement.%'), 0::bigint,
          'rien de tout cela n''a laissé de trace au journal : rien n''a été publié');

-- --- Publier ------------------------------------------------------------------------------
CREATE TEMP TABLE pub AS
SELECT admin_publish_announcement(
         '  Les signalements du 21 au 27/09 ont été perdus : merci de les refaire.  ',
         now() + interval '7 days',
         'panne du serveur du 21 au 27/09') AS r;

SELECT is((SELECT r ->> 'body' FROM pub),
          'Les signalements du 21 au 27/09 ont été perdus : merci de les refaire.',
          'le texte est rangé sans ses espaces autour');
SELECT is((SELECT count(*) FROM admin_actions WHERE action = 'announcement.publish'), 1::bigint,
          'une ligne announcement.publish au journal');
SELECT is((SELECT a.snapshot ->> 'body' FROM admin_actions a WHERE a.action = 'announcement.publish'),
          'Les signalements du 21 au 27/09 ont été perdus : merci de les refaire.',
          'avec le texte en instantané : le journal garde ce qui a été dit');
SELECT is((SELECT a.reason FROM admin_actions a WHERE a.action = 'announcement.publish'),
          'panne du serveur du 21 au 27/09', 'et le motif');
SELECT is((SELECT created_by FROM announcements), 'aaaaaaaa-0000-0000-0000-00000000000a'::uuid,
          'l''annonce porte son auteur, pris dans le jeton');

-- --- Ce que l'app lit ---------------------------------------------------------------------
SELECT is(app_test.anon_reads_announcements(), 1::bigint,
          'anon voit l''annonce en cours dans announcements_public');
SELECT is((SELECT string_agg(column_name, ',' ORDER BY column_name)
             FROM information_schema.columns WHERE table_name = 'announcements_public'),
          'body,ends_at,id,starts_at',
          'et rien de qui l''a écrite : ni created_by ni e-mail');
SELECT ok(NOT has_table_privilege('anon', 'announcements', 'SELECT'),
          'anon ne lit pas la table elle-même');
SELECT ok(NOT has_table_privilege('anon', 'admin_announcements', 'SELECT'),
          'ni la vue de la console');
SELECT throws_ok($$ SELECT app_test.anon_reads_announcements_table() $$, '42501', NULL,
                 'et l''essayer est refusé, pas seulement absent des droits déclarés');

-- Programmée pour plus tard, ou déjà finie : pas dans la vue publique.
INSERT INTO announcements (body, starts_at, ends_at, created_by) VALUES
  ('Demain', now() + interval '1 day', now() + interval '2 days', 'aaaaaaaa-0000-0000-0000-00000000000a'),
  ('Hier',   now() - interval '2 days', now() - interval '1 day', 'aaaaaaaa-0000-0000-0000-00000000000a');
SELECT is(app_test.anon_reads_announcements(), 1::bigint,
          'une annonce programmée ou terminée n''est pas montrée à l''app');
SELECT is((SELECT string_agg(state, ',' ORDER BY id) FROM admin_announcements),
          'active,scheduled,expired',
          'la console, elle, voit les trois avec leur état');
SELECT is((SELECT created_by_email FROM admin_announcements WHERE state = 'active'),
          'moderation@example.org', 'et qui les a écrites');

-- --- Retirer ------------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT admin_withdraw_announcement(424242, 'essai') $$,
  'P0002', NULL, 'retirer une annonce inconnue échoue avant d''écrire quoi que ce soit');

SELECT admin_withdraw_announcement((SELECT (r ->> 'id')::bigint FROM pub), 'texte corrigé, republiée');
SELECT is(app_test.anon_reads_announcements(), 0::bigint,
          'retirée, l''annonce disparaît de ce que l''app lit');
SELECT is((SELECT count(*) FROM admin_actions WHERE action = 'announcement.withdraw'), 1::bigint,
          'une ligne announcement.withdraw au journal');
SELECT is((SELECT state FROM admin_announcements WHERE id = (SELECT (r ->> 'id')::bigint FROM pub)),
          'withdrawn', 'et la console la voit retirée');
SELECT throws_ok(
  format($$ SELECT admin_withdraw_announcement(%s, 'encore') $$, (SELECT r ->> 'id' FROM pub)),
  'P0002', 'Cette annonce est déjà retirée.', 'la retirer deux fois est refusé, en clair');

-- --- Un administrateur désactivé ne parle plus à personne ---------------------------------
UPDATE admins SET disabled_at = now() WHERE user_id = 'aaaaaaaa-0000-0000-0000-00000000000a';
SELECT throws_ok(
  $$ SELECT admin_publish_announcement('Bonjour', now() + interval '1 day', 'essai') $$,
  '42501', NULL, 'désactivé, il ne publie plus');
SELECT throws_ok($$ SELECT count(*) FROM admin_announcements $$, '42501', NULL,
                 'et ne lit plus la liste');
UPDATE admins SET disabled_at = NULL WHERE user_id = 'aaaaaaaa-0000-0000-0000-00000000000a';

SELECT * FROM finish();
ROLLBACK;
