import { readdir, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { env } from '$env/dynamic/private';
import { blockedReport, parse, parseBlocked, report } from '$lib/downloads.js';

/**
 * L'onglet Téléchargements : ce que `make downloads` imprime, depuis le même journal. Le
 * dossier est un volume de Caddy monté en lecture seule dans ce conteneur
 * (server/docker-compose.yml, `caddy_logs`). Le fichier courant et les anciens de la
 * rotation, dans l'ordre où ils ont été écrits.
 *
 * Pas d'appel à PostgREST ici : le journal ne passe pas par la base, et n'a pas à y passer.
 * La page reste réservée aux administrateurs par le hook, comme toutes les autres.
 * @type {import('./$types').PageServerLoad}
 */
export async function load() {
	const dir = env.DOWNLOADS_LOG_DIR ?? '/var/log/caddy';
	const [downloads, blocked] = await Promise.all([
		concat(dir, /^downloads.*\.log$/),
		concat(dir, /^blocked.*\.log$/)
	]);
	return {
		report: report(parse(downloads.text)),
		blocked: blockedReport(parseBlocked(blocked.text)),
		files: downloads.files + blocked.files
	};
}

/**
 * Le contenu des fichiers d'un journal, du plus ancien au plus récent.
 * @param {string} dir @param {RegExp} pattern
 */
async function concat(dir, pattern) {
	/** @type {{ name: string, mtime: number }[]} */
	let files = [];
	try {
		const names = (await readdir(dir)).filter((/** @type {string} */ n) => pattern.test(n));
		files = await Promise.all(
			names.map(async (/** @type {string} */ name) => ({
				name,
				mtime: (await stat(join(dir, name))).mtimeMs
			}))
		);
	} catch {
		// Dossier absent : aucun journal encore, ou console lancée hors de Docker. Même
		// écran qu'un journal vide, sans erreur — il n'y a rien à corriger côté console.
		return { text: '', files: 0 };
	}
	files.sort((a, b) => a.mtime - b.mtime);
	const texts = await Promise.all(files.map((f) => readFile(join(dir, f.name), 'utf8')));
	return { text: texts.join('\n'), files: files.length };
}
