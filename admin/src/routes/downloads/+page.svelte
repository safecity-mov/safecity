<script>
	import { count } from '$lib/format.js';
	import { LAST, timeOf, zone } from '$lib/downloads.js';

	let { data } = $props();
	const r = $derived(data.report);
	const b = $derived(data.blocked);
</script>

<h1>Téléchargements de l'APK</h1>
<p class="note">
	Ce que le serveur a servi depuis la page de téléchargement : un téléchargement complet par
	ligne, les reprises par morceaux comptées à part. Heure, fichier et langue annoncée par le
	navigateur, qui tient lieu de pays ; jamais d'adresse, elle n'est pas dans le journal. Les
	mises à jour par F-Droid n'y figurent pas.
</p>

{#if r.total === 0}
	<p class="vide">Aucun téléchargement pour l'instant.</p>
{:else}
	<div class="colonnes">
		<section>
			<h2>Par fichier</h2>
			<table>
				<thead><tr><th>Fichier</th><th class="n">Téléchargements</th><th class="n">Reprises</th></tr></thead>
				<tbody>
					{#each r.byFile as row (row.label)}
						<tr><td class="mono">{row.label}</td><td class="n">{row.n}</td><td class="n">{row.resumed || ''}</td></tr>
					{/each}
					<tr class="total"><td>au total</td><td class="n">{r.total}</td><td></td></tr>
				</tbody>
			</table>
		</section>

		<section>
			<h2>Par langue du navigateur</h2>
			<table>
				<thead><tr><th>Langue</th><th class="n">Téléchargements</th></tr></thead>
				<tbody>
					{#each r.byLanguage as row (row.label)}
						<tr><td>{row.label}</td><td class="n">{row.n}</td></tr>
					{/each}
				</tbody>
			</table>
		</section>

		<section>
			<h2>Par jour <small>(heure de Paris)</small></h2>
			<table>
				<thead><tr><th>Jour</th><th class="n">Téléchargements</th></tr></thead>
				<tbody>
					{#each r.byDay as row (row.label)}
						<tr><td>{row.label}</td><td class="n">{row.n}</td></tr>
					{/each}
				</tbody>
			</table>
		</section>
	</div>

	<section>
		<h2>Les {Math.min(LAST, r.total)} derniers</h2>
		<table>
			<thead><tr><th>Quand</th><th>Langue</th><th>Fichier</th></tr></thead>
			<tbody>
				{#each r.last as hit, i (i)}
					<tr><td>{timeOf(hit.when)}</td><td>{hit.language}</td><td class="mono">{hit.file}</td></tr>
				{/each}
			</tbody>
		</table>
	</section>

{/if}

<h1 class="second">Blocages</h1>
<p class="note">
	Ce que la limitation de débit a refusé : au-delà de 300 requêtes par minute sur l'API ou de
	60 par heure sur les fichiers APK, depuis une même adresse, le serveur répond « trop de
	demandes » sans rien traiter. Ici l'heure et le chemin, jamais l'adresse : on sait que la
	limite a servi, pas si c'est une personne qui insiste ou cent.
</p>

{#if b.total === 0}
	<p class="vide">Aucun blocage pour l'instant.</p>
{:else}
	<div class="colonnes">
		<section>
			<h2>Par zone</h2>
			<table>
				<thead><tr><th>Zone</th><th class="n">Refus</th></tr></thead>
				<tbody>
					{#each b.byZone as row (row.label)}
						<tr><td>{row.label}</td><td class="n">{row.n}</td></tr>
					{/each}
					<tr class="total"><td>au total</td><td class="n">{b.total}</td></tr>
				</tbody>
			</table>
		</section>
		<section>
			<h2>Par jour <small>(heure de Paris)</small></h2>
			<table>
				<thead><tr><th>Jour</th><th class="n">Refus</th></tr></thead>
				<tbody>
					{#each b.byDay as row (row.label)}
						<tr><td>{row.label}</td><td class="n">{row.n}</td></tr>
					{/each}
				</tbody>
			</table>
		</section>
	</div>
	<section>
		<h2>Les {Math.min(LAST, b.total)} derniers</h2>
		<table>
			<thead><tr><th>Quand</th><th>Zone</th><th>Chemin</th></tr></thead>
			<tbody>
				{#each b.last as hit, i (i)}
					<tr><td>{timeOf(hit.when)}</td><td>{zone(hit.path)}</td><td class="mono">{hit.path}</td></tr>
				{/each}
			</tbody>
		</table>
	</section>
{/if}

<p class="note"><small>{count(data.files, 'fichier de journal', 'fichiers de journal')} lu(s).</small></p>

<style>
	.colonnes { display: flex; flex-wrap: wrap; gap: 1.5rem; align-items: flex-start; }
	.colonnes section { flex: 1 1 16rem; }
	h1.second { margin-top: 2rem; }
	h2 { font-size: 1rem; margin: 0.6rem 0 0.4rem; }
	h2 small { color: #5a6470; font-weight: normal; }
	.n { text-align: right; }
	.total td { font-weight: 600; border-top: 2px solid #c8cdd4; }
</style>
