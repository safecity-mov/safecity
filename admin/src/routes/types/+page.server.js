import { fail } from '@sveltejs/kit';
import { api, ApiError, requireInteger, rpc } from '$lib/api.js';
import { attempt } from '$lib/actions.js';
import { toBase64 } from '$lib/base64.js';
import { iconName, isGlyph } from '$lib/glyphs.js';

/** 64 Ko, comme la contrainte en base. Vérifié ici aussi pour ne pas transporter pour rien. */
const MAX_BYTES = 65536;

/** « 209 o » plutôt que « 0 Ko » : une silhouette bien faite pèse quelques centaines d'octets. */
const size = (/** @type {number} */ bytes) =>
	bytes < 1024 ? `${bytes} o` : `${Math.round(bytes / 1024)} Ko`;

/** @param {FormDataEntryValue | null} value */
const text = (value) => String(value ?? '').trim();

/**
 * Un glyphe Material Symbols choisi dans la console, dessiné par le navigateur : son nom, son
 * style et le PNG qui en résulte. Le nom et le style sont vérifiés contre la liste du paquet —
 * c'est ce qui finit dans `hazard_types.icon` et dans le message — et le PNG est confié à la
 * base, qui le valide comme n'importe quel fichier téléversé.
 * @param {FormData} form
 */
function glyphOf(form) {
	const name = text(form.get('glyph'));
	const style = text(form.get('glyph_style'));
	const png = text(form.get('png_base64'));
	if (!name && !png) return null;
	if (!isGlyph(name, style)) throw new ApiError(`Glyphe inconnu : « ${name} ».`, 400);
	// 64 Ko d'octets font 88 Ko de base64 ; au-delà, inutile d'aller jusqu'à la base.
	if (!png || png.length > Math.ceil(MAX_BYTES / 3) * 4) {
		throw new ApiError('Le dessin du glyphe est absent ou trop lourd.', 400);
	}
	return { name, style: /** @type {import('$lib/glyphs.js').GlyphStyle} */ (style), png };
}

/**
 * Le catalogue pilote l'interface de l'app (§3) : ce qu'on écrit ici apparaît chez tout le
 * monde au prochain lancement. D'où l'édition ligne par ligne plutôt qu'un formulaire unique —
 * on voit ce qu'on change.
 *
 * Chaque écriture est journalisée par un trigger côté base : pas de motif à saisir, mais rien
 * ne passe inaperçu. Les bornes sont vérifiées ici pour un message immédiat, et en `CHECK`
 * côté base pour que la règle ne dépende pas de qui écrit.
 * @type {import('./$types').PageServerLoad}
 */
export async function load({ locals }) {
	const [types, icons] = await Promise.all([
		api(locals.token, '/hazard_types?order=sort_order'),
		api(locals.token, '/hazard_type_icons_public?select=type_code,width,updated_at')
	]);
	// Indexées par type : la page en a besoin ligne par ligne, pas en liste.
	const byType = Object.fromEntries(
		icons.map((/** @type {{ type_code: string }} */ i) => [i.type_code, i])
	);
	return { types, icons: byType };
}

