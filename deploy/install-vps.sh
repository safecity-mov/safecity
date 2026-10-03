#!/usr/bin/env bash
# L'application — installation du VPS, de zéro à une instance qui répond (SPEC §7, §14 semaine 7).
#
# S'exécute **sur le VPS**, en root, sur une Debian 12/13 ou une Ubuntu 22.04/24.04 fraîche
# (Hetzner CX22 ou équivalent). Il est écrit pour être rejoué : chaque étape regarde d'abord
# si elle a déjà été faite. Le relancer après avoir resynchronisé le dépôt (voir
# deploy/README.md, et rsync-exclude.txt) met l'instance à jour sans rien perdre.
#
# Ce qu'il ne fait pas, et ne fera pas :
#   — il n'écrase jamais un `.env` existant. Les secrets ne se régénèrent pas sous les pieds
#     d'une base qui tourne : `PGRST_JWT_SECRET` changé révoque tous les jetons d'admin, et
#     `AUTHENTICATOR_PASSWORD` changé coupe PostgREST de la base.
#   — il ne touche pas au volume de données.
#   — il ne crée aucun administrateur : `make admin-add EMAIL=…` reste un geste conscient.
#
# Usage, sur le VPS :
#   cd /opt/app/deploy && ./install-vps.sh
#
# Licence : AGPL-3.0.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SERVER="$ROOT/server"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

sc_load_env "$HERE" SITE_DOMAIN ADMIN_DOMAIN TILES_REGION
APP_AUTHOR="$(sc_app_author "$ROOT")"
sc_require_domain

DEPLOY_USER="${DEPLOY_USER:-app}"
FDROID_DIR="$SERVER/fdroid"

[ "$(id -u)" = 0 ] || sc_die "à lancer en root sur le VPS (sudo ./install-vps.sh)."
[ -f "$SERVER/docker-compose.yml" ] || sc_die "arborescence inattendue : $SERVER/docker-compose.yml introuvable."

. /etc/os-release 2>/dev/null || true
case "${ID:-}" in
  debian|ubuntu) : ;;
  *) sc_warn "distribution non testée (${ID:-inconnue}) : le script suppose apt et systemd." ;;
esac

sc_step "L'application — installation du VPS"
sc_info "domaine public  : $SITE_DOMAIN"
sc_info "console         : $ADMIN_DOMAIN"
sc_info "dépôt           : $ROOT"
sc_info "fond de carte   : $TILES_REGION"


# --- 1. Paquets de base -----------------------------------------------------
sc_step "1/9 — paquets de base"
export DEBIAN_FRONTEND=noninteractive
# Sur une Ubuntu fraîche, les mises à jour automatiques démarrent d'elles-mêmes peu après le
# premier boot et tiennent le verrou d'apt plusieurs minutes. Avec ce délai, apt attend en
# l'annonçant (« Waiting for cache lock ») au lieu d'échouer — ou d'attendre sans rien dire.
APT="apt-get -o DPkg::Lock::Timeout=900"
$APT update -qq
$APT install -y -qq \
  ca-certificates curl git gnupg rsync openssl make \
  ufw unattended-upgrades python3-yaml >/dev/null
sc_ok "paquets installés."

# Les mises à jour de sécurité s'appliquent seules : personne ne surveillera ce VPS tous
# les matins pendant une bêta qui peut durer des mois.
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
sc_ok "mises à jour de sécurité automatiques activées."


# --- 2. Swap ----------------------------------------------------------------
# Un CX22 a 4 Go. La construction de l'image de la console (npm ci) et l'extraction du
# PMTiles y passent tout juste ; sans swap, l'OOM killer tombe sur Postgres, qui n'y est
# pour rien. 2 Go suffisent à absorber les pics.
sc_step "2/9 — swap"
# On regarde le swap *actif*, pas la présence du fichier : un fichier laissé par une tentative
# ratée ne compte pas, et c'est exactement le cas qu'on veut pouvoir rejouer.
if swapon --show --noheadings 2>/dev/null | grep -q .; then
  sc_ok "swap déjà en place."
