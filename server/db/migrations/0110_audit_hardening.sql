-- L'application — durcissement après l'audit du 15 septembre 2026 (AUDIT.md).
--
-- Tout ce que l'audit a relevé côté base et qui se corrige sans rouvrir une décision de la
-- spec. Dans l'ordre où ça compte :
--
--   C1  un jeton admin lisait `hazards.created_by` et `events.device_id` — le lien terminal →
--       gestes, que tout le reste du code cache ;
--   I1  le débannissement est retiré : il ne rendait presque rien et le laissait croire ;
--   C2  un administrateur désactivé, ou un jeton fuité, continuait de tout lire ;
--   C6  `report_hazard` sans verrou : un rejeu concurrent créait un danger sans événement ;
--   I3  `proximity_tier()` était un RPC public qui recevait des coordonnées de terminal ;
--   M10 et avec lui les 800 fonctions PostGIS, exécutables par `anon` via /rpc/st_* ;
--   I2  « Effacer mes données » levait un bannissement ;
--   I4  le catalogue acceptait un rayon anti-doublon à 0, et le seuil de résolution un
--       plancher à 0 — ce dernier vit maintenant dans `moderation_settings` (0010, 0120) ;
--   M11 la carte tronquait à 5 000 sans tri ni avertissement ;
--   M1, M5, M6, M7, M8, M9, M13, S1, S2 : voir chaque section.
--
-- Rejouable, comme les autres : `make migrate` repasse tous les fichiers.

---------------------------------------------------------------------------
-- S2 — fermé par défaut
---------------------------------------------------------------------------
-- Toute fonction créée désormais par le rôle des migrations naît sans EXECUTE pour PUBLIC :
-- il faut le donner explicitement. C'est la révocation une à une qui avait laissé passer I3.
--
-- Forme globale, et non `IN SCHEMA public` : les privilèges par défaut d'un schéma
-- s'**ajoutent** au défaut global, ils ne peuvent pas lui retirer ce qu'il accorde. Révoquer
-- « dans le schéma » ne produit donc aucune entrée, et PUBLIC garde EXECUTE.
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

---------------------------------------------------------------------------
-- I3, S4 — la définition de référence du palier quitte l'API
---------------------------------------------------------------------------
-- Les RPC ne l'appellent plus depuis 0100 ; elle recevait pourtant, en clair et pour tout
-- le monde, une latitude et une longitude de terminal. Elle vit désormais dans
-- `app_test` (voir db/tests/_helpers.sql), où les tests continuent de vérifier que la
-- table `proximity_tiers` et la règle disent la même chose.
DROP FUNCTION IF EXISTS proximity_tier(geometry, double precision, double precision);

---------------------------------------------------------------------------
-- M10 — ce qu'`anon` peut appeler, et rien d'autre
---------------------------------------------------------------------------
-- PostGIS s'installe dans `public`, avec EXECUTE pour PUBLIC sur chacune de ses fonctions :
-- PostgREST les exposait toutes. Aucune n'a d'usage depuis l'API — nos fonctions tournent
-- en SECURITY DEFINER, donc avec les droits du propriétaire.
--
-- `hazards_public` passe en droits du propriétaire pour la même raison : en
-- `security_invoker`, c'est `anon` qui exécutait ST_X/ST_Y. Le filtre de statut est dans la
-- vue, `created_by` n'y figure pas : rien ne change pour ce qu'elle laisse voir.
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC, anon, admin_api;

ALTER VIEW hazards_public RESET (security_invoker);

GRANT EXECUTE ON FUNCTION report_hazard(uuid, uuid, text, double precision, double precision,
                                        smallint, text, smallint)   TO anon;
GRANT EXECUTE ON FUNCTION confirm_hazard(uuid, uuid, uuid, smallint) TO anon;
GRANT EXECUTE ON FUNCTION mark_resolved(uuid, uuid, uuid, smallint)  TO anon;
GRANT EXECUTE ON FUNCTION remove_own_hazard(uuid, uuid, uuid)        TO anon;
GRANT EXECUTE ON FUNCTION hazards_in_bbox(double precision, double precision, double precision,
                                          double precision, text[], smallint, boolean) TO anon;
