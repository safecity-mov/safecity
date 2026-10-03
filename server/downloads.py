#!/usr/bin/env python3
"""L'application — lit le journal des téléchargements de l'APK (caddy/Caddyfile, `log apk`).

Appelé par `make downloads`, qui lui passe le journal sur l'entrée standard. Une ligne par
requête servie sur un APK : heure UTC, fichier, code, taille, langue du navigateur. Jamais
d'adresse IP — elle n'est pas dans le fichier, ce script n'a donc rien à en faire.

Un téléchargement complet répond 200 ; un 206 est une reprise par morceaux du même fichier,
comptée à part pour ne pas gonfler le total. Avec `--blocked`, lit le journal des blocages de la limitation de débit (`log blocked`) :
l'heure, le chemin, le code 429, rien d'autre — combien de refus, par jour et par zone, sans
savoir si c'est une adresse ou cent. Appelé par `make blocked`. Licence : AGPL-3.0.
"""
import collections
import datetime
import json
import sys
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
DERNIERS = 40
BLOCAGES = "--blocked" in sys.argv[1:]


def zone(chemin):
    """Quelle limite a joué : l'API ou les fichiers APK (voir caddy/Caddyfile, `rate_limit`)."""
    if chemin.startswith("/rest/"):
        return "API"
    if chemin.endswith(".apk"):
        return "APK"
    return "autre"


def langue(brute):
    """« fr-FR,fr;q=0.9,en;q=0.8 » → « fr-FR ». Vide si le navigateur ne dit rien."""
    if not brute:
        return "—"
    return brute.split(",")[0].split(";")[0].strip() or "—"


def heure_locale(ts):
    if not ts:
        return "        ?    "
    try:
        moment = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return "        ?    "
    return moment.astimezone(PARIS).strftime("%d/%m %H:%M")


lignes = []
for brute in sys.stdin:
    brute = brute.strip()
    if not brute:
        continue
    try:
        entree = json.loads(brute)
    except ValueError:
        continue
    requete = entree.get("request", {})
    if not BLOCAGES and requete.get("method") != "GET":
        continue
    lignes.append(
        {
            "quand": entree.get("ts"),
            "chemin": requete.get("uri", "").split("?")[0],
            "fichier": requete.get("uri", "").split("?")[0].rsplit("/", 1)[-1],
            "code": entree.get("status"),
            "langue": langue(entree.get("lang")),
        }
    )

if BLOCAGES:
    refus = [l for l in lignes if l["code"] == 429]
    if not refus:
        print("aucun blocage pour l'instant")
        sys.exit(0)
    print("Blocages par zone")
    for z, n in sorted(collections.Counter(zone(l["chemin"]) for l in refus).items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {z}")
    print(f"  {len(refus):5d}  au total")
    print("\nPar jour (heure de Paris)")
    par_jour = collections.Counter(heure_locale(l["quand"])[:5] for l in refus)
    for jour, n in sorted(par_jour.items(), key=lambda kv: kv[0][3:5] + kv[0][0:2]):
        print(f"  {n:5d}  {jour}")
    print(f"\nLes {min(DERNIERS, len(refus))} derniers")
    for l in refus[-DERNIERS:]:
        print(f"  {heure_locale(l['quand'])}  {zone(l['chemin']):<6}  {l['chemin']}")
    sys.exit(0)

complets = [l for l in lignes if l["code"] == 200]
reprises = collections.Counter(l["fichier"] for l in lignes if l["code"] == 206)

if not lignes:
    print("aucun téléchargement pour l'instant")
    sys.exit(0)

print("Par fichier")
par_fichier = collections.Counter(l["fichier"] for l in complets)
for fichier, n in sorted(par_fichier.items(), key=lambda kv: -kv[1]):
    suffixe = f"   (+{reprises[fichier]} reprises)" if reprises[fichier] else ""
    print(f"  {n:5d}  {fichier}{suffixe}")
print(f"  {len(complets):5d}  au total")

print("\nPar langue du navigateur")
for lang, n in sorted(collections.Counter(l["langue"] for l in complets).items(), key=lambda kv: -kv[1]):
    print(f"  {n:5d}  {lang}")

print("\nPar jour (heure de Paris)")
par_jour = collections.Counter()
for l in complets:
    par_jour[heure_locale(l["quand"])[:5]] += 1
for jour, n in sorted(par_jour.items(), key=lambda kv: kv[0][3:5] + kv[0][0:2]):
    print(f"  {n:5d}  {jour}")

print(f"\nLes {min(DERNIERS, len(complets))} derniers")
for l in complets[-DERNIERS:]:
    print(f"  {heure_locale(l['quand'])}  {l['langue']:<8}  {l['fichier']}")
