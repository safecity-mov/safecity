# L'application — app Android

Flutter, MapLibre Native, Android 8+. Licence : **Apache-2.0** (SPEC §12.1 — l'AGPL
bloquerait une publication iOS ultérieure, cf. §12.2).

## Lancer en développement

Le serveur doit tourner (`cd ../server && make up`). Il publie un point d'entrée HTTP en clair
sur `127.0.0.1:8080`. Une seule commande le rend joignable, **émulateur et téléphone
confondus** :

```sh
adb reverse tcp:8080 tcp:8080   # à refaire après chaque rebranchement
flutter pub get
flutter run
```

`adb reverse` renvoie le port du serveur **dans** l'appareil : `127.0.0.1:8080` y atteint le
poste de développement. C'est le défaut de `AppConfig`, il n'y a rien à passer.

**`127.0.0.1` et non `localhost`.** Le nom résout vers `::1` *et* `127.0.0.1`, et sans réseau la
tentative IPv6 traîne avant de basculer sur IPv4. Mesuré sur un Pixel 9 en mode avion : **8 123
ms** pour échouer sur `localhost`, **121 ms** sur `127.0.0.1`, pour la même erreur « connexion
refusée ». C'est ce qui faisait attendre dix secondes devant un écran blanc au lancement hors
ligne, puis dix de plus avant que les dangers du cache n'apparaissent — un cache instantané
précédé de deux délais réseau. L'émulateur ne le montre pas : il échoue en 76 ms.

**Le cache de tuiles de MapLibre est indexé par URL.** Changer l'adresse de base l'a donc vidé
d'un coup : les 36 tuiles et 11 polices gardées l'étaient sous `http://localhost:8080/…`, plus
rien ne les retrouvait. Hors ligne, la carte reste alors blanche pendant que les marqueurs
s'affichent — eux viennent de notre propre base. Il faut repasser en ligne une fois pour la
regarnir. À retenir avant de toucher à `APP_TILES`.

**Et 36 tuiles, c'est presque rien.** Le cache ambiant de MapLibre n'est pas dimensionnable
depuis ce plugin : seul `downloadOfflineRegion` l'est, et le §10 réserve le téléchargement de
l'Île-de-France à la V2. Sur un vrai trajet, le fond de carte sera donc blanc dès qu'on sort de
ce qu'on vient de consulter. À savoir avant de lire les résultats de la bêta sur le hors-ligne
(§4.6) : la file d'attente et le cache de dangers tiennent, le fond de carte non. Le point
d'entrée en clair de Caddy reste publié sur `127.0.0.1` uniquement, donc rien n'apparaît sur
le Wi-Fi — contrairement à ce qu'imposerait de viser l'IP locale du poste.

Sur un téléphone : brancher en USB, débogage USB activé, le reste est identique.

**Ne pas compter sur `--dart-define` en debug.** Ces constantes ne sont figées à la
compilation qu'en build AOT (`--release`, `--profile`). En debug, `flutter run` les fournit au
lancement : l'app rouverte depuis l'écran d'accueil ne les a plus et retombe sur les valeurs
par défaut. C'est pourquoi le défaut doit marcher tel quel.

Le HTTP en clair n'est autorisé qu'en build de debug, et seulement vers `localhost` et
`10.0.2.2` : voir `android/app/src/debug/res/xml/network_security_config.xml`. En release,
tout passe par HTTPS derrière Caddy.

### Piloter l'émulateur

Le zoom de la carte se fait à deux doigts, que le trackpad ne simule pas tout seul : maintenir
**⌘** (ou Ctrl) puis glisser fait apparaître les deux points de contact. Le double-tap
maintenu suivi d'un glissement vers le haut dézoome à un doigt. Et si les clics ne semblent
pas arriver à l'app, vérifier que le **mode zoom** (la loupe dans la barre d'outils de
l'émulateur) est désactivé : quand il est actif, il intercepte les clics pour agrandir la
fenêtre au lieu de les transmettre.

