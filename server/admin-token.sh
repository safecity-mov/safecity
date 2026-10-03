#!/usr/bin/env bash
# L'application — crée un administrateur et imprime son jeton (SPEC §4.3).
#
# Il n'y a pas d'écran de connexion : le jeton EST l'authentification. Il est délivré ici, à
# la main, sur la machine qui héberge — ce qui suppose un accès SSH au serveur, et fait de cet
# accès le vrai facteur d'authentification. Trois comptes au plus (§4.3), entre gens qui se
# connaissent : c'est proportionné à une bêta fermée, et insuffisant pour l'ouverture, où il
# faudra de vrais comptes.
#
# Le jeton n'expire pas. Pour révoquer, désactiver l'administrateur — toute lecture et toute
# action passent alors par `current_admin()`, qui le refuse :
#   UPDATE admins SET disabled_at = now() WHERE email = '…';
# Si c'est le secret lui-même qui a fui, changer PGRST_JWT_SECRET dans .env et redémarrer
# `rest` : tous les jetons émis tombent d'un coup.
#
# Usage :  ./admin-token.sh moderation@example.org
set -euo pipefail

EMAIL="${1:-}"
if [ -z "$EMAIL" ]; then
  echo "usage : $0 <email>" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
set -a; . "$HERE/.env"; set +a

if [ -z "${PGRST_JWT_SECRET:-}" ]; then
  echo "PGRST_JWT_SECRET manquant dans .env" >&2
  exit 1
fi

USER_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"

# Paramètres psql plutôt qu'une interpolation dans le SQL : une apostrophe dans l'adresse ne
# doit pas devenir du SQL. Par l'entrée standard et non par `-c` : psql ne substitue ses
# variables que dans ce qu'il lit lui-même, `-c` envoyant la chaîne telle quelle au serveur.
docker compose -f "$HERE/docker-compose.yml" exec -T db \
  psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-postgres}" --dbname "${POSTGRES_DB:-app}" \
  -q -v uid="$USER_ID" -v email="$EMAIL" <<'SQL'
INSERT INTO admins (user_id, email) VALUES (:'uid', :'email');
SQL

python3 - "$USER_ID" "$PGRST_JWT_SECRET" <<'PY'
import base64, hashlib, hmac, json, sys

def b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b'=').decode()

user_id, secret = sys.argv[1], sys.argv[2]
# `role` est ce que PostgREST assume ; `sub` est ce que current_admin() vérifie dans `admins`.
header = b64(json.dumps({'alg': 'HS256', 'typ': 'JWT'}, separators=(',', ':')).encode())
payload = b64(json.dumps({'role': 'admin_api', 'sub': user_id}, separators=(',', ':')).encode())
signing_input = f'{header}.{payload}'.encode()
signature = b64(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
print(f'{header}.{payload}.{signature}')
PY
