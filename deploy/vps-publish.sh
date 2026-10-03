#!/usr/bin/env bash
# L'application — régénère l'index du dépôt F-Droid et la page de téléchargement.
#
# S'exécute **sur le VPS**, sous l'utilisateur `app`. Appelé par install-vps.sh à
# l'installation, et par release-app.sh après chaque dépôt d'APK. Rien ne le rend interactif :
# il lit ce qui est dans `repo/` et en déduit tout le reste.
#
# Sortie 3 : l'APK est en place et téléchargeable, mais l'index F-Droid n'a pas pu être
# régénéré — les testeurs ne seront pas prévenus tant que ce n'est pas réparé.
#
# Licence : AGPL-3.0.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FDROID_DIR="$ROOT/server/fdroid"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

sc_load_env "$HERE" SITE_DOMAIN
APP_ID="$(sc_app_id "$ROOT")"
APP_NAME="$(sc_app_name "$ROOT")"
APP_AUTHOR="$(sc_app_author "$ROOT")"
APP_SUMMARY="$(sc_app_summary "$ROOT")"
sc_require_domain

[ -d "$FDROID_DIR" ] || sc_die "$FDROID_DIR manquant — lancer install-vps.sh d'abord."
# public/ est la racine servie par Caddy, repo/ y est monté en dessous ; config.yml,
# keystore.p12 et metadata/ restent ici, hors de tout montage.
mkdir -p "$FDROID_DIR/repo" "$FDROID_DIR/metadata" "$FDROID_DIR/public" "$FDROID_DIR/public/repo"

REPO_URL="https://$SITE_DOMAIN/fdroid/repo"
STATUS=0


# --- La fiche que le client F-Droid affiche ---------------------------------
# Réécrite à chaque passage : elle se déduit entièrement de vps.env, il n'y a rien à conserver.
{
  echo "# L'application — fiche du dépôt F-Droid. Produite par deploy/vps-publish.sh."
  echo 'Categories:'
  echo '  - Navigation'
  echo 'License: Apache-2.0'
  echo "AuthorName: $APP_AUTHOR"
  # Une seule phrase, celle d'app.properties, sans point final : F-Droid affiche le Summary
  # comme un sous-titre et coupe au-delà de 80 caractères.
  printf 'Summary: %s\n' "$(printf '%s' "$APP_SUMMARY" | sed 's/\.$//' | cut -c1-80)"
  [ -n "${SOURCE_URL:-}" ] && printf 'SourceCode: %s\n' "$SOURCE_URL"
  printf 'WebSite: https://%s/apk\n' "$SITE_DOMAIN"
  cat <<'DESC'
Description: |-
    Signaler un nid-de-poule en quelques secondes, le voir sur une carte, et confirmer ceux
    que d'autres ont signalés. Un danger réparé quitte la carte quand assez de personnes
    l'ont marqué résolu.

    Sans compte et sans mouchard. Aucune analytics, aucune télémétrie, aucune dépendance à
    un composant non libre. Le fond de carte, l'API et les polices viennent tous du même
    serveur : aucune requête ne part vers un domaine tiers.

    La position n'est lue qu'au moment d'un geste explicite, jamais en arrière-plan, et elle
    ne quitte pas le téléphone : l'app en déduit elle-même un ordre de grandeur de distance
    et n'envoie que celui-là. Le lien entre un terminal et ses signalements est coupé au bout
    de vingt-quatre heures.

    Bêta fermée. Pilote parisien, mais la carte couvre toute la France métropolitaine.
DESC
} > "$FDROID_DIR/metadata/$APP_ID.yml"


# --- L'index signé ----------------------------------------------------------
if command -v fdroid >/dev/null 2>&1 && [ -f "$FDROID_DIR/config.yml" ]; then
  # Les défauts sont posés à part, et jamais dans un `${VAR:-mot}` : une apostrophe dans le
  # mot y est lue comme une quote par bash, et la ligne d'appel ne se parse plus — trois
  # arguments au lieu de quatre, ou « bad substitution » selon la version.
  [ -n "${REPO_NAME:-}" ]        || REPO_NAME="$APP_NAME — bêta"
  [ -n "${REPO_DESCRIPTION:-}" ] || REPO_DESCRIPTION="Dépôt de la bêta fermée de $APP_NAME."
  python3 - "$FDROID_DIR/config.yml" "$REPO_URL" "$REPO_NAME" "$REPO_DESCRIPTION" <<'PY'
