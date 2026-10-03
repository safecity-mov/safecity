-- L'application — 0210 : les sauts géographiquement impossibles (§4.3 amendé, complète 0170).
--
-- Un testeur a signalé qu'un émulateur Android — BlueStacks et les autres — permet de régler
-- sa position au clic et de lancer dix instances. C'est vrai, et ce n'était déjà pas le chemin
-- le plus court : l'API est ouverte, sans compte ni clé (§4), donc un `curl` avec
-- `proximity = 1` et un UUID tiré au hasard fait la même chose en une ligne. Le §6.2 l'assume
-- depuis le début : le palier est une **déclaration** du client, et le calculer côté serveur
-- n'apportait aucune garantie d'intégrité.
--
-- Ce qu'une déclaration ne peut pas falsifier, en revanche, c'est la géométrie de ce qu'elle
-- affirme. Dire « j'étais sur place » à Montmartre, puis « j'étais sur place » à Ivry
-- quatre-vingt-dix secondes plus tard, c'est se contredire soi-même : il n'existe aucun trajet
-- qui relie les deux. Et cela se lit avec ce que le serveur garde déjà — la position des
-- **dangers**, pleine précision (§11.6), et l'heure des gestes.
--
-- **Aucune position de personne n'entre ici.** Le calcul ne connaît que des positions de
-- dangers, celles-là mêmes que l'app affiche à tout le monde. Rien de nouveau n'est stocké : la
-- colonne ajoutée n'existe pas, tout se calcule à la lecture, et la fenêtre de 24 heures est
-- celle du §11.2 — passé ce délai, `device_id` est à `NULL` et il n'y a plus rien à recouper.
--
-- **Cet écran signale, il n'agit pas.** Le geste part normalement, il pèse son poids normal, et
-- c'est un humain qui bloque avec un motif, journalisé comme le reste (§4.3). L'anti-abus
-- automatique — refuser, repondérer, shadow-ban — reste en phase 2 (§4.6) : un saut impossible
-- prouve qu'un terminal ne tourne pas l'app telle qu'elle est publiée, pas que son signalement
-- soit faux, et une position falsifiée peut être un choix de vie privée plutôt qu'un sabotage.
-- C'est exactement pourquoi la décision reste humaine.
--
-- **Le seuil est à 50 km/h, et c'est une vitesse à vol d'oiseau.** ST_Distance sur des
-- geography mesure la ligne droite, alors qu'un trajet réel en ville est plus long d'environ un
-- tiers : 50 km/h en ligne droite, c'est donc de l'ordre de 65 à 70 km/h parcourus. Le vélo
-- (15), le métro de porte à porte (20), le RER (40) passent tous ; la téléportation ne passe
-- pas. Réglable à l'appel, comme la fenêtre.

DROP FUNCTION IF EXISTS admin_suspect_devices(interval);

CREATE OR REPLACE FUNCTION admin_suspect_devices(
  since   interval DEFAULT interval '24 hours',
  max_kmh real     DEFAULT 50
)
RETURNS TABLE (
  id                 uuid,
  banned_at          timestamptz,
  gestures           bigint,        -- tous ses gestes dans la fenêtre, retraits compris
  jumps              bigint,        -- ses enchaînements « sur place » physiquement impossibles
  top_kmh            real,          -- le pire d'entre eux, en km/h à vol d'oiseau ; 0 s'il n'y en a pas
  opinions           bigint,        -- dangers sur lesquels il a pris position
  contradicted       bigint,        -- ... dont le collectif dit le contraire (0140)
  refuted            bigint,        -- ses « résolu » suivis d'une confirmation par un autre (0170)
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
  -- Chaque enchaînement de deux gestes déclarés « sur place », par terminal, dans l'ordre du
  -- journal : deux positions de danger et deux horodatages donnent une vitesse.
  --
  -- Seuls les paliers 1 comptent. Un terminal qui dit « ailleurs » n'affirme rien sur sa
  -- position, il n'a donc rien à se contredire ; et un « ailleurs » intercalé entre deux
  -- « sur place » ne change pas le trajet que les deux impliquent, d'où le `lag` sur les
  -- paliers 1 seulement.
  hops AS (
    SELECT p.device_id,
           ST_Distance(p.geom::geography, p.prev_geom::geography)
             -- Plancher d'une seconde : deux gestes dans la même seconde diviseraient par
             -- zéro, et une vitesse infinie ne se sérialise pas en JSON. Le chiffre reste
             -- énorme, ce qui est bien ce qu'on veut dire.
             / greatest(extract(epoch FROM (p.created_at - p.prev_at)), 1)::double precision
             * 3.6 AS kmh
      FROM (
        SELECT e.device_id, h.geom, e.created_at,
               lag(h.geom)       OVER w AS prev_geom,
               lag(e.created_at) OVER w AS prev_at
          FROM events e
          JOIN hazards h ON h.id = e.hazard_id
         WHERE e.device_id IS NOT NULL
           AND e.cancelled_at IS NULL
           AND e.proximity = 1
           AND e.created_at >= now() - admin_suspect_devices.since
        WINDOW w AS (PARTITION BY e.device_id ORDER BY e.created_at, e.id)
      ) p
     WHERE p.prev_geom IS NOT NULL
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
           (SELECT count(*) FROM refutations f WHERE f.device_id = a.device_id AND f.refuted) AS refuted,
           (SELECT count(*) FROM hops p WHERE p.device_id = a.device_id
             AND p.kmh > admin_suspect_devices.max_kmh)                   AS jumps,
           (SELECT coalesce(max(p.kmh), 0)::real FROM hops p WHERE p.device_id = a.device_id
             AND p.kmh > admin_suspect_devices.max_kmh)                   AS top_kmh
      FROM activity a
  ),
  rated AS (
    SELECT s.*,
           CASE WHEN s.opinions = 0 THEN 0::real
                ELSE s.contradicted::real / s.opinions::real END AS rate
      FROM scored s
  )
  SELECT d.id, d.banned_at, r.gestures, r.jumps, r.top_kmh,
         r.opinions, r.contradicted, r.refuted, r.rate, r.last_seen_at
    FROM rated r
    JOIN devices d ON d.id = r.device_id
   -- Les sauts impossibles d'abord : c'est de l'arithmétique, pas un jugement sur l'avis des
   -- autres — un terminal qui en porte un ne tourne pas l'app telle qu'elle est publiée. Puis
   -- les « résolu » infirmés, les contredits, la part de contradiction, l'activité.
   ORDER BY r.jumps DESC, r.refuted DESC, r.contradicted DESC, r.rate DESC,
            r.gestures DESC, r.last_seen_at DESC;
END
$$;

COMMENT ON FUNCTION admin_suspect_devices(interval, real) IS
  'Terminaux actifs dans la fenêtre, les plus suspects d''abord (§4.3 amendé). Ne rend que des '
  'totaux par identifiant : ni danger, ni position. `jumps` compte les enchaînements de deux '
  'gestes « sur place » que nulle vitesse terrestre ne relie, `max_kmh` étant le seuil en km/h '
  'à vol d''oiseau. Signale seulement : c''est un humain qui bloque, avec un motif (§4.6).';

REVOKE ALL ON FUNCTION admin_suspect_devices(interval, real) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_suspect_devices(interval, real) TO admin_api;

NOTIFY pgrst, 'reload schema';
