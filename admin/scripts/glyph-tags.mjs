#!/usr/bin/env node
/**
 * L'application — mots-clés des glyphes Material Symbols, pour la recherche de l'écran Types.
 *
 * Le nom d'un glyphe ne dit pas tout : « vehicle » n'apparaît dans aucun nom, alors que Google
 * en propose des dizaines, parce que sa page cherche aussi dans des mots-clés et une catégorie
 * par icône. Ce script télécharge ces métadonnées une fois, ne garde que les glyphes que la
 * console connaît (ceux de `@material-symbols/font-400`) et écrit `src/lib/glyph-tags.json` :
 * nom → mots-clés, en anglais comme les noms.
 *
 * Le fichier est commité, comme les PNG de `server/db/icons/render.py` : la console ne contacte
 * jamais Google à l'exécution. À relancer quand le paquet `@material-symbols/*` change de
 * version (`npm run glyph-tags`), et commiter le résultat avec la montée de version.
 */
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');

// `incomplete=true` inclut les glyphes dont tous les styles ne sont pas encore publiés ; le
// paquet npm, lui, les a. Sans ce paramètre il en manquerait quelques dizaines.
const SOURCE = 'https://fonts.google.com/metadata/icons?key=material_symbols&incomplete=true';

const dts = await readFile(join(root, 'node_modules/@material-symbols/font-400/index.d.ts'), 'utf8');
const names = [...dts.matchAll(/"([a-z0-9_]+)"/g)].map((m) => m[1]);
const known = new Set(names);

const response = await fetch(SOURCE);
if (!response.ok) throw new Error(`${SOURCE} : ${response.status}`);
// Google préfixe son JSON d'un garde anti-XSSI, « )]}' », à retirer.
const { icons } = JSON.parse((await response.text()).replace(/^\)\]\}'\s*/, ''));

// Les mots-clés de Google sont bavards (« travel time », « vehicle icon », « transport
// symbol ») : on les réduit à des mots simples, sans le bruit qui n'aide personne à chercher,
// sinon le fichier pèse plus d'un mégaoctet.
const NOISE = new Set(['icon', 'icons', 'symbol', 'symbols', 'and', 'the', 'with', 'for', 'of']);

/** @type {Map<string, Set<string>>} */
const tags = new Map();
for (const icon of icons) {
	if (!known.has(icon.name)) continue;
	// Le même nom revient une fois par famille : on réunit les mots-clés.
	const set = tags.get(icon.name) ?? new Set();
	const own = new Set(icon.name.split('_'));
	for (const phrase of [...(icon.tags ?? []), ...(icon.categories ?? [])]) {
		for (const w of String(phrase).toLowerCase().split(/[^a-z0-9]+/)) {
			// Un mot déjà dans le nom n'apporte rien : la recherche regarde aussi le nom.
			if (w.length >= 3 && !NOISE.has(w) && !own.has(w) && !icon.name.includes(w)) set.add(w);
		}
	}
	tags.set(icon.name, set);
}

/** @type {Record<string, string>} */
const out = {};
for (const name of names) {
	const set = tags.get(name);
	if (set?.size) out[name] = [...set].sort().join(' ');
}
const file = join(root, 'src/lib/glyph-tags.json');
await writeFile(file, JSON.stringify(out));

const missing = names.filter((n) => !tags.has(n));
console.log(`${Object.keys(out).length} glyphes avec mots-clés sur ${names.length}, ${missing.length} absents des métadonnées`);
if (missing.length) console.log('absents :', missing.slice(0, 20).join(' '), missing.length > 20 ? '…' : '');
console.log(`${file} : ${(await readFile(file)).length} o`);
