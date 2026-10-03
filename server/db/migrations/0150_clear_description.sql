-- L'application — 0150 : effacer la « précision » d'un danger (§4.3 amendé).
--
-- La précision est le seul texte libre que l'app fait remonter (140 caractères, §3). Un
-- nid-de-poule bien réel peut être accompagné d'une insulte, d'un nom, d'un numéro de plaque :
-- retirer le danger serait punir la carte pour un texte. Ce geste efface le texte et laisse
-- le danger, ses compteurs et son journal intacts.
--
-- Même règle que les autres actions d'administration : motif obligatoire, ligne dans le journal
-- d'audit avec le texte effacé en instantané — c'est la seule trace qu'il en restera, et elle
-- permet de juger après coup que l'effacement était fondé. Aucun événement dans `events` : la
-- précision n'y a jamais figuré, ce n'est pas un geste de modération collaborative.
CREATE OR REPLACE FUNCTION admin_clear_hazard_description(id uuid, reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_before text;
BEGIN
  SELECT h.description INTO v_before
    FROM hazards h WHERE h.id = admin_clear_hazard_description.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'danger inconnu : %', admin_clear_hazard_description.id
      USING ERRCODE = 'no_data_found';
  END IF;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'Ce danger n''a pas de précision.' USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM audit('hazard.description.clear', admin_clear_hazard_description.id::text, reason,
                jsonb_build_object('description_before', v_before));

  UPDATE hazards h SET description = NULL WHERE h.id = admin_clear_hazard_description.id;

  RETURN jsonb_build_object('id', admin_clear_hazard_description.id, 'cleared', true);
END
$$;

REVOKE ALL ON FUNCTION admin_clear_hazard_description(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_clear_hazard_description(uuid, text) TO admin_api;

NOTIFY pgrst, 'reload schema';
