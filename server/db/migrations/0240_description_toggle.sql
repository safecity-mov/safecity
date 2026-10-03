-- L'application — 0240 : couper la précision libre depuis la console (§4.3 amendé).
--
-- Le texte libre d'un signalement est la seule chose publique et définitive que l'app laisse
-- écrire (§11.2). Tant que la modération se fait à la main, un modérateur doit pouvoir le
-- fermer d'un geste, le temps d'une vague d'insultes ou pour toute la bêta, sans attendre une
-- version de l'app.
--
-- Un réglage de plus dans `moderation_settings`, lu par l'app avec les autres : quand il est à
-- faux, l'app n'offre plus le champ, et le serveur ne garde aucun texte, quoi que lui envoie
-- une app qui n'aurait pas encore relu la règle. Le client déclare, le serveur décide. Les
-- précisions déjà écrites ne sont pas effacées, mais plus montrées : l'API publique les rend
-- nulles tant que le réglage est à faux, et les rend telles quelles dès qu'il repasse à vrai.
-- Les administrateurs continuent de les voir, pour pouvoir en effacer une
-- (`admin_clear_hazard_description`, 0150).

ALTER TABLE moderation_settings
  ADD COLUMN IF NOT EXISTS descriptions_enabled boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN moderation_settings.descriptions_enabled IS
  'À faux, l''app n''offre plus le champ « Précision », le serveur n''enregistre aucun texte '
  'sur les nouveaux signalements (trigger hazards_description_gate), et l''API publique '
  '(hazard_json, hazards_public) masque les textes existants sans les effacer.';

-- Le verrou est posé sur la table, pas dans report_hazard : il vaut pour tout chemin d'écriture,
-- présent ou futur, et report_hazard n'a pas à être recopié pour une ligne.
CREATE OR REPLACE FUNCTION hazards_description_gate()
RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.description IS NOT NULL
     AND NOT (SELECT s.descriptions_enabled FROM moderation_settings s WHERE s.id = 1) THEN
    NEW.description := NULL;
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS hazards_description_gate_trigger ON hazards;
CREATE TRIGGER hazards_description_gate_trigger
  BEFORE INSERT OR UPDATE OF description ON hazards
  FOR EACH ROW EXECUTE FUNCTION hazards_description_gate();

-- Le journal d'audit nomme le geste : couper le texte libre n'est pas « régler un seuil », et un
-- modérateur qui relit le journal doit le voir sans ouvrir le snapshot.
CREATE OR REPLACE FUNCTION moderation_settings_audit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_sub    text;
  v_admin  uuid;
  v_action text := 'rules.update';
  v_reason text := 'réglage des seuils de résolution';
BEGIN
  v_sub := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub';
  IF v_sub IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT a.user_id INTO v_admin
    FROM admins a WHERE a.user_id = v_sub::uuid AND a.disabled_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'administrateur inconnu ou désactivé' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF OLD.descriptions_enabled IS DISTINCT FROM NEW.descriptions_enabled THEN
    v_action := 'rules.descriptions';
    v_reason := CASE WHEN NEW.descriptions_enabled
                     THEN 'précision libre rouverte'
                     ELSE 'précision libre coupée' END;
  END IF;

  INSERT INTO admin_actions (admin_id, action, target, reason, snapshot)
  VALUES (v_admin, v_action, 'moderation_settings', v_reason,
          jsonb_build_object('before', to_jsonb(OLD), 'after', to_jsonb(NEW)));
  RETURN NULL;
END
$$;

-- Ce que l'API publique montre : la même sérialisation qu'en 0200, la précision en moins quand
-- elle est coupée. `admin_hazards` ne change pas : un modérateur doit voir pour effacer.
CREATE OR REPLACE FUNCTION hazard_json(p_hazard uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'id',                h.id,
    'type',              h.type,
    'lat',               ST_Y(h.geom),          -- pleine précision, aucun arrondi (§11.6)
    'lng',               ST_X(h.geom),
    'severity',          h.severity,
    'status',            h.status,
    'description',       CASE WHEN s.descriptions_enabled THEN h.description END,
    'address',           h.address,
    'created_at',        h.created_at,
    'last_confirmed_at', h.last_confirmed_at,
    'confirm_weight',    h.confirm_weight,
    'confirmations',     round(h.confirm_weight)::int,   -- compatibilité, voir 0200
    'resolve_weight',    h.resolve_weight,
    'resolve_threshold', resolve_threshold(h.confirm_weight, s.min_resolve_votes,
                                           s.confirmations_per_resolve_vote, s.max_resolve_votes),
    'reported_remotely', EXISTS (
       SELECT 1 FROM events e
        WHERE e.hazard_id = h.id AND e.type = 'create' AND e.proximity = 2
          AND e.cancelled_at IS NULL
    )
  )
  FROM hazards h
  CROSS JOIN moderation_settings s
  WHERE h.id = p_hazard AND s.id = 1;
$$;

CREATE OR REPLACE VIEW hazards_public AS
  SELECT h.id, h.type, ST_Y(h.geom) AS lat, ST_X(h.geom) AS lng,
         h.severity, h.status,
         CASE WHEN s.descriptions_enabled THEN h.description END AS description,
         h.address,
         h.created_at, h.last_confirmed_at, h.confirm_weight, h.resolve_weight
    FROM hazards h
   CROSS JOIN moderation_settings s
   WHERE h.status IN ('active', 'disputed') AND s.id = 1;