import sys, yaml

chemin, url, nom, description = sys.argv[1:5]
with open(chemin) as f:
    config = yaml.safe_load(f) or {}

config['repo_url'] = url
config['repo_name'] = nom
config['repo_description'] = description
# Aucune archive : une bêta garde toutes ses versions sous la main, et un testeur qui revient
# après deux mois doit pouvoir réinstaller celle qu'il avait.
config['archive_older'] = 0

with open(chemin, 'w') as f:
    yaml.safe_dump(config, f, default_flow_style=False, allow_unicode=True)
PY

  cd "$FDROID_DIR"
  if fdroid update --create-metadata --pretty >/tmp/fdroid-update.log 2>&1; then
    sc_ok "index F-Droid régénéré."
  else
    sc_warn "« fdroid update » a échoué :"
    tail -n 15 /tmp/fdroid-update.log >&2
    STATUS=3
  fi

  # L'empreinte du certificat qui signe l'index. Elle fait partie de l'adresse que les
  # testeurs ajoutent : elle ne doit jamais changer, sinon le dépôt est à rajouter chez chacun.
  #
  # Rien ici ne doit arrêter le script : sans empreinte, la page se rend quand même, avec
  # une adresse nue, et on le dit. Sous `set -e -o pipefail`, un keytool qui échoue dans un
  # `$(… | sed | …)` tuait le script sans un mot — sa sortie d'erreur partait à /dev/null.
  FP=""
  if KEYTOOL="$(sc_android_tool keytool)"; then
    KS=""; ALIAS=""; STOREPASS=""
    read -r KS ALIAS STOREPASS < <(python3 - "$FDROID_DIR/config.yml" <<'PY'
import sys, yaml
c = yaml.safe_load(open(sys.argv[1])) or {}
print(c.get('keystore', 'keystore.p12'), c.get('repo_keyalias', ''), c.get('keystorepass', ''))
PY
    ) || true
    # fdroid init écrit le chemin tel qu'on l'a donné : relatif au dépôt, ou absolu.
    case "$KS" in /*) KS_PATH="$KS" ;; *) KS_PATH="$FDROID_DIR/$KS" ;; esac
    if KT_OUT="$("$KEYTOOL" -J-Duser.language=en -list -v -keystore "$KS_PATH" -storepass "$STOREPASS" -alias "$ALIAS" 2>&1)"; then
      FP="$(printf '%s\n' "$KT_OUT" | sed -n 's/.*SHA[ -]*256: *\([0-9A-Fa-f:]*\).*/\1/p' | head -n 1 | sc_normalize_fingerprint)"
    else
      sc_warn "keytool n'a pas pu lire la clé d'index ($KS_PATH, alias « $ALIAS ») :"
      printf '%s\n' "$KT_OUT" | grep -vi 'password' | tail -n 3 | sed 's/^/     /' >&2
    fi
  else
    sc_warn "keytool introuvable sur ce serveur : empreinte du dépôt non calculée."
  fi
  if [ -n "$FP" ]; then
    printf '%s\n' "$FP" > "$FDROID_DIR/public/fingerprint.txt"
    sc_ok "empreinte du dépôt : $FP"
  else
    sc_warn "empreinte du dépôt illisible : la page donnera une adresse sans « ?fingerprint= »."
    STATUS=3
  fi
else
  sc_warn "fdroidserver absent ou dépôt non initialisé : pas d'index, donc pas de mise à jour automatique."
  STATUS=3
fi

FINGERPRINT=""
[ -f "$FDROID_DIR/public/fingerprint.txt" ] && FINGERPRINT="$(cat "$FDROID_DIR/public/fingerprint.txt")"


