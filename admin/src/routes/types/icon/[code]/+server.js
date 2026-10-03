import { error } from '@sveltejs/kit';
import { api } from '$lib/api.js';
import { fromBase64 } from '$lib/base64.js';

/**
 * Sert les octets d'une icône, pour l'aperçu de l'écran Types.
 *
 * Le détour par ce serveur n'est pas une complication gratuite : le navigateur ne peut pas
 * appeler PostgREST directement sans jeton, et le jeton ne doit pas quitter le cookie
 * `httpOnly`. La page demande donc l'image ici, et c'est ce serveur qui va la chercher.
 * @type {import('./$types').RequestHandler}
 */
export async function GET({ params, locals }) {
	const rows = await api(
		locals.token,
		`/hazard_type_icons_public?type_code=eq.${encodeURIComponent(params.code)}&select=png_b64`
	);
	if (!rows?.length) error(404, 'aucune icône pour ce type');

	return new Response(fromBase64(rows[0].png_b64), {
		headers: {
			'Content-Type': 'image/png',
			// L'URL porte déjà `updated_at` : une icône remplacée change d'adresse, donc le
			// cache long n'affiche jamais une image périmée.
			'Cache-Control': 'private, max-age=31536000, immutable'
		}
	});
}
