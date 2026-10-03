-- L'application — administration de la bêta (§4.3).
--
-- Ce qui est vérifié ici tient en une phrase : un administrateur peut défaire, il ne peut
-- pas agir en douce, et ce qu'il défait reste défait jusqu'à ce qu'il le refasse.

BEGIN;
SELECT no_plan();

-- --- Décor -------------------------------------------------------------------------------
INSERT INTO admins (user_id, email) VALUES
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'moderation@example.org');

INSERT INTO devices (id) VALUES
  ('bbbbbbbb-0000-0000-0000-00000000000b'),   -- le vandale
  ('cccccccc-0000-0000-0000-00000000000c');   -- un honnête

CREATE TEMP TABLE ids AS
SELECT (report_hazard(gen_random_uuid(), 'bbbbbbbb-0000-0000-0000-00000000000b'::uuid,
                      'pothole', 48.8000, 2.3000, 3::smallint) ->> 'id')::uuid AS vandale,
       (report_hazard(gen_random_uuid(), 'cccccccc-0000-0000-0000-00000000000c'::uuid,
                      'pothole', 48.8500, 2.3500, 2::smallint) ->> 'id')::uuid AS honnete;

-- Le vandale confirme aussi le danger de l'honnête : son bannissement devra défaire ça.
SELECT confirm_hazard(gen_random_uuid(), (SELECT honnete FROM ids),
                      'bbbbbbbb-0000-0000-0000-00000000000b'::uuid);

-- --- Sans jeton, rien ---------------------------------------------------------------------
SELECT throws_ok(
  format('SELECT admin_ban_device(%L, %L)', 'bbbbbbbb-0000-0000-0000-00000000000b', 'essai'),
  '42501',
  NULL,
  'sans jeton, bannir est impossible'
);

SELECT set_config('request.jwt.claims', '{"sub":"99999999-9999-9999-9999-999999999999"}', true);
SELECT throws_ok(
  format('SELECT admin_ban_device(%L, %L)', 'bbbbbbbb-0000-0000-0000-00000000000b', 'essai'),
  '42501',
  NULL,
  'un jeton qui ne correspond à aucun admin non plus'
);

SELECT set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a"}', true);

-- --- Le motif n'est pas facultatif --------------------------------------------------------
SELECT throws_ok(
  format('SELECT admin_ban_device(%L, %L)', 'bbbbbbbb-0000-0000-0000-00000000000b', '  '),
  '23514',
  NULL,
  'un motif vide est refusé : le journal d''audit doit dire pourquoi'
);

-- --- Retirer un danger --------------------------------------------------------------------
SELECT admin_set_hazard_removed((SELECT honnete FROM ids), true, 'doublon manifeste');
SELECT is((SELECT h.status FROM hazards h WHERE h.id = (SELECT honnete FROM ids)),
          'removed'::hazard_status,
          'retirer passe le danger en removed');
SELECT is((SELECT count(*) FROM hazards_public p WHERE p.id = (SELECT honnete FROM ids)),
          0::bigint,
          'et il disparaît de ce que le public peut lire (§4.2)');

SELECT admin_set_hazard_removed((SELECT honnete FROM ids), false, 'erreur de ma part');
SELECT isnt((SELECT h.status FROM hazards h WHERE h.id = (SELECT honnete FROM ids)),
            'removed'::hazard_status,
            'rétablir le remet en jeu : le retrait est réversible (§4.3)');

-- --- Bannir -------------------------------------------------------------------------------
SELECT is((SELECT (admin_ban_device('bbbbbbbb-0000-0000-0000-00000000000b',
                                    'vandalisme coordonné') ->> 'events_cancelled')::int),
          2,
          'bannir annule tous les événements du terminal, création et confirmation');

SELECT is((SELECT h.status FROM hazards h WHERE h.id = (SELECT vandale FROM ids)),
          'removed'::hazard_status,
          'ses signalements sont retirés');

