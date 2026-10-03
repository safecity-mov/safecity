import { fail, redirect } from '@sveltejs/kit';
import { dev } from '$app/environment';
import { COOKIE, rpc } from '$lib/api.js';

/**
 * Le jeton est l'authentification (§4.3, bêta). Il est délivré à la main sur le serveur par
 * `make admin-add`, collé ici une fois, puis rangé dans un cookie `httpOnly` : le navigateur
 * ne peut plus le lire, et il ne réapparaît jamais à l'écran.
 *
 * Ce n'est pas un vrai système de comptes, et ça ne prétend pas l'être. Trois personnes qui se
 * connaissent, un accès SSH pour obtenir un jeton : c'est proportionné à une bêta fermée, et
 * insuffisant pour l'ouverture, où il faudra des comptes et un second facteur.
 * @type {import('./$types').Actions}
 */
export const actions = {
	default: async ({ request, cookies }) => {
		const form = await request.formData();
		const token = String(form.get('token') ?? '').trim();
		if (!token) return fail(400, { message: 'Collez votre jeton.' });

		// Vérifié contre la base plutôt que décodé ici : c'est `current_admin()` qui fait foi,
		// et un jeton bien formé dont l'administrateur est désactivé doit être refusé. Le hook
		// refera cette vérification à chaque requête.
		try {
			await rpc(token, 'admin_whoami', {});
		} catch (error) {
			return fail(401, { message: 'Jeton refusé. ' + (error instanceof Error ? error.message : '') });
		}

		cookies.set(COOKIE, token, {
			path: '/',
			httpOnly: true,
			sameSite: 'strict',
			secure: !dev,
			maxAge: 60 * 60 * 12
		});
		redirect(303, '/');
	}
};
