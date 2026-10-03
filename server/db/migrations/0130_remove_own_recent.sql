-- L'application — 0130 : « Retirer mes signalements récents » (§11.4 amendé).
--
-- Quelqu'un a fait l'idiot avec l'app, ou dix essais pour la découvrir, et veut nettoyer.
-- La carte ne dit pas lesquels sont les siens — `created_by` n'est exposé nulle part (§11.2) —
-- donc les retirer un par un depuis la feuille de détail suppose de les retrouver de mémoire.
-- Ce geste les retire d'un coup, aux mêmes conditions que `remove_own_hazard` : ses propres
-- signalements, créés il y a moins de 24 heures, encore sur la carte.
--
-- Au-delà de 24 heures, il ne reste rien à retirer par construction : le lien terminal →
-- signalement est effacé (0050), et le serveur ne sait plus lesquels sont les siens. C'est la
-- promesse de confidentialité qui borne ce droit, pas une réticence.
--
-- Chaque retrait est un événement `remove` ordinaire dans le journal : rien n'est supprimé
-- physiquement (§5), et un administrateur peut rétablir depuis le journal d'audit.
CREATE OR REPLACE FUNCTION remove_own_recent_hazards(device_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_id      uuid;
  v_removed integer := 0;
BEGIN
  PERFORM assert_not_banned(remove_own_recent_hazards.device_id);

  FOR v_id IN
    SELECT h.id
      FROM hazards h
     WHERE h.created_by = remove_own_recent_hazards.device_id
       AND h.created_at >= now() - interval '24 hours'
       AND h.status <> 'removed'
     ORDER BY h.created_at
       FOR UPDATE
  LOOP
    -- Un client_id par événement : la table l'exige unique. Ce geste ne passe pas par la
    -- file hors-ligne, il n'a donc pas d'idempotence à préserver côté client.
    PERFORM record_event(gen_random_uuid(), v_id, remove_own_recent_hazards.device_id, 'remove');
    v_removed := v_removed + 1;
  END LOOP;

  RETURN jsonb_build_object('removed', v_removed);
END
$$;

REVOKE ALL ON FUNCTION remove_own_recent_hazards(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION remove_own_recent_hazards(uuid) TO anon;

NOTIFY pgrst, 'reload schema';
