# L'application — Caddy avec la limitation de débit (SPEC §6.3 amendé).
#
# L'image officielle n'embarque pas de limiteur de débit : on la reconstruit avec le module de
# Matt Holt, l'auteur de Caddy. Il compte les requêtes par adresse, en mémoire, sur une fenêtre
# glissante, et n'écrit rien : la règle « aucun journal d'accès » (§11) tient.
#
# Deux étages, comme la console : la chaîne Go pour construire, l'image légère pour tourner.
FROM caddy:2-builder-alpine AS build
RUN xcaddy build --with github.com/mholt/caddy-ratelimit

FROM caddy:2-alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy
