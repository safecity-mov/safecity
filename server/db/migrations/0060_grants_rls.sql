-- L'application — RLS et droits (SPEC §7, §8).
-- Le rôle `anon` ne peut rien écrire directement : il n'a que SELECT sur deux tables et
-- EXECUTE sur les RPC. Toute écriture passe par une fonction SECURITY DEFINER qui applique
-- les règles du §6.

ALTER TABLE hazard_types  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hazards       ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices       ENABLE ROW LEVEL SECURITY;
ALTER TABLE events        ENABLE ROW LEVEL SECURITY;
ALTER TABLE photos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE admins        ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;

-- Le catalogue est public : l'app le lit au démarrage et en dérive son UI (§3).
-- Tous les types sont lisibles, y compris désactivés : `enabled` ne pilote que la création,
-- et l'app a besoin du libellé et du verbe de résolution d'un type désactivé pour afficher
-- les dangers existants de ce type (§4.3).
DROP POLICY IF EXISTS hazard_types_read ON hazard_types;
CREATE POLICY hazard_types_read ON hazard_types FOR SELECT TO anon USING (true);

-- Les seuils du §6.1 sont publiés comme les paliers de proximité : l'app affiche la règle,
-- elle ne l'invente pas. Trois entiers, aucun compteur, aucune donnée personnelle.
ALTER TABLE moderation_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS moderation_settings_read ON moderation_settings;
CREATE POLICY moderation_settings_read ON moderation_settings FOR SELECT TO anon USING (true);

-- Dangers non masqués uniquement (§4.2).
DROP POLICY IF EXISTS hazards_read ON hazards;
CREATE POLICY hazards_read ON hazards FOR SELECT TO anon
  USING (status NOT IN ('removed', 'archived'));

-- `events`, `devices`, `photos`, `admins`, `admin_actions` : aucune policy, donc aucun accès
-- direct. Le journal est exposé, sans device_id, par hazard_detail() (§11).

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT ON hazard_types TO anon;
GRANT SELECT ON moderation_settings TO anon;
GRANT SELECT (id, type, geom, severity, status, description, address, source,
              created_at, last_confirmed_at, confirmations, resolve_weight, flags)
  ON hazards TO anon;   -- `created_by` exclu : lien device → signalement (§11)

-- Vue de confort pour PostgREST : lat/lng exploitables sans décoder du WKB.
--
-- En droits du propriétaire : `anon` n'a pas le droit d'exécuter les fonctions PostGIS
-- (0110), c'est donc la vue qui appelle ST_X/ST_Y, pas lui. Le filtre de statut est le même
-- que la policy, et `created_by` n'y figure pas.
CREATE OR REPLACE VIEW hazards_public AS
  SELECT h.id, h.type, ST_Y(h.geom) AS lat, ST_X(h.geom) AS lng,
         h.severity, h.status, h.description, h.address,
         h.created_at, h.last_confirmed_at, h.confirmations, h.resolve_weight
    FROM hazards h
   WHERE h.status NOT IN ('removed', 'archived');
GRANT SELECT ON hazards_public TO anon;

-- Fonctions internes : jamais appelables depuis l'API.
REVOKE ALL ON FUNCTION recompute_hazard(uuid)                          FROM PUBLIC;
REVOKE ALL ON FUNCTION events_recompute_trigger()                      FROM PUBLIC;
REVOKE ALL ON FUNCTION record_event(uuid, uuid, uuid, event_type, double precision, double precision, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION ensure_device(uuid)                             FROM PUBLIC;
-- hazard_json() rend un danger sans regarder son statut : réservée aux appels internes,
-- sans quoi elle contournerait la policy hazards_read.
REVOKE ALL ON FUNCTION hazard_json(uuid)                               FROM PUBLIC;
REVOKE ALL ON FUNCTION anonymize_old_events(interval)                  FROM PUBLIC;

-- RPC publics (§8).
GRANT EXECUTE ON FUNCTION report_hazard(uuid, uuid, text, double precision, double precision,
                                        smallint, text, double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION confirm_hazard(uuid, uuid, uuid, double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION mark_resolved(uuid, uuid, uuid, double precision, double precision)  TO anon;
GRANT EXECUTE ON FUNCTION remove_own_hazard(uuid, uuid, uuid)                                  TO anon;
GRANT EXECUTE ON FUNCTION hazards_in_bbox(double precision, double precision, double precision,
                                          double precision, text[], smallint, boolean)         TO anon;
GRANT EXECUTE ON FUNCTION hazard_detail(uuid)                                                  TO anon;
-- « Effacer mes données » et « Régénérer mon identifiant » (§11.4, §4.1 F8).
GRANT EXECUTE ON FUNCTION forget_device(uuid)                                                  TO anon;

-- PostgREST recharge son cache de schéma sur NOTIFY.
NOTIFY pgrst, 'reload schema';
