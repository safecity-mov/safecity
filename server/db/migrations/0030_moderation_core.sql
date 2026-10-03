-- L'application — cœur de la modération collaborative (SPEC §6).
-- « Pas de permission, mais du poids. » Ces fonctions sont internes : elles ne sont pas
-- exposées en RPC (voir 0060_grants_rls.sql).

---------------------------------------------------------------------------
-- §6.2 Proximité : trois paliers, et rien d'autre.
---------------------------------------------------------------------------
-- La position du déclarant entre ici et n'en ressort jamais : on ne renvoie qu'un palier
-- sur trois valeurs. Ni la coordonnée ni la distance exacte ne touchent le disque (§11.1).
CREATE OR REPLACE FUNCTION proximity_tier(
  hazard_geom geometry,
  device_lat  double precision,
  device_lng  double precision
) RETURNS smallint
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN device_lat IS NULL OR device_lng IS NULL THEN 3::smallint
    WHEN ST_DWithin(hazard_geom::geography,
                    ST_SetSRID(ST_MakePoint(device_lng, device_lat), 4326)::geography, 50)   THEN 1::smallint
    WHEN ST_DWithin(hazard_geom::geography,
                    ST_SetSRID(ST_MakePoint(device_lng, device_lat), 4326)::geography, 500)  THEN 2::smallint
    ELSE 3::smallint
  END;
$$;

COMMENT ON FUNCTION proximity_tier(geometry, double precision, double precision) IS
  'Palier de proximité §6.2 : 1 = ≤50 m, 2 = 50–500 m, 3 = au-delà ou position refusée. '
  'La position reçue est consommée en mémoire et jamais persistée (§11.1).';

-- §6.2 : ≤ 50 m → 1,0 ; 50–500 m → 0,5 ; au-delà ou position refusée → 0,25.
-- DROP d'abord : 0100 reprend cette fonction en renommant son paramètre, ce que
-- CREATE OR REPLACE refuse. Sans cela, `make migrate` échouait ici sur toute base existante.
DROP FUNCTION IF EXISTS proximity_weight(smallint);
CREATE FUNCTION proximity_weight(tier smallint)
RETURNS real
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE tier WHEN 1 THEN 1.0::real WHEN 2 THEN 0.5::real ELSE 0.25::real END;
$$;

---------------------------------------------------------------------------
-- §6.1 Seuil dynamique de résolution
---------------------------------------------------------------------------
-- seuil = clamp(ceil(confirmations / N), plancher, plafond), les trois réglages venant de
-- `moderation_settings`. Un trou confirmé par 15 personnes ne disparaît pas sur 2 clics.
--
-- La fonction reste pure : elle reçoit les réglages, elle ne va pas les chercher. C'est ce qui
-- permet de la tester valeur par valeur sans écrire dans la table.
DROP FUNCTION IF EXISTS resolve_threshold(int, int);
CREATE OR REPLACE FUNCTION resolve_threshold(
  confirmations                  int,
  min_resolve_votes              int,
  confirmations_per_resolve_vote int DEFAULT 3,
  max_resolve_votes              int DEFAULT 5
) RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  -- `greatest(…, 1)` sur le diviseur : la contrainte de la table interdit déjà zéro, mais la
  -- fonction est appelable directement et une division par zéro ne dirait rien d'utile.
  SELECT greatest(
           min_resolve_votes,
           least(
             max_resolve_votes,
             ceil(confirmations::numeric / greatest(confirmations_per_resolve_vote, 1))::int
           )
         );
$$;

---------------------------------------------------------------------------
-- Recalcul des compteurs depuis le journal
---------------------------------------------------------------------------
-- Les compteurs de `hazards` sont des vues matérialisées du journal : cette fonction est
-- une fonction pure du contenu de `events`. Si un device vandalise, on neutralise ses
-- événements et on rappelle recompute_hazard() : rien n'est perdu (§5).
--
-- Retour à `active` après un « confirmer » (§6.1) : le poids « résolu » n'est pas remis à
-- zéro en effaçant des lignes, mais en ne comptant que les votes « résolu » postérieurs au
-- dernier `create`/`confirm`. L'ordre retenu est celui du `id` bigserial et non de
-- `created_at`, pour rester déterministe quand deux événements partagent un horodatage.
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

  -- Le danger a pu disparaître sous nos pieds : une purge (§4.3) supprime la ligne, ce qui
  -- cascade sur ses événements et redéclenche ce recalcul. Il n'y a alors plus rien à faire.
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
  WHERE e.hazard_id = p_hazard;

  SELECT coalesce(sum(e.weight), 0)::real
    INTO v_resolve
    FROM events e
   WHERE e.hazard_id = p_hazard
     AND e.type = 'mark_resolved'
     AND (v_reset_id IS NULL OR e.id > v_reset_id);

  v_threshold := resolve_threshold(greatest(v_confirmations, 1), v_min_votes, v_per_vote, v_max_votes);

  IF v_remove_id IS NOT NULL AND (v_restore_id IS NULL OR v_restore_id < v_remove_id) THEN
    v_status := 'removed';
  ELSIF v_current = 'archived' THEN
    -- L'archivage vient du cron d'expiration (§6.4) : le journal ne le contredit pas.
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

CREATE OR REPLACE FUNCTION events_recompute_trigger()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM recompute_hazard(OLD.hazard_id);
  ELSE
    PERFORM recompute_hazard(NEW.hazard_id);
  END IF;
  RETURN NULL;
END
$$;

DROP TRIGGER IF EXISTS events_recompute ON events;
CREATE TRIGGER events_recompute
  AFTER INSERT OR UPDATE OR DELETE ON events
  FOR EACH ROW EXECUTE FUNCTION events_recompute_trigger();

---------------------------------------------------------------------------
-- Enregistrement d'un événement
---------------------------------------------------------------------------
-- Idempotent deux fois : par `client_id` (rejeu d'une action hors-ligne, §10) et par
-- l'index unique (hazard_id, device_id, type) qui borne à une action de chaque type par
-- danger et par device (§6.3). Dans les deux cas on ne lève pas d'erreur : le client
-- réaffiche l'état renvoyé par le serveur.
CREATE OR REPLACE FUNCTION record_event(
  p_client_id  uuid,
  p_hazard_id  uuid,
  p_device_id  uuid,
  p_type       event_type,
  p_device_lat double precision DEFAULT NULL,
  p_device_lng double precision DEFAULT NULL,
  p_payload    jsonb DEFAULT NULL
) RETURNS smallint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_geom geometry;
  v_tier smallint;
BEGIN
  SELECT h.geom INTO v_geom FROM hazards h WHERE h.id = p_hazard_id;

  -- La position du déclarant s'arrête ici : seul le palier est écrit (§6.2, §11.1).
  v_tier := proximity_tier(v_geom, p_device_lat, p_device_lng);

  INSERT INTO events (client_id, hazard_id, device_id, type, proximity, weight, payload)
  VALUES (p_client_id, p_hazard_id, p_device_id, p_type, v_tier, proximity_weight(v_tier), p_payload)
  ON CONFLICT DO NOTHING;

  RETURN v_tier;
END
$$;

-- Un device est créé à la volée, sans autre donnée que son UUID (§11.1).
CREATE OR REPLACE FUNCTION ensure_device(p_device_id uuid)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  INSERT INTO devices (id) VALUES (p_device_id) ON CONFLICT (id) DO NOTHING;
$$;