else
  # `dd` et non `fallocate` : le noyau refuse un fichier de swap troué, et fallocate en produit
  # sur certains systèmes de fichiers. Sur btrfs il faut en plus couper le copy-on-write avant
  # d'écrire le premier octet, sinon swapon répond « Operation not permitted ».
  rm -f /swapfile
  if [ "$(df --output=fstype / | tail -n 1)" = btrfs ]; then
    truncate -s 0 /swapfile
    chattr +C /swapfile 2>/dev/null || true
  fi
  dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  if swapon /swapfile 2>/dev/null; then
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sc_ok "2 Go de swap."
  else
    # Un confort, pas une condition : on continue sans, en le disant.
    rm -f /swapfile
    sc_warn "swap impossible sur ce système ($(df --output=fstype / | tail -n 1)) — on continue sans."
    sc_warn "Postgres et le build de la console tiendront dans 4 Go, avec moins de marge."
  fi
fi


# --- 3. Pare-feu ------------------------------------------------------------
# Postgres et Supabase Studio sont publiés sur 127.0.0.1 par Compose, donc déjà hors de
# portée ; ufw ferme ce qu'un futur service publierait par distraction.
sc_step "3/9 — pare-feu"
ufw --force default deny incoming >/dev/null
ufw --force default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
sc_ok "ufw : 22, 80, 443 ouverts, le reste fermé."


# --- 4. SSH -----------------------------------------------------------------
sc_step "4/9 — accès SSH"
if [ "${HARDEN_SSH:-oui}" != "oui" ]; then
  sc_info "durcissement SSH désactivé (HARDEN_SSH=$HARDEN_SSH)."
elif [ ! -s /root/.ssh/authorized_keys ]; then
  # Couper l'authentification par mot de passe sans clé autorisée, c'est se verrouiller
  # dehors définitivement. On refuse plutôt que de « réparer » à l'aveugle.
  sc_warn "aucune clé dans /root/.ssh/authorized_keys : mot de passe laissé actif."
else
  install -d -m 755 /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/10-app.conf <<'SSHD'
# L'application — l'accès SSH est le vrai facteur d'authentification de l'administration
# (server/admin-token.sh) : le jeton d'admin est délivré à la main sur cette machine.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
SSHD
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  sc_ok "authentification par mot de passe désactivée."
fi

# Utilisateur de publication. Il ne sert qu'à déposer les APK et à régénérer l'index du
# dépôt F-Droid : ni Docker, ni sudo, ni accès à la base. Une clé volée sur le poste de
# développement ne donne donc pas le serveur.
if ! id -u "$DEPLOY_USER" >/dev/null 2>&1; then
  # `useradd` plutôt qu'`adduser` : le second est un script dont les options changent d'une
  # version de Debian à l'autre, et un compte créé sans shell ne peut pas recevoir de commande
  # SSH — ce qui est précisément ce qu'on lui demande.
  useradd --system --create-home --home-dir "/home/$DEPLOY_USER" \
          --shell /bin/bash --user-group "$DEPLOY_USER"
  sc_ok "utilisateur $DEPLOY_USER créé."
fi
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
AUTHORIZED="/home/$DEPLOY_USER/.ssh/authorized_keys"
touch "$AUTHORIZED"
if [ -n "${ADMIN_SSH_KEY:-}" ]; then
  # Soit un chemin vers une clé publique, soit la clé collée telle quelle dans vps.env.
  if [ -f "$ADMIN_SSH_KEY" ]; then KEY_TEXT="$(cat "$ADMIN_SSH_KEY")"; else KEY_TEXT="$ADMIN_SSH_KEY"; fi
elif [ -s /root/.ssh/authorized_keys ]; then
  KEY_TEXT="$(cat /root/.ssh/authorized_keys)"
  sc_info "clés reprises de celles autorisées pour root."
else
  KEY_TEXT=""
