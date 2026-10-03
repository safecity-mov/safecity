import { redirect } from '@sveltejs/kit';
import { ApiError, COOKIE, rpc } from '$lib/api.js';

/**
 * Deux règles.
 *
 * Sans jeton en cookie, on ne voit rien d'autre que l'écran de connexion.
 *
 * Avec un jeton, il est **vérifié en base à chaque requête** : `admin_whoami()` échoue si le
 * `sub` n'est plus un administrateur actif, ou si le secret JWT a changé. Le cookie est alors
 * supprimé et l'on revient à la connexion. Sans cela, un administrateur désactivé — ou un jeton
 * qui a fui, puisqu'il n'expire pas — continuait de lire les dangers, les terminaux et le
 * journal d'audit ; seules les actions échouaient. Un aller-retour de plus par page, pour
 * trois personnes : c'est le bon prix.
 *
 * @type {import('@sveltejs/kit').Handle}
 */
export async function handle({ event, resolve }) {
	const token = event.cookies.get(COOKIE);
	const onLogin = event.url.pathname === '/login';

	if (!token) {
		if (!onLogin) redirect(303, '/login');
		return secured(await resolve(event));
	}

	/** @type {{ user_id: string, email: string } | null} */
	let admin = null;
	try {
		admin = await rpc(token, 'admin_whoami', {});
	} catch (error) {
		if (!(error instanceof ApiError && error.isAuth)) throw error;
	}

	if (!admin) {
		event.cookies.delete(COOKIE, { path: '/' });
		if (!onLogin) redirect(303, '/login?reason=revoked');
		return secured(await resolve(event));
	}

	if (onLogin) redirect(303, '/');
	event.locals.token = token;
	event.locals.admin = admin;
	return secured(await resolve(event));
}

/**
 * Ce qui arrive dans un `load` et que personne n'a attrapé : le serveur qui ne répond pas,
 * typiquement. Le message d'`ApiError` est déjà lisible ; le reste ne doit rien dire de plus.
 * @type {import('@sveltejs/kit').HandleServerError}
 */
export function handleError({ error }) {
	return {
		message: error instanceof ApiError ? error.message : 'Erreur inattendue.'
	};
}

/** @param {Response} response */
function secured(response) {
	// Une console de modération n'a rien à faire dans un cadre, ni dans un index.
	response.headers.set('X-Frame-Options', 'DENY');
	// `same-origin` et non `no-referrer`, et ce n'est pas un relâchement : Chrome soumet aussi
	// l'en-tête `Origin` des soumissions de formulaire à cette politique. Sous `no-referrer` il
	// envoie `Origin: null`, que SvelteKit rejette en « Cross-site POST form submissions are
	// forbidden » — la console devient inutilisable. `same-origin` ne transmet rien vers
	// l'extérieur, ce qui était le but : aucun identifiant de danger ni de terminal ne sort.
	response.headers.set('Referrer-Policy', 'same-origin');
	return response;
}