GRANT EXECUTE ON FUNCTION hazard_detail(uuid)                        TO anon;
GRANT EXECUTE ON FUNCTION forget_device(uuid)                        TO anon;

-- Les fonctions qu'une vue appelle s'exécutent avec les droits de **celui qui lit la vue**,
-- pas de son propriétaire (CREATE VIEW, « functions called in the view are treated the same
-- as if they had been called directly »). Les deux accesseurs de coordonnées des vues
-- publiques et admin sont donc les seules fonctions PostGIS qui restent accordées.
GRANT EXECUTE ON FUNCTION st_x(geometry), st_y(geometry) TO anon, admin_api;

---------------------------------------------------------------------------
-- C1, S3 — l'admin ne lit pas le lien terminal → gestes
---------------------------------------------------------------------------
-- Les vues `admin_hazards` et `admin_devices` étaient en `security_invoker`, ce qui obligeait
-- à donner à `admin_api` le SELECT sur `hazards`, `devices` et `events` en entier — donc sur
-- `created_by` et `device_id`, que le §11 et le commentaire au-dessus de ces vues disaient
-- pourtant exclus. En droits du propriétaire, les vues lisent ce qu'elles montrent, et le
-- rôle n'a plus rien d'autre.
REVOKE ALL ON hazards, devices, events FROM admin_api;
DROP POLICY IF EXISTS hazards_admin_read ON hazards;
DROP POLICY IF EXISTS devices_admin_read ON devices;
DROP POLICY IF EXISTS events_admin_read  ON events;

ALTER VIEW admin_hazards RESET (security_invoker);
ALTER VIEW admin_devices RESET (security_invoker);

---------------------------------------------------------------------------
-- C2 — désactiver un administrateur ferme aussi la lecture
---------------------------------------------------------------------------
-- Le jeton n'expire pas ; la seule révocation est `admins.disabled_at`. Elle ne bloquait que
-- les actions, parce que les lectures passaient par des vues sans aucun contrôle. Toutes
-- les lectures admin passent maintenant par `current_admin()`, qui lève une erreur 42501
-- si le `sub` du jeton n'est pas un administrateur actif — PostgREST la rend en 403, et la
-- console renvoie alors à l'écran de connexion.
CREATE OR REPLACE VIEW admin_hazards AS
  SELECT h.id, h.type, ST_Y(h.geom) AS lat, ST_X(h.geom) AS lng,
         h.severity, h.status, h.description, h.address, h.source,
         h.created_at, h.last_confirmed_at, h.confirmations, h.resolve_weight, h.flags,
         (SELECT count(*) FROM events e WHERE e.hazard_id = h.id) AS events_count
    FROM hazards h
   WHERE current_admin() IS NOT NULL;

CREATE OR REPLACE VIEW admin_devices AS
  SELECT d.id, d.created_at, d.banned_at,
         (SELECT count(*) FROM events e WHERE e.device_id = d.id) AS events_count,
         (SELECT count(*) FROM events e WHERE e.device_id = d.id AND e.cancelled_at IS NOT NULL)
           AS events_cancelled,
         (SELECT count(*) FROM hazards h WHERE h.created_by = d.id) AS hazards_created
    FROM devices d
   WHERE current_admin() IS NOT NULL;

DROP POLICY IF EXISTS admin_actions_read ON admin_actions;
CREATE POLICY admin_actions_read ON admin_actions
  FOR SELECT TO admin_api USING (current_admin() IS NOT NULL);

DROP POLICY IF EXISTS admins_admin_read ON admins;
CREATE POLICY admins_admin_read ON admins
  FOR SELECT TO admin_api USING (current_admin() IS NOT NULL);

DROP POLICY IF EXISTS hazard_types_admin_write ON hazard_types;
CREATE POLICY hazard_types_admin_write ON hazard_types
  FOR ALL TO admin_api USING (current_admin() IS NOT NULL) WITH CHECK (current_admin() IS NOT NULL);

