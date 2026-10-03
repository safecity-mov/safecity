-- L'application — 0170 : les « résolu » infirmés par la suite (§4.3 amendé, complète 0140).
--
-- Être à contre-courant de l'histoire d'un danger est un indice. Dire « résolu » et voir
-- ensuite quelqu'un d'autre passer et confirmer que le danger est toujours là en est un bien
-- meilleur : un nid-de-poule ne réapparaît pas. L'ordre compte, et 0140 ne le regardait pas.
--
-- D'où une colonne de plus : `refuted`, le nombre de ses votes « résolu » suivis, sur le même
-- danger, d'au moins une confirmation par une autre personne. Une seule suffit — celui qui
-- vient après a le danger sous les yeux, celui qui a voté « résolu » ne l'avait pas. La liste
-- se trie sur elle d'abord. L'inverse (confirmer, puis voir les autres dire résolu) n'est pas
-- compté : c'est la vie normale d'un danger réparé.
--
-- « Ultérieur » se lit sur (created_at, id) : deux gestes dans la même seconde — un jeu
-- d'essai, une transaction de test — se départagent par leur numéro dans le journal.
DROP FUNCTION IF EXISTS admin_suspect_devices(interval);

CREATE OR REPLACE FUNCTION admin_suspect_devices(since interval DEFAULT interval '24 hours')
RETURNS TABLE (
  id                 uuid,
  banned_at          timestamptz,
  gestures           bigint,        -- tous ses gestes dans la fenêtre, retraits compris
  opinions           bigint,        -- dangers sur lesquels il a pris position
  contradicted       bigint,        -- ... dont le collectif dit le contraire (0140)
  refuted            bigint,        -- ses « résolu » suivis d'une confirmation par un autre
  contradiction_rate real,          -- contradicted / opinions, 0 sans avis
  last_seen_at       timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM current_admin();

  RETURN QUERY
  WITH collective AS (
    SELECT e.hazard_id,
           count(*) FILTER (WHERE e.type IN ('create', 'confirm'))::int AS present,
           count(*) FILTER (WHERE e.type = 'mark_resolved')::int        AS gone
      FROM events e
     WHERE e.cancelled_at IS NULL
       AND e.type IN ('create', 'confirm', 'mark_resolved')
     GROUP BY e.hazard_id
  ),
  mine AS (
    SELECT e.device_id, e.hazard_id,
           (array_agg(e.type ORDER BY e.created_at DESC, e.id DESC))[1]
             IN ('create', 'confirm')                                    AS says_present,
           count(*) FILTER (WHERE e.type IN ('create', 'confirm'))::int AS own_present,
           count(*) FILTER (WHERE e.type = 'mark_resolved')::int        AS own_gone
      FROM events e
     WHERE e.device_id IS NOT NULL
       AND e.cancelled_at IS NULL
       AND e.created_at >= now() - admin_suspect_devices.since
       AND e.type IN ('create', 'confirm', 'mark_resolved')
     GROUP BY e.device_id, e.hazard_id
  ),
  judged AS (
    SELECT m.device_id,
           CASE WHEN m.says_present THEN c.present - m.own_present
                ELSE                     c.gone    - m.own_gone    END AS with_me,
           CASE WHEN m.says_present THEN c.gone    - m.own_gone
                ELSE                     c.present - m.own_present END AS against_me
      FROM mine m
      JOIN collective c ON c.hazard_id = m.hazard_id
  ),
  refutations AS (
    -- Chaque « résolu » du terminal, et s'il a été suivi d'une confirmation d'un autre.
    SELECT r.device_id,
           EXISTS (SELECT 1 FROM events c
                    WHERE c.hazard_id = r.hazard_id
                      AND c.type = 'confirm'
                      AND c.cancelled_at IS NULL
                      AND c.device_id IS DISTINCT FROM r.device_id
                      AND (c.created_at, c.id) > (r.created_at, r.id)) AS refuted
      FROM events r
     WHERE r.device_id IS NOT NULL
       AND r.cancelled_at IS NULL
       AND r.type = 'mark_resolved'
       AND r.created_at >= now() - admin_suspect_devices.since
  ),
  activity AS (
    SELECT e.device_id, count(*) AS gestures, max(e.created_at) AS last_seen_at
      FROM events e
     WHERE e.device_id IS NOT NULL
       AND e.created_at >= now() - admin_suspect_devices.since
     GROUP BY e.device_id
  ),
  scored AS (
    SELECT a.device_id, a.gestures, a.last_seen_at,
           (SELECT count(*) FROM judged j WHERE j.device_id = a.device_id) AS opinions,
           (SELECT count(*) FROM judged j WHERE j.device_id = a.device_id
             AND j.against_me >= 2 AND j.against_me > j.with_me + 1)      AS contradicted,
           (SELECT count(*) FROM refutations f WHERE f.device_id = a.device_id AND f.refuted) AS refuted
      FROM activity a
  )
  SELECT d.id, d.banned_at, s.gestures, s.opinions, s.contradicted, s.refuted,
         CASE WHEN s.opinions = 0 THEN 0::real ELSE s.contradicted::real / s.opinions::real END,
         s.last_seen_at
    FROM scored s
    JOIN devices d ON d.id = s.device_id
   -- Les « résolu » infirmés d'abord : c'est le signal le plus sûr. Puis les contredits, la
   -- part de contradiction, l'activité.
   ORDER BY s.refuted DESC, s.contradicted DESC, 7 DESC, s.gestures DESC, s.last_seen_at DESC;
END
$$;

REVOKE ALL ON FUNCTION admin_suspect_devices(interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_suspect_devices(interval) TO admin_api;

NOTIFY pgrst, 'reload schema';
