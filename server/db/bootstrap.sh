#!/usr/bin/env bash
# L'application — amorçage de la base.
# Exécuté une fois par docker-entrypoint-initdb.d à la création du volume. Les migrations
# passent par db/migrate.sh, le même script que `make migrate` et la mise à jour du VPS : un
# registre (`schema_migrations`) retient ce qui est appliqué, chaque fichier ne se joue qu'une
# fois.
set -euo pipefail

DB="${POSTGRES_DB:-app}"
PSQL=(psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-postgres}" --dbname "$DB" --no-psqlrc)

echo "== L'application : rôles =="
# `authenticator` est le rôle de connexion de PostgREST ; il n'a aucun droit propre et
# bascule sur `anon` pour chaque requête (§8).
"${PSQL[@]}" <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD '${AUTHENTICATOR_PASSWORD:?AUTHENTICATOR_PASSWORD manquant}';
  ELSE
    ALTER ROLE authenticator LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD}';
  END IF;
END
\$\$;
GRANT anon TO authenticator;
EOSQL

echo "== L'application : migrations =="
/db/migrate.sh "$DB"

echo "== L'application : base prête =="
