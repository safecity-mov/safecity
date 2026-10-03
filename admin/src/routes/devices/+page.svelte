<script>
	import FormMessage from '$lib/FormMessage.svelte';
	import Pager from '$lib/Pager.svelte';
	import { shortDate } from '$lib/format.js';

	let { data, form } = $props();
</script>

<h1>Terminaux</h1>
<p class="note">
	Bloquer refuse les écritures du terminal, annule tous ses gestes et retire ses signalements.
	Rien n'est supprimé : le journal reste entier, et les compteurs se recalculent sans lui.
</p>
<p class="note">
	<strong>Un blocage est définitif.</strong> Il n'y a pas de déblocage : il ne rétablissait
	jamais les signalements retirés, et passé 24 heures il ne remettait plus aucun geste en jeu
	non plus, le lien entre un terminal et ses gestes étant coupé entre-temps. En cas d'erreur,
	rétablissez les dangers un par un depuis l'onglet Dangers ; la personne, elle, repart d'un
	identifiant neuf depuis l'écran Paramètres de l'application.
</p>

<form method="GET" class="filtres">
	<label for="state">Afficher</label>
	<select id="state" name="state">
		<option value="" selected={data.state === ''}>tous, bloqués d'abord</option>
		<option value="banned" selected={data.state === 'banned'}>bloqués seulement</option>
		<option value="suspects" selected={data.state === 'suspects'}>actifs ces 24 h, à contre-courant d'abord</option>
	</select>
	<button type="submit" class="secondaire">Filtrer</button>
</form>

{#if data.state === 'suspects'}
	<p class="note">
		Un <strong>saut impossible</strong>, c'est deux gestes déclarés « sur place » que nulle
		vitesse terrestre ne relie : dire qu'on était à moins de cent mètres d'un danger à
		Montmartre, puis d'un autre à Ivry quatre-vingt-dix secondes plus tard. Le calcul ne lit
		que la position des <strong>dangers</strong> et l'heure des gestes, jamais celle de
		personne (§11.1) ; la vitesse affichée est à vol d'oiseau, et le seuil de 50 km/h laisse
		donc passer près de 70 km/h de trajet réel — la marche, le vélo, le métro et le RER sont largement
		en dessous. La liste se trie là-dessus d'abord : c'est de l'arithmétique et non un
		jugement sur l'avis des autres.
	</p>
	<p class="note">
		<strong>Un saut ne dit pas qu'un signalement est faux</strong>, il dit que le terminal ne
		tourne pas l'application telle qu'elle est publiée — un émulateur, une position
		simulée. Ce peut être un sabotage ; ce peut aussi être quelqu'un qui simule sa position
		par souci de vie privée, et ses signalements restent bons. D'où cet écran plutôt qu'un
		refus automatique : c'est vous qui tranchez, avec un motif.
	</p>
	<p class="note">
		Un avis, c'est « le danger est là » (créer, confirmer) ou « il n'y est plus » (résolu).
		Un « résolu » est <strong>infirmé</strong> quand quelqu'un d'autre passe ensuite et
		confirme que le danger est toujours là : un nid-de-poule ne réapparaît pas, c'est le plus
		sûr des signaux tirés de la carte. Un avis est <strong>contredit</strong> quand au moins
		deux autres personnes disent le contraire et qu'elles sont plus nombreuses que son camp,
		lui compris ; une égalité ne contredit personne. Une personne, une voix par danger : deux
		avis de la même personne n'en font pas un collectif. Beaucoup de gestes et beaucoup de
		contredits, c'est le portrait d'un saboteur ; un seul contredit, c'est peut-être un
		nid-de-poule rebouché. Passé 24 heures sans geste, le terminal sort de cette liste : le
		lien avec ses gestes est effacé.
	</p>
{/if}

<FormMessage {form} />

{#if data.devices.length === 0}
	<p class="vide">Aucun terminal ne correspond.</p>
{:else if data.state === 'suspects'}
	<table>
		<thead>
			<tr><th>Identifiant</th><th>Dernier geste</th><th>Gestes</th><th>Sauts impossibles</th><th>Résolus infirmés</th><th>Avis contredits</th><th>État</th><th>Action</th></tr>
		</thead>
		<tbody>
			{#each data.devices as d (d.id)}
				<tr class:banni={d.banned_at} class:suspect={!d.banned_at && (d.jumps >= 1 || d.refuted >= 1 || d.contradicted >= 2)}>
					<td class="mono">{d.id}</td>
					<td>{shortDate(d.last_seen_at)}</td>
					<td>{d.gestures}</td>
					<td class:fort={d.jumps >= 1}>
						{d.jumps}
						{#if d.jumps > 0}<small> ({Math.round(d.top_kmh)} km/h)</small>{/if}
					</td>
					<td class:fort={d.refuted >= 1}>{d.refuted}</td>
					<td>
						{d.contradicted} sur {d.opinions}
						{#if d.opinions > 0}<small> ({Math.round(d.contradiction_rate * 100)} %)</small>{/if}
					</td>
					<td>{d.banned_at ? `bloqué le ${shortDate(d.banned_at)}` : 'actif'}</td>
					<td>
						{#if d.banned_at}
							<span class="definitif">définitif</span>
						{:else}
							<form method="POST" action="?/ban" class="action">
								<input type="hidden" name="device_id" value={d.id} />
								<input type="text" name="reason" placeholder="Motif" aria-label="Motif" required size="14" />
								<button type="submit" class="danger">Bloquer</button>
							</form>
						{/if}
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
	<Pager current={data.page} hasMore={data.hasMore} shown={data.devices.length} limit={data.limit} />
{:else}
	<table>
		<thead>
			<tr><th>Identifiant</th><th>Vu depuis</th><th>Gestes</th><th>État</th><th>Action</th></tr>
		</thead>
		<tbody>
			{#each data.devices as d (d.id)}
				<tr class:banni={d.banned_at}>
					<td class="mono">{d.id}</td>
					<td>{shortDate(d.created_at)}</td>
					<td>
						{d.events_count}
						{#if d.events_cancelled > 0}<small> dont {d.events_cancelled} annulé(s)</small>{/if}
						<br /><small>{d.hazards_created} signalement(s)</small>
					</td>
					<td>{d.banned_at ? `bloqué le ${shortDate(d.banned_at)}` : 'actif'}</td>
					<td>
						{#if d.banned_at}
							<!-- Pas de bouton : le blocage ne se défait pas. Une case grisée dit
							     mieux qu'un bouton désactivé que ce n'est pas une permission
							     manquante, mais qu'il n'y a rien à faire ici. -->
							<span class="definitif">définitif</span>
						{:else}
							<form method="POST" action="?/ban" class="action">
								<input type="hidden" name="device_id" value={d.id} />
								<input type="text" name="reason" placeholder="Motif" aria-label="Motif" required size="14" />
								<button type="submit" class="danger">Bloquer</button>
							</form>
						{/if}
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
	<Pager current={data.page} hasMore={data.hasMore} shown={data.devices.length} limit={data.limit} />
{/if}

<style>
	.filtres { margin-bottom: 1rem; display: flex; gap: 0.5rem; align-items: center; }
	.action { display: flex; gap: 0.35rem; }
	tr.banni { background: #fdf1f1; }
	tr.suspect { background: #fff6e5; }
	.fort { color: #a4161a; font-weight: 600; }
	.definitif { color: #8a8f97; font-size: 0.85rem; font-style: italic; }
	small { color: #5a6470; }
	.note strong { color: #1b1f24; }
</style>
