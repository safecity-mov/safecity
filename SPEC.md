# L'application — Spécification v1.6

Application mobile de signalement collaboratif des dangers de la route en ville,
à commencer par les nids-de-poule. Pilote : Paris.
Statut : cadrage terminé. **Objectif immédiat : une bêta fermée** (§4.6). Le reste du document
décrit la cible complète et reste valable, mais n'est pas à construire maintenant.

## 0. Décisions prises

| Sujet | Décision | Conséquence |
|---|---|---|
| Comptes utilisateurs | Aucun pour le moment | Identité anonyme par device, réputation implicite. Compte optionnel envisageable plus tard, rien ne l'exige. |
| Périmètre | Nids-de-poule d'abord, extensible à d'autres dangers | Modèle, API et UI génériques (« danger » + catalogue de types) dès la v1. Un seul type activé au lancement. |
| Surfaces | Trois : app Flutter (contribution), site web public (consultation seule), console d'administration | Les trois sont dans le périmètre v1. Détail en §4.2 et §4.3. |
| Mobile | Flutter | Une base de code iOS + Android, MapLibre Native, hors-ligne via drift. Pas de PWA. |
| Pilote | Paris | Centre par défaut sur Paris, lien avec DansMaRue en V2. Le **recrutement** est parisien ; l'app, elle, fonctionne partout en France métropolitaine — un testeur qui descend à Lyon ne doit pas trouver une carte blanche. |
| Nom | L'application | Tous les usagers de l'espace public, à pied comme sur roues. |
| Partenariat | Aucun pour le moment | Pas de collectif ni d'accord avec la Ville. |
| Amorçage | Carte vide au lancement, aucun import | Pas de dépendance juridique ni technique à l'open data tiers. Le périmètre d'ouverture devient le levier critique (§4.4). |
| Types additionnels | Gelés | Le catalogue (§3) est modélisé et documenté, mais seul `pothole` est activé. Aucune activation prévue pendant le pilote. |
| Licence | Scindée : AGPL-3.0 serveur, Apache-2.0 app, ODbL données | Validée. Détail et justification en §12. |
| Objectif immédiat | **Bêta fermée**, pas d'ouverture publique | Périmètre réduit en §4.6. Environ 8 semaines au lieu de 13. Tout ce qui ne sert pas à répondre aux questions de la bêta est reporté. |
| Distribution v0 | **F-Droid uniquement, sans enregistrement développeur** | Publication pseudonyme possible immédiatement, sans association ni D-U-N-S. Contrepartie : **Android seul, pas d'iOS** (§12.6). |
| Identité de l'éditeur | Association loi 1901, différée | Non nécessaire pour F-Droid. Redevient obligatoire avant l'ouverture publique, pour nommer le responsable de traitement RGPD et pour toute publication sur les stores (§12.6). |
| Identité des contributeurs | Pseudonymes acceptés, ni CLA ni DCO | Le DCO exige un « real name ». S'en passer garde le dépôt ouvert aux pseudonymes (§12.7). |
| Seuil de résolution | 2 votes de devices distincts pour `pothole` | Le retrait par le créateur sous 24 h couvre l'erreur de bonne foi, donc rien n'oblige à descendre à 1. Un acteur isolé ne peut pas effacer la carte. |

---

## 1. Vision et périmètre

**Problème.** Nids-de-poule, rails glissants, plaques d'égout affaissées, verre brisé : les
dangers de la chaussée sont signalés tard, dans des outils fermés, et personne ne sait lesquels
existent encore. Pour qui roule ou marche dessus, c'est une chute.

**Promesse.** En deux gestes, signaler un danger. Voir ceux autour de soi.
Les faire disparaître de la carte quand ils sont résolus. Sans compte, sans friction.

**Cible.** Tous les usagers de l'espace public parisien : piétons, cyclistes, trottinettes, motards, automobilistes.

**Principes**
1. Zéro friction : pas de compte, signalement en moins de 10 secondes.
2. Collaboratif : tout le monde peut ajouter, confirmer, marquer résolu.
3. Ouvert : code libre, données ouvertes, cartographie OpenStreetMap.
4. Sobre : hébergeable sur un VPS à quelques euros par mois.
5. Vie privée : on cartographie les dangers, pas les gens. **Minimisation par défaut** : toute
   donnée qui n'est pas indispensable à une fonction décrite ici n'est pas collectée. En cas de
   doute, on ne collecte pas (§11).
6. Extensible : ajouter un type de danger = une ligne en base, pas une release.

**Hors périmètre v1.** Calcul d'itinéraire, comptes, gamification, dangers non localisables
(comportements, météo).

---

## 2. Cas d'usage

| Persona | Usage |
|---|---|
| Usager quotidien, à pied, à vélo ou en trottinette | S'arrête 10 s pour signaler ; consulte la carte avant un nouveau trajet. |
| Riverain | Voit les dangers de sa rue ; marque « résolu » quand la voirie est passée. |
| Collectif d'usagers (Paris en Selle, MDB, associations de piétons, conseils de quartier…) | Anime la communauté, pré-remplit la carte, utilise l'export pour interpeller la Ville. |
| Ville de Paris (V2) | Consomme l'export GeoJSON, l'endpoint Open311, ou reçoit les signalements via DansMaRue. |

---

## 3. Catalogue des types de danger

Le type est une donnée, pas du code. Chaque type porte ses libellés, son icône, sa durée de vie
et son seuil de résolution.

| Code | Libellé | Icône | Durée de vie par défaut | Verbe de résolution | v1 |
|---|---|---|---|---|---|
| `pothole` | Nid-de-poule | 🕳 | 180 j | « Réparé » | **activé** |
| `slippery` | Rails / pavés / plaque glissante | ⚠️ | 365 j | « Corrigé » | désactivé |
| `manhole` | Plaque d'égout affaissée ou manquante | ⭕ | 180 j | « Réparé » | désactivé |
| `debris` | Verre brisé, gravats, débris | 🧹 | 7 j | « Nettoyé » | désactivé |
| `curb` | Bordure / marche dangereuse | 🧱 | 365 j | « Corrigé » | désactivé |
| `works` | Chantier non sécurisé | 🚧 | 30 j | « Terminé » | désactivé |
| `lighting` | Éclairage défaillant | 💡 | 90 j | « Rétabli » | désactivé |

Activer un type : `UPDATE hazard_types SET enabled = true`, ou depuis la console (§4.3). L'app lit
le catalogue au démarrage et le relit à chaque retour au premier plan (amendement, bêta) : un type
activé apparaît dans le sélecteur sans que l'app ait à être fermée puis rouverte.

**Statut : gelé.** Les six types autres que `pothole` sont insérés en base avec `enabled = false`
et ne sont pas activés pendant le pilote. Ils sont ici pour deux raisons : garantir que le modèle
et l'UI supportent le multi-type sans refonte, et documenter les durées de vie et verbes de
résolution déjà réfléchis. La décision d'activation se prendra sur les retours du pilote, pas
maintenant.

Conséquence pour la v1 : le sélecteur de type est masqué tant qu'un seul type est activé, et
l'écran de signalement se réduit à gravité + photo + texte.

---

## 4. Fonctionnalités

### 4.1 App mobile (v1)

| ID | Fonction | Détail |
|---|---|---|
| F1 | Carte | Position, fond OSM vectoriel, marqueur = icône du type + couleur de niveau, clustering au dézoom, détail en bottom sheet. Filtre par type et niveau. |
| F2 | Signaler | Bouton central → pin posé à ma position, ajustable. Sélecteur de type (masqué si un seul type activé). Niveau sur 3 crans, 1, 2 ou 3, sans libellé (amendement : les mots « gênant », « dangereux », « très dangereux » ne voulaient pas dire la même chose pour tout le monde). Photo optionnelle. Commentaire optionnel (140 caractères), que la console peut couper d'un réglage (amendement, §4.3) : le champ disparaît, le serveur ne garde plus de texte et masque ceux qui existent, sans les effacer. |
| F2b | Anti-doublon | Si un danger actif **du même type** existe à moins de 15 m : « Est-ce celui-ci ? » → Confirmer plutôt que créer. |
| F3 | Confirmer | « Toujours là ». Met à jour `last_confirmed_at` et pèse dans le poids « présent » du danger, selon la proximité (§6.1, §6.2 amendés). |
| F4 | Marquer résolu | La « suppression » collaborative. Le bouton dit **« Plus là »**, le pendant exact de « Toujours là » (amendement ; il portait le verbe du type). Règles en §6. |
| F5 | Détail | Type (par son icône, sans libellé — amendement), niveau, date, nom de la voie (lu dans le fond de carte, §7), historique — c'est lui qui montre les confirmations, geste par geste. Photos abandonnées pour la bêta (§4.6). |
| F6 | Hors-ligne | File d'attente locale des actions, cache des dangers et des tuiles consultées, synchronisation à la reconnexion. |
| F7 | Signaler un abus | Flag avec motif. |
| F8 | Paramètres | À propos, licences, attribution OpenStreetMap, effacer mes données, régénérer mon identifiant. **Sans export** (amendement) : voir §11.4. |

### 4.2 Site web public (v1)

Consultation seule. Une URL partageable et indexable, qui ouvre la carte sans rien installer.

- Carte plein écran, même fond PMTiles et mêmes marqueurs que l'app.
- Permalien par danger, `/d/{id}` : photo, type, gravité, date, confirmations, adresse. Page
  rendue côté serveur pour être partageable sur les réseaux et indexable.
- Permalien par vue, `/#13/48.8566/2.3522`, pour envoyer une zone à quelqu'un.
- Filtres type et gravité. Pas de calque « résolus récemment » : un danger résolu quitte la carte, ici comme dans l'app (§6.1).
- Bandeau de présentation, liens vers les stores, attribution OSM, lien vers les données ouvertes.

**Décision : aucune contribution depuis le web.** Signaler, confirmer et marquer résolu restent
réservés à l'app. Tout le dispositif anti-abus du §6 repose sur deux choses qu'un navigateur ne
fournit pas de façon fiable : une identité de device stable et une position GPS crédible. Ouvrir
l'écriture au web créerait un canal de vandalisme sans contrepartie, et sans compte pour le
tempérer. Le bouton « Signaler » du site renvoie vers les stores.

Conséquence : le site n'a besoin que d'un rôle Postgres en lecture seule limité aux dangers non
masqués. Pas d'authentification, pas d'écriture, surface d'attaque quasi nulle.

Le site renvoie vers F-Droid tant que l'app n'est pas sur les stores (§12.6), et il ne peut pas
être mis en ligne avant que le responsable de traitement soit nommé (§11).

### 4.3 Console d'administration (v1)

Application web protégée, sur un sous-domaine distinct du site public. Trois comptes au plus
au lancement.

| Écran | Fonctions |
|---|---|
| File de modération | Dangers flaggés, triés par nombre de flags. Consulter, restaurer, retirer, purger. |
| Recherche et carte | Retrouver un danger par identifiant, adresse ou zone. Mêmes actions à l'unité. |
| Types de danger | Créer et éditer `hazard_types` : libellés, icône, verbe de résolution, `default_ttl_days`, `dedup_radius_m`, activation. |
| Règles de modération | Régler les seuils du §6.1 — plancher, rythme, plafond — pour tous les types à la fois, et les paliers de proximité du §6.2 — distances et poids. Écriture journalisée comme le catalogue. |
| Devices | Activité d'un device, réputation, annulation de tous ses événements, bannissement. |
| Journal d'audit | Historique horodaté de toutes les actions admin. Lecture seule. |
| Annonces (amendement) | Une ligne à toutes les personnes qui utilisent l'app, avec une durée et un motif ; l'app l'affiche en bandeau, comme l'avis de version, au lancement et au retour au premier plan. Se retire, ne se modifie pas. Née de la panne du 21 au 27/09/2026, pendant laquelle rien ne permettait de prévenir les testeurs. |