fi
if [ -n "$KEY_TEXT" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    grep -qxF "$line" "$AUTHORIZED" || printf '%s\n' "$line" >> "$AUTHORIZED"
  done <<< "$KEY_TEXT"
  sc_ok "clé(s) autorisée(s) pour $DEPLOY_USER."
else
  sc_warn "aucune clé pour $DEPLOY_USER : release-app.sh ne pourra pas publier."
fi
chown "$DEPLOY_USER:$DEPLOY_USER" "$AUTHORIZED"
chmod 600 "$AUTHORIZED"


# --- 5. Docker --------------------------------------------------------------
sc_step "5/9 — Docker"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  sc_ok "déjà installé : $(docker --version)"
else
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  $APT update -qq
  $APT install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  systemctl enable --now docker >/dev/null
  sc_ok "$(docker --version)"
fi


# --- 6. Secrets du serveur --------------------------------------------------
sc_step "6/9 — configuration du serveur"
if [ -f "$SERVER/.env" ]; then
  sc_ok ".env existant conservé — aucun secret n'est régénéré."
  # Les deux domaines, eux, peuvent bouger : un changement de DNS ne doit pas demander de
  # réinstaller. Le reste du fichier est laissé intact.
  tmp="$(mktemp)"
  sed -e "s|^SITE_DOMAIN=.*|SITE_DOMAIN=$SITE_DOMAIN|" \
      -e "s|^ADMIN_DOMAIN=.*|ADMIN_DOMAIN=$ADMIN_DOMAIN|" "$SERVER/.env" > "$tmp"
  cat "$tmp" > "$SERVER/.env"; rm -f "$tmp"
  sc_ok "domaines mis à jour dans .env."
else
  umask 077
  cat > "$SERVER/.env" <<ENV
# L'application — secrets de l'instance. Générés par deploy/install-vps.sh le $(date -u +%Y-%m-%d).
# Ne jamais les régénérer sur une base qui tourne : PGRST_JWT_SECRET révoque tous les jetons
# d'administration, AUTHENTICATOR_PASSWORD coupe PostgREST de la base.
POSTGRES_DB=app
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 32)
AUTHENTICATOR_PASSWORD=$(openssl rand -hex 32)
PGRST_JWT_SECRET=$(openssl rand -hex 32)
SITE_DOMAIN=$SITE_DOMAIN
ADMIN_DOMAIN=$ADMIN_DOMAIN
ENV
  chmod 600 "$SERVER/.env"
  umask 022
  sc_ok ".env créé, secrets tirés au sort."
fi


# --- 7. Fond de carte -------------------------------------------------------
sc_step "7/9 — fond de carte"
BASEMAP="$SERVER/tiles/data/basemap.pmtiles"
if [ -s "$BASEMAP" ]; then
  sc_ok "basemap.pmtiles déjà présent ($(du -h "$BASEMAP" | cut -f1))."
else
  FREE_GB="$(df -BG --output=avail "$SERVER" | tail -n 1 | tr -dc '0-9')"
  if [ "$TILES_REGION" = france ] && [ "${FREE_GB:-0}" -lt 20 ]; then
    sc_warn "seulement ${FREE_GB} Go libres : l'extrait France en demande ~10, plus la base et les images."
    sc_warn "Basculer sur TILES_REGION=idf (~300 Mo) si l'installation échoue faute de place."
  fi
  sc_info "extraction depuis le build quotidien de Protomaps — comptez 20 à 60 minutes."
  "$SERVER/tiles/fetch-pmtiles.sh" "$TILES_REGION"
  sc_ok "fond de carte extrait."
fi

if [ -d "$SERVER/tiles/data/fonts" ] && [ -f "$SERVER/tiles/data/style.json" ]; then
  sc_ok "glyphes et style déjà en place."
else
  # Sans glyphes auto-hébergés : une carte sans aucun nom de rue, ou un appel vers un CDN
  # tiers à chaque déplacement. Les deux sont exclus (§7, §11.5).
  "$SERVER/tiles/fetch-assets.sh"
  sc_ok "glyphes, sprite et style servis."
fi


# --- 8. Services ------------------------------------------------------------
# Le profil `tiles` n'est pas optionnel en production : MapLibre Native attend des tuiles
# /z/x/y, et sans `tileserver` le style servi pointe sur un 502. C'est la différence entre
# ce qu'on lance en développement (`make up`) et ce qui doit tourner ici.
sc_step "8/9 — services"
# Créé avant que Compose ne le monte : un montage vers un chemin absent fait créer le
# répertoire par Docker, en root, et l'utilisateur de publication ne peut plus y écrire.
# public/repo est vide et le reste : c'est le point où Docker monte repo/ par-dessus, et il
# doit exister avant, le montage parent étant en lecture seule (voir docker-compose.yml).
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$FDROID_DIR" "$FDROID_DIR/repo" "$FDROID_DIR/public" "$FDROID_DIR/public/repo"
cd "$SERVER"
# Compose attend les dépendances lui-même, mais avec sa propre patience : dépassée, il sort
# en erreur et laisse Caddy non démarré. On tolère cette sortie, on attend nous-mêmes que
# PostgREST soit sain, puis on relance `up` — sans effet sur ce qui tourne, il ne fait que
# démarrer ce qui attendait.
docker compose --profile tiles up -d --build db rest admin caddy tileserver \
  || sc_warn "un service n'était pas prêt dans le délai de Compose — on attend nous-mêmes."

