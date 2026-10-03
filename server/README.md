# L'application — serveur

PostgreSQL 16 + PostGIS 3.4, PostgREST, Caddy. Toute la logique métier vit dans des
fonctions SQL exposées en RPC : **le client déclare, le serveur décide** (SPEC §8).

Licence : **AGPL-3.0** (§12.1).

## Démarrer

```sh
cp .env.example .env      # puis remplacer toutes les valeurs : openssl rand -hex 32
make up                   # base + API + console d'administration + frontal
make test                 # les règles de modération du §6, en SQL
make tiles                # extrait PMTiles France métropolitaine (~9 Go ; `idf` pour ~300 Mo)
```

> **En production, ne pas se contenter de `make up`.** Il ne démarre pas `tileserver`, qui
> vit dans le profil `tiles` ; or MapLibre Native attend des tuiles `/z/x/y`, et sans lui la
> carte est blanche derrière les marqueurs. C'est
> [`deploy/install-vps.sh`](../deploy/README.md) qui monte l'instance complète, profil
> compris.

`make up` construit l'image de base (PostGIS + pg_cron + pgTAP), applique les migrations dans
l'ordre et démarre PostgREST et la console derrière Caddy. Chaque service attend que le
précédent soit **sain**, pas seulement démarré : PostgREST s'interroge sur `/ready`, publié sur `127.0.0.1:3001`, qui ne
répond 200 qu'une fois la base jointe et le cache de schéma chargé — depuis l'hôte, parce que
l'image amd64 n'a aucun shell où loger un healthcheck Docker. Le volume de données survit
à `make down`. `make migrate` applique les migrations en attente : `db/migrate.sh` tient un
registre, `schema_migrations`, et chaque fichier ne se joue qu'une fois, dans sa transaction
avec son inscription ; le premier échec arrête tout. **Une migration appliquée ne se modifie
plus : ce qui doit changer se fait dans un nouveau fichier.** Jusqu'à 0210, chaque déploiement
rejouait tous les fichiers ; c'est ce rejeu qui a cassé le serveur le 21/09/2026 — l'en-tête
de `0220_repair_after_replay.sql` raconte comment.

> **Sur Mac Apple Silicon**, `postgis/postgis:16-3.4` n'existe qu'en amd64 : Docker l'émule,
> ce qui est lent mais fonctionne. Le VPS cible est x86, l'émulation ne le concerne pas.

## Ce que l'API expose

Rien d'autre que ceci. Le rôle `anon` n'a **aucun droit d'écriture direct** : il a `SELECT`
sur trois tables et trois vues, et `EXECUTE` sur huit fonctions — la liste exacte est vérifiée
par `060_privacy.sql`, PostGIS compris. Toute écriture passe par une fonction qui applique les
règles du §6.

| Appel | Rôle |
|---|---|
| `GET  /rest/v1/hazard_types` | Catalogue des types (§3). L'app le lit au démarrage et en dérive son UI. |
| `GET  /rest/v1/hazard_type_icons_public` | Silhouettes téléversées depuis la console, en base64. |
| `GET  /rest/v1/proximity_tiers` | La règle des paliers du §6.2 : distances et poids, éditables depuis la console. L'app calcule le palier elle-même, avec ces valeurs. |
| `GET  /rest/v1/moderation_settings` | Les seuils de résolution du §6.1, les mêmes pour tous les types. Lus pour annoncer « 1 vote sur 2 » sur un signalement pas encore parti. |
| `GET  /rest/v1/announcements_public` | L'annonce en cours, s'il y en a une : une ligne écrite depuis la console, avec sa date de fin (0230). Lue au lancement et au retour au premier plan, affichée en bandeau. |
| `GET  /rest/v1/hazards_public` | Dangers actifs ou contestés, avec `lat`/`lng` déjà décodés. Un danger résolu n'y figure pas : il quitte la carte (§6.1). |
| `POST /rest/v1/rpc/hazards_in_bbox` | GeoJSON FeatureCollection pour la carte, plus un booléen `truncated` : au-delà de 5 000 dangers la réponse est coupée, et le client ne doit alors rien déduire de ce qui manque. |
| `POST /rest/v1/rpc/hazard_detail` | Détail d'un danger et sa chronologie, **sans `device_id`**. |
| `POST /rest/v1/rpc/report_hazard` | Signaler. Renvoie `{duplicate_of, distance_m}` si un danger du même type est dans le rayon (§4.1 F2b). |
| `POST /rest/v1/rpc/confirm_hazard` | « Toujours là ». Refusé à l'auteur du signalement tant que le lien existe, soit 24 h (§6.1). |
| `POST /rest/v1/rpc/mark_resolved` | Voter « résolu » (§6.1). |
| `POST /rest/v1/rpc/remove_own_hazard` | Retrait par le créateur, sous 24 h. |
| `POST /rest/v1/rpc/remove_own_recent_hazards` | « Retirer mes signalements récents » : tous les siens de moins de 24 h, d'un coup (§11.4 amendé). |
| `POST /rest/v1/rpc/forget_device` | « Effacer mes données » (§11.4) : coupe le lien avec ses gestes et retire ses votes. |

