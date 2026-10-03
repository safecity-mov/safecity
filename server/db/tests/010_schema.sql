-- L'application — le schéma est-il celui du §5, et le catalogue celui du §3 ?
BEGIN;
SELECT no_plan();

SELECT has_table('hazard_types'), has_table('devices'), has_table('hazards'),
       has_table('events'), has_table('admins'), has_table('admin_actions'), has_table('photos');

SELECT has_type('hazard_status'), has_type('event_type');
SELECT enum_has_labels('hazard_status', ARRAY['active','disputed','resolved','removed','archived']);
SELECT enum_has_labels('event_type',
       ARRAY['create','confirm','mark_resolved','remove','flag','restore','photo_add']);

-- La position du danger est une géométrie ponctuelle en WGS84, en double précision (§11.6).
SELECT col_type_is('hazards', 'geom', 'geometry(Point,4326)');
SELECT has_index('hazards', 'hazards_geom_idx');
SELECT has_index('hazards', 'hazards_status_idx');

-- Idempotence (§10) et « une action de chaque type par danger et par device » (§6.3).
SELECT col_is_unique('events', 'client_id');
SELECT has_index('events', 'events_one_per_device');

-- Contrainte produit : commentaire de 140 caractères (§4.1 F2).
SELECT throws_ok(
  $$ INSERT INTO hazards (type, geom, severity, description)
     VALUES ('pothole', ST_SetSRID(ST_MakePoint(2.35, 48.85), 4326), 2, repeat('x', 141)) $$,
  '23514', NULL, 'un commentaire de plus de 140 caractères est refusé');

SELECT throws_ok(
  $$ INSERT INTO hazards (type, geom, severity)
     VALUES ('pothole', ST_SetSRID(ST_MakePoint(2.35, 48.85), 4326), 4) $$,
  '23514', NULL, 'la gravité est bornée à 1–3');

-- §3 : sept types modélisés, un seul activé pendant le pilote.
SELECT is((SELECT count(*) FROM hazard_types), 7::bigint, 'les sept types du catalogue sont présents');
SELECT is((SELECT count(*) FROM hazard_types WHERE enabled), 1::bigint, 'un seul type est activé');
SELECT is((SELECT code FROM hazard_types WHERE enabled), 'pothole', 'et c''est pothole');
SELECT is((SELECT count(*) FROM moderation_settings), 1::bigint,
          'un seul jeu de seuils, pour tous les types (§6.1)');
SELECT is((SELECT min_resolve_votes FROM moderation_settings), 2,
          'plancher de résolution : 2 devices distincts (§0)');
SELECT is((SELECT confirmations_per_resolve_vote FROM moderation_settings), 3,
          'une voix « résolu » de plus toutes les trois confirmations');
SELECT is((SELECT max_resolve_votes FROM moderation_settings), 5,
          'et jamais plus de cinq');
SELECT is((SELECT report_confirmations FROM moderation_settings), 3,
          'un signalement vaut trois confirmations (§6.1 amendé)');
SELECT hasnt_column('public', 'hazard_types', 'min_resolve_votes',
          'le catalogue ne porte plus de règle de modération');
SELECT throws_ok($$ INSERT INTO moderation_settings (id) VALUES (2) $$,
                 '23514', NULL, 'une seconde ligne de réglages est refusée');
SELECT is((SELECT dedup_radius_m FROM hazard_types WHERE code = 'pothole'), 15,
          'rayon anti-doublon : 15 m (§4.1 F2b)');
SELECT is((SELECT default_ttl_days FROM hazard_types WHERE code = 'debris'), 7,
          'les débris passent en « à vérifier » au bout d''une semaine (§6.4)');

SELECT * FROM finish();
ROLLBACK;
