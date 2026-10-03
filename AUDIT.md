# Audit du code — 15 septembre 2026

> **Suivi au 15 septembre 2026 (soir).** Tout l'audit est traité, sauf ce qui est listé plus
> bas. Appliqué et testé : **C1 à C6**, I2 à I14, I16, I17 (hors spec), I18, M1 à M11, M13,
> M14 et M16 en partie, M17, et S1 à S8 (S5 partiellement, S8 en partie).
>
> Les corrections serveur vivent dans `0110_audit_hardening.sql`. La console est repassée à
> zéro erreur `svelte-check`, avec `attempt()`, `format.js`, `paging.js` et des routes en
> anglais. L'app a gagné `hazard_merge.dart` (C5), `gesture_timer.dart` (I9),
> `gesture_feedback.dart` et `widgets/map_chrome.dart` (S5), plus les premiers tests widget de
> l'écran carte (I18).
>
> | | avant | après |
> |---|---|---|
> | assertions pgTAP | 182 | 262 |
> | tests Flutter | 148 | 199 |
> | erreurs `svelte-check` | 38 | 0 |
>
> **Décisions prises en cours de route.** Le **débannissement est retiré** (I1, D3) : il ne
> rétablissait jamais les dangers, et passé 24 heures il ne remettait plus aucun geste en jeu
> faute de lien — un bouton qui lève le blocage sans rien réparer. Un blocage est désormais
> définitif ; en cas d'erreur, les dangers se rétablissent un par un depuis le journal d'audit,
> et la personne repart d'un identifiant neuf depuis l'écran Paramètres. Le **cache de dangers
> garde ses 45 minutes** (I15) : un danger pris à part ne dit rien de personne, mais la
> sélection de ceux qu'un téléphone a chargés dessine son trajet, exactement comme les tuiles.
> La feuille de téléchargement et `PRIVACY.md` disent maintenant qu'une zone embarquée contient
> les rues, pas les dangers.
>
> **Les décisions D sont tranchées** (`0120_moderation_decisions.sql`, SPEC §6.1 amendé). **D1
> tombe** : `events_one_per_device` ne bloque pas un revote à vie, seulement pendant 24 heures,
> puisque deux `device_id` à `NULL` ne se contredisent pas — le constat lisait l'index sans lire
> son propre `COMMENT`. **D2 est appliqué** : l'auteur ne confirme plus son propre signalement,
> côté serveur, tant que `created_by` existe. **D4 aussi** : un danger résolu quitte la carte,
> `include_resolved` et le calque « résolus récemment » disparaissent, la vue publique et la
> policy s'alignent sur la même définition de « visible ». Au passage, les deux constantes du
> seuil dynamique et son plancher se retrouvent dans `moderation_settings`, une table d'une
> seule ligne, éditable depuis un écran « Règles » de la console : la règle du §6.1 est celle que
> la bêta doit pouvoir corriger sans déploiement, et elle vaut pour tous les types — le plancher
> par type promettait de traiter le verre brisé autrement, et ne faisait que disperser la seule
> décision de modération du produit dans sept lignes de catalogue. Les paliers de proximité du
> §6.2 — 50 m, 500 m et leurs poids — s'éditent au même endroit : c'est la même règle vue par
> l'autre bout, et ces distances n'ont jamais été validées sur un trajet réel.
>
> **Non traité** : M12, laissé de côté ; M14, M16 et S8 en partie ; S5 s'arrête au chrome, au chronomètre et aux retours de geste, sans
> extraire `HazardLayers` ni le suivi de position. Le RPC `admin_upsert_hazard_type` suggéré en
> I4 n'est pas fait : les bornes sont en `CHECK` et la console valide avant d'écrire.
>
> **Trouvé en passant.** `make migrate` échouait sur toute base existante depuis 0100 :
> `proximity_weight` y renommait un paramètre, ce que `CREATE OR REPLACE` refuse. Corrigé dans
> 0030. Et les fonctions appelées par une vue s'exécutent avec les droits du lecteur, pas du
> propriétaire : `st_x`, `st_y` et `current_admin` restent donc accordées, et le test 060 liste
> désormais exactement ce que chaque rôle peut appeler. Enfin, contrairement à ce que le
> constat M4 laissait croire, l'image PostgREST embarque bash : le healthcheck est donc
> possible, et il interroge `/ready` par une socket ouverte à la main.