**Trois niveaux de suppression, volontairement distincts.**

| Action | Effet | Réversible | Usage |
|---|---|---|---|
| Retirer | `status = 'removed'`. Disparaît des cartes, tout reste en base. | oui | Doublon, signalement manifestement faux. C'est l'action par défaut. |
| Annuler un device | Neutralise tous ses événements et recalcule les compteurs de chaque danger touché. | oui | Vandalisme coordonné. |
| Purger | `DELETE` réel de la ligne, de ses événements et de ses photos dans le stockage objet. | **non** | Contenu illicite, photo d'une personne identifiable, demande d'effacement RGPD. Double confirmation et motif obligatoires. |

Le retrait est l'action courante, la purge est l'exception. Les trois sont écrites dans le
journal d'audit avec l'identité de l'admin, l'horodatage et le motif, dans la même transaction
que l'action elle-même.

**On bannit depuis un danger, jamais depuis une carte des terminaux** (amendement). Un
modérateur juge ce qu'il voit : un signalement. Il lui faut donc un chemin vers l'auteur — mais
afficher `created_by` à côté d'un danger, ou pire dessiner les signalements d'un terminal sur un
fond de carte, reconstituerait exactement ce que le §11 interdit de stocker : une journée de
déplacements d'une personne, lisible d'un coup d'œil. Le lien existe en base pendant 24 heures
(§11.2), il ne remonte pour autant dans aucune interface.

Le geste part donc du danger : `admin_ban_hazard_author(hazard_id, reason)` résout l'auteur côté
serveur, le bannit, et ne rend que des compteurs. `admin_hazards` n'expose pas `created_by`,
`admin_devices` n'expose que des totaux. Deux conséquences assumées :

- **Le journal d'audit, lui, garde l'identifiant du terminal** — sans lui on ne pourrait pas
  débannir. L'exposition est bornée aux terminaux effectivement sanctionnés.
- **Passé 24 heures, il n'y a plus d'auteur à qui remonter.** Le vandalisme se modère dans la
  journée, ou plus du tout. C'est le prix de la fenêtre du §11.2, et la console le dit en clair
  plutôt que de renvoyer une erreur technique.

