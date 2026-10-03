/**
 * Le journal des téléchargements de l'APK (server/caddy/Caddyfile, `log apk`), lu et compté
 * comme le fait `make downloads` (server/downloads.py) : les deux doivent dire la même chose.
 *
 * Une ligne JSON par requête servie sur un fichier .apk : heure UTC, méthode, chemin, code,
 * taille, langue annoncée par le navigateur. Jamais d'adresse IP — elle n'est pas dans le
 * fichier, il n'y a donc rien à en retirer ici.
 *
 * Un téléchargement complet répond 200 ; un 206 est une reprise par morceaux du même fichier,
 * comptée à part pour ne pas gonfler le total.
 */

const TZ = 'Europe/Paris';
export const LAST = 40;

/** « fr-FR,fr;q=0.9,en;q=0.8 » → « fr-FR ». Un tiret si le navigateur ne dit rien.
 *  @param {string | undefined} raw */
export const language = (raw) => (raw ?? '').split(',')[0].split(';')[0].trim() || '—';

/** @typedef {{ when: Date | null, file: string, code: number, language: string }} Hit */

/**
 * @param {string} text le contenu d'un ou plusieurs fichiers de journal, concaténés
 * @returns {Hit[]}
 */
export function parse(text) {
	/** @type {Hit[]} */
	const hits = [];
	for (const raw of text.split('\n')) {
		const line = raw.trim();
		if (!line) continue;
		/** @type {any} */
		let entry;
		try {
			entry = JSON.parse(line);
		} catch {
			continue;
		}
		const request = entry.request ?? {};
		if (request.method !== 'GET') continue;
		const when = entry.ts ? new Date(entry.ts) : null;
		hits.push({
			when: when && !Number.isNaN(when.getTime()) ? when : null,
			file: String(request.uri ?? '').split('?')[0].split('/').pop() ?? '',
			code: Number(entry.status),
			language: language(entry.lang)
		});
	}
	return hits;
}

/** @param {Date | null} d */
const dayOf = (d) =>
	d ? d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', timeZone: TZ }) : '?';
/** @param {Date | null} d */
export const timeOf = (d) =>
	d
		? d.toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: TZ })
		: '?';

/** Compte les valeurs d'une clé, rendu trié par nombre décroissant.
 *  @template T @param {T[]} items @param {(item: T) => string} key */
function tally(items, key) {
	/** @type {Map<string, number>} */
	const counts = new Map();
	for (const item of items) counts.set(key(item), (counts.get(key(item)) ?? 0) + 1);
	return [...counts.entries()].map(([label, n]) => ({ label, n }));
}

/**
 * Les mêmes quatre tableaux que `make downloads`.
 * @param {Hit[]} hits
 */
export function report(hits) {
	const complete = hits.filter((h) => h.code === 200);
	const resumed = tally(hits.filter((h) => h.code === 206), (h) => h.file);
	const resumedByFile = Object.fromEntries(resumed.map((r) => [r.label, r.n]));

	const byFile = tally(complete, (h) => h.file)
		.sort((a, b) => b.n - a.n)
		.map((row) => ({ ...row, resumed: resumedByFile[row.label] ?? 0 }));
	const byLanguage = tally(complete, (h) => h.language).sort((a, b) => b.n - a.n);
	// Par jour, dans l'ordre du calendrier : la clé jj/mm se trie sur mm puis jj.
	const byDay = tally(complete, (h) => dayOf(h.when)).sort((a, b) =>
		(a.label.slice(3, 5) + a.label.slice(0, 2)).localeCompare(b.label.slice(3, 5) + b.label.slice(0, 2))
	);
	const last = complete.slice(-LAST).reverse();

	return { total: complete.length, byFile, byLanguage, byDay, last };
}

/** Quelle limite a joué (server/caddy/Caddyfile, `rate_limit`). @param {string} path */
export const zone = (path) => (path.startsWith('/rest/') ? 'API' : path.endsWith('.apk') ? 'APK' : 'autre');

/** @typedef {{ when: Date | null, path: string, code: number }} Refusal */

/**
 * Le journal des blocages (`log blocked`) : une ligne par 429 de la limitation de débit,
 * l'heure, le chemin, rien d'autre.
 * @param {string} text
 * @returns {Refusal[]}
 */
export function parseBlocked(text) {
	/** @type {Refusal[]} */
	const refusals = [];
	for (const raw of text.split('\n')) {
		const line = raw.trim();
		if (!line) continue;
		/** @type {any} */
		let entry;
		try {
			entry = JSON.parse(line);
		} catch {
			continue;
		}
		if (Number(entry.status) !== 429) continue;
		const when = entry.ts ? new Date(entry.ts) : null;
		refusals.push({
			when: when && !Number.isNaN(when.getTime()) ? when : null,
			path: String(entry.request?.uri ?? '').split('?')[0],
			code: 429
		});
	}
	return refusals;
}

/** @param {Refusal[]} refusals */
export function blockedReport(refusals) {
	const byZone = tally(refusals, (r) => zone(r.path)).sort((a, b) => b.n - a.n);
	const byDay = tally(refusals, (r) => dayOf(r.when)).sort((a, b) =>
		(a.label.slice(3, 5) + a.label.slice(0, 2)).localeCompare(b.label.slice(3, 5) + b.label.slice(0, 2))
	);
	const last = refusals.slice(-LAST).reverse();
	return { total: refusals.length, byZone, byDay, last };
}