Pour avoir des dangers à l'écran : `docker compose exec -T db psql -U postgres -d app
-f /db/seed-demo.sql` côté serveur.

## Les tests

```sh
flutter test      # 57 assertions
flutter analyze
```

Un build de publication se fait par [`deploy/release-app.sh`](../deploy/release-app.sh), qui
enchaîne les deux avant de construire, et refuse de publier un APK signé en debug.

| Fichier | Ce qu'il vérifie |
|---|---|
| `hazard_model_test.dart` | Décodage RPC et GeoJSON, précision intacte, statut inconnu sans casse |
| `api_client_test.dart` | Anti-doublon, position omise quand elle manque, messages du serveur |
| `report_sheet_test.dart` | Sélecteur de type masqué à un seul type, niveau obligatoire, 140 caractères |
| `hazard_detail_sheet_test.dart` | Verbe de résolution issu du catalogue, bandeaux d'état, pas d'identifiant de terminal |
| `map_filters_test.dart` | Filtres de type et de niveau |
| `marker_icons_test.dart` | Source GeoJSON minimale, noms d'images cohérents avec le style |

Ce que les tests ne couvrent pas : l'écran de carte lui-même (`MapScreen`), qui a besoin
d'une vraie surface MapLibre. Vérifié à la main sur émulateur — fond de carte, marqueurs aux
trois niveaux, clustering avec compteur au dézoom, tap, cycle complet créer / doublon /
confirmer / résoudre.

## Organisation

```
lib/src/
  config.dart              adresses de l'instance, centre et zooms
  data/                    modèles, client RPC, identité de device
  location/                canal natif de localisation
  ui/                      carte, signalement, détail, onboarding
