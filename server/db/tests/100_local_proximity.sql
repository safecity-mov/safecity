-- L'application — le palier est déclaré par l'appareil (§6.2, §11.1), sur deux valeurs (0200).
--
-- Ce qui est vérifié : la règle reste publiée en un seul endroit, le serveur applique ce qu'on
-- lui déclare, accepte encore le code des apps d'avant, et refuse ce qui n'est pas un palier.

BEGIN;
SELECT no_plan();

-- --- La règle est lisible par l'app --------------------------------------------------------
SELECT is((SELECT count(*)::int FROM proximity_tiers), 2,
          'deux paliers publiés : « sur place » et « ailleurs » (§6.2 amendé)');
SELECT is((SELECT t.max_distance_m FROM proximity_tiers t WHERE t.tier = 1), 100,
          'le premier palier s''arrête à 100 m');
SELECT is((SELECT t.max_distance_m FROM proximity_tiers t WHERE t.tier = 2), NULL,
          'le second n''a pas de borne : c''est « ailleurs », ou pas de position');
SELECT is((SELECT t.weight FROM proximity_tiers t WHERE t.tier = 1), 1.0::real,
          'sur place, un geste pèse 1');
SELECT is((SELECT round(t.weight::numeric, 4) FROM proximity_tiers t WHERE t.tier = 2), 0.3333,
          'ailleurs, un tiers — trois gestes d''ailleurs valent un geste sur place');

-- La définition de référence et la table publiée ne peuvent pas diverger : la première lit la
-- seconde. On le vérifie tout de même, c'est l'invariant qui permet à l'app de calculer juste.
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
                         app_test.north(48.8566, 10), 2.3522), 1::smallint,
          'à 10 m, la référence serveur dit palier 1 — ce que l''app doit trouver aussi');
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
                         app_test.north(48.8566, 200), 2.3522), 2::smallint,
          'à 200 m, palier 2');
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
                         app_test.north(48.8566, 2000), 2.3522), 2::smallint,
          'à 2 km, palier 2 aussi');

-- --- Le serveur applique ce qu'on lui déclare ----------------------------------------------
INSERT INTO devices (id) VALUES ('aaaa0000-0000-0000-0000-00000000aaaa');

CREATE TEMP TABLE cas AS
SELECT (report_hazard(gen_random_uuid(), 'aaaa0000-0000-0000-0000-00000000aaaa'::uuid,
                      'pothole', 48.9100, 2.4100, 2::smallint, NULL, 1::smallint)
        ->> 'id')::uuid AS proche,
       (report_hazard(gen_random_uuid(), 'aaaa0000-0000-0000-0000-00000000aaaa'::uuid,
                      'pothole', 48.9200, 2.4200, 2::smallint, NULL, 2::smallint)
        ->> 'id')::uuid AS loin,
       (report_hazard(gen_random_uuid(), 'aaaa0000-0000-0000-0000-00000000aaaa'::uuid,
                      'pothole', 48.9300, 2.4300, 2::smallint, NULL, 3::smallint)
        ->> 'id')::uuid AS ancien;

SELECT is((SELECT e.weight FROM events e WHERE e.hazard_id = (SELECT proche FROM cas)),
          1.0::real, 'un palier 1 déclaré pèse 1,0');
SELECT is((SELECT round(e.weight::numeric, 4) FROM events e WHERE e.hazard_id = (SELECT loin FROM cas)),
          0.3333, 'un palier 2 déclaré pèse un tiers');

-- Les apps publiées avant 0200 envoient encore 3 pour « loin » : c'est le palier 2.
SELECT is((SELECT e.proximity FROM events e WHERE e.hazard_id = (SELECT ancien FROM cas)),
          2::smallint, 'un palier 3 déclaré par une app d''avant est enregistré 2');
SELECT is((SELECT round(e.weight::numeric, 4) FROM events e WHERE e.hazard_id = (SELECT ancien FROM cas)),
          0.3333, 'et pèse comme lui');
SELECT is((SELECT count(*) FROM events e WHERE e.proximity NOT BETWEEN 1 AND 2), 0::bigint,
          'le code 3 n''existe plus dans le journal');

-- Le badge « signalé à distance » suit le palier, pas une coordonnée (§6.2).
SELECT is((SELECT (hazard_json(c.loin) ->> 'reported_remotely')::boolean FROM cas c), true,
          'un palier 2 porte le badge « signalé à distance »');
SELECT is((SELECT (hazard_json(c.ancien) ->> 'reported_remotely')::boolean FROM cas c), true,
          'un 3 d''avant aussi');
