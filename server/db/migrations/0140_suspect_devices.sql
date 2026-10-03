-- L'application — 0140 : les terminaux à contre-courant (§4.3 amendé).
--
-- Un saboteur ne se reconnaît pas à son volume de gestes : un cycliste assidu en fait autant.
-- Il se reconnaît à ce qu'il dit le contraire des autres, souvent. Cette fonction rend, pour
-- chaque terminal actif dans la fenêtre, combien de fois son avis sur un danger a été contredit
-- par le collectif.
--
-- Un « avis » : `create` ou `confirm` disent « le danger est là », `mark_resolved` dit « il n'y
-- est plus ». Sur un même danger, les avis forment deux camps ; le terminal est contredit quand
-- le camp opposé compte au moins deux personnes ET est plus nombreux que le sien, lui compris.
-- Une égalité n'est pas une contradiction : à quatre contre quatre, chacun verrait sinon quatre
-- voix contre les trois autres du sien, et tout le monde serait « contredit ». Deux avis de
-- personnes différentes valent plus que deux avis d'une même personne : c'est déjà ce que
-- garantit l'index `events_one_per_device` (un `confirm`, un `mark_resolved` par terminal et par
-- danger), et le créateur est unique. Compter les événements, c'est donc compter les personnes,
-- même une fois `device_id` effacé au bout de 24 heures (§11.2).
--
-- Les gestes d'un terminal bloqué (`cancelled_at`) ne pèsent dans aucun camp : un vandale déjà
-- banni ne fait pas passer les honnêtes pour des dissidents.
--
-- La fenêtre porte sur les gestes DU terminal : au-delà de 24 heures, ils n'ont plus de
-- terminal (0050), il n'y a donc rien à rendre de plus, quelle que soit la valeur demandée.
-- L'avis des autres, lui, est lu sur toute l'histoire du danger.
--
-- Ce qui sort : des totaux par identifiant, comme `admin_devices`. Ni danger, ni position, ni
-- heure d'un geste précis, hors le dernier — la règle du §4.3 amendé tient : on repère un
-- terminal sans jamais dessiner sa journée. Le modérateur juge ensuite depuis la carte.
CREATE OR REPLACE FUNCTION admin_suspect_devices(since interval DEFAULT interval '24 hours')
RETURNS TABLE (
  id                 uuid,
  banned_at          timestamptz,
  gestures           bigint,        -- tous ses gestes dans la fenêtre, retraits compris
  opinions           bigint,        -- dangers sur lesquels il a pris position
  contradicted       bigint,        -- ... dont le collectif dit le contraire
  contradiction_rate real,          -- contradicted / opinions, 0 sans avis
  last_seen_at       timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM current_admin();

  RETURN QUERY
  WITH collective AS (
    -- Les deux camps, sur chaque danger, toutes personnes confondues.
    SELECT e.hazard_id,
           count(*) FILTER (WHERE e.type IN ('create', 'confirm'))::int AS present,
           count(*) FILTER (WHERE e.type = 'mark_resolved')::int        AS gone
      FROM events e
     WHERE e.cancelled_at IS NULL
       AND e.type IN ('create', 'confirm', 'mark_resolved')
     GROUP BY e.hazard_id
  ),
  mine AS (
    -- La position d'un terminal sur un danger : son dernier mot. Confirmer puis marquer
    -- résolu trois heures plus tard n'est pas une contradiction, c'est un nid-de-poule
    -- rebouché ; seul le dernier avis compte, les précédents sont retirés des deux camps.
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
    -- `with_me` compte les autres voix de mon camp ; la mienne s'y ajoute à la comparaison.
    SELECT m.device_id,
           CASE WHEN m.says_present THEN c.present - m.own_present
                ELSE                     c.gone    - m.own_gone    END AS with_me,
           CASE WHEN m.says_present THEN c.gone    - m.own_gone
                ELSE                     c.present - m.own_present END AS against_me
      FROM mine m
      JOIN collective c ON c.hazard_id = m.hazard_id
  ),
  activity AS (
    SELECT e.device_id, count(*) AS gestures, max(e.created_at) AS last_seen_at
      FROM events e
     WHERE e.device_id IS NOT NULL
       AND e.created_at >= now() - admin_suspect_devices.since
     GROUP BY e.device_id
  )
  SELECT d.id,
         d.banned_at,
         a.gestures,
         count(j.device_id)                                                       AS opinions,
         count(*) FILTER (WHERE j.against_me >= 2 AND j.against_me > j.with_me + 1)   AS contradicted,
         CASE WHEN count(j.device_id) = 0 THEN 0::real
              ELSE (count(*) FILTER (WHERE j.against_me >= 2 AND j.against_me > j.with_me + 1))::real
                   / count(j.device_id)::real END                                 AS contradiction_rate,
         a.last_seen_at
    FROM activity a
    JOIN devices d ON d.id = a.device_id
    LEFT JOIN judged j ON j.device_id = a.device_id
   GROUP BY d.id, d.banned_at, a.gestures, a.last_seen_at
   -- Les plus contredits d'abord, puis la part de contradiction, puis l'activité : un
   -- terminal contredit deux fois sur deux avis passe avant un contredit deux fois sur vingt.
   ORDER BY 5 DESC, 6 DESC, 3 DESC, 7 DESC;
END
$$;

REVOKE ALL ON FUNCTION admin_suspect_devices(interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_suspect_devices(interval) TO admin_api;

NOTIFY pgrst, 'reload schema';
