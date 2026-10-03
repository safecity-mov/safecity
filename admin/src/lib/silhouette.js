/**
 * Dessine un glyphe Material Symbols en silhouette PNG, dans le navigateur.
 *
 * C'est `server/db/icons/render.py` transposé sur un canevas : blanc sur transparent,
 * 128 × 128, centré sur la boîte réelle du glyphe et non sur sa boîte nominale, parce que les
 * icônes Material n'ont pas toutes la même hauteur. Le fichier produit passe ensuite par
 * `admin_set_hazard_icon`, avec les mêmes contrôles qu'un PNG téléversé à la main.
 *
 * On part du tracé SVG servi par la console, pas de la police : le canevas ne sait pas régler
 * l'axe `FILL` d'une police variable, et le tracé donne un rendu vectoriel net à n'importe
 * quelle taille.
 */
import { glyphUrl } from '$lib/glyphs.js';

/** Même côté que les silhouettes par défaut : quelques centaines d'octets, bien au-dessous des 64 Ko. */
const SIDE = 128;

/** Les SVG du paquet sont dessinés sur une grille de 960 unités, d'ordonnée −960 à 0. */
const EM = 960;

/**
 * @param {string} name le nom du glyphe
 * @param {import('$lib/glyphs.js').GlyphStyle} style plein ou contour
 * @returns {Promise<string>} le PNG en base64, sans préfixe `data:`
 */
export async function renderSilhouette(name, style) {
	const response = await fetch(glyphUrl(name, style));
	// Un cookie expiré renvoie vers /login : ce n'est pas un dessin, et le dire vaut mieux
	// qu'un « introuvable » qui enverrait chercher du mauvais côté.
	if (response.redirected) throw new Error('Session expirée : reconnectez-vous.');
	if (!response.ok) throw new Error(`Le dessin de « ${name} » est introuvable.`);
	const paths = [...(await response.text()).matchAll(/\sd="([^"]+)"/g)].map((m) => m[1]);
	if (paths.length === 0) throw new Error(`Le dessin de « ${name} » est vide.`);

	const work = canvas();
	const ctx = context(work);
	ctx.setTransform(SIDE / EM, 0, 0, SIDE / EM, 0, SIDE);
	for (const d of paths) ctx.fill(new Path2D(d));

	// La boîte réelle, pixel par pixel : c'est `textbbox` dans render.py.
	const { data } = ctx.getImageData(0, 0, SIDE, SIDE);
	let left = SIDE, top = SIDE, right = -1, bottom = -1;
	for (let y = 0; y < SIDE; y++) {
		for (let x = 0; x < SIDE; x++) {
			if (data[(y * SIDE + x) * 4 + 3] === 0) continue;
			if (x < left) left = x;
			if (x > right) right = x;
			if (y < top) top = y;
			if (y > bottom) bottom = y;
		}
	}
	if (right < 0) throw new Error(`Le dessin de « ${name} » est vide.`);

	// Recopié au pixel près pour le centrer, puis repeint en blanc par le seul canal alpha.
	const out = canvas();
	const octx = context(out);
	octx.drawImage(
		work,
		Math.round((SIDE - (right - left + 1)) / 2 - left),
		Math.round((SIDE - (bottom - top + 1)) / 2 - top)
	);
	octx.globalCompositeOperation = 'source-in';
	octx.fillStyle = '#fff';
	octx.fillRect(0, 0, SIDE, SIDE);

	return out.toDataURL('image/png').split(',')[1];
}

function canvas() {
	const c = document.createElement('canvas');
	c.width = SIDE;
	c.height = SIDE;
	return c;
}

/** @param {HTMLCanvasElement} c */
function context(c) {
	const ctx = c.getContext('2d');
	if (!ctx) throw new Error('Le navigateur ne sait pas dessiner sur un canevas.');
	return ctx;
}
