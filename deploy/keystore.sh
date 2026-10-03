#!/usr/bin/env bash
# L'application — crée la clé de publication de l'app Android. Une seule fois, pour toujours.
#
# Android identifie une application par le couple (applicationId, clé de signature). Une mise
# à jour signée par une autre clé n'est pas une mise à jour : le système refuse de l'installer
# par-dessus, et la seule issue est de désinstaller — donc de perdre l'identifiant de terminal,
# la base locale et les zones hors ligne de chaque testeur. **Perdre cette clé, c'est perdre
# l'application.** Il n'y a pas de recours, pas de récupération, pas de support à contacter :
# F-Droid ne conserve aucune copie, contrairement au « Play App Signing » de Google.
#
# D'où trois partis pris :
#   — la clé vit hors du dépôt, dans ~/.app, pour qu'aucun `git add -A` ne l'emporte ;
#   — sa validité est de 30 ans, parce qu'une clé expirée ne signe plus rien et qu'on ne peut
#     pas en changer ;
#   — le script refuse d'écraser un magasin existant.
#
# Usage : ./deploy/keystore.sh
#
# Licence : AGPL-3.0.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

sc_load_env "$HERE"
APP_ID="$(sc_app_id "$ROOT")"
APP_AUTHOR="$(sc_app_author "$ROOT")"

# Dérivé de l'applicationId, sauf surcharge KEYSTORE dans vps.env (voir common.sh).
KEYSTORE_PATH="$(sc_keystore_path "$ROOT")"
KEY_ALIAS="$(sc_key_alias)"

KEYTOOL="$(sc_android_tool keytool)" || sc_die "aucun JDK utilisable : keytool introuvable.
     Sur un Mac, celui d'Android Studio fait l'affaire :
       export JAVA_HOME=\"/Applications/Android Studio.app/Contents/jbr/Contents/Home\""

sc_step "Clé de publication de l'application"
sc_info "magasin  : $KEYSTORE_PATH"
sc_info "alias    : $KEY_ALIAS"
sc_info "app      : $APP_ID"

if [ -f "$KEYSTORE_PATH" ]; then
  sc_warn "le magasin existe déjà — rien n'est écrasé."
  # Le cas d'une restauration à moitié faite : la clé est revenue de la sauvegarde, le
  # fichier qui porte son mot de passe non. Rien ne peut plus la lire, et le dire ici vaut
  # mieux qu'une erreur de keytool sur un mot de passe vide.
  [ -f "$ROOT/app/android/key.properties" ] || sc_die "app/android/key.properties manquant.
     Le magasin est là mais le mot de passe qui l'ouvre ne l'est pas. Il vient de la même
     sauvegarde : restaurer les deux fichiers ensemble."
  sc_info "Son empreinte :"
else
  echo
  sc_info "Cette clé signera toutes les versions de l'app, pour toute sa vie."
  sc_info "Elle n'est ni récupérable ni remplaçable. La sauvegarder hors de cette machine"
  sc_info "fait partie de l'opération, pas d'un « plus tard »."
  echo
  sc_confirm "Créer la clé de publication ?" || sc_die "abandon."

  mkdir -p "$(dirname "$KEYSTORE_PATH")"
  chmod 700 "$(dirname "$KEYSTORE_PATH")"

  # Le mot de passe est tiré au sort et rangé à côté du magasin plutôt que demandé : il n'a
  # pas à être mémorisable, il a à être sauvegardé avec la clé — les deux ne servent qu'ensemble.
  STOREPASS="$(openssl rand -base64 33 | tr -d '\n')"

  # Aucun nom de personne dans le certificat : il est lisible par quiconque installe l'APK,
  # et l'éditeur publie sous pseudonyme (§12.6). Ni ville, ni pays, ni organisation réelle.
  "$KEYTOOL" -genkeypair \
    -keystore "$KEYSTORE_PATH" \
    -storetype PKCS12 \
    -storepass "$STOREPASS" \
    -keypass "$STOREPASS" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA -keysize 4096 \
    -validity 10950 \
    -dname "CN=$APP_AUTHOR" >/dev/null

  chmod 600 "$KEYSTORE_PATH"

  # Gradle lit ce fichier ; il est dans .gitignore. Le chemin est absolu pour ne pas dépendre
  # du répertoire depuis lequel le build est lancé.
  cat > "$ROOT/app/android/key.properties" <<PROPS
# L'application — clé de publication. Produit par deploy/keystore.sh, jamais versionné.
# Sans ce fichier, un build release retombe sur la signature de debug (voir
# app/android/app/build.gradle.kts) : pratique en développement, refusé à la publication.
storeFile=$KEYSTORE_PATH
storePassword=$STOREPASS
keyAlias=$KEY_ALIAS
keyPassword=$STOREPASS
PROPS
  chmod 600 "$ROOT/app/android/key.properties"

  sc_ok "clé créée."
fi

FINGERPRINT="$(
  "$KEYTOOL" -J-Duser.language=en -list -v \
    -keystore "$KEYSTORE_PATH" \
    -storetype PKCS12 \
    -storepass "$(sed -n 's/^storePassword=//p' "$ROOT/app/android/key.properties")" \
    -alias "$KEY_ALIAS" 2>/dev/null \
  | sed -n 's/.*SHA[ -]*256: *\([0-9A-Fa-f:]*\).*/\1/p' | head -n 1 | sc_normalize_fingerprint
)"

[ -n "$FINGERPRINT" ] || sc_die "impossible de lire l'empreinte du certificat."

echo
sc_info "Empreinte SHA-256 du certificat :"
sc_info "  $SC_BOLD$FINGERPRINT$SC_RESET"
echo

if grep -q '^RELEASE_CERT_SHA256=.\+' "$SC_ENV_FILE" 2>/dev/null; then
  CURRENT="$(sed -n 's/^RELEASE_CERT_SHA256=//p' "$SC_ENV_FILE" | tr -d '"' | head -n 1)"
  if [ "$CURRENT" != "$FINGERPRINT" ]; then
    sc_warn "vps.env annonce une AUTRE empreinte : $CURRENT"
    sc_warn "Deux clés pour une seule app : les téléphones déjà équipés refuseront la mise à jour."
  else
    sc_ok "vps.env porte déjà cette empreinte."
  fi
else
  # sed -i diffère entre BSD et GNU ; on réécrit le fichier plutôt que de choisir.
  tmp="$(mktemp)"
  sed "s|^RELEASE_CERT_SHA256=.*|RELEASE_CERT_SHA256=$FINGERPRINT|" "$SC_ENV_FILE" > "$tmp"
  mv "$tmp" "$SC_ENV_FILE"
  sc_ok "empreinte inscrite dans deploy/vps.env."
fi

cat <<FIN

   ${SC_BOLD}À faire maintenant, pas plus tard${SC_RESET}

   Sauvegarder ces deux fichiers hors de cette machine — chiffrés, sur un support que
   la perte du portable n'emporte pas :

     $KEYSTORE_PATH
     $ROOT/app/android/key.properties

   Le second porte le mot de passe du premier. Séparés, ils ne servent à rien ; ensemble,
   ils signent l'application. Les garder au même endroit qu'une sauvegarde du dépôt suffit,
   à condition que cet endroit ne soit pas ce Mac.

FIN
