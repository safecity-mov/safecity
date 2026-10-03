#!/usr/bin/env bash
# L'application — construit, signe et publie une version de l'app Android (SPEC §12.6, §14).
#
# S'exécute **sur le poste de développement**, là où sont Flutter et la clé de publication.
# La clé ne va jamais sur le VPS : le serveur ne reçoit qu'un APK déjà signé, et ne peut donc
# rien publier que ce poste n'ait produit.
#
# Ce qu'il refuse de faire, et pourquoi :
#   — publier un APK signé par une autre clé que celle annoncée dans vps.env. Android refuse
#     une mise à jour dont la signature a changé ; les testeurs devraient désinstaller, donc
#     perdre leur identifiant de terminal, leur cache et leurs zones hors ligne.
#   — publier un APK signé en debug. La clé de debug est publique et partagée par tous les
#     SDK Android : n'importe qui pourrait signer une mise à jour de l'application.
#   — publier depuis un arbre de travail sale, sans quoi personne ne peut plus dire quel code
#     tourne sur les téléphones.
#   — publier une app qui demande la position en arrière-plan (§11.1).
#
# Usage :
#   ./deploy/release-app.sh --bump patch        0.1.0 → 0.1.1, build +1
#   ./deploy/release-app.sh --bump minor        0.1.0 → 0.2.0
#   ./deploy/release-app.sh --version 1.0.0     version explicite
#   ./deploy/release-app.sh --rebuild           même version, build +1
#   ./deploy/release-app.sh --bump patch --dry-run   construit et vérifie, ne publie rien
#   ./deploy/release-app.sh --bump patch --no-git     n'exige pas un arbre propre, ne commite pas
#   ./deploy/release-app.sh --bump patch --note "Corrige l'envoi hors ligne"
#                                               une ligne montrée dans l'app (latest.json)
#   ./deploy/release-app.sh --bump patch --require    cette version devient le minimum : en
#                                               dessous, l'app dit « mise à jour nécessaire »
#
# Licence : AGPL-3.0.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$ROOT/app"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

BUMP=""; EXPLICIT=""; DRY_RUN=0; USE_GIT=1; SKIP_TESTS=0; NOTE=""; REQUIRE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --bump)     BUMP="${2:-}"; shift 2 ;;
    --version)  EXPLICIT="${2:-}"; shift 2 ;;
    --rebuild)  BUMP="rebuild"; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --no-git)   USE_GIT=0; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --note)     NOTE="${2:-}"; shift 2 ;;
    --require)  REQUIRE=1; shift ;;
    -h|--help)  sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          sc_die "option inconnue : $1 (voir --help)" ;;
  esac
done

sc_load_env "$HERE" SITE_DOMAIN
APP_ID="$(sc_app_id "$ROOT")"
sc_require_domain
[ "$DRY_RUN" = 1 ] || { [ -n "${VPS_SSH:-}" ] && [ -n "${VPS_ROOT:-}" ]; } \
  || sc_die "VPS_SSH et VPS_ROOT sont nécessaires pour publier (ou lancer avec --dry-run)."


# --- Ce qu'il faut sous la main --------------------------------------------
sc_need flutter "https://docs.flutter.dev/get-started/install"
[ "$DRY_RUN" = 1 ] || { sc_need rsync; sc_need ssh; }

# apksigner est un script qui lance java : sans JDK dans le PATH, il échoue sur une ligne
# illisible. Sur un Mac, celui d'Android Studio est là, simplement pas exposé — et le
# `/usr/bin/java` qu'on y trouve n'est qu'une amorce qui renvoie une erreur.
JAVA_HOME="$(sc_java_home)" || sc_die "aucun JDK utilisable.
     Celui d'Android Studio fait l'affaire :
       export JAVA_HOME=\"/Applications/Android Studio.app/Contents/jbr/Contents/Home\""
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

APKSIGNER="$(sc_android_tool apksigner)" || sc_die "apksigner introuvable (SDK Android, build-tools)."
AAPT2="$(sc_android_tool aapt2 || true)"

[ -f "$APP/android/key.properties" ] || sc_die "app/android/key.properties manquant.
     La clé de publication n'a pas encore été créée :
       ./deploy/keystore.sh"

if [ -z "${RELEASE_CERT_SHA256:-}" ]; then
  sc_die "RELEASE_CERT_SHA256 est vide dans ${SC_ENV_FILE}.
     Relancer ./deploy/keystore.sh : il l'y inscrit."
fi


