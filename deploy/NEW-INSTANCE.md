# Nouvelle instance, de zéro

Un dépôt cloné → une app installable, avec son nom, son identité Android et son serveur.
Une demi-journée, dont une heure d'attente. Il faut : un Mac avec Flutter et Android Studio,
un domaine, un VPS.

## 0. Choisir

| Quoi | Où | Change après publication ? |
|---|---|---|
| `applicationId` (ex. `fr.monapp`, domaine à l'envers) | `app/android/app.properties` | **Jamais** |
| `author` (pseudonyme, visible dans l'APK) | `app/android/app.properties` | **Jamais** |
| `appName` (nom affiché) | `app/lib/src/ui/labels.dart` **et** `AndroidManifest.xml`, identiques | Oui |
| domaine (figé dans l'APK) | `deploy/vps.env` | Non : vide le cache carte des téléphones |

Tout le reste en découle : clé dans `~/.app/<applicationId>-release.jks`, nom du dépôt
F-Droid et titre de la page depuis `appName`.

## 1. Poste

```sh
# 1. copie de travail dédiée (sinon vps.env et key.properties d'une autre instance sont écrasés)
cd ~/Dev/safecycle && git worktree add ../monapp -b monapp && cd ../monapp

# 2. identité
$EDITOR app/android/app.properties                       # applicationId=fr.monapp  author=monpseudo
                                                         # summary=La phrase de la page /apk et de F-Droid
$EDITOR app/lib/src/ui/labels.dart                       # static const appName = 'MonApp';
$EDITOR app/android/app/src/main/AndroidManifest.xml     # android:label="MonApp"

# 3. icônes : remplacer les 5 fichiers
ls app/android/app/src/main/res/mipmap-*/ic_launcher.png

# 4. (optionnel) description longue de la fiche F-Droid
$EDITOR deploy/vps-publish.sh                            # bloc Description:

# 5. configuration
cp deploy/vps.env.example deploy/vps.env
$EDITOR deploy/vps.env
#   SITE_DOMAIN=monapp.fr   ADMIN_DOMAIN=admin.monapp.fr   VPS_SSH=app@monapp.fr   VPS_ROOT=/opt/app

# 6. clé de signature — la perdre = plus aucune mise à jour possible, jamais
./deploy/keystore.sh
#   → SAUVEGARDER hors du Mac, ensemble : ~/.app/fr.monapp-release.jks + app/android/key.properties
#     (key.properties vit dans le dossier de travail : supprimer le dossier, c'est le perdre)

# 7. essai à blanc, puis commit (release-app.sh exige un arbre propre)
./deploy/release-app.sh --version 0.1.0 --dry-run --no-git
#   attendu : ✓ signé par la clé de publication  ✓ identité publiée : fr.monapp  ✓ nom affiché : MonApp
git add -A && git commit -m "MonApp : identité, nom, icône"
```

Ne pas toucher : `namespace = "me.safe"` ni le dossier `kotlin/me/safe/`.

## 2. Serveur

```sh
# 1. VPS : x86 obligatoire (pas la gamme ARM), Ubuntu ou Debian, Falkenstein/Nuremberg/Helsinki
#    minimum Hetzner CX22 : 2 vCPU, 4 Go, 40 Go, 3,79 €/mois
#    à la création, coller la clé PUBLIQUE :
cat ~/.ssh/id_ed25519.pub
#    (pas de clé ? ssh-keygen -t ed25519 — il demande avant d'écraser une existante)

# 2. DNS chez le registrar, type A, TTL 300, vers l'IP du VPS — pas de AAAA
#    @      → monapp.fr
#    admin  → admin.monapp.fr

# 3. vérifier avant de continuer
dig +short monapp.fr && dig +short admin.monapp.fr && ssh root@monapp.fr echo ok

# 4. installer (≈ 1 h, fond de carte)
ssh root@monapp.fr 'apt-get update -qq && apt-get install -y -qq rsync'
./deploy/push-server.sh --install
#   messages normaux : « ERROR: No Android SDK found! », « on attend nous-mêmes »
#   à la fin, NOTER l'adresse du dépôt F-Droid AVEC son empreinte :
#   https://monapp.fr/fdroid/repo?fingerprint=<64 hex>

# 5. SAUVEGARDER hors du serveur (clé d'index + son mot de passe + secrets de la base)
mkdir -p ~/.app/sauvegarde-monapp
scp root@monapp.fr:/opt/app/server/fdroid/{keystore.p12,config.yml} \
    root@monapp.fr:/opt/app/server/.env ~/.app/sauvegarde-monapp/

# 6. vérifier
curl -sS https://monapp.fr/rest/v1/hazard_types | head -c 200          # du JSON
curl -sL https://monapp.fr/apk | grep -o "Aucune version[^<]*"          # la page, vide

# 7. modérateur → imprime le jeton = mot de passe de https://admin.monapp.fr
ssh root@monapp.fr 'cd /opt/app/server && make admin-add EMAIL=moi@monapp.fr'
```

## 3. Publier

```sh
./deploy/release-app.sh --version 0.1.0
```

Tests, build, signature, identité, nom, dépôt sur le serveur, index F-Droid, commit + tag.
Refuse : autre clé que celle de `vps.env`, signature debug, arbre modifié, permission de
position en arrière-plan.

Vérifier sur un téléphone : `https://monapp.fr/apk` → télécharger → autoriser la source →
carte affichée, signalement envoyé. Donner aux testeurs l'adresse du dépôt avec empreinte,
ou `https://monapp.fr/apk`. Sans F-Droid, l'app affiche elle-même un bandeau à chaque
nouvelle version (`latest.json`), qui télécharge l'APK sous un nom par version, `monapp-0.1.0.apk`.

## 4. Ensuite

| Pour | Commande |
|---|---|
| Correction | `./deploy/release-app.sh --bump patch` |
| Évolution | `./deploy/release-app.sh --bump minor` |
| Correction à installer sans faute (bandeau « nécessaire » dans l'app) | `./deploy/release-app.sh --bump patch --require --note "Pourquoi"` |
| Récupérer les correctifs de `main` | `git merge --no-edit main` (ou `export GIT_MERGE_AUTOEDIT=no` dans `~/.zshrc`) |
| Mise à jour du serveur (compose, Caddyfile, migration, console, paquets) | `./deploy/push-server.sh --install` — rejouable, ne touche ni aux secrets ni au dépôt F-Droid |
| Le serveur est-il au dernier commit ? | `./deploy/push-server.sh --status` — le script refuse d'envoyer un arbre modifié ou un commit déjà envoyé |
| Scripts de publication ou page `/apk` seulement | `./deploy/push-server.sh` puis la ligne ci-dessous |
| Regénérer page et index | `ssh root@monapp.fr 'runuser -u app -- /opt/app/deploy/vps-publish.sh'` |
| API saine ? | `ssh root@monapp.fr 'curl -fsS http://127.0.0.1:3001/ready && echo'` |
| Combien de téléchargements de l'APK | onglet Téléchargements de la console, ou `ssh root@monapp.fr 'cd /opt/app/server && make downloads'` |
| La limitation de débit a-t-elle servi ? | même onglet, en bas, ou `ssh root@monapp.fr 'cd /opt/app/server && make blocked'` |
| Journaux | `ssh root@monapp.fr 'cd /opt/app/server && docker compose logs --tail=50 rest'` |

Jamais : `rsync -a` nu vers le serveur ; changer `applicationId` ou `author` ; régénérer
`server/.env` sur un serveur qui tourne.

## 5. Pannes connues

| Symptôme | Cause | Faire |
|---|---|---|
| `rsync: command not found` (serveur) | serveur nu | §2.4, première ligne |
| `Could not resolve hostname` | faute de frappe ou DNS pas propagés | `dig`, relancer ; rien à nettoyer |
| `swapon failed` | système refuse le swap | rien, le script continue sans |
| silence 10 min à l'étape 9/9 | `fdroidserver` s'installe (Java) ou `apt` attend un verrou | attendre |
| `dependency db/rest failed to start`, `is unhealthy` | base encore en initialisation (disque lent) | le script attend la base jusqu'à 10 min puis relance ; sinon `cd /opt/app/server && docker compose --profile tiles up -d`, puis relancer l'installation |
| `impossible de lire l'empreinte` (Mac) | `keytool` en français | corrigé dans le script |
| `vps.env: Permission denied` | droits trop stricts à l'arrivée | `push-server.sh` les pose ; sinon `chmod -R a+rX /opt/app/deploy` |
| « échec de l'installation » (testeur) | signature changée, ou version debug installée avant | désinstaller d'abord |
| `/fdroid/` montre une liste de fichiers | page pas encore rendue | `vps-publish.sh` (§4) |
| `make: command not found` (serveur) | installé au prochain `push-server.sh --install` | `cd /opt/app/server && ./admin-token.sh <email>` |
| dossier de travail supprimé | `vps.env` et `key.properties` n'étaient pas versionnés | `git worktree add ../monapp monapp` ; `scp root@monapp.fr:/opt/app/deploy/vps.env deploy/` ; `key.properties` depuis la sauvegarde |
| l'app ne prévient jamais d'une nouvelle version, `/fdroid/latest.json` en 404 | scripts du serveur en retard sur le dépôt | `./deploy/push-server.sh` puis `ssh root@monapp.fr 'runuser -u app -- /opt/app/deploy/vps-publish.sh'` ; `release-app.sh` refuse désormais de publier dans ce cas |
| `vps.env annonce une AUTRE empreinte` | clé recréée (possible seulement si rien n'est publié) | vider `RELEASE_CERT_SHA256=` dans `vps.env`, relancer `keystore.sh` |

## 6. Rapatrier une instance dans une autre copie de travail

Pour publier depuis `ici/` une app jusque-là publiée depuis `ailleurs/`, sans fusion git.
Reporter des **valeurs**, jamais des fichiers entiers de code : `ici/` a le code le plus récent.

```sh
# 1. les deux fichiers non versionnés — les seuls qu'on ne recrée pas
cp ailleurs/deploy/vps.env               ici/deploy/vps.env
cp ailleurs/app/android/key.properties   ici/app/android/key.properties

# 2. l'identité, trois valeurs à recopier à la main
grep -E '^(applicationId|author|summary)=' ailleurs/app/android/app.properties
$EDITOR ici/app/android/app.properties                       # mêmes valeurs
grep "appName = " ailleurs/app/lib/src/ui/labels.dart
$EDITOR ici/app/lib/src/ui/labels.dart                       # static const appName = '…';
$EDITOR ici/app/android/app/src/main/AndroidManifest.xml     # android:label="…", identique

# 3. les icônes, si elles ont été changées
cp ailleurs/app/android/app/src/main/res/mipmap-*/ic_launcher.png ... (même arborescence)

# 4. le numéro de version : celui EN LIGNE, pas celui d'ailleurs/ (qui peut être en retard)
curl -sL https://monapp.fr/apk | grep -o 'Version</dt><dd>[^<]*'     # ex. 0.5.1 (build 10)
$EDITOR ici/app/pubspec.yaml                                 # version: 0.5.1+10
$EDITOR ici/app/lib/src/config.dart                          # version = '0.5.1'  versionCode = 10

# 5. vérifier, commiter, publier
cd ici && ./deploy/release-app.sh --bump patch --dry-run --no-git
#   attendu : ✓ signé par la clé de publication  ✓ identité publiée  ✓ nom affiché
git add -A && git commit -m "Reprise de l'instance"
./deploy/push-server.sh --install        # si ici/ apporte des changements serveur
./deploy/release-app.sh --bump patch
```

La clé de signature ne bouge pas : elle est dans `~/.app/<applicationId>-release.jks`, hors des
deux dossiers. Si `release-app.sh` refuse la signature, c'est que `key.properties` n'est pas
celui qui va avec cette clé. Ensuite, `ailleurs/` peut être supprimé ; en garder d'abord une
sauvegarde des deux fichiers du point 1.