# Quand Compose renonce, il laisse les services qui dépendaient de la base à l'état
# « créé », jamais démarrés : attendre PostgREST à ce moment-là, c'est attendre un
# conteneur éteint. On attend donc d'abord la base elle-même, puis on redonne l'ordre de
# démarrage, et seulement ensuite on sonde PostgREST. Le premier démarrage d'une base
# sur un disque réseau lent a pris plus de deux minutes : on lui laisse dix.
sc_info "attente de la base…"
DB_OK=0
for _ in $(seq 1 120); do
  STATE="$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q db 2>/dev/null)" 2>/dev/null || true)"
  if [ "$STATE" = healthy ]; then DB_OK=1; break; fi
  sleep 5
done
if [ "$DB_OK" != 1 ]; then
  sc_die "la base n'est toujours pas prête après 10 minutes. Pour voir pourquoi :
       cd $SERVER && docker compose logs --tail=50 db"
fi
sc_ok "base prête."
docker compose --profile tiles up -d db rest admin caddy tileserver

# Sondé depuis l'hôte : l'image PostgREST n'a pas de shell, aucun healthcheck Docker ne
# peut tourner dedans. `/ready` ne répond 200 qu'une fois la base jointe et le cache de
# schéma chargé — c'est ce qu'on attend, et rien de moins.
sc_info "attente de PostgREST…"
READY=0
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null http://127.0.0.1:3001/ready 2>/dev/null; then READY=1; break; fi
  sleep 5
done
if [ "$READY" != 1 ]; then
  sc_die "PostgREST ne répond toujours pas sur /ready après 5 minutes. Pour voir pourquoi :
       cd $SERVER && docker compose logs --tail=50 rest && docker compose logs --tail=50 db"
fi
# Le Caddyfile est monté fichier par fichier dans le conteneur. rsync le remplace par un
# nouveau fichier plutôt que d'écrire dans l'ancien, et le montage, lui, garde l'ancien : Caddy
# continuerait de servir la configuration d'avant, `up -d` ne voyant rien à changer. On le
# recrée donc à chaque passage — une seconde de coupure, contre une configuration qui
# n'arrive jamais.
docker compose up -d --force-recreate --no-deps caddy >/dev/null
# Le journal des téléchargements a déménagé de /data vers son propre volume (partagé avec la
# console) : on emporte l'ancien, une fois, pour ne pas perdre les premiers comptes.
# Sous un autre nom que le fichier courant, que Caddy vient de créer et tient ouvert ; `mv`
# garde la date de l'ancien, donc la console le lit en premier, et `make downloads` aussi
# (`-` avant `.` dans l'ordre des noms).
docker compose exec -T caddy sh -c '
  [ -f /data/downloads.log ] && mv /data/downloads.log /var/log/caddy/downloads-migrated.log
  for f in /data/downloads-*.log; do [ -f "$f" ] && mv "$f" /var/log/caddy/; done
  chmod 0644 /var/log/caddy/downloads*.log 2>/dev/null; true' >/dev/null 2>&1 || true
sc_ok "services démarrés."

# Les migrations en attente, une fois chacune (db/migrate.sh, registre `schema_migrations`).
# Le volume survit à une réinstallation : les appliquer ici est ce qui fait de ce script un
# outil de mise à jour autant que d'installation. Un échec arrête tout ici même : le 21/09,
# une boucle qui continuait a laissé une fonction périmée en place en disant « appliquées ».
docker compose exec -T db /db/migrate.sh \
  || sc_die "une migration a échoué (voir ci-dessus) : la base n'a pas bougé, rien n'a été recouvert."
sc_ok "migrations appliquées."


# --- 9. Dépôt F-Droid -------------------------------------------------------
sc_step "9/9 — dépôt F-Droid"
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$FDROID_DIR"

if ! command -v fdroid >/dev/null 2>&1; then
  # Gros paquet : il tire un Java complet et une pile Python. Plusieurs minutes, une seule
  # fois. La sortie d'erreur reste visible, c'est là qu'apt annonce qu'il attend un verrou.
  sc_info "installation de fdroidserver — plusieurs minutes, une seule fois…"
  $APT install -y -qq fdroidserver >/dev/null || sc_warn "fdroidserver n'a pas pu être installé."
