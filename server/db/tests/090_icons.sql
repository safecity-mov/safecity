-- L'application — icônes de type téléversées (§3, §4.3).
--
-- Ce qui est vérifié : la base refuse ce que l'app ne saurait pas dessiner, et ce qu'elle
-- accepte ressort tel quel de l'autre côté.

BEGIN;
SELECT no_plan();

INSERT INTO admins (user_id, email) VALUES
  ('11111111-0000-0000-0000-000000000011', 'moderation@example.org');
SELECT set_config('request.jwt.claims', '{"sub":"11111111-0000-0000-0000-000000000011"}', true);

-- Les silhouettes par défaut (0160) sont là dès la migration ; ce test raisonne sur un
-- catalogue nu, et compte ses lignes. Dans la transaction du test, donc sans effet ailleurs.
DELETE FROM hazard_type_icons;

-- --- Lecture d'en-tête ---------------------------------------------------------------------
SELECT is(png_dimensions(decode('iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII=', 'base64')), ARRAY[64, 64],
          'les dimensions se lisent dans l''IHDR, sans sortir de SQL');
SELECT is(png_dimensions('\x00010203040506070809101112131415161718192021'::bytea), NULL,
          'ce qui n''est pas un PNG n''a pas de dimensions');

-- --- Ce qui est refusé ---------------------------------------------------------------------
SELECT throws_ok(
  format('SELECT admin_set_hazard_icon(%L, %L)', 'pothole', 'pas du tout du base64 !!'),
  '23514', NULL,
  'un fichier illisible est refusé'
);
SELECT throws_ok(
  format('SELECT admin_set_hazard_icon(%L, %L)', 'pothole', encode('bonjour'::bytea, 'base64')),
  '23514', NULL,
  'un fichier qui n''est pas un PNG est refusé'
);
SELECT throws_ok(
  format('SELECT admin_set_hazard_icon(%L, %L)', 'pothole', 'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAYAAAChS3wfAAAATklEQVR42u3QAQEAAAgCIP+f1h8FE0ifiwABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIEHDPADPh0sLflADlAAAAAElFTkSuQmCC'),
  '23514', NULL,
  'une image non carrée est refusée : le marqueur est un disque'
);
SELECT throws_ok(
  format('SELECT admin_set_hazard_icon(%L, %L)', 'inconnu', 'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII='),
  'P0002', NULL,
  'un type inexistant est refusé'
);

-- --- Ce qui passe --------------------------------------------------------------------------
SELECT is((admin_set_hazard_icon('pothole', 'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII=') ->> 'width')::int, 64,
          'un PNG carré est accepté et sa largeur rendue');

SELECT is((SELECT i.width FROM hazard_type_icons i WHERE i.type_code = 'pothole'), 64,
          'la largeur est calculée par la base, pas déclarée par le client');

SELECT is((SELECT p.png_b64 FROM hazard_type_icons_public p WHERE p.type_code = 'pothole'),
          'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII=',
          'et l''app relit exactement les octets téléversés');

-- --- Remplacer, puis retirer ---------------------------------------------------------------
SELECT lives_ok(
  format('SELECT admin_set_hazard_icon(%L, %L)', 'pothole', 'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII='),
  'téléverser deux fois remplace au lieu d''échouer'
);
SELECT is((SELECT count(*)::int FROM hazard_type_icons), 1,
          'une seule icône par type');

SELECT is((admin_clear_hazard_icon('pothole') ->> 'removed')::int, 1,
          'retirer l''icône rend le type à son glyphe embarqué');
SELECT is((SELECT count(*)::int FROM hazard_type_icons), 0, 'et la ligne a disparu');

-- --- Rien sans administrateur ---------------------------------------------------------------
SELECT set_config('request.jwt.claims', '', true);
SELECT throws_ok(
  format('SELECT admin_set_hazard_icon(%L, %L)', 'pothole', 'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII='),
  '42501', NULL,
  'sans jeton, téléverser est impossible'
);

-- --- Le journal a tout vu -------------------------------------------------------------------
SELECT set_config('request.jwt.claims', '{"sub":"11111111-0000-0000-0000-000000000011"}', true);
SELECT is((SELECT count(*)::int FROM admin_actions a WHERE a.action LIKE 'type.icon.%'), 3,
          'deux téléversements et un retrait au journal, les refus n''y sont pas');

SELECT * FROM finish();
ROLLBACK;
