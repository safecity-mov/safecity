-- L'application — catalogue des types de danger (SPEC §3).
-- Statut : gelé. Seul `pothole` est activé pendant le pilote. Les six autres sont insérés
-- avec enabled = false pour garantir que le modèle et l'UI supportent le multi-type sans refonte.
-- Activer un type : UPDATE hazard_types SET enabled = true WHERE code = '...';

INSERT INTO hazard_types
  (code,        label_fr,                                     icon,        resolved_label_fr, default_ttl_days, dedup_radius_m, enabled, sort_order)
VALUES
  ('pothole',   'Nid-de-poule',                               'pothole',   'Réparé',                       180,             15, true,   10),
  ('slippery',  'Rails / pavés / plaque glissante',           'slippery',  'Corrigé',                      365,             15, false,  20),
  ('manhole',   'Plaque d''égout affaissée ou manquante',     'manhole',   'Réparé',                       180,             15, false,  30),
  ('debris',    'Verre brisé, gravats, débris',               'debris',    'Nettoyé',                        7,             15, false,  40),
  ('curb',      'Bordure / marche dangereuse',                'curb',      'Corrigé',                      365,             15, false,  50),
  ('works',     'Chantier non sécurisé',                      'works',     'Terminé',                       30,             15, false,  60),
  ('lighting',  'Éclairage défaillant',                       'lighting',  'Rétabli',                       90,             15, false,  70)
ON CONFLICT (code) DO NOTHING;
