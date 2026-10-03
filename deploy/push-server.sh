#!/usr/bin/env bash
# L'application — envoie le dépôt sur le VPS, et lance l'installation si on le demande.
#
# S'exécute sur le poste de développement. C'est la commande rsync du mode d'emploi, avec
# ce qu'on oublie quand on la tape à la main :
#   — la liste de ce qui ne monte jamais (rsync-exclude.txt), dont deux entrées écraseraient
#     l'état du serveur de façon irréparable ;
#   — la lisibilité de ce qui monte. rsync -a recopie les droits du poste ; un vps.env créé
#     en 600 arrive en 600, appartenant à root, et l'utilisateur de publication ne peut plus
#     le lire. Rien de ce qui monte n'est secret — c'est la liste d'exclusion qui le
#     garantit — donc tout peut être lisible par tous sur le serveur.
#
# Usage :
#   ./deploy/push-server.sh               envoie — rien n'est redémarré ni rejoué
#   ./deploy/push-server.sh --install     envoie, puis lance install-vps.sh sur le serveur
#   ./deploy/push-server.sh --status      dit à quel commit est le serveur, n'envoie rien
#   ./deploy/push-server.sh --dry-run     montre ce qui partirait, n'envoie rien
#   ./deploy/push-server.sh --force       passe outre les deux garde-fous ci-dessous
#
# Sans --install, seuls les fichiers changent : ça suffit pour deploy/ (vps-publish.sh, la
# page /apk), que le serveur exécute à la prochaine publication. Dès que le changement touche
# ce qui tourne — docker-compose.yml, le Caddyfile, une migration, la console, un paquet —
# il faut --install : c'est lui qui reconstruit, redémarre, migre. Il est rejouable et
# n'écrase ni les secrets ni le dépôt F-Droid ; en doute, le lancer ne coûte que du temps.
# Le script le dit lui-même quand des fichiers de ce genre ont changé depuis la dernière
# installation.
#
# Deux garde-fous, parce que le serveur doit correspondre à un commit et à un seul :
#   — l'arbre doit être propre : ce qui part est exactement le dernier commit, et on peut
#     le dire ensuite. Un envoi depuis un arbre modifié n'a pas de nom ;
#   — un commit déjà envoyé ne repart pas (déjà installé aussi, avec --install). Rien à
#     faire, et on le dit, plutôt qu'un rsync muet qui laisse croire qu'il s'est passé
#     quelque chose.
# Le serveur garde la trace dans deploy/DEPLOYED : commit envoyé, commit installé, dates.
#
# Licence : AGPL-3.0.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

INSTALL=0; DRY=""; STATUS=0; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1; shift ;;
    --status) STATUS=1; shift ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY="--dry-run --itemize-changes"; shift ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) sc_die "option inconnue : $1 (voir --help)" ;;
  esac
done

sc_load_env "$HERE" VPS_SSH VPS_ROOT
sc_require_domain
sc_need rsync; sc_need ssh; sc_need git

# L'installation se fait en root ; la publication, sous l'utilisateur de VPS_SSH. Même hôte.
TARGET="root@${VPS_SSH#*@}"
MARK="$VPS_ROOT/deploy/DEPLOYED"

# --- Où en est le serveur -----------------------------------------------------------------
HEAD_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
short() { printf '%s' "${1:0:7}"; }
# Le fichier de trace, tel qu'il est sur le serveur : absent avant le premier envoi qui l'écrit.
REMOTE_MARK="$(ssh "$TARGET" "cat '$MARK' 2>/dev/null" 2>/dev/null || true)"
mark() { printf '%s\n' "$REMOTE_MARK" | sed -n "s/^$1=//p" | head -n 1; }
PUSHED="$(mark pushed_commit)"; PUSHED_AT="$(mark pushed_at)"
INSTALLED="$(mark installed_commit)"; INSTALLED_AT="$(mark installed_at)"

# Ce qui, entre deux commits, demande --install : ce qui tourne, pas ce qui se lit.
needs_install_between() {
  git -C "$ROOT" cat-file -e "$1^{commit}" 2>/dev/null || return 1
  git -C "$ROOT" diff --quiet "$1" "$2" -- server admin deploy/install-vps.sh && return 1
  return 0
}

