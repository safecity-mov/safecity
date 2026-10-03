<script>
	import { page } from '$app/state';
	import { pageHref } from '$lib/paging.js';

	/**
	 * Précédent / suivant, sans compte total : on sait seulement s'il y a une suite.
	 * @type {{ current: number, hasMore: boolean, shown: number, limit: number }}
	 */
	let { current, hasMore, shown, limit } = $props();
</script>

{#if current > 1 || hasMore}
	<nav class="pager" aria-label="Pages">
		{#if current > 1}
			<a href={pageHref(page.url, current - 1)}>← Précédent</a>
		{/if}
		<span>Page {current}, {shown} sur {limit} par page</span>
		{#if hasMore}
			<a href={pageHref(page.url, current + 1)}>Suivant →</a>
		{/if}
	</nav>
{/if}

<style>
	.pager { display: flex; gap: 1rem; align-items: center; margin: 1rem 0; font-size: 0.85rem; color: #5a6470; }
	.pager a { color: #1f5673; }
</style>
