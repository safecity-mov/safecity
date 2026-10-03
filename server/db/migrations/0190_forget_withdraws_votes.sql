-- L'application — 0190 : « Effacer mes données » retire ses votes, et un terminal tout neuf
-- attend un quart d'heure avant de pouvoir dire « résolu » (§6.3 et §11.4 amendés).
--
-- Le trou : « résolu », effacer mes données, « résolu ». L'effacement coupait le lien mais
-- laissait le vote compté ; l'identifiant neuf n'était plus gêné par l'index « un vote par
-- terminal et par danger », dont le vote précédent n'avait plus de terminal. Deux tours, et
-- un nid-de-poule bien réel quittait la carte, à une seule personne.
--
-- Deux réponses, l'une pour le bouton, l'autre pour la réinstallation.
--
-- 1. Effacer ses données retire ses votes. Une confirmation ou un « résolu » est une donnée
--    de la personne, elle part avec le reste : `cancelled_at`, comme un bannissement, et le
--    trigger de recalcul refait les compteurs. Les créations restent : ce sont des faits sur
--    la rue (§11.4), et « Retirer mes signalements récents » existe pour elles. Le bouton
--    devient inutile pour tricher : chaque tour annule le vote du tour précédent.
--
-- 2. Un terminal vu depuis moins de quinze minutes ne peut pas dire « résolu ». Réinstaller
--    l'app, ou effacer ses données dans Android, donne un identifiant neuf sans passer par le
--    serveur : le vote précédent reste compté, et rien ne le rattache plus à personne. On ne
--    peut pas l'empêcher sans compte (§6.3, assumé), on peut le rendre lent : un quart d'heure
--    par voix. Le refus dit combien il reste à attendre, l'app affiche ce message tel quel.
--    Le compteur part du premier geste vu par le serveur (`devices.created_at`), pas de
--    l'installation, et ce premier geste peut être le refus lui-même : d'où une réponse 400
--    posée par `response.status` et non une exception, qui annulerait la ligne `devices`
--    tout juste créée et ferait repartir le compteur à chaque essai. La transaction est
--    validée ; l'app, elle, voit un refus ordinaire avec son message (§8). Créer et
--    confirmer restent libres : ils ajoutent à la carte, ils n'en retirent rien.
CREATE OR REPLACE FUNCTION forget_device(device_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_votes   bigint;
  v_events  bigint;
  v_hazards bigint;
BEGIN
  -- Avant de couper le lien : après, on ne saurait plus lesquels sont les siens.
  UPDATE events e SET cancelled_at = now()
   WHERE e.device_id = forget_device.device_id
     AND e.cancelled_at IS NULL
     AND e.type IN ('confirm', 'mark_resolved', 'flag');
  GET DIAGNOSTICS v_votes = ROW_COUNT;

  UPDATE events e SET device_id = NULL WHERE e.device_id = forget_device.device_id;
  GET DIAGNOSTICS v_events = ROW_COUNT;

  UPDATE hazards h SET created_by = NULL WHERE h.created_by = forget_device.device_id;
  GET DIAGNOSTICS v_hazards = ROW_COUNT;

  UPDATE photos p SET device_id = NULL WHERE p.device_id = forget_device.device_id;

  DELETE FROM devices d WHERE d.id = forget_device.device_id AND d.banned_at IS NULL;

  RETURN jsonb_build_object(
    'events_anonymized', v_events,
    'hazards_anonymized', v_hazards,
    'votes_withdrawn', v_votes
  );
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
  v_wait   integer;
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

  -- Le quart d'heure de carence. Arrondi à la minute supérieure : « dans 1 min » plutôt que
  -- « dans 0 min » à quelques secondes de la fin.
  SELECT ceil(extract(epoch FROM (d.created_at + interval '15 minutes' - now())) / 60)::integer
    INTO v_wait
    FROM devices d WHERE d.id = mark_resolved.device_id;
  IF v_wait > 0 THEN
    PERFORM set_config('response.status', '400', true);
    RETURN jsonb_build_object(
      'message', format('Ce téléphone vient d''arriver : marquer un danger résolu sera possible dans %s min.', v_wait)
    );
  END IF;

  PERFORM record_event(mark_resolved.client_id, mark_resolved.id, mark_resolved.device_id,
                       'mark_resolved', mark_resolved.proximity);

  RETURN hazard_json(mark_resolved.id);
END
$$;

NOTIFY pgrst, 'reload schema';
