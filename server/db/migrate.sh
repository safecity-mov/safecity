#!/usr/bin/env bash
# L'application — applique les migrations en attente, une seule fois chacune.
#
# Un registre, `schema_migrations`, retient le nom de chaque fichier appliqué. À chaque appel,
# les fichiers déjà inscrits sont ignorés ; les autres sont joués dans l'ordre des noms, chacun
# dans sa propre transaction **avec** son inscription au registre : soit la migration passe et
# elle est inscrite, soit rien n'a bougé. Le premier échec arrête tout, bruyamment. Une
# migration qui ne passe pas n'est pas appliquée, et les suivantes ne doivent pas la recouvrir.
#
# Pourquoi un registre, et plus un rejeu complet à chaque déploiement : le rejeu reposait sur
# un invariant que personne ne vérifiait — « la dernière migration qui définit un objet doit
# repasser, parce que les précédentes le réinstallent dans une version périmée ». Le 21/09/2026,
# le déploiement de 0210 a rejoué 0030, qui a remis l'ancien `recompute_hazard`, puis 0200 a
# échoué (`cannot change name of input parameter "tier"`) sans que rien ne s'arrête : le serveur
# a refusé tous les gestes pendant six jours. L'en-tête de 0220 raconte le détail.
#
# Conséquence pour qui écrit une migration : **un fichier appliqué ne se modifie plus.** Ce qui
# doit changer se fait dans un nouveau fichier, numéroté après le dernier.
#
# Reprise d'une base antérieure au registre : elle a `hazards`, mais pas `schema_migrations`.
# Elle est réputée à BASELINE_UPTO, la dernière migration d'avant le registre : ces fichiers
# sont inscrits sans être joués, et l'application reprend au suivant. Une base restée en
# arrière de BASELINE_UPTO (un poste de développement pas mis à jour depuis longtemps) n'est
# pas reconnue : `make reset`, ou inscrire soi-même ce qui est vraiment en place.
#
# Usage : /db/migrate.sh [BASE]   — BASE vaut $POSTGRES_DB par défaut.
#   Dans le conteneur ; depuis l'hôte, `make migrate`. Appelé aussi par bootstrap.sh à la
#   création du volume, par install-vps.sh à chaque mise à jour, et par run-tests.sh sur la
#   base jetable.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="${1:-${POSTGRES_DB:-app}}"
BASELINE_UPTO="0210_implausible_jumps.sql"

psql_() { psql -v ON_ERROR_STOP=1 --no-psqlrc --username "${POSTGRES_USER:-postgres}" --dbname "$DB" -q "$@"; }

psql_ <<'EOSQL'
SET client_min_messages TO warning;   -- pas de « already exists, skipping » à chaque appel
CREATE TABLE IF NOT EXISTS schema_migrations (
  filename   text        PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE schema_migrations IS
  'Registre des migrations appliquées, tenu par db/migrate.sh : un fichier inscrit ne se '
  'rejoue plus. Ni anon ni admin_api ne le lisent.';
REVOKE ALL ON schema_migrations FROM PUBLIC;
EOSQL

# --- Reprise d'une base d'avant le registre ---------------------------------------------
recorded="$(psql_ -At -c "SELECT count(*) FROM schema_migrations")"
has_schema="$(psql_ -At -c "SELECT to_regclass('public.hazards') IS NOT NULL")"
if [ "$recorded" = 0 ] && [ "$has_schema" = t ]; then
  echo "-- base antérieure au registre : réputée à $BASELINE_UPTO, inscrite sans rejeu"
  values=""
  for f in "$HERE"/migrations/*.sql; do
    name="$(basename "$f")"
    [[ "$name" > "$BASELINE_UPTO" ]] && break
    values="${values:+$values, }('$name')"
  done
  [ -n "$values" ] && psql_ -c "INSERT INTO schema_migrations (filename) VALUES $values ON CONFLICT DO NOTHING"
fi

# --- Ce qui reste à jouer -----------------------------------------------------------------
recorded_list="$(psql_ -At -c "SELECT filename FROM schema_migrations")"
applied=0
skipped=0
for f in "$HERE"/migrations/*.sql; do
  name="$(basename "$f")"
  if grep -qxF "$name" <<<"$recorded_list"; then
    skipped=$((skipped + 1))
    continue
  fi
  echo "-- $name"
  # La migration et son inscription dans la même transaction (--single-transaction couvre
  # tous les -f et -c de l'appel) : pas d'état où l'une existe sans l'autre.
  if ! psql_ --single-transaction -f "$f" -c "INSERT INTO schema_migrations (filename) VALUES ('$name')"; then
    echo "‼ $name : échec. Rien de ce fichier n'est appliqué, et les migrations suivantes ne sont pas jouées." >&2
    exit 1
  fi
  applied=$((applied + 1))
done

echo "== migrations : $applied appliquée(s), $skipped déjà en place =="
psql_ -c "NOTIFY pgrst, 'reload schema'"