**Repérer un saboteur sans le suivre** (amendement). Un saboteur ne se reconnaît pas à son
volume — un usager assidu en fait autant — mais à ce qu'il dit très souvent le contraire des
autres. `admin_suspect_devices(since, max_kmh)` rend, pour chaque terminal actif dans la
fenêtre, ses gestes et le nombre de ses avis contredits : un avis (« le danger est là » par
création ou confirmation, « il n'y est plus » par résolu) est contredit quand au moins deux
autres personnes disent le contraire et sont plus nombreuses que son camp, lui compris ; une
égalité ne contredit personne. Une personne, une voix par danger, ce que l'index unique
garantit déjà : deux avis d'une même personne ne font pas un collectif. Plus sûr encore parmi
les signaux tirés de la carte : un « résolu » **infirmé**, c'est-à-dire suivi sur le même danger
d'une confirmation par quelqu'un d'autre — un nid-de-poule ne réapparaît pas, celui qui est
passé après avait le danger sous les yeux. Toujours des totaux par identifiant, dans la même
règle que `admin_devices` ; le modérateur juge ensuite depuis la carte.

**Et un saut géographiquement impossible, trié en premier** (amendement). Un émulateur Android
règle sa position au clic et lance dix instances : un testeur l'a signalé, et ce n'était déjà
pas le chemin le plus court, l'API étant ouverte sans compte ni clé (§4). Le §6.2 l'assume — le
palier est une déclaration, et le calculer côté serveur n'apportait aucune garantie. Ce qu'une
déclaration ne peut pas falsifier, c'est la **géométrie de ce qu'elle affirme** : deux gestes
« sur place » que nulle vitesse terrestre ne relie se contredisent l'un l'autre. `jumps` les
compte, `top_kmh` donne le pire, et le seuil est de **50 km/h à vol d'oiseau** — un trajet réel
en ville étant plus long d'environ un tiers, cela laisse passer près de 70 km/h parcourus, donc
la marche, le vélo, le métro et le RER. Le calcul ne lit que la position des **dangers** et l'heure des
gestes ; aucune position de personne n'y entre, rien de nouveau n'est stocké, et la fenêtre de
24 heures est celle du §11.2.

C'est le premier critère de tri, parce que c'est de l'arithmétique et non un jugement sur l'avis
des autres : « contredit » et « infirmé » ont tous deux une lecture innocente, un saut n'en a
pas. Mais **il signale, il n'agit pas** : un saut prouve que le terminal ne tourne pas l'app
telle qu'elle est publiée, pas que son signalement soit faux, et une position simulée peut être
un choix de vie privée. L'anti-abus automatique — refuser un geste, le repondérer, shadow-ban —
reste en phase 2 (§4.6) ; ici c'est un humain qui bloque, avec un motif.

**Règles sur les types, à ne pas manquer à l'implémentation.**

- **L'icône d'un type est une image téléversée** (amendement). `hazard_types.icon` n'est qu'un
  nom, traduit côté app par une correspondance codée en dur : la moitié de la promesse du §3 —
  « ajouter un type est une ligne en base, pas une release » — était donc fausse, puisqu'un
  nouveau type arrivait sans dessin. La console téléverse maintenant un PNG dans
  `hazard_type_icons`, et le nom reste le **repli** : au premier lancement, hors ligne, ou si
  l'image est illisible, le glyphe embarqué prend le relais. Rien ne casse si personne ne
  téléverse jamais.

  Le fichier attendu est une **silhouette**, pas une image en couleurs : carrée, entre 32 et
  512 px, 64 Ko au plus, fond transparent. L'app n'en lit que le canal alpha et peint la forme
  aux couleurs du marqueur — c'est ce qui lui permet de s'inverser quand le danger est
  contesté (§9), ce qu'une image en couleurs interdirait. La validation est **en base**
  (signature PNG, dimensions, poids), pas seulement dans la console : sinon la règle
  dépendrait de qui écrit.

- `enabled` pilote la **création**, jamais l'affichage. Désactiver un type ne fait pas
  disparaître les dangers existants de ce type, qui restent visibles et confirmables. Sans cette
  règle, une case à cocher effacerait des centaines de points de la carte sans prévenir.
- Un type référencé par au moins un danger ne peut pas être supprimé, seulement désactivé. La
  clé étrangère l'interdit déjà, la console doit l'expliquer plutôt que de laisser remonter une
  erreur SQL.
- Modifier `default_ttl_days` ne vaut que pour les prochains passages du cron, sans effet rétroactif.

**Authentification.** Le « pas de compte » du §0 vaut pour les utilisateurs, pas pour les admins.
Comptes Supabase Auth nominatifs, 2FA TOTP activée dès le pilote, rôle `admin` porté par un claim
JWT et vérifié **en RLS côté Postgres**, jamais seulement dans l'interface. Pas de restriction
par IP, les admins sont mobiles. Le sous-domaine admin n'est pas référencé depuis le site public.

### 4.4 Amorçage de la carte

**Décision : on démarre avec une carte vide, sans import de données tierces.** Cela retire un
blocage juridique, une brique technique et un risque de crédibilité, au prix d'un démarrage
plus lent.

En conséquence, le périmètre d'ouverture devient le levier le plus important du pilote. Une
carte collaborative ne vit pas de la surface couverte mais du recoupement. Il faut que plusieurs
personnes empruntent le même axe pour qu'un danger soit confirmé, puis marqué résolu. Un
signalement que personne ne recroise n'est qu'une note personnelle, et la modération du §6
ne s'enclenche jamais.

Stratégie retenue :

- Ouvrir sur les **axes à fort trafic** intra-muros (rue de Rivoli, boulevard de
  Sébastopol, canal Saint-Martin, boulevard Voltaire) plutôt que sur un découpage administratif.
  La densité d'usagers par kilomètre prime sur la surface.
- Pré-remplir soi-même, à pied ou à vélo, sur ces axes pendant la phase de test. Quelques dizaines de points
  suffisent à ce que le premier utilisateur ne tombe pas sur un écran vide, et le trajet sert
  de toute façon à tester l'app en conditions réelles.
- Ne pas élargir le périmètre tant que le taux de confirmation croisée (§13) n'est pas atteint.
  Un élargissement prématuré dilue les utilisateurs et casse le recoupement.

Un import depuis l'open data parisien reste possible plus tard, mais n'est plus au programme
du pilote. Le champ `source` du modèle (§5) est conservé pour ne pas fermer la porte.

### 4.5 V2 (après pilote)

- **Mode trajet** : détection automatique des chocs (accéléromètre + GPS), validation en fin de trajet.
- **Notifications de proximité** : dangers graves sur mes trajets habituels (ntfy / UnifiedPush).
- **Export open data** : GeoJSON et CSV publics, endpoint **Open311 GeoReport v2**.
- **Passerelle DansMaRue** : transmission des signalements confirmés à la Ville de Paris (accès partenaire à demander), et lecture du statut de traitement en retour.
- **Floutage automatique** visages et plaques.
- **Compte optionnel** (magic link) si le besoin de réputation persistante se confirme.

### 4.6 Périmètre de la bêta fermée

Tout ce qui précède décrit la cible. Voici ce qu'on construit maintenant, et ce qui attend.

| Brique | Bêta | Raison |
|---|---|---|
| Schéma et journal d'événements (§5) | **oui** | Fondation. Très coûteux à rétro-adapter. |
| Fonctions RPC avec pondération par proximité (§6.2) | **oui** | Quelques lignes de SQL. Changer la pondération plus tard invaliderait les données déjà collectées. |
| `client_id` et idempotence | **oui** | Rétro-adapter une synchronisation hors-ligne est douloureux. |
| Carte, créer, confirmer, résolu, détail | **oui** | C'est l'objet même du test. |
| Hors-ligne (§10) | **oui** | Un trajet en ville traverse des zones sans réseau. C'est une condition réelle d'usage, pas un raffinement. |
| Photos | **non** (amendement) | Elles étaient le seul moyen de vérifier après coup si les signalements sont justes et si les trois gravités veulent dire la même chose pour tout le monde. Mais la photo n'est pas un fichier de plus : c'est le seul endroit où un visage, une plaque ou une façade peuvent entrer, avec les EXIF qui portent position et numéro de série. Elle demande donc un effacement des métadonnées, une suppression réelle du binaire quand le danger est archivé, et une modération — reportée en phase 2 (§6.3). Sans elle, on héberge ce que les testeurs déposent. Le coût n'est pas le stockage, c'est tout ce qui l'entoure. La question de la cohérence des gravités se traite autrement : faire noter les mêmes trous par tout le monde (§4.6). |
| Catalogue multi-type (§3) | **oui** | Déjà modélisé, coût nul, un seul type activé. |
| Réputation, shadow-ban, rate limiting (§6.3) | non | Inutile entre gens qui se connaissent. Le modèle les prévoit, l'application de la règle attend. |
| Flags et file de modération | non | Même raison. |
| Cron d'expiration (§6.4) | non | Sans effet visible sur quelques semaines. |
| Console d'administration (§4.3) | **partiellement** (amendement) | Huit actions avancées : retirer un danger, effacer sa précision (le texte libre) sans le retirer, couper la précision libre pour tous les signalements à venir (réglage de `moderation_settings`, journalisé), le retrouver sur une carte, bannir un terminal, gérer le catalogue, téléverser les icônes de type, et publier une annonce que l'app affiche en bandeau (la panne du 21 au 27/09/2026 a montré qu'il n'existait aucun moyen de prévenir les testeurs). Plus une lecture : les terminaux actifs des 24 dernières heures classés par sauts géographiquement impossibles puis par avis contredits par le collectif, pour repérer un saboteur sans jamais relier un identifiant à un danger. Sans elles, le seul levier contre du vandalisme était de retirer les signalements un par un dans Supabase Studio, sans trace — or Studio écrit en direct et ne journalise rien, ce qui vide le journal d'audit du §4.3 de son sens. Restent reportées : la file de modération (rien ne l'alimente sans signalements d'abus), la purge irréversible (sans objet sans photos), et le shadow-ban du §6.3, remplacé par un blocage franc. |
| Site web public (§4.2) | non | Reporté. |
| Avis de mise à jour dans l'app (§12.6) | **oui** (amendement) | Le dépôt F-Droid prévient ceux qui l'ont ajouté ; beaucoup de testeurs ne le feront pas. L'app lit donc à chaque lancement et à chaque retour au premier plan, sur son propre serveur, un fichier `latest.json` écrit à chaque publication, et affiche un bandeau si une version plus récente existe. La requête ne porte rien — ni identifiant ni version installée — et l'app refuse un APK annoncé sur un autre domaine que le sien (§11.5). Elle n'installe rien seule : Android l'interdit hors magasin, le testeur touche le bandeau et confirme. Une version minimale peut être exigée, pour une correction qui change ce que l'app envoie. |
| Association loi 1901 (§12.6) | non | Une bêta fermée entre personnes qui se connaissent reste proportionnée. |

**Ce que la bêta doit répondre.**

| Question | Comment la mesurer |
|---|---|
| Le signalement tient-il sous 15 secondes ? | Temps entre l'ouverture de la feuille et l'envoi, instrumenté dans l'app. |
| Les trois niveaux de gravité veulent-ils dire la même chose pour tout le monde ? | Faire noter les dix mêmes trous par tous les testeurs, comparer les écarts. |
| Le rayon anti-doublon de 15 m est-il le bon ? | Doublons créés malgré la détection, et détections à tort. |
| La synchronisation hors-ligne tient-elle un vrai trajet ? | File d'attente, échecs, doublons après reconnexion. La file étant en mémoire (§10), noter aussi le modèle de téléphone : un geste perdu peut l'être par la surcouche constructeur, pas par le code. |
| Quel coût en batterie et en GPS sur une heure de trajet ? | Mesure directe. |
| Quelqu'un marque-t-il jamais un danger résolu ? | Comptage des événements `mark_resolved`. |

**Ce que la bêta ne peut pas répondre.** Le recoupement. Avec une poignée de testeurs, deux
personnes ne croiseront pas le même trou, donc les confirmations indépendantes seront rares et
les seuils de résolution du §6.1 resteront non validés. L'hypothèse centrale du produit tient
jusqu'à l'ouverture. Il faut le savoir avant de lire les résultats de la bêta, et ne pas conclure
d'une absence de confirmations que le modèle est faux.

---

## 5. Modèle de données (PostgreSQL + PostGIS)

```sql
CREATE TYPE hazard_status AS ENUM ('active', 'disputed', 'resolved', 'removed', 'archived');
CREATE TYPE event_type    AS ENUM ('create', 'confirm', 'mark_resolved', 'remove', 'flag', 'restore', 'photo_add');

-- Catalogue des types de danger : la donnée pilote l'UI.
CREATE TABLE hazard_types (
  code               text PRIMARY KEY,                 -- 'pothole', 'debris', ...
  label_fr           text NOT NULL,
  icon               text NOT NULL,                    -- glyphe de repli ; l'image vit dans hazard_type_icons
  resolved_label_fr  text NOT NULL,                    -- « Réparé », « Nettoyé »... (bandeau et historique, plus le bouton)
  default_ttl_days   int  NOT NULL,                    -- passage en 'disputed' sans confirmation
  dedup_radius_m     int  NOT NULL DEFAULT 15,
  enabled            bool NOT NULL DEFAULT false,
  sort_order         int  NOT NULL DEFAULT 100
);

-- Les seuils du §6.1, une seule ligne, les mêmes pour tous les types (amendement).
CREATE TABLE moderation_settings (
  id                             int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  min_resolve_votes              int NOT NULL DEFAULT 2,   -- plancher du seuil dynamique
  confirmations_per_resolve_vote int NOT NULL DEFAULT 3,   -- une voix de plus toutes les N
  max_resolve_votes              int NOT NULL DEFAULT 5,   -- plafond du seuil dynamique
  updated_at                     timestamptz NOT NULL DEFAULT now()
);

-- Identité anonyme : UUID généré côté client, stocké en secure storage.
CREATE TABLE devices (
  id          uuid PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  reputation  int NOT NULL DEFAULT 0,
  banned_at   timestamptz
);

CREATE TABLE hazards (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type               text NOT NULL REFERENCES hazard_types(code),
  geom               geometry(Point, 4326) NOT NULL,
  severity           smallint NOT NULL CHECK (severity BETWEEN 1 AND 3),
  status             hazard_status NOT NULL DEFAULT 'active',
  description        text CHECK (char_length(description) <= 140),
  address            text,                                     -- cache géocodage inverse
  source             text NOT NULL DEFAULT 'user',              -- 'user' en v1 ; réservé pour un import futur
  created_by         uuid REFERENCES devices(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  last_confirmed_at  timestamptz NOT NULL DEFAULT now(),
  -- Compteurs dérivés du journal `events` (maintenus par trigger)
  confirm_weight     real NOT NULL DEFAULT 0,                  -- somme pondérée des gestes « présent » : create × N, confirm (amendement)
  resolve_weight     real NOT NULL DEFAULT 0,                  -- somme pondérée des votes « résolu »
  flags              int  NOT NULL DEFAULT 0
);
CREATE INDEX hazards_geom_idx   ON hazards USING gist (geom);
CREATE INDEX hazards_status_idx ON hazards (status, type);

-- Journal append-only : source de vérité, rejouable.
CREATE TABLE events (
  id           bigserial PRIMARY KEY,
  client_id    uuid UNIQUE NOT NULL,          -- idempotence (généré côté client)
  hazard_id    uuid NOT NULL REFERENCES hazards(id),
  device_id    uuid REFERENCES devices(id),   -- mis à NULL au bout de 24 h : borne la fenêtre de corrélation (§11)
  type         event_type NOT NULL,
  -- La position du déclarant n'arrive JAMAIS jusqu'ici : l'app calcule le palier sur
  -- l'appareil et n'envoie que lui. Voir §6.2, §11.
  proximity    smallint,                      -- 1 = sur place (≤ 100 m), 2 = ailleurs ou position refusée (amendement)
  weight       real NOT NULL DEFAULT 1,       -- dérivé de proximity (× réputation en phase 2)
  payload      jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX events_hazard_idx ON events (hazard_id, created_at);
CREATE UNIQUE INDEX events_one_per_device
  ON events (hazard_id, device_id, type) WHERE type IN ('confirm', 'mark_resolved', 'flag');

-- Administrateurs : le « pas de compte » ne vaut que pour les utilisateurs.
CREATE TABLE admins (
  user_id      uuid PRIMARY KEY,             -- auth.users(id) de Supabase Auth
  email        text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  disabled_at  timestamptz
);

-- Journal d'audit : append-only, ni modifiable ni supprimable, y compris par un admin.
CREATE TABLE admin_actions (
  id          bigserial PRIMARY KEY,
  admin_id    uuid NOT NULL REFERENCES admins(user_id),
  action      text NOT NULL,                 -- 'remove'|'restore'|'purge'|'revoke_device'|'ban_device'|'type_upsert'
  target      text NOT NULL,                 -- 'hazard:<uuid>' | 'device:<uuid>' | 'type:<code>'
  reason      text,                          -- obligatoire pour 'purge' et 'ban_device'
  snapshot    jsonb,                         -- état avant action ; pour une purge RGPD, identifiants et horodatage seulement, jamais le contenu effacé
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE photos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hazard_id   uuid NOT NULL REFERENCES hazards(id),
  device_id   uuid REFERENCES devices(id),
  object_key  text NOT NULL,                  -- clé S3 / MinIO
  created_at  timestamptz NOT NULL DEFAULT now()
);
```

**Pourquoi un journal d'événements.** Les compteurs de `hazards` sont des vues matérialisées
du journal. Si un device vandalise, on annule ses événements et on recalcule : rien n'est perdu.

---

## 6. Modération collaborative (le cœur du sujet)

Contrainte : « tout le monde peut supprimer », sans compte. Risques : vandalisme, suppression
massive, faux signalements, données périmées. Réponse : **pas de permission, mais du poids** :
suppression douce, quorum, proximité, réputation implicite.

### 6.1 Supprimer = voter « résolu »

Aucune suppression physique. Un vote « résolu » par device distinct.

| Situation | Effet |
|---|---|
| Le créateur retire son propre signalement dans les 24 h | Statut `removed` immédiat (correction d'erreur). |
| Poids cumulé « résolu » ≥ 1 | Statut `disputed` : marqueur grisé, toujours visible, mention « signalé résolu ». |
| Poids cumulé « résolu » ≥ seuil | Statut `resolved` : le danger quitte la carte (amendement ; il y restait 30 jours dans un calque « résolus récemment »). |
| Un « confirmer » arrive pendant `disputed` | Retour `active`, poids « résolu » remis à zéro. Tout reste dans le journal. |

**Seuil dynamique** : `seuil = clamp(ceil(poids_présent / N), plancher, plafond)`. Un trou
confirmé par 15 personnes ne disparaît pas sur 2 clics. **Valeurs retenues pour le pilote** :
plancher 2, une voix de plus toutes les 3 confirmations, plafond 5. Descendre le plancher à 1
aurait servi à corriger vite les erreurs de saisie, mais le retrait par le créateur sous 24 h
couvre déjà ce cas. À 2, un acteur isolé ne peut pas effacer la carte.

**Les confirmations pèsent comme les votes** (amendement ; le seuil se calculait sur un
*compte* de confirmations). « Toujours là » et « résolu » sont les deux réponses à la même
question, et une seule était pondérée par la proximité : un « toujours là » depuis le canapé
comptait 1 plein là où un « résolu » depuis le même canapé pesait un quart. Il était plus
facile d'ancrer un danger à distance que de le retirer à distance. Le seuil se calcule donc
sur `confirm_weight`, la somme des poids des gestes « présent » — le `create` et les `confirm`
non annulés — et le compte de confirmations disparaît : la chronologie du danger montre
chaque geste, c'est ce qu'une personne veut lire.

**Un signalement vaut N confirmations**, N = 3 au départ, dans `moderation_settings`
(`report_confirmations`). Placer le pin, choisir le type et la gravité est le geste lourd. À 3,
un signalement sur place vaut exactement une voix « résolu » — c'est aussi le rythme du seuil —
et un signalement fait d'ailleurs (3 × ⅓) vaut une confirmation sur place. Comme les trois
autres réglages, N s'applique au recalcul et non à l'écriture : un changement vaut pour tout
l'historique.

**Question ouverte** : un « confirmer » pendant `disputed` remet le poids « résolu » à zéro
quel que soit son palier — un « toujours là » à ⅓ efface deux « résolu » sur place à 1. C'est la
dernière asymétrie entre les deux gestes ; on la garde tant qu'un cas réel ne l'a pas mise en
défaut.

**Les trois réglages vivent dans `moderation_settings`, pas dans le code ni dans le catalogue**
(amendement ; le diviseur et le plafond étaient écrits en dur dans `resolve_threshold`, et le
plancher était une colonne de `hazard_types`, par type). C'est la seule règle du §6 que la bêta
doit pouvoir corriger en la regardant tourner : elle s'édite dans la console, sans déploiement.

**Et c'est la même règle pour tous les types.** Un seuil par type promettait de traiter le
verre brisé autrement que le nid-de-poule ; en pratique il dispersait la seule décision de
modération du produit dans sept lignes de catalogue, là où personne ne la cherchait. Un type de
danger décrit un danger — libellé, icône, rayon anti-doublon, durée de vie. La façon de modérer
n'en fait pas partie. Une table d'une seule ligne, lue par l'app comme `proximity_tiers`, et un
écran qui montre l'effet du réglage avant de l'écrire.

**Un danger résolu quitte la carte** (amendement). Il y avait deux définitions de « visible » :
la carte servait les résolus sur demande pendant 30 jours, la vue publique les servait tous,
sans limite de date. Une seule définition désormais, `active` ou `disputed`, tenue par la
policy, la vue et le RPC. Ce n'est pas une perte pour le cycle de vie d'un danger :
l'anti-doublon ne regarde que les dangers encore visibles, donc le jour où le trou se rouvre,
le signalement suivant crée un danger neuf avec ses propres confirmations. Les résolus restent
lisibles dans la console et dans le journal, qui ne perd jamais rien (§5).

**Un signalement ne se confirme pas par son auteur** (amendement). Créer compte déjà pour une
confirmation : l'auteur qui appuyait ensuite sur « toujours là » en valait deux, et un danger
gonflé est plus *difficile* à faire disparaître, puisque le seuil monte avec les
confirmations. Le contrôle est côté serveur, l'app ignorant quels dangers sont les siens
(§11). Il s'éteint au bout de 24 heures, quand `created_by` passe à `NULL` : c'est la même
durée de vie que la voix unique par danger, pour la même raison, et la minimisation prime.

### 6.2 Proximité

Chaque action envoie un **palier de proximité**, calculé par l'app (amendement ; le serveur
recevait la position et le calculait lui-même) :

| Distance | Palier | Poids |
|---|---|---|
| ≤ 100 m | 1, « sur place » | 1 |
| au-delà, ou position refusée | 2, « ailleurs » | ⅓, et badge « signalé à distance » sur une création |

Le GPS se falsifie, mais cela relève la barre pour le vandalisme depuis un canapé.

**Deux paliers, pas trois** (amendement ; la règle avait un palier intermédiaire, 50 à 500 m
à 0,5, et « au-delà » à 0,25). Le 500 m ne correspondait à rien de vécu : posé avant d'avoir vu
un seul trajet réel, il ne départageait rien d'utile. Un seul seuil, « sur place » ou
« ailleurs », se raconte en une phrase ; le ratio de 3 aussi : **trois gestes d'ailleurs
valent un geste sur place**, dans un sens comme dans l'autre (§6.1). Les 100 m absorbent
l'erreur du GPS urbain et l'arrêt au feu suivant ; c'est un réglage de console, à corriger si le
badge « signalé à distance » tombe sur des signalements honnêtes. Le poids est ⅓ et non 0,33 :
trois fois 0,33 font 0,99, sous le 1 qui fait passer un danger en `disputed`.

Le journal a été recodé une fois à l'amendement : le palier 3 y devient 2, et l'ancien palier 2
(50 à 500 m) devient « ailleurs », ce qu'il serait sous la nouvelle règle. Les poids écrits ne
bougent pas — le §5 protège les faits, quoi, quand, quel poids, pas le numéro d'un code — et les
apps antérieures, qui envoient encore 3 pour « loin », sont comprises.

**La position du déclarant ne quitte jamais l'appareil** (amendement). Le serveur recevait
`device_lat` / `device_lng`, en déduisait le palier et les jetait : elles n'étaient jamais
écrites, mais elles traversaient le réseau, et la promesse tenait à ce qu'aucun journal ne les
attrape en chemin. Le calcul se fait maintenant sur le téléphone, et les RPC n'ont plus de
paramètre pour recevoir une coordonnée.

**Ce n'est pas une concession sur la triche.** C'était déjà le client qui fournissait la
coordonnée : envoyer celle du danger donnait le poids maximal depuis n'importe où, exactement
comme déclarer « palier 1 ». Le calcul côté serveur n'apportait aucune garantie d'intégrité, il
n'en perd donc aucune. L'anti-abus, reporté en phase 2 (§4.6), devra traiter le palier comme
une déclaration — ce qu'il était déjà.

**Le seuil reste publié par le serveur**, dans `proximity_tiers`, que l'app lit au lancement
comme elle lit le catalogue. Sans cela, deux versions installées en même temps pondéreraient le
même geste différemment. Tant que le serveur n'a rien dit — premier lancement, hors ligne — la
règle compilée dans l'app s'applique, identique à celle qu'installe la migration.

**Et il s'édite depuis la console** (amendement), au même endroit que les seuils du §6.1 :
distance et poids sont les deux moitiés d'une même règle, et 100 m est une valeur posée avant
d'avoir vu beaucoup de trajets réels. La base refuse ce qui inverserait la règle — un geste
d'ailleurs qui pèserait plus qu'un geste sur place, un premier palier sans distance, un second
qui cesserait d'être « ailleurs », un troisième palier.

**Un réglage ne vaut que pour la suite**, contrairement aux seuils du §6.1 qui se recalculent
sur tout l'historique. Le poids d'un vote est figé dans `events.weight` au moment de l'écriture,
et le journal ne se réécrit pas (§5) ; le palier, lui, a été calculé par un téléphone qui
appliquait la règle qu'il connaissait alors. Une application déjà ouverte continue donc de
pondérer à l'ancienne jusqu'à son prochain démarrage.

Hors-ligne, la position du moment est gardée localement avec l'action en attente, puis effacée
du terminal dès l'envoi.

### 6.3 Anti-abus sans compte

- **Rate limiting** par device et par IP : 20 créations / jour, 60 actions / jour,
  une action de chaque type par danger et par device (index unique ci-dessus).
- **Réputation implicite du device** : +1 quand une action est corroborée par d'autres,
  -2 quand elle est inversée ou flaggée. Réputation ≥ 10 → poids × 1,5.
  Réputation ≤ -5 → poids 0 (shadow-ban : aucune erreur visible, actions ignorées).
- **Réinitialiser son identifiant** contourne le shadow-ban mais remet la réputation à 0 et
  retombe sur le rate limit IP : acceptable pour un pilote.
  **Amendement (bêta)** : « Effacer mes données » retire aussi ses confirmations et ses votes
  « résolu » (`cancelled_at`, comme un bannissement) — sinon deux tours de « résolu, effacer,
  résolu » faisaient disparaître un danger à une seule personne. Et un terminal vu depuis moins
  de quinze minutes ne peut pas dire « résolu » : réinstaller l'app donne un identifiant neuf
  sans passer par le serveur, on ne l'empêche pas, on le rend lent, un quart d'heure par voix.
  Le refus dit le temps restant. Créer et confirmer restent libres dès le premier geste.
  **Amendement (0250)** : le compteur part de la première ouverture de l'app, qui déclare son
  identifiant au serveur une fois (`declare_device`), et non plus du premier geste — sinon qui
  regardait la carte vingt minutes avant de voter attendait deux fois.
- **Flags** : 3 flags → masqué en attente de revue, puis traité dans la file de modération de
  la console d'administration (§4.3).
- **Rejeu** : le journal permet de corriger a posteriori un vandalisme découvert tard.

**Ce qui est en place avant le rate limiting** (amendement, bêta). Le serveur ne doit pas
dépendre de l'hébergeur pour rester debout devant un script. Deux bornes, sans rien journaliser :
un délai maximal par requête selon le rôle (cinq secondes pour l'app, quinze pour la console,
migration 0180), pour qu'une requête absurde ne tienne pas une des dix connexions du pool ; et un
plafond de mille lignes par réponse dans PostgREST, pour qu'une lecture de table en boucle coûte
mille lignes et pas la table. Et une limite de vitesse par adresse dans Caddy, comptée en mémoire
sur une fenêtre glissante et jamais écrite, ce qui respecte le §11 : trois cents requêtes par
minute sur l'API, soixante par heure sur les fichiers APK (une dizaine par téléchargement, le
navigateur prenant le fichier par morceaux). Au-delà, 429 sans toucher à la base. Chaque refus
laisse une ligne dans un journal `blocked` filtré comme celui des téléchargements — heure,
chemin, code, sans adresse — lu par `make blocked` et l'onglet Téléchargements de la console :
on sait que la limite sert, pas à qui.
L'image Caddy est construite avec le module (`server/caddy/Dockerfile`). Ce que rien de tout
cela ne couvre : une attaque qui sature le lien réseau lui-même, ou un script qui change
d'adresse à chaque requête.

