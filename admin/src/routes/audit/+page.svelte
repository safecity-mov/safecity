<script>
	import Pager from '$lib/Pager.svelte';
	import { ACTION_LABELS, longDate } from '$lib/format.js';

	let { data } = $props();
</script>

<h1>Journal d'audit</h1>
<p class="note">
	Toute action passée par cette console, avec son motif. En écriture seule, y compris pour un
	administrateur : la base ne lui accorde que la lecture, et refuse toute modification. Ce qui
	est fait directement en SQL, lui, n'apparaît pas ici.
</p>

{#if data.actions.length === 0}
	<p class="vide">Aucune action pour l'instant.</p>
{:else}
	<table>
		<thead>
			<tr><th>Quand</th><th>Qui</th><th>Quoi</th><th>Sur</th><th>Motif</th></tr>
		</thead>
		<tbody>
			{#each data.actions as a (a.id)}
				<tr>
					<td>{longDate(a.created_at)}</td>
					<td>{data.byId[a.admin_id] ?? a.admin_id}</td>
					<td>{ACTION_LABELS[a.action] ?? a.action}</td>
					<td class="mono">{a.target}</td>
					<td>
						{a.reason}
						{#if a.snapshot?.hazards_removed?.length}
							<br /><small>{a.snapshot.hazards_removed.length} signalement(s) retiré(s)</small>
						{/if}
						<!-- Le texte effacé d'un danger : c'est ici, et seulement ici, qu'il survit.
						     Le montrer est ce qui permet de juger l'effacement après coup. -->
						{#if a.snapshot?.description_before}
							<br /><small class="efface">« {a.snapshot.description_before} »</small>
						{/if}
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
	<Pager current={data.page} hasMore={data.hasMore} shown={data.actions.length} limit={data.limit} />
{/if}

<style>
	small { color: #5a6470; }
	.efface { text-decoration: line-through; text-decoration-color: #a4161a; }
</style>
