# Architecture

Ce que le système est **aujourd'hui**, en bêta : qui parle à qui, et ce qui ne circule jamais.
[SPEC.md](SPEC.md) dit pourquoi ; ce document dit comment. Quand les deux divergent, c'est
celui-ci qui est en retard : le corriger, pas la spec.

## Vue d'ensemble

```
   téléphone Android                          VPS  (Docker Compose, un seul hôte)
 ┌───────────────────────┐                  ┌──────────────────────────────────────────────┐
 │ app Flutter           │   https          │ Caddy  ── TLS, une seule origine ──          │
 │  · carte MapLibre     │ ───────────────► │   /rest/v1/*   ─► PostgREST ─► PostgreSQL     │
 │  · SQLite (drift)     │  4 routes,       │   /tiles/*     ─► fichiers PMTiles + tileserver│
 │    catalogue, cache   │  même domaine    │   /fdroid/*    ─► dépôt F-Droid, page /apk     │
 │  · file en mémoire    │                  │   admin.<dom>  ─► console SvelteKit ─► PostgREST│
 │  · secure storage :   │                  └──────────────────────────────────────────────┘
 │    UUID du terminal   │
 └───────────────────────┘                    Mac de publication : Flutter, clé de signature,
   position GPS : ne sort jamais              deploy/*.sh  ── rsync + ssh ──► VPS
```

Une origine, quatre routes. L'app ne contacte **aucun autre domaine** : pas de fond de carte
tiers, pas de géocodeur, pas de télémétrie (§11.5). Le nom de rue est lu dans les tuiles déjà
chargées.

## Le serveur (`server/`)

| Conteneur | Rôle | Exposé |
|---|---|---|
| `db` | PostgreSQL 16 + PostGIS + pg_cron. Toute la logique métier est en fonctions SQL. | réseau interne |
| `rest` | PostgREST : expose les vues et RPC du schéma `public` au rôle `anon`. | `127.0.0.1:3001` (sonde) |
| `admin` | Console SvelteKit, rendue côté serveur, parle à PostgREST par le réseau interne. | via Caddy |
| `caddy` | Frontal TLS, routage, fichiers statiques, limitation de débit par adresse (en mémoire, image construite avec le module). Aucun journal d'accès, sauf le journal des téléchargements d'APK sans IP. | 80, 443 |
| `tileserver` | Découpe le PMTiles en `/z/x/y` (profil `tiles`). | via Caddy |
| `meta`, `studio` | Supabase Studio, lecture seule de fait (profil `admin`, jamais exposé). | `127.0.0.1:3000` |

**La base décide, le client déclare.** Un signalement, une confirmation, un vote « résolu »
sont des appels RPC ; la fonction SQL vérifie, écrit un événement dans `events`, et les
compteurs de `hazards` en dérivent par trigger (§5, §6). Rien ne s'écrit en direct depuis
l'extérieur : `anon` n'a que `SELECT` sur des vues et `EXECUTE` sur huit fonctions, la liste
exacte étant figée par un test (`db/tests/060_privacy.sql`).

**La console n'écrit que par des fonctions `admin_*`** qui journalisent dans `admin_actions`
avec un motif. Ses jetons sont des lignes en base ; Caddy ne les voit jamais transiter vers
l'extérieur, la console parle à PostgREST en interne.

Les migrations vivent dans `db/migrations/` ; `db/migrate.sh` les applique une fois chacune et
les inscrit dans `schema_migrations`, le premier échec arrête tout, et un fichier appliqué ne se
modifie plus. Les règles de modération et de confidentialité ont leurs tests SQL dans
`db/tests/`, joués sur une base jetable (`make test`).

## L'app (`app/`)

Flutter, Android seul. Un écran principal, la carte, et une feuille par geste.

| Ce qui vit sur le téléphone | Où | Combien de temps |
|---|---|---|
| UUID du terminal | secure storage chiffré | jusqu'à « Effacer mes données » |
| Catalogue des types, règles | SQLite (drift) | remplacé à chaque lecture réussie |
| Cache des dangers, tuiles | SQLite + cache MapLibre | 45 min, purge par alarme système |
| Zones hors ligne | cache MapLibre | jusqu'à suppression par la personne |
| File des gestes hors ligne | **mémoire** | la session |
| Position GPS | mémoire | oubliée en quittant l'écran |

