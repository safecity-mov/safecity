#!/usr/bin/env bash
# L'application — tests SQL des règles de modération (§6).
# « Les règles de modération sont testées en SQL, pas seulement via l'app. »
#
# Crée une base jetable, y applique toutes les migrations, joue les fichiers de db/tests,
# puis le jeu d'essai, puis la supprime. Ne touche jamais à la base de travail.
#
# Usage (dans le conteneur) : /db/run-tests.sh
# Usage (depuis l'hôte)     : make test
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PGUSER_="${POSTGRES_USER:-postgres}"
TEST_DB="app_tests_$$"

psql_() { psql -v ON_ERROR_STOP=1 --no-psqlrc --username "$PGUSER_" "$@"; }

cleanup() {
  psql_ --dbname postgres -c "DROP DATABASE IF EXISTS \"$TEST_DB\"" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== base de test : $TEST_DB =="
psql_ --dbname postgres -c "CREATE DATABASE \"$TEST_DB\"" >/dev/null

# `anon`, `authenticator` et `admin_api` sont des rôles de cluster : ils existent déjà si
# bootstrap.sh est passé. On s'en assure **avant** les migrations, et non après. Le rejeu de
# 0060 qui compensait leur absence réappliquait un fichier hors de son tour : une migration
# ultérieure ayant changé la signature d'une fonction, ce second passage échouait sur une
# fonction qui n'existait plus. `authenticator` est requis par 0070 (`GRANT admin_api TO
# authenticator`) : sur un cluster nu — une CI — il manquait.
psql_ --dbname "$TEST_DB" -q -c "DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN CREATE ROLE authenticator NOLOGIN NOINHERIT; END IF;
END \$\$;" >/dev/null

# Les migrations, par le même script que `make migrate` et le déploiement : chacune une fois,
# dans sa transaction, inscrite au registre `schema_migrations`.
"$HERE/migrate.sh" "$TEST_DB" >/dev/null

failures=0

# Le registre lui-même, sur trois points :
# 1. un second passage ne joue rien ;
# 2. une base d'avant le registre — elle a `hazards`, pas `schema_migrations` — est réputée à
#    0210 et reprend à 0220, sans rien rejouer d'autre ;
# 3. 0220 répare ce que le rejeu du 21/09 avait défait. On rejoue 0030 exprès, comme le
#    déploiement le faisait, ce qui réinstalle l'ancien `recompute_hazard` et les vieilles
#    surcharges ; puis on efface le registre. La suite pgTAP, ensuite, ne passe que si 0220 a
#    remis la dernière version de chaque objet (170_migrations.sql, 040_resolve.sql).
echo "── migrate.sh ────────────────────────────────────────"
if out="$("$HERE/migrate.sh" "$TEST_DB" 2>&1)" && grep -q '0 appliquée' <<<"$out"; then
  echo "ok - un second passage ne joue rien"
else
  echo "$out"; echo "‼ migrate.sh : un second passage devrait ne rien jouer"; failures=$((failures + 1))
fi
psql_ --dbname "$TEST_DB" -q --single-transaction -f "$HERE/migrations/0030_moderation_core.sql" >/dev/null
psql_ --dbname "$TEST_DB" -q -c "DROP TABLE schema_migrations" >/dev/null
expected="$(ls "$HERE"/migrations/*.sql | wc -l | tr -d ' ')"
if out="$("$HERE/migrate.sh" "$TEST_DB" 2>&1)" && grep -q 'antérieure au registre' <<<"$out" \
   && [ "$(psql_ --dbname "$TEST_DB" -At -c 'SELECT count(*) FROM schema_migrations')" = "$expected" ]; then
  echo "ok - une base d'avant le registre est reprise à 0210 et réparée par 0220 ($expected inscrites)"
else
  echo "$out"; echo "‼ migrate.sh : la reprise d'une base d'avant le registre échoue"; failures=$((failures + 1))
fi

psql_ --dbname "$TEST_DB" -q -c "CREATE EXTENSION IF NOT EXISTS pgtap" >/dev/null
psql_ --dbname "$TEST_DB" -q -f "$HERE/tests/_helpers.sql" >/dev/null

for f in "$HERE"/tests/[0-9]*.sql; do
  name="$(basename "$f")"
  echo
  echo "── $name ────────────────────────────────────────────"
  if ! out="$(psql_ --dbname "$TEST_DB" -At -f "$f" 2>&1)"; then
    echo "$out"
    echo "‼ $name : erreur SQL"
    failures=$((failures + 1))
    continue
  fi
  echo "$out"
  if grep -qE '^not ok' <<<"$out"; then
    failures=$((failures + 1))
    echo "‼ $name : $(grep -cE '^not ok' <<<"$out") test(s) en échec"
  fi
done

# Le jeu d'essai suit-il encore les signatures des RPC ? Joué ici, sur la base jetable,
# plutôt que découvert cassé sur une base de développement qu'il vient de vider.
echo
echo "── seed-demo.sql ─────────────────────────────────────"
if out="$(psql_ --dbname "$TEST_DB" -At -f "$HERE/seed-demo.sql" 2>&1)" \
   && [ "$(psql_ --dbname "$TEST_DB" -At -c 'SELECT count(*) FROM hazards')" = "12" ]; then
  echo "ok - le jeu d'essai se joue de bout en bout (12 dangers)"
else
  echo "$out"
  echo "‼ seed-demo.sql : ne se joue plus"
  failures=$((failures + 1))
fi

echo "── seed-suspects.sql ─────────────────────────────────"
if out="$(psql_ --dbname "$TEST_DB" -At -f "$HERE/seed-suspects.sql" 2>&1)" \
   && [ "$(psql_ --dbname "$TEST_DB" -At -c 'SELECT count(*) FROM hazards')" = "15" ]; then
  echo "ok - le jeu d'essai « saboteurs » se joue de bout en bout (15 dangers)"
else
  echo "$out"
  echo "‼ seed-suspects.sql : ne se joue plus"
  failures=$((failures + 1))
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "✓ toutes les règles du §6 passent"
else
  echo "✗ $failures fichier(s) en échec"
  exit 1
fi