Lecture seule, sur `de0f9ae`. Trois bases lues en entier : serveur (11 migrations, 11 fichiers de
tests, Compose, Caddy, scripts), console (`admin/src`), app (`app/lib` hors code généré). Chaque
constat a été relu dans le code ; les droits SQL ont été vérifiés sur la base de travail.

État constaté : `flutter analyze` propre, 148 tests Flutter, 182 assertions pgTAP, **`svelte-check`
rouge (38 erreurs)**.

Convention : **C** critique (à corriger avant d'élargir la bêta), **I** important, **M** mineur,
**S** simplification, **D** décision à écrire dans la spec.

---

## Critique

**C1. Un jeton admin lit le lien terminal → gestes, que tout le reste du code cache.**
`server/db/migrations/0070_admin.sql:368` : `GRANT SELECT ON hazards, devices, events TO admin_api`
avec policies `USING (true)`. Vérifié en base : `has_column_privilege('admin_api','hazards','created_by')`
et `('admin_api','events','device_id')` valent `true`. Contredit `0070:337-340`, `0080:11-12`, le
README et le §4.3. `GET /rest/v1/events?select=hazard_id,created_at&device_id=eq.<uuid>` reconstitue
une journée de trajets. La console n'utilise pas ces chemins, mais le jeton n'expire pas.
Cause : vues `admin_hazards`/`admin_devices` en `security_invoker = true`.
→ Passer les vues en droits du propriétaire (retirer `security_invoker`), supprimer la ligne 368,
ajouter dans `070_admin.sql` un test `NOT has_column_privilege(...)` sur ces deux colonnes.

**C2. Désactiver un administrateur n'empêche pas la lecture.**
`admin/src/routes/login/+page.server.js:22` valide le jeton par `GET /admin_devices?limit=1`, une
vue lue sans `current_admin()` (`0070:349-357, 379-380`). Le jeton n'expire jamais
(`admin-token.sh:10`) et la seule révocation documentée est `disabled_at`. Un admin désactivé ou
un jeton fuité continue de lire dangers, terminaux, journal d'audit, e-mails ; seules les actions
échouent. Le commentaire `login:19-20` décrit un comportement qui n'existe pas.
→ RPC `admin_whoami()` (appelle `current_admin()`) accordée à `admin_api`, appelée à la connexion
et dans `hooks.server.js` ; ou policies `USING (current_admin() IS NOT NULL)` sur les vues admin.

**C3. Les erreurs de la console s'affichent comme des succès.**
`+page.svelte:30`, `carte/+page.svelte:181`, `devices/+page.svelte:13`, `types/+page.svelte:19` :
`class:erreur={!!form.status}`. `form` ne contient que `data` (SvelteKit `render.js:100`), aucune
action ne renvoie `status`. Motif trop court, auteur déjà banni, PNG non carré : message en bleu
« ok ». svelte-check le signalait.
→ `page.status >= 400` via `$app/state`, ou renvoyer `{ message, error: true }` depuis un helper
commun (voir S7).

**C4. App : un 5xx pendant le vidage de la file jette les gestes.**
`app/lib/src/data/hazard_repository.dart:543-547` : `_isOffline` ne reconnaît que
`SocketException`, `TimeoutException`, `ClientException` ; la branche `statusCode == null` est
morte (`ApiException` porte toujours un code). Dans `drain()` (`495-500`) tout autre échec →
`_drop` + « refusé ». PostgREST qui redémarre pendant un drain = file perdue, mesure `queueRefused`
faussée. Idem `HandshakeException` (portail captif).
→ Transitoire si `statusCode >= 500 || 408 || 429` ou `IOException` ; test avec un 503.

**C5. App : la carte n'oublie jamais un danger ; le provisoire devient un fantôme.**
`map_screen.dart:313-317` fusionne sans élaguer. Conséquences : (a) un danger retiré par la console
ou résolu par d'autres reste affiché `active` toute la session ; (b) `map_screen.dart:512` ajoute
le provisoire sous son `clientId`, `drain()` le retire de `_provisional` mais pas de `_hazards` →
après retour du réseau, deux marqueurs, le fantôme ne s'ouvre pas. `_rememberArea` (`612-636`) a
le même défaut côté cache drift.
→ Quand la réponse vient du serveur, retirer de `_hazards` (hors provisoires) et du cache les
entrées de la bbox absentes de la réponse ; `DrainReport` expose les `clientId` réglés.

**C6. `report_hazard` sans verrou : danger orphelin et anti-doublon contournable.**
`0100_local_proximity.sql:140-193`. Contrôle d'idempotence, anti-doublon et INSERT sans aucun
verrou (contrairement à `confirm_hazard`). Rejeu concurrent d'un même `client_id` (timeout réseau,
cas nominal du §10) : deux `hazards`, le second `record_event` fait `DO NOTHING` → un point sans
événement `create`. Deux testeurs à la même seconde passent l'anti-doublon.
→ `pg_advisory_xact_lock(hashtext(client_id::text))` en tête, puis un verrou sur cellule de grille
(`hashtext(type || ST_GeoHash(v_geom, 6))`) autour de la section création.

