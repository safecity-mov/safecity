-- L'application — 0230 : une annonce aux personnes qui utilisent l'app (§4.3 amendé).
--
-- Du 21 au 27/09/2026, le serveur a refusé tous les gestes (voir 0220). Il a fallu prévenir les
-- testeurs de refaire leurs signalements, et il n'existait aucun canal : le seul texte que le
-- serveur sache porter est la `note` de `latest.json`, écrite par le script de publication d'une
-- version, jamais depuis la console, et affichée seulement quand un bandeau de mise à jour est
-- déjà là.
--
-- D'où ceci : un administrateur écrit une ligne dans la console, avec une date de fin ; l'app la
-- lit au lancement et à chaque retour au premier plan, au même moment et de la même façon que
-- l'avis de version, et l'affiche en bandeau. Toucher le bandeau le ferme. L'annonce s'éteint à
-- sa date de fin, ou quand un administrateur la retire.
--
-- Ce que l'app demande ne porte rien — ni identifiant ni version — comme les autres lectures
-- de réglages (§11.5). Ce que la console écrit passe par deux fonctions journalisées avec motif
-- (§4.3), jamais par la table. La table elle-même n'est lisible que par la vue publique, qui ne
-- montre que les annonces en cours et rien de qui les a écrites.

---------------------------------------------------------------------------
-- La table
---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS announcements (
  id           bigserial    PRIMARY KEY,
  body         text         NOT NULL CHECK (length(body) BETWEEN 1 AND 200),
  starts_at    timestamptz  NOT NULL DEFAULT now(),
  ends_at      timestamptz  NOT NULL,
  created_by   uuid         NOT NULL REFERENCES admins(user_id),
  created_at   timestamptz  NOT NULL DEFAULT now(),
  withdrawn_at timestamptz,
  CHECK (ends_at > starts_at)
);

COMMENT ON TABLE announcements IS
  'Annonces courtes aux personnes qui utilisent l''app (§4.3 amendé). Écrites par '
  'admin_publish_announcement(), retirées par admin_withdraw_announcement(), lues par l''app '
  'à travers announcements_public. Une ligne par annonce, jamais modifiée après coup.';
COMMENT ON COLUMN announcements.body IS
  'Le texte du bandeau, 200 caractères au plus : une ligne, pas un article.';
COMMENT ON COLUMN announcements.ends_at IS
  'Obligatoire : une annonce ne reste jamais par oubli.';

ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
-- Aucune policy, pour personne : tout passe par les vues et les fonctions ci-dessous.

---------------------------------------------------------------------------
-- Ce que l'app lit
---------------------------------------------------------------------------
-- En droits du propriétaire, comme hazards_public (0110) : le filtre est dans la vue, et rien
-- de qui a écrit l'annonce n'y figure.
CREATE OR REPLACE VIEW announcements_public AS
  SELECT a.id, a.body, a.starts_at, a.ends_at
    FROM announcements a
   WHERE a.withdrawn_at IS NULL
     AND now() >= a.starts_at
     AND now() <  a.ends_at;
GRANT SELECT ON announcements_public TO anon;

COMMENT ON VIEW announcements_public IS
  'Les annonces en cours, pour l''app : lue au lancement et au retour au premier plan, par une '
  'requête qui ne porte rien (§11.5).';

---------------------------------------------------------------------------
-- Ce que la console voit
---------------------------------------------------------------------------
CREATE OR REPLACE VIEW admin_announcements AS
  SELECT a.id, a.body, a.starts_at, a.ends_at, a.created_at, a.withdrawn_at,
         ad.email AS created_by_email,
         CASE
           WHEN a.withdrawn_at IS NOT NULL THEN 'withdrawn'
           WHEN now() < a.starts_at       THEN 'scheduled'
           WHEN now() >= a.ends_at        THEN 'expired'
           ELSE                                'active'
         END AS state
    FROM announcements a
    JOIN admins ad ON ad.user_id = a.created_by
   WHERE current_admin() IS NOT NULL;
GRANT SELECT ON admin_announcements TO admin_api;

---------------------------------------------------------------------------
-- Publier
---------------------------------------------------------------------------
-- Le motif dit pourquoi on annonce, le corps dit quoi : les deux vont au journal.
CREATE OR REPLACE FUNCTION admin_publish_announcement(body text, ends_at timestamptz, reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := current_admin();
  v_body  text := btrim(coalesce(admin_publish_announcement.body, ''));
  v_row   announcements;
BEGIN
  IF v_body = '' THEN
    RAISE EXCEPTION 'Le texte de l''annonce est vide.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(v_body) > 200 THEN
    RAISE EXCEPTION 'Le texte de l''annonce dépasse 200 caractères (%).', length(v_body)
      USING ERRCODE = 'check_violation';
  END IF;
  IF admin_publish_announcement.ends_at IS NULL
     OR admin_publish_announcement.ends_at <= now() THEN
    RAISE EXCEPTION 'La date de fin est déjà passée.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO announcements (body, ends_at, created_by)
  VALUES (v_body, admin_publish_announcement.ends_at, v_admin)
  RETURNING * INTO v_row;

  PERFORM audit('announcement.publish', v_row.id::text, reason,
                jsonb_build_object('body', v_row.body, 'ends_at', v_row.ends_at));

  RETURN jsonb_build_object('id', v_row.id, 'body', v_row.body,
                            'starts_at', v_row.starts_at, 'ends_at', v_row.ends_at);
END
$$;

REVOKE ALL ON FUNCTION admin_publish_announcement(text, timestamptz, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_publish_announcement(text, timestamptz, text) TO admin_api;

---------------------------------------------------------------------------
-- Retirer
---------------------------------------------------------------------------
-- Une annonce ne se modifie pas : on la retire, et on en publie une autre s'il le faut. Le
-- journal garde ce qui a été dit, et jusqu'à quand.
CREATE OR REPLACE FUNCTION admin_withdraw_announcement(id bigint, reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_row announcements;
BEGIN
  SELECT * INTO v_row FROM announcements a
   WHERE a.id = admin_withdraw_announcement.id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'annonce inconnue : %', admin_withdraw_announcement.id
      USING ERRCODE = 'no_data_found';
  END IF;
  IF v_row.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cette annonce est déjà retirée.' USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM audit('announcement.withdraw', v_row.id::text, reason,
                jsonb_build_object('body', v_row.body, 'ends_at', v_row.ends_at));

  UPDATE announcements a SET withdrawn_at = now()
   WHERE a.id = admin_withdraw_announcement.id;

  RETURN jsonb_build_object('id', v_row.id, 'withdrawn', true);
END
$$;

REVOKE ALL ON FUNCTION admin_withdraw_announcement(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_withdraw_announcement(bigint, text) TO admin_api;

NOTIFY pgrst, 'reload schema';
