# L'application — console d'administration (SPEC §4.3).
# Deux étages : on construit avec toute la chaîne npm, on n'embarque que le résultat.
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# Les tracés Material Symbols sont lus à l'exécution (src/routes/types/glyph) : seule la
# famille Outlined sert, les deux autres sont retirées de l'image.
RUN npm run build && npm prune --omit=dev \
 && rm -rf node_modules/@material-symbols/svg-400/rounded node_modules/@material-symbols/svg-400/sharp

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/build ./build
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
# Jamais en root : la console parle à PostgREST, elle n'a besoin de rien d'autre.
USER node
EXPOSE 3000
CMD ["node", "build/index.js"]