describe() {
  if [ -z "$PUSHED" ]; then
    sc_info "serveur : aucune trace d'envoi (antérieur à ce garde-fou)."
    return
  fi
  local behind
  if git -C "$ROOT" cat-file -e "$PUSHED^{commit}" 2>/dev/null; then
    behind="$(git -C "$ROOT" rev-list --count "$PUSHED..$HEAD_COMMIT")"
  else
    behind="?"
  fi
  sc_info "envoyé   : $(short "$PUSHED") le $PUSHED_AT"
  if [ -n "$INSTALLED" ]; then
    sc_info "installé : $(short "$INSTALLED") le $INSTALLED_AT"
  else
    sc_info "installé : jamais depuis ce garde-fou"
  fi
  if [ "$PUSHED" = "$HEAD_COMMIT" ]; then
    sc_ok "le serveur a le dernier commit ($(short "$HEAD_COMMIT"))."
  else
    sc_info "poste    : $(short "$HEAD_COMMIT"), $behind commit(s) plus loin."
  fi
  if [ -n "$INSTALLED" ] && [ "$INSTALLED" != "$PUSHED" ] && needs_install_between "$INSTALLED" "$PUSHED"; then
    sc_warn "des fichiers serveur ont changé depuis la dernière installation : --install attendu."
  fi
}

if [ "$STATUS" = 1 ]; then
  sc_step "État du serveur $TARGET"
  describe
  exit 0
fi

# --- Garde-fou 1 : l'arbre doit être exactement le dernier commit -------------------------
if [ -z "$DRY" ] && [ "$FORCE" = 0 ] && [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  git -C "$ROOT" status --short | head -n 15 >&2
  sc_die "arbre modifié : ce qui partirait n'est pas le commit $(short "$HEAD_COMMIT"). Commiter d'abord (ou --force)."
fi

# --- Garde-fou 2 : un commit déjà envoyé ne repart pas ------------------------------------
if [ -z "$DRY" ] && [ "$FORCE" = 0 ] && [ "$PUSHED" = "$HEAD_COMMIT" ]; then
  if [ "$INSTALL" = 0 ]; then
    describe
    sc_die "le commit $(short "$HEAD_COMMIT") est déjà sur le serveur. Rien à envoyer (--install pour installer, --force pour renvoyer)."
  elif [ "$INSTALLED" = "$HEAD_COMMIT" ]; then
    describe
    sc_die "le commit $(short "$HEAD_COMMIT") est déjà envoyé et installé. Rien à faire (--force pour rejouer)."
  fi
fi

sc_step "Envoi du dépôt vers $TARGET:$VPS_ROOT/ (commit $(short "$HEAD_COMMIT"))"
[ -n "$DRY" ] && sc_info "essai : rien ne part."
# shellcheck disable=SC2086
rsync -a $DRY \
  --chmod=Dgo+rx,Fgo+r \
  --exclude-from="$HERE/rsync-exclude.txt" \
  "$ROOT/" "$TARGET:$VPS_ROOT/"
[ -n "$DRY" ] && exit 0
sc_ok "dépôt synchronisé."

# Ceinture et bretelles : le --chmod ci-dessus dépend de l'implémentation de rsync — celle
# que macOS livre depuis Sequoia est openrsync, qui n'en fait pas toujours le même usage
# sur les fichiers déjà en place. On règle donc les droits sur le serveur, explicitement,
# sur les seuls chemins que vps-publish.sh lit sous l'utilisateur de publication.
ssh "$TARGET" "chmod a+rx '$VPS_ROOT' '$VPS_ROOT/app' '$VPS_ROOT/app/android' '$VPS_ROOT/server' \
  && chmod -R a+rX '$VPS_ROOT/deploy' \
  && chmod a+r '$VPS_ROOT/app/android/app.properties'"
sc_ok "droits de lecture posés pour l'utilisateur de publication."

# La trace : ce qui vient de partir, en gardant ce qui a été installé. Réécrite en entier,
# lisible par tous comme le reste de deploy/.
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
write_mark() {
  ssh "$TARGET" "printf 'pushed_commit=%s\npushed_at=%s\ninstalled_commit=%s\ninstalled_at=%s\n' \
    '$HEAD_COMMIT' '$NOW' '$1' '$2' > '$MARK' && chmod a+r '$MARK'"
}
write_mark "$INSTALLED" "$INSTALLED_AT"

if [ "$INSTALL" = 1 ]; then
  sc_step "Installation sur le serveur"
  TTY=""; [ -t 0 ] && TTY="-t"
  # shellcheck disable=SC2086
  ssh $TTY "$TARGET" "cd '$VPS_ROOT/deploy' && ./install-vps.sh"
  write_mark "$HEAD_COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sc_ok "installé : $(short "$HEAD_COMMIT")."
else
  if [ -n "$INSTALLED" ] && needs_install_between "$INSTALLED" "$HEAD_COMMIT"; then
    sc_warn "des fichiers serveur ont changé depuis l'installation de $(short "$INSTALLED") : lancer ./deploy/push-server.sh --install"
  elif [ -z "$INSTALLED" ]; then
    sc_warn "aucune trace d'installation : impossible de dire si ce qui tourne a changé. Dans le doute, ./deploy/push-server.sh --install"
  else
    sc_info "rien de ce qui tourne n'a changé depuis l'installation de $(short "$INSTALLED") : --install inutile."
  fi
fi
