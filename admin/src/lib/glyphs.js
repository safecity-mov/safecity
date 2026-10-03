/**
 * Les glyphes Material Symbols que la console propose comme icône de type (SPEC §4.3 amendé).
 *
 * Tout vient de deux paquets du même générateur, à la même version, Apache-2.0, servis par
 * cette origine : `@material-symbols/font-400` pour la liste des noms et la police qui dessine
 * la grille, `@material-symbols/svg-400` pour les tracés que le navigateur peint en
 * silhouette (voir silhouette.js et routes/types/glyph). La console ne contacte jamais Google,
 * pas plus qu'un autre domaine tiers.
 *
 * Material Symbols est la famille qui a succédé à Material Icons, celle dont viennent les sept
 * glyphes codés dans l'app (`server/db/icons/render.py`). Plein et contour n'y sont plus deux
 * polices mais un axe `FILL` ; on n'embarque que la famille Outlined, les variantes arrondie et
 * anguleuse ne se distinguant pas sur une pastille de 20 px.
 */
import dts from '@material-symbols/font-400/index.d.ts?raw';

/** @typedef {'filled' | 'outlined'} GlyphStyle */

/**
 * Le suffixe suit la convention de la famille et du paquet Flutter `material_symbols_icons` :
 * le contour est la forme par défaut (`Symbols.name`), le plein n'est pas un autre glyphe mais
 * le même avec `fill: 1` — d'où `name` et `name_fill`, comme `name.svg` et `name-fill.svg`.
 * @type {Record<GlyphStyle, { label: string, fill: 0 | 1, suffix: string }>}
 */
export const STYLES = {
	filled: { label: 'Plein', fill: 1, suffix: '_fill' },
	outlined: { label: 'Contour', fill: 0, suffix: '' }
};

/** Un nom de glyphe : minuscules, chiffres, soulignés. Rien qui puisse former un chemin. */
export const NAME_RE = /^[a-z0-9_]+$/;

/** Les noms officiels, dans l'ordre du paquet, lus dans sa déclaration de types. */
export const NAMES = [...dts.matchAll(/"([a-z0-9_]+)"/g)].map((m) => m[1]);
const KNOWN = new Set(NAMES);

/** Vrai pour un nom et un style que la console connaît. Vérifié côté serveur avant d'écrire. */
export const isGlyph = (/** @type {string} */ name, /** @type {string} */ style) =>
	style in STYLES && KNOWN.has(name);

/**
 * Le nom tel qu'il est écrit dans `hazard_types.icon` pour un type créé depuis la console :
 * `dangerous`, `waves_fill`. L'app n'en fait rien ; il dit à un développeur quel glyphe
 * embarquer si un jour il fallait un repli.
 * @param {string} name @param {GlyphStyle} style
 */
export const iconName = (name, style) => `${name}${STYLES[style].suffix}`;

/** Où la console sert le tracé SVG d'un glyphe (routes/types/glyph/[name]). */
export const glyphUrl = (/** @type {string} */ name, /** @type {GlyphStyle} */ style) =>
	`/types/glyph/${name}?fill=${STYLES[style].fill}`;
