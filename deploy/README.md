# Déploiement

Deux gestes, et rien d'autre à retenir :

```sh
./deploy/install-vps.sh            # sur le VPS, une fois — puis à chaque mise à jour du serveur
./deploy/release-app.sh --bump patch   # sur le Mac, à chaque version de l'app
```

Le reste de ce fichier explique ce qu'ils font, ce qu'ils refusent de faire, et ce qu'il
faut avoir sauvegardé pour que la bêta survive à la perte d'une machine.

Pour monter **une nouvelle instance de zéro** — autre nom, autre identité Android, autre
serveur — suivre plutôt [NEW-INSTANCE.md](NEW-INSTANCE.md), qui reprend tout pas à pas, avec
les pannes déjà rencontrées et ce qui les répare.

Licence : **AGPL-3.0**, comme le reste du serveur (SPEC §12.1).

## Ce qui est là

| Fichier | Rôle |
|---|---|
| `vps.env.example` | Gabarit de configuration. À copier en `vps.env`, **jamais versionné**. |
| `keystore.sh` | Crée la clé de publication de l'app. **Une fois, pour toujours.** |
| `install-vps.sh` | Provisionne le VPS de zéro, et le remet à jour ensuite. Tourne **sur le VPS**. |
| `release-app.sh` | Construit, signe, vérifie et publie une version de l'app. Tourne **sur le Mac**. |
| `vps-publish.sh` | Régénère l'index F-Droid et la page de téléchargement. Appelé par les deux autres. |
| `apk-page.html` | Le gabarit de la page qu'on donne aux testeurs. |
| `push-server.sh` | Envoie le dépôt sur le VPS, et lance l'installation avec `--install`. Tourne **sur le Mac**. |
| `rsync-exclude.txt` | Ce qui ne monte jamais sur le VPS. Trois entrées y écraseraient son état. |

## Où se règle quoi

Trois fichiers, et rien n'est écrit deux fois.

| Fichier | Versionné | Ce qu'il porte |
|---|---|---|
| `app/android/app.properties` | oui | L'**identité publiée** de l'app : son `applicationId`, l'`author` qui signe, et le `summary`, la phrase qui la présente en tête de la page `/apk` et sur la fiche F-Droid. Lu par Gradle au build **et** par les scripts de `deploy/`. |
| `deploy/vps.env` | non | Le **domaine**, la cible SSH, l'empreinte de la clé de publication, l'étendue du fond de carte. |
| `server/.env` | non, **généré** | Les secrets de la base et de PostgREST. Produit par `install-vps.sh`, jamais écrasé ensuite. |

**Le domaine ne s'écrit qu'une fois**, dans `vps.env`. De là, `install-vps.sh` le recopie dans
`server/.env`, d'où Caddy et Compose le lisent ; et `release-app.sh` le fige dans l'APK par
`--dart-define`. Il n'y a aucun troisième endroit à penser à changer.

**L'`applicationId` ne s'écrit qu'une fois**, dans `app.properties`. Il nomme l'APK publié, la
fiche du dépôt F-Droid, et l'application sur le téléphone. Deux copies auraient fini par
diverger, et le dépôt aurait annoncé une application que l'APK n'est pas — ce qui ne se voit
qu'au moment où un testeur lit « échec de l'installation ». `release-app.sh` relit d'ailleurs
l'identité dans l'APK construit et refuse de publier si elle ne correspond pas.

## Ce que les testeurs voient

`https://<domaine>/apk` — une page qui propose deux chemins.

**Par F-Droid**, l'adresse d'un dépôt à ajouter une fois. Le client vérifie, télécharge et
prévient à chaque nouvelle version. C'est ce qui rend une bêta de plusieurs mois tenable :
personne n'a à revenir sur la page, et personne ne reste six semaines sur une vieille
version sans le savoir.

**Ou le fichier directement**, pour qui ne veut pas de F-Droid. Même APK, même signature,
mais aucune mise à jour automatique.

Les deux sont servis par Caddy en statique, depuis `server/fdroid/`.

---

## Première installation

### 1. Un domaine, deux enregistrements

Deux `A` vers l'IP du VPS. Sans eux, Caddy ne peut obtenir aucun certificat et l'installation
s'arrête là.

```
app.example.org         → 203.0.113.10
admin.app.example.org   → 203.0.113.10
```

### 2. La configuration, des deux côtés

```sh
cp deploy/vps.env.example deploy/vps.env
$EDITOR deploy/vps.env
```

Le même fichier sert sur le Mac et sur le VPS. Il ne contient aucun secret — domaine, cible
SSH, empreinte de certificat — le recopier tel quel est sans risque.

### 3. La clé de publication, sur le Mac

```sh
./deploy/keystore.sh
```