---

## Important

**I1. Débannir après 24 h ne restaure rien.** `anonymize_old_events` (`0050:21-24`) met `device_id`
à NULL sur les événements annulés aussi ; `admin_unban_device` (`0070:273-279`) filtre sur
`device_id` → `events_restored: 0`, `cancelled_at` reste à vie, l'audit dit « débanni ». La base
de travail contient déjà 1 événement annulé orphelin. Le test 070 débannit dans la même
transaction et ne peut pas le voir. → **D** : soit le dire dans le message et le §4.3, soit
`events.cancelled_by REFERENCES admin_actions(id)` et débannir par cette clé. Test
« bannir → anonymiser → débannir ».

**I2. `forget_device` lève le bannissement.** `0050:65` supprime la ligne `devices` ;
`ensure_device` la recrée vierge au geste suivant, **même UUID**. Régénérer l'identifiant contourne
déjà le ban (assumé §11.4), mais ici la trace admin disparaît et `admin_unban_device` journalise
pour un terminal inexistant. → Ne pas supprimer la ligne (elle ne porte que l'UUID), ou la garder
si `banned_at IS NOT NULL`.

**I3. `proximity_tier(geometry, lat, lng)` est un RPC public.** `0100:266`. Un point d'entrée
`anon` qui reçoit des coordonnées de terminal, à rebours du §6.2 amendé. L'app ne l'appelle pas,
mais la porte invite une future version à « laisser le serveur calculer ». → `REVOKE`, et déplacer
la fonction dans `app_test` (S4). Étendre le test 100 à toutes les fonctions `anon`.

**I4. `hazard_types` sans aucun `CHECK`, édité en direct et sans motif.** `0010:14-24` ;
`0070:367` (`INSERT, UPDATE, DELETE`) ; console `types/+page.server.js:36-38` : `Number('')` = 0
accepté, `NaN` → `null` → erreur SQL brute. `min_resolve_votes = 0` ou `dedup_radius_m = 0`
passent. → `CHECK (min_resolve_votes >= 1)`, `CHECK (dedup_radius_m BETWEEN 1 AND 500)`,
`CHECK (default_ttl_days > 0)` ; idéalement un RPC `admin_upsert_hazard_type(jsonb, reason)`
pour respecter « jamais d'écriture directe ».

**I5. `seed-demo.sql` est cassé depuis 0100 et tronque avant d'échouer.** `seed-demo.sql:11`
`TRUNCATE` puis appels à 9/5 arguments (`:40-44, 49-53, 60`) supprimés par `0100:56-59`. Sans
transaction : base de dev vidée. → Signatures à palier, `BEGIN; … ROLLBACK/COMMIT`, jouer dans
`run-tests.sh`.

**I6. Console : un 401 rend la console inutilisable.** Tous les `load` appellent `api()` sans
traiter 401/403 → page 500 ; `hooks.server.js:20-22` renvoie `/login` vers `/` tant que le cookie
existe. Rotation du secret JWT = 500 en boucle, seule issue « Quitter ». → `handleError` ou garde
dans le hook : sur `ApiError` 401/403, supprimer le cookie, rediriger vers `/login`.

**I7. Console : pas de pagination, débannissement impossible hors top 100.** `devices:7`
(`limit=100`, tri activité), `/:11` (100), `audit:9` (200). Un auteur banni depuis la carte avec 2
gestes n'apparaît pas dans `/devices`, donc pas de bouton « Débloquer » — alors que
`carte/+page.svelte:229-230` le promet. → Filtre `?etat=bloques`, tri `banned_at.desc.nullslast`,
`?page=` et indicateur « tronqué » comme sur la carte.

**I8. Console : `api()` sans timeout, erreurs non HTTP et messages SQL bruts.** `lib/api.js:24,34-43`.
`FOR UPDATE` tenu ailleurs = requête bloquée 5 min ; PostgREST down = « fetch failed » affiché ;
23505 (« duplicate key… »), 22P02, PGRST202 remontent en anglais. → `AbortSignal.timeout(10_000)`,
convertir en `ApiError(503)`, lire `code` et traduire les codes qui ne sont pas les nôtres.

**I9. App : la mesure n°1 du §4.6 (« signalement < 15 s ») est polluée.** `map_screen.dart:418`
démarre `_gestureClock` ; `onCancel` (`928`) ne l'annule pas ; `_onMapClick` (`393-412`) entre en
placement sans chrono. Annuler, rouler 10 min, taper la carte, envoyer → 600 s enregistrées ; un
placement par tap direct n'est jamais mesuré. → `_gestureClock = null` dans `onCancel`, démarrer
dans `_onMapClick`.

**I10. App : `drain()` réentrant.** Appelé par le `Timer` 30 s (`hazard_repository.dart:520`), au
`resumed` et au tap du bandeau. Deux boucles sur la même file : la seconde réponse est « déjà
voté » → compté « refusé », message et mesure faux. → `Future<DrainReport>? _draining`.

**I11. App : `_reload` hors d'ordre écrase un état plus récent.** `map_screen.dart:295-325` :
debounce mais aucun jeton de séquence, réponse jusqu'à 15 s. Un geste appliqué puis une vieille
réponse qui remet l'ancien statut. → compteur de séquence, ignorer les réponses périmées.

**I12. App : un 5xx au démarrage bloque l'app malgré le catalogue en cache.**
`hazard_repository.dart:243-249` ne sert le cache que si `_isOffline` ; `app.dart:99-101`
`on Object catch` transforme tout (TypeError de parsing, migration drift) en « Vérifiez votre
connexion ». → Servir le cache pour toute erreur si non vide ; message réseau réservé aux erreurs
réseau.

**I13. App : `covered` peut mentir avec un filtre.** `hazard_repository.dart:278-284` mémorise la
zone quels que soient `types`/`minSeverity`. Filtre « très dangereux » en ligne, hors ligne sans
filtre → `covered = true`, aucun bandeau, « rien d'autre ici » affirmé (§10). → Ne mémoriser la
zone qu'en l'absence de filtre restrictif.

**I14. App : le danger provisoire est actionnable.** `hazard_repository.dart:321-325` sert le
provisoire au détail, `hazard_detail_sheet.dart:160-180` propose les gestes → `confirm_hazard`
sur un `clientId` inconnu du serveur ; hors ligne, mis en file puis « refusé ». → `isProvisional`
sur `HazardDetail`, masquer les gestes.

**I15. Le cache de dangers vit 45 min, la doc dit 24 h, et la « zone hors ligne » n'a pas de dangers.**
`cacheTtl = TraceHorizon.maxAge` (45 min) mais `hazard_repository.dart:54, 638` et
`database.dart:79` disent « 24 h ». Le téléchargement hors ligne (`offline_maps*.dart`) ne
précharge aucun danger : une heure sans réseau sur une zone téléchargée = tuiles mais bandeau
« zone jamais chargée ». Cohérent avec §11.7, pas avec ce que « hors ligne » laisse entendre.
→ **D** : l'écrire dans la feuille de téléchargement et la spec, corriger les commentaires.

**I16. L'onboarding fait une promesse fausse.** `labels.dart:34-35` : « Le GPS n'est lu que quand
vous signalez ou confirmez ». Depuis l'« écart assumé » de `location_service.dart:43-53`, la
position est suivie tant que la carte est affichée. `PRIVACY.md:92` est juste, le libellé non.
→ « Suivie pendant que la carte est affichée, jamais en arrière-plan, jamais enregistrée ».

**I17. Documentation périmée sur la promesse centrale.**
- « la position part dans l'appel RPC » : `location_service.dart:5-7`, `api_client.dart:151-153`
  (cite un `devicePos` inexistant), `0010:61-62`.
- « 90 jours » : `0001:5`, `0010:59`, `0050:28`, `db/Dockerfile:2`, `server/README.md:67`.
- `.env.example:11` : `PGRST_JWT_SECRET` « inutilisé pendant la bêta » — il signe les jetons admin,
  c'est le seul rempart entre Internet et `admin_api`.
- `COMMENT ON TABLE admin_actions` « VIDE pendant la bêta » (`0010:119-121`) **toujours en base**,
  jamais écrasé par 0070. `0010:74-76`, `docker-compose.yml:104` : « console reportée ».
- `server/README.md:25-26, 44-57, 84-93` : « six fonctions », exemple avec `device_lat`, « 145
  assertions ».
- Manifest, `data_extraction_rules.xml:5`, `device_identity.dart:56-57` parlent d'une file sur
  disque (elle est en mémoire).
- `admin/svelte.config.js:7-10` : le commentaire décrit une désactivation ; `checkOrigin: true` est
  la valeur par défaut (dépréciée en Kit 2.70), le vrai correctif est dans `hooks.server.js`.

**I18. Tests absents sur des parties critiques.**
- SQL : `hazards_in_bbox(include_resolved)` et sa fenêtre de 30 j (troisième ligne du §6.1) ;
  rejeu du même `client_id` sur confirm/resolve ; bannir → anonymiser → débannir ; `forget_device`
  sur un banni ; `remove_own_hazard` entre 24 h et 25 h (répond « seul le créateur » au lieu du
  message de délai, `0040:218-225`) ; palier 2 via RPC ; bornes de `hazard_types`.
- App : `map_screen.dart` (1178 l.) n'a **aucun** test widget ; `LocationService` (fraîcheur 60 s,
  `forget`), `DeviceIdentity`, `_isOffline` hors 400, `drain()` concurrent, migration drift 1→3,
  `confirmHazard`/`markResolved`/`forgetDevice` au niveau HTTP.
