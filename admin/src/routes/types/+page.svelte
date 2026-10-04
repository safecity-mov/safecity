<script>
	import { tick } from 'svelte';
	import FormMessage from '$lib/FormMessage.svelte';
	import GlyphPicker from '$lib/GlyphPicker.svelte';
	import { STYLES } from '$lib/glyphs.js';

	let { data, form } = $props();

	/**
	 * Pour un type existant, le glyphe choisi part aussitôt : on remplit le formulaire caché
	 * de la ligne et on le soumet. C'est le même aller-retour serveur que « Téléverser ».
	 * @type {Record<string, HTMLFormElement>}
	 */
	const glyphForms = {};
	/** @type {Record<string, { name: string, style: import('$lib/glyphs.js').GlyphStyle, pngBase64: string }>} */
	let chosen = $state({});

	/** @param {string} code @param {{ name: string, style: import('$lib/glyphs.js').GlyphStyle, pngBase64: string }} glyph */
	async function sendGlyph(code, glyph) {
		chosen[code] = glyph;
		// Les champs cachés sont liés à `chosen` : on laisse Svelte les écrire avant d'envoyer.
		await tick();
		glyphForms[code]?.requestSubmit();
	}

	/**
	 * Pour un type à créer, le glyphe attend dans le formulaire : il partira avec le reste.
	 * @type {{ name: string, style: import('$lib/glyphs.js').GlyphStyle, pngBase64: string } | null}
	 */
	let newGlyph = $state(null);
</script>

<h1>Types de danger</h1>
<p class="note">
	Ce catalogue pilote l'interface de l'application : un libellé changé ici se voit chez tous
	les testeurs au prochain lancement. Un type désactivé n'est plus proposé au signalement,
	mais les dangers existants de ce type restent affichés.
</p>
<p class="note">
	Combien de voix il faut pour faire disparaître un danger ne se règle pas ici : c'est la même
	règle pour tous les types, dans <a href="/rules">Règles</a>.
</p>
<p class="note">
	<strong>L'icône est une silhouette, pas une image en couleurs.</strong> Le marqueur est un
	disque coloré par le niveau, qui s'inverse quand le danger est contesté : l'application
	n'utilise donc que la transparence du fichier et peint la forme elle-même. Le plus simple
	est de choisir un glyphe Material Symbols dans la grille, la famille qui a succédé aux
	dessins d'origine de l'application. On peut aussi téléverser un PNG carré à fond
	transparent, entre 32 et 512 px,
	64 Ko au plus. L'aperçu ci-dessous montre le résultat exact. Sans image, le type garde le
	dessin embarqué dans l'application.
</p>

<FormMessage {form} />

