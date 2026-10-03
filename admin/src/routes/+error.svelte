<script>
	import { page } from '$app/state';
</script>

<h1>Indisponible</h1>
<p class="erreur">{page.error?.message ?? 'Erreur inattendue.'}</p>
<p class="note">
	Code {page.status}. Si le serveur ne répond pas, rien n'a été modifié : rechargez la page
	dans un instant. Si le problème persiste, vérifiez que PostgREST tourne (<code>make logs</code>).
</p>
<p><a href="/">Retour aux dangers</a></p>
