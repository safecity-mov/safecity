import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { error } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import { NAME_RE, isGlyph } from '$lib/glyphs.js';

/**
 * Sert le tracé SVG d'un glyphe Material Symbols, pour que le navigateur le peigne en
 * silhouette (lib/silhouette.js).
 *
 * Les tracés sont lus dans le paquet `@material-symbols/svg-400` à l'exécution plutôt
 * qu'empaquetés : près de huit mille fichiers pour la seule famille Outlined, dont un ou deux
 * servent par choix d'icône. Le paquet est une dépendance d'exécution pour cette raison, et
 * le Dockerfile n'en garde que `outlined/`. `GLYPH_DIR` permet de le ranger ailleurs.
 *
 * Comme tout ici, la route est derrière le cookie d'administration : aucune ressource de la
 * console n'est publique, même un dessin.
 */
const DIR = env.GLYPH_DIR ?? join(process.cwd(), 'node_modules/@material-symbols/svg-400/outlined');

/** @type {import('./$types').RequestHandler} */
export async function GET({ params, url }) {
	// La regex seule interdit déjà tout séparateur de chemin ; l'appartenance à la liste
	// refuse en plus un nom plausible qui ne serait pas un glyphe.
	if (!NAME_RE.test(params.name) || !isGlyph(params.name, 'outlined')) {
		error(404, 'glyphe inconnu');
	}
	const fill = url.searchParams.get('fill') === '1';

	/** @type {string} */
	let svg;
	try {
		svg = await readFile(join(DIR, `${params.name}${fill ? '-fill' : ''}.svg`), 'utf8');
	} catch (e) {
		// Nom dans la liste de la police mais sans fichier : les deux paquets sont à la même
		// version, ça ne devrait pas arriver, et si ça arrive le sélecteur affiche le message.
		if (e instanceof Error && 'code' in e && e.code === 'ENOENT') error(404, 'aucun dessin pour ce glyphe');
		throw e;
	}

	return new Response(svg, {
		headers: {
			'Content-Type': 'image/svg+xml',
			'X-Content-Type-Options': 'nosniff',
			// Un SVG ouvert directement est un document : qu'il ne puisse rien charger.
			'Content-Security-Policy': "default-src 'none'"
			// Pas de Cache-Control : Caddy sert toute la console en `no-store`
			// (server/caddy/Caddyfile), et un tracé pèse quelques centaines d'octets.
		}
	});
}
