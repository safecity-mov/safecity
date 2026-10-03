import { banAuthor, clearDescription, loadHazards, logout, moderate } from '$lib/actions.js';
import { api } from '$lib/api.js';

/**
 * Écran « Recherche et carte » du §4.3 : retrouver un danger par zone, et agir dessus à l'unité.
 *
 * Tout est chargé d'un coup plutôt que par cadre de vue. À l'échelle de la bêta c'est quelques
 * dizaines de points ; recharger à chaque déplacement coûterait un aller-retour par geste de
 * souris pour rien. `LIMIT` borne la casse, et l'écran dit quand il tronque plutôt que de
 * laisser croire à une carte complète.
 */
const LIMIT = 2000;

/**
 * Avec les dangers, le catalogue et ses silhouettes : la carte dessine les mêmes marqueurs
 * que l'app — icône du type, diamètre selon la gravité, creux quand le danger est contesté —
 * à ceci près que la couleur dit ici le statut, ce qui est ce qu'un modérateur regarde.
 * @type {import('./$types').PageServerLoad}
 */
export async function load(event) {
	const [page, types, icons] = await Promise.all([
		loadHazards(event, LIMIT),
		api(event.locals.token, '/hazard_types?select=code,label_fr&order=sort_order'),
		api(event.locals.token, '/hazard_type_icons_public?select=type_code,updated_at')
	]);
	const byCode = Object.fromEntries(
		types.map((/** @type {{ code: string, label_fr: string }} */ t) => [t.code, t])
	);
	const iconByCode = Object.fromEntries(
		icons.map((/** @type {{ type_code: string, updated_at: string }} */ i) => [i.type_code, i.updated_at])
	);
	return { ...page, types: byCode, icons: iconByCode };
}

export const actions = { moderate, clearDescription, banAuthor, logout };
