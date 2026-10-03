-- L'application — jeu d'essai pour le développement. **Jamais sur la base de production** :
-- la carte démarre vide, sans aucun import (§4.4).
--
-- Points répartis sur les axes cyclables visés par le pilote (§4.4) : rue de Rivoli,
-- boulevard de Sébastopol, canal Saint-Martin, boulevard Voltaire.
--
--   make seed
--   (ou : docker compose exec -T db psql -U postgres -d app -f /db/seed-demo.sql)
--
-- Joué aussi par run-tests.sh, sur la base jetable : un seed qui ne suit plus les signatures
-- des RPC casse au premier appel, et il vaut mieux l'apprendre là que sur une base vidée.

-- Une seule transaction : le TRUNCATE et les insertions tiennent ou tombent ensemble. Sans
-- cela, un appel qui échoue après le TRUNCATE laisse une base de développement vide.
BEGIN;

-- Rejouable : on repart d'une carte vide. Sans cela, un second passage retombe sur
-- un danger laissé « removed » par le passage précédent et s'interrompt au milieu.
TRUNCATE events, photos, hazards, devices CASCADE;

DO $$
DECLARE
  v_device uuid;
  v_hazard uuid;
  v_point  record;
BEGIN
  FOR v_point IN
    SELECT * FROM (VALUES
      -- rue de Rivoli
      (48.85920, 2.34200, 3, 'Trou profond en sortie de virage'),
      (48.85935, 2.34580, 2, NULL),
      (48.85950, 2.35010, 1, 'Petit affaissement, gênant en danseuse'),
      (48.85965, 2.35440, 3, 'Bord de plaque, dangereux sous la pluie'),
      -- boulevard de Sébastopol
      (48.86340, 2.35090, 2, 'Sur la bande cyclable, au niveau du feu'),
      (48.86610, 2.35150, 2, NULL),
      (48.86880, 2.35210, 1, NULL),
      -- canal Saint-Martin
      (48.87150, 2.36480, 3, 'Nid-de-poule large, à éviter'),
      (48.87420, 2.36620, 2, NULL),
      -- boulevard Voltaire
      (48.85780, 2.37920, 2, 'Rainure de tramway mal rebouchée'),
      (48.86020, 2.37340, 1, NULL),
      (48.86260, 2.36760, 3, 'Deux trous côte à côte')
    ) AS t(lat, lng, severity, description)
  LOOP
    v_device := gen_random_uuid();
    -- Palier 1 : signalé sur place, comme le ferait l'app depuis 0100.
    v_hazard := (report_hazard(
      gen_random_uuid(), v_device, 'pothole',
      v_point.lat, v_point.lng, v_point.severity::smallint, v_point.description,
      1::smallint
    ) ->> 'id')::uuid;

    -- Quelques confirmations, pour que les compteurs et le seuil dynamique
    -- aient des valeurs réalistes à l'écran.
    IF v_point.severity >= 2 THEN
      PERFORM confirm_hazard(gen_random_uuid(), v_hazard, gen_random_uuid(), 1::smallint);
    END IF;
    IF v_point.severity = 3 THEN
      PERFORM confirm_hazard(gen_random_uuid(), v_hazard, gen_random_uuid(), 1::smallint);
      PERFORM confirm_hazard(gen_random_uuid(), v_hazard, gen_random_uuid(), 1::smallint);
    END IF;
  END LOOP;

  -- Un danger contesté, pour voir le marqueur creux et le bandeau du détail.
  SELECT h.id INTO v_hazard
    FROM hazards h WHERE h.status = 'active' ORDER BY h.created_at LIMIT 1;
  -- Un terminal neuf ne peut pas dire « résolu » pendant un quart d'heure (0190) : celui-ci
  -- est là depuis la veille.
  v_device := gen_random_uuid();
  INSERT INTO devices (id, created_at) VALUES (v_device, now() - interval '1 day');
  PERFORM mark_resolved(gen_random_uuid(), v_hazard, v_device, 1::smallint);
END
$$;

COMMIT;

SELECT status, count(*) FROM hazards GROUP BY status ORDER BY 1;
