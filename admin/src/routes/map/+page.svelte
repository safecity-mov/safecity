<script>
	import { onMount } from 'svelte';
	import { enhance } from '$app/forms';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import FormMessage from '$lib/FormMessage.svelte';
	import { count, shortDate, STATUS_COLORS, STATUS_LABELS, statusLabel } from '$lib/format.js';

	let { data, form } = $props();

	/** @type {HTMLDivElement} Le conteneur DOM de la carte. */
	let container;
	/** @type {import('maplibre-gl').Map | null} En `$state` : l'effet de mise à jour doit
	 *  repartir dès que la carte existe, et elle n'existe qu'après le chargement du style. */
	let map = $state(null);
	/** Identifiant du danger ouvert dans le panneau, ou `null`. @type {string | null} */
	let selection = $state(null);

	const hazard = $derived(
		data.hazards.find((/** @type {any} */ h) => h.id === selection) ?? null
	);

	/** @param {any[]} hazards */
	const collection = (hazards) => ({
		type: 'FeatureCollection',
		features: hazards.map((/** @type {any} */ h) => ({
			type: 'Feature',
			geometry: { type: 'Point', coordinates: [h.lng, h.lat] },
			properties: { id: h.id, status: h.status, type: h.type, severity: h.severity }
		}))
	});

	/** Les mêmes rayons que l'app (`Severity.markerRadius`) : le diamètre dit la gravité. */
	const RADIUS = /** @type {any} */ (['match', ['get', 'severity'], 1, 9, 2, 12, 15]);
	/**
	 * Un peu plus petits de loin, pour que les points voisins restent distincts. `zoom` ne
	 * peut être lu qu'en tête d'un `interpolate` : c'est donc lui qui enveloppe la taille
	 * tirée de la donnée, et non l'inverse — MapLibre refuse la couche sinon, sans la dessiner.
	 * @param {number} factor multiplie le rayon à zoom 14 et au-delà
	 */
	const scaled = (factor) =>
		/** @type {any} */ ([
			'interpolate', ['linear'], ['zoom'],
			10, ['*', RADIUS, factor * 0.6],
			14, ['*', RADIUS, factor]
		]);
	/** Côté du canevas des silhouettes, en pixels physiques (pixelRatio 2 → 64 px logiques). */
	const ICON_PX = 128;
	const INK = STATUS_COLORS.disputed;

	/**
	 * La silhouette d'un type, en deux encres : blanche sur un disque plein, colorée sur le
	 * disque creux d'un danger contesté. Seul le canal alpha du PNG sert, comme dans l'app :
	 * `source-in` repeint la forme à l'encre voulue. Sans silhouette téléversée, l'initiale du
	 * libellé tient lieu de glyphe — la console n'a pas la police d'icônes de l'app.
	 * @param {string} code @param {string} ink
	 */
	async function silhouette(code, ink) {
		const canvas = document.createElement('canvas');
		canvas.width = canvas.height = ICON_PX;
		const ctx = /** @type {CanvasRenderingContext2D} */ (canvas.getContext('2d'));
		const version = data.icons[code];
		let drawn = false;
		if (version) {
			try {
				const img = new Image();
				img.src = `/types/icon/${encodeURIComponent(code)}?v=${encodeURIComponent(version)}`;
				await img.decode();
				ctx.drawImage(img, 0, 0, ICON_PX, ICON_PX);
				ctx.globalCompositeOperation = 'source-in';
				ctx.fillStyle = ink;
				ctx.fillRect(0, 0, ICON_PX, ICON_PX);
				drawn = true;
			} catch {
				// Image abîmée ou introuvable : l'initiale prend le relais, le danger reste visible.
			}
		}
		if (!drawn) {
			const letter = (data.types[code]?.label_fr ?? code).trim().charAt(0).toUpperCase() || '?';
			ctx.fillStyle = ink;
			ctx.font = `bold ${ICON_PX * 0.72}px system-ui, sans-serif`;
			ctx.textAlign = 'center';
			ctx.textBaseline = 'middle';
			ctx.fillText(letter, ICON_PX / 2, ICON_PX / 2 + ICON_PX * 0.04);
		}
		return ctx.getImageData(0, 0, ICON_PX, ICON_PX);
	}

	/** @param {import('maplibre-gl').Map} instance */
	async function registerIcons(instance) {
		for (const code of Object.keys(data.types)) {
			const [white, inked] = await Promise.all([silhouette(code, '#fff'), silhouette(code, INK)]);
			for (const [suffix, image] of [['white', white], ['ink', inked]]) {
				const name = `type-${code}-${suffix}`;
				if (instance.hasImage(name)) instance.removeImage(name);
				instance.addImage(name, /** @type {ImageData} */ (image), { pixelRatio: 2 });
			}
		}
	}

	/** Cadre qui contient tout, pour ne pas ouvrir sur une carte vide loin des points.
	 *  @param {any[]} hazards */
	function bounds(hazards) {
		if (hazards.length === 0) return null;
		return hazards.reduce(
			(/** @type {number[][]} */ b, /** @type {any} */ h) => [
				[Math.min(b[0][0], h.lng), Math.min(b[0][1], h.lat)],
				[Math.max(b[1][0], h.lng), Math.max(b[1][1], h.lat)]
			],
			[
				[hazards[0].lng, hazards[0].lat],
				[hazards[0].lng, hazards[0].lat]
			]
		);
	}

	onMount(() => {
		/** @type {import('maplibre-gl').Map | undefined} */
		let instance;
		let destroyed = false;

		(async () => {
			// Import dynamique : MapLibre touche au DOM dès son chargement et ne survit pas au
			// rendu côté serveur. Le reste de la console, lui, continue de fonctionner sans
			// JavaScript — l'écran Dangers reste la porte de secours si celui-ci ne s'affiche pas.
			//
			// Import nommé, et pas `default` : MapLibre 6 ne l'expose plus.
			//
			// `setWorkerUrl` n'est pas un détail de confort : MapLibre déduit l'adresse de son
			// worker de `import.meta.url`, que Vite réécrit vers le chunk empaqueté, où le
			// fichier n'existe pas. Le worker répond alors 404 — et comme tuiles et glyphes ne
			// transitent que par lui, la carte s'affiche vide, sans une seule erreur en console.
			const [{ Map: MapLibre, NavigationControl, ScaleControl, setWorkerUrl }, worker] =
				await Promise.all([
					import('maplibre-gl'),
					import('maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url')
				]);
			if (destroyed) return;
			setWorkerUrl(worker.default);

			instance = new MapLibre({
				container,
				// Servi par notre propre Caddy, comme les tuiles, les glyphes et les sprites :
				// aucune requête ne sort vers un domaine tiers (§11.5).
				style: '/tiles/style.json',
				center: [2.3522, 48.8566],
				zoom: 11
			});
			instance.addControl(new NavigationControl({ showCompass: false }), 'top-right');
			instance.addControl(new ScaleControl({ unit: 'metric' }));

			// Un type disparu du catalogue n'a pas d'image : une image vide plutôt qu'un
			// avertissement par tuile, le disque coloré reste, seul le glyphe manque.
			instance.on('styleimagemissing', (/** @type {any} */ e) => {
				if (instance && !instance.hasImage(e.id)) {
					instance.addImage(e.id, { width: 1, height: 1, data: new Uint8Array(4) });
				}
			});

			instance.on('load', async () => {
				if (!instance || destroyed) return;
				await registerIcons(instance);
				if (destroyed) return;

				// Même regroupement que l'app : au-delà de z13, chaque danger est seul.
				instance.addSource('hazards', {
					type: 'geojson',
					data: collection(data.hazards),
					cluster: true,
					clusterMaxZoom: 13,
					clusterRadius: 48
				});

				instance.addLayer({
					id: 'clusters',
					type: 'circle',
					source: 'hazards',
					filter: ['has', 'point_count'],
					paint: {
						'circle-color': '#1F5673',
						'circle-opacity': 0.9,
						'circle-stroke-color': '#fff',
						'circle-stroke-width': 2,
						'circle-radius': ['step', ['get', 'point_count'], 16, 10, 21, 50, 27]
					}
				});
				instance.addLayer({
					id: 'cluster-count',
					type: 'symbol',
					source: 'hazards',
					filter: ['has', 'point_count'],
					layout: {
						'text-field': ['get', 'point_count_abbreviated'],
						'text-font': ['Noto Sans Medium'],
						'text-size': 13,
						'text-allow-overlap': true
					},
					paint: { 'text-color': '#fff' }
				});

				const status = /** @type {any} */ ([
					'match',
					['get', 'status'],
					...Object.entries(STATUS_COLORS).flat(),
					'#5a6470'
				]);
				const disputed = /** @type {any} */ (['==', ['get', 'status'], 'disputed']);
				instance.addLayer({
					id: 'hazards',
					type: 'circle',
					source: 'hazards',
					filter: ['!', ['has', 'point_count']],
					paint: {
						'circle-radius': scaled(1),
						// Plein aux couleurs du statut ; creux, cerclé de la couleur, quand le
						// danger est « signalé résolu » — le même code visuel que l'app.
						'circle-color': ['case', disputed, '#fff', status],
						'circle-stroke-color': ['case', disputed, status, '#fff'],
						'circle-stroke-width': ['case', disputed, 2.5, 2],
						'circle-opacity': 0.95
					}
				});
				instance.addLayer({
					id: 'hazard-icons',
					type: 'symbol',
					source: 'hazards',
					filter: ['!', ['has', 'point_count']],
					layout: {
						'icon-image': [
							'concat',
							'type-',
							['get', 'type'],
							['case', disputed, '-ink', '-white']
						],
						// La silhouette occupe 1,3 rayon de côté, comme dans l'app : l'image fait
						// 64 px logiques, d'où le rapport.
						'icon-size': scaled(1.3 / 64),
						'icon-allow-overlap': true,
						'icon-ignore-placement': true
					}
				});

				// Le cadre initial contient les dangers encore sur la carte : un signalement
				// retiré, souvent inventé loin de tout, ne doit pas dézoomer tout le monde.
				// Sans aucun danger visible, on montre quand même les retirés plutôt que rien.
				const visible = data.hazards.filter((/** @type {any} */ h) => h.status !== 'removed');
				const box = bounds(visible.length ? visible : data.hazards);
				if (box) {
					instance.fitBounds(
						/** @type {[[number, number], [number, number]]} */ (box),
						{ padding: 60, maxZoom: 15, duration: 0 }
					);
				}

				instance.on('click', 'hazards', (/** @type {any} */ e) => {
					selection = e.features[0].properties.id;
				});
				// Un groupe s'ouvre au clic, jusqu'au zoom où il se sépare.
				instance.on('click', 'clusters', async (/** @type {any} */ e) => {
					if (!instance) return;
					const feature = e.features[0];
					const source = /** @type {import('maplibre-gl').GeoJSONSource} */ (
						instance.getSource('hazards')
					);
					const zoom = await source.getClusterExpansionZoom(feature.properties.cluster_id);
					instance.easeTo({ center: feature.geometry.coordinates, zoom });
				});
				for (const layer of ['hazards', 'clusters']) {
					instance.on('mouseenter', layer, () => {
						if (instance) instance.getCanvas().style.cursor = 'pointer';
					});
					instance.on('mouseleave', layer, () => {
						if (instance) instance.getCanvas().style.cursor = '';
					});
				}

				map = instance;
			});
		})();

		// Rendue de façon synchrone : Svelte ignore ce que rend un callback `async`, et la carte
		// resterait vivante après le départ de l'écran.
		return () => {
			destroyed = true;
			instance?.remove();
		};
	});

	// Après une modération, `enhance` rejoue le `load` : la carte survit, ses points se mettent
	// à jour. Sans cela il faudrait recharger la page, et on perdrait la vue en cours.
	$effect(() => {
		const source = /** @type {import('maplibre-gl').GeoJSONSource | undefined} */ (
			map?.getSource('hazards')
		);
		source?.setData(collection(data.hazards));
	});
