/**
 * Base64 sans `Buffer` : les deux fonctions dont la console a besoin, sur les primitives que
 * Node et le navigateur partagent. Évite de tirer les définitions de types de Node pour deux
 * appels, et garde `svelte-check` au vert.
 */

/** @param {Uint8Array} bytes */
export function toBase64(bytes) {
	let binary = '';
	// Par tranches : `String.fromCharCode(...bytes)` sur 64 Ko d'arguments dépasse la pile.
	for (let i = 0; i < bytes.length; i += 0x8000) {
		binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
	}
	return btoa(binary);
}

/** @param {string} b64 */
export function fromBase64(b64) {
	const binary = atob(b64);
	const bytes = new Uint8Array(binary.length);
	for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
	return bytes;
}