# --- Numéro de version ------------------------------------------------------
CURRENT="$(sc_pubspec_version "$APP")"
[ -n "$CURRENT" ] || sc_die "version illisible dans app/pubspec.yaml."
CUR_NAME="${CURRENT%%+*}"
CUR_CODE="${CURRENT##*+}"

if [ -n "$EXPLICIT" ]; then
  NEW_NAME="$EXPLICIT"
elif [ "$BUMP" = rebuild ]; then
  NEW_NAME="$CUR_NAME"
elif [ -n "$BUMP" ]; then
  IFS=. read -r MA MI PA <<< "$CUR_NAME"
  case "$BUMP" in
    major) NEW_NAME="$((MA + 1)).0.0" ;;
    minor) NEW_NAME="$MA.$((MI + 1)).0" ;;
    patch) NEW_NAME="$MA.$MI.$((PA + 1))" ;;
    *)     sc_die "--bump attend major, minor ou patch." ;;
  esac
else
  sc_die "rien à publier : préciser --bump patch|minor|major, --version X.Y.Z ou --rebuild.
     Version actuelle : $CUR_NAME (build $CUR_CODE)"
fi

case "$NEW_NAME" in
  [0-9]*.[0-9]*.[0-9]*) : ;;
  *) sc_die "version malformée : $NEW_NAME (attendu X.Y.Z)" ;;
esac

# Le versionCode monte toujours, même pour une reconstruction : c'est le seul nombre
# qu'Android et F-Droid comparent pour décider qu'il y a une mise à jour.
NEW_CODE="$((CUR_CODE + 1))"
APK_NAME="${APP_ID}_${NEW_CODE}.apk"

sc_step "L'application $NEW_NAME (build $NEW_CODE)"
sc_info "depuis    : $CUR_NAME (build $CUR_CODE)"
sc_info "serveur   : https://$SITE_DOMAIN"
sc_info "app       : $APP_ID"
[ "$DRY_RUN" = 1 ] && sc_info "mode      : essai, rien ne sera publié"


# --- L'arbre de travail -----------------------------------------------------
if [ "$USE_GIT" = 1 ]; then
  sc_need git
  cd "$ROOT"
  [ -z "$(git status --porcelain)" ] || sc_die "arbre de travail modifié.
     Un APK publié doit correspondre à un commit, sinon plus personne ne peut dire quel
     code tourne sur les téléphones. Commiter d'abord, ou --no-git pour un essai local."
  COMMIT="$(git rev-parse --short HEAD)"
  sc_ok "arbre propre, sur $COMMIT."
fi


# --- Écriture du numéro de version -----------------------------------------
# `AppConfig.version` recopie celle du pubspec, et `privacy_text_test.dart` casse si les deux
# divergent : les deux fichiers bougent ensemble ou pas du tout.
# Les copies de secours vivent hors de l'arbre : un `config.dart.bak` dans lib/ traverserait
# `flutter analyze` et finirait un jour dans un commit.
WORK="$(mktemp -d)"
RESTORE=1
cleanup() {
  if [ "$RESTORE" = 1 ] && [ -f "$WORK/pubspec.yaml" ]; then
    cp "$WORK/pubspec.yaml" "$APP/pubspec.yaml"
    cp "$WORK/config.dart" "$APP/lib/src/config.dart"
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

cp "$APP/pubspec.yaml" "$WORK/pubspec.yaml"
cp "$APP/lib/src/config.dart" "$WORK/config.dart"

python3 - "$APP" "$NEW_NAME" "$NEW_CODE" <<'PY'
import pathlib, re, sys

app, nom, code = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]

pubspec = app / "pubspec.yaml"
texte, n = re.subn(r'^version: .*$', f'version: {nom}+{code}', pubspec.read_text(), count=1, flags=re.M)
assert n == 1, "ligne « version: » introuvable dans pubspec.yaml"
pubspec.write_text(texte)

config = app / "lib/src/config.dart"
texte, n = re.subn(r"(static const String version = ')[^']*(')", rf"\g<1>{nom}\g<2>",
                   config.read_text(), count=1)
assert n == 1, "AppConfig.version introuvable dans config.dart"
# Le versionCode aussi : c'est lui que l'app compare à latest.json pour se savoir en retard.
texte, n = re.subn(r"(static const int versionCode = )\d+(;)", rf"\g<1>{code}\g<2>", texte, count=1)
assert n == 1, "AppConfig.versionCode introuvable dans config.dart"
config.write_text(texte)
PY
sc_ok "version et versionCode écrits dans pubspec.yaml et config.dart."


# --- Construction -----------------------------------------------------------
sc_step "Construction"
cd "$APP"
flutter pub get >/dev/null

