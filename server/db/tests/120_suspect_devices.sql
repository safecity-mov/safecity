-- L'application — repérer les terminaux à contre-courant (§4.3 amendé, 0140, 0170, 0210).
--
-- Un saboteur est quelqu'un de très actif dont l'avis va très souvent contre celui des autres,
-- collectivement. Ce test dit ce que « contredit » veut dire, ce qu'est un saut
-- géographiquement impossible, et ce que la fonction ne rend pas.
BEGIN;
SELECT no_plan();

INSERT INTO admins (user_id, email) VALUES
  ('dddddddd-0000-0000-0000-00000000000d', 'moderation@example.org');
SELECT set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-00000000000d"}', true);

CREATE TEMP TABLE d (label text PRIMARY KEY, id uuid DEFAULT gen_random_uuid());
INSERT INTO d (label) VALUES ('honnete'), ('saboteur'), ('b'), ('c'), ('e'), ('x'), ('y'),
                           ('loin1'), ('loin2'), ('teleport'), ('metro'), ('canape');
CREATE TEMP TABLE h (label text PRIMARY KEY, id uuid);

CREATE OR REPLACE FUNCTION pg_temp.dev(p text) RETURNS uuid LANGUAGE sql AS
  $$ SELECT id FROM d WHERE label = p $$;
CREATE OR REPLACE FUNCTION pg_temp.haz(p text) RETURNS uuid LANGUAGE sql AS
  $$ SELECT id FROM h WHERE label = p $$;

-- h1 : trois personnes le voient, le saboteur seul le dit résolu.
INSERT INTO h VALUES ('h1', app_test.report(pg_temp.dev('honnete'), 48.8566, 2.3522));
SELECT app_test.confirm_near(pg_temp.dev('b'), pg_temp.haz('h1'));
SELECT app_test.confirm_near(pg_temp.dev('c'), pg_temp.haz('h1'));
SELECT app_test.resolve_near(pg_temp.dev('saboteur'), pg_temp.haz('h1'));

-- h3 : inventé par le saboteur, deux personnes le disent résolu.
INSERT INTO h VALUES ('h3', app_test.report(pg_temp.dev('saboteur'), 48.8600, 2.3600));
SELECT app_test.resolve_near(pg_temp.dev('b'), pg_temp.haz('h3'));
SELECT app_test.resolve_near(pg_temp.dev('c'), pg_temp.haz('h3'));

-- h4 : du saboteur aussi, mais personne ne s'est prononcé.
INSERT INTO h VALUES ('h4', app_test.report(pg_temp.dev('saboteur'), 48.8700, 2.3700));

-- h5 : une seule personne contre l'honnête — un avis isolé ne contredit pas.
INSERT INTO h VALUES ('h5', app_test.report(pg_temp.dev('honnete'), 48.8800, 2.3800));
SELECT app_test.resolve_near(pg_temp.dev('e'), pg_temp.haz('h5'));

-- h2 : deux contre l'honnête, mais l'un des deux est banni : il ne reste qu'une voix.
INSERT INTO h VALUES ('h2', app_test.report(pg_temp.dev('honnete'), 48.8900, 2.3900));
SELECT app_test.resolve_near(pg_temp.dev('x'), pg_temp.haz('h2'));
SELECT app_test.resolve_near(pg_temp.dev('y'), pg_temp.haz('h2'));
SELECT admin_ban_device(pg_temp.dev('y'), 'vandale connu');

-- h6 : deux contre deux. Une égalité ne contredit personne.
INSERT INTO h VALUES ('h6', app_test.report(pg_temp.dev('honnete'), 48.9000, 2.4000));
SELECT app_test.confirm_near(pg_temp.dev('b'), pg_temp.haz('h6'));
SELECT app_test.resolve_near(pg_temp.dev('c'), pg_temp.haz('h6'));
SELECT app_test.resolve_near(pg_temp.dev('x'), pg_temp.haz('h6'));

-- h7 : le saboteur dit « résolu », PUIS b passe et confirme que c'est toujours là. Infirmé.
INSERT INTO h VALUES ('h7', app_test.report(pg_temp.dev('honnete'), 48.9100, 2.4100));
SELECT app_test.resolve_near(pg_temp.dev('saboteur'), pg_temp.haz('h7'));
SELECT app_test.confirm_near(pg_temp.dev('b'), pg_temp.haz('h7'));

-- h8 : b confirme d'abord, le saboteur dit « résolu » ensuite. Contredit, mais pas infirmé :
-- personne n'est repassé après lui.
INSERT INTO h VALUES ('h8', app_test.report(pg_temp.dev('honnete'), 48.9200, 2.4200));
SELECT app_test.confirm_near(pg_temp.dev('b'), pg_temp.haz('h8'));
SELECT app_test.resolve_near(pg_temp.dev('saboteur'), pg_temp.haz('h8'));

