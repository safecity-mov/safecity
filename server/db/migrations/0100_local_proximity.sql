-- L'application — le palier de proximité se calcule sur l'appareil (§6.2, §11.1).
--
-- CE QUI CHANGE, ET POURQUOI CE N'EST PAS UNE CONCESSION.
--
-- Jusqu'ici les RPC recevaient `device_lat` / `device_lng`, en déduisaient un palier sur trois
-- valeurs, et jetaient les coordonnées. La position n'était jamais écrite — mais elle
-- traversait le réseau, entrait dans le processus, et la promesse tenait à ce qu'aucun journal
-- ne l'attrape en chemin. C'est une promesse d'exploitation, vérifiable mais pas structurelle.
--
-- On pourrait croire que ce calcul côté serveur protégeait de la triche. Il n'en était rien :
-- **c'est le client qui fournissait la coordonnée**. Envoyer celle du danger lui-même donnait
-- le poids maximal depuis n'importe où — exactement aussi facile que d'annoncer « palier 1 ».
-- Déplacer le calcul ne perd donc aucune garantie d'intégrité, parce qu'il n'y en avait pas.
--
-- Ce qu'on gagne est une phrase d'une autre nature : la position ne quitte jamais l'appareil.
--
-- CE QU'IL FAUT TENIR EN ÉCHANGE.
--
-- La règle des 50 / 500 mètres ne doit pas devenir une constante de l'app, sans quoi deux
-- versions installées pondéreraient différemment. Elle vit donc en base, dans une table que
-- l'app lit au lancement comme elle lit le catalogue. Une seule définition, des deux côtés.
--
-- L'anti-abus reste reporté en phase 2 (§4.6). Quand il viendra, il devra traiter le palier
-- comme une déclaration — ce qu'il était déjà.

---------------------------------------------------------------------------
-- La règle, en données
---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS proximity_tiers (
  tier           smallint PRIMARY KEY CHECK (tier BETWEEN 1 AND 3),
  -- NULL sur le dernier palier : « au-delà », ou pas de position du tout.
  max_distance_m int,
  weight         real NOT NULL CHECK (weight > 0 AND weight <= 1)
);

INSERT INTO proximity_tiers (tier, max_distance_m, weight) VALUES
  (1, 50,   1.0),
  (2, 500,  0.5),
  (3, NULL, 0.25)
ON CONFLICT (tier) DO NOTHING;

COMMENT ON TABLE proximity_tiers IS
  'Paliers de proximité du §6.2. Lue par l''app, qui calcule le palier sur l''appareil : la '
  'position du déclarant ne quitte jamais le téléphone (§11.1).';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'proximity_tiers_distance') THEN
    ALTER TABLE proximity_tiers ADD CONSTRAINT proximity_tiers_distance
      CHECK (max_distance_m IS NULL OR max_distance_m BETWEEN 1 AND 100000);
  END IF;
END
$$;

-- Ce qu'un `CHECK` ne peut pas dire, parce que ça se lit d'une ligne à l'autre : les paliers
-- s'éloignent, et un vote émis de plus loin ne pèse jamais plus lourd. Sans ce contrôle, un
-- réglage maladroit dans la console inverserait la règle du §6.2 sans que rien ne proteste —
-- et l'app appliquerait l'inversion au prochain lancement.
--
-- Par instruction et non par ligne : la console écrit les trois paliers d'un coup, et l'état
-- n'a de sens qu'une fois les trois posés.
CREATE OR REPLACE FUNCTION proximity_tiers_coherent()
RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM proximity_tiers a JOIN proximity_tiers b ON b.tier = a.tier + 1
     WHERE a.max_distance_m IS NULL
        OR (b.max_distance_m IS NOT NULL AND b.max_distance_m <= a.max_distance_m)
  ) THEN
    RAISE EXCEPTION 'chaque palier doit porter plus loin que le précédent, et seul le dernier est sans limite'
      USING ERRCODE = 'check_violation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM proximity_tiers a JOIN proximity_tiers b ON b.tier = a.tier + 1
     WHERE b.weight > a.weight
  ) THEN
    RAISE EXCEPTION 'un vote émis de plus loin ne peut pas peser plus lourd'
      USING ERRCODE = 'check_violation';
  END IF;

  IF (SELECT max_distance_m FROM proximity_tiers WHERE tier = 3) IS NOT NULL THEN
    RAISE EXCEPTION 'le dernier palier n''a pas de limite : c''est « au-delà », ou pas de position du tout'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NULL;