- Console : `svelte-check` 38 erreurs (`@types/node` absent, `locals.token` `string | undefined`,
  `any` implicites) — tant qu'il est rouge il ne protège de rien (C3 en faisait partie).

---

## Mineur

- **M1** `0100:163-185` : `lat`/`lng`/`device_id`/`client_id` NULL ou hors bornes → erreurs
  PostGIS/23502 brutes. Valider en tête avec `check_violation`.
- **M2** Caddy : aucun `request_body max_size` sur `/rest/v1/*` ; domaine admin sans HSTS,
  `nosniff`, `Cache-Control: no-store`, CSP. Console : `BODY_SIZE_LIMIT` (512 Ko par défaut) non
  posé, un PNG de 800 Ko donne une 413 en anglais avant l'action.
- **M3** `Makefile:19` : `make up` ne démarre pas `admin` → 502 sur `ADMIN_DOMAIN`.
- **M4** Compose : `rest` sans healthcheck, `go-pmtiles:latest` non épinglé, pas de rotation des
  logs Docker (les `RAISE EXCEPTION` y vont).
- **M5** Index manquants `events(device_id)`, `hazards(created_by)` : `admin_devices` fait trois
  sous-requêtes corrélées par ligne, `forget_device`/ban filtrent dessus.
- **M6** `anonymize_old_events` ignore `photos.device_id` alors que `forget_device` le traite.
- **M7** `hazard_detail.timeline` et `reported_remotely` (`0040:31-34, 294-299`) ignorent
  `cancelled_at` : après un ban, la chronologie publique compte des gestes annulés.
