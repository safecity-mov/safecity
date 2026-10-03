#!/usr/bin/env bash
# L'application — glyphes de police et sprite d'icônes (SPEC §7).
#
# Sans glyphes auto-hébergés, deux options seulement : une carte sans aucun nom
# de rue, ou un appel vers un CDN tiers à chaque déplacement de la carte. Les
# deux sont exclues (§7, §11.5), donc on les sert depuis le VPS.
#
# Usage : ./tiles/fetch-assets.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HERE/data/fonts"
SPRITES="$HERE/data/sprites"
SOURCE="https://github.com/protomaps/basemaps-assets/archive/refs/heads/main.tar.gz"

# Les polices sont lues dans le style lui-même : une police ajoutée au style et
# oubliée ici renvoie des 404 sur les glyphes, et MapLibre cesse alors d'afficher
# *toutes* les étiquettes — pas seulement celles de la police manquante.
STYLE="$HERE/../../app/assets/map_style.json"
if [ -f "$STYLE" ]; then
  IFS=$'\n' read -r -d '' -a WANTED < <(
    python3 -c "
import json, sys
style = json.load(open('$STYLE'))
polices = set()
for couche in style.get('layers', []):
    for police in couche.get('layout', {}).get('text-font', []):
        polices.add(police)
print('\n'.join(sorted(polices)))
" && printf '\0'
  )
else
  WANTED=("Noto Sans Regular" "Noto Sans Medium")
fi
echo "polices demandées par le style : ${#WANTED[@]}"

echo "source : $SOURCE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$SOURCE" | tar -xz -C "$tmp"
root="$(find "$tmp" -maxdepth 1 -type d -name 'basemaps-assets-*' | head -1)"

mkdir -p "$DEST"
for font in "${WANTED[@]}"; do
  if [ ! -d "$root/fonts/$font" ]; then
    echo "police absente du dépôt amont : $font" >&2
    exit 1
  fi
  rm -rf "$DEST/$font"
  cp -R "$root/fonts/$font" "$DEST/$font"
  echo "  $font — $(ls "$DEST/$font" | wc -l | tr -d ' ') plages"
done

# Sprite des points d'intérêt, référencé par app/assets/map_style.json.
mkdir -p "$SPRITES"
for f in light.json light.png light@2x.json light@2x.png; do
  if [ ! -f "$root/sprites/v4/$f" ]; then
    echo "sprite absent du dépôt amont : $f" >&2
    exit 1
  fi
  cp "$root/sprites/v4/$f" "$SPRITES/$f"
done
echo "  sprite light — $(ls "$SPRITES" | wc -l | tr -d ' ') fichiers"

echo
echo "✓ glyphes servis sur /tiles/fonts/{fontstack}/{range}.pbf"
echo "✓ sprite servi sur   /tiles/sprites/light"
echo "  Polices Noto sous licence SIL Open Font License 1.1."

# Style servi par l'instance, pour le téléchargement de zones hors ligne (§10).
#
# MapLibre télécharge une région à partir d'une **URL** de style : il refuse un
# contenu, un `file://` et un chemin nu (« Unable to parse resourceUrl »). Le
# style doit donc être joignable en HTTP, et sur la même instance que les tuiles
# — aucune requête de l'app ne sort vers un tiers (§7, §11.5).
#
# L'adresse de base y est un gabarit Caddy plutôt qu'une valeur figée : le même
# fichier répond correctement au téléphone qui vient par `127.0.0.1:8080` et au
# navigateur qui vient par le domaine public. Voir la directive `templates` du
# Caddyfile.
STYLE_OUT="$HERE/data/style.json"
python3 - "$STYLE" "$STYLE_OUT" <<'PY'
import sys
src, dest = sys.argv[1], sys.argv[2]
base = '{{if .Req.TLS}}https{{else}}http{{end}}://{{.Req.Host}}/tiles'
open(dest, 'w', encoding='utf-8').write(
    open(src, encoding='utf-8').read().replace('{{TILES_BASE}}', base))
PY
echo "✓ style servi sur     /tiles/style.json"
