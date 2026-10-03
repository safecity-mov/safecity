import { sveltekit } from '@sveltejs/kit/vite';

export default {
	plugins: [sveltekit()],
	// MapLibre charge son moteur de tuiles dans un worker qui est lui-même un module ES.
	// Sans ce format, Vite l'empaquetterait en IIFE et `new Worker(url, { type: 'module' })`
	// n'irait nulle part. Voir l'appel à `setWorkerUrl` dans src/routes/carte/+page.svelte.
	worker: { format: 'es' }
};