- **M8** Fonctions admin : `admin_set_hazard_removed(id, NULL, …)` rétablit (CASE sur NULL) ;
  `admin_ban_device` sans garde « déjà banni » ; `admin_unban_device` et `admin_clear_hazard_icon`
  journalisent avant de vérifier la cible.
- **M9** `admin_actions` append-only seulement par les grants : un trigger `BEFORE UPDATE OR
  DELETE … RAISE` protège aussi de Studio (superuser).
- **M10** PostGIS installé dans `public` : **798 fonctions** exécutables par `anon` via `/rpc/st_*`
  (OpenAPI énorme, surface inutile).
- **M11** `hazards_in_bbox` : `LIMIT 5000` sans `ORDER BY` ni indicateur de troncature.
- **M12** PNG : type de couleur non vérifié (`0090:24-37`) ; un RGB opaque donne un carré plein.
- **M13** `run-tests.sh` ne crée que `anon` ; `0070:29` `GRANT admin_api TO authenticator` casse
  sur un cluster nu (CI). Migrations jouées sans `--single-transaction`. `admin-token.sh:35`
  interpole l'e-mail dans le SQL. `admins.email` non `UNIQUE` alors que la révocation documentée
  est `WHERE email = …`.
- **M14** App : `marker_icons.dart:146` `bytes!` ; `setState` après `await` sans `mounted`
  (`map_screen.dart:282, 556`) ; `_regenerate` sans `finally` (`settings_screen.dart:149-165`) ;
  `offline_maps.dart:123-148` `Completer` sans timeout ni annulation ; `map_screen.dart:688` met à
  jour `_hazards` sans `_pushToMap`, `986` vide puis `_reload` retourne tôt sous le zoom 11.
