# L'application — fonctions partagées par les scripts de déploiement.
#
# Jamais exécuté directement : sourcé par install-vps.sh, release-app.sh et vps-publish.sh.
# Licence : AGPL-3.0, comme le reste du serveur (SPEC §12.1).

# shellcheck shell=bash

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  SC_BOLD=$'\033[1m'; SC_RED=$'\033[31m'; SC_GREEN=$'\033[32m'
  SC_YELLOW=$'\033[33m'; SC_DIM=$'\033[2m'; SC_RESET=$'\033[0m'
else
  SC_BOLD=''; SC_RED=''; SC_GREEN=''; SC_YELLOW=''; SC_DIM=''; SC_RESET=''
fi

sc_step() { printf '\n%s== %s%s\n' "$SC_BOLD" "$*" "$SC_RESET"; }
sc_info() { printf '   %s\n' "$*"; }
sc_dim()  { printf '   %s%s%s\n' "$SC_DIM" "$*" "$SC_RESET"; }
sc_ok()   { printf '   %s✓%s %s\n' "$SC_GREEN" "$SC_RESET" "$*"; }
sc_warn() { printf '   %s!%s %s\n' "$SC_YELLOW" "$SC_RESET" "$*" >&2; }
sc_die()  { printf '\n%s✗ %s%s\n\n' "$SC_RED" "$*" "$SC_RESET" >&2; exit 1; }

# sc_need <commande> [explication]
sc_need() {
  command -v "$1" >/dev/null 2>&1 || sc_die "commande manquante : $1${2:+ — $2}"
}

# Une confirmation, et une seule réponse acceptée : « oui ». Même convention que le Makefile
# du serveur, pour qu'un « y » réflexe ne détruise rien.
sc_confirm() {
  local answer
  read -r -p "   $1 [oui/non] " answer
  [ "$answer" = "oui" ]
}

# sc_load_env <répertoire deploy> [variables obligatoires…]
#
# `vps.env` n'est pas versionné : il porte le domaine, la cible SSH et l'empreinte de la clé
# de publication. `vps.env.example` l'est, et sert de gabarit.
sc_load_env() {
  local dir="$1"; shift
  SC_ENV_FILE="${APP_ENV:-$dir/vps.env}"

  if [ ! -f "$SC_ENV_FILE" ]; then
    sc_die "$SC_ENV_FILE manquant.
     Le créer à partir du gabarit, puis remplir les valeurs :
       cp $dir/vps.env.example $dir/vps.env"
  fi

  [ -r "$SC_ENV_FILE" ] || sc_die "$SC_ENV_FILE n'est pas lisible par $(id -un).
     Il est arrivé avec des droits trop stricts. Sur le serveur : chmod -R a+rX $dir
     Depuis le poste, préférer ./deploy/push-server.sh, qui règle les droits en envoyant."

  # shellcheck disable=SC1090
  set -a; . "$SC_ENV_FILE"; set +a

  local v missing=()
  for v in "$@"; do
    [ -n "${!v:-}" ] || missing+=("$v")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    sc_die "variables manquantes dans $SC_ENV_FILE : ${missing[*]}"
  fi
}

# Un domaine d'exemple laissé tel quel produirait un certificat que Let's Encrypt ne
# délivrera jamais, et un APK qui parle à un serveur qui n'existe pas. Vérifié seulement par
# ce qui en dépend : créer la clé de publication n'a pas à attendre l'achat d'un domaine.
sc_require_domain() {
  case "${SITE_DOMAIN:-}" in
    *example.org|*example.com|'')
      sc_die "SITE_DOMAIN vaut encore la valeur d'exemple dans ${SC_ENV_FILE:-vps.env}." ;;
  esac
}

# Développe un « ~ » de tête. Le reste ($HOME, ${USER}…) l'est déjà par le sourcing.
sc_expand_path() { printf '%s\n' "${1/#\~/$HOME}"; }

