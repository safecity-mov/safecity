<script>
	import FormMessage from '$lib/FormMessage.svelte';
	import Pager from '$lib/Pager.svelte';
	import { count, shortDate, STATUS_LABELS, statusLabel } from '$lib/format.js';

	let { data, form } = $props();
</script>

<h1>Dangers</h1>

<form method="GET" class="filtres">
	<label for="status">Statut</label>
	<select id="status" name="status">
		<option value="" selected={data.status === ''}>tous</option>
		{#each Object.entries(STATUS_LABELS) as [value, text] (value)}
			<option {value} selected={data.status === value}>{text}</option>
		{/each}
	</select>
	<!-- Un bouton plutôt qu'un `onchange` : la console marche sans JavaScript, et c'est ce qui
	     permet de ne mettre aucune logique côté client — donc jamais le jeton. -->
	<button type="submit" class="secondaire">Filtrer</button>
</form>

<FormMessage {form} />

{#if data.hazards.length === 0}
	<p class="vide">Aucun danger ne correspond.</p>
{:else}
	<table>
		<thead>
			<tr>
				<th>Type</th><th>Position</th><th>Gravité</th><th>Statut</th>
				<th>Poids « présent »</th><th>Créé</th><th>Action</th>
			</tr>
		</thead>
		<tbody>
			{#each data.hazards as h (h.id)}
				<tr>
					<td>
						{h.type}
						{#if h.description}
							<br /><small>{h.description}</small>
							<!-- Le texte part, le danger reste : pour une insulte ou un nom sur un
							     signalement par ailleurs fondé. -->
							<form method="POST" action="?/clearDescription" class="action precision">
								<input type="hidden" name="id" value={h.id} />
								<input type="text" name="reason" placeholder="Motif" aria-label="Motif de l'effacement" required size="10" />
								<button type="submit" class="secondaire">Effacer la précision</button>
							</form>
						{/if}
					</td>
					<td class="mono">{h.lat.toFixed(5)}, {h.lng.toFixed(5)}</td>
					<td>{h.severity}</td>
					<td>{statusLabel(h.status)}</td>
					<td>{h.confirm_weight.toFixed(1)} <small>({count(h.events_count, 'geste')})</small></td>
					<td>{shortDate(h.created_at)}</td>
					<td>
						<form method="POST" action="?/moderate" class="action">
							<input type="hidden" name="id" value={h.id} />
							<input type="hidden" name="removed" value={h.status === 'removed' ? 'false' : 'true'} />
							<input type="text" name="reason" placeholder="Motif" aria-label="Motif" required size="14" />
							<button type="submit" class={h.status === 'removed' ? 'secondaire' : 'danger'}>
								{h.status === 'removed' ? 'Rétablir' : 'Retirer'}
							</button>
						</form>
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
	<Pager current={data.page} hasMore={data.hasMore} shown={data.hazards.length} limit={data.limit} />
{/if}

<style>
	.filtres { margin-bottom: 1rem; display: flex; gap: 0.5rem; align-items: center; }
	.action { display: flex; gap: 0.35rem; }
	.precision { margin-top: 0.3rem; }
	small { color: #5a6470; }
</style>
