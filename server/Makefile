# L'application — serveur. Voir README.md.
SHELL := /bin/bash
COMPOSE := docker compose

.PHONY: help up down logs migrate seed seed-suspects test icons-default blocked psql tiles studio admin-add reset

help:
	@echo "make up       — démarre la base, PostgREST, la console d'administration et Caddy"
	@echo "make down     — arrête tout (les données sont conservées)"
	@echo "make migrate  — applique les migrations en attente (registre schema_migrations)"
	@echo "make seed     — charge le jeu d'essai (JAMAIS en production : il vide la carte)"
	@echo "make seed-suspects — jeu d'essai « saboteurs », pour l'écran Terminaux à contre-courant (même avertissement)"
	@echo "make test     — joue les tests SQL des règles de modération (§6)"
	@echo "make psql     — ouvre un shell SQL"
	@echo "make admin-add EMAIL=… — crée un administrateur et imprime son jeton (§4.3)"
	@echo "make icons-default EMAIL=… — remet les silhouettes par défaut des types, au nom de cet administrateur"
	@echo "make studio   — démarre Supabase Studio sur http://127.0.0.1:3000"
	@echo "make tiles    — télécharge l'extrait PMTiles Île-de-France"
	@echo "make downloads — compte les téléchargements de l'APK, comme l'onglet Téléchargements de la console"
	@echo "make blocked  — compte les refus de la limitation de débit, par zone et par jour"
	@echo "make reset    — DÉTRUIT le volume de données et repart de zéro"

# `admin` en fait partie : sans lui, Caddy répond 502 sur ADMIN_DOMAIN. `tileserver` aussi, dès
# que le fond de carte est là (make tiles) : sans lui, les dangers s'affichent sur une carte
# blanche, Caddy répondant 502 sur /tiles/basemap. C'est ce que fait déjà deploy/install-vps.sh.
up:
	$(COMPOSE) --profile tiles up -d --build db rest admin caddy $$([ -f tiles/data/basemap.pmtiles ] && echo tileserver)
	@echo "API : https://$${SITE_DOMAIN:-localhost}/rest/v1/"
	@echo "Console : https://$${ADMIN_DOMAIN:-admin.localhost}/ (en local : http://127.0.0.1:8081/)"

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

# db/migrate.sh : chaque fichier une fois, dans sa transaction avec son inscription au
# registre `schema_migrations` ; le premier échec arrête tout. Recharge PostgREST à la fin.
migrate:
	$(COMPOSE) exec -T db /db/migrate.sh

seed:
	@read -p "Vider la carte et charger le jeu d'essai ? [oui/non] " a; [ "$$a" = "oui" ]
	$(COMPOSE) exec -T db psql -v ON_ERROR_STOP=1 -U "$${POSTGRES_USER:-postgres}" -d "$${POSTGRES_DB:-app}" -f /db/seed-demo.sql

# Une journée de bêta avec deux saboteurs, pour l'écran « Terminaux, à contre-courant ».
seed-suspects:
	@read -p "Vider la carte et charger le jeu d'essai « saboteurs » ? [oui/non] " a; [ "$$a" = "oui" ]
	$(COMPOSE) exec -T db psql -v ON_ERROR_STOP=1 -U "$${POSTGRES_USER:-postgres}" -d "$${POSTGRES_DB:-app}" -f /db/seed-suspects.sql

test:
	$(COMPOSE) exec -T db /db/run-tests.sh

psql:
	$(COMPOSE) exec db psql -U "$${POSTGRES_USER:-postgres}" -d "$${POSTGRES_DB:-app}"

admin-add:
	@test -n "$(EMAIL)" || (echo "usage : make admin-add EMAIL=moderation@example.org" && exit 1)
	@./admin-token.sh "$(EMAIL)"

# Revenir aux silhouettes par défaut des types (db/icons/, rendues par db/icons/render.py depuis
# les glyphes de l'app). Elles sont posées d'office par la migration 0160 ; cette cible sert
# après un téléversement raté : elle remplace ce qui est là, au nom d'un administrateur, par la
# RPC de l'écran Types et dans le journal d'audit.
icons-default:
	@test -n "$(EMAIL)" || (echo "usage : make icons-default EMAIL=moderation@example.org" && exit 1)
	$(COMPOSE) exec -T db psql -v ON_ERROR_STOP=1 -U "$${POSTGRES_USER:-postgres}" -d "$${POSTGRES_DB:-app}" -v email="$(EMAIL)" -f /db/icons/load.sql

studio:
	$(COMPOSE) --profile admin up -d meta studio
	@echo "Studio : http://127.0.0.1:3000 (jamais exposé publiquement, §7)"

tiles:
	./tiles/fetch-pmtiles.sh

# Le journal des téléchargements (caddy/Caddyfile, `log apk`) : une ligne par requête servie
# sur un APK — heure, fichier, code, taille, langue du navigateur, jamais d'adresse. Le
# journal est dans le volume de Caddy ; le rapport est fait ici, sur l'hôte (downloads.py).
downloads:
	@$(COMPOSE) exec -T caddy sh -c 'cat /var/log/caddy/downloads*.log 2>/dev/null' | python3 ./downloads.py

# Ce que la limitation de débit a refusé (caddy/Caddyfile, `log blocked`) : par zone, par jour.
blocked:
	@$(COMPOSE) exec -T caddy sh -c 'cat /var/log/caddy/blocked*.log 2>/dev/null' | python3 ./downloads.py --blocked

reset:
	@read -p "Détruire toutes les données locales ? [oui/non] " a; [ "$$a" = "oui" ]
	$(COMPOSE) down -v
