#!/usr/bin/env bash
# L'application — extrait PMTiles du fond de carte (SPEC §7).
#
# Le fond de carte est auto-hébergé, et ce n'est pas qu'une question de coût : un fond de
# carte tiers reçoit la zone que l'utilisateur consulte à chaque déplacement de la carte.
# Aucune requête de l'app ne sort vers un domaine tiers (§7, §11.5).
#
# Le fichier s'appelle `basemap.pmtiles`, **par son rôle et non par son étendue**. Le
# serveur de tuiles dérive l'URL du nom de fichier : la renommer changerait l'adresse des
# tuiles, et le cache disque de MapLibre étant indexé par URL, cela le viderait d'un coup.
# Changer d'étendue ne doit pas coûter le cache de tous les téléphones.
#
# Usage : ./tiles/fetch-pmtiles.sh [france|idf|BBOX] [AAAAMMJJ]
# Sans argument, la France métropolitaine.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/data/basemap.pmtiles"

REGION="${1:-france}"
case "$REGION" in
  # France métropolitaine, Corse comprise. La bêta doit fonctionner partout en France :
  # un testeur qui descend à Lyon ne doit pas se retrouver devant une carte blanche.
  france) BBOX="-5.15,41.30,9.56,51.10"; LABEL="France métropolitaine (~9,4 Go)" ;;
  # L'extrait d'origine, conservé pour un poste de développement qui n'a pas la place.
  idf)    BBOX="1.4462,48.1200,3.5592,49.2413"; LABEL="Île-de-France (~300 Mo)" ;;
  *)      BBOX="$REGION"; LABEL="bbox fournie" ;;
esac

BUILD="${2:-$(date -u -v-1d +%Y%m%d 2>/dev/null || date -u -d yesterday +%Y%m%d)}"
SOURCE="https://build.protomaps.com/${BUILD}.pmtiles"

echo "source : $SOURCE"
echo "bbox   : $BBOX ($LABEL)"
echo "sortie : $OUT"
echo

mkdir -p "$HERE/data"

if command -v pmtiles >/dev/null 2>&1; then
  pmtiles extract "$SOURCE" "$OUT" --bbox="$BBOX"
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "$HERE/data:/data" ghcr.io/protomaps/go-pmtiles:latest \
    extract "$SOURCE" /data/basemap.pmtiles --bbox="$BBOX"
else
  echo "Il faut le CLI pmtiles (https://github.com/protomaps/go-pmtiles) ou Docker." >&2
  exit 1
fi

echo
echo "✓ $(du -h "$OUT" | cut -f1) — servi par Caddy sur /tiles/basemap/{z}/{x}/{y}.mvt"
echo "  Le build quotidien est ODbL / OpenStreetMap : l'attribution « © OpenStreetMap"
echo "  contributors » doit rester visible en permanence dans l'app (§12.5)."
