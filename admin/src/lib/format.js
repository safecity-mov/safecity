/**
 * Libellés et formats partagés entre les écrans. Une seule définition : la liste et la carte
 * disaient « signalé résolu » chacune de leur côté, et l'audit ne libellait pas les icônes.
 */

/** Statuts d'un danger (§5), tels qu'on les lit à l'écran.
 *  @type {Record<string, string>} */
export const STATUS_LABELS = {
	active: 'actif',
	disputed: 'signalé résolu',
	resolved: 'résolu',
	removed: 'retiré',
	archived: 'archivé'
};

/** Couleurs des statuts sur la carte. @type {Record<string, string>} */
export const STATUS_COLORS = {
	active: '#a4161a',
	disputed: '#e07a00',
	resolved: '#2a8a4a',
	removed: '#8a8f97',
	archived: '#c8cdd4'
};

/**
 * Actions du journal d'audit (§4.3).
 *
 * `device.unban` n'est plus produit : le déblocage a été retiré. Son libellé reste, parce que
 * le journal est en écriture seule et peut porter des lignes antérieures à cette décision.
 * @type {Record<string, string>}
 */
export const ACTION_LABELS = {
	'hazard.remove': 'danger retiré',
	'hazard.restore': 'danger rétabli',
	'hazard.description.clear': 'précision effacée',
	'device.ban': 'terminal bloqué',
	'device.unban': 'terminal débloqué',
	'type.insert': 'type créé',
	'type.update': 'type modifié',
	'type.delete': 'type supprimé',
	'type.icon.set': 'icône téléversée',
	'type.icon.clear': 'icône retirée',
	'rules.update': 'seuils réglés',
	'tiers.update': 'paliers de proximité réglés',
	'announcement.publish': 'annonce publiée',
	'announcement.withdraw': 'annonce retirée'
};

/** États d'une annonce (0230), tels que la vue `admin_announcements` les calcule.
 *  @type {Record<string, string>} */
export const ANNOUNCEMENT_STATES = {
	active: 'en cours',
	scheduled: 'programmée',
	expired: 'terminée',
	withdrawn: 'retirée'
};

/** @param {string} status */
export const statusLabel = (status) => STATUS_LABELS[status] ?? status;

/**
 * Un filtre de statut lu dans l'URL : une valeur connue, ou rien. `?status=foo` donnait une
 * erreur 500 (enum invalide côté base) là où il faut simplement ne pas filtrer.
 * @param {URL} url
 */
export const statusFilter = (url) => {
	const value = url.searchParams.get('status') ?? '';
	return value in STATUS_LABELS ? value : '';
};

/** Fuseau des modérateurs, fixé : le rendu côté serveur ne dépend pas du `TZ` du conteneur. */
const TZ = 'Europe/Paris';

/** @param {string} iso */
export const shortDate = (iso) =>
	new Date(iso).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short', timeZone: TZ });

/** @param {string} iso */
export const longDate = (iso) =>
	new Date(iso).toLocaleString('fr-FR', { dateStyle: 'medium', timeStyle: 'medium', timeZone: TZ });

/** « 3 gestes », « 1 geste ». @param {number} n @param {string} singular @param {string} [plural] */
export const count = (n, singular, plural = `${singular}s`) => `${n} ${n > 1 ? plural : singular}`;