### 6.4 Expiration automatique (pg_cron, quotidien)

- `default_ttl_days` du type sans confirmation → `disputed` (« à vérifier »).
- 2 × `default_ttl_days` → `archived`.

Des débris passent en « à vérifier » au bout d'une semaine, un nid-de-poule au bout de six mois.

---

## 7. Stack technique (100 % open source)

| Couche | Choix | Licence | Note |
|---|---|---|---|
| App mobile | **Flutter** (Dart 3, stable) | BSD-3 | Android 8+ en v0. Le code iOS reste maintenu, la publication iOS est seulement différée (§12.6). |
| Rendu carte | **maplibre_gl** | BSD-2 | Style vectoriel, rotation, clustering natif. |
| Fond de carte | **Protomaps PMTiles**, extrait France métropolitaine auto-hébergé | ODbL | ~9,4 Go jusqu'au zoom 15, servi statiquement par Caddy. Le fichier s'appelle `basemap.pmtiles`, par son rôle et non par son étendue : le serveur dérive l'URL du nom, et le cache disque de MapLibre est indexé par URL — changer d'étendue ne doit pas vider le cache de tous les téléphones. OpenFreeMap en dépannage. |
| Géocodage inverse | ~~**Photon**~~ | Apache-2 | **Écarté** (amendement ci-dessous) : le nom de voie est lu dans les tuiles déjà chargées, rien ne sort de l'appareil. |
| Base de données | **PostgreSQL 16 + PostGIS 3.4** | PostgreSQL / GPL-2 | |
| API | **PostgREST** seul, devant Postgres | MIT | Logique métier en fonctions SQL, accès par `GRANT` et RLS. Le reste de Supabase (Auth, Storage, Realtime) n'est **pas déployé** : ni compte, ni photo, ni temps réel en bêta. Supabase Studio reste en option locale, jamais exposé. |
| Stockage photos | **Supabase Storage** (S3) | Apache-2 | **Phase 2**, avec les photos (§4.6). MinIO si on sort de Supabase. |
| Identité | UUID tiré par le terminal, en stockage chiffré | — | Aucun compte, aucun service d'auth : l'UUID est un porteur, pas une preuve (§11.4). |
| Stockage local app | **drift** (SQLite) | MIT | |
| Sync arrière-plan | ~~**workmanager**~~ | MIT | Écarté : la file d'attente vit en mémoire, il n'y a rien à reprendre en arrière-plan (§10). |
| Site web public | **SvelteKit** en sortie statique + **MapLibre GL JS** | MIT / BSD-2 | **Phase 2** (§4.6). Chargement rapide et indexable, servi en fichiers statiques par Caddy. |
| Console admin | **SvelteKit**, rendu côté serveur (`adapter-node`), même dépôt, sous-domaine séparé | MIT | Une seule chaîne d'outils web pour les deux surfaces. En service. |
| Admin de secours | **Supabase Studio**, déjà inclus | Apache-2 | Accès SQL brut pour ce que la console ne couvre pas. Jamais exposé publiquement. |
| Reverse proxy / TLS | **Caddy** | Apache-2 | |
| Notifications (V2) | **ntfy** / UnifiedPush | Apache-2 | **Phase 2.** |
| Erreurs | **GlitchTip** | MIT | **Non déployé** en bêta : aucun rapport d'erreur ne quitte l'app (§11.5). |
| Analytics | aucune | — | Le seul comptage est celui des téléchargements d'APK, sans adresse IP (§11.1). |
| Tâches planifiées | **pg_cron** | PostgreSQL | |
| CI / forge | **Forgejo** + Actions (ou GitHub) | GPL-3 | **Pas encore** : dépôt local, tests joués à la main et par `release-app.sh` avant chaque publication. |
| Déploiement | **Docker Compose** sur VPS, scripts `deploy/` | | Un hôte, x86, 2 vCPU / 4 Go / 40 Go suffisent. |