Elle est créée dans `~/.app`, hors du dépôt, et son empreinte est inscrite dans
`vps.env`. **La sauvegarder tout de suite**, avec `app/android/key.properties` qui porte son
mot de passe : la perdre, c'est perdre l'application. Android identifie une app par le couple
(applicationId, clé) ; une version signée autrement ne s'installe pas par-dessus, et chaque
testeur devrait désinstaller — donc perdre son identifiant de terminal, son cache et ses
zones hors ligne.

### 4. Le serveur

Envoyer le dépôt sur le VPS, puis lancer l'installation depuis la machine. `rsync` doit exister
des deux côtés, et une Debian fraîche ne l'a pas : le script l'installe, mais il arrive lui-même
par `rsync`. D'où la première ligne, une seule fois.

```sh
ssh root@203.0.113.10 'apt-get update -qq && apt-get install -y -qq rsync'
./deploy/push-server.sh --install
```

`push-server.sh` est un `rsync` vers `root@<domaine>:/opt/app/`, avec deux choses qu'on oublie
en le tapant : la liste [`rsync-exclude.txt`](rsync-exclude.txt), qui retient trois choses
dont deux écraseraient l'état du serveur de façon irréparable, et la lisibilité de ce qui
monte, sans quoi l'utilisateur de publication ne peut pas lire `vps.env`. **Ne pas le
remplacer par un `rsync -a` nu.** `deploy/vps.env` voyage avec le reste : c'est voulu.

Compter une heure, dont l'essentiel pour extraire les 9,4 Go de fond de carte. Le script
installe Docker, tire les secrets au sort, monte la base, applique les migrations, télécharge
les tuiles et initialise le dépôt F-Droid. Il est rejouable : relancé, il ne refait que ce qui
manque.

À la fin il imprime l'adresse du dépôt F-Droid, **empreinte comprise**. C'est celle-là qu'on
donne aux testeurs, et elle ne doit plus changer.

### 5. Un modérateur

```sh
cd /opt/app/server && make admin-add EMAIL=moderation@example.org
```

### 6. La première version de l'app

Depuis le Mac :

```sh
./deploy/release-app.sh --version 0.1.0
```

---

## Publier une version

```sh
./deploy/release-app.sh --bump patch     # 0.1.0 → 0.1.1
./deploy/release-app.sh --bump minor     # 0.1.0 → 0.2.0
./deploy/release-app.sh --version 1.0.0
./deploy/release-app.sh --rebuild        # même numéro, nouveau build
```

Dans l'ordre : il écrit le numéro de version dans `pubspec.yaml` **et** dans `config.dart`,
lance `flutter analyze` et `flutter test`, construit l'APK release avec les adresses de
l'instance figées dedans, vérifie la signature et les permissions, dépose le fichier sur le
VPS, régénère l'index F-Droid, puis commite et étiquette la version localement.

`--dry-run` fait tout sauf publier, et remet les numéros de version comme avant.
`--no-git` n'exige pas un arbre propre et ne commite rien.

### Prévenir les testeurs qui n'ont pas F-Droid

Le dépôt F-Droid prévient tout seul ceux qui l'ont ajouté. Pour les autres, l'app lit à
chaque lancement `https://<domaine>/fdroid/latest.json`, écrit par `vps-publish.sh`, et
affiche un bandeau si le `versionCode` publié dépasse le sien. Toucher le bandeau télécharge
l'APK ; Android propose l'installation par-dessus l'ancienne. La requête ne porte rien, ni
identifiant ni version installée, et l'app refuse un APK annoncé sur un autre domaine.

Deux options de `release-app.sh` alimentent ce fichier :

```sh
./deploy/release-app.sh --bump patch --note "Corrige l'envoi hors ligne"
./deploy/release-app.sh --bump patch --require
```

`--note` est une ligne libre, conservée tant que la version ne change pas. `--require` fait
de cette version le minimum : en dessous, le bandeau dit « mise à jour nécessaire » et passe
devant tout le reste. À réserver aux versions qui corrigent un envoi faux, ou que le serveur
n'accepte plus. Le minimum reste acquis aux publications suivantes.

### Ce qu'il refuse

- **Un APK signé par une autre clé que celle de `vps.env`.** C'est la vérification qui compte
  le plus : personne ne s'aperçoit d'une signature qui a changé avant que les testeurs ne
  voient « échec de l'installation », et à ce moment-là il est trop tard.
- **Un APK signé en debug.** La clé de debug est publique et identique pour tous les SDK
  Android : n'importe qui pourrait signer une mise à jour de l'application.
- **Un arbre de travail modifié.** Un APK en circulation doit correspondre à un commit,
  sinon plus personne ne peut dire quel code tourne sur les téléphones.
- **Une app qui demande `ACCESS_BACKGROUND_LOCATION`** (§11.1). Une permission peut entrer
  par fusion de manifeste, sans que rien dans le code ne le dise.

### Le versionCode monte toujours