-- Deux dangers loin l'un de l'autre, Montmartre et Ivry, neuf kilomètres et demi à vol
-- d'oiseau. Chacun signalé par un terminal différent : sans cela, celui qui les créerait tous
-- les deux se téléporterait lui-même.
INSERT INTO h VALUES ('nord', app_test.report(pg_temp.dev('loin1'), 48.8900, 2.3400));
INSERT INTO h VALUES ('sud',  app_test.report(pg_temp.dev('loin2'), 48.8100, 2.3800));

-- Trois personnes disent « sur place » sur les deux. Seule l'heure les sépare.
SELECT app_test.confirm_near(pg_temp.dev('teleport'), pg_temp.haz('nord'));
SELECT app_test.confirm_near(pg_temp.dev('teleport'), pg_temp.haz('sud'));
SELECT app_test.confirm_near(pg_temp.dev('metro'), pg_temp.haz('nord'));
SELECT app_test.confirm_near(pg_temp.dev('metro'), pg_temp.haz('sud'));
-- Et une quatrième les confirme « d'ailleurs » : elle n'affirme rien sur sa position.
SELECT app_test.confirm_far(pg_temp.dev('canape'), pg_temp.haz('nord'));
SELECT app_test.confirm_far(pg_temp.dev('canape'), pg_temp.haz('sud'));

-- --- Le temps, que le jeu d'essai écrasait ------------------------------------------------
-- Tout ce qui précède est écrit dans la même transaction, donc à la même seconde : chaque
-- terminal se téléporterait d'un danger à l'autre. On étale les gestes de dix minutes, dans
-- l'ordre où ils ont été écrits — `row_number` et non `id`, parce qu'une séquence ne revient
-- pas en arrière au ROLLBACK et que le premier identifiant dépend des fichiers joués avant.
-- L'ordre relatif est conservé au geste près : c'est lui que lisent « contredit » et
-- « infirmé ».
WITH ordre AS (
  SELECT e.id, row_number() OVER (ORDER BY e.created_at, e.id) AS n FROM events e
)
UPDATE events e SET created_at = now() - interval '6 hours' + ordre.n * interval '10 minutes'
  FROM ordre WHERE ordre.id = e.id;

-- Puis les deux cas qui nous intéressent, à l'heure près. Quatre-vingt-dix secondes pour
-- neuf kilomètres et demi : trois cent soixante-quinze km/h, aucun trajet terrestre.
UPDATE events SET created_at = now() - interval '15 minutes'
 WHERE device_id = pg_temp.dev('teleport') AND hazard_id = pg_temp.haz('nord');
UPDATE events SET created_at = now() - interval '15 minutes' + interval '90 seconds'
 WHERE device_id = pg_temp.dev('teleport') AND hazard_id = pg_temp.haz('sud');

-- Les mêmes deux dangers, quarante minutes d'écart : quatorze km/h, un métro et deux marches.
UPDATE events SET created_at = now() - interval '60 minutes'
 WHERE device_id = pg_temp.dev('metro') AND hazard_id = pg_temp.haz('nord');
UPDATE events SET created_at = now() - interval '60 minutes' + interval '40 minutes'
 WHERE device_id = pg_temp.dev('metro') AND hazard_id = pg_temp.haz('sud');

-- Le terminal de canapé va aussi vite que le téléporteur, mais sans rien déclarer.
UPDATE events SET created_at = now() - interval '20 minutes'
 WHERE device_id = pg_temp.dev('canape') AND hazard_id = pg_temp.haz('nord');
UPDATE events SET created_at = now() - interval '20 minutes' + interval '90 seconds'
 WHERE device_id = pg_temp.dev('canape') AND hazard_id = pg_temp.haz('sud');

CREATE TEMP TABLE r AS SELECT * FROM admin_suspect_devices();

-- --- Un saut impossible passe devant tout le reste (0210) -------------------------------
-- C'est de l'arithmétique et non un jugement sur l'avis des autres : un terminal qui en porte
-- un ne tourne pas l'app telle qu'elle est publiée. « Contredit » et « infirmé » ont tous deux
-- une lecture innocente — un nid-de-poule rebouché, puis rouvert. Un saut, non.
SELECT is((SELECT r.id FROM r LIMIT 1),
          pg_temp.dev('teleport'), 'le téléporteur est en tête de liste, telle que la fonction la rend');

-- --- Le saboteur ressort, en tête de ceux dont les positions se tiennent ----------------
SELECT is((SELECT r.id FROM r WHERE r.jumps = 0 LIMIT 1),
          pg_temp.dev('saboteur'), 'le saboteur est en tête de ceux dont les positions se tiennent');
SELECT is((SELECT (r.gestures, r.opinions, r.contradicted) FROM r WHERE r.id = pg_temp.dev('saboteur')),
          (5::bigint, 5::bigint, 4::bigint),
          'cinq gestes, cinq avis, quatre contredits : h1, h3, h7, h8 — h4 seul ne l''est pas');
SELECT is((SELECT round(r.contradiction_rate::numeric, 2) FROM r WHERE r.id = pg_temp.dev('saboteur')),
          0.80, 'quatre avis sur cinq à contre-courant');

