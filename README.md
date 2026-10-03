# L'application

Signalement collaboratif des dangers de la route en ville, à commencer par les nids-de-poule.
Pilote parisien. Sans compte, sans analytics, sans dépendance propriétaire, auto-hébergé.

**[SPEC.md](SPEC.md) est la source de vérité.** Le cadrage est clos ; les décisions sont
récapitulées en §17.

## Où en est le projet

Phase 1, **bêta fermée** (§4.6). Feuille de route en §14.

| Semaines | Livrable | État |
|---|---|---|
| 1–2 | Schéma Postgres, fonctions RPC, Docker Compose, tests SQL, PMTiles servi | fait |
| 3–5 | App Flutter : carte, catalogue, créer, confirmer, résolu, détail | fait |
| 6 | Hors-ligne, paramètres, instrumentation locale des mesures | fait |
| — | Console d'administration : retirer, bannir, catalogue (§4.3 avancé) | fait |
| 7 | Build Android sans dépendance propriétaire, dépôt F-Droid, déploiement VPS | outillé, pas encore déployé |
| 8+ | Bêta fermée sur les axes visés | à venir |

## Structure

```
SPEC.md          la spécification, source de vérité : les décisions et leur pourquoi
ARCHITECTURE.md  le système tel qu'il tourne : qui parle à qui, et ce qui ne circule jamais
PRIVACY.md       la politique de confidentialité, dont l'app embarque une version courte et la longue
server/      PostgreSQL + PostGIS, PostgREST, Caddy — AGPL-3.0
app/         Flutter, Android — Apache-2.0
admin/       console de modération, SvelteKit — AGPL-3.0
deploy/      installation du VPS et publication de l'app — AGPL-3.0
```

Démarrer le serveur : voir [server/README.md](server/README.md).
Lancer l'app : voir [app/README.md](app/README.md).
Modérer : voir [admin/README.md](admin/README.md).
Mettre en ligne : voir [deploy/README.md](deploy/README.md).

L'app se distribue par un **dépôt F-Droid auto-hébergé** sur le VPS, à côté de l'API et du
fond de carte (§12.6) : les testeurs l'ajoutent une fois et reçoivent les mises à jour sans
rien faire. L'APK reste téléchargeable à la main sur `https://<domaine>/apk`.

## Licences

| Composant | Licence | Pourquoi |
|---|---|---|
| Serveur, et plus tard les surfaces web | **AGPL-3.0** | Seul endroit où la clause réseau a un sens (§12.1) |
| App Flutter | **Apache-2.0** | L'AGPL bloquerait une publication iOS ultérieure (§12.2) |
| Données | **ODbL 1.0** | La valeur réelle du projet, compatible OSM |

Cartographie © OpenStreetMap contributors.

## Contribuer

Pseudonymes bienvenus. **Ni CLA ni DCO** : le DCO exige un « real name », s'en passer garde
le dépôt ouvert aux pseudonymes (§12.7). Contrepartie assumée : la licence du dépôt est
définitive (§12.4).