**La position ne quitte jamais l'appareil.** L'app calcule elle-même un palier de proximité
(sur place, ailleurs) avec le seuil venu du serveur, et n'envoie que ce palier.
Le serveur n'a aucune colonne pour une coordonnée de déclarant (§11.1).

**Le natif est réduit à trois choses**, en Kotlin, sans plugin tiers : la localisation par
`LocationManager` (F-Droid refuse les Play Services), la purge des traces par alarme, et
l'ouverture d'une URL pour la mise à jour.

Au lancement et à chaque retour au premier plan, l'app relit le catalogue, demande au
serveur s'il existe une version plus récente (`/fdroid/latest.json`) et s'il y a une annonce
en cours (`announcements_public`). Trois requêtes sans identifiant. Le bandeau d'annonce
se ferme d'un toucher ; l'identifiant de la dernière annonce fermée reste sur l'appareil.

## La console (`admin/`)

SvelteKit sur `admin.<domaine>`, une action par écran : retirer un danger, bannir un
terminal, gérer le catalogue et ses icônes, régler les seuils, publier ou retirer une annonce
que l'app affiche en bandeau, lire le journal d'audit. Elle ne connaît jamais l'auteur d'un
signalement, seulement son terminal quand il faut bannir.

L'icône d'un type se choisit parmi les glyphes Material Symbols, plein ou contour, embarqués
dans la console (paquets `@material-symbols/font-400` et `svg-400`, Apache-2.0, servis par la
console elle-même) : le navigateur peint le tracé SVG en silhouette PNG et l'envoie par
`admin_set_hazard_icon`, exactement comme un fichier téléversé. L'app ne change pas, elle ne
reçoit qu'une silhouette de plus.

## Publication (`deploy/`)

Deux machines, deux clés, jamais mélangées.

- **Le Mac** construit et signe l'APK (`release-app.sh`), vérifie signature, identité,
  permissions, puis dépose le fichier sur le VPS par rsync. La clé de signature de l'APK ne
  quitte jamais le Mac.
- **Le VPS** signe l'index F-Droid (`vps-publish.sh`, clé d'index à lui), rend la page
  `/apk` et `latest.json`, et propose l'APK sous un nom par version (`safe-city-0.5.2.apk`,
  pour que le navigateur n'empile pas des doublons) à côté de l'adresse stable
  `app-latest.apk`. `install-vps.sh` installe et met à jour tout le serveur ;
  `push-server.sh` envoie le dépôt, avec `--install` pour rejouer l'installation ; il refuse un
  arbre modifié ou un commit déjà envoyé, et `--status` dit à quel commit est le serveur
  (trace dans `deploy/DEPLOYED` sur le VPS).

Ce qui est en ligne est toujours un commit : le script refuse un arbre modifié, et étiquette la
version publiée.

## Ce qui n'existe pas, volontairement

- **Aucun compte**, aucune authentification : l'UUID est un porteur, pas une preuve (§11.4).
- **Aucun journal d'accès** avec adresse IP. Le journal des téléchargements d'APK garde
  l'heure, le fichier et la langue du navigateur, jamais l'adresse.
- **Aucune photo** en bêta, donc aucun stockage d'objets.
- **Aucun service tiers** : ni géocodeur, ni suivi d'erreurs, ni analytics, ni push.
- **Aucune suppression physique** côté utilisateur : retirer, c'est écrire un événement.

## Où lire la suite

| Pour | Voir |
|---|---|
| Les décisions et leur pourquoi | [SPEC.md](SPEC.md), §17 pour le récapitulatif |
| Le schéma et les RPC | [server/README.md](server/README.md), `server/db/migrations/` |
| L'app en développement | [app/README.md](app/README.md) |
| Modérer | [admin/README.md](admin/README.md) |
| Mettre en ligne, publier | [deploy/README.md](deploy/README.md), [deploy/NEW-INSTANCE.md](deploy/NEW-INSTANCE.md) |
| Ce que l'app fait des données | [PRIVACY.md](PRIVACY.md) |