DROP POLICY IF EXISTS hazard_type_icons_admin ON hazard_type_icons;
CREATE POLICY hazard_type_icons_admin ON hazard_type_icons
  FOR SELECT TO admin_api USING (current_admin() IS NOT NULL);

-- Ce que la console appelle à la connexion, puis à chaque requête : « qui suis-je ? ».
-- Un jeton bien formé dont l'administrateur est désactivé échoue ici, et nulle part plus loin.
CREATE OR REPLACE FUNCTION admin_whoami()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object('user_id', a.user_id, 'email', a.email)
    FROM admins a WHERE a.user_id = current_admin();
$$;

-- `current_admin()` est appelée par les vues et les policies, donc avec les droits du rôle
-- qui lit : il lui faut EXECUTE. Elle ne rend qu'un identifiant que le jeton porte déjà.
GRANT EXECUTE ON FUNCTION current_admin()                               TO admin_api;
GRANT EXECUTE ON FUNCTION admin_whoami()                                TO admin_api;
GRANT EXECUTE ON FUNCTION admin_set_hazard_removed(uuid, boolean, text) TO admin_api;
GRANT EXECUTE ON FUNCTION admin_ban_device(uuid, text)                  TO admin_api;
GRANT EXECUTE ON FUNCTION admin_ban_hazard_author(uuid, text)           TO admin_api;
GRANT EXECUTE ON FUNCTION admin_set_hazard_icon(text, text)             TO admin_api;
GRANT EXECUTE ON FUNCTION admin_clear_hazard_icon(text)                 TO admin_api;

---------------------------------------------------------------------------
-- M13 — un e-mail, un administrateur
---------------------------------------------------------------------------
-- La révocation documentée est `WHERE email = …` : elle doit désigner une seule ligne.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admins_email_key') THEN
    ALTER TABLE admins ADD CONSTRAINT admins_email_key UNIQUE (email);
  END IF;
END
$$;

---------------------------------------------------------------------------
-- M9 — le journal d'audit ne se réécrit pas, même en SQL
---------------------------------------------------------------------------
-- Les droits ne protégeaient que du rôle `admin_api`. Supabase Studio, lui, est superuser.
-- Un trigger n'arrête pas un superuser décidé, mais il arrête un clic malheureux.
CREATE OR REPLACE FUNCTION admin_actions_immutable()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'le journal d''audit est en écriture seule (§4.3)'
    USING ERRCODE = 'insufficient_privilege';
END
$$;

DROP TRIGGER IF EXISTS admin_actions_immutable ON admin_actions;
CREATE TRIGGER admin_actions_immutable
  BEFORE UPDATE OR DELETE ON admin_actions
  FOR EACH ROW EXECUTE FUNCTION admin_actions_immutable();
DROP TRIGGER IF EXISTS admin_actions_no_truncate ON admin_actions;
CREATE TRIGGER admin_actions_no_truncate
  BEFORE TRUNCATE ON admin_actions
  FOR EACH STATEMENT EXECUTE FUNCTION admin_actions_immutable();

COMMENT ON TABLE admin_actions IS
  'Journal d''audit du §4.3 : une ligne par action passée par la console, avec son motif. '
  'En écriture seule. Ce qui est fait directement en SQL ou dans Studio n''y figure pas.';

---------------------------------------------------------------------------
-- I4 — le catalogue a des bornes
---------------------------------------------------------------------------
-- La console édite cette table en direct ; `Number('')` donne 0, et un seuil de résolution à
-- 0 ferait basculer un danger « résolu » au premier vote. Les bornes sont celles du
-- formulaire, écrites là où elles comptent.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'hazard_types_code_format') THEN
    ALTER TABLE hazard_types ADD CONSTRAINT hazard_types_code_format
      CHECK (code ~ '^[a-z_]{3,30}$');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'hazard_types_labels_present') THEN
    ALTER TABLE hazard_types ADD CONSTRAINT hazard_types_labels_present
      CHECK (btrim(label_fr) <> '' AND btrim(resolved_label_fr) <> '');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'hazard_types_dedup_radius') THEN
    ALTER TABLE hazard_types ADD CONSTRAINT hazard_types_dedup_radius
      CHECK (dedup_radius_m BETWEEN 1 AND 500);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'hazard_types_ttl') THEN
    ALTER TABLE hazard_types ADD CONSTRAINT hazard_types_ttl
      CHECK (default_ttl_days BETWEEN 1 AND 3650);
  END IF;