-- --- Un « résolu » suivi d'une confirmation : infirmé ------------------------------------
SELECT is((SELECT r.refuted FROM r WHERE r.id = pg_temp.dev('saboteur')), 1::bigint,
          'un seul « résolu » infirmé : h7, où b est repassé après lui. Sur h1 et h8, les confirmations '
          'étaient antérieures ; sur h3 c''est une création');
SELECT is((SELECT r.refuted FROM r WHERE r.id = pg_temp.dev('c')), 0::bigint,
          'c a dit « résolu » sur h3 et h6 sans que personne ne repasse : rien d''infirmé');

-- --- Les autres ne le sont pas -----------------------------------------------------------
SELECT is((SELECT (r.opinions, r.contradicted) FROM r WHERE r.id = pg_temp.dev('honnete')),
          (6::bigint, 0::bigint),
          'l''honnête : jamais plus d''une voix qui compte contre lui, égalité sur h6 — jamais contredit');
SELECT is((SELECT (r.opinions, r.contradicted) FROM r WHERE r.id = pg_temp.dev('b')),
          (5::bigint, 0::bigint),
          'b : majoritaire ou à égalité partout — jamais contredit');
SELECT is((SELECT (r.opinions, r.contradicted) FROM r WHERE r.id = pg_temp.dev('c')),
          (3::bigint, 0::bigint),
          'c : deux contre deux sur h6, personne n''est contredit dans une égalité');
SELECT is((SELECT r.banned_at IS NOT NULL FROM r WHERE r.id = pg_temp.dev('y')), true,
          'le terminal bloqué figure dans la liste, marqué comme tel');

-- --- Les sauts géographiquement impossibles (0210) ---------------------------------------
SELECT is((SELECT r.jumps FROM r WHERE r.id = pg_temp.dev('teleport')), 1::bigint,
          'un « sur place » à Montmartre puis un à Ivry en quatre-vingt-dix secondes : un saut');
SELECT ok((SELECT r.top_kmh FROM r WHERE r.id = pg_temp.dev('teleport')) BETWEEN 300 AND 450,
          'et la vitesse qu''il faudrait tenir est affichée, autour de 375 km/h');

SELECT is((SELECT r.jumps FROM r WHERE r.id = pg_temp.dev('metro')), 0::bigint,
          'les deux mêmes dangers à quarante minutes d''écart : un métro suffit, rien à signaler');
SELECT is((SELECT r.top_kmh FROM r WHERE r.id = pg_temp.dev('metro')), 0::real,
          'et aucune vitesse n''est retenue quand aucun saut ne dépasse le seuil');

SELECT is((SELECT r.jumps FROM r WHERE r.id = pg_temp.dev('canape')), 0::bigint,
          'un terminal qui dit « ailleurs » n''affirme rien sur sa position : rien à contredire');

SELECT is((SELECT count(*) FROM r WHERE r.jumps > 0), 1::bigint,
          'et personne d''autre : les gestes du jeu d''essai sont étalés dans le temps');

-- Le seuil se règle à l'appel, comme la fenêtre.
SELECT is((SELECT s.jumps FROM admin_suspect_devices(interval '24 hours', 500) s
            WHERE s.id = pg_temp.dev('teleport')), 0::bigint,
          'un seuil relevé à 500 km/h laisse passer le téléporteur');
SELECT is((SELECT s.jumps FROM admin_suspect_devices(interval '24 hours', 10) s
            WHERE s.id = pg_temp.dev('metro')), 1::bigint,
          'un seuil abaissé à 10 km/h accuse le métro : c''est bien un réglage, pas une vérité');

-- --- Rien qui relie un terminal à un danger ------------------------------------------------
-- Le saut est un total, lui aussi : un compte et une vitesse. Ni quel danger, ni où.
SELECT is((SELECT array_to_string(p.proargnames, ',') FROM pg_proc p WHERE p.proname = 'admin_suspect_devices'),
          'since,max_kmh,id,banned_at,gestures,jumps,top_kmh,opinions,contradicted,refuted,contradiction_rate,last_seen_at',
          'la fonction ne rend que des totaux par identifiant : ni danger, ni position');

-- --- La fenêtre porte sur les gestes du terminal ------------------------------------------
UPDATE events SET created_at = created_at - interval '25 hours' WHERE device_id = pg_temp.dev('e');
SELECT is((SELECT count(*) FROM admin_suspect_devices() s WHERE s.id = pg_temp.dev('e')), 0::bigint,
          'un terminal sans geste depuis 24 h n''apparaît plus');
SELECT is((SELECT count(*) FROM admin_suspect_devices(interval '48 hours') s WHERE s.id = pg_temp.dev('e')),
          1::bigint, 'mais une fenêtre plus large le retrouve');

-- --- Réservé aux administrateurs -----------------------------------------------------------
SELECT set_config('request.jwt.claims', '', true);
SELECT throws_ok('SELECT * FROM admin_suspect_devices()', '42501', NULL,
                 'sans jeton d''administrateur, rien ne sort');

SELECT * FROM finish();
ROLLBACK;