Exemple :

```sh
curl -sX POST https://$SITE_DOMAIN/rest/v1/rpc/report_hazard \
  -H 'Content-Type: application/json' \
  -d '{"client_id":"…","device_id":"…","type":"pothole",
       "lat":48.8566,"lng":2.3522,"severity":2,"proximity":1}'
```

### Deux écarts avec l'esquisse du §8

1. **`device_id` est un paramètre explicite** de chaque écriture. L'esquisse le laisse
   implicite (session anonyme Supabase Auth) ; la bêta n'a pas d'auth, l'app envoie donc
   l'UUID qu'elle garde en secure storage.
2. **`device_pos` n'existe pas : l'app envoie un palier (`proximity`, 1 à 3).** Le serveur ne
   reçoit jamais de coordonnée du déclarant. La règle qui fait la correspondance distance →
   palier est publiée dans `proximity_tiers`, pour que deux versions de l'app pondèrent pareil.

## La vie privée, telle qu'elle est implémentée

- **La position du déclarant n'arrive jamais jusqu'au serveur.** L'app en déduit un palier
  sur trois valeurs, et n'envoie que lui (§6.2, §11.1). `events` n'a aucune colonne de
  géométrie, aucun RPC n'a de paramètre pour en recevoir une, et `060_privacy.sql` et
  `100_local_proximity.sql` le vérifient structurellement.
- **La position du danger et les horodatages sont intacts**, sans arrondi ni bruit (§11.6).
  La minimisation porte sur le lien entre les données, jamais sur leur précision.
- **`anonymize_old_events()`** coupe le lien terminal → actions au-delà de **24 heures**, sur
  `events.device_id`, `hazards.created_by` et `photos.device_id`. Planifiée toutes les heures
  par pg_cron — une fois par nuit laisserait vivre le lien jusqu'à 48 h selon l'heure du
  geste. Contrepartie assumée en bêta : passé la fenêtre, un terminal peut re-voter sur un
  même danger, voir SPEC §11.2. Le cron d'expiration du §6.4, lui, est reporté en phase 2 et
  n'est pas créé.
- **Aucun journal d'accès** : Caddy et PostgreSQL sont configurés pour ne rien écrire (§11.1).
- `created_by` et `events.device_id` ne sont exposés par l'API à personne, **jeton
  d'administration compris** : `admin_api` n'a aucun droit sur `hazards`, `devices` ni
  `events`, seulement sur des vues qui ne portent pas ces colonnes (`070_admin.sql`).

## Les tests

```sh
make test
```

Une base jetable est créée, les migrations y sont appliquées par `migrate.sh`, qui est lui-même
éprouvé — un second passage ne joue rien, et une base d'avant le registre, sur laquelle 0030 a
été rejouée exprès comme le 21/09, est reprise à 0210 et réparée par 0220 — puis les fichiers
de `db/tests` sont joués en pgTAP, puis le jeu d'essai `seed-demo.sql` pour vérifier qu'il suit
encore les signatures des RPC, et la base est supprimée. Rien ne touche la base de travail.