- **M15** App : les `Error` (TypeError de `fromJson`) traversent tous les `on Exception` ; dans
  `_reload` lancé par `Timer` → erreur asynchrone silencieuse, carte figée.
- **M16** App : `provisional.resolveThreshold = 1` (serveur : 2) ; `types()` fait trois
  allers-retours séquentiels ; `_rememberArea` fait 4 écritures SQLite par `onCameraIdle`.
- **M17** Console : `?statut=foo` → 500 (enum invalide) ; dates SSR en UTC puis réécrites (pas de
  `TZ`) ; `type.icon.set/clear` non libellés dans le journal ; « active → removed » en anglais ;
  champs « Motif » sans label accessible ; `enregistrer` réussit sur 0 ligne (pas de
  `Prefer: return=representation`) ; `icon` non éditable après création ; identifiants en français
  (`moderer`, `LIMITE`, `/carte`) à rebours de la convention.

### Décisions à écrire (D)

- **D1** `events_one_per_device (hazard, device, type)` : après un « toujours là » qui remet le
  poids à zéro, un terminal ayant voté « résolu » ne peut **plus jamais** revoter sur ce danger
  (`ON CONFLICT DO NOTHING` silencieux, `hazard_json` renvoyé comme si accepté). Non tranché par
  §6.1, non testé.