END
$$;

---------------------------------------------------------------------------
-- M5 — les index que `forget_device`, le bannissement et `admin_devices` attendaient
---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS events_device_idx
  ON events (device_id) WHERE device_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS hazards_created_by_idx
  ON hazards (created_by) WHERE created_by IS NOT NULL;

---------------------------------------------------------------------------
-- S1 — le recalcul ne se déclenche que quand le journal change de sens
---------------------------------------------------------------------------
-- `anonymize_old_events` met `device_id` à NULL toutes les heures : ça ne change rien aux
-- compteurs, et ça recalculait pourtant chaque danger touché, événement par événement. Le
-- trigger ne réagit plus qu'à ce que `recompute_hazard` lit vraiment.
DROP TRIGGER IF EXISTS events_recompute ON events;
CREATE TRIGGER events_recompute
  AFTER INSERT OR DELETE OR UPDATE OF cancelled_at, weight ON events
  FOR EACH ROW EXECUTE FUNCTION events_recompute_trigger();

---------------------------------------------------------------------------
-- C6, M1 — `report_hazard` verrouillé et borné
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
  -- M1 : dire ce qui manque plutôt que de laisser PostGIS ou une contrainte NOT NULL
  -- répondre en anglais.
  IF report_hazard.client_id IS NULL OR report_hazard.device_id IS NULL THEN
    RAISE EXCEPTION 'identifiant de geste ou de terminal manquant' USING ERRCODE = 'check_violation';
  END IF;
  IF report_hazard.lat IS NULL OR report_hazard.lng IS NULL
     OR report_hazard.lat NOT BETWEEN -90 AND 90
     OR report_hazard.lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'position du danger invalide' USING ERRCODE = 'check_violation';
  END IF;
  IF report_hazard.type IS NULL THEN
    RAISE EXCEPTION 'type de danger manquant' USING ERRCODE = 'check_violation';
  END IF;

  -- C6, premier verrou : deux rejeux du même geste — timeout réseau puis renvoi, le cas
  -- nominal du §10 — se sérialisent ici. Le second attend le premier, puis trouve son
  -- événement et rend le même danger. Sans cela, deux `hazards` naissaient, et le second
  -- `record_event` faisait `DO NOTHING` : un point sans événement `create`.
  PERFORM pg_advisory_xact_lock(hashtext('report_hazard:client:' || report_hazard.client_id::text));

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

  IF report_hazard.severity IS NULL OR report_hazard.severity NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'gravité hors bornes : %', report_hazard.severity USING ERRCODE = 'check_violation';
  END IF;
  IF char_length(coalesce(report_hazard.description, '')) > 140 THEN
    RAISE EXCEPTION 'commentaire limité à 140 caractères' USING ERRCODE = 'check_violation';
  END IF;

  v_geom := ST_SetSRID(ST_MakePoint(report_hazard.lng, report_hazard.lat), 4326);

  -- C6, second verrou : deux testeurs qui signalent le même trou à la même seconde
  -- passaient tous deux l'anti-doublon, chacun ne voyant pas encore l'autre. Un verrou par
  -- type, et non par cellule de grille : à l'échelle de la bêta la contention est nulle, et
  -- une grille laisse passer deux points de part et d'autre d'une frontière de cellule.
  -- Toujours pris après le verrou par geste, dans cet ordre, pour ne jamais s'interbloquer.
  PERFORM pg_advisory_xact_lock(hashtext('report_hazard:type:' || report_hazard.type));

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

