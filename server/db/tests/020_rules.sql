-- L'application — §6.1 seuil dynamique et §6.2 pondération par proximité, en isolation.
BEGIN;
SELECT no_plan();

-- §6.2 amendé (0200) : ≤ 100 m → 1 « sur place » ; au-delà ou position refusée → 2 « ailleurs ».
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
                         app_test.north(48.8566, 10), 2.3522), 1::smallint,
          'à 10 m du danger : palier 1');
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
                         app_test.north(48.8566, 99), 2.3522), 1::smallint,
          'à 99 m : encore sur place');
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
                         app_test.north(48.8566, 200), 2.3522), 2::smallint,
          'à 200 m : ailleurs');
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
                         app_test.north(48.8566, 1000), 2.3522), 2::smallint,
          'à 1 km : ailleurs aussi, il n''y a plus de palier intermédiaire');
SELECT is(app_test.proximity_tier(ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326), NULL, NULL), 2::smallint,
          'position refusée : palier 2, et non une erreur');

SELECT is(proximity_weight(1::smallint), 1.0::real, 'palier 1 → poids 1,0');
SELECT is(round(proximity_weight(2::smallint)::numeric, 2), 0.33, 'palier 2 → poids 1/3');
SELECT is(round(proximity_weight(3::smallint)::numeric, 2), 0.33,
          'un palier inconnu vaut le moins : celui du dernier palier');

-- §6.1 amendé : seuil = clamp(ceil(poids / N), min_resolve_votes, plafond), sur le **poids**
-- des gestes « présent » et non plus leur compte. Sans les préciser, ce sont les réglages
-- d'avant : une voix de plus toutes les 3 confirmations, jamais plus de 5.
SELECT is(resolve_threshold(3, 2),  2, 'un signalement neuf sur place (poids 3) : le plancher');
SELECT is(resolve_threshold(6, 2),  2, 'poids 6 : ceil(2) = 2, toujours le plancher');
SELECT is(resolve_threshold(7, 2),  3, 'poids 7 : le seuil monte à 3');
SELECT is(resolve_threshold(9, 2),  3, 'poids 9 : 3 encore');
SELECT is(resolve_threshold(15, 2), 5, 'poids 15 : le seuil plafonne à 5');
SELECT is(resolve_threshold(60, 2), 5, 'et ne dépasse jamais 5');
SELECT is(resolve_threshold(2.5, 2), 2, 'un poids fractionnaire s''arrondit vers le haut : ceil(0,83) = 1, plancher 2');
SELECT is(resolve_threshold(6.1, 2), 3, 'et 6,1 passe déjà à 3');
SELECT is(resolve_threshold(3, 1),  1, 'un plancher à 1 garde son plancher');

-- Les mêmes, réglés depuis la console.
SELECT is(resolve_threshold(9, 2, 9, 5),  2,
          'une voix de plus toutes les neuf confirmations : neuf restent au plancher');
SELECT is(resolve_threshold(9, 2, 1, 5),  5,
          'une par confirmation : le plafond tout de suite');
SELECT is(resolve_threshold(30, 2, 3, 3), 3,
          'le plafond coupe avant le seuil calculé');
SELECT is(resolve_threshold(30, 2, 3, 10), 10,
          'et un plafond relevé laisse le seuil monter');
SELECT is(resolve_threshold(9, 2, 0, 5),  5,
          'un diviseur nul ne fait pas planter le recalcul de toute la carte');

-- Les bornes de la table de réglages : la console l'édite en direct (AUDIT I4).
SELECT throws_ok(
  $$ UPDATE moderation_settings SET max_resolve_votes = 1 $$,
  '23514', NULL, 'un plafond sous le plancher est refusé');
SELECT throws_ok(
  $$ UPDATE moderation_settings SET confirmations_per_resolve_vote = 0 $$,
  '23514', NULL, 'un diviseur nul aussi');
SELECT throws_ok(
  $$ UPDATE moderation_settings SET min_resolve_votes = 0 $$,
  '23514', NULL, 'et un plancher à zéro, qui effacerait la carte sur un seul vote');
SELECT throws_ok(
  $$ UPDATE moderation_settings SET report_confirmations = 0 $$,
  '23514', NULL, 'un signalement qui ne vaudrait rien est refusé');
SELECT throws_ok(
  $$ UPDATE moderation_settings SET report_confirmations = 11 $$,
  '23514', NULL, 'et un qui vaudrait plus de dix confirmations aussi');

SELECT * FROM finish();
ROLLBACK;
