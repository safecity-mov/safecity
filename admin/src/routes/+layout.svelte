<script>
	import { page } from '$app/state';

	let { data, children } = $props();

	const tabs = [
		{ href: '/', label: 'Dangers' },
		{ href: '/map', label: 'Carte' },
		{ href: '/devices', label: 'Terminaux' },
		{ href: '/types', label: 'Types' },
		{ href: '/rules', label: 'Règles' },
		{ href: '/announcements', label: 'Annonces' },
		{ href: '/audit', label: 'Journal' },
		{ href: '/downloads', label: 'Téléchargements' }
	];
</script>

{#if page.url.pathname !== '/login'}
	<header>
		<nav>
			<strong>L'application</strong>
			{#each tabs as tab (tab.href)}
				<a href={tab.href} class:actif={page.url.pathname === tab.href}>{tab.label}</a>
			{/each}
			<span class="qui" title="Administrateur reconnu par la base pour ce jeton">{data.email}</span>
			<form method="POST" action="/?/logout" class="sortie">
				<button type="submit">Quitter</button>
			</form>
		</nav>
	</header>
{/if}

<main>
	{@render children()}
</main>

<style>
	:global(body) {
		margin: 0;
		font-family: system-ui, -apple-system, sans-serif;
		color: #1b1f24;
		background: #f7f8fa;
	}
	:global(h1) { font-size: 1.4rem; }
	:global(table) { width: 100%; border-collapse: collapse; background: #fff; }
	:global(th) { text-align: left; font-size: 0.75rem; text-transform: uppercase; color: #5a6470; }
	:global(th), :global(td) { padding: 0.6rem 0.75rem; border-bottom: 1px solid #e6e9ee; vertical-align: top; }
	:global(td.mono) { font-family: ui-monospace, monospace; font-size: 0.8rem; }
	:global(button) {
		font: inherit; padding: 0.4rem 0.8rem; border: 1px solid #1f5673;
		background: #1f5673; color: #fff; border-radius: 6px; cursor: pointer;
	}
	:global(button.secondaire) { background: #fff; color: #1f5673; }
	:global(button.danger) { background: #a4161a; border-color: #a4161a; }
	:global(input[type='text']), :global(input[type='number']) {
		font: inherit; padding: 0.35rem 0.5rem; border: 1px solid #c8cdd4; border-radius: 6px;
	}
	:global(.erreur) { color: #a4161a; font-weight: 600; }
	:global(.ok) { color: #1f5673; font-weight: 600; }
	:global(.vide) { color: #5a6470; padding: 2rem 0; }
	:global(.note) { color: #5a6470; max-width: 48rem; }

	header { background: #1f5673; }
	nav { display: flex; align-items: center; gap: 1.25rem; padding: 0.75rem 1.5rem; max-width: 72rem; margin: 0 auto; }
	nav strong { color: #fff; margin-right: 0.5rem; }
	nav a { color: #cfe0ea; text-decoration: none; font-size: 0.95rem; }
	nav a.actif { color: #fff; font-weight: 600; }
	.qui { margin-left: auto; color: #cfe0ea; font-size: 0.8rem; }
	.sortie button { background: transparent; border-color: #cfe0ea; color: #cfe0ea; }
	main { max-width: 72rem; margin: 0 auto; padding: 1.5rem; }
</style>
