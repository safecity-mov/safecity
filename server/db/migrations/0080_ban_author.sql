-- L'application — bannir depuis un danger, sans jamais montrer l'auteur (§4.3, §11).
--
-- Pourquoi cette fonction existe alors que `admin_ban_device` fait déjà le travail.
--
-- Un modérateur juge ce qu'il voit : un signalement. Pour le sanctionner il lui faut remonter
-- à son auteur. La manière évidente — afficher `created_by` à côté du danger, ou dessiner les
-- signalements d'un terminal sur une carte — reconstituerait exactement ce que le §11 interdit
-- de stocker : une journée de trajets d'une personne, lisible d'un coup d'œil. Le lien existe
-- en base pendant 24 heures, il ne doit pas pour autant remonter dans une interface.
--
-- Donc le geste part du danger, la résolution se fait ici, et l'identifiant du terminal ne
-- franchit jamais la frontière du serveur. Le client déclare, le serveur décide (§8).
--
-- Le journal d'audit, lui, garde l'identifiant : une sanction sans trace de sa cible ne
-- s'examine pas. C'est une exposition assumée, bornée aux terminaux effectivement
-- sanctionnés, et écrite dans une table en écriture seule.

CREATE OR REPLACE FUNCTION admin_ban_hazard_author(hazard_id uuid, reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_device uuid;
  v_result jsonb;
BEGIN
  SELECT h.created_by INTO v_device
    FROM hazards h WHERE h.id = admin_ban_hazard_author.hazard_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger inconnu : %', admin_ban_hazard_author.hazard_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Passé 24 heures, `anonymize_old_events()` a mis `created_by` à NULL (§11.2) : il n'y a
  -- plus d'auteur à qui remonter. Ce n'est pas une panne, c'est la fenêtre de corrélation qui
  -- s'est refermée — et le modérateur doit le lire comme tel.
  IF v_device IS NULL THEN
    RAISE EXCEPTION 'Ce danger n''a plus d''auteur : le lien est coupé au bout de 24 heures. '
                    'Le vandalisme se modère dans la journée, ou plus du tout.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF EXISTS (SELECT 1 FROM devices d WHERE d.id = v_device AND d.banned_at IS NOT NULL) THEN
    RAISE EXCEPTION 'L''auteur de ce danger est déjà banni.' USING ERRCODE = 'unique_violation';
  END IF;

  -- Une seule implémentation du bannissement : celle-ci n'en est que la porte d'entrée.
  -- `admin_ban_device` journalise déjà, motif obligatoire compris.
  v_result := admin_ban_device(v_device, admin_ban_hazard_author.reason);

  RETURN jsonb_build_object(
    'events_cancelled', v_result -> 'events_cancelled',
    'hazards_removed', jsonb_array_length(v_result -> 'hazards_removed')
  );
END
$$;

REVOKE ALL ON FUNCTION admin_ban_hazard_author(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_ban_hazard_author(uuid, text) TO admin_api;

NOTIFY pgrst, 'reload schema';