END
$$;

REVOKE ALL ON FUNCTION proximity_tiers_coherent() FROM PUBLIC;

DROP TRIGGER IF EXISTS proximity_tiers_coherent_trigger ON proximity_tiers;
CREATE TRIGGER proximity_tiers_coherent_trigger
  AFTER INSERT OR UPDATE OR DELETE ON proximity_tiers
  FOR EACH STATEMENT EXECUTE FUNCTION proximity_tiers_coherent();

ALTER TABLE proximity_tiers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS proximity_tiers_read ON proximity_tiers;
CREATE POLICY proximity_tiers_read ON proximity_tiers FOR SELECT TO anon USING (true);
GRANT SELECT ON proximity_tiers TO anon;

---------------------------------------------------------------------------
-- La règle se règle depuis la console (§4.3)
---------------------------------------------------------------------------
-- Les droits d'administration vivent ici plutôt qu'en 0070 : la table naît dans ce fichier.
--
-- `INSERT` autant qu'`UPDATE` : la console écrit les trois paliers en une seule requête, par
-- l'upsert de PostgREST. Trois PATCH séparés passeraient par des états incohérents — un palier
-- déplacé plus loin que le suivant, le temps d'une requête — et le contrôle ci-dessus les
-- refuserait à juste titre.
GRANT SELECT, INSERT, UPDATE ON proximity_tiers TO admin_api;

DROP POLICY IF EXISTS proximity_tiers_admin ON proximity_tiers;
CREATE POLICY proximity_tiers_admin ON proximity_tiers
  FOR ALL TO admin_api USING (current_admin() IS NOT NULL) WITH CHECK (current_admin() IS NOT NULL);

-- Une ligne de journal par réglage, pas une par palier : les trois ne veulent rien dire
-- séparément. D'où la table de transition, et l'état complet en instantané.
CREATE OR REPLACE FUNCTION proximity_tiers_audit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_sub   text;
  v_admin uuid;
BEGIN
  -- Comme pour le catalogue : ce que fait une migration n'est pas une action d'administrateur.
  v_sub := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub';
  IF v_sub IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT a.user_id INTO v_admin
    FROM admins a WHERE a.user_id = v_sub::uuid AND a.disabled_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'administrateur inconnu ou désactivé' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO admin_actions (admin_id, action, target, reason, snapshot)
  VALUES (v_admin, 'tiers.update', 'proximity_tiers', 'réglage des paliers de proximité',
          jsonb_build_object('after', (
            SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tier) FROM proximity_tiers t)));
  RETURN NULL;
END
$$;

REVOKE ALL ON FUNCTION proximity_tiers_audit() FROM PUBLIC;

DROP TRIGGER IF EXISTS proximity_tiers_audit_trigger ON proximity_tiers;
CREATE TRIGGER proximity_tiers_audit_trigger
  AFTER INSERT OR UPDATE ON proximity_tiers
  FOR EACH STATEMENT EXECUTE FUNCTION proximity_tiers_audit();

---------------------------------------------------------------------------
-- Les fonctions lisent la table plutôt que de la répéter
---------------------------------------------------------------------------
-- Elles passent d'IMMUTABLE à STABLE : elles dépendent maintenant d'une table. Aucun index ni
-- colonne générée ne s'appuie dessus, donc rien ne s'y oppose.
DROP FUNCTION IF EXISTS report_hazard(uuid, uuid, text, double precision, double precision,
                                      smallint, text, double precision, double precision);