SELECT is((SELECT (hazard_json(c.proche) ->> 'reported_remotely')::boolean FROM cas c), false,
          'un palier 1 ne le porte pas');

-- --- Ce qui n'est pas un palier est refusé --------------------------------------------------
SELECT throws_ok(
  $$ SELECT report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole',
                          48.96, 2.46, 2::smallint, NULL, 7::smallint) $$,
  '23514', NULL,
  'un palier hors bornes est refusé : le client déclare, il n''invente pas'
);
SELECT throws_ok(
  $$ SELECT report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole',
                          48.97, 2.47, 2::smallint, NULL, 0::smallint) $$,
  '23514', NULL, 'zéro non plus');

-- Sans palier déclaré, le moins favorable. Mieux vaut sous-pondérer un geste honnête que
-- sur-pondérer une déclaration absente.
-- Le signalement d'abord, la lecture ensuite : imbriquer l'appel dans le WHERE laisserait
-- l'ordre d'évaluation décider du résultat.
CREATE TEMP TABLE muet AS
SELECT (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole',
                      48.94, 2.44, 2::smallint) ->> 'id')::uuid AS id;

SELECT is((SELECT round(e.weight::numeric, 4) FROM events e WHERE e.hazard_id = (SELECT id FROM muet)),
          0.3333,
          'un geste sans palier déclaré compte pour un tiers');

-- --- Plus aucune coordonnée du déclarant n'entre ---------------------------------------------
SELECT hasnt_column('events', 'device_lat', 'le journal n''a pas de latitude du déclarant');
SELECT is(
  (SELECT count(*)::int FROM information_schema.parameters
    WHERE specific_schema = 'public'
      AND specific_name LIKE 'report_hazard%'
      AND parameter_name IN ('device_lat', 'device_lng')),
  0,
  'et le RPC n''a plus de quoi en recevoir une');

-- --- La règle se règle, et refuse ce qui n'a pas de sens ------------------------------------
-- La distance et les poids s'éditent depuis la console (§4.3). Autant de façons de casser la
-- règle du §6.2, que la base doit refuser plutôt que de laisser l'app les appliquer.
SELECT throws_ok($$ UPDATE proximity_tiers SET weight = CASE tier WHEN 1 THEN 0.5 ELSE 0.9 END $$,
                 '23514', NULL,
                 'un vote d''ailleurs qui pèserait plus qu''un vote sur place est refusé');
SELECT throws_ok($$ UPDATE proximity_tiers SET max_distance_m = 5000 WHERE tier = 2 $$,
                 '23514', NULL,
                 'le second palier garde son « ailleurs », sans limite');
SELECT throws_ok($$ UPDATE proximity_tiers SET max_distance_m = NULL WHERE tier = 1 $$,
                 '23514', NULL,
                 'et le premier garde une distance');
SELECT throws_ok($$ UPDATE proximity_tiers SET weight = 1.5 WHERE tier = 1 $$,
                 '23514', NULL,
                 'un poids supérieur à 1 n''entre pas');
SELECT throws_ok($$ INSERT INTO proximity_tiers (tier, max_distance_m, weight) VALUES (3, NULL, 0.1) $$,
                 '23514', NULL,
                 'un troisième palier non plus');
SELECT throws_ok($$ DELETE FROM proximity_tiers WHERE tier = 2 $$,
                 '23514', NULL,
                 'et il en faut deux');

-- Un réglage cohérent passe, et la règle de référence le suit immédiatement.
SELECT lives_ok($$ UPDATE proximity_tiers SET max_distance_m = 150 WHERE tier = 1 $$,
                'élargir le palier « sur place » est accepté');
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
                         app_test.north(48.8566, 120), 2.3522), 1::smallint,
          'à 120 m, le palier devient 1 : la règle publiée est celle qui s''applique');

-- Le poids d'un geste déjà émis ne bouge pas : il est figé dans le journal, qui ne se réécrit
-- jamais (§5). Un réglage vaut pour la suite, pas pour le passé.
CREATE TEMP TABLE ancien_poids AS
SELECT (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole',
                      48.95, 2.45, 2::smallint, NULL, 1::smallint) ->> 'id')::uuid AS id;
UPDATE proximity_tiers SET weight = 0.6 WHERE tier = 1;
SELECT is((SELECT e.weight FROM events e WHERE e.hazard_id = (SELECT id FROM ancien_poids)),
          1.0::real,
          'un vote déjà pesé garde son poids quand la règle change');

SELECT * FROM finish();
ROLLBACK;