**État en bêta** (amendement). Ce tableau mêle ce qui tourne et ce qui est visé. Tourne
aujourd'hui : Flutter et MapLibre, PMTiles et tileserver, PostgreSQL et PostgREST, la console
SvelteKit, Caddy, pg_cron, Docker Compose, le dépôt F-Droid auto-hébergé. Le reste est marqué
phase 2 ou non déployé. [ARCHITECTURE.md](ARCHITECTURE.md) décrit le système tel qu'il tourne ;
c'est lui qui fait foi sur l'existant, ce tableau sur la cible.

**Le nom de voie est lu dans le fond de carte, pas demandé à un géocodeur** (amendement).
Photon reste la cible du tableau ci-dessus, mais il n'est pas en service — et il recevrait la
coordonnée de chaque danger consulté, soit exactement le genre de trace que le §11.5 cherche à
éviter, fût-ce vers notre propre serveur. Les tuiles vectorielles portent déjà `name` sur leurs
voies : l'app interroge donc sa propre carte, choisit la voie la plus proche du danger, et se
tait au-delà de 60 mètres. Rien ne sort de l'appareil, et cela fonctionne hors ligne sur les
zones embarquées.

Ce qu'on y perd, et qu'il faut assumer : c'est un **nom de voie**, jamais un numéro, et il faut
que la carte soit chargée à cet endroit — le style ne trace les voies mineures qu'à partir du
zoom 12. Quand la réponse manque, l'écran montre la coordonnée : une ligne technique vaut mieux
qu'un nom approximatif, le §11.6 voulant qu'on retrouve le trou à quelques mètres.

**Contrainte de vie privée sur les services cartographiques.** Le fond de carte et le géocodage
inverse sont auto-hébergés, et ce n'est pas qu'une question de coût. Un fond de carte tiers reçoit
la zone que l'utilisateur consulte à chaque déplacement de la carte ; une instance Photon publique
recevrait la coordonnée de chaque danger signalé. Les deux sont servis depuis le VPS, sur un
extrait France métropolitaine. Aucune requête de l'app ne sort vers un domaine tiers.

**Contrainte F-Droid.** Aucune dépendance propriétaire dans l'app : pas de Google Play Services,
pas de Firebase, pas de SDK cartographique fermé. La localisation passe par le `LocationManager`
natif d'Android, jamais par le service de localisation fusionnée (§12.6).

**Pourquoi Supabase auto-hébergé.** PostGIS natif, règles d'accès en RLS, API REST et temps réel
sans écrire de backend, Postgres reste au centre. Si l'on veut une API maison plus tard, on garde
le schéma et les fonctions SQL tels quels.

---

## 8. API (esquisse)

Toute la logique du §6 vit dans des fonctions SQL / PL/pgSQL exposées en RPC par PostgREST.
Le client déclare, le serveur décide.

```
GET  /hazard_types?enabled=eq.true                              → catalogue
GET  /hazards?bbox=minLon,minLat,maxLon,maxLat&status=active&type=pothole
                                                                → GeoJSON FeatureCollection
GET  /hazards/{id}                                              → détail + événements
GET  /tiles/{z}/{x}/{y}.pbf                                     → tuiles vectorielles ST_AsMVT (au-delà de ~5 000 dangers)

POST /rpc/report_hazard    { client_id, type, lat, lng, severity, description?, device_pos? }
                           → { id } ou { duplicate_of: id, distance_m }
POST /rpc/confirm_hazard   { client_id, id, device_pos? }
POST /rpc/mark_resolved    { client_id, id, device_pos? }
POST /rpc/flag_hazard      { client_id, id, reason }
POST /storage/photos       multipart ; EXIF supprimé côté client ET serveur ; max 2 Mo, recompressé 1600 px

GET  /export.geojson                (V2) dump open data ODbL, régénéré chaque nuit
GET  /open311/v2/requests.json      (V2) lecture seule, GeoReport v2
```

**Site web public** : rôle `anon` en lecture seule, restreint par RLS aux dangers non masqués.
Il consomme `/hazard_types`, `/hazards` et `/tiles`, rien d'autre.

**Console admin** : JWT porteur du rôle `admin`, vérifié en RLS. Chaque appel écrit dans
`admin_actions` au sein de la même transaction que son effet.

```
POST  /rpc/admin_remove_hazard    { id, reason }
POST  /rpc/admin_restore_hazard   { id, reason }
POST  /rpc/admin_purge_hazard     { id, reason }     -- supprime aussi les objets photo du stockage
POST  /rpc/admin_revoke_device    { device_id, reason }
POST  /rpc/admin_ban_device       { device_id, reason }
POST  /rpc/admin_upsert_type      { code, label_fr, icon, resolved_label_fr, ttl, ... }
GET   /admin_actions                                 -- journal d'audit, lecture seule
```

Toutes les écritures portent un `client_id` UUID : rejouer une action hors-ligne ne crée
jamais de doublon.

`device_pos` est un paramètre d'entrée, jamais une colonne. Les fonctions le consomment pour
calculer `proximity` et ne le persistent nulle part (§11).

---

## 9. Écrans et UX

1. **Carte** (écran principal, unique onglet). Centre par défaut : Paris, zoom 13, puis position
   de l'utilisateur. FAB central « + », recentrer, filtres type et niveau (le calque « résolus
   récemment » est retiré, §6.1). Marqueur : icône du type **et** couleur de niveau (jamais la couleur seule).
2. **Nouveau signalement** (bottom sheet). Mini-carte avec pin ajustable, sélecteur de type
   (rangée d'icônes sans libellé, le nom à l'appui long et au lecteur d'écran — amendement ;
   masquée si un seul type activé), 3 boutons de niveau, « 1 », « 2 »,
   « 3 », chacun avec sa jauge (amendement : plus de libellés), photo, texte, « Envoyer ». Objectif : moins de 10 secondes.
3. **Détail** (bottom sheet). Photo, type, niveau, « signalé il y a 3 j », adresse, la
   chronologie des gestes et la **balance** : une barre à deux moitiés, poids « toujours là »
   contre poids « plus là » à la même échelle, avec le repère du seuil qui tranche. Deux gros
   boutons : « Toujours là » / « Plus là ». Menu « … » : signaler un abus, partager, ajouter
   une photo.
4. **Onboarding** (un écran). Ce que fait l'app, demande de géolocalisation, mention
   « données ouvertes, pas de compte ».
5. **Paramètres.** À propos, licences, exporter mes signalements, effacer mes données,
   régénérer mon identifiant.

Accessibilité : contraste AA, cibles ≥ 44 pt, libellés VoiceOver / TalkBack, type et niveau
lisibles sans la couleur.

---

## 10. Hors-ligne et synchronisation

- Base locale drift : `hazard_types` et `hazards_cache` (TTL **45 min** par bbox — c'était 24 h,
  ramené à l'horizon d'oubli du §11.7, qui prime). Le TTL par zone sert à distinguer « il n'y a
  rien ici » de « je ne sais pas » : sans lui, la carte afficherait hors ligne un vide rassurant
  et faux.
- Une action = un geste en attente, avec son `client_id`, envoyé dès que possible. Idempotent
  côté serveur : rejouer la file ne crée jamais de doublon.
- **La file d'attente vit en mémoire, pas sur le disque** (amendement). Un geste fait sans
  réseau repart dès que le réseau revient, tant que l'app est en vie ; si Android tue le
  processus avant, il est perdu. Le cas nominal d'un trajet est l'app au premier plan, et ce
  périmètre évite une table, `workmanager`, et la question de savoir ce que la position du
  déclarant ferait sur un disque (§11.1). Conséquence : **rien de ce que la base locale contient
  ne concerne la personne** — uniquement le catalogue et des dangers, c'est-à-dire des faits sur
  la voirie. Conséquence sur la mesure du §4.6 : ce que le test hors-ligne observera dépendra en
  partie de l'agressivité du constructeur à tuer les applications.
- Le fichier de base locale est exclu des sauvegardes Android, sur les deux mécanismes
  (`allowBackup` et `dataExtractionRules`). Ce qui ne part pas n'a pas à être protégé ailleurs.
- Tuiles : le cache disque de MapLibre ne suffit pas. Il est **ambiant et très petit** — de
  l'ordre de la quarantaine de tuiles, non dimensionnable depuis le plugin Flutter — donc hors
  ligne le fond de carte devient blanc dès qu'on sort de ce qu'on vient de consulter, marqueurs
  flottant sur du vide. Il est aussi indexé par URL : changer l'adresse de base le vide d'un
  coup.
- **Téléchargement de zone, avancé en bêta** (le §10 le réservait à la V2). L'utilisateur choisit
  une zone sur la carte et l'embarque jusqu'au zoom 15. Paris intra-muros pèse 424 tuiles, une
  quarantaine de mégaoctets : le fond de carte hors ligne coûte donc peu, et un signalement posé
  sur du blanc ne serait pas ajustable à quelques mètres (§11.6). C'est la seule vraie réponse,
  et elle vaut d'autant plus que le fond couvre la France entière : personne ne téléchargera
  9,4 Go sur son téléphone.
- Conflits : le serveur a toujours raison ; le client réaffiche l'état renvoyé. Un geste mis en
  file ne modifie donc **rien** à l'écran tant que le serveur n'a pas tranché : deviner sa
  décision serait mentir à l'utilisateur. Seul un signalement fait exception, affiché aussitôt
  sous forme de marqueur provisoire pour que le geste ait un effet visible.

---

## 11. Vie privée : minimisation

Principe directeur : **une donnée non collectée n'a pas besoin d'être protégée, sécurisée,
conservée, ni effacée.** Ce qui suit décrit surtout ce que le système ne fait pas.

### 11.1 Ce qui n'est jamais collecté

