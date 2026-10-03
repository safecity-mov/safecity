-- L'application — administration de la bêta (SPEC §4.3, avancé depuis la phase 2).
--
-- Le §4.6 reportait la console. Sans elle, le seul levier contre du vandalisme était de
-- retirer les signalements un par un en SQL, sans trace et sans moyen de neutraliser un
-- terminal. On avance donc trois actions, et seulement trois :
--
--   1. retirer un danger (réversible),
--   2. bannir un terminal — le bloquer et annuler tout ce qu'il a fait,
--   3. gérer le catalogue des types.
--
-- Ce qui reste reporté : la file de modération, faute de signalements d'abus pour
-- l'alimenter ; la purge irréversible, qui n'a pas d'objet sans photos ni contenu libre
-- abondant ; le shadow-ban du §6.3, remplacé ici par un blocage franc.
--
-- **Tout passe par des fonctions, jamais par des écritures directes**, pour une raison :
-- le §4.3 veut que chaque action admin soit journalisée dans la même transaction que son
-- effet. Une console qui écrit en direct, comme Supabase Studio, ne laisse aucune trace.

---------------------------------------------------------------------------
-- Rôle
---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_api') THEN
    CREATE ROLE admin_api NOLOGIN NOINHERIT;
  END IF;
END
$$;
GRANT admin_api TO authenticator;
GRANT USAGE ON SCHEMA public TO admin_api;

-- L'admin est identifié par le `sub` de son jeton, qui doit exister dans `admins` et ne pas
-- être désactivé. Aucun mot de passe ici : l'authentification est le jeton lui-même, délivré
-- hors ligne par `make admin-add` et injecté par le frontal (voir server/README.md).
CREATE OR REPLACE FUNCTION current_admin()
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_sub   text;
  v_admin uuid;
BEGIN
  v_sub := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub';
  IF v_sub IS NULL THEN
    RAISE EXCEPTION 'action réservée aux administrateurs' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT a.user_id INTO v_admin
    FROM admins a WHERE a.user_id = v_sub::uuid AND a.disabled_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'administrateur inconnu ou désactivé' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_admin;
END
$$;

