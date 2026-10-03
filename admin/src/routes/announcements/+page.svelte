<script>
	import FormMessage from '$lib/FormMessage.svelte';
	import { ANNOUNCEMENT_STATES, shortDate } from '$lib/format.js';

	let { data, form } = $props();

	// Le compteur se tient pendant qu'on tape : deux cents caractères, c'est une ligne de
	// bandeau, pas un article. Le serveur refuse au-delà, autant le voir avant.
	let body = $state('');
	const restants = $derived(data.maxLength - body.length);

	/** Retirer n'a de sens que pour ce qui est encore visible, ou va le devenir. */
	const retirable = (/** @type {{ state: string }} */ a) =>
		a.state === 'active' || a.state === 'scheduled';
</script>

<h1>Annonces</h1>
<p class="note">
	Un message court à <strong>toutes les personnes qui utilisent l'app</strong>. Il apparaît en
	bandeau en haut de la carte, là où s'affiche « Version disponible », au prochain lancement ou
	retour au premier plan ; le toucher le ferme. L'annonce s'éteint d'elle-même à la fin de sa
	durée, ou quand vous la retirez.
</p>
<p class="note">
	Une annonce ne se corrige pas : retirez-la et publiez-en une autre. Le journal garde le texte,
	la durée et le motif de chacune. Et seules les versions de l'app qui savent lire les annonces
	les affichent — les plus anciennes ne verront que l'avis de mise à jour.
</p>

<FormMessage {form} />

<form method="POST" action="?/publish" class="carte">
	<label class="texte">Texte
		<textarea name="body" bind:value={body} maxlength={data.maxLength} rows="2" required
			placeholder="Les signalements du 21 au 27 septembre ont été perdus : merci de les refaire."></textarea>
		<small class:alerte={restants < 20}>{restants} caractère{restants > 1 ? 's' : ''} restant{restants > 1 ? 's' : ''}</small>
	</label>
	<div class="champs">
		<label>Visible pendant
			<select name="hours">
				{#each data.durations as d (d.hours)}
					<option value={d.hours} selected={d.hours === data.defaultHours}>{d.label}</option>
				{/each}
			</select>
			<small>une heure par défaut : le bandeau se voit à chaque ouverture</small>
		</label>
		<label>Motif
			<input type="text" name="reason" placeholder="panne du 21 au 27/09" required />
			<small>inscrit au journal, pas affiché dans l'app</small>
		</label>
		<button type="submit">Publier</button>
	</div>
</form>

<h2>Les dernières</h2>
{#if data.announcements.length === 0}
	<p class="dim">Aucune annonce pour l'instant.</p>
{:else}
	<table>
		<thead>
			<tr><th>État</th><th>Texte</th><th>Du</th><th>Au</th><th>Par</th><th></th></tr>
		</thead>
		<tbody>
			{#each data.announcements as a (a.id)}
				<tr class={a.state}>
					<td>{ANNOUNCEMENT_STATES[a.state] ?? a.state}</td>
					<td class="corps">{a.body}</td>
					<td>{shortDate(a.starts_at)}</td>
					<td>{a.withdrawn_at ? `retirée le ${shortDate(a.withdrawn_at)}` : shortDate(a.ends_at)}</td>
					<td>{a.created_by_email}</td>
					<td>
						{#if retirable(a)}
							<form method="POST" action="?/withdraw" class="action">
								<input type="hidden" name="id" value={a.id} />
								<input type="text" name="reason" placeholder="Motif" aria-label="Motif du retrait" required size="12" />
								<button type="submit" class="danger">Retirer</button>
							</form>
						{/if}
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
{/if}

<style>
	.note strong { color: #1b1f24; }
	.carte { background: #fff; border: 1px solid #e6e9ee; border-radius: 8px; padding: 1rem; margin-bottom: 1.5rem; }
	.texte { display: flex; flex-direction: column; font-size: 0.75rem; color: #5a6470; gap: 0.25rem; margin-bottom: 1rem; }
	.texte textarea { font: inherit; font-size: 0.95rem; color: #1b1f24; padding: 0.5rem; resize: vertical; }
	.texte small { font-size: 0.7rem; color: #8a8f97; }
	.texte small.alerte { color: #a4161a; }
	.champs { display: flex; flex-wrap: wrap; gap: 1rem; align-items: flex-end; }
	.champs label { display: flex; flex-direction: column; font-size: 0.75rem; color: #5a6470; gap: 0.25rem; }
	.champs small { font-size: 0.7rem; color: #8a8f97; }
	.action { display: flex; gap: 0.4rem; align-items: center; }
	.corps { max-width: 28rem; }
	tr.expired td, tr.withdrawn td { color: #8a8f97; }
	h2 { font-size: 1.1rem; margin-top: 2rem; }
	.dim { font-size: 0.8rem; color: #5a6470; }
</style>