---------------------------------------------------------------------------
-- M7 — la chronologie publique ignore les gestes annulés
---------------------------------------------------------------------------
-- Après un bannissement, `recompute_hazard` ne compte plus les événements annulés ; le détail
-- et le badge « signalé à distance » les montraient encore.
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
    'description',       h.description,
    'address',           h.address,
    'created_at',        h.created_at,
    'last_confirmed_at', h.last_confirmed_at,
    'confirmations',     h.confirmations,
    'resolve_weight',    h.resolve_weight,
    'resolve_threshold', resolve_threshold(h.confirmations, s.min_resolve_votes,
                                           s.confirmations_per_resolve_vote, s.max_resolve_votes),
    -- Badge « signalé à distance » (§6.2) : dérivé du palier de l'événement de création.
    'reported_remotely', EXISTS (
       SELECT 1 FROM events e
        WHERE e.hazard_id = h.id AND e.type = 'create' AND e.proximity = 3
          AND e.cancelled_at IS NULL
    )
  )
  FROM hazards h
  CROSS JOIN moderation_settings s
  WHERE h.id = p_hazard AND s.id = 1;
$$;

CREATE OR REPLACE FUNCTION hazard_detail(id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT hazard_json(hazard_detail.id) || jsonb_build_object(
    'timeline', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'type', e.type, 'proximity', e.proximity, 'created_at', e.created_at)
               ORDER BY e.id)
        FROM events e WHERE e.hazard_id = hazard_detail.id AND e.cancelled_at IS NULL
    ), '[]'::jsonb),
    'photos', coalesce((
      SELECT jsonb_agg(jsonb_build_object('object_key', p.object_key, 'created_at', p.created_at)
               ORDER BY p.created_at)
        FROM photos p WHERE p.hazard_id = hazard_detail.id
    ), '[]'::jsonb)
  )
  WHERE EXISTS (
    SELECT 1 FROM hazards h
     WHERE h.id = hazard_detail.id AND h.status NOT IN ('removed', 'archived')
  );
$$;

---------------------------------------------------------------------------
-- M11 — la carte tronque, et elle le dit
---------------------------------------------------------------------------
-- Le plafond de 5 000 existait déjà. Sans `ORDER BY`, il rendait un sous-ensemble
-- arbitraire, dans l'ordre physique de la table — qui bouge après un VACUUM : deux
-- chargements du même cadre pouvaient montrer des points différents. Et personne n'était
-- prévenu, ce qui est devenu coûteux : l'app élague désormais de son cache ce que le serveur
-- ne renvoie plus dans la zone. Une troncature muette deviendrait une perte locale, et la
-- zone serait mémorisée comme complète — donc « rien d'autre ici » affirmé sur un vide
-- fabriqué (§10).
--
-- D'où deux ajouts. Un tri stable, qui garde ce qui compte le plus quand il faut couper : le
-- plus grave d'abord, puis le plus récemment confirmé. Et un drapeau `truncated`, que l'app
-- lit pour ne rien élaguer ni mémoriser.
--
-- Le nom d'un paramètre ne peut pas changer par CREATE OR REPLACE : on repart de zéro pour
-- que les migrations restent rejouables.
DROP FUNCTION IF EXISTS hazards_in_bbox(double precision, double precision, double precision,
                                        double precision, text[], smallint, boolean);

CREATE FUNCTION hazards_in_bbox(
  min_lon          double precision,
  min_lat          double precision,
  max_lon          double precision,
  max_lat          double precision,
  types            text[] DEFAULT NULL,
  -- Gravité *minimale* : le filtre de la carte sert à ne garder que les dangers
  -- au moins aussi graves que le niveau choisi, pas l'inverse (§4.1 F1).
  min_severity     smallint DEFAULT NULL,
  include_resolved boolean DEFAULT false
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH visible AS (
    SELECT h.id, h.geom
      FROM hazards h
     WHERE h.geom && ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
       AND (
             h.status IN ('active', 'disputed')
          -- Calque « résolus récemment » : 30 jours après le vote qui a fait basculer (§6.1).
          OR (include_resolved AND h.status = 'resolved' AND EXISTS (
                SELECT 1 FROM events e
                 WHERE e.hazard_id = h.id AND e.type = 'mark_resolved'
                   AND e.created_at > now() - interval '30 days'))
           )
       AND (types IS NULL OR h.type = ANY (types))
       AND (min_severity IS NULL OR h.severity >= min_severity)
     ORDER BY h.severity DESC, h.last_confirmed_at DESC, h.id
     LIMIT 5000
  )
  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    -- Vrai quand le plafond est atteint : la réponse ne décrit alors plus la zone entière,
    -- et le client ne doit ni la mémoriser comme complète ni en déduire une absence.
    'truncated', (SELECT count(*) FROM visible) >= 5000,
    'features', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'type', 'Feature',
          'id', f.id,
          'geometry', ST_AsGeoJSON(f.geom)::jsonb,
          'properties', hazard_json(f.id) - 'lat' - 'lng'
        ))
      FROM visible f), '[]'::jsonb)
  );