Y compris pour un `--rebuild`. C'est le seul nombre qu'Android et F-Droid comparent pour
décider qu'il y a une mise à jour ; deux APK différents sous le même versionCode donnent un
dépôt dont le client ne sait plus quoi faire.

---

## Mettre le serveur à jour

```sh
./deploy/push-server.sh --install
```

Le script reconstruit les images, applique les migrations en attente — chaque fichier une
fois, inscrit dans `schema_migrations` ; la première qui échoue arrête l'installation, la base
n'a pas bougé — et recharge le cache de schéma de PostgREST. Le volume de données et le `.env`
ne sont jamais touchés.

---

## À sauvegarder, et ce que coûte chaque perte

| Quoi | Où | Si c'est perdu |
|---|---|---|
| `~/.app/app-release.jks` + `app/android/key.properties` | Mac | **L'application est perdue.** Plus aucune mise à jour possible ; il faut un nouvel applicationId et une réinstallation manuelle chez chaque testeur. |
| `server/fdroid/keystore.p12` + `server/fdroid/config.yml` | VPS | Chaque testeur doit retirer puis rajouter le dépôt : son empreinte est dans l'URL. |
| `server/.env` | VPS | Les secrets de la base. Récupérables depuis le volume, mais douloureusement. |
| Le volume `pgdata` | VPS | Tous les signalements. |

Les deux premiers ne se régénèrent pas. Les sauvegarder est une étape de l'installation, pas
une bonne pratique à faire plus tard.

---

## Détails qui se paient cher si on les ignore

**Le profil `tiles` n'est pas optionnel en production.** MapLibre Native attend des tuiles
`/z/x/y` ; sans le conteneur `tileserver`, le style servi renvoie un 502 et la carte est
blanche. `make up` ne le démarre pas — `install-vps.sh` si. C'est la différence entre la
commande de développement et ce qui doit tourner sur le VPS.

**L'APK n'embarque pas `x86_64`.** Les bibliothèques natives pèsent une trentaine de
mégaoctets par architecture : les trois font 90 Mo, deux en font 69. `x86_64` ne sert qu'aux
émulateurs, où l'on travaille en debug. Pour descendre à ~45 Mo, mettre
`TARGET_PLATFORMS=android-arm64` dans `vps.env` — tout appareil Android 13 est en arm64, mais
un vieux téléphone de test en armv7 ne pourra plus installer.

**R8 ne tourne qu'en release.** Les règles de `app/android/app/proguard-rules.pro` n'ont donc
aucun effet visible en développement, et leur absence ne se voyait pas avant la première
tentative de publication : R8 refusait de compiler à cause des classes Google Play Services
que le projet exclut volontairement (§12.6). Elles sont listées nommément, et pas en
`com.google.android.gms.**`, pour que l'arrivée d'une nouvelle référence casse le build au
lieu de passer inaperçue.

**Le cache de tuiles de MapLibre est indexé par URL.** Changer `SITE_DOMAIN` après coup vide
d'un coup le fond de carte gardé sur chaque téléphone, et les zones téléchargées hors ligne
avec. À choisir avant la première version publiée.

---

## L'identité publiée

**L'`applicationId` vaut `mov.safecity`** (safecity.mov à l'envers), dans `app/android/app.properties`. Il ne se change plus
après la première publication : le dépôt F-Droid traiterait une nouvelle valeur comme une autre
application, personne ne recevrait la mise à jour, et les deux cohabiteraient sur le téléphone
de qui installe les deux. La spec le signalait comme à trancher avant la semaine 7 (§12.6) —
c'est maintenant, et c'est le seul point de ce déploiement qui n'est pas réversible d'une
commande.

Tant que rien n'est publié, le changer est une ligne à éditer, et rien d'autre. Le `namespace`
Kotlin, lui, reste `me.safe` : il nomme la classe R et résout les noms relatifs du manifeste,
donc il suit l'arborescence des sources. Android n'exige pas que les deux soient égaux —
vérifié sur un build où ils diffèrent, le manifeste fusionné pointe toujours sur
`me.safe.MainActivity`.

---

## Quand ça ne marche pas

**Caddy n'obtient pas de certificat.** Les `A` ne pointent pas encore, ou le port 80 est
fermé. `docker compose logs caddy`.

**`fdroid update` échoue.** L'APK est quand même en ligne et téléchargeable ; c'est
seulement la mise à jour automatique qui ne part pas. Le journal est dans
`/tmp/fdroid-update.log` sur le VPS. Après correction :

```sh
ssh app@<domaine> /opt/app/deploy/vps-publish.sh
```

**Un testeur voit « échec de l'installation ».** Presque toujours une signature qui a changé,
ou un APK signé en debug installé plus tôt. `release-app.sh` empêche le premier cas ; pour le
second, désinstaller d'abord.

**PostgREST répond 503.** Le cache de schéma n'est pas chargé. `docker compose restart rest`,
et regarder `docker compose logs rest`.
