# L'application

App mobile de signalement collaboratif des dangers dans l'espace public en ville, à commencer par les
nids-de-poule. Pilote parisien. Stack 100 % open source, auto-hébergée.

## À lire en premier

**[SPEC.md](SPEC.md) est la source de vérité.** Le cadrage est clos, les décisions sont
récapitulées en §17. Ne pas rouvrir une décision déjà tranchée sans que ce soit demandé.
**[ARCHITECTURE.md](ARCHITECTURE.md)** décrit le système tel qu'il tourne : à lire avant de
toucher au serveur, à l'app ou au déploiement, et à tenir à jour quand ils changent.

## Phase en cours

**Phase 1 : bêta fermée.** Le périmètre exact est en **§4.6**. Tout ce qui n'y figure pas est
reporté en phase 2, même si la spec le décrit en détail.

Reporté, à ne pas construire maintenant : anti-abus automatique (flags, réputation, shadow-ban,
rate limiting), cron d'expiration, site web public, association loi 1901.

**La console d'administration est partiellement avancée** (§4.3 amendé) : retirer un danger,
bannir un terminal, gérer le catalogue. Tout passe par des fonctions SQL qui journalisent dans
`admin_actions`, avec motif obligatoire — jamais par des écritures directes. Supabase Studio
reste là pour regarder, pas pour agir : il n'écrit rien dans le journal d'audit.

## Contraintes non négociables

1. **Minimisation des données (§11).** Elle porte sur le **lien** entre les données, jamais sur
   leur précision. La position du déclarant **ne quitte jamais l'appareil** : l'app en déduit
   elle-même un palier de proximité sur deux valeurs, et n'envoie que ce palier. Le seuil
   vient du serveur (`proximity_tiers`), pour que deux versions de l'app ne pondèrent pas
   différemment. Aucune analytics, aucune télémétrie, aucun appel à un domaine tiers depuis
   l'app. `device_id` mis à `NULL` sur les événements après 24 heures.
2. **Précision géographique et temporelle intacte (§11.6).** La position du danger et les
   horodatages sont stockés à pleine précision, sans arrondi ni bruit. Un nid-de-poule doit être
   localisé à quelques mètres, sinon le produit ne sert à rien. Ne jamais « améliorer » la vie
   privée en dégradant ces deux valeurs.
3. **Aucune dépendance propriétaire (§12.6).** Contrainte F-Droid. Pas de Google Play Services,
   pas de Firebase. En particulier `geolocator` doit être configuré avec
   `AndroidSettings(forceLocationManager: true)`, sinon l'app est rejetée du dépôt F-Droid.
4. **Pas de compte utilisateur.** Identité anonyme par UUID de device, en secure storage.
5. **Le journal `events` est la source de vérité.** Les compteurs de `hazards` en dérivent par
   trigger. Aucune suppression physique côté utilisateur.
6. **Fond de carte auto-hébergé, pas de géocodeur.** PMTiles France métropolitaine sur le VPS ;
   le nom de rue est lu dans les tuiles déjà chargées, Photon est écarté (§7 amendé). Le recrutement de la bêta est parisien, mais **l'app doit fonctionner partout en
   France** : personne ne doit tomber sur une carte blanche en changeant de ville.

## Stack

- **App** : Flutter, `maplibre_gl`, `drift` (SQLite local : catalogue et cache de dangers,
  jamais la file d'attente ni rien qui concerne la personne). Android seul en v0.
- **Serveur** : PostgreSQL 16 + PostGIS 3.4, PostgREST seul devant (pas d'Auth, pas de
  Storage : ni compte ni photo en bêta), Supabase Studio en option locale pour regarder.
  Toute la logique métier vit dans des fonctions SQL exposées en RPC. Le client déclare,
  le serveur décide.
- **Infra** : Docker Compose sur un VPS, Caddy en frontal.
- **Web (phase 2)** : SvelteKit + MapLibre GL JS.

## Conventions

- **Identifiants de code, schéma SQL, noms de fichiers : en anglais** (`hazards`, `report_hazard`,
  `mark_resolved`). C'est ce que fait déjà la spec.
- **Documentation, commentaires, libellés d'interface : en français.**
- Les règles de modération (§6) sont testées en SQL, pas seulement via l'app.

## Licences

- Serveur et surfaces web : **AGPL-3.0**
- App Flutter : **Apache-2.0** (l'AGPL bloquerait une publication iOS ultérieure, cf. §12.2)
- Données : **ODbL 1.0**
- Contributeurs : pseudonymes acceptés, **ni CLA ni DCO** (§12.7).