# --- Le raccourci « dernière version » --------------------------------------
# Hors de `repo/` : un second fichier pour le même paquet à l'intérieur ferait un doublon de
# versionCode aux yeux de `fdroid update`. Un lien dur et non symbolique : les deux dossiers
# sont montés séparément dans Caddy, un lien relatif n'y résoudrait pas pareil qu'ici.
#
# Deux noms pour le même fichier. `app-latest.apk` : l'adresse stable, celle qu'on peut écrire
# sur un papier. `safe-city-0.5.2.apk` : celle que la page et l'app donnent au navigateur, un
# nom par version, pour que Brave ou Chrome n'empilent pas des « app-latest (1).apk » à chaque
# mise à jour. Le nom versionné précédent est retiré : la page n'offre que la dernière version,
# et le dépôt F-Droid garde les anciennes sous leur nom à lui.
LATEST_APK="$(ls -1 "$FDROID_DIR/repo/"*.apk 2>/dev/null | sort -V | tail -n 1 || true)"
APK_FILENAME="app-latest.apk"
if [ -n "$LATEST_APK" ]; then
  ln -f "$LATEST_APK" "$FDROID_DIR/public/app-latest.apk"
  VERSION_NAME="$(python3 - "$FDROID_DIR/repo/index-v1.json" "$APP_ID" <<'PY2' 2>/dev/null || true
import json, sys
paquets = json.load(open(sys.argv[1])).get("packages", {}).get(sys.argv[2], [])
if paquets:
    print(max(paquets, key=lambda p: p.get("versionCode", 0)).get("versionName", ""))
PY2
)"
  SLUG="$(sc_apk_filename "$APP_NAME")"
  if [ -n "$VERSION_NAME" ]; then
    APK_FILENAME="$(sc_apk_filename "$APP_NAME" "$VERSION_NAME")"
    find "$FDROID_DIR/public" -maxdepth 1 -name "$SLUG-*.apk" ! -name "$APK_FILENAME" -delete
    ln -f "$LATEST_APK" "$FDROID_DIR/public/$APK_FILENAME"
  fi
fi


# --- La page de téléchargement ----------------------------------------------
python3 - "$FDROID_DIR" "$HERE/apk-page.html" "$APP_ID" "$REPO_URL" "$FINGERPRINT" "${SOURCE_URL:-}" "$APP_NAME" "$APP_SUMMARY" "$APK_FILENAME" <<'PY'
import datetime, hashlib, html, json, pathlib, re, sys

fdroid = pathlib.Path(sys.argv[1])
gabarit = pathlib.Path(sys.argv[2]).read_text()
app_id, repo_url, fingerprint, source_url, app_name, summary, fichier_apk = sys.argv[3:10]

# Ce que le client F-Droid sait déjà de la dernière version : on relit son propre index
# plutôt que de le recalculer, pour que la page ne puisse pas annoncer autre chose que lui.
version = None
index = fdroid / "repo" / "index-v1.json"
if index.exists():
    paquets = json.loads(index.read_text()).get("packages", {}).get(app_id, [])
    if paquets:
        version = max(paquets, key=lambda p: p.get("versionCode", 0))


def code_depuis_nom(chemin):
    trouve = re.search(r"(\d+)\.apk$", chemin.name)
    return int(trouve.group(1)) if trouve else 0


apks = list((fdroid / "repo").glob("*.apk"))
apk = max(apks, key=code_depuis_nom) if apks else None

if apk is None:
    bloc = "<p>Aucune version publiée pour l'instant.</p>"
else:
    taille = version["size"] if version else apk.stat().st_size
    empreinte = version["hash"] if version else hashlib.sha256(apk.read_bytes()).hexdigest()
    nom_version = version["versionName"] if version else "—"
    code = version["versionCode"] if version else code_depuis_nom(apk)
    date = datetime.datetime.fromtimestamp(apk.stat().st_mtime).strftime("%d/%m/%Y")
    bloc = (
        f'<a class="bouton" href="/fdroid/{html.escape(fichier_apk)}">Télécharger l’APK</a>'
        "<dl>"
        f"<dt>Version</dt><dd>{html.escape(str(nom_version))} (build {html.escape(str(code))})</dd>"
        f"<dt>Publiée le</dt><dd>{date}</dd>"
        f"<dt>Taille</dt><dd>{taille / 1024 / 1024:.1f} Mo</dd>"
        f"<dt>SHA-256</dt><dd><code>{html.escape(empreinte)}</code></dd>"
        "</dl>"
    )

