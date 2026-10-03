-- L'application — icônes de danger téléversées depuis la console (§3, §4.3).
--
-- Jusqu'ici `hazard_types.icon` n'était pas une image : c'était un nom, traduit côté app par
-- une correspondance codée en dur (`HazardType.icon`). Conséquence, la promesse du §3 —
-- « ajouter un type est une ligne en base, pas une release » — était fausse pour la moitié du
-- type : son libellé venait de la base, son icône exigeait une publication.
--
-- Une image téléversée ici prend le dessus. Le glyphe embarqué reste le repli : au premier
-- lancement, hors ligne, ou si l'image n'a pas encore été récupérée, l'app dessine toujours
-- quelque chose. Rien ne casse si personne ne téléverse jamais.
--
-- CE QU'ON ATTEND DU FICHIER, ET POURQUOI.
-- Le marqueur est un disque coloré portant une silhouette blanche, qui s'inverse quand le
-- danger est contesté (§9). Une image en couleurs ne pourrait pas s'inverser. L'app n'utilise
-- donc que le **canal alpha** du PNG et le peint elle-même. Le fichier doit être une
-- silhouette pleine sur fond transparent : carrée, entre 32 et 512 px, 64 Ko au plus.

---------------------------------------------------------------------------
-- Lire l'en-tête d'un PNG sans quitter SQL
---------------------------------------------------------------------------
-- La validation vit ici et pas seulement dans la console : c'est la base qui doit refuser un
-- fichier douteux, sinon la règle dépend de qui écrit. IHDR est à position fixe — signature
-- sur 8 octets, longueur et type sur 8, puis largeur et hauteur sur 4 octets chacune.
CREATE OR REPLACE FUNCTION png_dimensions(image bytea)
RETURNS int[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN image IS NULL OR length(image) < 24 THEN NULL
    WHEN substring(image from 1 for 8) <> '\x89504e470d0a1a0a'::bytea THEN NULL
    ELSE ARRAY[
      get_byte(image, 16) * 16777216 + get_byte(image, 17) * 65536
        + get_byte(image, 18) * 256 + get_byte(image, 19),
      get_byte(image, 20) * 16777216 + get_byte(image, 21) * 65536
        + get_byte(image, 22) * 256 + get_byte(image, 23)
    ]
  END;
$$;

COMMENT ON FUNCTION png_dimensions(bytea) IS
  'Largeur et hauteur d''un PNG lues dans son IHDR, ou NULL si ce n''est pas un PNG.';

---------------------------------------------------------------------------
-- L'image
---------------------------------------------------------------------------
-- Table séparée, et non une colonne de plus sur `hazard_types` : le catalogue est relu à
-- chaque lancement de l'app, il n'a pas à transporter des blobs. Les icônes se récupèrent à
-- part, et `updated_at` suffit à savoir s'il faut les reprendre.
CREATE TABLE IF NOT EXISTS hazard_type_icons (
  type_code  text PRIMARY KEY REFERENCES hazard_types(code) ON DELETE CASCADE,
  png        bytea NOT NULL,
  width      int GENERATED ALWAYS AS ((png_dimensions(png))[1]) STORED,
  height     int GENERATED ALWAYS AS ((png_dimensions(png))[2]) STORED,
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT hazard_type_icons_est_png CHECK (png_dimensions(png) IS NOT NULL),
  CONSTRAINT hazard_type_icons_poids   CHECK (length(png) <= 65536),
  CONSTRAINT hazard_type_icons_format  CHECK (
    (png_dimensions(png))[1] = (png_dimensions(png))[2]
    AND (png_dimensions(png))[1] BETWEEN 32 AND 512
  )
);

COMMENT ON TABLE hazard_type_icons IS
  'Silhouette PNG par type de danger. Seul le canal alpha est utilisé : l''app peint la forme '
  'aux couleurs du marqueur (§9). Absente, le glyphe embarqué prend le relais.';

---------------------------------------------------------------------------
-- Ce que l'app lit
---------------------------------------------------------------------------
-- En base64 plutôt qu'en bytea : PostgREST rend un bytea en hexadécimal, soit deux fois le
-- poids pour rien. La vue est la seule porte publique ; la table brute ne l'est pas.
--
-- Les retours à la ligne sont retirés : `encode(..., 'base64')` en pose un tous les 76
-- caractères, ce que le décodeur base64 de Dart refuse. Mieux vaut le corriger ici, une fois,
-- que dans chaque client.
CREATE OR REPLACE VIEW hazard_type_icons_public AS
  SELECT i.type_code, i.width, i.updated_at,
         replace(encode(i.png, 'base64'), E'\n', '') AS png_b64
    FROM hazard_type_icons i;

ALTER TABLE hazard_type_icons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hazard_type_icons_admin ON hazard_type_icons;
CREATE POLICY hazard_type_icons_admin ON hazard_type_icons
  FOR SELECT TO admin_api USING (true);

GRANT SELECT ON hazard_type_icons_public TO anon, admin_api;
GRANT SELECT ON hazard_type_icons TO admin_api;

---------------------------------------------------------------------------
-- Téléverser, retirer
---------------------------------------------------------------------------
-- Par RPC et non par écriture directe : la console envoie du base64, la base décode, vérifie
-- et journalise. Le même geste passé en PATCH obligerait le navigateur à fabriquer de
-- l'hexadécimal PostgREST, et laisserait la validation hors de la base.
CREATE OR REPLACE FUNCTION admin_set_hazard_icon(type_code text, png_base64 text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_png bytea;
  v_dim int[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hazard_types t WHERE t.code = admin_set_hazard_icon.type_code) THEN
    RAISE EXCEPTION 'type inconnu : %', admin_set_hazard_icon.type_code
      USING ERRCODE = 'no_data_found';
  END IF;

  BEGIN
    v_png := decode(png_base64, 'base64');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Fichier illisible.' USING ERRCODE = 'check_violation';
  END;

  v_dim := png_dimensions(v_png);
  IF v_dim IS NULL THEN
    RAISE EXCEPTION 'Ce fichier n''est pas un PNG.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_dim[1] <> v_dim[2] THEN
    RAISE EXCEPTION 'L''image doit être carrée (reçu % × % px).', v_dim[1], v_dim[2]
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_dim[1] < 32 OR v_dim[1] > 512 THEN
    RAISE EXCEPTION 'Côté attendu entre 32 et 512 px (reçu % px).', v_dim[1]
      USING ERRCODE = 'check_violation';
  END IF;
  IF length(v_png) > 65536 THEN
    RAISE EXCEPTION 'Fichier trop lourd : % Ko pour 64 Ko au plus.', round(length(v_png) / 1024.0)
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM audit('type.icon.set', admin_set_hazard_icon.type_code, 'téléversement d''une icône',
                jsonb_build_object('width', v_dim[1], 'bytes', length(v_png)));

  INSERT INTO hazard_type_icons (type_code, png)
  VALUES (admin_set_hazard_icon.type_code, v_png)
  -- Par le nom de la contrainte : `ON CONFLICT (type_code)` serait ambigu, le paramètre de
  -- la fonction porte le même nom que la colonne.
  ON CONFLICT ON CONSTRAINT hazard_type_icons_pkey
    DO UPDATE SET png = EXCLUDED.png, updated_at = now();

  RETURN jsonb_build_object('width', v_dim[1], 'bytes', length(v_png));
END
$$;

CREATE OR REPLACE FUNCTION admin_clear_hazard_icon(type_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_supprime int;
BEGIN
  PERFORM audit('type.icon.clear', admin_clear_hazard_icon.type_code, 'retrait d''une icône');

  DELETE FROM hazard_type_icons i WHERE i.type_code = admin_clear_hazard_icon.type_code;
  GET DIAGNOSTICS v_supprime = ROW_COUNT;

  RETURN jsonb_build_object('removed', v_supprime);
END
$$;

REVOKE ALL ON FUNCTION png_dimensions(bytea)               FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_set_hazard_icon(text, text)   FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_clear_hazard_icon(text)       FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_set_hazard_icon(text, text) TO admin_api;
GRANT EXECUTE ON FUNCTION admin_clear_hazard_icon(text)     TO admin_api;

NOTIFY pgrst, 'reload schema';