# L'identité publiée de l'app, lue là où Gradle la lit : app/android/app.properties.
#
# Elle n'est pas dans vps.env, et ce n'est pas un détail. L'applicationId est ce qu'Android et
# F-Droid comparent pour décider qu'un APK est bien une mise à jour de l'app installée. Deux
# copies de cette valeur finiraient par diverger, et le dépôt annoncerait alors une application
# que l'APK n'est pas — sans que rien ne le signale, jusqu'à ce qu'un testeur voie « échec de
# l'installation ».
sc_app_property() {
  local fichier="$1/app/android/app.properties" cle="$2"
  [ -f "$fichier" ] || sc_die "$fichier manquant : c'est là qu'est écrit $cle."
  local valeur
  valeur="$(sed -n "s/^[[:space:]]*$cle[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$fichier" | head -n 1)"
  [ -n "$valeur" ] || sc_die "$cle illisible dans $fichier."
  printf '%s\n' "$valeur"
}
sc_app_id() { sc_app_property "$1" applicationId; }

# Le nom de publication, même fichier : il signe les deux clés et figure sur la fiche F-Droid.
sc_app_author() { sc_app_property "$1" author; }

# Une propriété qui est une phrase : tout ce qui suit le `=`, espaces compris, sans le
# commentaire de fin de ligne. `sc_app_property` s'arrête au premier espace, c'est voulu pour
# un identifiant, pas pour un texte.
sc_app_text() {
  local fichier="$1/app/android/app.properties" cle="$2"
  [ -f "$fichier" ] || sc_die "$fichier manquant : c'est là qu'est écrit $cle."
  sed -n "s/^[[:space:]]*$cle[[:space:]]*=[[:space:]]*//p" "$fichier" | head -n 1 \
    | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'
}

# La phrase qui présente l'app : en tête de la page /apk et en `Summary` de la fiche F-Droid.
sc_app_summary() {
  local s
  s="$(sc_app_text "$1" summary)"
  [ -n "$s" ] || s="Signalement collaboratif des dangers de la route."
  printf '%s\n' "$s"
}

# Le nom affiché, tel que l'app l'écrit : AppLabels.appName dans labels.dart. Le manifeste
# Android en porte une copie, que release-app.sh compare à celle-ci avant de publier.
# Le nom de fichier sous lequel un APK est proposé au téléchargement : le nom affiché en
# minuscules ASCII, puis la version, `safe-city-0.5.2.apk`. Un nom par version, pour que le
# navigateur n'empile pas des « app-latest (1).apk » à chaque mise à jour et que la liste des
# téléchargements dise quelle version est laquelle. Sans version, le préfixe seul.
sc_apk_filename() {
  local nom="$1" version="${2:-}" slug
  # Les accents tombent (é → e) : python3 est déjà requis par les scripts de publication.
  slug="$(python3 -c 'import sys, unicodedata
print(unicodedata.normalize("NFKD", sys.argv[1]).encode("ascii", "ignore").decode())' "$nom" 2>/dev/null || printf '%s' "$nom")"
  slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  [ -n "$slug" ] || slug="app"
  if [ -n "$version" ]; then
    printf '%s-%s.apk\n' "$slug" "$version"
  else
    printf '%s\n' "$slug"
  fi
}

sc_app_name() {
  local fichier="$1/app/lib/src/ui/labels.dart" valeur
  [ -f "$fichier" ] || sc_die "$fichier manquant : c'est là qu'est écrit le nom de l'app."
  valeur="$(sed -n "s/.*static const appName = '\([^']*\)'.*/\1/p" "$fichier" | head -n 1)"
  [ -n "$valeur" ] || sc_die "AppLabels.appName illisible dans $fichier."
  printf '%s\n' "$valeur"
}

# Où vit la clé de publication. Par défaut ~/.app/<applicationId>-release.jks : un fichier
# par app, dérivé de l'identité, sans rien à écrire — deux instances sur le même poste ne
# peuvent pas se signer l'une avec la clé de l'autre par oubli d'une ligne. KEYSTORE dans
# vps.env reste une surcharge possible, pour qui range ses clés ailleurs.
sc_keystore_path() {
  if [ -n "${KEYSTORE:-}" ]; then
    sc_expand_path "$KEYSTORE"
  else
    printf '%s\n' "$HOME/.app/$(sc_app_id "$1")-release.jks"
  fi
}

sc_key_alias() { printf '%s\n' "${KEY_ALIAS:-app}"; }

# La version déclarée dans pubspec.yaml, sous la forme « 0.1.0+1 ».
sc_pubspec_version() {
  sed -n 's/^version: *\([0-9][^ ]*\).*/\1/p' "$1/pubspec.yaml" | head -n 1
}

# Un JDK qui fonctionne vraiment.
#
# Sur un Mac, `/usr/bin/java` et `/usr/bin/keytool` existent toujours : ce sont des amorces
# qui ouvrent une fenêtre « Unable to locate a Java Runtime » et sortent en erreur. Un
# `command -v keytool` les trouve donc et on croit tenir un JDK. D'où le test à l'exécution
# plutôt que la simple présence du fichier.
sc_java_home() {
  local home
  for home in \
    "${JAVA_HOME:-}" \
    "$(/usr/libexec/java_home 2>/dev/null || true)" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "/usr/lib/jvm/default-java"
  do
    if [ -n "$home" ] && [ -x "$home/bin/java" ] && "$home/bin/java" -version >/dev/null 2>&1; then
      printf '%s\n' "$home"
      return 0
    fi
  done

  if command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
    printf '%s\n' "$(dirname "$(dirname "$(command -v java)")")"
    return 0
  fi

  return 1
}

# Localise un outil du JDK ou des build-tools Android. Ni keytool ni apksigner ne sont dans
# le PATH d'un Mac : ils viennent du JDK embarqué dans Android Studio et du SDK Android, que
# Flutter installe sans les exposer.
sc_android_tool() {
  local name="$1" candidate home sdk

  case "$name" in
    keytool|jarsigner|java)
      if home="$(sc_java_home)" && [ -x "$home/bin/$name" ]; then
        printf '%s\n' "$home/bin/$name"
        return 0
      fi
      ;;
  esac

  # build-tools : plusieurs versions installées côte à côte, on prend la plus récente.
  sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
  if [ -d "$sdk/build-tools" ]; then
    candidate="$(find "$sdk/build-tools" -maxdepth 2 -name "$name" -type f 2>/dev/null | sort -V | tail -n 1)"
    [ -n "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  fi

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  return 1
}

# L'empreinte SHA-256 d'un certificat, en minuscules et sans deux-points : la forme que
# F-Droid attend dans « ?fingerprint=… », et celle qu'`apksigner` imprime pour un APK.
sc_normalize_fingerprint() {
  tr -d ': \t\r\n' | tr 'A-Z' 'a-z'
}