lien_source = ""
if source_url:
    lien_source = f' Sources : <a href="{html.escape(source_url)}">{html.escape(source_url)}</a>.'

adresse = repo_url + (f"?fingerprint={fingerprint}" if fingerprint else "")

page = (gabarit
        .replace("{{APP_NAME}}", html.escape(app_name))
        .replace("{{SUMMARY}}", html.escape(summary))
        .replace("{{REPO_URL}}", html.escape(adresse))
        .replace("{{VERSION_BLOCK}}", bloc)
        .replace("{{SOURCE_LINK}}", lien_source)
        .replace("{{GENERATED}}", datetime.datetime.now().strftime("%d/%m/%Y à %H:%M")))

(fdroid / "public" / "index.html").write_text(page)
print("   ✓ page de téléchargement rendue")
PY

# --- Ce que l'app lit pour se savoir en retard (§12.6) ----------------------
# `public/latest.json` : la dernière version, telle que l'index F-Droid la connaît, plus deux
# champs qui ne viennent que de la ligne de commande de release-app.sh :
#   RELEASE_NOTE_B64  — une ligne libre, en base64 pour traverser ssh sans souci de quotes ;
#                       gardée tant que la version ne change pas, effacée sinon.
#   RELEASE_REQUIRE=1 — cette version devient le minimum : en dessous, l'app dit « nécessaire »
#                       au lieu de « disponible ». Le minimum reste acquis aux passages suivants.
python3 - "$FDROID_DIR" "$APP_ID" "$SITE_DOMAIN" "${RELEASE_NOTE_B64:-}" "${RELEASE_REQUIRE:-0}" "$APK_FILENAME" <<'PY'
import base64, datetime, hashlib, json, pathlib, re, sys

fdroid = pathlib.Path(sys.argv[1])
app_id, domaine, note_b64, exiger, fichier_apk = sys.argv[2:7]
cible = fdroid / "public" / "latest.json"

precedent = {}
if cible.exists():
    try:
        precedent = json.loads(cible.read_text())
    except ValueError:
        precedent = {}

version = None
index = fdroid / "repo" / "index-v1.json"
if index.exists():
    paquets = json.loads(index.read_text()).get("packages", {}).get(app_id, [])
    if paquets:
        version = max(paquets, key=lambda p: p.get("versionCode", 0))

apks = list((fdroid / "repo").glob("*.apk"))
if not apks:
    if cible.exists():
        cible.unlink()
    print("   · pas d'APK : pas de latest.json")
    sys.exit(0)

def code_depuis_nom(chemin):
    trouve = re.search(r"(\d+)\.apk$", chemin.name)
    return int(trouve.group(1)) if trouve else 0

apk = max(apks, key=code_depuis_nom)
code = version["versionCode"] if version else code_depuis_nom(apk)
nom = version["versionName"] if version else "—"
taille = version["size"] if version else apk.stat().st_size
sha = version["hash"] if version else hashlib.sha256(apk.read_bytes()).hexdigest()

if note_b64:
    note = base64.b64decode(note_b64).decode("utf-8").strip()
elif precedent.get("versionCode") == code:
    note = precedent.get("note", "")
else:
    note = ""

minimum = precedent.get("minVersionCode", 0) or 0
if exiger == "1":
    minimum = code

cible.write_text(json.dumps({
    "package": app_id,
    "versionName": nom,
    "versionCode": code,
    "url": f"https://{domaine}/fdroid/{fichier_apk}",
    "sha256": sha,
    "size": taille,
    "minVersionCode": minimum,
    "note": note,
    "publishedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}, ensure_ascii=False, indent=2) + "\n")
suffixe = f", minimum exigé : build {minimum}" if minimum else ""
print(f"   ✓ latest.json : {nom} (build {code}){suffixe}")
PY

# Caddy sert ce répertoire en lecture seule ; il doit pouvoir lire ce qu'on vient d'écrire.
chmod -R a+rX "$FDROID_DIR/repo" 2>/dev/null || true
chmod -R a+rX "$FDROID_DIR/public" 2>/dev/null || true

exit "$STATUS"
