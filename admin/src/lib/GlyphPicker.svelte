<script>
	/**
	 * Le choix d'un glyphe Material Symbols comme icône de type : une recherche, deux styles,
	 * une grille. Au clic, le glyphe est dessiné en silhouette PNG et rendu au parent par
	 * `onpick`, qui décide quoi en faire — l'envoyer tout de suite pour un type existant, ou
	 * le garder pour la création.
	 *
	 * La grille s'écrit avec la police variable du paquet `@material-symbols/font-400` (le
	 * texte du span est le nom, la police en fait un dessin par ligature, et l'axe `FILL` se
	 * règle en CSS). La silhouette, elle, est peinte depuis le tracé SVG (lib/silhouette.js),
	 * parce que le canevas ne sait pas régler cet axe.
	 *
	 * La recherche porte sur le nom et sur les mots-clés de Google (lib/glyph-tags.json, écrit
	 * par scripts/glyph-tags.mjs) : « vehicle » ne figure dans aucun nom mais décrit plus de
	 * cent glyphes. Les mots-clés sont chargés à la première ouverture, pas avec la page.
	 *
	 * C'est la seconde surface de la console qui exige JavaScript, après la carte : il n'y a
	 * pas de canevas sans navigateur. Sans lui, la grille n'apparaît pas et le téléversement
	 * d'un PNG reste possible.
	 */
	import '@material-symbols/font-400/outlined.css';
	import { browser } from '$app/environment';
	import { NAMES, STYLES } from '$lib/glyphs.js';
	import { renderSilhouette } from '$lib/silhouette.js';

	/**
	 * @type {{
	 *   label?: string,
	 *   onpick: (glyph: { name: string, style: import('$lib/glyphs.js').GlyphStyle, pngBase64: string }) => void | Promise<void>
	 * }}
	 */
	let { label = 'Choisir un glyphe Material', onpick } = $props();

	/** Au-delà, la grille ne sert plus à choisir : on demande d'affiner. */
	const MAX_SHOWN = 240;

	let open = $state(false);
	let query = $state('');
	/** Nom → mots-clés, en anglais comme les noms ; vide tant que le fichier n'est pas arrivé. */
	let tags = $state(/** @type {Record<string, string>} */ ({}));
	let tagsLoading = $state(false);
	/** @type {import('$lib/glyphs.js').GlyphStyle} */
	let style = $state('filled');
	let busy = $state(false);
	let error = $state('');

	/**
	 * Chaque mot tapé doit se retrouver dans le nom ou dans les mots-clés. Les glyphes dont le
	 * nom contient la recherche viennent d'abord : « car » doit montrer `directions_car` avant
	 * la centaine d'icônes de transport qui portent le mot-clé.
	 */
	const matches = $derived.by(() => {
		const words = query.trim().toLowerCase().split(/[\s_-]+/).filter(Boolean);
		if (words.length === 0) return NAMES;
		const byName = [];
		const byTag = [];
		for (const n of NAMES) {
			const t = tags[n] ?? '';
			if (words.every((w) => n.includes(w))) byName.push(n);
			else if (words.every((w) => n.includes(w) || t.includes(w))) byTag.push(n);
		}
		return byName.concat(byTag);
	});
	const shown = $derived(matches.slice(0, MAX_SHOWN));

	async function toggle() {
		open = !open;
		if (!open || tagsLoading || Object.keys(tags).length) return;
		tagsLoading = true;
		try {
			// Import dynamique : Vite en fait un fichier à part, demandé une fois, ici.
			tags = (await import('$lib/glyph-tags.json')).default;
		} catch {
			// Sans mots-clés la recherche marche encore, sur le nom seul.
		} finally {
			tagsLoading = false;
		}
	}

	/** @param {string} name */
	async function pick(name) {
		if (busy) return;
		busy = true;
		error = '';
		try {
			const pngBase64 = await renderSilhouette(name, style);
			await onpick({ name, style, pngBase64 });
			open = false;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Le dessin du glyphe a échoué.';
		} finally {
			busy = false;
		}
	}
