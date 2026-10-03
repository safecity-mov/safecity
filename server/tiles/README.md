# Fond de carte

Extrait **PMTiles France métropolitaine**, servi statiquement par Caddy sur `/tiles/basemap.pmtiles`
(SPEC §7). Environ 9 Go jusqu'au zoom 15, un seul fichier, aucune dépendance réseau
en dehors du VPS.

```sh
make tiles          # ou ./tiles/fetch-pmtiles.sh 20260913
```

Le fichier produit n'est pas versionné (voir `.gitignore`). Il se régénère à la demande
depuis le build quotidien de Protomaps, lui-même dérivé d'OpenStreetMap.

## Le fichier s'appelle `basemap.pmtiles`, pas `france.pmtiles`

Le serveur de tuiles dérive l'URL du nom de fichier : `basemap.pmtiles` devient
`/tiles/basemap/{z}/{x}/{y}.mvt`. Or le cache disque de MapLibre est **indexé par URL**. Renommer
le fichier parce que l'étendue a changé viderait d'un coup le cache de tous les téléphones, et
hors ligne la carte redeviendrait blanche sous les marqueurs — constaté en passant de `localhost`
à `127.0.0.1`, qui a coûté les 36 tuiles gardées. Le nom dit donc le **rôle**, jamais l'étendue.

`./tiles/fetch-pmtiles.sh [france|idf|BBOX]` change l'étendue sans changer le nom. La France
métropolitaine pèse ~9 Go jusqu'au zoom 15, l'Île-de-France ~300 Mo pour un poste de
développement à l'étroit.

## Deux façons de le servir

| Chemin | Pour qui | Comment |
|---|---|---|
| `/tiles/basemap.pmtiles` | Clients qui lisent le format PMTiles directement, par requêtes de plage d'octets | Servi par Caddy, activé par défaut |
| `/tiles/{z}/{x}/{y}.mvt` | Clients qui attendent des tuiles classiques | `docker compose --profile tiles up -d tileserver` |

MapLibre GL JS lit PMTiles via `pmtiles://`. Côté Flutter, à vérifier en semaine 3 selon ce
que `maplibre_gl` accepte : si le protocole n'est pas supporté, basculer sur le profil
`tiles` ci-dessus. C'est la seule raison d'être de ce second chemin.

## Reste à faire (semaine 3)

- Un style MapLibre servi à côté du PMTiles. Les styles `protomaps-themes-base` sont un
  point de départ ; le style doit pointer vers `/tiles/`, jamais vers un domaine tiers.
- Attribution « © OpenStreetMap contributors » visible en permanence (§12.5).