-- Le signalement de l'honnête a été fait sans palier déclaré, donc « ailleurs » : 3 × 1/3.
SELECT is(app_test.confirm_weight((SELECT honnete FROM ids)),
          1.00::numeric,
          'et sa confirmation chez les autres cesse de compter : reste le signalement seul');

SELECT is((SELECT count(*) FROM events e WHERE e.device_id = 'bbbbbbbb-0000-0000-0000-00000000000b'),
          2::bigint,
          'le journal, lui, reste entier : on annule, on ne supprime pas (§5)');

SELECT isnt((SELECT d.banned_at FROM devices d WHERE d.id = 'bbbbbbbb-0000-0000-0000-00000000000b'),
            NULL,
            'le terminal porte sa date de bannissement');

-- --- Et le blocage mord -------------------------------------------------------------------
SELECT throws_ok(
  format('SELECT report_hazard(gen_random_uuid(), %L, %L, 48.9, 2.4, 2::smallint)',
         'bbbbbbbb-0000-0000-0000-00000000000b', 'pothole'),
  '42501',
  NULL,
  'un terminal banni ne peut plus signaler'
);
SELECT throws_ok(
  format('SELECT confirm_hazard(gen_random_uuid(), %L, %L)',
         (SELECT honnete FROM ids), 'bbbbbbbb-0000-0000-0000-00000000000b'),
  '42501',
  NULL,
  'ni confirmer'
);
SELECT lives_ok(
  format('SELECT confirm_hazard(gen_random_uuid(), %L, %L)',
         (SELECT honnete FROM ids), gen_random_uuid()),
  'tandis qu''un terminal quelconque passe toujours'
);

-- --- Et il n'y a pas de retour en arrière (décision, AUDIT I1) -----------------------------
SELECT hasnt_function('public', 'admin_unban_device',
                      'le débannissement n''existe pas : il ne rendait presque rien');
SELECT is((SELECT h.status FROM hazards h WHERE h.id = (SELECT vandale FROM ids)),
          'removed'::hazard_status,
          'ses dangers restent retirés ; on les rétablit un par un depuis le journal (§4.3)');

-- --- Le journal d'audit -------------------------------------------------------------------
-- Trois actions abouties : retirer, rétablir, bannir. La tentative sans motif n'en fait pas
-- partie — elle a échoué avant d'écrire, ce qui est le but de journaliser d'abord et d'agir
-- ensuite.
SELECT is((SELECT count(*) FROM admin_actions), 3::bigint,
          'chaque action aboutie est journalisée, et seulement elles');
SELECT is((SELECT count(*) FROM admin_actions a WHERE a.reason IS NULL OR btrim(a.reason) = ''),
          0::bigint,
          'aucune sans motif');

-- --- Le catalogue -------------------------------------------------------------------------
UPDATE hazard_types SET dedup_radius_m = 20 WHERE code = 'pothole';
SELECT is((SELECT count(*) FROM admin_actions a WHERE a.action = 'type.update'),
          1::bigint,
          'éditer le catalogue laisse une trace, alors que c''est une écriture en table');

-- --- Les seuils de résolution -------------------------------------------------------------
-- Ils s'éditent comme le catalogue, en table, et se journalisent pareil : une règle de
-- modération changée sans trace serait le plus gros angle mort de la console (§4.3).
UPDATE moderation_settings SET min_resolve_votes = 3;
SELECT is((SELECT count(*) FROM admin_actions a WHERE a.action = 'rules.update'),
          1::bigint,
          'régler les seuils laisse une trace');
SELECT is((SELECT a.snapshot -> 'after' ->> 'min_resolve_votes' FROM admin_actions a
            WHERE a.action = 'rules.update'),
          '3', 'et le journal garde la valeur écrite');
SELECT ok((SELECT updated_at > now() - interval '1 minute' FROM moderation_settings),
          'la date de réglage est posée par la base');