DROP FUNCTION IF EXISTS confirm_hazard(uuid, uuid, uuid, double precision, double precision);
DROP FUNCTION IF EXISTS mark_resolved(uuid, uuid, uuid, double precision, double precision);
DROP FUNCTION IF EXISTS record_event(uuid, uuid, uuid, event_type, double precision,
                                     double precision, jsonb);
DROP FUNCTION IF EXISTS proximity_weight(smallint);

CREATE OR REPLACE FUNCTION proximity_tier(
  hazard_geom geometry,
  device_lat  double precision,
  device_lng  double precision
) RETURNS smallint
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  -- Gardée comme **définition de référence** de la règle, et c'est elle que les tests
  -- interrogent. Les RPC ne l'appellent plus : ils reçoivent le palier déjà calculé.
  SELECT coalesce(
    (SELECT min(t.tier) FROM proximity_tiers t
      WHERE t.max_distance_m IS NOT NULL
        AND device_lat IS NOT NULL AND device_lng IS NOT NULL
        AND ST_DWithin(
              hazard_geom::geography,
              ST_SetSRID(ST_MakePoint(device_lng, device_lat), 4326)::geography,
              t.max_distance_m)),
    3::smallint);
$$;

CREATE OR REPLACE FUNCTION proximity_weight(p_tier smallint)
RETURNS real
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  -- Un palier inconnu vaut le moins : mieux vaut sous-pondérer que sur-pondérer.
  SELECT coalesce((SELECT t.weight FROM proximity_tiers t WHERE t.tier = p_tier), 0.25::real);
$$;

---------------------------------------------------------------------------
-- L'écriture du journal prend un palier, plus des coordonnées
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION record_event(
  p_client_id uuid,
  p_hazard_id uuid,
  p_device_id uuid,
  p_type      event_type,
  p_proximity smallint DEFAULT 3,
  p_payload   jsonb DEFAULT NULL
) RETURNS smallint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_tier smallint := coalesce(p_proximity, 3::smallint);
BEGIN
  IF v_tier NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'palier de proximité hors bornes : %', v_tier USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO events (client_id, hazard_id, device_id, type, proximity, weight, payload)
  VALUES (p_client_id, p_hazard_id, p_device_id, p_type, v_tier, proximity_weight(v_tier), p_payload)
  ON CONFLICT DO NOTHING;

  RETURN v_tier;
END
$$;

---------------------------------------------------------------------------
-- Les trois gestes qui portaient une position
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION report_hazard(
  client_id   uuid,
  device_id   uuid,
  type        text,
  lat         double precision,
  lng         double precision,
  severity    smallint,
  description text DEFAULT NULL,
  proximity   smallint DEFAULT 3
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_existing  uuid;
  v_geom      geometry(Point, 4326);
  v_radius    int;
  v_enabled   bool;
  v_dup       record;
  v_hazard    uuid;
BEGIN
  -- Rejeu d'une action hors-ligne : on renvoie l'état, jamais un doublon (§10).
  SELECT e.hazard_id INTO v_existing
    FROM events e WHERE e.client_id = report_hazard.client_id;
  IF FOUND THEN
    RETURN hazard_json(v_existing);
  END IF;

  SELECT ht.enabled, ht.dedup_radius_m INTO v_enabled, v_radius
    FROM hazard_types ht WHERE ht.code = report_hazard.type;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'type de danger inconnu : %', report_hazard.type USING ERRCODE = 'foreign_key_violation';
  END IF;
  -- `enabled` pilote la création, jamais l'affichage (§4.3).
  IF NOT v_enabled THEN
    RAISE EXCEPTION 'type de danger désactivé : %', report_hazard.type USING ERRCODE = 'check_violation';
  END IF;

  IF report_hazard.severity NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'gravité hors bornes : %', report_hazard.severity USING ERRCODE = 'check_violation';
  END IF;
  IF char_length(coalesce(report_hazard.description, '')) > 140 THEN
    RAISE EXCEPTION 'commentaire limité à 140 caractères' USING ERRCODE = 'check_violation';
  END IF;

  v_geom := ST_SetSRID(ST_MakePoint(report_hazard.lng, report_hazard.lat), 4326);

  -- Anti-doublon : même type, danger encore visible, dans le rayon du type.
  SELECT h.id,
         round(ST_Distance(h.geom::geography, v_geom::geography)::numeric, 1) AS distance_m
    INTO v_dup
    FROM hazards h
   WHERE h.type = report_hazard.type
     AND h.status IN ('active', 'disputed')
     AND ST_DWithin(h.geom::geography, v_geom::geography, v_radius)
   ORDER BY h.geom <-> v_geom
   LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'duplicate_of', v_dup.id,
      'distance_m',   v_dup.distance_m,
      'hazard',       hazard_json(v_dup.id)
    );
  END IF;

  PERFORM assert_not_banned(report_hazard.device_id);
  PERFORM ensure_device(report_hazard.device_id);

  INSERT INTO hazards (type, geom, severity, description, created_by)
  VALUES (report_hazard.type, v_geom, report_hazard.severity,
          nullif(report_hazard.description, ''), report_hazard.device_id)
  RETURNING hazards.id INTO v_hazard;

  PERFORM record_event(report_hazard.client_id, v_hazard, report_hazard.device_id, 'create',
                       report_hazard.proximity);

  RETURN hazard_json(v_hazard);