assets/map_style.json      style MapLibre, servi depuis l'instance
android/app/src/main/kotlin/…/LocationChannel.kt
```

## Deux points à connaître avant de toucher au code

### La localisation ne passe pas par `geolocator`

La spec (§12.6) prescrit `geolocator` configuré avec `AndroidSettings(forceLocationManager:
true)`. **Cela ne suffit pas** : l'option change le chemin d'exécution, pas le contenu du
binaire. L'APK construit ainsi embarquait 17 classes `com.google.android.gms`, vérifié en
désassemblant les `.dex`. F-Droid refuse les dépendances propriétaires, donc elles ne
doivent pas être dans l'arbre de build du tout.

D'où [`LocationChannel.kt`](android/app/src/main/kotlin/me/safe/LocationChannel.kt),
qui parle directement au `LocationManager` d'Android. L'app n'a besoin que d'une position
ponctuelle au moment d'un geste, ce qui tient en une centaine de lignes. Un garde-fou Gradle
exclut `com.google.android.gms` et `com.google.firebase` : le build casse plutôt que de
laisser rentrer un blob par une dépendance transitive.

Il reste 10 références GMS dans l'APK **de debug**, toutes venant de MapLibre, sans aucune
implémentation liée. Le code qui les utilise n'est pas atteint : la carte est construite avec
`myLocationEnabled: false`. En release, R8 les retire entièrement — il n'en reste aucune dans
le `.dex` publié.

C'est d'ailleurs R8 qui a révélé le seul obstacle au premier build de publication : il refuse
de compiler devant une référence qu'il ne peut pas résoudre, et ces classes-là sont absentes
exprès. `android/app/proguard-rules.pro` les déclare une à une — nommément, jamais en
`com.google.android.gms.**`, pour qu'une nouvelle référence amenée par une dépendance casse
le build au lieu de se fondre dans un joker. Ce fichier n'a d'effet qu'en release : rien en
développement ne dit s'il est juste.

### La permission est redemandée au moment du geste

Android accorde volontiers la localisation « une seule fois », puis la révoque dès que l'app
repasse en arrière-plan. Constaté sur un Pixel 9 : deux signalements d'affilée, le premier en
palier 1 (poids 1), le second en palier 3 (poids 0,25) sans que l'utilisateur ait bougé ni
été prévenu.

C'est doublement gênant — l'utilisateur croit peser sur la carte alors qu'il pèse un quart, et
la pondération du §6.2 se dégrade en silence alors que c'est une des mesures de la bêta (§4.6).
D'où deux garde-fous : la permission est redemandée au moment du geste s'il elle a sauté, et un
envoi parti sans position le dit explicitement. Refuser reste possible, ce n'est simplement plus
invisible (§11.1).

### L'indicateur de position est dessiné par l'app

`myLocationEnabled` de MapLibre activerait son LocationComponent, qui passe par les Google
Play Services : exclu (§12.6). Deux cercles sur une source GeoJSON font le travail, alimentés
par le canal natif.

Il **suit** la position, ce qui amende le §11.1 — amendement reporté dans la spec. La version
ponctuelle, où le point ne bougeait qu'à l'appui sur un bouton, s'est révélée déroutante à
l'usage, et l'attente d'un fix rendait chaque envoi lent (5 à 10 s).

Ce que la bascule ne change pas, et qu'il faut préserver en touchant à ce code :

- le suivi ne tourne que pendant que la carte est visible, l'abonnement est coupé sur
  `AppLifecycleState` dès que l'app quitte le premier plan ;
- aucune permission d'arrière-plan n'est déclarée dans le manifeste ;
- aucune position n'est écrite sur le disque ni transmise, en dehors de l'appel RPC qui en
  déduit un palier à trois valeurs et la jette (§6.2, §11.1).

La cadence est de 5 s ou 10 m, ce qui suffit à suivre quelqu'un qui se déplace sans faire chauffer le GPS.

### Le fond de carte s'efface devant les dangers

`assets/map_style.json` est un style maison, pas un thème Protomaps repris tel quel. Les
points d'intérêt y sont **volontairement rares**. À Paris, afficher cafés et restaurants noie la
voirie et, surtout, les marqueurs de danger — qui sont l'objet de l'app. Ne restent que des
repères et ce qui sert à qui se déplace en ville : eau potable, toilettes, bancs, transports, espaces verts,
monuments.

Glyphes et sprite sont servis par l'instance (`./tiles/fetch-assets.sh` côté serveur). **Le
script lit les polices dans le style lui-même** : une police ajoutée au style et oubliée dans
le script renvoie des 404 sur les glyphes, et MapLibre cesse alors d'afficher *toutes* les
étiquettes, pas seulement celles de la police manquante. Le piège a coûté une itération.

**Une couche de tuile ne contient pas qu'un seul type de géométrie.** `water` mêle les plans
d'eau (Polygon), l'axe des cours d'eau (LineString) et des ancres de libellé (Point). Un calque
`fill` sans filtre remplit *tout* ce qu'il trouve : MapLibre referme la LineString sur elle-même
et la traite comme un polygone. L'axe du Canal Saint-Martin devenait ainsi un coin de 2,7 km²
étalé sur le 10e, d'autant plus large qu'on dézoomait — la simplification retire des sommets à
la ligne, et le faux polygone enfle. D'où le `["==", "$type", "Polygon"]` sur chaque `fill`,
vérifié par `test/map_style_test.dart`.

Le même test vérifie que chaque `source-layer` visé existe vraiment. Le calque `waterway`
pointait sur `physical_line`, absent du schéma Protomaps v4 : il ne dessinait rien depuis le
début, sans que rien ne le signale. Un style est une donnée — rien ne le compile, rien ne le
relit.

### La base locale ne contient rien qui concerne la personne

`drift` garde deux choses, et seulement deux : le **catalogue** des types, sans lequel l'app ne
s'ouvre même pas hors ligne, et un **cache de dangers** avec la liste des zones déjà chargées.

Une « zone » est un rectangle déjà demandé au serveur, avec sa date : chaque appel réussi à
`hazards_in_bbox` en enregistre un. Elles comptent autant que les dangers eux-mêmes, parce qu'un
cache qui répond « rien » est ambigu. Arriver hors réseau dans un quartier jamais consulté et y
voir une carte propre se lit « pas de nid-de-poule ici » — le pire mensonge possible pour ce
produit. D'où `HazardsView.isBlind`, et le bandeau qui le dit à l'écran.

**La file d'attente n'est pas en base.** Le §10 la prévoyait sur disque avec `workmanager` ; elle
vit en mémoire. Un geste fait sans réseau repart dès que le réseau revient, tant que l'app est en
vie ; si Android tue le processus avant, il est perdu. Périmètre assumé pour la bêta : le cas
nominal d'un trajet est l'app au premier plan. Le bénéfice n'est pas que la simplicité — c'est
que **rien de ce que le disque contient ne concerne la personne**, donc la question de savoir ce
que la position du déclarant ferait sur un disque ne se pose pas (§11.1).

Corollaire découvert en chemin : `android:allowBackup` vaut `true` par défaut. Android
téléversait vers Google Drive tout ce que l'app écrit — la base locale, et le stockage chiffré
qui porte l'identifiant de terminal. Désactivé sur les deux mécanismes, `allowBackup` et
`dataExtractionRules` pour le transfert d'appareil à appareil d'Android 12+.

**Ce qui distingue une panne d'un refus.** `HazardRepository._isOffline` tranche : une
`SocketException`, un délai dépassé, une `ClientException`. Un refus du serveur est une réponse —
il a un sens, un message, et rejouer le geste ne le changera pas ; il sort donc de la file.
Confondre les deux remplirait la file de gestes morts, ou jetterait des gestes valides.

**Un geste mis en file ne change rien à l'écran** tant que le serveur n'a pas tranché : deviner
sa décision serait mentir. Seul un signalement fait exception, affiché aussitôt en marqueur
provisoire — sinon le geste n'aurait aucune trace.

### Rien sur le disque ne dit où on est passé il y a plus d'une heure

Exigence du §11.7 : un téléphone volé, ouvert et fouillé de fond en comble, ne doit rien livrer
de plus d'une heure. Aucune position GPS n'est jamais écrite — mais **afficher une carte laisse
des traces d'un autre genre** : les tuiles du fond gardent leur z/x/y et leur heure d'accès, une
tuile de niveau 15 fait 1,2 km de côté, et le cache de MapLibre n'évince qu'à la taille, jamais
à l'âge. Mesuré sur le téléphone : 68 tuiles, aucune expirée supprimée, deux heures après.

`TraceSweeper` (Kotlin) efface les tuiles, les zones en cache et leurs dangers. Deux régimes :
**à l'âge, 45 minutes**, pendant qu'on regarde la carte, pour que la vue en cours survive ; et
**tout, 20 minutes après** le passage en arrière-plan, quand personne ne lit.

Le plafond annoncé se calcule : 45 (âge toléré) + 5 (intervalle des passages) + 20 (délai de
l'alarme) + 15 (fenêtre de report d'Android, 75 % du délai) = **85 minutes**. La fenêtre est
mesurée dans `dumpsys alarm` : `window=+33m44s` pour une alarme à 45 min, `+14m59s` après
passage à 20 min. C'est ce relevé qui a imposé de raccourcir le délai — le premier réglage
plafonnait en réalité au-delà de deux heures, pour une promesse d'une heure.

Deux choix qui ne sont pas évidents :

- **En Kotlin, pas en Dart.** Rien de Flutter ne tourne en arrière-plan. Regarder la carte puis
  empocher le téléphone laisserait tout intact jusqu'à la prochaine ouverture. Une alarme
  système, elle, réveille le processus même après qu'Android l'a tué — constaté : processus tué
  par `am kill`, alarme déclenchée, 19 lignes effacées, nouveau pid.
- **Du SQL direct, pas `clearAmbientCache()`.** La fonction du plugin efface tout ou rien : en
  pleine sortie, elle rendrait la carte blanche au moment où on roule dessus. La coupure à l'âge
  épargne la vue en cours, et les tuiles d'une zone téléchargée volontairement.

`PRAGMA secure_delete` avant chaque suppression, sans quoi les octets restent lisibles dans les
pages libérées du fichier et la purge n'est que cosmétique devant quelqu'un qui sait lire un
disque. Il se pose par `rawQuery` : ce PRAGMA rend une valeur, et `execSQL` refuse.

Hors de notre base, une trace qu'on n'écrit pas nous-mêmes : **l'instantané que prend Android
pour l'écran « applis récentes »** — une image de la carte centrée sur la personne, gardée sur
disque. Refusé par `setRecentsScreenshotEnabled(false)` à partir d'Android 13, sans bloquer les
captures d'écran volontaires. En dessous, seul `FLAG_SECURE` en viendrait à bout, au prix de les
bloquer aussi : non tranché, le parc de la bêta est en Android 13+.

Conséquence assumée sur le hors-ligne : **le cache sert la sortie en cours et l'a oubliée avant
qu'on rentre.** Rouvrir sans réseau une heure plus tard affiche « zone jamais chargée ». Une
zone téléchargée, elle, ne s'efface jamais toute seule — c'est le sens de la fonctionnalité, et
c'est la seule trace que la personne crée exprès, voit listée et supprime d'un geste.

### Les paramètres portent les droits, pas des réglages

Il n'y a aucune préférence à régler dans cette app. L'écran F8 existe pour autre chose : rendre
exerçables les droits du §11.4, et afficher les attributions que l'ODbL impose pour le fond de
carte OpenStreetMap — nulle part ailleurs il n'y avait de place pour elles.

Le texte de confidentialité existe en deux longueurs. `assets/privacy.md` est la version courte,
une page, celle que l'écran ouvre : la version longue faisait peur, et un texte qu'on ne lit pas
ne promet rien. `assets/privacy-full.md` est la version détaillée, copie de `../PRIVACY.md` que
`privacy_text_test.dart` compare octet à octet — Flutter ne sait pas embarquer un fichier hors du
paquet. Après une modification : `cp PRIVACY.md app/assets/privacy-full.md`. Le même test vérifie,
dans les deux textes, que les durées écrites sont celles que le code applique — si l'horizon
d'oubli change sans que la phrase suive, il tombe.

Le rendu passe par `markdown_view.dart`, une centaine de lignes plutôt qu'une dépendance :
`flutter_markdown` est abandonné depuis 2025, et le sous-ensemble utile tient en six règles. Les
tableaux deviennent des blocs empilés — trois colonnes ne se lisent pas sur un téléphone.

**« Exporter mes signalements » n'est pas construit**, et pas par oubli : l'app ne sait pas
lesquels sont les siens. `created_by` n'est pas exposé par l'API, et le lien est coupé au bout de
24 heures (§11.2). Le construire demanderait soit de tenir une liste locale de ses propres
signalements — un historique personnel permanent sur le disque, exactement ce que le §11.7 vient
d'effacer — soit un RPC qui ne pourrait jamais rendre plus que les dernières 24 heures. À
trancher avant de l'annoncer à des testeurs.

### Les mesures de la bêta sont des totaux, pas un journal

Le §4.6 pose six questions ; trois se mesurent dans l'app. `BetaMeasurements` tient **une ligne
par indicateur** — compte, total, minimum, maximum — et rien d'autre. Ni position, ni horodatage,
ni liste de ce qui a été signalé : un journal d'événements répondrait aux mêmes questions et
serait une trace de plus sur le disque, après une journée passée à en effacer (§11.7). Un test
vérifie que la table n'a bien que ces cinq colonnes.

**Deux chronomètres pour la question des quinze secondes.** La spec dit « entre l'ouverture de la
feuille et l'envoi » ; elle a été écrite avant que le parcours ne place le pin *avant* la feuille.
Mesurer depuis la feuille laisse dehors l'ajustement du pin, qui est la partie lente. Les deux
sont donc relevées, et c'est `signalement.geste` — de l'appui sur « Signaler » à la réponse du
serveur — qui répond à la question.

**Le refus de doublon ne laissait aucune trace.** « Le rayon anti-doublon de 15 m est-il le bon ? »
se lit dans deux chiffres : les doublons proposés par le serveur, et ceux que la personne refuse
— une détection à tort. Le second n'existait nulle part avant, ni en base ni dans l'app.

Le modèle de téléphone vient du canal natif, à la demande, et n'est jamais gardé : le §4.6 veut le
noter avec les mesures de la file, parce qu'un geste perdu peut l'être par la surcouche du
constructeur plutôt que par le code.

Rien ne part tout seul : il n'y a aucun appel réseau dans `beta_measurements.dart`, et le seul
chemin de sortie est le bouton « copier » de l'écran « Mes mesures ». Cet écran existe aussi pour
la transparence — une app qui chronomètre ce que fait la personne doit le lui montrer, sinon la
promesse « aucune télémétrie » est invérifiable.

### Le fond de carte s'embarque par zone

Le cache ambiant de MapLibre tient une quarantaine de tuiles : trois ou quatre écrans, dont un
trajet sort tout de suite. Le bouton « cartes hors-ligne » embarque la zone affichée jusqu'au
zoom 15. Paris intra-muros pèse 424 tuiles, une quarantaine de mégaoctets. Le §10 réservait cela
à la V2 ; un signalement posé sur un fond blanc n'étant pas ajustable à quelques mètres (§11.6),
c'est avancé en bêta — d'autant que le fond couvre désormais la France entière et que personne
ne téléchargera 9 Go sur son téléphone.

**MapLibre télécharge une région à partir d'une URL de style**, jamais d'un contenu : un JSON en
clair, un `file://` et un chemin nu sont tous refusés par « Unable to parse resourceUrl ».
L'instance sert donc le style elle-même, sur `/tiles/style.json`, avec l'adresse de base rendue
par un gabarit Caddy à partir de l'hôte demandé — la même copie répond au téléphone qui vient par
`127.0.0.1:8080` et au domaine public. La carte affichée, elle, garde son asset : le style n'est
pas négociable au runtime. Les deux viennent du même fichier, `tiles/fetch-assets.sh` produisant
la copie servie.

