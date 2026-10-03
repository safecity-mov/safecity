import { api } from '$lib/api.js';
import { pageOf, pageQuery } from '$lib/paging.js';

const PAGE_SIZE = 200;

/**
 * Le journal d'audit du §4.3, en lecture seule — et il l'est aussi côté base : `admin_api` n'a
 * que le SELECT, et un trigger refuse toute réécriture. Un administrateur qui pourrait effacer
 * ses traces n'aurait pas de traces.
 * @type {import('./$types').PageServerLoad}
 */
export async function load({ locals, url }) {
	const page = pageOf(url);
	const { query, slice } = pageQuery(page, PAGE_SIZE);
	const [rows, admins] = await Promise.all([
		api(locals.token, `/admin_actions?order=created_at.desc&${query}`),
		api(locals.token, '/admins?select=user_id,email')
	]);
	const { rows: actions, hasMore } = slice(rows);
	const byId = Object.fromEntries(
		admins.map((/** @type {{ user_id: string, email: string }} */ a) => [a.user_id, a.email])
	);
	return { actions, byId, page, hasMore, limit: PAGE_SIZE };
}
