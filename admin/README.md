# L'application — console d'administration

SvelteKit, `adapter-node`. Licence : **AGPL-3.0**, comme le reste des surfaces serveur
(SPEC §12.1).

Cinq actions, celles du §4.3 avancées pour la bêta : **retirer un danger**, qui est
réversible ; **effacer sa précision**, le texte libre, sans toucher au danger ; **bannir un terminal**, qui ne l'est pas, depuis un danger sans jamais voir son
auteur ou depuis la liste des terminaux, que l'on peut trier par sauts géographiquement
impossibles — deux « sur place » que nulle vitesse terrestre ne relie — puis par avis
contredits par le collectif, pour repérer un saboteur sans relier un identifiant à un
danger ; **gérer le
catalogue des types** et leurs icônes, celles de l'app étant là d'office, les autres choisies
parmi les glyphes Material Symbols ou téléversées en PNG ;
**régler les seuils de résolution** du §6.1 et les paliers de proximité du §6.2, les mêmes
pour tous les types. Plus les **téléchargements de l'APK**, comptés depuis le journal de Caddy, sans adresse, et le **journal d'audit**, en lecture seule — les réglages y entrent
comme le reste.

## Lancer en développement

Le serveur doit tourner (`cd ../server && make up`).

```sh
npm install
APP_API=http://127.0.0.1:8080/rest/v1 ORIGIN=http://localhost:5173 npm run dev
```

Puis obtenir un jeton et le coller dans l'écran de connexion :

```sh
cd ../server && make admin-add EMAIL=vous@example.org
```

`npm run check` (svelte-check) doit rester à zéro erreur : c'est lui qui avait vu que les
erreurs des actions s'affichaient comme des succès, et personne ne le lisait.

## Trois partis pris

**Le jeton ne touche jamais le navigateur.** Il est rangé dans un cookie `httpOnly`,
`SameSite=Strict`, que seul ce serveur lit ; tous les appels à PostgREST partent du serveur.
Un jeton dans du JavaScript serait lisible par la moindre extension. Conséquence assumée :
aucune interactivité côté client, chaque geste est un aller-retour. Pour trois écrans de
modération, c'est le bon échange — la console fonctionne d'ailleurs sans JavaScript du tout,
à deux exceptions près : la carte, et la grille de glyphes Material Symbols de l'écran Types,
qui peint la silhouette sur un canevas avant de l'envoyer par le même formulaire qu'un PNG.

**Le jeton est l'authentification, et il est vérifié à chaque requête.** Pas d'écran de mot
de passe : il est délivré à la main sur la machine qui héberge, ce qui fait de l'accès SSH le
vrai facteur. Il n'expire pas ; en échange, `hooks.server.js` demande à la base
(`admin_whoami()`) qui il est **à chaque page**. Un administrateur désactivé, ou un secret JWT
changé, est renvoyé à l'écran de connexion au clic suivant. Proportionné à trois comptes entre
gens qui se connaissent (§4.3), insuffisant pour l'ouverture, où il faudra de vrais comptes et
un second facteur.

**La console ne décide de rien.** Elle appelle des fonctions SQL qui appliquent les règles et
journalisent dans la même transaction. Le motif obligatoire, le refus d'une action sans motif,
l'annulation des événements plutôt que leur suppression, les bornes du catalogue : tout cela
vit en base, et resterait vrai si quelqu'un appelait l'API à la main. La console est une
façade, et elle doit le rester.

## Comment c'est rangé

- `src/lib/api.js` — l'accès à PostgREST : jeton, délai de 10 s, erreurs traduites quand ce
  n'est pas nous qui avons écrit le message (les exceptions de nos fonctions SQL sont déjà en
  français et passent telles quelles).
- `src/lib/actions.js` — `attempt()`, le motif « essayer, rendre un message, ou échouer »
  commun à toutes les actions ; les actions partagées par la liste et la carte ; le `load`
  qu'elles partagent aussi.
- `src/lib/format.js`, `paging.js` — libellés des statuts et du journal, dates en heure de
  Paris, pagination par `?page=`.
- `src/lib/glyphs.js`, `silhouette.js`, `GlyphPicker.svelte` — les glyphes Material Symbols
  proposés comme icône de type. Deux paquets du même générateur, Apache-2.0, servis par cette
  origine et jamais par Google : `@material-symbols/font-400` pour la liste des noms et la
  police de la grille, `@material-symbols/svg-400` pour les tracés, servis par
  `src/routes/types/glyph/` et que le navigateur peint en silhouette PNG. La base valide le
  résultat comme un fichier téléversé. La recherche porte aussi sur les mots-clés de Google
  (`src/lib/glyph-tags.json`, commité, écrit par `npm run glyph-tags` à relancer quand le
  paquet change de version) : la console ne contacte jamais Google à l'exécution.
- `src/routes/` — un écran par dossier : `/` dangers, `/map` carte, `/devices` terminaux
  (filtre `?state=banned`), `/types` catalogue et icônes (`/types/glyph/<nom>` sert les tracés
  SVG au canevas), `/rules` seuils et paliers,
  `/audit` journal, `/login`.

Les identifiants de code sont en anglais et les libellés en français, comme partout ailleurs.

## Ce qu'il faut savoir avant de déployer

**`ORIGIN`, ou `PROTOCOL_HEADER` + `HOST_HEADER`, sont obligatoires.** `adapter-node` refuse
les POST dont l'origine ne correspond pas à celle qu'il croit servir, et sans cela il se
trompe : tout formulaire renvoie « Cross-site POST form submissions are forbidden ». Symptôme
déroutant, cause triviale. `docker-compose.yml` pose les deux en-têtes.

**`BODY_SIZE_LIMIT` est à 256 Ko** dans Compose : le plus gros corps légitime est une icône de
64 Ko dans un formulaire. Au-delà, `adapter-node` répond 413 avant l'action.

**Les tracés Material Symbols sont lus sur le disque à l'exécution**, dans
`node_modules/@material-symbols/svg-400/outlined` (près de huit mille petits fichiers, un ou
deux servent par choix d'icône, donc pas empaquetés). Le Dockerfile retire les familles
arrondie et anguleuse de l'image ; `GLYPH_DIR` permet de ranger le dossier ailleurs.

**La Content-Security-Policy est émise par SvelteKit** (`svelte.config.js`), avec un nonce par
réponse. Tout vient de cette origine : si un jour la carte s'affiche blanche, vérifier d'abord
que MapLibre trouve son worker (`worker-src`) et ses tuiles (`connect-src`) dans la console du
navigateur.

**L'avis npm sur `cookie` est laissé tel quel.** Il concerne des caractères hors bornes dans
un nom de cookie ; le nôtre est une constante du code. Le correctif proposé rétrograderait
SvelteKit en 0.0.30.

## Ce qui n'est délibérément pas là

- **La file de modération** (§4.3) : rien ne l'alimente tant qu'il n'y a pas de signalement
  d'abus, reporté en phase 2.
- **La purge irréversible** : sans photos ni contenu libre abondant, `removed` suffit. Elle
  reste spécifiée pour l'ouverture.
- **`created_by`** n'est exposé nulle part, même ici : modérer ne demande pas de savoir qui a
  signalé quoi (§11), et le rôle `admin_api` n'a d'ailleurs aucun droit sur les tables qui
  portent ce lien. Bannir se fait depuis le danger ; c'est le serveur qui remonte à l'auteur.