| Fichier | Ce qu'il vérifie |
|---|---|
| `010_schema.sql` | Le schéma est celui du §5, le catalogue celui du §3 |
| `020_rules.sql` | Seuil dynamique (§6.1), ses réglages et leurs bornes, paliers de proximité (§6.2), en isolation |
| `030_report.sql` | Anti-doublon à 15 m, idempotence du `client_id`, catalogue, bornes des entrées, verrous |
| `040_resolve.sql` | « Supprimer = voter résolu » de bout en bout, l'auteur qui ne se confirme pas, et les seuils qui se règlent sans déploiement |
| `050_remove.sql` | Retrait par le créateur, sa fenêtre de 24 h, le drapeau de troncature, et le danger résolu qui quitte la carte |
| `060_privacy.sql` | Ce que le système ne collecte pas, et la liste exacte de ce qu'`anon` et `admin_api` peuvent appeler |
| `070_admin.sql` | Retirer, bannir, journal d'audit ; ce qu'un jeton admin ne lit pas ; un admin désactivé ne lit plus rien |
| `080_ban_author.sql` | Bannir depuis un danger sans jamais rendre l'identifiant du terminal |
| `090_icons.sql` | Validation des silhouettes PNG côté base |
| `100_local_proximity.sql` | Le palier est déclaré par l'app ; la règle publiée et la règle appliquée sont les mêmes ; un réglage ne réécrit pas les gestes déjà pesés |
| `170_migrations.sql` | Le registre des migrations, et l'absence des fonctions périmées que le rejeu du 21/09 avait fait renaître |
| `180_announcements.sql` | Les annonces aux testeurs : publiées et retirées avec motif, lues par l'app sans leur auteur, jamais sans fin |

398 assertions au total.

## Administration

Trois actions du §4.3 sont avancées depuis la phase 2, parce que sans elles le seul levier
contre du vandalisme était de retirer les signalements un par un, sans trace : **retirer un
danger**, **bannir un terminal**, **gérer le catalogue**. La console qui les porte est dans
[`../admin`](../admin/README.md).

```sh
make admin-add EMAIL=moderation@example.org   # crée l'admin, imprime son jeton
```

Il n'y a pas d'écran de mot de passe : **le jeton est l'authentification**. Il est délivré à
la main sur la machine qui héberge, ce qui fait de l'accès SSH le vrai facteur. Proportionné à
une bêta fermée de trois comptes au plus, insuffisant pour l'ouverture.

**Révoquer** : `UPDATE admins SET disabled_at = now() WHERE email = '…'`. Toute lecture et
toute action admin passent par `current_admin()`, qui refuse alors le jeton — la console
renvoie à l'écran de connexion. Si c'est `PGRST_JWT_SECRET` qui a fui, le changer révoque tous
les jetons d'un coup.