-- Les paliers de proximité pareillement, mais en une seule ligne de journal pour les deux :
-- séparés, ils ne veulent rien dire (§6.2).
UPDATE proximity_tiers SET weight = 0.4 WHERE tier = 2;
SELECT is((SELECT count(*) FROM admin_actions a WHERE a.action = 'tiers.update'),
          1::bigint,
          'régler les paliers laisse une trace, une seule pour les deux');
SELECT is((SELECT jsonb_array_length(a.snapshot -> 'after') FROM admin_actions a
            WHERE a.action = 'tiers.update'),
          2, 'et le journal garde l''état complet de la règle');

-- Et il a des bornes : la console l'édite en direct, `Number('')` vaut 0 (AUDIT I4).
SELECT throws_ok($$ UPDATE hazard_types SET dedup_radius_m = 0 WHERE code = 'pothole' $$,
                 '23514', NULL, 'un rayon anti-doublon à 0 aussi');
SELECT throws_ok($$ UPDATE hazard_types SET default_ttl_days = 0 WHERE code = 'pothole' $$,
                 '23514', NULL, 'et une expiration à 0 jour');
SELECT throws_ok($$ UPDATE hazard_types SET label_fr = '  ' WHERE code = 'pothole' $$,
                 '23514', NULL, 'un libellé vide n''a rien à faire dans l''app');
SELECT throws_ok($$ INSERT INTO hazard_types (code, label_fr, icon, resolved_label_fr, default_ttl_days)
                    VALUES ('Verre Brisé', 'x', 'x', 'x', 30) $$,
                 '23514', NULL, 'un code hors [a-z_] est refusé');

-- --- Ce que le jeton ne lit pas (AUDIT C1) ------------------------------------------------
-- Le rôle `admin_api` n'a aucun droit sur les tables qui portent le lien terminal → gestes.
-- Les vues d'administration lisent en droits du propriétaire, et n'exposent pas ce lien.
SELECT ok(NOT has_table_privilege('admin_api', 'hazards', 'SELECT'),
          'admin_api ne lit pas la table hazards');
SELECT ok(NOT has_table_privilege('admin_api', 'devices', 'SELECT'),
          'ni devices');
SELECT ok(NOT has_table_privilege('admin_api', 'events', 'SELECT'),
          'ni events');
SELECT ok(NOT has_column_privilege('admin_api', 'hazards', 'created_by', 'SELECT'),
          'et surtout pas hazards.created_by');
SELECT ok(NOT has_column_privilege('admin_api', 'events', 'device_id', 'SELECT'),
          'ni events.device_id : le lien reste hors de portée d''un jeton (§11)');
SELECT throws_ok($$ SELECT app_test.admin_api_reads_hazards() $$, '42501', NULL,
                 'vérifié en exécution : lire hazards sous admin_api échoue');
SELECT throws_ok($$ SELECT app_test.admin_api_reads_events() $$, '42501', NULL,
                 'lire events aussi');
SELECT ok(app_test.admin_api_reads_admin_hazards() >= 2,
          'tandis que la vue admin_hazards répond, avec un jeton valide');
SELECT is((SELECT count(*)::int FROM information_schema.columns
            WHERE table_name IN ('admin_hazards', 'admin_devices')
              AND column_name IN ('created_by', 'device_id')), 0,
          'et aucune vue admin ne porte created_by ni device_id');

-- --- Désactiver un administrateur ferme tout, la lecture comprise (AUDIT C2) --------------
SELECT is(admin_whoami() ->> 'email', 'moderation@example.org',
          'admin_whoami() reconnaît un administrateur actif');

UPDATE admins SET disabled_at = now() WHERE user_id = 'aaaaaaaa-0000-0000-0000-00000000000a';

SELECT throws_ok('SELECT admin_whoami()', '42501', NULL,
                 'désactivé, il n''est plus reconnu');