</script>

{#if browser}
	<div class="choix">
		<button type="button" class="secondaire" onclick={toggle} aria-expanded={open}>
			{label}
		</button>

		{#if open}
			<div class="panneau">
				<div class="outils">
					<!-- svelte-ignore a11y_autofocus : le panneau vient de s'ouvrir sur un clic, le focus y est attendu -->
					<input
						type="search"
						placeholder="Rechercher (en anglais) : vehicle, glass, warning…"
						bind:value={query}
						autofocus
						aria-label="Rechercher un glyphe"
					/>
					{#each Object.entries(STYLES) as [key, s] (key)}
						<label class="style">
							<input type="radio" name="glyph-style" value={key} bind:group={style} />
							{s.label}
						</label>
					{/each}
				</div>

				{#if error}<p class="erreur">{error}</p>{/if}

				<div class="grille" aria-busy={busy}>
					{#each shown as name (name)}
						<button
							type="button"
							class="glyphe"
							title={name}
							disabled={busy}
							onclick={() => pick(name)}
						>
							<span class="pastille">
								<span
									class="mi material-symbols-outlined"
									style="font-variation-settings: 'FILL' {STYLES[style].fill}"
								>{name}</span>
							</span>
							<span class="nom">{name.replaceAll('_', ' ')}</span>
						</button>
					{:else}
						<p class="vide">Aucun glyphe ne porte ce nom.</p>
					{/each}
				</div>
				{#if matches.length > shown.length}
					<p class="reste">{matches.length - shown.length} autres glyphes : affinez la recherche.</p>
				{/if}
			</div>
		{/if}
	</div>
{/if}

<style>
	.choix { display: flex; flex-direction: column; gap: 0.5rem; }
	.panneau {
		border: 1px solid #e6e9ee; border-radius: 8px; background: #f7f8fa; padding: 0.75rem;
		width: min(100%, 44rem);
	}
	.outils { display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: center; margin-bottom: 0.5rem; }
	.outils input[type='search'] {
		font: inherit; padding: 0.35rem 0.5rem; border: 1px solid #c8cdd4; border-radius: 6px;
		flex: 1 1 16rem;
	}
	.style { font-size: 0.85rem; display: flex; gap: 0.3rem; align-items: center; }
	.grille {
		display: grid; grid-template-columns: repeat(auto-fill, minmax(5.2rem, 1fr)); gap: 0.25rem;
		max-height: 22rem; overflow-y: auto; padding: 0.25rem; background: #fff;
		border: 1px solid #e6e9ee; border-radius: 6px;
	}
	.grille[aria-busy='true'] { opacity: 0.6; }
	.glyphe {
		display: flex; flex-direction: column; align-items: center; gap: 0.25rem;
		background: none; border: 1px solid transparent; border-radius: 6px; padding: 0.4rem 0.2rem;
		color: #1b1f24; cursor: pointer;
	}
	.glyphe:hover, .glyphe:focus-visible { border-color: #1f5673; background: #f0f5f8; }
	/* La même pastille que l'aperçu de la page : le choix se fait sur le rendu réel. Le
	   débordement est coupé : avant l'arrivée de la police, le nom s'afficherait en toutes
	   lettres. */
	.pastille {
		width: 2.6rem; height: 2.6rem; border-radius: 50%; background: #a4161a; overflow: hidden;
		border: 2px solid #fff; box-shadow: 0 1px 4px rgb(0 0 0 / 0.25);
		display: flex; align-items: center; justify-content: center;
	}
	.mi { font-size: 1.6rem; color: #fff; }
	.nom { font-size: 0.65rem; color: #5a6470; text-align: center; line-height: 1.15; word-break: break-word; }
	.reste, .vide { font-size: 0.8rem; color: #5a6470; margin: 0.4rem 0 0; }
	.vide { grid-column: 1 / -1; padding: 1rem; }
</style>