- **D2** Le créateur peut confirmer son propre danger : `create` + `confirm` = 2 confirmations.
- **D3** Débannissement après 24 h (I1) ; cache 45 min et zones hors ligne (I15).
- **D4** `hazards`/`hazards_public` servent les `resolved` sans limite, la carte les borne à 30 j :
  deux définitions de « visible ».

---

## Simplifications

- **S1** Trigger `events_recompute` en `AFTER INSERT OR DELETE OR UPDATE OF cancelled_at, weight`
  : `anonymize_old_events` recalcule aujourd'hui chaque danger touché **par événement**, toutes les
  heures, pour un changement de `device_id` sans effet ; et les boucles `PERFORM recompute_hazard`
  de `admin_ban_device`/`admin_unban_device` doublent le trigger (le commentaire `0070:243-247`
  est faux).
- **S2** `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` dans
  0060 : fermer par défaut au lieu de révoquer une à une (c'est ce qui a laissé passer I3).
- **S3** Vues admin en `security_invoker = false` : résout C1 en une ligne.
- **S4** `proximity_tier` dans `app_test` : hors du schéma public, hors OpenAPI, résout I3.
- **S5** Découper `map_screen.dart` (1178 l.) : `HazardLayers` (sources/couches/images, ~115 l.),
  suivi de position, retours de geste en fonctions pures (`_sansPosition`, `_feedbackFor`),
  widgets de chrome (`_TopBanner`, `_PlacementBar`, `_RoundButton`, ~155 l.), `GestureTimer`
  (corrige I9).
- **S6** `_PendingAction` en `sealed class` typée : supprime `kind` en `String`, le reparsing de
  `payload` et le `throw ArgumentError` de `_call`.
- **S7** Console : un helper `attempt(fn)` pour le motif `try / rpc / fail` répété 7 fois ;
  `$lib/format.js` pour statuts et dates (dupliqués liste/carte) ; `load` et filtre de statut
  partagés entre `/` et `/carte`.
- **S8** App : paramètres morts `HazardDetailSheet.busy`, `ReportSheet.address` ; deux
  `FlutterSecureStorage` identiques ; `relativeDate` dans `theme.dart`.

---

## Points forts

1. **Discipline `SECURITY DEFINER`** : `search_path` fixé partout, internes révoquées, et
   `060_privacy.sql` vérifie structurellement ce qu'`anon` ne peut ni lire ni appeler, y compris le
   contournement par `hazard_json`.
2. **Le journal est vraiment la source de vérité** : `recompute_hazard` est une fonction pure de
   `events`, le retour à `active` se fait par comparaison d'`id` sans effacer, et `040_resolve.sql`
   le prouve en écrasant les compteurs puis en recalculant.
3. **La position ne quitte réellement jamais l'appareil**, et c'est verrouillé par des tests des
   deux côtés (`api_client_test`, `hazard_repository_test`, `100_local_proximity.sql`) ; le jeton
   admin ne touche jamais le navigateur ; la contrainte F-Droid est tenue en profondeur (canal
   natif `LocationManager`, `exclude(com.google.android.gms)` en Gradle).

## Ordre suggéré

1. C1 + S3 (une migration, un test) ; I3 + S4 ; C2 (`admin_whoami`).
2. C3, I6, I8 côté console, en passant par S7 et un `svelte-check` vert.
3. C4, C5, I10, I11 dans l'app, avec les premiers tests widget de `map_screen`.
4. C6, I4, I5, I1/I2 (après décision D3).
5. I9, I13, I14, I16, puis la passe de documentation I17.