END
$$;

CREATE OR REPLACE FUNCTION confirm_hazard(
  client_id uuid,
  id        uuid,
  device_id uuid,
  proximity smallint DEFAULT 3
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_status hazard_status;
BEGIN
  -- Sérialise les votes concurrents : le quorum du §6.1 se lit sur un journal stable.
  SELECT h.status INTO v_status FROM hazards h WHERE h.id = confirm_hazard.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger % introuvable', confirm_hazard.id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_status IN ('removed', 'archived') THEN
    RAISE EXCEPTION 'danger % non confirmable (statut %)', confirm_hazard.id, v_status
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM assert_not_banned(confirm_hazard.device_id);
  PERFORM ensure_device(confirm_hazard.device_id);
  -- Un « confirmer » pendant `disputed` ramène à `active` et annule le poids « résolu » :
  -- c'est recompute_hazard() qui l'applique, en ne comptant que les votes postérieurs (§6.1).
  PERFORM record_event(confirm_hazard.client_id, confirm_hazard.id, confirm_hazard.device_id,
                       'confirm', confirm_hazard.proximity);

  RETURN hazard_json(confirm_hazard.id);
END
$$;

CREATE OR REPLACE FUNCTION mark_resolved(
  client_id uuid,
  id        uuid,
  device_id uuid,
  proximity smallint DEFAULT 3
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_status hazard_status;
BEGIN
  SELECT h.status INTO v_status FROM hazards h WHERE h.id = mark_resolved.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger % introuvable', mark_resolved.id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_status IN ('removed', 'archived') THEN
    RAISE EXCEPTION 'danger % déjà retiré (statut %)', mark_resolved.id, v_status
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM assert_not_banned(mark_resolved.device_id);
  PERFORM ensure_device(mark_resolved.device_id);
  PERFORM record_event(mark_resolved.client_id, mark_resolved.id, mark_resolved.device_id,
                       'mark_resolved', mark_resolved.proximity);

  RETURN hazard_json(mark_resolved.id);
END
$$;

---------------------------------------------------------------------------
-- Droits
---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION record_event(uuid, uuid, uuid, event_type, smallint, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION report_hazard(uuid, uuid, text, double precision, double precision,
                                        smallint, text, smallint)   TO anon;
GRANT EXECUTE ON FUNCTION confirm_hazard(uuid, uuid, uuid, smallint) TO anon;
GRANT EXECUTE ON FUNCTION mark_resolved(uuid, uuid, uuid, smallint)  TO anon;
GRANT EXECUTE ON FUNCTION proximity_tier(geometry, double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION proximity_weight(smallint) TO anon;

NOTIFY pgrst, 'reload schema';
