import { api, requireReason, rpc } from '$lib/api.js';
import { attempt } from '$lib/actions.js';
import { count } from '$lib/format.js';
import { pageOf, pageQuery } from '$lib/paging.js';

const PAGE_SIZE = 100;

/**
 * Les terminaux bloqués d'abord, puis les plus actifs : c'est là que se trouve un vandale, et
 * c'est la seule chose qu'on puisse dire d'un identifiant sans le relier à ses signalements
 * (§11).
 *
 * Le filtre « bloqués » existe parce qu'un blocage est définitif : il doit rester relisable.
 * Un auteur banni depuis la carte n'a parfois que deux gestes, et sans ce filtre il
 * disparaîtrait sous cent terminaux plus actifs dès le lendemain.
 * @type {import('./$types').PageServerLoad}
 */
export async function load({ locals, url }) {
	const wanted = url.searchParams.get('state');
	const state = wanted === 'banned' || wanted === 'suspects' ? wanted : '';
	const page = pageOf(url);
	const { query, slice } = pageQuery(page, PAGE_SIZE);

	// À contre-courant : les terminaux actifs ces 24 dernières heures, les sauts
	// géographiquement impossibles d'abord (0210), puis les plus souvent contredits par le
	// collectif (0140). Une fonction et non une vue, parce que le calcul compare chaque avis à
	// l'histoire entière du danger et chaque « sur place » au précédent ; elle rend tout d'un
	// coup, la page se découpe ici. Toujours des totaux par identifiant : ni danger, ni
	// position (§4.3 amendé). Les seuils restent ceux de la fonction — 24 heures, 50 km/h à
	// vol d'oiseau : cet écran regarde, il ne règle pas.
	if (state === 'suspects') {
		const all = await rpc(locals.token, 'admin_suspect_devices', {});
		const { rows, hasMore } = slice(all.slice((page - 1) * PAGE_SIZE));
		return { devices: rows, state, page, hasMore, limit: PAGE_SIZE };
	}

	const filter = state ? '&banned_at=not.is.null' : '';
	const { rows, hasMore } = slice(
		await api(
			locals.token,
			`/admin_devices?order=banned_at.desc.nullslast,events_count.desc&${query}${filter}`
		)
	);
	return { devices: rows, state, page, hasMore, limit: PAGE_SIZE };
}

export const actions = {
	/**
	 * Bloquer, et seulement bloquer : il n'y a pas de déblocage (§4.3, décision d'audit).
	 * Il ne rétablissait jamais les signalements retirés, et passé 24 heures il ne remettait
	 * plus aucun geste en jeu non plus, faute de lien. Ce qui reste en cas d'erreur : rétablir
	 * les dangers un par un depuis l'onglet Dangers, et laisser la personne repartir d'un
	 * identifiant neuf depuis son écran Paramètres.
	 * @param {import('@sveltejs/kit').RequestEvent} event
	 */
	ban: async ({ request, locals }) => {
		const form = await request.formData();
		return attempt(async () => {
			const result = await rpc(locals.token, 'admin_ban_device', {
				device_id: form.get('device_id'),
				reason: requireReason(form.get('reason'))
			});
			return {
				message:
					`Terminal bloqué, définitivement. ` +
					`${count(result.events_cancelled, 'geste annulé', 'gestes annulés')}, ` +
					`${count(result.hazards_removed.length, 'signalement retiré', 'signalements retirés')}. ` +
					`Si c'est une erreur, rétablissez-les un par un depuis l'onglet Dangers.`
			};
		});
	}
};