L'estimation annoncée compte un coût fixe de 5 Mo pour les polices : sur une zone de dix tuiles
elles pesaient plus que les tuiles, et annoncer 1 Mo puis en écrire 6 ferait douter du reste.

### La carte est rendue en `TextureView`, pas en Virtual Display

`MapLibreMap.useHybridComposition = true`, assigné dans `main()` avant `runApp`. Par défaut le
plugin embarque un `GLSurfaceView` par Virtual Display, dont la surface est perdue quand l'écran
s'éteint : au déverrouillage la carte reste figée sur sa dernière image, jusqu'à ce qu'un
aller-retour vers une autre app force la recréation de la vue. Les journaux le disent —
`Creating virtual display: flutter-vd#0`, puis `getUniqueId: Invalid operation on virtual
display`. Le `TextureView` coûte un peu plus cher à dessiner ; une carte figée après un
déverrouillage coûte davantage, puisqu'en déplacement l'écran s'éteint entre deux signalements.

### La permission se demande aux moments d'intention, jamais pendant un envoi

Une permission de localisation accordée **« Une seule fois »** est révoquée par Android dès que
l'app repasse en arrière-plan. `dumpsys package me.safe` le montre : `granted=false,
flags=[ ... ONE_TIME ... ]`. Le premier accès à la position après chaque réveil rouvre donc le
dialogue système — et s'il s'ouvre au milieu d'un envoi, le geste reste suspendu à une réponse
humaine. Dix secondes observées sur un Pixel 9, pour une spec qui en vise quinze pour le geste
entier (§4.6). Pire : rien à l'écran n'explique l'attente, puisque le dialogue est une autre
activité.

D'où `currentPosition(mayAsk: …)`, faux par défaut. La demande n'a lieu qu'après un geste
d'intention — ouvrir le mode placement, appuyer sur « recentrer » — où le dialogue arrive avec
son contexte sans rien suspendre. Un envoi ne demande jamais : il part sans position, pèse moins,
et le dit. Le recentrage **automatique** du lancement ne demande pas non plus : ce serait la
pop-up nue à l'ouverture que le §9 écarte, et en « une seule fois » elle reviendrait à chaque
lancement, devant une carte encore vide.

Il y avait un second piège, invisible : `onListen` du canal natif sortait en silence quand la
permission manquait — **sans erreur**, donc Flutter croyait suivre un flux vivant. Une fois la
permission rendue, rien ne réarmait `requestLocationUpdates` : l'indicateur restait figé et
chaque geste rouvrait une lecture ponctuelle, pour toute la session.
`onRequestPermissionsResult` réarme désormais le suivi.

L'usage « une seule fois » est courant, et il doit rester fluide : ouverture sans dialogue, une
seule demande au moment où l'on appuie sur « Signaler », puis un envoi immédiat et pesé à son
vrai poids.

Le message le dit d'ailleurs différemment selon la cause. Pas de signal, on n'y peut rien.
Permission révoquée, si : l'app conseille « pendant l'utilisation », sans quoi le problème se
reproduira à chaque réveil.

### Un geste n'attend pas un fix qui ne vient pas

`LocationService.gestureTimeout` vaut trois secondes, contre douze pour une lecture ordinaire.
Le suivi tourne pendant que la carte est visible : dehors, la position est toujours fraîche et
la lecture instantanée. Si le suivi n'a rien donné depuis une minute, c'est qu'il n'y a pas de
signal — porche, tunnel, intérieur — et douze secondes de plus ne le feront pas apparaître. Ça
ne faisait que retarder de 5 à 10 secondes un geste que la spec veut sous quinze (§4.6). Sans
position le geste part quand même : il pèse moins, et l'app le dit.

### Le pin se place en déplaçant la carte, ou se pose au doigt

La spec (§9) décrit une mini-carte avec un pin à faire glisser. L'app fait l'inverse : le pin
reste fixe au centre de l'écran et c'est la carte qui bouge dessous. Un tap sur une zone vide
ouvre aussi le mode placement directement à cet endroit, et un tap pendant le placement y
déplace le pin — un tap sur un marqueur ouvre son détail, le plugin ne déclenche pas les deux.
Même intention — c'est le geste manuel qui porte la précision, pas le capteur (§11.6) — mais
plus précis au pouce, et sans seconde instance de carte dans une feuille. Un zoom minimal est
imposé avant de pouvoir valider.

Un tap sur une **grappe** zoome jusqu'au niveau où elle se sépare, que la source calcule
(`getClusterExpansionZoom`). Une grappe agrège des dangers distincts : il n'y a rien de sensé à
ouvrir, mais ne rien faire donnait l'impression d'un geste raté.

## Ce que l'app ne fait pas

La position de l'utilisateur part dans l'appel RPC et n'en revient jamais : le serveur en
déduit un palier sur trois valeurs et la jette (§6.2, §11.1). Le GPS n'est lu qu'au moment
d'un geste explicite — aucune permission d'arrière-plan n'est déclarée, aucun trajet n'est
suivi. Il n'y a aucune analytics, aucune télémétrie, et aucune requête vers un domaine tiers :
fond de carte, glyphes et API viennent tous de l'instance de l'application.

## Reste à faire

Semaine 6 (§14) : file d'attente hors-ligne avec `drift` et `workmanager`, photos, écran de
paramètres, instrumentation **locale** des mesures du §4.6. Chaque écriture porte déjà un
`client_id` généré sur le terminal, pour que la file d'attente n'ait rien à rétro-adapter.

Un point à ne pas oublier dans cette instrumentation : **une détection anti-doublon ne laisse
aucune trace**. Le serveur refuse la création et renvoie `distance_m`, mais rien n'est écrit
nulle part. Or le §4.6 veut mesurer « les doublons créés malgré la détection, et les détections
à tort » pour trancher le rayon de 15 m. Il faut donc journaliser côté terminal, à chaque
`DuplicateFound` : la distance proposée, et ce que l'utilisateur en a fait — confirmer, ou
abandonner. Sans cela la question de la bêta restera sans réponse.

Semaine 7 : GlitchTip. Le build release signé et le dépôt F-Droid auto-hébergé sont faits,
voir [deploy/README.md](../deploy/README.md).

Points ouverts : l'`applicationId` (`mov.safecity`, tranché) ne se change plus après une première
publication — **c'est maintenant qu'il se tranche**, la publication est outillée. Il s'écrit
dans [`android/app.properties`](android/app.properties), seul endroit où il figure : Gradle
et les scripts de `deploy/` le lisent là. Le changer ne demande pas de déplacer un fichier
Kotlin, le `namespace` restant `me.safe`. Le géocodage
inverse (Photon) n'est pas déployé, donc `address` reste nul et l'écran de détail affiche la
coordonnée.