| Donnée | Décision |
|---|---|
| Compte, e-mail, téléphone, nom | Jamais demandés. Il n'existe aucun champ pour les saisir. |
| Position de l'utilisateur | **Ne quitte jamais l'appareil** (amendement). L'app calcule le palier de proximité sur deux valeurs et n'envoie que lui ; le serveur n'a plus de paramètre pour recevoir une coordonnée. Ni coordonnée, ni distance exacte ne sont persistées (§5, §6.2). |
| Trajets, historique de déplacement | **Aucune collecte.** La position est suivie tant que la carte est à l'écran, pour l'indicateur de position et pour peser les gestes (§6.2) ; elle n'est ni écrite, ni mise en cache sur le disque, ni transmise. Le suivi s'arrête dès que l'app quitte le premier plan, et **aucune permission d'arrière-plan n'est déclarée**. |
| Identifiant publicitaire, identifiant d'installation, empreinte d'appareil | Jamais lus. Aucune dépendance qui y donne accès (§7). |
| Carnet d'adresses, calendrier, micro, capteurs | Permissions jamais demandées. |
| Analytics, mesure d'audience, télémétrie produit | **Aucune.** Les mesures de la bêta (§4.6) sont calculées et stockées sur le terminal, et transmises seulement si le testeur les exporte lui-même. |
| Journaux d'accès du reverse proxy | Désactivés pendant la bêta. Le rate limiting par IP qui les justifiait est reporté en phase 2 (§4.6). **Une exception, bornée** (amendement) : le journal des téléchargements de l'APK, journal nommé `apk` dans le Caddyfile, alimenté uniquement par les requêtes sur les fichiers `.apk`, et filtré à la source pour ne garder que l'heure, le fichier, la méthode, le code, la taille et la langue annoncée par le navigateur (`Accept-Language`, qui tient lieu de pays) — **jamais l'adresse IP**, ni convertie en lieu ni écrite, ni aucun autre en-tête. Il porte sur la page de téléchargement, pas sur l'app. L'onglet Téléchargements de la console et `make downloads` le lisent, avec les mêmes comptes. **Vérifié** : `log { output discard }` au global et par site ; côté base `log_statement=none` et `log_min_duration_statement=-1`. Une requête en échec est journalisée par `log_min_error_statement`, mais **sans ses paramètres** — `log_parameter_max_length_on_error` vaut 0, constaté en provoquant une erreur avec des coordonnées et un `device_id` d'essai : seul le texte SQL apparaît, les valeurs restent dans `$1`. |

L'entrée « trajets » ci-dessus porte sur la position lue par le capteur, qui ne touche jamais le
disque. Afficher une carte laisse en revanche des traces d'un autre genre, bornées à 45 minutes :
voir **§11.7**.

### 11.2 Ce qui est collecté, et pourquoi c'est le minimum

| Donnée | Raison d'être | Durée |
|---|---|---|
| Position du **danger** | C'est l'objet même du service. **Aucun arrondi, aucune dégradation** : voir §11.6. | Vie du signalement |
| Identifiant de device, UUID aléatoire | Empêche le même terminal de voter deux fois sur un danger, et permet le retrait par le créateur sous 24 h. | Mis à `NULL` sur les événements au bout de **24 heures** |
| Palier de proximité (1 ou 2) | Pondère les gestes, « présent » comme « résolu » (§6.1, §6.2). Deux valeurs discrètes au lieu d'une distance continue : ne permet pas de reconstituer un trajet. | Vie de l'événement |
| Horodatage | Ancienneté d'un signalement, expiration automatique, ordre des événements, mesures de la bêta. | **Précision conservée**, pas d'arrondi |
| Photo, facultative | Vérifier la réalité et la gravité d'un signalement. | Supprimée du stockage objet quand le danger passe en `archived` |
| Commentaire, 140 caractères, facultatif | Préciser le danger. Le libellé du champ prévient qu'il est public. | Vie du signalement |

**La fenêtre de corrélation est le seul vrai garde-fou, et c'est voulu.** Position du danger et
horodatage sont tous deux conservés à pleine précision, parce que le produit ne fonctionne pas
autrement. Un événement de création dit donc « quelqu'un était ici, à cette seconde ». Ce qui
empêche d'en faire un profil, c'est l'impossibilité de relier ces événements entre eux : tant
que `device_id` y figure, tous les signalements d'une même personne sont reliables et
redessinent ses itinéraires habituels.

**Cette fenêtre est de 24 heures** (amendement ; elle valait 90 jours). Elle est calée sur la
seule fonction qui a réellement besoin du lien, le retrait par le créateur, qui dure exactement
24 h (§6.1). Quatre-vingt-dix jours étaient un héritage de l'anti-abus, reporté en phase 2
(§4.6) : on conservait de quoi relier trois mois de trajets pour une fonction qu'on ne
construisait pas. Le cron passe toutes les heures, sans quoi un geste fait juste après le
passage nocturne aurait gardé son lien 48 heures.

**Ce que ça coûte.** `events_one_per_device` porte sur `(hazard_id, device_id, type)`, et deux
`NULL` ne se contredisent pas : passé la fenêtre, un terminal peut voter à nouveau sur le même
danger. Une voix par jour et par danger, là où le §6.1 veut deux terminaux distincts.

**Mais il faut voir ce que cette contrainte valait déjà.** Mesuré sur l'instance :

| Scénario | Compteur |
|---|---|
| premier vote d'un terminal | 6 → 7 |
| second vote du **même** terminal, app fermée puis rouverte | 7 → 7 |
| après « Régénérer mon identifiant », **un appui** | 7 → 8 |

Fermer et rouvrir l'app ne change rien : l'identifiant est persistant. Mais il est **auto-attribué
et jetable**, et le §11.4 offre de le renouveler en un geste, sans délai ni question. L'index
n'a donc jamais protégé contre quelqu'un qui le veut — il empêche le double vote **accidentel**,
et c'est tout ce qu'il a jamais fait. Passer de 90 jours à 24 heures ne change pas la nature de
cette protection, seulement sa durée dans le cas honnête.

Corollaire : le **pseudonyme par danger**, `hmac(device_id, hazard_id, secret)`, restaure la
contrainte sans rétablir le lien entre deux dangers — mais il ne résiste pas davantage à une
régénération d'identifiant. La vraie réponse est ailleurs, dans l'anti-abus du §6.3 reporté en
phase 2 : réputation, limitation de débit, quorum exigeant. **À trancher avant toute ouverture
publique**, en sachant que le problème est celui de l'identité auto-attribuée, pas celui de la
fenêtre de corrélation.

Autrement dit, la minimisation porte sur le **lien** entre les données, pas sur leur précision.
Dégrader la précision casserait le produit ; couper le lien ne coûte rien.

### 11.3 Photos

- EXIF supprimé sur le terminal **avant** l'envoi, et de nouveau côté serveur.
- Recompression à 1600 px, ce qui dégrade au passage la lisibilité des plaques.
- Consigne à l'écran : « Cadrez le danger, pas les personnes ni les plaques ».
- Floutage automatique des visages et des plaques en V2.
- C'est le seul contenu du système qui peut porter la donnée personnelle d'un tiers. En cas de
  doute pendant la bêta, on supprime.

### 11.4 Droits et effacement

- **Régénérer son identifiant**, dans les paramètres, à tout moment. Coupe le lien avec toutes
  les actions passées, immédiatement et sans rien demander à personne. **Sans délai minimal, et
  c'est délibéré** : imposer « une fois par 24 h » supposerait de mémoriser que tel identifiant
  remplace tel autre, c'est-à-dire d'écrire le lien qu'on vient de couper. Un verrou local, lui,
  ne verrouille rien — effacer les données de l'app donne un identifiant neuf en deux gestes, et
  l'API accepte de toute façon n'importe quel UUID de n'importe qui. Le verrou ne retarderait
  donc que les usages légitimes, dont celui de quelqu'un qui vient de se faire voler son
  téléphone. Ce qui marche est ailleurs : une identité **émise** par le serveur et coûteuse à
  obtenir (§6.3, phase 2). L'écran F8 affiche une confirmation, pas un délai.
- **Effacer mes données** met `device_id` à `NULL` sur tous les événements. Les signalements
  restent : ce sont des données sur la voirie, pas sur la personne.
- **Un seul bouton pour les deux** (amendement, bêta). « Régénérer » et « Effacer » coupaient le
  même lien par ses deux bouts ; à l'écran, deux boutons qui promettent la même chose rendaient
  le choix confus sans rien protéger de plus. « Effacer mes données » fait désormais les deux :
  le serveur oublie, puis le téléphone tire un numéro neuf. La partie locale ne dépend de
  personne et se fait toujours ; si le serveur est injoignable, l'app le dit, et le lien avec
  l'ancien numéro tient jusqu'à la coupure automatique des 24 heures.
- **Retirer mes signalements récents** (amendement, bêta). Quelqu'un a fait des essais, ou
  l'idiot, et veut nettoyer ; or la carte ne dit pas lesquels sont les siens (`created_by` n'est
  pas exposé), donc les retirer un par un suppose de les retrouver de mémoire. Un geste retire
  d'un coup tous les siens de moins de 24 heures, aux conditions exactes de `remove_own_hazard`
  (§6.1) : même fenêtre, même événement `remove` au journal, aucune suppression physique.
  Au-delà de 24 heures il n'y a rien à retirer par construction — le lien est coupé — et c'est la
  confidentialité qui borne ce droit, pas une réticence. En ligne seulement : c'est un geste de
  nettoyage, pas un geste de terrain à mettre en file (§10).
- ~~**Exporter mes signalements**~~ **abandonné** (amendement). L'app ne sait pas lesquels sont
  les siens : `created_by` n'est pas exposé, et le lien est coupé à 24 heures (§11.2). Le
  construire supposerait soit une liste locale de ses propres signalements — un historique
  personnel permanent sur le disque, exactement ce que le §11.7 efface — soit un export qui ne
  rendrait jamais plus que la dernière journée. Les deux sont pires que l'absence : on ne promet
  pas un droit qu'on servirait à moitié.
- **Effacement réel** d'une ligne, de ses événements et de ses photos : purge administrateur
  (§4.3), seul chemin irréversible.

**L'identifiant de terminal est un porteur, pas une preuve.** `forget_device`, `remove_own_hazard`
et `remove_own_recent_hazards` sont exécutables par `anon` avec le seul UUID : qui le connaît agit comme ce
terminal. C'est le prix de l'absence de compte, et c'est tenable parce que l'UUID n'est exposé
nulle part — ni dans l'API publique (`created_by` est exclu du `GRANT`, `events` et `devices`
n'ont aucune policy), ni dans la chronologie d'un danger, ni dans une sauvegarde Android. Il n'y
a en revanche aucun second facteur : une fuite de l'UUID donne à un tiers le pouvoir d'effacer
ce lien, jamais celui de lire quoi que ce soit.

### 11.5 Cadre

- **Base légale** : intérêt légitime. Politique de confidentialité en une page dans l'app,
  rédigée pour être lue. Le texte source est [PRIVACY.md](PRIVACY.md) ; l'écran F8 l'affichera
  tel quel. Chaque affirmation y renvoie au fichier qui la met en œuvre, pour qu'elle puisse
  être vérifiée plutôt que crue.
- **Responsable de traitement** : l'association éditrice (§12.6). Non constituée pendant la bêta
  fermée, obligatoire avant toute ouverture publique.
- **Sous-traitants** : aucun. Tout est auto-hébergé sur un VPS unique, y compris le fond de carte
  et le géocodage inverse (§7).
- **Rapports d'erreur** : GlitchTip auto-hébergé, sans contenu utilisateur dans les traces, et
  désactivable dans les paramètres.

### 11.6 Précision géographique : exigence produit

La position d'un nid-de-poule doit être exacte à quelques mètres. En dessous, un usager ne
peut pas l'anticiper, l'anti-doublon du §4.1 ne reconnaît plus un danger déjà signalé, et la
carte perd son intérêt. Cette précision prime sur toute considération de minimisation.

- `geometry(Point, 4326)` en double précision. **Aucun arrondi, aucun décalage, aucun bruit**
  ajouté au stockage comme à la restitution.
