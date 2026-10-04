-- L'application — 0250 : l'app déclare son terminal au premier lancement (§6.3 amendé).
--
-- Le quart d'heure de carence avant « Plus là » (0190) court depuis `devices.created_at`, la
-- première fois que le serveur voit l'identifiant. Jusqu'ici, ce premier contact était un
-- geste : quelqu'un qui installe l'app, regarde la carte vingt minutes puis appuie sur
-- « Plus là » se voyait refuser et devait encore attendre. D'où cet appel, que l'app fait une
-- fois par identifiant, à son premier lancement et après « Effacer mes données » : il crée la
-- ligne `devices`, rien d'autre. Le compteur part de l'ouverture de l'app, pas du premier geste.
--
-- Ce que le serveur apprend de plus : qu'un identifiant existe depuis telle date, avant tout
-- geste. C'est la seule donnée ajoutée (§11), et elle part avec « Effacer mes données » comme
-- le reste de la ligne. Idempotent : redéclarer un terminal connu ne touche pas à sa date, un
-- terminal bloqué reste bloqué (ensure_device ne fait rien sur une ligne existante).
CREATE OR REPLACE FUNCTION declare_device(device_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_since timestamptz;
BEGIN
  IF declare_device.device_id IS NULL THEN
    RAISE EXCEPTION 'identifiant de terminal manquant' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM ensure_device(declare_device.device_id);
  SELECT d.created_at INTO v_since FROM devices d WHERE d.id = declare_device.device_id;
  RETURN jsonb_build_object('since', v_since);
END
$$;

REVOKE ALL ON FUNCTION declare_device(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION declare_device(uuid) TO anon;