export const actions = {
	/** @param {import('@sveltejs/kit').RequestEvent} event */
	save: async ({ request, locals }) => {
		const form = await request.formData();
		const code = text(form.get('code'));
		return attempt(async () => {
			const patch = {
				label_fr: text(form.get('label_fr')),
				resolved_label_fr: text(form.get('resolved_label_fr')),
				icon: text(form.get('icon')) || code,
				default_ttl_days: requireInteger(form.get('default_ttl_days'), 'Expire après', 1, 3650),
				dedup_radius_m: requireInteger(form.get('dedup_radius_m'), 'Rayon anti-doublon', 1, 500),
				// L'ordre d'apparition dans l'app, les plus petits en premier (hazard_types.sort_order).
				sort_order: requireInteger(form.get('sort_order'), 'Ordre', 0, 9999),
				enabled: form.get('enabled') === 'on'
			};
			if (!patch.label_fr || !patch.resolved_label_fr) {
				throw new ApiError('Le libellé et le verbe de résolution sont obligatoires.', 400);
			}
			// `return=representation` : sans lui, un PATCH qui ne touche aucune ligne réussit
			// en silence. On veut savoir si le type existe encore.
			const rows = await api(locals.token, `/hazard_types?code=eq.${encodeURIComponent(code)}`, {
				method: 'PATCH',
				headers: { Prefer: 'return=representation' },
				body: JSON.stringify(patch)
			});
			if (!Array.isArray(rows) || rows.length === 0) {
				throw new ApiError(`Le type « ${code} » n’existe plus.`, 404);
			}
			return { message: `« ${patch.label_fr} » enregistré.` };
		});
	},

	/**
	 * Téléverser une silhouette. Le fichier est relu en base64 et confié à la base, qui le
	 * valide : signature PNG, carré, dimensions, poids. Les deux contrôles faits ici ne sont
	 * là que pour rendre un message immédiat — la règle qui compte est celle du serveur.
	 * @param {import('@sveltejs/kit').RequestEvent} event
	 */
	upload: async ({ request, locals }) => {
		const form = await request.formData();
		const code = text(form.get('code'));
		const file = form.get('png');

		if (!(file instanceof File) || file.size === 0) {
			return fail(400, { message: 'Choisissez un fichier PNG.', error: true });
		}
		if (file.size > MAX_BYTES) {
			return fail(400, {
				message: `Fichier trop lourd : ${size(file.size)} pour 64 Ko au plus.`,
				error: true
			});
		}

		return attempt(async () => {
			const bytes = new Uint8Array(await file.arrayBuffer());
			const result = await rpc(locals.token, 'admin_set_hazard_icon', {
				type_code: code,
				png_base64: toBase64(bytes)
			});
			return {
				message: `Icône de « ${code} » remplacée : ${result.width} px, ${size(result.bytes)}.`
			};
		});
	},

	/** @param {import('@sveltejs/kit').RequestEvent} event */
	clearIcon: async ({ request, locals }) => {
		const form = await request.formData();
		const code = text(form.get('code'));
		return attempt(async () => {
			await rpc(locals.token, 'admin_clear_hazard_icon', { type_code: code });
			return { message: `Icône de « ${code} » retirée : le glyphe embarqué reprend la main.` };
		});
	},

	/**
	 * Poser un glyphe Material Symbols choisi dans la grille sur un type existant. Même RPC, mêmes
	 * contrôles et même ligne d'audit qu'un PNG téléversé : pour la base, c'est une silhouette
	 * comme une autre, elle a seulement été dessinée par le navigateur plutôt qu'à la main.
	 * @param {import('@sveltejs/kit').RequestEvent} event
	 */
	glyph: async ({ request, locals }) => {
		const form = await request.formData();
		const code = text(form.get('code'));
		return attempt(async () => {
			const glyph = glyphOf(form);
			if (!glyph) throw new ApiError('Choisissez un glyphe.', 400);
			const result = await rpc(locals.token, 'admin_set_hazard_icon', {
				type_code: code,
				png_base64: glyph.png
			});
			return {
				message:
					`Icône de « ${code} » remplacée par le glyphe « ${iconName(glyph.name, glyph.style)} » : ` +
					`${result.width} px, ${size(result.bytes)}.`
			};
		});
	},

	/** @param {import('@sveltejs/kit').RequestEvent} event */
	create: async ({ request, locals }) => {
		const form = await request.formData();
		const code = text(form.get('code'));
		if (!/^[a-z_]{3,30}$/.test(code)) {
			return fail(400, {
				message: 'Le code doit être en minuscules sans accent : « broken_glass ».',
				error: true
			});
		}
		return attempt(async () => {
			const label = text(form.get('label_fr'));
			if (!label) throw new ApiError('Le libellé est obligatoire.', 400);
			// Vérifié avant d'insérer : un glyphe refusé ne doit pas laisser un type à moitié créé.
			const glyph = glyphOf(form);
			await api(locals.token, '/hazard_types', {
				method: 'POST',
				body: JSON.stringify({
					code,
					label_fr: label,
					// Le nom du glyphe de repli. L'app n'en connaît que sept, codés en dur : pour
					// un type nouveau il donne le triangle générique, et seule la silhouette
					// téléversée compte. Le nom Material Symbols choisi y est écrit quand même,
					// `dangerous` ou `waves_fill` : il dit à un développeur quel glyphe embarquer
					// (`Symbols.waves`, `fill: 1`) si un jour il fallait un repli.
					icon: glyph ? iconName(glyph.name, glyph.style) : code,
					resolved_label_fr: text(form.get('resolved_label_fr')) || 'Résolu',
					default_ttl_days: 60,
					dedup_radius_m: 15,
					// Un type naît désactivé : l'app le dessine mais ne propose pas de le
					// signaler (§4.3). On l'active quand ses libellés sont relus.
					enabled: false,
					sort_order: 99
				})
			});
			if (!glyph) {
				return {
					message: `« ${code} » créé, désactivé et sans icône. Relisez ses libellés avant de l'activer.`
				};
			}
			// Deux écritures, deux lignes d'audit : la création par le trigger, l'icône par la
			// RPC. Si la seconde échoue, le type existe — on le dit, plutôt que de laisser
			// croire que rien ne s'est passé.
			try {
				await rpc(locals.token, 'admin_set_hazard_icon', { type_code: code, png_base64: glyph.png });
			} catch (e) {
				throw new ApiError(
					`« ${code} » créé, mais son icône a été refusée : ${e instanceof Error ? e.message : 'échec'}`,
					e instanceof ApiError ? e.status : 500
				);
			}
			return { message: `« ${code} » créé, désactivé, avec l'icône « ${iconName(glyph.name, glyph.style)} ». Relisez ses libellés avant de l'activer.` };
		});
	}
};