$$;

GRANT EXECUTE ON FUNCTION hazards_in_bbox(double precision, double precision, double precision,
                                          double precision, text[], smallint, boolean) TO anon;

---------------------------------------------------------------------------
-- M6 — l'anonymisation traite aussi les photos
---------------------------------------------------------------------------
-- `photos.device_id` porte le même lien que `events.device_id`. La table est vide pendant la
-- bêta (§4.6), mais `forget_device` la traitait déjà, et le cron doit faire pareil.
CREATE OR REPLACE FUNCTION anonymize_old_events(older_than interval DEFAULT interval '24 hours')
RETURNS TABLE (events_anonymized bigint, hazards_anonymized bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_events  bigint;
  v_hazards bigint;
BEGIN
  UPDATE events e
     SET device_id = NULL
   WHERE e.device_id IS NOT NULL
     AND e.created_at < now() - older_than;
  GET DIAGNOSTICS v_events = ROW_COUNT;

  UPDATE hazards h
     SET created_by = NULL
   WHERE h.created_by IS NOT NULL
     AND h.created_at < now() - older_than;
  GET DIAGNOSTICS v_hazards = ROW_COUNT;

  UPDATE photos p
     SET device_id = NULL
   WHERE p.device_id IS NOT NULL
     AND p.created_at < now() - older_than;

  RETURN QUERY SELECT v_events, v_hazards;
END
$$;

---------------------------------------------------------------------------
-- I2 — « Effacer mes données » ne lève pas un bannissement
---------------------------------------------------------------------------
-- La ligne `devices` ne porte que l'UUID et une date de première vue : elle part avec le
-- reste, **sauf si le terminal est bloqué**. Sinon `ensure_device` recréait une ligne vierge
-- au geste suivant, sous le même identifiant, et la décision de l'administrateur disparaissait
-- sans trace. Régénérer son identifiant contourne déjà le blocage (§11.4, assumé) : il ne
-- s'agit pas de l'empêcher, mais de ne pas l'effacer par un chemin qui n'est pas fait pour ça.
CREATE OR REPLACE FUNCTION forget_device(device_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_events  bigint;
  v_hazards bigint;
BEGIN
  UPDATE events e SET device_id = NULL WHERE e.device_id = forget_device.device_id;
  GET DIAGNOSTICS v_events = ROW_COUNT;

  UPDATE hazards h SET created_by = NULL WHERE h.created_by = forget_device.device_id;
  GET DIAGNOSTICS v_hazards = ROW_COUNT;

  UPDATE photos p SET device_id = NULL WHERE p.device_id = forget_device.device_id;

  DELETE FROM devices d WHERE d.id = forget_device.device_id AND d.banned_at IS NULL;

  RETURN jsonb_build_object('events_anonymized', v_events, 'hazards_anonymized', v_hazards);
END
$$;

---------------------------------------------------------------------------
-- Le débannissement disparaît (décision, AUDIT I1 / D3)
---------------------------------------------------------------------------
-- Il ne rendait presque rien : jamais les dangers retirés, et plus aucun geste passé les
-- 24 heures de la fenêtre de corrélation, puisque le lien terminal → événements a été coupé
-- entre-temps. Un bouton qui lève le blocage sans rien réparer, en laissant croire l'inverse.
-- Le raisonnement complet est en tête de la section « Actions » de 0070.
--
-- Conséquence assumée : un blocage est définitif. En cas d'erreur, les dangers se rétablissent
-- un par un depuis le journal d'audit, et la personne repart d'un identifiant neuf depuis
-- l'écran Paramètres (§11.4) — ce qui contournait déjà le blocage.
--
-- Les lignes `device.unban` déjà inscrites au journal d'audit restent : il est en écriture
-- seule, et ce qui a eu lieu a eu lieu.
DROP FUNCTION IF EXISTS admin_unban_device(uuid, text);

---------------------------------------------------------------------------
-- M8 — les fonctions admin vérifient leur cible avant d'écrire au journal
---------------------------------------------------------------------------
-- Journaliser d'abord et vérifier ensuite laissait des lignes « icône retirée » sans icône.
-- Et un `removed` à NULL rétablissait au lieu de refuser.
CREATE OR REPLACE FUNCTION admin_set_hazard_removed(id uuid, removed boolean, reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_before hazard_status;
BEGIN
  IF removed IS NULL THEN
    RAISE EXCEPTION 'préciser s''il faut retirer ou rétablir' USING ERRCODE = 'check_violation';
  END IF;

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

CREATE OR REPLACE FUNCTION admin_ban_device(device_id uuid, reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_banned  timestamptz;
  v_hazards uuid[];
  v_events  bigint;
BEGIN
  SELECT d.banned_at INTO v_banned FROM devices d WHERE d.id = admin_ban_device.device_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'terminal inconnu : %', admin_ban_device.device_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_banned IS NOT NULL THEN
    RAISE EXCEPTION 'Ce terminal est déjà bloqué.' USING ERRCODE = 'unique_violation';
  END IF;

  -- Les dangers que ce terminal a créés, à retirer. Relevés avant l'annulation, et gardés
  -- dans le journal d'audit : c'est la seule trace qui permettra de les rétablir un par un
  -- si le bannissement était une erreur. Il n'y a pas de retour en bloc (voir 0070).
  SELECT coalesce(array_agg(h.id), '{}') INTO v_hazards
    FROM hazards h WHERE h.created_by = admin_ban_device.device_id AND h.status <> 'removed';

  PERFORM audit('device.ban', admin_ban_device.device_id::text, reason,
                jsonb_build_object('hazards_removed', to_jsonb(v_hazards)));

  UPDATE devices d SET banned_at = now() WHERE d.id = admin_ban_device.device_id;

  -- Le trigger `events_recompute` réagit à `cancelled_at` : chaque danger touché est
  -- recalculé par là, y compris ceux que ce terminal avait simplement confirmés.
  UPDATE events e SET cancelled_at = now()
   WHERE e.device_id = admin_ban_device.device_id AND e.cancelled_at IS NULL;
  GET DIAGNOSTICS v_events = ROW_COUNT;

  INSERT INTO events (client_id, hazard_id, device_id, type, weight)
  SELECT gen_random_uuid(), h, NULL, 'remove'::event_type, 0 FROM unnest(v_hazards) AS h;

  RETURN jsonb_build_object(
    'device_id', admin_ban_device.device_id,
    'events_cancelled', v_events,
    'hazards_removed', to_jsonb(v_hazards)
  );
END
$$;

CREATE OR REPLACE FUNCTION admin_clear_hazard_icon(type_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_supprime int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hazard_type_icons i WHERE i.type_code = admin_clear_hazard_icon.type_code) THEN
    RAISE EXCEPTION 'aucune icône téléversée pour « % »', admin_clear_hazard_icon.type_code
      USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM audit('type.icon.clear', admin_clear_hazard_icon.type_code, 'retrait d''une icône');

  DELETE FROM hazard_type_icons i WHERE i.type_code = admin_clear_hazard_icon.type_code;
  GET DIAGNOSTICS v_supprime = ROW_COUNT;

  RETURN jsonb_build_object('removed', v_supprime);
END
$$;

NOTIFY pgrst, 'reload schema';
