import { api, ApiError, requireReason, rpc } from '$lib/api.js';
import { attempt, logout } from '$lib/actions.js';

/**
 * Une annonce aux personnes qui utilisent l'app (§4.3 amendé, 0230).
 *
 * Une ligne, une date de fin, un motif : l'app l'affiche en bandeau au lancement et au retour
 * au premier plan, comme l'avis de nouvelle version. Elle ne se modifie pas après coup — on la
 * retire et on en publie une autre — et le journal garde ce qui a été dit, jusqu'à quand, et
 * pourquoi.
 */

/** Combien de temps l'annonce reste, au choix. Une heure par défaut : le bandeau prend la
 *  place de l'avis de version et se voit à chaque ouverture, une annonce qui traîne pollue.
 *  Qui veut plus long le choisit. */
const DURATIONS = [
	{ hours: 1, label: '1 heure' },
	{ hours: 6, label: '6 heures' },
	{ hours: 24, label: '1 jour' },
	{ hours: 72, label: '3 jours' },
	{ hours: 168, label: '7 jours' }
];
const DEFAULT_HOURS = 1;

const MAX_LENGTH = 200;

/** @type {import('./$types').PageServerLoad} */
export async function load({ locals }) {
	const announcements = await api(
		locals.token,
		'/admin_announcements?order=created_at.desc&limit=30'
	);
	return { announcements, durations: DURATIONS, defaultHours: DEFAULT_HOURS, maxLength: MAX_LENGTH };
}

export const actions = {
	logout,

	/** @param {import('@sveltejs/kit').RequestEvent} event */
	publish: async ({ request, locals }) => {
		const form = await request.formData();
		return attempt(async () => {
			const body = String(form.get('body') ?? '').trim();
			if (!body) throw new ApiError('Écrivez le texte de l’annonce.', 400);
			if (body.length > MAX_LENGTH) {
				throw new ApiError(`Le texte dépasse ${MAX_LENGTH} caractères (${body.length}).`, 400);
			}
			const hours = Number(form.get('hours'));
			const duration = DURATIONS.find((d) => d.hours === hours);
			if (!duration) throw new ApiError('Choisissez une durée dans la liste.', 400);
			const endsAt = new Date(Date.now() + hours * 3_600_000).toISOString();

			await rpc(locals.token, 'admin_publish_announcement', {
				body,
				ends_at: endsAt,
				reason: requireReason(form.get('reason'))
			});
			return {
				message:
					`Annonce publiée pour ${duration.label}. ` +
					'Les applications la liront à leur prochain lancement ou retour au premier plan.'
			};
		});
	},

	/** @param {import('@sveltejs/kit').RequestEvent} event */
	withdraw: async ({ request, locals }) => {
		const form = await request.formData();
		return attempt(async () => {
			await rpc(locals.token, 'admin_withdraw_announcement', {
				id: Number(form.get('id')),
				reason: requireReason(form.get('reason'))
			});
			return { message: 'Annonce retirée. Elle disparaît des applications à leur prochaine lecture.' };
		});
	}
};