- Le GPS grand public donne 5 à 15 m en ville dense, davantage entre des immeubles hauts. La
  position brute ne suffit donc pas : le **pin reste déplaçable à la main** sur une mini-carte
  (F2), et c'est lui qui porte la précision réelle, pas le capteur.
- Zoom minimal imposé avant de pouvoir valider un signalement, pour que le geste d'ajustement
  ait un sens.
- Conséquence sur le rayon anti-doublon : à 15 m, deux relevés GPS du même trou peuvent tomber
  au-delà du seuil. C'est précisément l'une des questions à trancher pendant la bêta (§4.6).

Rien de tout cela n'entre en conflit avec le §11 : la position du **danger** est une donnée sur
la voirie. C'est la position de la **personne** qui n'est jamais conservée.

### 11.7 Ce que l'appareil garde, et pendant combien de temps

**Exigence : quelqu'un qui volerait le téléphone et obtiendrait un accès complet à son contenu
ne doit y trouver aucune trace de plus d'une heure de l'endroit où l'appareil est passé.**

Aucune position GPS n'est écrite, ni ici ni ailleurs (§11.1). Mais afficher une carte laisse des
traces d'un autre genre, qui disent « cette zone a été regardée » — ce qui revient au même en
pratique :

| Fichier | Trace | Durée de vie |
|---|---|---|
| `mbgl-offline.db`, table `tiles` | tuiles du fond de carte, z/x/y et heure d'accès | **45 min / 1 h 30** |
| `app.sqlite`, `cached_areas` | rectangles chargés, horodatés | **45 min / 1 h 30** |
| `app.sqlite`, `cached_hazards` | dangers de ces rectangles | **45 min / 1 h 30** |
| `mbgl-offline.db`, table `regions` | bornes d'une zone téléchargée | **jusqu'à suppression** |
| Instantané « applis récentes » | image de la carte centrée sur la personne | refusé à Android 13+ |
| `FlutterSecureStorage` | identifiant de terminal, chiffré | pas une trace de lieu |

**Deux chiffres, et le second est celui qui engage.** 45 minutes est l'âge toléré pendant qu'on
regarde la carte : la purge se fait à l'âge, pour que la vue en cours survive. 1 h 30 est le
plafond, et il se calcule au lieu de s'espérer :

```
   45 min   âge toléré au premier plan
+   5 min   intervalle entre deux passages (TraceHorizon.interval)
+  20 min   délai de l'alarme (TraceSweeper.ALARM_DELAY_MS)
+  15 min   fenêtre de report qu'Android s'accorde — 75 % du délai
= 85 min
```

La fenêtre est mesurée, pas supposée : `dumpsys alarm` annonce `window=+33m44s` pour une alarme
à 45 min, et `window=+14m59s` après passage à 20 min. C'est ce qui a imposé de raccourcir le
délai — le premier réglage plafonnait en réalité à plus de deux heures.

**Quand l'alarme se déclenche, elle n'efface pas à l'âge : elle efface tout** ce qui n'appartient
pas à une zone téléchargée. Sans cela, ce qu'elle épargnerait faute d'être assez vieux ne serait
repris par personne, et le plafond n'existerait plus.

L'alarme est inexacte. `setExactAndAllowWhileIdle` demanderait `SCHEDULE_EXACT_ALARM`, que la
personne doit accorder à la main, ou `USE_EXACT_ALARM`, réservée aux réveils et minuteurs :
aucune des deux n'est honnête ici. Le quota d'alarmes par bucket de veille ne mord pas — elle
est toujours programmée juste après un usage actif, donc l'app est au mieux de son classement.

Le mécanisme est en Kotlin (`TraceSweeper`), pour deux raisons. **Rien de Flutter ne tourne
quand l'app est en arrière-plan** : regarder la carte puis empocher le téléphone laisserait la
trace intacte jusqu'à la prochaine ouverture. Et la coupure se fait **à l'âge**, par SQL direct,
là où `clearAmbientCache()` du plugin efface tout ou rien — appelée en pleine sortie, elle
rendrait la carte blanche au moment précis où on roule dessus.

**Une zone téléchargée est l'exception, et elle est assumée.** Elle stocke ses bornes en clair et
ne s'efface jamais toute seule : c'est le sens même de la fonctionnalité. C'est aussi la seule
trace que la personne crée délibérément, qu'elle voit listée, et qu'elle supprime d'un geste.
Le panneau le dit en toutes lettres.

Conséquence assumée sur le hors-ligne (§10) : **le cache sert la sortie en cours et l'a oubliée
avant qu'on rentre.** Rouvrir l'app sans réseau une heure après affiche « zone jamais chargée ».
C'est le prix de l'exigence ci-dessus, et c'est le bon arbitrage pour une app qu'on utilise en
roulant.

---

## 12. Licences et identité

### 12.1 Décision : licence scindée (validée)

| Composant | Licence | Raison |
|---|---|---|
| Serveur : schéma SQL, fonctions RPC, Docker Compose | **AGPL-3.0** | C'est le seul endroit où la clause réseau a un sens. Quiconque héberge un fork public doit publier ses modifications. |
| Site web public et console admin | **AGPL-3.0** | Livrés par un navigateur, jamais par un store : le conflit du §12.2 ne s'y pose pas. La clause réseau s'y applique naturellement. |
| App Flutter | **Apache-2.0** | Évite le blocage App Store décrit en §12.2. Le client est une coquille au-dessus d'une API publique : il n'y a rien à protéger. Le brevet explicite d'Apache-2.0 vaut mieux que MIT pour un texte à peine plus long. |
| Données | **ODbL 1.0** | La valeur réelle du projet. Partage à l'identique, compatible OSM. |

### 12.2 Pourquoi pas l'AGPL sur l'app : le blocage App Store

Les conditions de distribution d'Apple imposent aux utilisateurs finaux des restrictions que la
GPL et l'AGPL interdisent d'ajouter : verrouillage DRM du binaire et limitation du nombre
d'appareils. L'AGPL-3.0 prévoit qu'en cas d'obligations inconciliables, on ne peut pas
distribuer du tout. VLC a été retiré de l'App Store en 2011 sur ce fondement, à la demande d'un
de ses propres développeurs.

Le détenteur du copyright peut lever le conflit en accordant une permission additionnelle, mais
seulement tant qu'il détient seul les droits. Dès qu'un contributeur extérieur fait accepter un
correctif sous AGPL, il acquiert la capacité de s'y opposer. Pour un projet civique qui cherche
des contributions, mettre l'app sous AGPL revient à parier que personne ne contribuera jamais,
ou à imposer un accord de contribution qui décourage justement les contributions.

### 12.3 Ce que l'AGPL protégerait vraiment ici

La crainte habituelle est qu'un tiers reprenne le code, héberge un service concurrent et ne
rende rien. Appliquée à l'application, elle tient mal :

- Le code vaut environ huit semaines de travail et reste reproductible. La valeur est dans la
  base de signalements et dans les utilisateurs parisiens actifs.
- Un concurrent ne fragmenterait pas le projet par le code mais par une base séparée. L'AGPL
  n'empêche rien de tel. Le partage à l'identique de l'ODbL sur les données est le seul vrai levier.
- Ce qui empêche une reprise trompeuse est la marque, pas la licence. Réserver le nom de l'application
  à l'INPI coûte quelques centaines d'euros et protège mieux que n'importe quel copyleft.

L'AGPL garde un intérêt réel côté serveur : elle garantit qu'une collectivité ou une société
qui déploierait sa propre instance publie ses adaptations. Le coût y est nul, puisqu'il n'y a
ni App Store ni distribution binaire.

### 12.4 Le sens unique à connaître

Tant que tu es seul auteur, tu relicencies comme tu veux. Dès que des contributions extérieures
arrivent sans accord de contribution, il faut l'accord de chaque contributeur pour changer de
licence. Passer d'AGPL à MIT devient alors très difficile.

L'inverse ne fonctionne pas non plus comme un filet de sécurité : partir en MIT puis durcir en
AGPL ne vaut que pour les versions futures, le code déjà publié en MIT le reste pour toujours.
La décision se prend donc maintenant, pas plus tard.

### 12.5 Attribution

- Carte : « © OpenStreetMap contributors » visible en permanence.
- Données importées : mention de la Ville de Paris selon les termes du jeu source.
- On n'écrit pas dans OSM : un danger est une donnée éphémère, hors périmètre OSM.

### 12.6 Publier sans exposer son identité personnelle

**Constat : aucune publication réellement anonyme n'est possible sur les deux stores.**

| Store | Compte individuel | Compte organisation |
|---|---|---|
| App Store | Le nom légal est affiché comme vendeur, partout. Dans l'UE, le DSA (art. 30 et 31) impose en plus d'afficher adresse, téléphone et e-mail sur la fiche produit. Déclarer le statut « non-trader », envisageable pour une app gratuite et non commerciale, n'y change rien pour un compte individuel : Apple exige quand même une adresse ou boîte postale, un téléphone et un e-mail publiquement affichés. | Le nom de l'entité légale apparaît comme vendeur. Numéro D-U-N-S obligatoire. L'adresse publique est tirée de la fiche D-U-N-S. Apple refuse les noms commerciaux et les enseignes. |
| Google Play | Vérification d'identité obligatoire : pièce d'identité et justificatif de domicile. Adresse résidentielle exigée, ni boîte postale ni domiciliation. Sont affichés publiquement le nom légal, le pays et l'e-mail. L'adresse complète devient publique en cas d'achats intégrés, que l'application n'aura pas. | Nom de l'organisation, D-U-N-S requis. |

**La porte de sortie Android se referme aussi.** Google étend la vérification d'identité aux apps
installées hors du Play Store. L'obligation entre en vigueur le 30 septembre 2026 pour sept
boutiques partenaires au Brésil, en Indonésie, à Singapour et en Thaïlande, avec un déploiement
mondial annoncé pour 2027. F-Droid, dont une partie des développeurs publient sous pseudonyme,
qualifie la mesure de menace existentielle et a publié une lettre ouverte en février 2026.
L'installation restera possible via ADB ou un parcours « avancé », avec avertissements. Miser sur
F-Droid seul fonctionne aujourd'hui en France, mais avec une échéance visible.

**Décision : v0 sur F-Droid, sans enregistrement développeur.** Publication pseudonyme possible
tout de suite, sans association, sans D-U-N-S et sans frais. Le tableau ci-dessus explique
pourquoi c'est la seule voie qui préserve l'anonymat aujourd'hui.

**Ce que cette décision coûte.**

- **Android seulement, pas d'iOS.** Il n'existe aucun équivalent de F-Droid sur iOS. Les
  boutiques alternatives ouvertes dans l'UE par le DMA exigent malgré tout un compte développeur
  Apple vérifié et une notarisation par Apple. L'anonymat et iOS sont incompatibles, sans
  contournement.
- Conséquence produit, à ne pas sous-estimer : le modèle collaboratif du §4.4 repose sur le
  recoupement, c'est-à-dire sur le nombre de personnes qui empruntent le même axe. Se priver de
  la base iOS réduit d'autant la densité dont dépend toute la mécanique de confirmation.
- Audience de F-Droid très réduite, qui se cumule avec la carte vide et le périmètre restreint.
  L'acquisition devient le point faible du pilote (§15).
- L'échéance de vérification décrite plus haut reste devant nous : mondiale annoncée pour 2027.

**Deux voies sur F-Droid, à mener dans cet ordre.**

