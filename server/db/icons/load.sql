-- L'application — remet les silhouettes par défaut dans le catalogue, au nom d'un administrateur.
-- (Elles sont posées d'office par la migration 0160 ; ceci sert à y revenir.)
--
-- Passe par `admin_set_hazard_icon`, comme l'écran Types : mêmes contrôles (PNG carré, 32 à
-- 512 px, 64 Ko au plus) et même ligne dans le journal d'audit. Jamais d'écriture directe.
-- Un type sans fichier ici est laissé tel quel ; un fichier pour un type inconnu est ignoré.
--
-- Usage : make icons-default EMAIL=moderation@example.org   (l'admin doit exister : make admin-add)
\set ON_ERROR_STOP on
BEGIN;

SELECT set_config('request.jwt.claims',
                  json_build_object('sub', (SELECT a.user_id FROM admins a
                                             WHERE a.email = :'email' AND a.disabled_at IS NULL))::text,
                  true) AS claims;

SELECT t.code,
       admin_set_hazard_icon(t.code, encode(pg_read_binary_file('/db/icons/' || t.code || '.png'), 'base64'))
         -> 'width' AS width
  FROM hazard_types t
 WHERE EXISTS (SELECT 1 FROM pg_stat_file('/db/icons/' || t.code || '.png', true))
 ORDER BY t.sort_order;

COMMIT;
