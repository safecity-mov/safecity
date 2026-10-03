import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
export default {
	kit: {
		adapter: adapter(),
		// La confiance dans l'origine derrière Caddy se règle par `PROTOCOL_HEADER` et
		// `HOST_HEADER` (docker-compose.yml), pas ici : `checkOrigin` est vrai par défaut et
		// déprécié en tant qu'option.
		//
		// Content-Security-Policy émise par SvelteKit, avec un nonce par réponse pour ses
		// propres scripts. Tout est servi par cette origine — la console ne contacte aucun
		// domaine tiers (§11.5) — et MapLibre a besoin de trois choses : ses tuiles et glyphes
		// en `connect-src`, son worker (un module ES de notre build) en `worker-src`, et des
		// images `blob:` pour les sprites qu'il décode. `unsafe-inline` sur les styles couvre
		// les attributs `style="…"` des composants, dont le masque des icônes.
		csp: {
			mode: 'auto',
			directives: {
				'default-src': ['self'],
				'script-src': ['self'],
				'style-src': ['self', 'unsafe-inline'],
				'img-src': ['self', 'data:', 'blob:'],
				'connect-src': ['self'],
				'worker-src': ['self', 'blob:'],
				'font-src': ['self'],
				'object-src': ['none'],
				'base-uri': ['self'],
				'form-action': ['self'],
				'frame-ancestors': ['none']
			}
		}
	}
};
