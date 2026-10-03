<script>
	/**
	 * Le retour d'une action : rouge si elle a échoué, bleu sinon. C'est `error`, posé par
	 * `attempt()`, qui tranche — pas un `status` que SvelteKit ne transmet pas au formulaire.
	 * @type {{ form: { message?: string, error?: boolean } | null | undefined }}
	 */
	let { form } = $props();
</script>

{#if form?.message}
	<p class:erreur={form.error} class:ok={!form.error} role={form.error ? 'alert' : 'status'}>
		{form.message}
	</p>
{/if}