-- Journalise, et rend l'identifiant de l'admin. Appelée au début de chaque action : si elle
-- échoue, rien de ce qui suit n'a lieu.
CREATE OR REPLACE FUNCTION audit(p_action text, p_target text, p_reason text, p_snapshot jsonb DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := current_admin();
BEGIN
  IF coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'un motif est obligatoire' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO admin_actions (admin_id, action, target, reason, snapshot)
  VALUES (v_admin, p_action, p_target, btrim(p_reason), p_snapshot);
  RETURN v_admin;
END
$$;

---------------------------------------------------------------------------
-- Annulation d'événements
---------------------------------------------------------------------------
-- Bannir un terminal doit défaire ce qu'il a fait sans trouer le journal, qui est la source
-- de vérité (§5). D'où une colonne plutôt qu'un DELETE : l'événement reste, il cesse
-- simplement de compter. Le recalcul l'ignore, et on peut toujours dire ce qui s'est passé.
ALTER TABLE events ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
COMMENT ON COLUMN events.cancelled_at IS
  'Événement neutralisé par un bannissement (§4.3) : conservé, mais ignoré par recompute_hazard.';

-- Reprise de 0030 avec le filtre d'annulation. Les deux agrégats sont concernés : les
-- confirmations et le poids de résolution.
CREATE OR REPLACE FUNCTION recompute_hazard(p_hazard uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_min_votes     int;
  v_per_vote      int;
  v_max_votes     int;
  v_current       hazard_status;
  v_remove_id     bigint;
  v_restore_id    bigint;
  v_confirmations int;
  v_last_seen     timestamptz;
  v_reset_id      bigint;
  v_resolve       real;
  v_flags         int;
  v_threshold     int;
  v_status        hazard_status;
BEGIN
  SELECT h.status INTO v_current FROM hazards h WHERE h.id = p_hazard;

  SELECT s.min_resolve_votes, s.confirmations_per_resolve_vote, s.max_resolve_votes
    INTO v_min_votes, v_per_vote, v_max_votes
    FROM moderation_settings s WHERE s.id = 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT
    max(e.id) FILTER (WHERE e.type = 'remove'),
    max(e.id) FILTER (WHERE e.type = 'restore'),
    count(*)  FILTER (WHERE e.type IN ('create', 'confirm')),
    max(e.created_at) FILTER (WHERE e.type IN ('create', 'confirm')),
    max(e.id) FILTER (WHERE e.type IN ('create', 'confirm')),
    count(*)  FILTER (WHERE e.type = 'flag')
  INTO v_remove_id, v_restore_id, v_confirmations, v_last_seen, v_reset_id, v_flags
  FROM events e
  WHERE e.hazard_id = p_hazard
    AND e.cancelled_at IS NULL;

  SELECT coalesce(sum(e.weight), 0)::real
    INTO v_resolve
    FROM events e
   WHERE e.hazard_id = p_hazard
     AND e.cancelled_at IS NULL
     AND e.type = 'mark_resolved'
     AND (v_reset_id IS NULL OR e.id > v_reset_id);

  v_threshold := resolve_threshold(greatest(v_confirmations, 1), v_min_votes, v_per_vote, v_max_votes);

  IF v_remove_id IS NOT NULL AND (v_restore_id IS NULL OR v_restore_id < v_remove_id) THEN
    v_status := 'removed';
  ELSIF v_current = 'archived' THEN
    v_status := 'archived';
  ELSIF v_resolve >= v_threshold THEN
    v_status := 'resolved';
  ELSIF v_resolve >= 1 THEN
    v_status := 'disputed';
  ELSE
    v_status := 'active';
  END IF;

  UPDATE hazards h
     SET confirmations     = greatest(v_confirmations, 1),
         last_confirmed_at = coalesce(v_last_seen, h.last_confirmed_at),
         resolve_weight    = v_resolve,
         flags             = v_flags,
         status            = v_status
   WHERE h.id = p_hazard;
END
$$;

---------------------------------------------------------------------------
-- Blocage d'un terminal banni
---------------------------------------------------------------------------
-- Un blocage franc, et non le shadow-ban du §6.3 : entre gens qui se connaissent, laisser
-- croire à quelqu'un que ses signalements comptent serait une tromperie inutile. Le
-- shadow-ban reste pertinent à l'ouverture, contre des acteurs qu'on ne connaît pas.
CREATE OR REPLACE FUNCTION assert_not_banned(p_device uuid)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices d WHERE d.id = p_device AND d.banned_at IS NOT NULL) THEN
    RAISE EXCEPTION 'ce terminal a été bloqué par un administrateur'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END
$$;

COMMENT ON COLUMN devices.banned_at IS
  'Terminal bloqué (§4.3) : ses écritures sont refusées, et ses événements sont annulés. '
  'Posé par admin_ban_device(), jamais à la main.';

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
-- Retirer et rétablir passent par le journal, comme n'importe quel geste : c'est lui qui
-- fait foi, et `recompute_hazard` en déduit le statut. Un UPDATE direct sur `hazards` serait
-- effacé au premier recalcul.
CREATE OR REPLACE FUNCTION admin_set_hazard_removed(id uuid, removed boolean, reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_before hazard_status;
BEGIN
  SELECT h.status INTO v_before FROM hazards h WHERE h.id = admin_set_hazard_removed.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger inconnu : %', admin_set_hazard_removed.id USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM audit(
    CASE WHEN removed THEN 'hazard.remove' ELSE 'hazard.restore' END,
    admin_set_hazard_removed.id::text,
    reason,
    jsonb_build_object('status_before', v_before)
  );

  INSERT INTO events (client_id, hazard_id, device_id, type, weight)
  VALUES (gen_random_uuid(), admin_set_hazard_removed.id, NULL,
          CASE WHEN removed THEN 'remove' ELSE 'restore' END::event_type, 0);

  RETURN jsonb_build_object(
    'id', admin_set_hazard_removed.id,
    'status_before', v_before,
    'status_after', (SELECT h.status FROM hazards h WHERE h.id = admin_set_hazard_removed.id)
  );
END
$$;

-- Bannir : bloquer, puis défaire. Les trois effets sont dans la même transaction, sans quoi
-- un bannissement à moitié appliqué serait pire que pas de bannissement.
CREATE OR REPLACE FUNCTION admin_ban_device(device_id uuid, reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_hazards uuid[];
  v_events  bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM devices d WHERE d.id = admin_ban_device.device_id) THEN
    RAISE EXCEPTION 'terminal inconnu : %', admin_ban_device.device_id USING ERRCODE = 'no_data_found';
  END IF;

  -- Les dangers que ce terminal a créés, à retirer. Relevés avant l'annulation, et gardés
  -- dans le journal d'audit : c'est la seule trace qui permettra de les rétablir un par un
  -- si le bannissement était une erreur.
  SELECT coalesce(array_agg(h.id), '{}') INTO v_hazards
    FROM hazards h WHERE h.created_by = admin_ban_device.device_id AND h.status <> 'removed';

  PERFORM audit('device.ban', admin_ban_device.device_id::text, reason,
                jsonb_build_object('hazards_removed', to_jsonb(v_hazards)));

  UPDATE devices d SET banned_at = now() WHERE d.id = admin_ban_device.device_id;

  UPDATE events e SET cancelled_at = now()
   WHERE e.device_id = admin_ban_device.device_id AND e.cancelled_at IS NULL;
  GET DIAGNOSTICS v_events = ROW_COUNT;

  INSERT INTO events (client_id, hazard_id, device_id, type, weight)
  SELECT gen_random_uuid(), h, NULL, 'remove'::event_type, 0 FROM unnest(v_hazards) AS h;

  -- L'annulation seule ne redéclenche aucun trigger utile : on recalcule à la main tous les
  -- dangers touchés, y compris ceux que ce terminal avait simplement confirmés.
  PERFORM recompute_hazard(e.hazard_id)
     FROM (SELECT DISTINCT e.hazard_id FROM events e
            WHERE e.device_id = admin_ban_device.device_id) e;

  RETURN jsonb_build_object(
    'device_id', admin_ban_device.device_id,
    'events_cancelled', v_events,
    'hazards_removed', to_jsonb(v_hazards)
  );
END
$$;

-- **Il n'y a pas de débannissement, et c'est délibéré.**
--
-- La fonction a existé. Elle ne rendait presque rien. Les dangers retirés n'étaient pas
-- rétablis : les rétablir en bloc supposerait qu'ils étaient tous légitimes, ce que personne
-- n'a vérifié. Et passé 24 heures, `anonymize_old_events()` a coupé le lien terminal →
-- événements, donc plus aucun geste ne pouvait être remis en jeu non plus. Restait un bouton
-- qui levait le blocage sans rien réparer, en laissant croire l'inverse — et un bouton qui
-- ment est pire que pas de bouton du tout.
--
-- Ce qui reste quand on s'est trompé : le journal d'audit garde la liste des dangers retirés,
-- et `admin_set_hazard_removed` les rétablit un par un, avec un motif à chaque fois. Côté
-- personne, « Régénérer mon identifiant » (§11.4, écran Paramètres) repart d'un UUID neuf.
-- Ce contournement existait déjà et était assumé ; il est désormais la seule voie de retour.

---------------------------------------------------------------------------
-- Catalogue des types
---------------------------------------------------------------------------
-- Le catalogue pilote l'interface de l'app (§3) : une faute de frappe ici se voit chez tout
-- le monde au prochain lancement. Il s'édite en table, mais chaque écriture est journalisée
-- par un trigger — sinon la console d'administration aurait un angle mort là où elle a le
-- plus d'effet.
CREATE OR REPLACE FUNCTION hazard_types_audit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_sub   text;
  v_admin uuid;
BEGIN
  -- Les migrations et le seed écrivent dans cette table sans jeton : ce ne sont pas des
  -- actions d'administrateur, et les journaliser ferait échouer `make migrate`. Le journal
  -- d'audit couvre ce qui passe par la console, pas ce qui passe par le dépôt de code.
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
  VALUES (
    v_admin,
    'type.' || lower(TG_OP),
    coalesce(NEW.code, OLD.code),
    'édition du catalogue',
    jsonb_build_object('before', to_jsonb(OLD), 'after', to_jsonb(NEW))
  );
  RETURN NULL;
END
$$;

DROP TRIGGER IF EXISTS hazard_types_audit_trigger ON hazard_types;
CREATE TRIGGER hazard_types_audit_trigger
  AFTER INSERT OR UPDATE OR DELETE ON hazard_types
  FOR EACH ROW EXECUTE FUNCTION hazard_types_audit();

-- Les seuils de résolution (§6.1) s'éditent de la même façon, et se journalisent pareil : une
-- règle de modération changée sans trace serait le plus gros angle mort possible de la console.
CREATE OR REPLACE FUNCTION moderation_settings_audit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_sub   text;
  v_admin uuid;
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

  INSERT INTO admin_actions (admin_id, action, target, reason, snapshot)
  VALUES (v_admin, 'rules.update', 'moderation_settings', 'réglage des seuils de résolution',
          jsonb_build_object('before', to_jsonb(OLD), 'after', to_jsonb(NEW)));
  RETURN NULL;
END
$$;

DROP TRIGGER IF EXISTS moderation_settings_audit_trigger ON moderation_settings;
CREATE TRIGGER moderation_settings_audit_trigger
  AFTER UPDATE ON moderation_settings
  FOR EACH ROW EXECUTE FUNCTION moderation_settings_audit();

-- `updated_at` est posé par la base : l'écran dit « réglé le … », pas « réglé quand la console
-- a bien voulu l'écrire ».
CREATE OR REPLACE FUNCTION touch_moderation_settings()
RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS moderation_settings_touch ON moderation_settings;
CREATE TRIGGER moderation_settings_touch
  BEFORE UPDATE ON moderation_settings
  FOR EACH ROW EXECUTE FUNCTION touch_moderation_settings();

---------------------------------------------------------------------------
-- Ce que l'admin voit
---------------------------------------------------------------------------
-- Tout, y compris ce qui est masqué au public : c'est la différence entre modérer et
-- consulter. `created_by` reste exclu même ici — un administrateur n'a pas besoin de savoir
-- qui a signalé quoi pour retirer un signalement, et le §11 ne fait pas d'exception pour
-- lui. Le lien device → dangers n'est visible qu'au moment d'un bannissement, dans le
-- résultat de l'action.
--
-- En droits du propriétaire, et non en `security_invoker` : c'est ce qui permet de ne donner
-- à `admin_api` **aucun** droit sur `hazards`, `devices` ni `events`. La version qui suit est
-- reprise par 0110, qui y ajoute le contrôle d'administrateur actif.
CREATE OR REPLACE VIEW admin_hazards AS
  SELECT h.id, h.type, ST_Y(h.geom) AS lat, ST_X(h.geom) AS lng,
         h.severity, h.status, h.description, h.address, h.source,
         h.created_at, h.last_confirmed_at, h.confirmations, h.resolve_weight, h.flags,
         (SELECT count(*) FROM events e WHERE e.hazard_id = h.id) AS events_count
    FROM hazards h;

CREATE OR REPLACE VIEW admin_devices AS
  SELECT d.id, d.created_at, d.banned_at,
         (SELECT count(*) FROM events e WHERE e.device_id = d.id) AS events_count,
         (SELECT count(*) FROM events e WHERE e.device_id = d.id AND e.cancelled_at IS NOT NULL)
           AS events_cancelled,
         (SELECT count(*) FROM hazards h WHERE h.created_by = d.id) AS hazards_created
    FROM devices d;

---------------------------------------------------------------------------
-- Droits
---------------------------------------------------------------------------
GRANT SELECT ON admin_hazards, admin_devices TO admin_api;
GRANT SELECT ON admin_actions TO admin_api;
-- La liste des administrateurs, pour que le journal d'audit dise « moderation@… » plutôt
-- qu'un UUID. Le §4.3 veut l'identité de l'admin dans l'historique, et un identifiant opaque
-- ne la donne pas.
GRANT SELECT (user_id, email, created_at, disabled_at) ON admins TO admin_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON hazard_types TO admin_api;
-- Les seuils du §6.1 : modifiables, jamais créés ni supprimés — il n'y a qu'une ligne.
GRANT SELECT, UPDATE ON moderation_settings TO admin_api;
-- Et rien sur `hazards`, `devices` ni `events` : les vues ci-dessus lisent en droits du
-- propriétaire, le rôle n'a pas besoin des tables — et ne doit pas les avoir (§11).

ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_actions_read ON admin_actions;
CREATE POLICY admin_actions_read ON admin_actions FOR SELECT TO admin_api USING (true);

DROP POLICY IF EXISTS admins_admin_read ON admins;
CREATE POLICY admins_admin_read ON admins FOR SELECT TO admin_api USING (true);

DROP POLICY IF EXISTS hazard_types_admin_write ON hazard_types;
CREATE POLICY hazard_types_admin_write ON hazard_types FOR ALL TO admin_api USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS moderation_settings_admin ON moderation_settings;
CREATE POLICY moderation_settings_admin ON moderation_settings
  FOR ALL TO admin_api USING (true) WITH CHECK (true);

REVOKE ALL ON FUNCTION current_admin()                                  FROM PUBLIC;
REVOKE ALL ON FUNCTION audit(text, text, text, jsonb)                   FROM PUBLIC;
REVOKE ALL ON FUNCTION assert_not_banned(uuid)                          FROM PUBLIC;
REVOKE ALL ON FUNCTION hazard_types_audit()                             FROM PUBLIC;
REVOKE ALL ON FUNCTION moderation_settings_audit()                      FROM PUBLIC;
REVOKE ALL ON FUNCTION touch_moderation_settings()                      FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_set_hazard_removed(uuid, boolean, text)    FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_ban_device(uuid, text)                     FROM PUBLIC;

GRANT EXECUTE ON FUNCTION admin_set_hazard_removed(uuid, boolean, text) TO admin_api;
GRANT EXECUTE ON FUNCTION admin_ban_device(uuid, text)                  TO admin_api;

NOTIFY pgrst, 'reload schema';