</script>

<h1>Carte</h1>

<form method="GET" class="filtres">
	<label for="status">Statut</label>
	<select id="status" name="status">
		<option value="" selected={data.status === ''}>tous</option>
		{#each Object.entries(STATUS_LABELS) as [value, text] (value)}
			<option {value} selected={data.status === value}>{text}</option>
		{/each}
	</select>
	<button type="submit" class="secondaire">Filtrer</button>
	<span class="compte">
		{count(data.hazards.length, 'danger')}
		{#if data.hasMore}<strong> — tronqué à {data.limit}, affinez le filtre</strong>{/if}
	</span>
</form>

<FormMessage {form} />

<div class="plan">
	<div class="carte" bind:this={container}></div>

	{#if hazard}
		<aside>
			<button class="fermer" onclick={() => (selection = null)} aria-label="Fermer">×</button>
			<h2>{data.types[hazard.type]?.label_fr ?? hazard.type}</h2>
			<p class="statut" style="color: {STATUS_COLORS[hazard.status] ?? '#5a6470'}">
				{statusLabel(hazard.status)}
			</p>
			{#if hazard.description}
				<p class="description">{hazard.description}</p>
				<!-- Le texte part, le danger reste : pour une insulte ou un nom sur un signalement
				     par ailleurs fondé. Le texte effacé est gardé dans le journal d'audit. -->
				<form method="POST" action="?/clearDescription" use:enhance class="precision">
					<input type="text" name="reason" placeholder="Motif" aria-label="Motif de l'effacement" required />
					<input type="hidden" name="id" value={hazard.id} />
					<button type="submit" class="secondaire">Effacer la précision</button>
				</form>
			{/if}
			<dl>
				<dt>Position</dt>
				<dd class="mono">{hazard.lat.toFixed(5)}, {hazard.lng.toFixed(5)}</dd>
				{#if hazard.address}<dt>Adresse</dt><dd>{hazard.address}</dd>{/if}
				<dt>Gravité</dt>
				<dd>{hazard.severity}</dd>
				<dt>Poids « présent »</dt>
				<dd>{hazard.confirm_weight.toFixed(1)} <small>({count(hazard.events_count, 'geste')})</small></dd>
				<dt>Signalements</dt>
				<dd>{hazard.flags}</dd>
				<dt>Créé</dt>
				<dd>{shortDate(hazard.created_at)}</dd>
				{#if hazard.last_confirmed_at}
					<dt>Confirmé</dt>
					<dd>{shortDate(hazard.last_confirmed_at)}</dd>
				{/if}
				<dt>Identifiant</dt>
				<dd class="mono petit">{hazard.id}</dd>
			</dl>

			<form method="POST" action="?/moderate" use:enhance>
				<input type="hidden" name="id" value={hazard.id} />
				<input type="hidden" name="removed" value={hazard.status === 'removed' ? 'false' : 'true'} />
				<input type="text" name="reason" placeholder="Motif" aria-label="Motif" required />
				<button type="submit" class={hazard.status === 'removed' ? 'secondaire' : 'danger'}>
					{hazard.status === 'removed' ? 'Rétablir' : 'Retirer'}
				</button>
			</form>

			<!-- Replié : bannir n'est pas le geste courant, et un bouton nu à côté de « Retirer »
			     s'appuie par mégarde. L'identifiant du terminal n'apparaît nulle part, ici pas
			     plus qu'ailleurs — c'est le serveur qui remonte à l'auteur (§11). -->
			<details class="bannir">
				<summary>Bannir l'auteur</summary>
				<p>
					Annule tous ses gestes et retire ses signalements. <strong>Définitif</strong> :
					il n'y a pas de déblocage. En cas d'erreur, les dangers se rétablissent un par
					un depuis cet écran. Possible dans les 24 h seulement : au-delà, plus rien ne
					relie un signalement à son auteur.
				</p>
				<form method="POST" action="?/banAuthor" use:enhance>
					<input type="hidden" name="hazard" value={hazard.id} />
					<input type="text" name="reason" placeholder="Motif" aria-label="Motif du bannissement" required />
					<button type="submit" class="danger">Bannir</button>
				</form>
			</details>
		</aside>
	{/if}

	<ul class="legende">
		{#each Object.entries(STATUS_COLORS) as [value, color] (value)}
			<li><span class="pastille" style="background: {color}"></span>{statusLabel(value)}</li>
		{/each}
		<li class="lecture">icône : type · diamètre : gravité · creux : signalé résolu</li>
	</ul>
</div>

<style>
	.filtres { margin-bottom: 1rem; display: flex; gap: 0.5rem; align-items: center; }
	.compte { color: #5a6470; font-size: 0.85rem; }
	.compte strong { color: #a4161a; }

	.plan { position: relative; }
	.carte {
		height: calc(100vh - 14rem);
		min-height: 24rem;
		border: 1px solid #e6e9ee;
		border-radius: 8px;
		overflow: hidden;
	}

	aside {
		position: absolute; top: 0.75rem; left: 0.75rem; width: 19rem; max-height: calc(100% - 1.5rem);
		overflow-y: auto; background: #fff; border: 1px solid #e6e9ee; border-radius: 8px;
		padding: 0.9rem 1rem; box-shadow: 0 2px 10px rgb(0 0 0 / 0.12);
	}
	aside h2 { font-size: 1.05rem; margin: 0 2rem 0.2rem 0; }
	.statut { margin: 0 0 0.6rem; font-size: 0.85rem; font-weight: 600; }
	.description { margin: 0 0 0.6rem; font-size: 0.9rem; }
	.fermer {
		position: absolute; top: 0.5rem; right: 0.5rem; background: transparent; border: none;
		color: #5a6470; font-size: 1.3rem; line-height: 1; padding: 0.1rem 0.35rem;
	}
	dl { display: grid; grid-template-columns: auto 1fr; gap: 0.15rem 0.6rem; margin: 0 0 0.9rem; font-size: 0.85rem; }
	dt { color: #5a6470; }
	dd { margin: 0; }
	dd.mono { font-family: ui-monospace, monospace; font-size: 0.8rem; }
	dd.petit { font-size: 0.7rem; word-break: break-all; }
	aside form { display: flex; gap: 0.35rem; }
	aside form input { min-width: 0; flex: 1; }

	.bannir { margin-top: 0.9rem; border-top: 1px solid #e6e9ee; padding-top: 0.7rem; }
	.bannir summary { font-size: 0.85rem; color: #a4161a; cursor: pointer; }
	.bannir p { font-size: 0.75rem; color: #5a6470; margin: 0.5rem 0; }

	/* Au-dessus de l'échelle MapLibre, qui occupe déjà le coin bas-gauche. */
	.precision { display: flex; gap: 0.35rem; margin: 0 0 0.8rem; }
	.legende {
		position: absolute; bottom: 2.6rem; left: 0.75rem; display: flex; gap: 0.75rem;
		list-style: none; margin: 0; padding: 0.4rem 0.7rem; background: rgb(255 255 255 / 0.92);
		border: 1px solid #e6e9ee; border-radius: 6px; font-size: 0.75rem; color: #1b1f24;
	}
	.legende li { display: flex; align-items: center; gap: 0.3rem; }
	.legende .lecture { color: #5a6470; font-size: 0.8rem; margin-left: 0.4rem; }
	.pastille { width: 0.7rem; height: 0.7rem; border-radius: 50%; border: 1px solid #fff; box-shadow: 0 0 0 1px #c8cdd4; }
</style>
