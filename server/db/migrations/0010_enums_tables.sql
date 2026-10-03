-- L'application — schéma de données (SPEC §5).
-- Le journal `events` est la source de vérité ; les compteurs de `hazards` en dérivent
-- par trigger (voir 0030_moderation_core.sql).

DO $$ BEGIN
  CREATE TYPE hazard_status AS ENUM ('active', 'disputed', 'resolved', 'removed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE event_type AS ENUM ('create', 'confirm', 'mark_resolved', 'remove', 'flag', 'restore', 'photo_add');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Catalogue des types de danger : la donnée pilote l'UI (§3).
CREATE TABLE IF NOT EXISTS hazard_types (
  code               text PRIMARY KEY,
  label_fr           text NOT NULL,
  icon               text NOT NULL,                    -- nom d'icône côté app
  resolved_label_fr  text NOT NULL,                    -- « Réparé », « Nettoyé »...
  default_ttl_days   int  NOT NULL,                    -- passage en 'disputed' sans confirmation (§6.4, reporté)
  dedup_radius_m     int  NOT NULL DEFAULT 15,
  enabled            bool NOT NULL DEFAULT false,      -- pilote la CRÉATION, jamais l'affichage (§4.3)
  sort_order         int  NOT NULL DEFAULT 100
);

-- Les seuils de résolution du §6.1, valables pour tous les types (amendement ; le plancher
-- vivait dans `hazard_types`, par type). C'est une règle de modération, pas une propriété
-- d'un nid-de-poule : la bêta doit pouvoir la corriger en la regardant tourner, depuis la
-- console et sans déploiement.
--
-- Une seule ligne, tenue par la clé primaire : une table à deux lignes poserait aussitôt la
-- question de savoir laquelle s'applique.
CREATE TABLE IF NOT EXISTS moderation_settings (
  id                             int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  -- Ce qu'il faut de voix « résolu » sur un danger tout neuf.
  min_resolve_votes              int NOT NULL DEFAULT 2
    CHECK (min_resolve_votes BETWEEN 1 AND 10),
  -- Combien de confirmations exigent une voix de plus : à 3, un danger vu par neuf personnes
  -- demande trois votes pour disparaître.
  confirmations_per_resolve_vote int NOT NULL DEFAULT 3
    CHECK (confirmations_per_resolve_vote BETWEEN 1 AND 100),
  -- Sans plafond, un danger très confirmé deviendrait impossible à résoudre.
  max_resolve_votes              int NOT NULL DEFAULT 5
    CHECK (max_resolve_votes BETWEEN 1 AND 20),
  updated_at                     timestamptz NOT NULL DEFAULT now(),
  -- Un plafond sous le plancher ne casserait rien — `greatest` gagne — mais il rendrait
  -- l'écran illisible : deux réglages qui se contredisent, dont un seul s'applique.
  CHECK (max_resolve_votes >= min_resolve_votes)
);

INSERT INTO moderation_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE moderation_settings IS
  'Les seuils du §6.1, les mêmes pour tous les types. Lue par l''app comme proximity_tiers : '
  'elle annonce « 1 vote sur 2 » sur un signalement qui n''est pas encore parti.';

-- Identité anonyme : UUID généré côté client, stocké en secure storage (§0, §11).
CREATE TABLE IF NOT EXISTS devices (
  id          uuid PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  reputation  int NOT NULL DEFAULT 0,                  -- modélisée, non appliquée en bêta (§4.6)
  banned_at   timestamptz
);

CREATE TABLE IF NOT EXISTS hazards (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type               text NOT NULL REFERENCES hazard_types(code),
  geom               geometry(Point, 4326) NOT NULL,           -- pleine précision, aucun bruit (§11.6)
  severity           smallint NOT NULL CHECK (severity BETWEEN 1 AND 3),
  status             hazard_status NOT NULL DEFAULT 'active',
  description        text CHECK (char_length(description) <= 140),
  address            text,                                     -- cache géocodage inverse
  source             text NOT NULL DEFAULT 'user',             -- 'user' en v1 ; réservé pour un import futur
  created_by         uuid REFERENCES devices(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  last_confirmed_at  timestamptz NOT NULL DEFAULT now(),
  -- Compteurs dérivés du journal `events` (maintenus par trigger)
  confirmations      int  NOT NULL DEFAULT 1,
  resolve_weight     real NOT NULL DEFAULT 0,
  flags              int  NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS hazards_geom_idx   ON hazards USING gist (geom);
CREATE INDEX IF NOT EXISTS hazards_status_idx ON hazards (status, type);

-- Journal append-only : source de vérité, rejouable (§5).
CREATE TABLE IF NOT EXISTS events (
  id           bigserial PRIMARY KEY,
  client_id    uuid UNIQUE NOT NULL,          -- idempotence (généré côté client, §10)
  hazard_id    uuid NOT NULL REFERENCES hazards(id) ON DELETE CASCADE,
  device_id    uuid REFERENCES devices(id),   -- mis à NULL au bout de 24 h (§11.2, 0050)
  type         event_type NOT NULL,
  -- La position du déclarant n'arrive JAMAIS jusqu'ici : l'app en déduit elle-même un palier
  -- sur trois valeurs, et n'envoie que lui (§6.2, §11.1, 0100).
  proximity    smallint CHECK (proximity BETWEEN 1 AND 3),
  weight       real NOT NULL DEFAULT 1,
  payload      jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS events_hazard_idx ON events (hazard_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS events_one_per_device
  ON events (hazard_id, device_id, type) WHERE type IN ('confirm', 'mark_resolved', 'flag');
-- Requis par anonymize_old_events() (§11.2).
CREATE INDEX IF NOT EXISTS events_device_age_idx ON events (created_at) WHERE device_id IS NOT NULL;

-- Administrateurs : le « pas de compte » ne vaut que pour les utilisateurs (§4.3).
-- La console d'administration, partiellement avancée depuis la phase 2, s'authentifie par
-- un jeton dont le `sub` est `user_id` (voir 0070 et admin-token.sh).
CREATE TABLE IF NOT EXISTS admins (
  user_id      uuid PRIMARY KEY,             -- le `sub` du jeton ; auth.users(id) plus tard
  email        text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  disabled_at  timestamptz
);

-- Journal d'audit : append-only, ni modifiable ni supprimable, y compris par un admin (§4.3).
CREATE TABLE IF NOT EXISTS admin_actions (
  id          bigserial PRIMARY KEY,
  admin_id    uuid NOT NULL REFERENCES admins(user_id),
  action      text NOT NULL,
  target      text NOT NULL,
  reason      text,
  snapshot    jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS photos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hazard_id   uuid NOT NULL REFERENCES hazards(id) ON DELETE CASCADE,
  device_id   uuid REFERENCES devices(id),
  object_key  text NOT NULL,                  -- clé S3 / MinIO
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS photos_hazard_idx ON photos (hazard_id);

-- Commentaires de colonnes : ils s'affichent dans Supabase Studio, qui reste là pour
-- regarder, pas pour agir. Sans eux, quelqu'un modifie `reputation` dans l'éditeur de tables
-- et croit avoir agi — la colonne n'est lue nulle part, l'anti-abus est reporté en phase 2
-- (§6.3). Un bouton qui ment est pire que pas de bouton du tout.
-- `devices.banned_at` et `admin_actions`, eux, agissent depuis 0070 : leurs commentaires y
-- sont posés, avec la fonction qui les écrit.
COMMENT ON COLUMN devices.reputation IS
  'SANS EFFET pendant la bêta : la pondération par réputation (§6.3) est reportée en phase 2.';
COMMENT ON COLUMN hazards.flags IS
  'SANS EFFET pendant la bêta : ni signalement d''abus, ni file de modération (§4.6).';
COMMENT ON COLUMN hazards.status IS
  'Dérivé du journal `events` par recompute_hazard() : un UPDATE direct est effacé au '
  'prochain recalcul. Retirer un danger passe par admin_set_hazard_removed() (§4.3).';