if [ "$SKIP_TESTS" = 0 ]; then
  sc_info "analyse…"
  flutter analyze
  sc_info "tests…"
  flutter test
  sc_ok "analyse et tests passés."
else
  sc_warn "tests sautés (--skip-tests)."
fi

# Les adresses sont figées à la compilation. En release c'est un build AOT, donc les
# `--dart-define` tiennent — ce qui n'est pas vrai en debug (voir app/README.md).
rm -f build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release \
  --target-platform "${TARGET_PLATFORMS:-android-arm,android-arm64}" \
  --dart-define=APP_API="https://$SITE_DOMAIN/rest/v1" \
  --dart-define=APP_TILES="https://$SITE_DOMAIN/tiles" \
  --dart-define=APP_UPDATES="https://$SITE_DOMAIN/fdroid/latest.json"

APK="$APP/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$APK" ] || sc_die "APK introuvable après le build : $APK"
sc_ok "APK construit ($(du -h "$APK" | cut -f1))."


# --- Vérifications ----------------------------------------------------------
sc_step "Vérifications"

SIGNER="$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null \
  | sed -n 's/.*certificate SHA-256 digest: *\([0-9a-fA-F]*\).*/\1/p' | head -n 1 | sc_normalize_fingerprint)"
[ -n "$SIGNER" ] || sc_die "signature illisible : l'APK n'est peut-être pas signé du tout."

EXPECTED="$(printf '%s' "$RELEASE_CERT_SHA256" | sc_normalize_fingerprint)"
if [ "$SIGNER" != "$EXPECTED" ]; then
  sc_die "l'APK est signé par une autre clé que celle annoncée.
     attendu : $EXPECTED
     trouvé  : $SIGNER
     Publier celui-ci rendrait la mise à jour impossible sur les téléphones déjà équipés :
     Android refuse une signature qui change. Vérifier app/android/key.properties."
fi
sc_ok "signé par la clé de publication."

if [ -n "$AAPT2" ]; then
  # L'identité réellement embarquée, et non celle qu'on croit avoir demandée. C'est ce nom
  # qui nomme l'APK et la fiche du dépôt : s'il ne correspond pas, F-Droid annonce une
  # application que le fichier n'est pas.
  PACKAGE="$("$AAPT2" dump badging "$APK" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)"
  [ "$PACKAGE" = "$APP_ID" ] || sc_die "l'APK déclare « $PACKAGE », app.properties dit « $APP_ID ».
     Un build gardé en cache, ou app/android/app.properties modifié sans reconstruire."
  sc_ok "identité publiée : $PACKAGE"

  # Le nom sous l'icône vient du manifeste, celui écrit dans l'app vient de Dart : deux
  # copies que rien ne relie à la compilation. On refuse un renommage fait d'un seul côté.
  LABEL_DART="$(sed -n "s/^  static const appName = '\([^']*\)';.*/\1/p" "$APP/lib/src/ui/labels.dart" | head -n 1)"
  [ -n "$LABEL_DART" ] || sc_die "AppLabels.appName introuvable dans app/lib/src/ui/labels.dart."
  LABEL_APK="$("$AAPT2" dump badging "$APK" 2>/dev/null | sed -n "s/^application-label:'\([^']*\)'.*/\1/p" | head -n 1)"
  [ "$LABEL_APK" = "$LABEL_DART" ] || sc_die "l'APK s'appelle « $LABEL_APK », l'app se nomme « $LABEL_DART ».
     Le manifeste (android:label) et lib/src/ui/labels.dart ne disent plus la même chose."
  sc_ok "nom affiché : $LABEL_APK"

  PERMS="$("$AAPT2" dump permissions "$APK" 2>/dev/null | sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" | sort -u)"
  if printf '%s\n' "$PERMS" | grep -q 'ACCESS_BACKGROUND_LOCATION'; then
    sc_die "l'APK demande la position en arrière-plan.
     L'app ne suit aucun trajet et ne lit jamais le GPS hors d'un geste explicite (§11.1).
     Une dépendance vient d'en faire entrer la permission par fusion de manifeste."
  fi
  sc_ok "permissions demandées :"
  printf '%s\n' "$PERMS" | sed 's/^android\.permission\./     · /'
else
  sc_warn "aapt2 introuvable : permissions non vérifiées."
fi

SHA="$(shasum -a 256 "$APK" 2>/dev/null | cut -d' ' -f1 || sha256sum "$APK" | cut -d' ' -f1)"
sc_info "sha256    : $SHA"


# --- Publication ------------------------------------------------------------
if [ "$DRY_RUN" = 1 ]; then
  sc_step "Essai terminé"
  sc_info "APK : $APK"
  sc_info "Les numéros de version sont remis comme avant : rien n'a été publié."
  exit 0
