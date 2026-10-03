-- L'application — §6.1 « supprimer = voter résolu » et §6.2 pondération, bout en bout.
-- C'est le test qui compte : c'est lui qui dit si un acteur isolé peut effacer la carte.
--
-- Depuis 0200, les gestes « présent » pèsent comme les votes « résolu » : `confirm_weight`
-- est une somme de poids, un signalement sur place vaut `report_confirmations` (3), un geste
-- d'ailleurs vaut 1/3. Les comparaisons de poids passent par `app_test.*` qui arrondit au
-- centième : ce sont des `real`.
BEGIN;
SELECT no_plan();

CREATE TEMP TABLE h (label text PRIMARY KEY, id uuid);
CREATE TEMP TABLE d (label text PRIMARY KEY, id uuid DEFAULT gen_random_uuid());
INSERT INTO d (label) VALUES ('a'), ('b'), ('c'), ('e');

-- --- Un vote « résolu » suffit à contester, pas à effacer ----------------------------
INSERT INTO h VALUES ('t1', app_test.report((SELECT id FROM d WHERE label='a'), 48.8566, 2.3522));

SELECT app_test.resolve_near((SELECT id FROM d WHERE label='b'), (SELECT id FROM h WHERE label='t1'));
SELECT is(app_test.weight((SELECT id FROM h WHERE label='t1')), 1.00,
          'un vote émis sur place pèse 1,0 (§6.2)');
SELECT is(app_test.status((SELECT id FROM h WHERE label='t1')), 'disputed',
          'poids 1 : le danger passe en « signalé résolu », reste visible (§6.1)');

-- Le seuil du nid-de-poule est de 2 : un second device distinct fait basculer.
SELECT app_test.resolve_near((SELECT id FROM d WHERE label='c'), (SELECT id FROM h WHERE label='t1'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='t1')), 'resolved',
          'deux devices distincts sur place : résolu (§0, seuil = 2)');

-- --- Un device seul ne peut pas effacer la carte -------------------------------------
INSERT INTO h VALUES ('t2', app_test.report((SELECT id FROM d WHERE label='a'), 48.8600, 2.3600));
SELECT app_test.resolve_near((SELECT id FROM d WHERE label='b'), (SELECT id FROM h WHERE label='t2'));
-- Même device, second vote : l'index unique (hazard_id, device_id, type) l'absorbe.
SELECT lives_ok(
  format($$ SELECT app_test.resolve_near(%L::uuid, %L::uuid) $$,
         (SELECT id FROM d WHERE label='b'), (SELECT id FROM h WHERE label='t2')),
  'voter deux fois ne renvoie pas d''erreur au client');
SELECT is((SELECT count(*) FROM events e
            WHERE e.hazard_id = (SELECT id FROM h WHERE label='t2') AND e.type = 'mark_resolved'),
          1::bigint, 'mais un seul vote est enregistré (§6.3)');
SELECT is(app_test.status((SELECT id FROM h WHERE label='t2')), 'disputed',
          'le danger reste contesté : un acteur isolé ne l''efface pas');

-- --- Voter de loin ne suffit pas -----------------------------------------------------
INSERT INTO h VALUES ('t3', app_test.report((SELECT id FROM d WHERE label='a'), 48.8700, 2.3700));
SELECT app_test.resolve_far((SELECT id FROM d WHERE label='b'), (SELECT id FROM h WHERE label='t3'));
SELECT app_test.resolve_far((SELECT id FROM d WHERE label='c'), (SELECT id FROM h WHERE label='t3'));
SELECT is(app_test.weight((SELECT id FROM h WHERE label='t3')), 0.67,
          'deux votes émis d''ailleurs pèsent 1/3 chacun (§6.2 amendé)');
SELECT is(app_test.status((SELECT id FROM h WHERE label='t3')), 'active',
          'et ne suffisent pas à contester le danger');
SELECT app_test.resolve_far((SELECT id FROM d WHERE label='e'), (SELECT id FROM h WHERE label='t3'));
SELECT is(app_test.weight((SELECT id FROM h WHERE label='t3')), 1.00,
          'trois votes d''ailleurs valent un vote sur place : c''est le sens du ratio 3');
SELECT is(app_test.status((SELECT id FROM h WHERE label='t3')), 'disputed',
          'et le danger passe en « signalé résolu »');

-- --- Un « confirmer » pendant `disputed` annule les votes résolus --------------------
INSERT INTO h VALUES ('t4', app_test.report((SELECT id FROM d WHERE label='a'), 48.8800, 2.3800));
SELECT app_test.resolve_near((SELECT id FROM d WHERE label='b'), (SELECT id FROM h WHERE label='t4'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='t4')), 'disputed',
          'le danger est contesté');

SELECT app_test.confirm_near((SELECT id FROM d WHERE label='c'), (SELECT id FROM h WHERE label='t4'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='t4')), 'active',
          '« Toujours là » ramène le danger à actif (§6.1)');
