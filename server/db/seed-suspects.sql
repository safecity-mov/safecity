-- L'application — jeu d'essai pour l'écran « Terminaux, à contre-courant » (0140).
-- **Jamais sur la base de production.**
--
-- Une journée de bêta avec une centaine de gestes et des personnages reconnaissables à leur
-- identifiant :
--
--   5ab00001-…  le saboteur flagrant : invente trois dangers, dit « résolu » sur huit vrais
--   5ab00002-…  le saboteur discret : confirme les inventions du premier, en conteste trois vrais
--   ac71f000-…  l'assidu : le plus actif de tous, toujours avec la majorité
--   c0c0c001-…  le réparateur : dit « résolu » sur deux dangers vraiment rebouchés, se trompe une fois
--   bad00000-…  un vandale déjà bloqué : ses gestes ne pèsent plus dans aucun camp
--   0000000N-…  six déclarants ordinaires, plus une vingtaine d'anonymes de passage
--
-- Attendu dans la console (Terminaux → « actifs ces 24 h, à contre-courant d'abord ») :
-- les deux saboteurs en tête, tous leurs avis contredits, et chacun un « résolu » infirmé
-- (un ordinaire est repassé confirmer après eux) ; le réparateur avec un seul contredit ; le
-- déclarant et les deux confirmateurs du « petit affaissement » rebouché avec un chacun — la
-- limite que la console annonce : un danger vraiment réparé contredit une fois ceux qui
-- l'avaient vu ; l'assidu à zéro malgré son volume ; le bloqué marqué comme tel.
--
--   make seed-suspects
--
-- Joué aussi par run-tests.sh, sur la base jetable, pour qu'il ne rouille pas.
BEGIN;

TRUNCATE events, photos, hazards, devices CASCADE;

-- Un terminal neuf ne peut pas dire « résolu » pendant un quart d'heure (0190) : ici tout le
-- monde est là depuis la veille.
CREATE FUNCTION pg_temp.aged(p uuid DEFAULT gen_random_uuid()) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO devices (id, created_at) VALUES (p, now() - interval '1 day') ON CONFLICT (id) DO NOTHING;
  SELECT p;
$$;

DO $$
DECLARE
  s1 uuid := '5ab00001-0000-4000-8000-000000000001';
  s2 uuid := '5ab00002-0000-4000-8000-000000000002';
  va uuid := 'ac71f000-0000-4000-8000-000000000003';
  lr uuid := 'c0c0c001-0000-4000-8000-000000000004';
  bd uuid := 'bad00000-0000-4000-8000-000000000005';
  h  uuid[] := ARRAY['00000001-0000-4000-8000-000000000011', '00000002-0000-4000-8000-000000000012',
                     '00000003-0000-4000-8000-000000000013', '00000004-0000-4000-8000-000000000014',
                     '00000005-0000-4000-8000-000000000015', '00000006-0000-4000-8000-000000000016']::uuid[];
  r  uuid[];  -- les vrais dangers, dans l'ordre
  f  uuid[];  -- les inventions du saboteur
  v_id uuid;
  i int;
  p record;
BEGIN
  PERFORM pg_temp.aged(x) FROM unnest(ARRAY[s1, s2, va, lr, bd] || h) AS x;

  -- --- Douze vrais dangers, déclarés par les six ordinaires et l'assidu -------------------
  FOR p IN
    SELECT * FROM (VALUES
      ( 1, 48.85920, 2.34200, 3, 'Trou profond en sortie de virage'),
      ( 2, 48.85935, 2.34580, 2, NULL),
      ( 3, 48.85950, 2.35010, 1, 'Petit affaissement'),
      ( 4, 48.85965, 2.35440, 3, 'Bord de plaque, dangereux sous la pluie'),
      ( 5, 48.86340, 2.35090, 2, 'Sur la bande cyclable, au feu'),
      ( 6, 48.86610, 2.35150, 2, NULL),
      ( 7, 48.86880, 2.35210, 1, NULL),
      ( 8, 48.87150, 2.36480, 3, 'Nid-de-poule large'),
      ( 9, 48.87420, 2.36620, 2, NULL),
      (10, 48.85780, 2.37920, 2, 'Rainure mal rebouchée'),
      (11, 48.86020, 2.37340, 1, NULL),
      (12, 48.86260, 2.36760, 3, 'Deux trous côte à côte')
    ) AS t(n, lat, lng, severity, description) ORDER BY n
  LOOP
    -- Les trois derniers sont de l'assidu, les autres tournent sur les six ordinaires.
    v_id := (report_hazard(gen_random_uuid(),
                           CASE WHEN p.n > 9 THEN va ELSE h[((p.n - 1) % 6) + 1] END,
                           'pothole', p.lat, p.lng, p.severity::smallint, p.description,
                           1::smallint) ->> 'id')::uuid;
    r := array_append(r, v_id);
  END LOOP;

  -- --- Le fond : des anonymes de passage confirment, deux ou trois par danger -------------
  FOR i IN 1..12 LOOP
    PERFORM confirm_hazard(gen_random_uuid(), r[i], gen_random_uuid(), 1::smallint);
    PERFORM confirm_hazard(gen_random_uuid(), r[i], gen_random_uuid(), 2::smallint);
    IF i % 2 = 0 THEN
      PERFORM confirm_hazard(gen_random_uuid(), r[i], gen_random_uuid(), 1::smallint);
    END IF;
  END LOOP;

  -- Les ordinaires confirment aussi les dangers des autres, une ou deux fois chacun.
  FOR i IN 1..6 LOOP
    PERFORM confirm_hazard(gen_random_uuid(), r[((i + 2) % 12) + 1], h[i], 1::smallint);
    IF i <= 3 THEN
      PERFORM confirm_hazard(gen_random_uuid(), r[((i + 6) % 12) + 1], h[i], 2::smallint);
    END IF;
  END LOOP;

  -- --- L'assidu : sept confirmations, toutes sur des dangers que d'autres voient aussi ------
  FOR i IN 1..9 LOOP
    IF i NOT IN (3, 7) THEN
      PERFORM confirm_hazard(gen_random_uuid(), r[i], va, 1::smallint);
    END IF;
  END LOOP;

  -- --- Deux dangers vraiment rebouchés : l'assidu, le réparateur et un passant le disent ---
  -- r[3] a le déclarant et deux confirmations, r[7] une de plus : quatre voix « il n'y est
  -- plus » contre trois, puis contre quatre. Sur r[3], les trois qui l'avaient vu sont
  -- contredits une fois — un vrai nid-de-poule rebouché, c'est à ça que ça ressemble. Sur
  -- r[7], égalité : personne. Dans les deux cas le seuil bascule.
  FOREACH v_id IN ARRAY ARRAY[r[3], r[7]] LOOP
    PERFORM mark_resolved(gen_random_uuid(), v_id, va, 1::smallint);
    PERFORM mark_resolved(gen_random_uuid(), v_id, lr, 1::smallint);
    PERFORM mark_resolved(gen_random_uuid(), v_id, pg_temp.aged(), 1::smallint);
    PERFORM mark_resolved(gen_random_uuid(), v_id, pg_temp.aged(), 1::smallint);
  END LOOP;

  -- Le réparateur confirme un danger, et se trompe une fois : r[8] (large, trois confirmations).
  PERFORM confirm_hazard(gen_random_uuid(), r[10], lr, 1::smallint);
  PERFORM mark_resolved(gen_random_uuid(), r[8], lr, 1::smallint);

  -- --- Le saboteur flagrant --------------------------------------------------------------
  -- Trois inventions, au milieu de nulle part.
  FOR p IN
    SELECT * FROM (VALUES
      (48.86500, 2.34000, 3, 'Énorme trou !!!'),
      (48.86700, 2.34300, 3, 'Route défoncée'),
      (48.86900, 2.34600, 2, NULL)
    ) AS t(lat, lng, severity, description)
  LOOP
    v_id := (report_hazard(gen_random_uuid(), s1, 'pothole', p.lat, p.lng,
                           p.severity::smallint, p.description, 1::smallint) ->> 'id')::uuid;
    f := array_append(f, v_id);
  END LOOP;
  -- « Résolu » sur huit vrais dangers, tous vus par trois personnes au moins.
  FOR i IN 1..8 LOOP
    IF i NOT IN (3, 7) THEN
      PERFORM mark_resolved(gen_random_uuid(), r[i], s1, 1::smallint);
    END IF;
  END LOOP;
  PERFORM mark_resolved(gen_random_uuid(), r[9],  s1, 1::smallint);
  PERFORM mark_resolved(gen_random_uuid(), r[10], s1, 1::smallint);

  -- Un « résolu » du flagrant sur r[11], puis un ordinaire repasse et confirme : infirmé.
  -- (Même chose pour le discret sur r[12], plus bas.)
  PERFORM mark_resolved(gen_random_uuid(), r[11], s1, 1::smallint);
  PERFORM confirm_hazard(gen_random_uuid(), r[11], h[2], 1::smallint);

  -- --- Le saboteur discret : confirme les inventions, conteste trois vrais ------------------
  FOR i IN 1..3 LOOP
    PERFORM confirm_hazard(gen_random_uuid(), f[i], s2, 1::smallint);
  END LOOP;
  PERFORM mark_resolved(gen_random_uuid(), r[1],  s2, 1::smallint);
  PERFORM mark_resolved(gen_random_uuid(), r[4],  s2, 1::smallint);
  PERFORM mark_resolved(gen_random_uuid(), r[12], s2, 1::smallint);
  PERFORM confirm_hazard(gen_random_uuid(), r[12], h[5], 1::smallint);

  -- --- Les ordinaires et un passant passent devant les inventions : rien à voir --------------
  -- Trois voix contre les deux saboteurs qui font bloc : à deux contre deux, l'ordinaire
  -- serait « contredit » — c'est la règle, deux personnes valent un collectif.
  FOR i IN 1..3 LOOP
    PERFORM mark_resolved(gen_random_uuid(), f[i], h[i],     1::smallint);
    PERFORM mark_resolved(gen_random_uuid(), f[i], h[i + 3], 1::smallint);
    PERFORM mark_resolved(gen_random_uuid(), f[i], pg_temp.aged(), 1::smallint);
  END LOOP;
  PERFORM mark_resolved(gen_random_uuid(), f[1], lr, 1::smallint);

  -- --- Un vandale déjà bloqué : quatre « résolu », neutralisés ----------------------------
  FOR i IN 9..12 LOOP
    PERFORM mark_resolved(gen_random_uuid(), r[i], bd, 1::smallint);
  END LOOP;
  -- Ce que ferait admin_ban_device, sans administrateur sous la main dans un seed : le
  -- terminal est marqué, ses gestes cessent de compter. Rien n'est écrit dans admin_actions.
  UPDATE devices SET banned_at = now() - interval '3 hours' WHERE id = bd;
  UPDATE events  SET cancelled_at = now() - interval '3 hours' WHERE device_id = bd;
END
$$;

-- Étaler la journée : chaque danger reçoit une heure de naissance dans les vingt dernières
-- heures, et ses gestes se suivent de quelques minutes, dans l'ordre où ils ont été joués.
WITH naissance AS (
  SELECT h.id, now() - (interval '20 hours') * random() - interval '2 hours' AS t
    FROM hazards h
)
UPDATE hazards h SET created_at = n.t, last_confirmed_at = n.t FROM naissance n WHERE n.id = h.id;

UPDATE events e
   SET created_at = h.created_at + (interval '7 minutes') * x.rang
  FROM hazards h,
       (SELECT id, row_number() OVER (PARTITION BY hazard_id ORDER BY id) - 1 AS rang FROM events) x
 WHERE h.id = e.hazard_id AND x.id = e.id;

COMMIT;

SELECT status, count(*) FROM hazards GROUP BY status ORDER BY 1;
SELECT count(*) AS gestes FROM events;
