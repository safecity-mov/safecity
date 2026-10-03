declare global {
	namespace App {
		interface Locals {
			/** Le jeton d'administration. Posé par hooks.server.js sur toute route sauf /login,
			 *  après vérification en base : un `load` peut compter dessus. */
			token: string;
			/** L'administrateur que la base reconnaît derrière ce jeton. */
			admin: { user_id: string; email: string };
		}
		interface Error {
			message: string;
		}
	}
}

export {};
