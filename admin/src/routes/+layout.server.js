/** L'identité reconnue par la base, pour l'en-tête. Vide sur /login, où le hook ne la pose pas.
 *  @type {import('./$types').LayoutServerLoad} */
export function load({ locals }) {
	return { email: locals.admin?.email ?? '' };
}