SELECT throws_ok($$ SELECT app_test.admin_api_reads_admin_hazards() $$, '42501', NULL,
                 'et ne lit plus les dangers');
SELECT throws_ok($$ SELECT app_test.admin_api_reads_audit() $$, '42501', NULL,
                 'ni le journal d''audit');
SELECT throws_ok($$ SELECT count(*) FROM admin_devices $$, '42501', NULL,
                 'ni les terminaux');

UPDATE admins SET disabled_at = NULL WHERE user_id = 'aaaaaaaa-0000-0000-0000-00000000000a';

-- --- Le journal d'audit ne se réécrit pas, même en SQL (AUDIT M9) -------------------------
SELECT throws_ok($$ UPDATE admin_actions SET reason = 'autre chose' $$, '42501', NULL,
                 'modifier une ligne du journal est refusé, même en superuser');
SELECT throws_ok($$ DELETE FROM admin_actions $$, '42501', NULL,
                 'la supprimer aussi');

-- --- Les fonctions admin vérifient leur cible avant d'écrire (AUDIT M8) -------------------
CREATE TEMP TABLE avant AS SELECT count(*) AS n FROM admin_actions;

SELECT throws_ok(
  format('SELECT admin_ban_device(%L, %L)', gen_random_uuid(), 'fantôme'),
  'P0002', NULL,
  'bannir un terminal inconnu est refusé');
SELECT throws_ok(
  format('SELECT admin_set_hazard_removed(%L, NULL, %L)', (SELECT honnete FROM ids), 'flou'),
  '23514', NULL,
  'retirer-ou-rétablir sans dire lequel est refusé, au lieu de rétablir en silence');
-- Depuis 0160, chaque type a sa silhouette par défaut : on en enlève une ici, dans la
-- transaction du test, pour avoir un type sans icône.
DELETE FROM hazard_type_icons WHERE type_code = 'pothole';
SELECT throws_ok(
  format('SELECT admin_clear_hazard_icon(%L)', 'pothole'),
  'P0002', NULL,
  'retirer une icône qui n''existe pas est refusé');
SELECT is((SELECT count(*) FROM admin_actions), (SELECT n FROM avant),
          'et aucune de ces tentatives n''a laissé de ligne au journal');

SELECT throws_ok(
  format('SELECT admin_ban_device(%L, %L)', 'bbbbbbbb-0000-0000-0000-00000000000b', 'encore'),
  '23505', NULL,
  'bannir un terminal déjà bloqué est refusé plutôt que de rendre des compteurs à zéro');

-- --- « Effacer mes données » ne lève pas un bannissement (AUDIT I2) -----------------------
SELECT lives_ok(
  format('SELECT forget_device(%L)', 'bbbbbbbb-0000-0000-0000-00000000000b'),
  'un terminal bloqué peut effacer ses données (§11.4)');
SELECT isnt((SELECT d.banned_at FROM devices d WHERE d.id = 'bbbbbbbb-0000-0000-0000-00000000000b'),
            NULL,
            'mais son blocage reste : la décision de l''administrateur n''est pas effacée par ce chemin');
SELECT throws_ok(
  format('SELECT report_hazard(gen_random_uuid(), %L, %L, 48.95, 2.45, 2::smallint)',
         'bbbbbbbb-0000-0000-0000-00000000000b', 'pothole'),
  '42501', NULL,
  'et il ne peut toujours pas signaler');

-- --- La chronologie publique ignore les gestes annulés (AUDIT M7) -------------------------
-- Le danger de l'honnête a reçu une confirmation du vandale, annulée par le bannissement,
-- puis une d'un terminal quelconque. Le détail ne doit montrer que la seconde.
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(hazard_detail((SELECT honnete FROM ids)) -> 'timeline') t
            WHERE t ->> 'type' = 'confirm'), 1,
          'le détail ne compte pas la confirmation annulée du vandale');

SELECT * FROM finish();
ROLLBACK;
