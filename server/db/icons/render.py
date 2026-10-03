#!/usr/bin/env python3
"""L'application — rend en PNG les glyphes Material que l'app dessine par défaut.

L'app connaît un glyphe par type (`HazardType.icon`, app/lib/src/data/models/hazard_type.dart) ;
la console, elle, n'affiche qu'un tiret tant que le catalogue n'a pas de silhouette. Ce script
produit les silhouettes correspondantes, et deux façons de les mettre dans le catalogue :

  - la migration 0160, écrite ici avec les PNG en base64 : posée au premier démarrage comme le
    sont les types eux-mêmes (0020), sans administrateur ni commande. Elle ne touche pas à un
    type dont un administrateur a déjà réglé l'icône, téléversée ou retirée ;
  - `make icons-default EMAIL=…`, qui rejoue les mêmes fichiers par la RPC d'administration,
    au nom d'un admin et dans le journal d'audit : pour revenir aux glyphes d'origine.

Silhouette au sens de la base (0090) : seul le canal alpha compte, la couleur est repeinte au
rendu. Ici blanc sur transparent, 128 × 128, quelques centaines d'octets.

Usage : python3 server/db/icons/render.py   (Flutter installé : la police est dans son cache)
Après un changement de glyphe dans l'app, relancer, et commiter PNG et migration ensemble.

Pour un type ajouté depuis la console, rien de tout cela : l'écran Types fait le même dessin
dans le navigateur (admin/src/lib/silhouette.js), à partir des tracés Material Symbols qu'il
embarque. Deux familles cohabitent donc : Material Icons, la classique, pour les sept glyphes
codés dans l'app et rendus ici ; Material Symbols, qui lui a succédé, pour les types créés en
console.
"""
import base64
import pathlib
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

# Le même tableau que `HazardType.icon`, avec les codepoints de `Icons` (Flutter).
GLYPHS = {
    "pothole": 0xEF9E,   # Icons.dangerous_outlined
    "slippery": 0xE6D3,  # Icons.waves
    "manhole": 0xEF53,   # Icons.circle_outlined
    "debris": 0xE2E4,    # Icons.grass
    "curb": 0xE5F8,      # Icons.stairs
    "works": 0xE189,     # Icons.construction
    "lighting": 0xE37C,  # Icons.lightbulb_outline
}
SIDE = 128

here = pathlib.Path(__file__).resolve().parent
flutter = shutil.which("flutter")
if flutter is None:
    raise SystemExit("flutter introuvable : la police MaterialIcons-Regular.otf vient de son cache")
sdk = pathlib.Path(subprocess.check_output(["readlink", "-f", flutter], text=True).strip()).parents[1]
font = ImageFont.truetype(str(sdk / "bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf"), SIDE)

for code, cp in GLYPHS.items():
    image = Image.new("RGBA", (SIDE, SIDE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    glyph = chr(cp)
    # Centré sur la boîte réelle du glyphe, pas sur sa ligne de base : les icônes Material
    # n'ont pas toutes la même hauteur.
    left, top, right, bottom = draw.textbbox((0, 0), glyph, font=font)
    draw.text(((SIDE - (right - left)) / 2 - left, (SIDE - (bottom - top)) / 2 - top),
              glyph, font=font, fill=(255, 255, 255, 255))
    out = here / f"{code}.png"
    image.save(out, optimize=True)
    print(f"{out.name:14} {out.stat().st_size} o")

# La migration : mêmes octets, rejouable. `ON CONFLICT DO NOTHING` protège une icône
# téléversée ; le test sur le journal protège un retrait volontaire — sans lui, l'installation,
# qui rejoue toutes les migrations, remettrait le glyphe qu'un administrateur a enlevé.
lines = [
    "-- L'application — 0160 : silhouettes par défaut des types de danger.",
    "--",
    "-- ÉCRIT PAR db/icons/render.py, ne pas éditer à la main : ce sont les glyphes Material que",
    "-- l'app dessine elle-même, rendus en PNG pour que la console montre la même chose (0090).",
    "-- Posées comme les types (0020) : au premier démarrage, sans administrateur. Un type dont",
    "-- l'icône a déjà été téléversée ou retirée depuis la console n'est pas touché.",
    "INSERT INTO hazard_type_icons (type_code, png)",
    "SELECT d.code, decode(d.png_b64, 'base64')",
    "  FROM (VALUES",
]
rows = []
for code in GLYPHS:
    b64 = base64.b64encode((here / f"{code}.png").read_bytes()).decode()
    rows.append(f"    ('{code}', '{b64}')")
lines.append(",\n".join(rows))
lines += [
    "  ) AS d(code, png_b64)",
    "  JOIN hazard_types t ON t.code = d.code",
    " WHERE NOT EXISTS (SELECT 1 FROM admin_actions a",
    "                    WHERE a.action IN ('type.icon.set', 'type.icon.clear') AND a.target = d.code)",
    "ON CONFLICT ON CONSTRAINT hazard_type_icons_pkey DO NOTHING;",
    "",
    "NOTIFY pgrst, 'reload schema';",
    "",
]
migration = here.parent / "migrations" / "0160_default_icons.sql"
migration.write_text("\n".join(lines))
print(f"{migration.name}  {migration.stat().st_size} o")
