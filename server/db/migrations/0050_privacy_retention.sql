-- L'application — minimisation : coupure du lien à 24 heures (SPEC §11.2).
--
-- « La minimisation porte sur le lien entre les données, pas sur leur précision. »
-- Position du danger et horodatages restent intacts (§11.6). Ce qui est borné, c'est la
-- possibilité de relier les actions d'un même terminal entre elles.
--
-- La fenêtre était de 90 jours. Ramenée à 24 heures, elle colle à la seule fonction qui a
-- vraiment besoin du lien : le retrait par le créateur, qui dure exactement 24 h (§6.1).
-- Au-delà, plus rien ne relie deux gestes d'un même terminal, donc plus rien ne redessine
-- un itinéraire habituel — ce qui était le vrai risque (§11.2).
--
-- Le prix est en bas de ce fichier, et il n'est pas nul.

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

  -- `hazards.created_by` porte exactement le même lien que `events.device_id` : le laisser
  -- en place viderait la fenêtre de 24 heures de son sens. Le seul usage de cette colonne est
  -- le retrait par le créateur sous 24 h (§6.1), qui est très loin derrière à ce stade.
  UPDATE hazards h
     SET created_by = NULL
   WHERE h.created_by IS NOT NULL
     AND h.created_at < now() - older_than;
  GET DIAGNOSTICS v_hazards = ROW_COUNT;

  RETURN QUERY SELECT v_events, v_hazards;
END
$$;

COMMENT ON FUNCTION anonymize_old_events(interval) IS
  'Coupe le lien device → actions au-delà de 24 heures (§11.2). Effet de bord connu et accepté '
  'pour la bêta : events_one_per_device porte sur (hazard_id, device_id, type) et deux NULL ne '
  'se contredisent pas, donc un terminal peut re-voter sur un danger passé cette fenêtre — une '
  'voix par jour et par danger, là où le §6.1 veut deux terminaux distincts. L''anti-abus est '
  'reporté en phase 2 (§4.6) ; la parade sans rétablir le lien est un pseudonyme par danger, '
  'hmac(device_id, hazard_id), incomparable d''un danger à l''autre.';

-- Droits d'effacement de l'utilisateur (§11.4), appelés depuis l'écran Paramètres (§4.1 F8).
-- « Effacer mes données » : les signalements restent, ce sont des données sur la voirie.
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

  DELETE FROM devices d WHERE d.id = forget_device.device_id;

  RETURN jsonb_build_object('events_anonymized', v_events, 'hazards_anonymized', v_hazards);
END
$$;

-- Planification : uniquement l'anonymisation. Le cron d'expiration du §6.4 est reporté
-- en phase 2 (§4.6) et n'est délibérément pas créé ici.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('app-anonymize');
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;  -- le job n'existait pas
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Toutes les heures, et non une fois par nuit : à 24 heures de fenêtre, un passage
    -- quotidien laisserait vivre le lien jusqu'à 48 heures selon l'heure du geste.
    PERFORM cron.schedule('app-anonymize', '17 * * * *',
                          'SELECT anonymize_old_events()');
  ELSE
    RAISE NOTICE 'pg_cron absent : lancer « SELECT anonymize_old_events(); » périodiquement';
  END IF;
END
$$;
