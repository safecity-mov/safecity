-- L'application — silhouettes par défaut des types (0160).
--
-- Posées d'office, et jamais par-dessus une décision d'administrateur : ni une icône
-- téléversée, ni un retrait. L'installation rejoue toutes les migrations, cette règle est ce
-- qui empêche 0160 de remettre ce qu'on a enlevé.
BEGIN;
SELECT no_plan();

SELECT is((SELECT count(*) FROM hazard_type_icons i JOIN hazard_types t ON t.code = i.type_code),
          (SELECT count(*) FROM hazard_types),
          'chaque type du catalogue a sa silhouette dès la migration');
SELECT is((SELECT count(*) FROM admin_actions a WHERE a.action LIKE 'type.icon.%'), 0::bigint,
          'sans une ligne d''audit : ce n''est pas un geste d''administrateur, c''est le schéma');

INSERT INTO admins (user_id, email) VALUES
  ('11111111-0000-0000-0000-000000000011', 'moderation@example.org');
SELECT set_config('request.jwt.claims', '{"sub":"11111111-0000-0000-0000-000000000011"}', true);

-- Un administrateur retire l'icône du nid-de-poule, et en téléverse une autre pour « slippery ».
SELECT admin_clear_hazard_icon('pothole');
SELECT admin_set_hazard_icon('slippery', 'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII=');
-- Et « manhole » perd la sienne sans passer par la console — comme un catalogue d'avant 0160.
DELETE FROM hazard_type_icons WHERE type_code = 'manhole';

-- Rejouer la migration, comme le fait l'installation.
\i /db/migrations/0160_default_icons.sql

SELECT is((SELECT count(*) FROM hazard_type_icons i WHERE i.type_code = 'pothole'), 0::bigint,
          'un retrait décidé depuis la console n''est pas défait par la migration');
SELECT is((SELECT i.width FROM hazard_type_icons i WHERE i.type_code = 'slippery'), 64,
          'une icône téléversée n''est pas remplacée');
SELECT is((SELECT i.width FROM hazard_type_icons i WHERE i.type_code = 'manhole'), 128,
          'un type jamais réglé retrouve sa silhouette par défaut');

SELECT * FROM finish();
ROLLBACK;