fi

sc_step "Publication"

# Le serveur exécute sa propre copie de vps-publish.sh : si elle est en retard sur celle-ci,
# la publication « réussit » avec un index ancien — un latest.json absent, une page d'un
# autre gabarit — et personne ne le voit. On compare les fichiers dont il dépend.
FRESH_FILES="vps-publish.sh lib/common.sh apk-page.html"
LOCAL_SUM="$(cd "$HERE" && cat $FRESH_FILES | shasum -a 256 | cut -d' ' -f1)"
REMOTE_SUM="$(ssh "$VPS_SSH" "cd '$VPS_ROOT/deploy' && cat $FRESH_FILES 2>/dev/null | sha256sum | cut -d' ' -f1" 2>/dev/null || true)"
if [ "$LOCAL_SUM" != "$REMOTE_SUM" ]; then
  sc_die "les scripts de publication du serveur ne sont pas ceux de ce dépôt.
     Le serveur exécuterait une ancienne version de vps-publish.sh. Les mettre à jour d'abord :
       ./deploy/push-server.sh
     puis relancer cette commande."
fi
sc_ok "scripts du serveur à jour."

cp "$APK" "$WORK/$APK_NAME"

sc_info "envoi vers ${VPS_SSH}…"
# Sans --chmod : le rsync de macOS (openrsync) refuse la forme numérique, et les droits
# sont posés côté serveur par vps-publish.sh sur tout repo/, juste après.
rsync "$WORK/$APK_NAME" "$VPS_SSH:$VPS_ROOT/server/fdroid/repo/"
sc_ok "$APK_NAME déposé."

# À partir d'ici l'APK est en ligne : les numéros de version ne sont plus remis comme avant,
# quoi qu'il arrive ensuite. Un dépôt réussi suivi d'un index en échec reste un dépôt réussi.
RESTORE=0

# La note traverse ssh en base64 : une apostrophe ou un guillemet dans le texte ne passerait
# pas deux shells de suite sans casser quelque part. Le shell distant est POSIX : la forme
# `VAR=valeur commande` lui suffit.
NOTE_B64=""
[ -z "$NOTE" ] || NOTE_B64="$(printf '%s' "$NOTE" | base64 | tr -d '\n')"
INDEX_OK=1
ssh "$VPS_SSH" "RELEASE_NOTE_B64=$NOTE_B64 RELEASE_REQUIRE=$REQUIRE $VPS_ROOT/deploy/vps-publish.sh" || INDEX_OK=0


# --- Trace locale -----------------------------------------------------------
if [ "$USE_GIT" = 1 ]; then
  cd "$ROOT"
  git add app/pubspec.yaml app/lib/src/config.dart
  git commit -q -m "Version $NEW_NAME (build $NEW_CODE)"
  git tag -a "v$NEW_NAME" -m "L'application $NEW_NAME (build $NEW_CODE), sha256 $SHA"
  sc_ok "commit et étiquette v$NEW_NAME créés localement (non poussés)."
else
  sc_warn "--no-git : le numéro de version reste modifié dans l'arbre, sans commit."
fi


# --- Récapitulatif ----------------------------------------------------------
cat <<FIN

${SC_BOLD}== L'application $NEW_NAME (build $NEW_CODE) est en ligne ==${SC_RESET}

   Page testeurs   https://$SITE_DOMAIN/apk
   APK direct      https://$SITE_DOMAIN/fdroid/$(sc_apk_filename "$(sc_app_name "$ROOT")" "$NEW_NAME")
   Adresse stable  https://$SITE_DOMAIN/fdroid/app-latest.apk
   sha256          $SHA

FIN

if [ "$INDEX_OK" = 0 ]; then
  sc_warn "l'index F-Droid n'a PAS été régénéré."
  sc_warn "L'APK est téléchargeable, mais aucun testeur ne sera prévenu de la mise à jour."
  sc_warn "Voir /tmp/fdroid-update.log sur le VPS, puis relancer :"
  sc_warn "  ssh $VPS_SSH $VPS_ROOT/deploy/vps-publish.sh"
  exit 3
fi

sc_info "Les téléphones qui ont ajouté le dépôt verront la mise à jour à leur prochaine"
sc_info "vérification. Pour la forcer : F-Droid → Mises à jour → tirer vers le bas."
sc_info "Les autres verront un bandeau dans l'app à leur prochain lancement (latest.json)."
[ "$REQUIRE" = 0 ] || sc_info "Version minimale exigée : en dessous, le bandeau dit « nécessaire »."
echo