SELECT is(app_test.weight((SELECT id FROM h WHERE label='t4')), 0.00,
          'et remet le poids « résolu » à zéro');
SELECT is((SELECT count(*) FROM events e
            WHERE e.hazard_id = (SELECT id FROM h WHERE label='t4') AND e.type = 'mark_resolved'),
          1::bigint, 'sans rien effacer du journal, qui reste la source de vérité (§5)');
SELECT is(app_test.confirm_weight((SELECT id FROM h WHERE label='t4')), 4.00,
          'la confirmation pèse : signalement 3, plus 1 sur place');

-- Un nouveau vote « résolu » d'un troisième device repart de zéro : il conteste à nouveau.
SELECT app_test.resolve_near((SELECT id FROM d WHERE label='e'), (SELECT id FROM h WHERE label='t4'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='t4')), 'disputed',
          'un vote postérieur au « toujours là » conteste de nouveau');

-- --- Seuil dynamique : un trou très confirmé ne disparaît pas sur deux clics ---------
INSERT INTO h VALUES ('t5', app_test.report(gen_random_uuid(), 48.8900, 2.3900));
SELECT app_test.confirm_by((SELECT id FROM h WHERE label='t5'), 6);
SELECT is(app_test.confirm_weight((SELECT id FROM h WHERE label='t5')), 9.00,
          'un signalement et six confirmations sur place : poids 9');

SELECT app_test.resolve_near(gen_random_uuid(), (SELECT id FROM h WHERE label='t5'));
SELECT app_test.resolve_near(gen_random_uuid(), (SELECT id FROM h WHERE label='t5'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='t5')), 'disputed',
          'deux votes ne suffisent plus : le seuil est monté à 3 (§6.1)');

SELECT app_test.resolve_near(gen_random_uuid(), (SELECT id FROM h WHERE label='t5'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='t5')), 'resolved',
          'le troisième vote atteint le seuil');

-- --- Le journal reste la source de vérité : recompute est une fonction pure ----------
UPDATE hazards SET status = 'active', resolve_weight = 0, confirm_weight = 0
 WHERE id = (SELECT id FROM h WHERE label='t5');
SELECT recompute_hazard((SELECT id FROM h WHERE label='t5'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='t5')), 'resolved',
          'un recalcul depuis le journal rétablit l''état (§5)');
SELECT is(app_test.confirm_weight((SELECT id FROM h WHERE label='t5')), 9.00,
          'compteurs compris');

-- Neutraliser les événements d'un device et recalculer : rien n'est perdu (§4.3, §5).
DELETE FROM events e WHERE e.hazard_id = (SELECT id FROM h WHERE label='t5') AND e.type = 'mark_resolved';
SELECT is(app_test.status((SELECT id FROM h WHERE label='t5')), 'active',
          'annuler les votes « résolu » ramène le danger sur la carte');

-- --- Un danger résolu à tort revient si quelqu'un le confirme ------------------------
-- Le trou est toujours là : « Toujours là » doit pouvoir le ramener sur la carte.
SELECT app_test.confirm_near(gen_random_uuid(), (SELECT id FROM h WHERE label='t1'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='t1')), 'active',
          'confirmer un danger résolu le remet en service');
SELECT is(app_test.weight((SELECT id FROM h WHERE label='t1')), 0.00,
          'avec un poids « résolu » remis à zéro');

-- --- D2 : un signalement ne se confirme pas par son auteur ---------------------------
INSERT INTO h VALUES ('sien', app_test.report((SELECT id FROM d WHERE label='a'), 48.8100, 2.3100));
SELECT is(app_test.confirm_weight((SELECT id FROM h WHERE label='sien')), 3.00,
          'signaler vaut déjà trois confirmations (§6.1 amendé)');
SELECT throws_ok(
  format($$ SELECT app_test.confirm_near(%L::uuid, %L::uuid) $$,
         (SELECT id FROM d WHERE label='a'), (SELECT id FROM h WHERE label='sien')),
  '23514', NULL, 'l''auteur ne peut pas en ajouter une seconde (AUDIT D2)');
SELECT is(app_test.confirm_weight((SELECT id FROM h WHERE label='sien')), 3.00,
          'le poids ne bouge pas');
SELECT lives_ok(
  format($$ SELECT app_test.confirm_near(%L::uuid, %L::uuid) $$,
         (SELECT id FROM d WHERE label='b'), (SELECT id FROM h WHERE label='sien')),
  'un autre terminal, lui, confirme');

