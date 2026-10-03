/**
 * Actions partagées entre la liste et la carte : c'est le même geste de modération, il ne doit
 * pas exister en deux exemplaires. Une divergence entre les deux écrans finirait par produire
 * deux règles là où le §4.3 n'en veut qu'une.
 */
import { fail, redirect } from '@sveltejs/kit';
import { api, ApiError, COOKIE, requireReason, rpc } from '$lib/api.js';
import { count, statusFilter, statusLabel } from '$lib/format.js';
import { pageOf, pageQuery } from '$lib/paging.js';

/**
 * Le motif « essayer, rendre un message, ou échouer proprement » que chaque action répète.
 *
 * Un échec porte `error: true` : c'est ce que les pages lisent pour colorer le message. Elles
 * lisaient `form.status`, qu'aucune action ne renvoie — SvelteKit ne transmet que `data` —
 * et toute erreur s'affichait donc comme un succès.
 * @param {() => Promise<{ message: string }>} fn
 */
export async function attempt(fn) {
	try {
		return await fn();
	} catch (error) {
		return fail(error instanceof ApiError ? error.status : 500, {
			message: error instanceof Error ? error.message : 'Échec.',
			error: true
		});
	}
}

/** Retirer ou rétablir. Les deux passent par la même fonction : c'est le même geste.
 *  @param {import('@sveltejs/kit').RequestEvent} event */
export async function moderate({ request, locals }) {
	const form = await request.formData();
	return attempt(async () => {
		const result = await rpc(locals.token, 'admin_set_hazard_removed', {
			id: form.get('id'),
			removed: form.get('removed') === 'true',
			reason: requireReason(form.get('reason'))
		});
		return {
			message: `Danger ${statusLabel(result.status_before)} → ${statusLabel(result.status_after)}.`
		};
	});
}

/**
 * Effacer la « précision », le texte libre d'un danger, sans toucher au danger : une insulte
 * ou un nom sur un nid-de-poule bien réel ne justifie pas de retirer le nid-de-poule. Le texte
 * effacé reste dans le journal d'audit, avec le motif.
 * @param {import('@sveltejs/kit').RequestEvent} event
 */
export async function clearDescription({ request, locals }) {
	const form = await request.formData();
	return attempt(async () => {
		await rpc(locals.token, 'admin_clear_hazard_description', {
			id: form.get('id'),
			reason: requireReason(form.get('reason'))
		});
		return { message: 'Précision effacée. Le danger reste tel quel.' };
	});
}

/**
 * Bannir l'auteur d'un danger, sans jamais recevoir son identifiant (§11).
 *
 * La console envoie le danger, le serveur remonte à l'auteur et le sanctionne. Elle apprend
 * combien de gestes ont été annulés, jamais qui. Un écran qui afficherait le terminal derrière
 * chaque signalement permettrait, de proche en proche, de redessiner les trajets d'une personne.
 * @param {import('@sveltejs/kit').RequestEvent} event
 */
export async function banAuthor({ request, locals }) {
	const form = await request.formData();
	return attempt(async () => {
		const result = await rpc(locals.token, 'admin_ban_hazard_author', {
			hazard_id: form.get('hazard'),
			reason: requireReason(form.get('reason'))
		});
		return {
			message:
				`Auteur banni : ${count(result.events_cancelled, 'geste annulé', 'gestes annulés')}, ` +
				`${count(result.hazards_removed, 'signalement retiré', 'signalements retirés')}.`
		};
	});
}

/** @param {import('@sveltejs/kit').RequestEvent} event */
export async function logout({ cookies }) {
	cookies.delete(COOKIE, { path: '/' });
	redirect(303, '/login');
}

/**
 * Les dangers, du plus récent au plus ancien, tous statuts confondus : modérer suppose de voir
 * ce qui est déjà masqué, sinon on ne peut pas le rétablir. Partagé par la liste et la carte,
 * qui ne diffèrent que par la taille de page.
 * @param {import('@sveltejs/kit').RequestEvent} event
 * @param {number} limit
 */
export async function loadHazards({ locals, url }, limit) {
	const status = statusFilter(url);
	const page = pageOf(url);
	const { query, slice } = pageQuery(page, limit);
	const filter = status ? `&status=eq.${status}` : '';
	const { rows, hasMore } = slice(
		await api(locals.token, `/admin_hazards?order=created_at.desc&${query}${filter}`)
	);
	return { hazards: rows, status, page, hasMore, limit };
}
