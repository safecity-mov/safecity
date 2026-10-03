/**
 * Accès à PostgREST, **toujours côté serveur**.
 *
 * Le jeton d'administration ne touche jamais le navigateur : il vit dans un cookie `httpOnly`
 * que seul ce serveur lit, et les appels partent d'ici. Une console qui mettrait le jeton dans
 * du JavaScript l'exposerait à la moindre extension, au moindre copier-coller de la console du
 * navigateur, et à tout ce qui saurait lire `localStorage`.
 *
 * Conséquence assumée : chaque geste est un aller-retour serveur, et la console n'a aucune
 * interactivité côté client. Pour trois écrans de modération, c'est le bon échange.
 */
import { env } from '$env/dynamic/private';

const BASE = env.APP_API ?? 'http://rest:3000';

/** Nom du cookie de session. Une seule valeur, fixée ici, jamais construite dynamiquement. */
export const COOKIE = 'sc_admin';

/**
 * Au-delà, on préfère dire « le serveur ne répond pas » que laisser la page tourner : un
 * `FOR UPDATE` tenu ailleurs bloquerait sinon la requête jusqu'à l'expiration de Node.
 */
const TIMEOUT_MS = 10_000;

/**
 * @param {string} token
 * @param {string} path chemin PostgREST, par exemple `/admin_hazards?order=created_at.desc`
 * @param {RequestInit} [options]
 * @returns {Promise<any>}
 */
export async function api(token, path, options = {}) {
	/** @type {Response} */
	let response;
	try {
		response = await fetch(`${BASE}${path}`, {
			...options,
			signal: AbortSignal.timeout(TIMEOUT_MS),
			headers: {
				Authorization: `Bearer ${token}`,
				'Content-Type': 'application/json',
				...(options.headers ?? {})
			}
		});
	} catch (cause) {
		// PostgREST arrêté, réseau interne coupé, délai dépassé : ce n'est pas une réponse,
		// donc pas un message SQL à transmettre. « fetch failed » ne dit rien à personne.
		throw new ApiError('Le serveur ne répond pas. Réessayez dans un instant.', 503, {
			code: 'UNREACHABLE',
			cause
		});
	}

	const text = await response.text();
	if (!response.ok) throw ApiError.fromResponse(response.status, text);
	return text ? JSON.parse(text) : null;
}

/** @param {string} token @param {string} fn @param {Record<string, unknown>} body */
export const rpc = (token, fn, body) =>
	api(token, `/rpc/${fn}`, { method: 'POST', body: JSON.stringify(body) });

/**
 * Ce que PostgREST rend quand ce n'est pas nous qui avons écrit le message. Les exceptions
 * levées par nos fonctions SQL sont déjà en français et lisibles (§8) : les réécrire ferait
 * diverger deux formulations de la même règle. On ne traduit donc que les messages de
 * PostgreSQL et de PostgREST eux-mêmes, reconnus à leur formulation anglaise.
 * @type {Array<[RegExp, string]>}
 */
const TRANSLATIONS = [
	[/^JWT|^JWS|jwt|expired|No suitable key/i, 'Jeton refusé.'],
	[/^Could not find the function/, 'Fonction inconnue de l’API : la base et la console ne sont pas à la même version.'],
	[/^duplicate key value/, 'Cette valeur existe déjà.'],
	[/^invalid input syntax/, 'Valeur mal formée.'],
	[/out of range/, 'Nombre hors bornes.'],
	[/^null value in column/, 'Un champ obligatoire est vide.'],
	[/violates check constraint/, 'Valeur hors des bornes autorisées.'],
	[/violates foreign key constraint/, 'Cette référence n’existe pas.'],
	[/^permission denied/, 'Accès refusé.'],
	[/does not exist$/, 'Cette ressource n’existe pas.']
];

export class ApiError extends Error {
	/**
	 * @param {string} message
	 * @param {number} status
	 * @param {{ code?: string, cause?: unknown }} [extra]
	 */
	constructor(message, status, extra = {}) {
		super(message, extra.cause === undefined ? undefined : { cause: extra.cause });
		this.status = status;
		this.code = extra.code ?? null;
	}

	/** Vrai quand le jeton lui-même est en cause : à traiter comme une déconnexion. */
	get isAuth() {
		return this.status === 401 || this.status === 403;
	}

	/**
	 * @param {number} status
	 * @param {string} text corps de la réponse, JSON PostgREST `{code, message, details, hint}` en général
	 */
	static fromResponse(status, text) {
		let message = `Erreur ${status}`;
		/** @type {string | undefined} */
		let code;
		try {
			const body = JSON.parse(text);
			if (typeof body?.message === 'string' && body.message) message = body.message;
			if (typeof body?.code === 'string') code = body.code;
		} catch {
			/* corps non JSON : on garde le code HTTP */
		}
		if (status === 401 || status === 403) {
			// Un 401 de PostgREST est toujours le jeton ; un 403 vient de `current_admin()`,
			// dont le message est déjà en français. On traduit le premier, on garde le second.
			if (status === 401) message = 'Jeton refusé.';
		}
		const translation = TRANSLATIONS.find(([pattern]) => pattern.test(message));
		if (translation && !/[éèêàçù]/.test(message)) message = translation[1];
		return new ApiError(message, status, { code });
	}
}

/**
 * Un motif est obligatoire pour toute action (§4.3), et le serveur le refuse déjà. On le
 * vérifie aussi ici pour rendre un message utile plutôt qu'une erreur SQL.
 * @param {FormDataEntryValue | null} value
 */
export function requireReason(value) {
	const reason = String(value ?? '').trim();
	if (reason.length < 3) {
		throw new ApiError('Indiquez un motif : il est inscrit au journal d’audit.', 400);
	}
	return reason;
}

/**
 * Un entier borné, tel que le catalogue l'exige. `Number('')` vaut 0 et `Number('abc')` vaut
 * NaN : ni l'un ni l'autre ne doit atteindre la base.
 * @param {FormDataEntryValue | null} value
 * @param {string} label ce qu'on dira s'il manque
 * @param {number} min
 * @param {number} max
 */
export function requireInteger(value, label, min, max) {
	const n = Number(String(value ?? '').trim());
	if (!Number.isInteger(n) || n < min || n > max) {
		throw new ApiError(`« ${label} » doit être un entier entre ${min} et ${max}.`, 400);
	}
	return n;
}