fi

if command -v fdroid >/dev/null 2>&1; then
  if [ -f "$FDROID_DIR/config.yml" ]; then
    sc_ok "dépôt déjà initialisé — la clé d'index est conservée."
  else
    # « ERROR: No Android SDK found! » à cette étape n'est qu'un message : fdroid init ne
    # s'arrête que si un sdk_path configuré est introuvable, et fdroid update lit les APK
    # avec androguard et vérifie les signatures avec l'apksigner du PATH, tous deux
    # installés par le paquet. Aucun SDK Android n'est nécessaire sur ce serveur.
    #
    # La clé qui signe l'index n'est PAS celle qui signe l'APK. Perdre celle-ci oblige les
    # testeurs à retirer et rajouter le dépôt (son empreinte est dans l'URL) ; perdre celle
    # de l'APK perdrait l'application. D'où deux clés, et une seule sur ce serveur.
    runuser -u "$DEPLOY_USER" -- sh -c "cd '$FDROID_DIR' && fdroid init --repo-keyalias app-repo --keystore keystore.p12 -d 'CN=$APP_AUTHOR'" >/dev/null
    sc_ok "dépôt initialisé, clé d'index créée."
  fi
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$FDROID_DIR"

  # vps-publish.sh tourne sous $DEPLOY_USER et lit hors de son répertoire : vps.env et le
  # gabarit de page dans deploy/, l'applicationId dans app/android/app.properties. Ces
  # fichiers arrivent du poste de développement avec les droits qu'ils y avaient, parfois
  # lisibles par leur seul propriétaire — et ici leur propriétaire est root. Aucun d'eux
  # n'est secret (vps.env n'en contient pas) : on les rend lisibles, et on ouvre le chemin
  # qui y mène. « X » ne donne l'exécution qu'aux répertoires et à ce qui l'avait déjà.
  chmod a+rx "$ROOT" "$ROOT/app" "$ROOT/app/android" "$SERVER"
  chmod -R a+rX "$HERE"
  chmod a+r "$ROOT/app/android/app.properties"

  runuser -u "$DEPLOY_USER" -- "$HERE/vps-publish.sh" \
    || sc_warn "index non régénéré — voir /tmp/fdroid-update.log."
else
  sc_warn "index F-Droid non généré. Les APK déposés resteront téléchargeables à la main."
fi


# --- Récapitulatif ----------------------------------------------------------
FINGERPRINT=""
[ -f "$FDROID_DIR/public/fingerprint.txt" ] && FINGERPRINT="$(cat "$FDROID_DIR/public/fingerprint.txt")"

cat <<FIN

${SC_BOLD}== Instance en ligne ==${SC_RESET}

   API           https://$SITE_DOMAIN/rest/v1/
   Console       https://$ADMIN_DOMAIN/
   Téléchargement https://$SITE_DOMAIN/apk

   ${SC_BOLD}DNS${SC_RESET} — deux enregistrements A vers l'IP de ce VPS, sans quoi Caddy n'obtient
   aucun certificat : $SITE_DOMAIN et $ADMIN_DOMAIN

   ${SC_BOLD}Créer un modérateur${SC_RESET}
     cd $SERVER && make admin-add EMAIL=moderation@example.org

   ${SC_BOLD}Publier l'app${SC_RESET} — depuis le poste de développement, pas d'ici :
     ./deploy/release-app.sh --bump patch

FIN

if [ -n "$FINGERPRINT" ]; then
  cat <<FIN
   ${SC_BOLD}Dépôt F-Droid${SC_RESET} — l'adresse à donner aux testeurs, empreinte comprise.
   Sans l'empreinte, le client F-Droid accepte n'importe quel index signé par n'importe qui.

     https://$SITE_DOMAIN/fdroid/repo?fingerprint=$FINGERPRINT

   ${SC_BOLD}À sauvegarder hors de ce VPS${SC_RESET}
     $FDROID_DIR/keystore.p12   la clé qui signe l'index
     $FDROID_DIR/config.yml     son mot de passe
     $SERVER/.env               les secrets de la base

   Perdre la clé d'index oblige chaque testeur à retirer puis rajouter le dépôt : son
   empreinte est dans l'URL ci-dessus.

FIN
fi