| Action | Appel |
|---|---|
| Qui suis-je | `POST /rpc/admin_whoami` |
| Retirer / rétablir un danger | `POST /rpc/admin_set_hazard_removed` `{id, removed, reason}` |
| Effacer la précision d'un danger | `POST /rpc/admin_clear_hazard_description` `{id, reason}` — le texte effacé reste dans le journal d'audit, le danger ne bouge pas |
| Bannir l'auteur d'un danger | `POST /rpc/admin_ban_hazard_author` `{hazard_id, reason}` — l'identifiant du terminal ne sort jamais |
| Bannir un terminal | `POST /rpc/admin_ban_device` `{device_id, reason}` — définitif, il n'y a pas de déblocage |
| Icône d'un type | `POST /rpc/admin_set_hazard_icon` `{type_code, png_base64}`, `admin_clear_hazard_icon` |
| Silhouettes par défaut | posées par la migration 0160 (les glyphes de l'app, rendus par `db/icons/render.py`), sauf pour un type déjà réglé depuis la console ; `make icons-default EMAIL=…` y revient, par la même RPC, au nom de cet administrateur |
| Catalogue | `GET/POST/PATCH /hazard_types` — bornes en `CHECK`, chaque écriture journalisée par trigger |
| Vue d'ensemble | `GET /admin_hazards`, `GET /admin_devices`, `GET /admin_actions` |
| Terminaux à contre-courant | `POST /rpc/admin_suspect_devices` `{since?}` — actifs dans la fenêtre (24 h par défaut), avec leurs « résolu » infirmés par une confirmation ultérieure et leurs avis contredits par le collectif ; des totaux, jamais un danger |

Quatre partis pris valent d'être connus.

**Le motif est obligatoire**, et il est écrit avant que l'action n'ait lieu : une action qui
échoue ne laisse donc rien, et une action qui aboutit a forcément sa ligne dans `admin_actions`.
Le journal est en écriture seule, y compris pour un superuser distrait : un trigger refuse
`UPDATE`, `DELETE` et `TRUNCATE`.

**Bannir annule, ne supprime pas.** Le journal est la source de vérité (§5) : les événements du
terminal reçoivent un `cancelled_at`, `recompute_hazard` les ignore, et les compteurs se
recalculent sans eux. Rien n'est troué, et on peut toujours dire ce qui s'est passé.

**Un bannissement est définitif, et il n'y a pas de déblocage.** La fonction a existé et a été
retirée : elle ne rétablissait jamais les dangers — les rétablir en bloc supposerait qu'ils
étaient tous légitimes, ce que personne n'a vérifié — et passé les 24 heures de la fenêtre de
corrélation, elle ne remettait plus aucun geste en jeu non plus, faute de lien. Restait un
bouton qui levait le blocage sans rien réparer, en laissant croire l'inverse.

En cas d'erreur, deux voies. Les dangers retirés se rétablissent un par un avec
`admin_set_hazard_removed` ; leur liste est dans le journal d'audit
(`snapshot -> 'hazards_removed'`). Et la personne repart d'un identifiant neuf depuis son écran
Paramètres (§11.4), ce qui contournait déjà le blocage et reste assumé pendant la bêta.

**`created_by` reste invisible, même à l'admin.** Un modérateur n'a pas besoin de savoir qui a
signalé quoi pour retirer un signalement (§11). Bannir se fait depuis le danger, et c'est le
serveur qui remonte à l'auteur. Le lien n'apparaît qu'au moment d'un bannissement, dans le
journal d'audit.

Ce qui reste reporté : la file de modération, faute de signalements d'abus pour l'alimenter ;
la purge irréversible, sans objet tant qu'il n'y a ni photos ni contenu libre abondant ; le
shadow-ban du §6.3, remplacé ici par un blocage franc — entre gens qui se connaissent, laisser
croire à quelqu'un que ses signalements comptent serait une tromperie inutile.

Supabase Studio reste disponible pour regarder la base : `make studio` sur `127.0.0.1:3000`,
**jamais exposé publiquement**, par tunnel SSH (`ssh -L 3000:127.0.0.1:3000 vps`). Mais il écrit
en direct, sans rien journaliser : les actions passent par les fonctions ci-dessus.

## Le dépôt F-Droid

Caddy sert aussi `server/fdroid/` sur `/fdroid/*`, et renvoie `/apk` vers sa page d'accueil :
les APK signés de la bêta, l'index que le client F-Droid interroge, et la page qu'on donne
aux testeurs. Tout y est statique — rien n'est produit à la demande. Le répertoire est
rempli par [`deploy/`](../deploy/README.md), et son contenu n'est pas versionné.

C'est la voie de distribution décidée en §12.6 : un dépôt personnel auto-hébergé, sans
enregistrement développeur, sans revue, et avec des mises à jour qui arrivent toutes seules
chez les testeurs — ce qui compte pour une bêta qui peut durer.

## Ce qui n'est délibérément pas là

Conformément au périmètre de la bêta (§4.6) :

- **Anti-abus automatique** : ni flags, ni réputation, ni rate limiting. `devices.reputation`,
  `hazards.flags` et la valeur `flag` de `event_type` existent — le modèle les prévoit,
  l'application de la règle attend. `devices.banned_at`, en revanche, **agit** : voir
  Administration.
- **Cron d'expiration** (§6.4) : `default_ttl_days` est renseigné pour chaque type, rien ne
  le consomme. `recompute_hazard()` respecte déjà le statut `archived` pour le jour où il
  arrivera.
- **Site web public**, **Supabase Storage pour les photos**, **géocodage Photon**.
