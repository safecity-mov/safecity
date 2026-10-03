/**
 * Pagination par `?page=`. Une ligne de plus que la page est demandée : si elle arrive, il y
 * a une suite. Pas de comptage exact — il coûterait une requête de plus pour un chiffre que
 * personne ne lit.
 */

/** @param {URL} url */
export function pageOf(url) {
	const n = Number(url.searchParams.get('page') ?? '1');
	return Number.isInteger(n) && n >= 1 ? n : 1;
}

/**
 * Le fragment de requête PostgREST pour une page, et de quoi lire la réponse.
 * @param {number} page
 * @param {number} limit
 */
export function pageQuery(page, limit) {
	return {
		query: `limit=${limit + 1}&offset=${(page - 1) * limit}`,
		/** @template T @param {T[]} rows */
		slice: (rows) => ({ rows: rows.slice(0, limit), hasMore: rows.length > limit })
	};
}

/**
 * Un lien vers une autre page, en gardant les autres filtres de l'URL.
 * @param {URL} url
 * @param {number} page
 */
export function pageHref(url, page) {
	const params = new URLSearchParams(url.searchParams);
	if (page <= 1) params.delete('page');
	else params.set('page', String(page));
	const qs = params.toString();
	return `${url.pathname}${qs ? `?${qs}` : ''}`;
}
