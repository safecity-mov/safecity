<script>
	import { untrack } from 'svelte';
	import FormMessage from '$lib/FormMessage.svelte';
	import { shortDate } from '$lib/format.js';

	let { data, form } = $props();

	// L'aperçu se calcule pendant qu'on tape : c'est ce qui permet de voir l'effet d'un réglage
	// avant de l'enregistrer, plutôt que de le découvrir sur la carte.
	//
	// `untrack` : ces trois champs partent de ce que dit la base, puis appartiennent à celui qui
	// tape. Les relier à `data` écraserait sa saisie au moindre rechargement de la page.
	let plancher = $state(untrack(() => data.rules.min_resolve_votes));
	let rythme = $state(untrack(() => data.rules.confirmations_per_resolve_vote));
	let plafond = $state(untrack(() => data.rules.max_resolve_votes));
	let signalement = $state(untrack(() => data.rules.report_confirmations));

	const palier = (/** @type {number} */ tier) =>
		data.tiers.find((/** @type {{ tier: number }} */ t) => t.tier === tier);

	let proche = $state(untrack(() => palier(1)?.max_distance_m ?? 100));
	let poids1 = $state(untrack(() => palier(1)?.weight ?? 1));
	let poids2 = $state(untrack(() => palier(2)?.weight ?? 1 / 3));

	/** Combien de personnes il faut à ce poids-là pour atteindre le plancher. */
	const votants = (/** @type {number} */ poids) => {
		const n = Math.ceil(plancher / Math.max(poids, 0.0001));
		return `${n} ${n > 1 ? 'personnes' : 'personne'}`;
	};

	/** Le seuil pour un poids « présent » donné : clamp(ceil(poids / N), plancher, plafond). */
	const seuil = (/** @type {number} */ poids) =>
		Math.max(plancher, Math.min(plafond, Math.ceil(poids / Math.max(rythme, 1))));

	/** Des confirmations sur place, après le signalement lui-même. */
	const exemples = [0, 3, 6, 15];

	const personnes = (/** @type {number} */ n) => `${n} ${n > 1 ? 'personnes' : 'personne'}`;
</script>

<h1>Règles de modération</h1>
<p class="note">
	Combien de voix « résolu » il faut pour qu'un danger quitte la carte. Ces trois réglages
	valent pour <strong>tous les types</strong> : un signalement ne se modère pas autrement selon
	qu'il s'agit d'un nid-de-poule ou de verre brisé.
</p>
<p class="note">
	Le seuil monte avec le <strong>poids</strong> des gestes « présent » — le signalement, puis
	chaque « toujours là » — pour qu'un trou vu par tout le quartier ne disparaisse pas sur deux
	clics. Un signalement vaut à lui seul plusieurs confirmations : c'est le geste lourd, celui
	qui place le pin et choisit la gravité. Et chaque geste, « présent » comme « résolu », pèse
	selon la distance : sur place 1, ailleurs ou sans position un tiers. Il faut donc trois
	personnes à distance pour valoir une sur place, dans un sens comme dans l'autre.
</p>
<p class="note">
	<strong>Un changement s'applique tout de suite</strong>, y compris aux dangers déjà signalés :
	le statut se recalcule depuis le journal à chaque geste. Baisser le plancher peut faire
	disparaître des dangers déjà contestés dès le vote suivant.
</p>

<FormMessage {form} />

<form method="POST" action="?/save" class="carte">
	<div class="champs">
		<label>Votes minimum
			<input type="number" name="min_resolve_votes" bind:value={plancher} min="1" max="10" required />
			<small>sur un danger tout neuf</small>
		</label>
		<label>Confirmations par voix
			<input
				type="number"
				name="confirmations_per_resolve_vote"
				bind:value={rythme}
				min="1"
				max="100"
				required
			/>
			<small>une voix exigée de plus toutes les N confirmations</small>
		</label>
		<label>Votes maximum
			<input type="number" name="max_resolve_votes" bind:value={plafond} min="1" max="20" required />
			<small>au-delà, plus rien ne monte</small>
		</label>
		<label>Un signalement vaut
			<input type="number" name="report_confirmations" bind:value={signalement} min="1" max="10" required />
			<small>confirmations sur place, dans le poids « présent »</small>
		</label>
		<button type="submit">Enregistrer</button>
	</div>