-- Passé 24 h, `anonymize_old_events` a coupé le lien : le serveur ne sait plus qui a signalé,
-- et la règle s'éteint avec lui. C'est la même durée de vie que la voix unique (§11.2).
UPDATE hazards SET created_by = NULL WHERE id = (SELECT id FROM h WHERE label='sien');
SELECT lives_ok(
  format($$ SELECT app_test.confirm_near(%L::uuid, %L::uuid) $$,
         (SELECT id FROM d WHERE label='a'), (SELECT id FROM h WHERE label='sien')),
  'une fois le lien effacé, plus rien ne distingue l''auteur des autres');

-- --- Les confirmations pèsent comme les votes (§6.1 amendé, 0200) -------------------
-- Quatre « toujours là » depuis le canapé ne font pas monter le seuil ; quatre sur place, si.
INSERT INTO h VALUES ('canape', app_test.report(gen_random_uuid(), 48.8300, 2.3300));
SELECT app_test.confirm_far(gen_random_uuid(), (SELECT id FROM h WHERE label='canape'));
SELECT app_test.confirm_far(gen_random_uuid(), (SELECT id FROM h WHERE label='canape'));
SELECT app_test.confirm_far(gen_random_uuid(), (SELECT id FROM h WHERE label='canape'));
SELECT app_test.confirm_far(gen_random_uuid(), (SELECT id FROM h WHERE label='canape'));
SELECT is(app_test.confirm_weight((SELECT id FROM h WHERE label='canape')), 4.33,
          'quatre confirmations d''ailleurs : 3 + 4 × 1/3');
SELECT is((hazard_json((SELECT id FROM h WHERE label='canape')) ->> 'resolve_threshold')::int, 2,
          'le seuil reste au plancher');

INSERT INTO h VALUES ('rue', app_test.report(gen_random_uuid(), 48.8400, 2.3400));
SELECT app_test.confirm_by((SELECT id FROM h WHERE label='rue'), 4);
SELECT is(app_test.confirm_weight((SELECT id FROM h WHERE label='rue')), 7.00,
          'quatre confirmations sur place : 3 + 4');
SELECT is((hazard_json((SELECT id FROM h WHERE label='rue')) ->> 'resolve_threshold')::int, 3,
          'et le seuil monte à 3');

-- Un signalement fait d'ailleurs vaut une confirmation sur place : 3 × 1/3.
CREATE TEMP TABLE loin AS
SELECT (report_hazard(gen_random_uuid(), app_test.aged(gen_random_uuid()), 'pothole',
                      48.8350, 2.3350, 2::smallint, NULL, 2::smallint) ->> 'id')::uuid AS id;
SELECT is(app_test.confirm_weight((SELECT id FROM loin)), 1.00,
          'un signalement d''ailleurs pèse comme une confirmation sur place');

-- Ce que vaut un signalement se règle, et vaut pour tout l'historique.
UPDATE moderation_settings SET report_confirmations = 6;
SELECT recompute_hazard((SELECT id FROM h WHERE label='rue'));
SELECT is(app_test.confirm_weight((SELECT id FROM h WHERE label='rue')), 10.00,
          'à six, le même danger pèse 6 + 4 : le réglage n''est pas figé dans le journal');
SELECT is((hazard_json((SELECT id FROM h WHERE label='rue')) ->> 'resolve_threshold')::int, 4,
          'et son seuil suit');
UPDATE moderation_settings SET report_confirmations = 3;
SELECT recompute_hazard((SELECT id FROM h WHERE label='rue'));

-- --- Le seuil se règle dans le catalogue, pas dans le code ---------------------------
INSERT INTO h VALUES ('reglage', app_test.report(gen_random_uuid(), 48.8200, 2.3200));
SELECT app_test.confirm_by((SELECT id FROM h WHERE label='reglage'), 6);
SELECT is((hazard_json((SELECT id FROM h WHERE label='reglage')) ->> 'resolve_threshold')::int, 3,
          'poids 9, une voix exigée toutes les trois : seuil 3');

UPDATE moderation_settings SET confirmations_per_resolve_vote = 9;
SELECT recompute_hazard((SELECT id FROM h WHERE label='reglage'));
SELECT is((hazard_json((SELECT id FROM h WHERE label='reglage')) ->> 'resolve_threshold')::int, 2,
          'le même danger retombe au plancher quand la règle se desserre');

SELECT app_test.resolve_near(gen_random_uuid(), (SELECT id FROM h WHERE label='reglage'));
SELECT app_test.resolve_near(gen_random_uuid(), (SELECT id FROM h WHERE label='reglage'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='reglage')), 'resolved',
          'et deux votes suffisent alors, sans qu''une ligne de code ait changé');
-- Le réglage vaut pour tous les types : il n'y a qu'une règle, et elle ne se lit pas dans le
-- catalogue (AUDIT, décision « mêmes seuils pour tous les types »).
SELECT is((SELECT count(*) FROM moderation_settings), 1::bigint,
          'et il n''y a toujours qu''un seul jeu de réglages');

SELECT * FROM finish();
ROLLBACK;