| Voie | Délai | Pour |
|---|---|---|
| Dépôt F-Droid personnel, auto-hébergé à côté du site | immédiat, aucune revue | Bêta, itérations rapides, contrôle total des mises à jour. L'utilisateur doit ajouter le dépôt à la main. |
| Dépôt F-Droid officiel | plusieurs semaines de revue | Découvrabilité. Impose la conformité stricte : sources publiques, build reproductible côté F-Droid, aucune dépendance propriétaire. |

**Contrainte technique qui en découle, à traiter dès le développement.** F-Droid refuse les
dépendances propriétaires. La stack du §7 est déjà compatible par construction : GlitchTip et non
Sentry hébergé, ntfy et UnifiedPush et non Firebase Cloud Messaging, MapLibre et non un SDK
cartographique fermé. Un point de vigilance subsiste : le paquet `geolocator` utilise par défaut
le service de localisation fusionnée des Google Play Services sur Android. Il faut forcer le
`LocationManager` natif (`AndroidSettings(forceLocationManager: true)`), sans quoi l'app est
rejetée du dépôt officiel ou signalée comme dépendante d'un composant non libre.

**Prévenir sans magasin (amendement, bêta).** Le client F-Droid n'annonce les mises à jour qu'à
ceux qui ont ajouté le dépôt. Pour les autres, l'app lit à chaque lancement et à chaque retour au premier plan
`https://<domaine>/fdroid/latest.json`, écrit par le script de publication à côté de la page de
téléchargement, et affiche un bandeau quand le `versionCode` publié dépasse le sien. Trois
garde-fous : la requête ne porte aucune donnée, pas même la version installée ; l'app refuse un
APK hébergé sur un autre domaine que le sien, même si son serveur le lui demande (§11.5) ; et rien
ne s'installe sans un geste, Android l'interdisant hors magasin. Le fichier peut porter une
version minimale exigée — le bandeau passe alors devant tout — et une ligne libre.

**L'association n'est pas annulée, elle est différée.** Elle redevient nécessaire dans deux cas,
qui arriveront tous les deux :

1. **Avant l'ouverture publique.** Le RGPD impose de nommer le responsable de traitement dans la
   politique de confidentialité (§11), et l'obligation naît du service, pas du canal de
   distribution. F-Droid ne change rien à ce point. Une bêta fermée entre gens qui se connaissent
   reste proportionnée ; un service ouvert aux Parisiens ne l'est plus.
2. **Le jour où iOS devient nécessaire**, ou une publication sur le Play Store.

Rien n'oblige à la déclarer maintenant. Il faut seulement l'avoir déclarée avant d'ouvrir au
public, en gardant à l'esprit les semaines de délai administratif.

**Modalités, pour mémoire, quand le moment viendra.** Déclaration gratuite en préfecture,
publication au JOAFE, numéro RNA puis SIREN, puis D-U-N-S gratuit. Siège à une adresse de
domiciliation, **jamais à ton domicile** : cette adresse devient publique. Apple Developer Program
99 $ par an, Google Play 25 $ une fois. L'association ne rend pas anonyme vis-à-vis de l'État :
le RNA conserve la liste des dirigeants à destination des services de l'État, et sa version
rénovée doit faire apparaître les bénéficiaires effectifs. Le JOAFE ne publie que le titre,
l'objet et le siège.

### 12.7 Identité des contributeurs

Beaucoup plus simple, et entièrement sous ton contrôle.

- **Pas de CLA.** Aucun accord de contribution n'est nécessaire, puisqu'aucune relicence n'est
  prévue (§12.4). Un CLA exigerait une identité vérifiable, soit précisément ce qu'on évite.
- **Pas de DCO non plus.** Le texte du Developer Certificate of Origin demande une signature avec
  un « real name ». L'adopter fermerait la porte aux pseudonymes.
- L'AGPL-3.0 et l'Apache-2.0 n'imposent aucune identification des contributeurs. Un pseudonyme et
  une adresse e-mail suffisent.
- Forge auto-hébergée (Forgejo) ou Codeberg, qui acceptent les comptes pseudonymes, plutôt qu'une
  plateforme qui pousse à la vérification d'identité.
- Contrepartie assumée : sans CLA ni DCO, la licence du dépôt devient définitive (§12.4). C'est
  cohérent avec le choix déjà arrêté.

---

## 13. Ce qu'on mesure

### 13.1 Bêta fermée

Les questions et leurs mesures sont en §4.6. Il n'y a pas de cible chiffrée : une bêta sert à
apprendre, pas à atteindre un score.

### 13.2 Ouverture publique (plus tard)

| Indicateur | Cible |
|---|---|
| Temps médian pour créer un signalement | < 15 s |
| Dangers confirmés par ≥ 2 devices dans le mois | ≥ 30 % |
| Signalements flaggés | < 2 % |
| Délai médian entre résolution réelle et statut `resolved` (échantillon manuel) | < 14 jours |
| Utilisateurs actifs hebdo | 50 à la fin du 2ᵉ mois |
| Couverture | ≥ 200 dangers actifs intra-muros à la fin du 1ᵉʳ mois |

---

## 14. Feuille de route

### Phase 1 — jusqu'à la bêta fermée

| Semaines | Livrable |
|---|---|
| 1–2 | Schéma Postgres (§5), fonctions RPC (§6, §8), Docker Compose, tests SQL des règles de modération, PMTiles France servi. |
| 3–5 | App Flutter : carte, catalogue, créer, confirmer, résolu, détail. |
| 6 | Hors-ligne, paramètres, instrumentation **locale** des mesures du §4.6 (§11.1). Photos abandonnées pour la bêta (§4.6 amendé). |
| 7 | Build Android sans dépendance propriétaire, dépôt F-Droid auto-hébergé, GlitchTip. |
| 8+ | Bêta fermée sur les axes visés (§4.4). Administration via Supabase Studio. |

Environ huit semaines. Le périmètre réduit du §4.6 économise cinq semaines par rapport à la
cible complète.

### Phase 2 — ouverture publique (non planifiée)

Dans cet ordre, quand la décision d'ouvrir sera prise :

1. Anti-abus effectif : flags, réputation, shadow-ban, rate limiting, cron d'expiration.
2. Console d'administration (§4.3), avant toute augmentation de l'exposition.
3. Déclaration de l'association (§12.6), préalable au site public. Plusieurs semaines de délai
   administratif, à lancer en avance.
4. Site web public (§4.2), une fois le responsable de traitement nommé.
5. Soumission au dépôt F-Droid officiel.
6. Publication sur les stores si iOS devient nécessaire.

---

## 15. Risques

| Risque | Mitigation |
|---|---|
| Acquisition : F-Droid seul, pas d'iOS, carte vide, périmètre restreint. Les quatre se cumulent. | Risque le plus élevé du pilote, assumé. Bêta fermée d'abord, recrutement direct sur les axes visés, publication sur les stores dès que l'association existe. |
| Carte vide → abandon (risque n°1, assumé) | Périmètre restreint aux axes à fort trafic, pré-remplissage personnel pendant les tests, pas d'élargissement avant d'atteindre le taux de confirmation croisée. |
| Vandalisme coordonné | Journal rejouable, shadow-ban, console d'administration. |
| Vérification développeur Android étendue au sideloading (mondiale annoncée pour 2027) | Suivre le calendrier. L'association et une publication Play deviennent le plan de repli, d'où l'intérêt de ne pas trop différer sa déclaration. |
| Compromission d'un compte admin | 2FA obligatoire, rôle vérifié en RLS et non côté client, sous-domaine séparé, journal d'audit inaltérable, purge sous double confirmation. |
| Purge accidentelle par un admin | Le retrait réversible est l'action par défaut ; la purge exige un motif et une seconde confirmation, et reste tracée. |
| Dangers résolus jamais marqués | Expiration automatique par type, calque « à vérifier ». |
| Dilution du message si trop de types | Types gelés, un seul activé. Activation par la donnée, après le pilote. |
| Coût des tuiles si trafic | PMTiles statique derrière Caddy, CDN si besoin. |
| Refus des stores (app « trop simple ») | Onboarding soigné, fiche store claire, carte web en parallèle. |
| Ville indifférente | Le produit vaut par lui-même ; DansMaRue / Open311 quand le volume le justifie. |

---

## 16. Questions ouvertes ❓

**Aucune ne bloque la bêta.** Les deux se posent en phase 2, au moment de créer l'association.

1. **Domiciliation du siège** de l'association. Adresse de domiciliation payante, structure
   d'hébergement d'associations, ou maison des associations d'un arrondissement ? Cette adresse
   sera publique.
2. **Marque.** Faire déposer le nom de l'application à l'INPI par l'association, classes 9 et 42, quelques
   centaines d'euros. C'est ce qui protège le nom contre une reprise trompeuse, bien mieux que la
   licence (§12.3), et le dépôt par l'association évite d'associer ton nom à la marque. À décider
   avant la mise en ligne publique du code.

---

## 17. Récapitulatif des décisions

| # | Sujet | Décision |
|---|---|---|
| 1 | Comptes utilisateurs | Aucun. Identité anonyme par device, réputation implicite. |
| 2 | Périmètre fonctionnel | Modèle multi-danger dès la v1, seul `pothole` activé. Autres types gelés. |
| 3 | Mobile | Flutter, MapLibre, drift. Pas de PWA. |
| 4 | Ville pilote | Paris, axes à fort trafic. |
| 5 | Nom | L'application. |
| 6 | Partenariat | Aucun. |
| 7 | Amorçage | Carte vide, aucun import. |
| 8 | Licences | AGPL-3.0 serveur, Apache-2.0 app, ODbL données. |
| 9 | Suppression côté utilisateurs | Vote « résolu » pondéré, seuil de 2 devices distincts, retrait par le créateur sous 24 h. Un danger résolu quitte la carte, l'auteur ne confirme pas son propre signalement, et les seuils comme les paliers de proximité s'éditent dans la console — les mêmes pour tous les types. Les confirmations pèsent comme les votes, un signalement vaut N confirmations (3), et la proximité n'a que deux paliers, « sur place » (≤ 100 m, poids 1) et « ailleurs » (⅓) (amendements, §6.1, §6.2). |
| 10 | Surfaces | App Flutter, site web public en lecture seule, console d'administration. Les trois en v1. |
| 11 | Contribution depuis le web | Interdite. L'anti-abus repose sur l'identité de device et le GPS. |
| 12 | Suppression côté admin | Trois niveaux : retirer (réversible, par défaut), annuler un device, purger (irréversible, motif obligatoire). |
| 13 | Objectif immédiat | Bêta fermée. Anti-abus, console, site public et association reportés en phase 2. |
| 14 | Distribution v0 | Dépôt F-Droid auto-hébergé et page de téléchargement, sans enregistrement développeur, publication pseudonyme. L'app se prévient elle-même d'une version plus récente, depuis son seul serveur (amendement, §12.6). Android uniquement, pas d'iOS. |
| 15 | Éditeur | Association loi 1901, différée. Obligatoire avant l'ouverture publique (RGPD) et avant toute publication sur les stores. |
| 16 | Contributeurs | Pseudonymes acceptés. Ni CLA ni DCO. |
| 17 | Données utilisateurs | Minimisation du **lien**, pas de la précision. Position du déclarant jamais stockée, aucune analytics, `device_id` effacé des événements après 24 heures, aucun service tiers (§11). |
| 18 | Précision géographique | Position du danger et horodatage conservés à pleine précision, sans arrondi. Exigence produit (§11.6). |

Le cadrage est clos. L'étape suivante est le schéma Postgres et les fonctions de modération du
§6, qui ne dépendent d'aucune décision en attente et servent aussi bien la bêta que l'ouverture.
