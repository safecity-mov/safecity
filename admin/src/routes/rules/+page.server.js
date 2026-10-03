import { api, ApiError, requireInteger } from '$lib/api.js';
import { attempt } from '$lib/actions.js';
import { logout } from '$lib/actions.js';

/**
 * Les seuils de résolution du §6.1. Une seule ligne en base, les mêmes règles pour tous les
 * types : c'est une règle de modération, pas une propriété d'un nid-de-poule.
 *
 * C'est le seul écran qui change le comportement de l'app sans rien changer aux données. D'où
 * l'insistance des explications : un modérateur doit pouvoir prévoir l'effet de son réglage
 * avant de l'écrire, pas le découvrir sur la carte.
 *
 * Comme le catalogue, la table s'écrit directement et un trigger journalise chaque écriture
 * dans `admin_actions` (§4.3).
 * @type {import('./$types').PageServerLoad}
 */
export async function load({ locals }) {
	const [rows, tiers] = await Promise.all([
		api(locals.token, '/moderation_settings?limit=1'),
		api(locals.token, '/proximity_tiers?order=tier')
	]);
	if (!rows[0]) {
		throw new ApiError('Les seuils de modération sont introuvables en base.', 500);
	}
	return { rules: rows[0], tiers };
}

export const actions = {
	logout,

	/** @param {import('@sveltejs/kit').RequestEvent} event */
	save: async ({ request, locals }) => {
		const form = await request.formData();
		return attempt(async () => {
			const patch = {
				min_resolve_votes: requireInteger(form.get('min_resolve_votes'), 'Votes minimum', 1, 10),
				confirmations_per_resolve_vote: requireInteger(
					form.get('confirmations_per_resolve_vote'),
					'Confirmations par voix',
					1,
					100
				),
				max_resolve_votes: requireInteger(form.get('max_resolve_votes'), 'Votes maximum', 1, 20),
				report_confirmations: requireInteger(
					form.get('report_confirmations'),
					'Un signalement vaut',
					1,
					10
				),
				// Une case à cocher absente du formulaire vaut « décochée » : c'est bien « coupée ».
				descriptions_enabled: form.get('descriptions_enabled') === 'on'
			};
			// La base le refuse aussi (CHECK), mais son message parlerait de contrainte violée.
			if (patch.max_resolve_votes < patch.min_resolve_votes) {
				throw new ApiError('Le plafond de votes ne peut pas être sous le plancher.', 400);
			}

			// `return=representation` : sans lui, un PATCH qui ne touche aucune ligne réussit en
			// silence. Ici, il n'y a qu'une ligne — autant savoir si elle est bien là.
			const rows = await api(locals.token, '/moderation_settings?id=eq.1', {
				method: 'PATCH',
				headers: { Prefer: 'return=representation' },
				body: JSON.stringify(patch)
			});
			if (!rows[0]) {
				throw new ApiError('Aucun réglage enregistré : la ligne est introuvable.', 404);
			}
			return {
				message: patch.descriptions_enabled
					? 'Seuils enregistrés. Ils valent pour tous les types.'
					: 'Seuils enregistrés, précision libre coupée : le serveur ne garde plus aucun texte ' +
						'sur les nouveaux signalements, masque ceux qui existent, et les applications ' +
						'retirent le champ à leur prochain retour au premier plan.'
			};
		});
	},

	/**
	 * Les deux paliers de proximité du §6.2 (0200) : « sur place » jusqu'à une distance, et
	 * « ailleurs ». Les deux lignes partent ensemble, par l'upsert de PostgREST : séparées, elles
	 * passeraient par un état où le geste lointain pèse plus que le proche, et la base le
	 * refuserait — à juste titre.
	 * @param {import('@sveltejs/kit').RequestEvent} event
	 */
	saveTiers: async ({ request, locals }) => {
		const form = await request.formData();
		return attempt(async () => {
			const proche = requireInteger(form.get('tier1_m'), 'Sur place, jusqu’à', 1, 100000);
			const poids = [1, 2].map((tier) =>
				requireWeight(form.get(`tier${tier}_w`), `Poids du palier ${tier}`)
			);

			if (poids[0] < poids[1]) {
				throw new ApiError('Un geste émis d’ailleurs ne peut pas peser plus lourd que sur place.', 400);
			}

			await api(locals.token, '/proximity_tiers', {
				method: 'POST',
				headers: { Prefer: 'resolution=merge-duplicates' },
				body: JSON.stringify([
					{ tier: 1, max_distance_m: proche, weight: poids[0] },
					{ tier: 2, max_distance_m: null, weight: poids[1] }
				])
			});
			return {
				message:
					'Paliers enregistrés. Les applications déjà ouvertes appliqueront la nouvelle règle ' +
					'à leur prochain démarrage.'
			};
		});
	}
};

/**
 * Un poids entre 0 et 1, avec quatre décimales au plus : de quoi écrire un tiers (0,3333) sans
 * que trois gestes d'ailleurs retombent à 0,99. `requireInteger` ne convient pas, et
 * `Number('')` vaut 0 — que la base refuserait, mais avec son propre vocabulaire.
 * @param {FormDataEntryValue | null} value
 * @param {string} label
 */
function requireWeight(value, label) {
	const n = Number(String(value ?? '').trim().replace(',', '.'));
	if (!Number.isFinite(n) || n <= 0 || n > 1) {
		throw new ApiError(`« ${label} » doit être un poids entre 0 et 1.`, 400);
	}
	return Math.round(n * 10000) / 10000;
}
