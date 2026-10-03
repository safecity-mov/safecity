<script>
	import { page } from '$app/state';

	let { form } = $props();

	const revoked = $derived(page.url.searchParams.get('reason') === 'revoked');
</script>

<main class="login">
	<h1>L'application</h1>
	<p class="lead">Console de modération.</p>

	{#if revoked}
		<p class="error" role="alert">
			Votre jeton n'est plus accepté : administrateur désactivé, ou secret du serveur changé.
			Demandez-en un nouveau.
		</p>
	{/if}

	<form method="POST">
		<label for="token">Jeton d'administration</label>
		<textarea id="token" name="token" rows="4" required autocomplete="off"
			placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9…"></textarea>
		<p class="hint">Obtenu sur le serveur par <code>make admin-add EMAIL=…</code>.</p>
		{#if form?.message}<p class="error" role="alert">{form.message}</p>{/if}
		<button type="submit">Entrer</button>
	</form>
</main>

<style>
	.login { max-width: 32rem; margin: 4rem auto; padding: 0 1.5rem; }
	h1 { margin-bottom: 0.25rem; }
	.lead { color: #5a6470; margin-top: 0; }
	label { display: block; font-weight: 600; margin-bottom: 0.5rem; }
	textarea { width: 100%; font-family: ui-monospace, monospace; font-size: 0.85rem; padding: 0.6rem; }
	.hint { color: #5a6470; font-size: 0.85rem; }
	.error { color: #a4161a; font-weight: 600; }
</style>
