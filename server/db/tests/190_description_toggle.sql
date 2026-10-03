-- L'application — couper la précision libre depuis la console (§4.3 amendé, 0240).
BEGIN;
SELECT no_plan();

INSERT INTO admins (user_id, email) VALUES
  ('dddddddd-0000-0000-0000-00000000000d', 'moderation@example.org');

SELECT is((SELECT s.descriptions_enabled FROM moderation_settings s WHERE s.id = 1), true,
          'par défaut, la précision est ouverte');

-- --- Ouverte : le texte passe ----------------------------------------------------------
CREATE TEMP TABLE ids AS
SELECT (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 48.8566, 2.3522,
                      2::smallint, 'Devant le 12', 1::smallint) ->> 'id')::uuid AS ouvert;
SELECT is((SELECT h.description FROM hazards h WHERE h.id = (SELECT ouvert FROM ids)),
          'Devant le 12', 'précision ouverte : le texte est gardé');

-- --- Coupée depuis la console : trace, puis plus aucun texte --------------------------------
SELECT set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-00000000000d"}', true);
UPDATE moderation_settings SET descriptions_enabled = false WHERE id = 1;

SELECT is((SELECT count(*) FROM admin_actions a WHERE a.action = 'rules.descriptions'), 1::bigint,
          'couper la précision laisse une trace nommée');
SELECT is((SELECT a.reason FROM admin_actions a WHERE a.action = 'rules.descriptions'),
          'précision libre coupée', 'avec le motif qui dit le sens du geste');
SELECT is((SELECT count(*) FROM admin_actions a WHERE a.action = 'rules.update'), 0::bigint,
          'et ce n''est pas compté comme un réglage de seuil');

CREATE TEMP TABLE tard AS
SELECT (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 48.8700, 2.3700,
                      2::smallint, 'Texte envoyé par une app en retard', 1::smallint) ->> 'id')::uuid AS id;
SELECT is((SELECT h.description FROM hazards h WHERE h.id = (SELECT id FROM tard)),
          NULL, 'précision coupée : le serveur ne garde rien, même si l''app envoie un texte');
SELECT is((SELECT (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 48.8800, 2.3800,
                                 2::smallint, 'encore', 1::smallint)) ->> 'description'),
          NULL, 'et la réponse au client ne le montre pas non plus');
SELECT is((SELECT h.description FROM hazards h WHERE h.id = (SELECT ouvert FROM ids)),
          'Devant le 12', 'les précisions déjà écrites ne sont pas effacées');
SELECT is(hazard_json((SELECT ouvert FROM ids)) ->> 'description', NULL,
          'mais l''API ne les montre plus');
SELECT is((hazard_detail((SELECT ouvert FROM ids))) ->> 'description', NULL,
          'ni dans le détail');
SELECT is((SELECT p.description FROM hazards_public p WHERE p.id = (SELECT ouvert FROM ids)), NULL,
          'ni dans la vue publique');
SELECT is((SELECT a.description FROM admin_hazards a WHERE a.id = (SELECT ouvert FROM ids)),
          'Devant le 12', 'la console, elle, voit toujours le texte, pour pouvoir l''effacer');
SELECT is((SELECT count(*) FROM hazards), 3::bigint,
          'le signalement lui-même est bien créé, seul le texte tombe');

-- --- Rouverte ------------------------------------------------------------------------------
UPDATE moderation_settings SET descriptions_enabled = true WHERE id = 1;
SELECT is((SELECT a.reason FROM admin_actions a WHERE a.action = 'rules.descriptions'
            ORDER BY a.created_at DESC, a.id DESC LIMIT 1),
          'précision libre rouverte', 'rouvrir est journalisé aussi');
SELECT is((SELECT (report_hazard(gen_random_uuid(), gen_random_uuid(), 'pothole', 48.8900, 2.3900,
                                 2::smallint, 'de retour', 1::smallint)) ->> 'description'),
          'de retour', 'rouverte : le texte repasse');
SELECT is(hazard_json((SELECT ouvert FROM ids)) ->> 'description', 'Devant le 12',
          'et les textes masqués réapparaissent tels quels');

-- --- Un seuil touché en même temps reste un réglage de seuil, nommé comme tel ------------------
UPDATE moderation_settings SET min_resolve_votes = 3 WHERE id = 1;
SELECT is((SELECT count(*) FROM admin_actions a WHERE a.action = 'rules.update'), 1::bigint,
          'un réglage de seuil garde son nom d''action');

SELECT * FROM finish();
ROLLBACK;