</form>

<h2>Ce que ça donne</h2>
<table>
	<thead>
		<tr>
			<th>Un signalement sur place, puis</th><th>Poids « présent »</th>
			<th>Votes « résolu » exigés</th><th>Soit, sur place</th>
		</tr>
	</thead>
	<tbody>
		{#each exemples as k (k)}
			<tr>
				<td>{k === 0 ? 'rien' : `${k} « toujours là » sur place`}</td>
				<td>{signalement + k}</td>
				<td>{seuil(signalement + k)}</td>
				<td>{personnes(seuil(signalement + k))}</td>
			</tr>
		{/each}
	</tbody>
</table>

<p class="dim">Dernier réglage : {shortDate(data.rules.updated_at)}. Chaque écriture est inscrite au journal.</p>

<h2>Poids d'un geste selon la distance</h2>
<p class="note">
	Un geste compte d'autant plus que la personne était près du danger — le signalement et
	« toujours là » comme « résolu ». C'est ce qui empêche d'effacer un trou depuis son canapé,
	ou d'en inventer un, et c'est <strong>l'application qui calcule le palier</strong>, sur
	l'appareil : la position de celui qui agit n'arrive jamais jusqu'ici (§11.1). Elle n'envoie
	que le palier, « sur place » ou « ailleurs » — d'où l'intérêt que la règle vienne du serveur,
	pour que deux versions installées en même temps ne pondèrent pas différemment.
</p>
<p class="note">
	<strong>Un changement ici ne touche que les gestes à venir</strong>, contrairement aux seuils
	ci-dessus. Le poids d'un vote est figé au moment où il est émis : le journal garde ce qui a
	été compté, et ne se réécrit pas. Et une application déjà ouverte continue d'appliquer
	l'ancienne règle jusqu'à son prochain démarrage.
</p>

<form method="POST" action="?/saveTiers" class="carte">
	<div class="champs">
		<label>Sur place, jusqu'à (m)
			<input type="number" name="tier1_m" bind:value={proche} min="1" max="100000" required />
			<small>palier 1</small>
		</label>
		<label>Poids
			<input type="number" name="tier1_w" bind:value={poids1} min="0.0001" max="1" step="any" required />
		</label>
		<label>Ailleurs, ou sans position
			<input type="text" value="pas de limite" disabled />
			<small>palier 2</small>
		</label>
		<label>Poids
			<input type="number" name="tier2_w" bind:value={poids2} min="0.0001" max="1" step="any" required />
			<small>0,3333 : un tiers, trois gestes d'ailleurs pour un sur place</small>
		</label>
		<button type="submit">Enregistrer</button>
	</div>
</form>

<p class="note">
	Avec ces valeurs, il faut <strong>{votants(poids1)}</strong> sur place pour atteindre un seuil
	de {plancher}, ou <strong>{votants(poids2)}</strong> ailleurs.
</p>

<style>
	.note strong { color: #1b1f24; }
	.carte { background: #fff; border: 1px solid #e6e9ee; border-radius: 8px; padding: 1rem; margin-bottom: 1.5rem; }
	.champs { display: flex; flex-wrap: wrap; gap: 1rem; align-items: flex-end; }
	.champs label { display: flex; flex-direction: column; font-size: 0.75rem; color: #5a6470; gap: 0.25rem; max-width: 16rem; }
	.champs small { font-size: 0.7rem; color: #8a8f97; }
	.champs input { width: 6rem; }
	h2 { font-size: 1.1rem; margin-top: 2rem; }
	.dim { font-size: 0.8rem; color: #5a6470; }
</style>