{#each data.types as t (t.code)}
	<div class="carte">
		<div class="icone">
			{#if data.icons[t.code]}
				<!-- Aperçu fidèle : on masque un aplat blanc par la silhouette, sur un disque
				     coloré. C'est exactement ce que fait l'application — elle ne lit que la
				     transparence du fichier. -->
				<span class="pastille">
					<span
						class="silhouette"
						style="mask-image: url('/types/icon/{t.code}?v={data.icons[t.code].updated_at}');
						       -webkit-mask-image: url('/types/icon/{t.code}?v={data.icons[t.code].updated_at}')"
					></span>
				</span>
				<span class="dim">{data.icons[t.code].width} px</span>
			{:else}
				<span class="pastille vide2" title="Aucune image : dessin embarqué">—</span>
				<span class="dim">embarquée</span>
			{/if}
		</div>

		<div class="televersement">
			<GlyphPicker onpick={(glyph) => sendGlyph(t.code, glyph)} />
			<form
				method="POST"
				action="?/glyph"
				class="cache"
				bind:this={glyphForms[t.code]}
				aria-hidden="true"
			>
				<input type="hidden" name="code" value={t.code} />
				<input type="hidden" name="glyph" value={chosen[t.code]?.name ?? ''} />
				<input type="hidden" name="glyph_style" value={chosen[t.code]?.style ?? ''} />
				<input type="hidden" name="png_base64" value={chosen[t.code]?.pngBase64 ?? ''} />
			</form>
			<form method="POST" action="?/upload" enctype="multipart/form-data">
				<input type="hidden" name="code" value={t.code} />
				<input type="file" name="png" accept="image/png" aria-label="Fichier PNG pour {t.code}" required />
				<button type="submit" class="secondaire">Téléverser</button>
			</form>
			{#if data.icons[t.code]}
				<form method="POST" action="?/clearIcon">
					<input type="hidden" name="code" value={t.code} />
					<button type="submit" class="secondaire">Retirer l'image</button>
				</form>
			{/if}
		</div>
	</div>

	<form method="POST" action="?/save" class="carte">
		<input type="hidden" name="code" value={t.code} />
		<div class="entete">
			<code>{t.code}</code>
			<label class="bascule">
				<input type="checkbox" name="enabled" checked={t.enabled} />
				proposé au signalement
			</label>
		</div>
		<div class="champs">
			<label>Libellé
				<input type="text" name="label_fr" value={t.label_fr} required />
			</label>
			<label>Verbe de résolution
				<input type="text" name="resolved_label_fr" value={t.resolved_label_fr} required />
			</label>
			<label>Glyphe de repli
				<input type="text" name="icon" value={t.icon} size="10" />
			</label>
			<label>Expire après (jours)
				<input type="number" name="default_ttl_days" value={t.default_ttl_days} min="1" max="3650" required />
			</label>
			<label>Rayon anti-doublon (m)
				<input type="number" name="dedup_radius_m" value={t.dedup_radius_m} min="1" max="500" required />
			</label>
			<label>Ordre
				<input type="number" name="sort_order" value={t.sort_order} min="0" max="9999" required />
				<small>dans l'app, les plus petits d'abord ; l'ordre de cette page est le même</small>
			</label>
			<button type="submit">Enregistrer</button>
		</div>
	</form>
{/each}

<h2>Nouveau type</h2>
<form method="POST" action="?/create" class="carte">
	<div class="champs">
		<label>Code
			<input type="text" name="code" placeholder="broken_glass" required />
		</label>
		<label>Libellé
			<input type="text" name="label_fr" placeholder="Verre brisé" required />
		</label>
		<label>Verbe de résolution
			<input type="text" name="resolved_label_fr" placeholder="Nettoyé" />
		</label>
		<button type="submit" class="secondaire">Créer, désactivé</button>
	</div>

	<!-- L'icône du nouveau type. Un type que l'app ne connaît pas n'a aucun dessin embarqué :
	     sans glyphe choisi ici, il s'affichera avec le triangle générique jusqu'à ce qu'on lui
	     téléverse une image. -->
	<div class="nouveau-glyphe">
		<div class="icone">
			{#if newGlyph}
				<span class="pastille">
					<span
						class="mi material-symbols-outlined"
						style="font-variation-settings: 'FILL' {STYLES[newGlyph.style].fill}"
					>{newGlyph.name}</span>
				</span>
				<span class="dim">{newGlyph.name}</span>
			{:else}
				<span class="pastille vide2" title="Aucun glyphe choisi : triangle générique">—</span>
				<span class="dim">sans icône</span>
			{/if}
		</div>
		<GlyphPicker
			label={newGlyph ? 'Changer de glyphe' : 'Choisir un glyphe Material'}
			onpick={(glyph) => {
				newGlyph = glyph;
			}}
		/>
		<input type="hidden" name="glyph" value={newGlyph?.name ?? ''} />
		<input type="hidden" name="glyph_style" value={newGlyph?.style ?? ''} />
		<input type="hidden" name="png_base64" value={newGlyph?.pngBase64 ?? ''} />
	</div>
</form>

<style>
	.note strong { color: #1b1f24; }

	/* Le bloc icône est collé au formulaire du type qui suit : une seule carte visuelle. */
	.carte:has(.icone) { display: flex; gap: 1.25rem; align-items: center; margin-bottom: 0; border-bottom: none; border-radius: 8px 8px 0 0; padding-bottom: 0.75rem; }
	.carte:has(.icone) + .carte { border-radius: 0 0 8px 8px; border-top: none; }
	/* Sauf la carte de création, qui porte son bloc icône en bas. */
	form.carte:has(.nouveau-glyphe) { display: block; border-bottom: 1px solid #e6e9ee; border-radius: 8px; padding-bottom: 1rem; }
	.icone { display: flex; flex-direction: column; align-items: center; gap: 0.3rem; }
	.pastille {
		width: 2.6rem; height: 2.6rem; border-radius: 50%; background: #a4161a; overflow: hidden;
		border: 2px solid #fff; box-shadow: 0 1px 4px rgb(0 0 0 / 0.25);
		display: flex; align-items: center; justify-content: center;
	}
	.pastille.vide2 { background: #e6e9ee; color: #8a8f97; box-shadow: none; }
	.silhouette {
		width: 65%; height: 65%; background: #fff;
		mask-size: contain; mask-repeat: no-repeat; mask-position: center;
		-webkit-mask-size: contain; -webkit-mask-repeat: no-repeat; -webkit-mask-position: center;
	}
	.mi { font-size: 1.6rem; color: #fff; }
	.dim { font-size: 0.7rem; color: #5a6470; }
	.televersement { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: flex-start; flex: 1; }
	.televersement form { display: flex; gap: 0.4rem; align-items: center; }
	.televersement form.cache { display: none; }
	.televersement input[type='file'] { font-size: 0.8rem; max-width: 15rem; }
	.nouveau-glyphe { display: flex; gap: 1.25rem; align-items: flex-start; margin-top: 1rem; padding-top: 1rem; border-top: 1px solid #e6e9ee; }
	.carte { background: #fff; border: 1px solid #e6e9ee; border-radius: 8px; padding: 1rem; margin-bottom: 0.75rem; }
	.entete { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.75rem; }
	.entete code { font-size: 0.9rem; color: #5a6470; }
	.bascule { font-size: 0.85rem; display: flex; gap: 0.35rem; align-items: center; }
	.champs { display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: flex-end; }
	.champs label { display: flex; flex-direction: column; font-size: 0.75rem; color: #5a6470; gap: 0.25rem; }
	.champs small { font-size: 0.7rem; color: #8a8f97; max-width: 14rem; }
	h2 { font-size: 1.1rem; margin-top: 2rem; }
</style>
