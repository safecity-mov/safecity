/// Tous les libellés visibles de l'application, rassemblés en un seul endroit.
///
/// Ils vivaient jusqu'ici dans le corps des widgets, répartis sur une douzaine
/// de fichiers. Trois raisons de les sortir :
///
/// - **relire ce que l'app raconte** d'un seul coup d'œil, plutôt qu'en ouvrant
///   douze écrans — les formulations se contredisaient d'un écran à l'autre ;
/// - **corriger un texte** sans traverser du code de mise en page ;
/// - **préparer leur édition depuis la console** (§4.3) : tant qu'une chaîne
///   est en dur dans un widget, rien ne peut la remplacer à l'exécution.
///
/// Trois règles tiennent ce fichier :
///
/// 1. une constante par texte fixe, une **fonction** par phrase à trous — les
///    variables restent ainsi visibles dans la signature, et un remplacement
///    qui en perdrait une ne compilerait pas ;
/// 2. identifiants en anglais, textes en français, comme partout ailleurs ;
/// 3. **aucune mise en forme ici** : pas de widget, pas de style, pas de
///    condition d'affichage. Ce fichier ne dit que ce qui est écrit.
library;

/// Le nom de l'application, tel qu'il s'écrit partout dans l'app.
///
/// Le même mot figure une seconde fois, hors de Dart, dans
/// `android/app/src/main/AndroidManifest.xml` (`android:label`) : c'est celui
/// qu'Android affiche sous l'icône, et le code Dart ne peut pas le lire à la
/// compilation. `deploy/release-app.sh` vérifie que l'APK construit porte bien
/// cette chaîne-ci, pour qu'un renommage à moitié fait ne soit pas publié.
abstract final class AppLabels {
  static const appName = 'Safe city';
}

/// Écran d'accueil (§9, écran 4).
abstract final class OnboardingLabels {
  static const pitch = 'Signalez les nids-de-poule. Voyez ceux des autres. '
      'Faites-les disparaître de la carte quand ils sont réparés.';

  static const noAccountTitle = 'Pas de compte';
  static const noAccountBody = 'Aucune inscription, aucun e-mail. Un identifiant aléatoire '
      'reste sur votre téléphone.';

  /// Ce que l'app fait vraiment (voir `LocationService`) : la position est
  /// suivie pendant que la carte est à l'écran, pour le point bleu. Dire
  /// « lue seulement quand vous signalez » était une promesse fausse.
  static const locationTitle = 'La position reste sur votre téléphone';
  static const locationBody = 'Suivie pendant que la carte est affichée, jamais en '
      'arrière-plan, jamais enregistrée. Elle ne part pas avec vos signalements : '
      'seul un palier de distance — sur place, ou ailleurs — est envoyé.';

  static const openDataTitle = 'Données ouvertes';
  static const openDataBody = 'Les dangers signalés sont publics, sous licence ODbL. '
      'Fond de carte OpenStreetMap.';

  static const start = 'Voir la carte';

  static const permissionNotice =
      'L\'app demandera l\'accès à votre position. Vous pouvez refuser : '
      'vos signalements compteront simplement un peu moins.';
}

/// Écran de démarrage, quand le catalogue ne peut pas être chargé (§3).
abstract final class StartupLabels {
  /// Réservé aux pannes réseau : un autre échec dit ce qu'il est.
  static const unreachable =
      'Impossible de joindre ${AppLabels.appName}. Vérifiez votre connexion.';
  static String failed(String detail) =>
      '${AppLabels.appName} n\'a pas pu démarrer : $detail';
  static const retry = 'Réessayer';
}

/// Feuille de signalement (§4.1 F3).
abstract final class ReportLabels {
  static const title = 'Signaler un danger';
  static const typeSection = 'Type';
  static const severitySection = 'Gravité';
  static const descriptionLabel = 'Précision (facultatif)';

  /// Prévient que le champ est public (§11.2).
  static const descriptionHelper = 'Public. Ne décrivez pas de personnes.';

  static const send = 'Envoyer';

  /// Lu par les lecteurs d'écran sur chaque case de gravité.
  static String severityOption(String severity) => 'Gravité : $severity';
}

/// Feuille de détail d'un danger (§4.1 F5).
abstract final class DetailLabels {
  /// Un danger contesté reste visible : c'est le point du §6.1.
  static const disputed = 'Quelqu\'un l\'a signalé résolu. '
      'Si le danger est toujours là, confirmez-le.';

  static String resolved(String verb) =>
      'Signalé $verb. S\'il est encore là, confirmez-le pour le remettre sur la carte.';

  static const reportedRemotely = 'Signalé à distance : l\'auteur n\'était pas sur place.';

  /// Un signalement encore en file : pas de geste possible dessus (§10).
  static const pending = 'En attente d\'envoi : ce signalement partira au retour du réseau. '
      'On pourra agir dessus ensuite.';

  static String reportedOn(String when) => 'Signalé $when';
  static String lastSeen(String when) => 'Vu $when';

  static const confirm = 'Toujours là';

  /// Le pendant exact de « Toujours là ». Le verbe du catalogue — « Réparé »,
  /// « Nettoyé » — reste sur le bandeau d'un danger déjà signalé résolu et dans
  /// l'historique : c'est là qu'il raconte quelque chose. Sur le bouton, il
  /// rompait la symétrie des deux gestes, qui répondent à la même question.
  static const gone = 'Plus là';

  // --- La balance (§6.1) ---
  /// Les deux côtés se nomment comme les deux boutons : ce qui est écrit sous
  /// la barre est ce sur quoi on appuie.
  static String balancePresent(String weight) => '$confirm $weight';
  static String balanceGone(String weight, int threshold) =>
      '$gone $weight sur $threshold';

  /// Ce que la barre dit, pour qui ne la voit pas.
  static String balanceSemantics(String presentWeight, String goneWeight, int threshold) =>
      'Balance du danger : $presentWeight pour « $confirm », $goneWeight pour « $gone ». '
      'Il en faut $threshold pour qu\'il quitte la carte.';

  /// Le serveur vérifie les deux conditions et refuse avec un message clair si
  /// elles ne sont pas réunies (§6.1).
  static const removeOwn = 'Retirer mon signalement (auteur, sous 24 h)';

  static String timeline(int count) => 'Historique ($count)';

  /// Une ligne d'historique, par type d'événement du journal (§5). Un type
  /// inconnu s'affiche tel quel plutôt que de faire disparaître la ligne.
  static String event(String type) => switch (type) {
        'create' => 'Signalé',
        'confirm' => 'Confirmé « toujours là »',
        'mark_resolved' => 'Signalé résolu',
        'remove' => 'Retiré par son auteur',
        'restore' => 'Rétabli',
        'photo_add' => 'Photo ajoutée',
        _ => type,
      };

  static const close = 'Fermer';
}

/// Les trois niveaux de gravité (§4.1). Portés par l'énumération `Severity`,
/// qui les lit ici : la couleur et l'icône sont à elle, le mot est à ce fichier.
abstract final class SeverityLabels {
  static const annoying = 'Gênant';
  static const dangerous = 'Dangereux';
  static const veryDangerous = 'Très dangereux';
}

/// Filtres de la carte (§4.1 F2).
abstract final class FiltersLabels {
  static const title = 'Filtres';
  static const typesSection = 'Types de danger';
  static const severitySection = 'Gravité minimale';
  static const apply = 'Appliquer';

  /// Le cran « aucune gravité minimale ».
  static const allSeverities = 'Toutes';
}

/// Cartes hors-ligne (§10).
abstract final class OfflineLabels {
  static const title = 'Cartes hors-ligne';

  static const intro = 'Le fond de carte ne se garde pas tout seul : ${AppLabels.appName} oublie au '
      'plus tard au bout d\'une heure et demie les endroits que vous avez regardés. Une zone '
      'embarquée, elle, reste sur cet appareil jusqu\'à ce que vous la supprimiez.';

  /// Ce qu'une zone embarquée ne contient pas, dit avant le téléchargement.
  ///
  /// Les dangers suivent l'horizon d'oubli comme le reste du cache : la liste
  /// des endroits chargés dit où l'on est passé, même si chaque danger pris à
  /// part est public (§11.7). Une zone embarquée montre donc les rues, et
  /// avoue ne rien savoir des dangers après une heure sans réseau. Mieux vaut
  /// le lire ici qu'en rouler la surprise.
  static const noHazards = 'Ce sont les rues qui sont embarquées, pas les dangers : '
      'ceux-ci s\'effacent au plus tard au bout d\'une heure et demie, comme partout ailleurs. Sans réseau, '
      'la carte vous dira franchement qu\'elle ne sait pas.';

  static const visibleArea = 'Zone affichée';

  static String tooLarge(int tiles) =>
      'Trop large : $tiles tuiles. Rapprochez-vous avant de télécharger.';
  static String areaSize(int tiles, String size) => '$tiles tuiles, environ $size';

  static String progress(int percent, String size) => '$percent %, $size téléchargés';

  static const download = 'Télécharger cette zone';
  static const alreadyDownloaded = 'Zone déjà embarquée';

  static const downloadedSection = 'Déjà embarquées';
  static const none = 'Aucune.';
  static const unnamed = 'Zone';
  static const remove = 'Supprimer';

  /// Nom par défaut quand la carte ne connaît pas la voie au centre de la zone.
  static String defaultAreaName(String date) => 'Zone du $date';
}

/// Écran « Mes mesures » (§4.6, instrumentation locale).
abstract final class MeasurementsLabels {
  static const title = 'Mes mesures';

  static const intro = 'La bêta doit répondre à quelques questions : un signalement '
      'tient-il sous quinze secondes, le rayon anti-doublon est-il le '
      'bon, la file hors-ligne tient-elle un vrai trajet. Voici ce que '
      'ce téléphone en sait.';

  static const copy = 'Copier';
  static const copied = 'Copié. À nous envoyer comme vous voulez.';

  /// Dit explicitement ce que le rapport ne contient pas (§11.1).
  static const notALog = 'Des totaux, pas un journal : ni position, ni heure, ni la liste '
      'de ce que vous avez signalé. Ces chiffres ne partent que si vous '
      'les copiez et nous les envoyez.';

  static const reset = 'Remettre les compteurs à zéro';

  static String tracked(int count) => 'Indicateurs suivis : $count.';
}

/// Écran Paramètres (§4.1 F8) et ses dialogues.
abstract final class SettingsLabels {
  static const title = 'Paramètres';

  // --- Mes données (§11.4) ---
  static const dataSection = 'Mes données';

  /// Retirer d'un coup ce qu'on a signalé récemment (§11.4 amendé). Passe
  /// avant « Effacer mes données » : une fois le lien coupé, il n'y a plus
  /// rien à retirer.
  static const removeRecent = 'Retirer mes signalements récents';
  static const removeRecentHint = 'Ceux des dernières 24 heures, d\'un coup. Au-delà, plus rien '
      'ne dit qu\'ils sont les vôtres.';

  /// Un seul geste pour couper le lien : le serveur oublie, et le téléphone
  /// repart d'un numéro neuf. Les deux ensemble, sinon l'un des deux garde la
  /// mémoire de l'autre.
  static const forget = 'Effacer mes données';
  static const forgetHint = 'Le serveur oublie que vos signalements viennent de vous, et ce '
      'téléphone repart d\'un numéro neuf. Les signalements restent sur la carte.';

  static const dataNotice = 'Le lien entre ce téléphone et vos signalements disparaît de toute '
      'façon tout seul au bout de 24 heures. Ces boutons servent à ne pas attendre.';

  // --- Confidentialité ---
  static const privacySection = 'Confidentialité';
  static const privacy = 'Ce que ${AppLabels.appName} sait de vous';
  static String privacyHint(int minutes) => 'L\'essentiel en une page. '
      'Les traces de carte sont effacées au bout de $minutes minutes.';
  static const privacyTitle = 'Confidentialité';

  /// En bas de la version courte : la longue, avec où vérifier chaque
  /// phrase dans le code.
  static const privacyDetailed = 'Lire la version détaillée';
  static const privacyDetailedTitle = 'Confidentialité, en détail';

  // --- À propos ---
  static const aboutSection = 'À propos';
  static String version(String version) => 'Version $version — bêta fermée';

  /// Sous le numéro de version : le serveur est interrogé à l'ouverture de
  /// l'écran, et la ligne dit ce qu'il a répondu (§12.6).
  static const checkingUpdates = 'Recherche de mise à jour…';
  static const upToDate = 'Vous avez la dernière version.';
  static String updateFound(String version) =>
      'Version $version disponible. Toucher pour la télécharger.';
  static const updateCheckFailed = 'Mise à jour : impossible de vérifier. Toucher pour réessayer.';

  static const licences = 'Licences';
  static const licencesBody = 'Application : Apache-2.0\n'
      'Serveur : AGPL-3.0\n'
      'Signalements : ODbL 1.0';

  static const basemap = 'Fond de carte';
  static const basemapBody = '© les contributeurs OpenStreetMap, sous ODbL.\n'
      'Tuiles Protomaps, rendues par MapLibre.';

  // --- Dialogues : ils disent ce qu'on perd, pas seulement ce qu'on fait ---
  static const removeRecentConfirmTitle = 'Retirer mes signalements récents ?';
  static const removeRecentConfirmBody =
      'Tous les dangers que vous avez signalés depuis 24 heures quitteront la '
      'carte. Les confirmations que vous avez données sur les signalements des '
      'autres restent.\n\n'
      'Au-delà de 24 heures, le serveur ne sait plus lesquels sont les vôtres : '
      'ceux-là ne peuvent plus être retirés, par personne.';
  static const removeRecentConfirmAction = 'Retirer';

  static const nothingToRemove = 'Aucun signalement de moins de 24 heures à retirer.';
  static String removedRecent(int count) => count > 1
      ? '$count signalements retirés de la carte.'
      : '$count signalement retiré de la carte.';

  /// Rien n'a bougé : le geste peut être refait en entier.
  static const removeRecentUnreachable = 'Serveur injoignable. Rien n\'a été retiré, '
      'réessayez plus tard.';

  static const forgetConfirmTitle = 'Effacer mes données ?';
  static const forgetConfirmBody =
      'Le serveur cessera de savoir que vos signalements viennent de ce '
      'téléphone, vos votes cesseront de compter, et ce téléphone repartira '
      'd\'un numéro tiré au hasard, sans '
      'lien avec ce que vous avez fait jusqu\'ici.\n\n'
      'Vos signalements resteront sur la carte : ce sont des faits sur la '
      'voirie, et d\'autres usagers s\'appuient dessus. Vous perdrez la '
      'possibilité de retirer ceux des dernières 24 heures, puisque plus rien '
      'ne dira qu\'ils sont les vôtres.';
  static const forgetConfirmAction = 'Effacer';

  static const nothingAttached = 'Nouvel identifiant. Rien n\'était rattaché à l\'ancien.';
  static String detached(int count) => count > 1
      ? 'Nouvel identifiant. $count gestes ne vous sont plus rattachés.'
      : 'Nouvel identifiant. $count geste ne vous est plus rattaché.';

  /// Le téléphone a bien changé de numéro, mais le serveur n'a pas été
  /// prévenu : le lien avec l'ancien tiendra jusqu'à la coupure automatique.
  static const forgottenLocallyOnly = 'Nouvel identifiant. Le serveur est injoignable : le lien '
      'avec l\'ancien s\'effacera tout seul sous 24 heures.';

  /// Le cache local n'a pas été touché : le geste peut être refait en entier.
  static const serverUnreachable = 'Serveur injoignable. Rien n\'a été effacé, '
      'réessayez plus tard.';

  static const cancel = 'Annuler';
}

/// Écran carte (§4.1 F1, F2, F4) : bandeaux, retours, dialogues.
abstract final class MapLabels {
  // --- Boutons et outils ---
  static const report = 'Signaler';
  static const filters = 'Filtres';
  static const recenter = 'Recentrer sur ma position';
  static const resetNorth = 'Remettre le nord en haut';
  static const offlineMaps = 'Cartes hors-ligne';
  static const settings = 'Paramètres';
  static const cancel = 'Annuler';

  // --- Placement du pin ---
  static const placeReady = 'Déplacez la carte, ou touchez le danger directement.';
  static const placeZoomIn = 'Encore trop loin pour placer le pin précisément.';
  static const placeZoom = 'Zoomer';
  static const placeContinue = 'Continuer';

  // --- Bandeaux ---
  static const blind = 'Hors ligne, zone jamais chargée : '
      'l\'absence de marqueur ne veut rien dire ici.';
  static String pending(int count) =>
      count > 1 ? '$count gestes en attente d\'envoi' : '$count geste en attente d\'envoi';

  // --- Mise à jour (§12.6) ---
  /// Le serveur annonce une version plus récente que celle installée. Toucher
  /// le bandeau télécharge l'APK ; Android fait le reste.
  static String updateAvailable(String version) =>
      'Version $version disponible. Touchez pour la télécharger.';

  /// Sous la version minimale exigée : l'app installée envoie quelque chose de
  /// faux, ou le serveur ne l'accepte plus.
  static String updateRequired(String version) =>
      'Mise à jour nécessaire : version $version. Touchez pour la télécharger.';

  /// La ligne libre écrite au moment de publier, quand il y en a une.
  static String updateWithNote(String base, String note) => '$base $note';

  /// Le navigateur n'a pas pris l'adresse : on donne la page à taper.
  static String updateOpenFailed(String pageUrl) =>
      'Impossible d\'ouvrir le navigateur. Rendez-vous sur $pageUrl';

  // --- Position ---
  /// Dit l'attente plutôt que de laisser un bouton muet dix secondes (§4.6).
  static const searchingPosition = 'Recherche de votre position…';
  static const positionUnavailable = 'Position indisponible. La carte reste sur Paris.';

  /// Deux causes, deux conseils. Pas de signal, on n'y peut rien. Permission
  /// révoquée, si : Android retire l'autorisation « une seule fois » à chaque
  /// passage en arrière-plan.
  static String weakerWithoutPermission(String base) =>
      '$base Autorisez la position pour qu\'il compte davantage.';
  static String weakerWithoutPosition(String base) => '$base Sans votre position, il compte moins.';

  // --- Retours après un geste ---
  static const reportSent = 'Signalement envoyé.';
  static const reportSentThanks = 'Signalement envoyé. Merci.';
  static const confirmed = 'Merci, le danger est confirmé.';
  static const removed = 'Signalement retiré.';
  static String markedResolved(String verb) => 'Marqué $verb. Il disparaît de la carte.';

  /// Le vote est pris mais le quorum n'est pas atteint : le dire, plutôt que de
  /// laisser croire à un échec (§6.1).
  static const voteRecorded = 'Vote enregistré. Il en faut d\'autres pour le retirer de la carte.';

  /// Le même message pour tous les gestes mis en file : ce qui compte est que le
  /// geste ne soit pas perdu, et qu'il ne soit pas parti.
  static const queued = 'Hors ligne. Le geste partira dès le retour du réseau.';

  static const networkError = 'Pas de réseau, ou le serveur ne répond pas.';

  // --- File d'attente vidée ---
  static String flushSent(int count) => count > 1 ? '$count gestes envoyés' : '$count geste envoyé';
  static String flushRefused(int count) =>
      count > 1 ? '$count refusés par le serveur' : '$count refusé par le serveur';

  // --- Anti-doublon (§6.3) ---
  static const duplicateTitle = 'Est-ce celui-ci ?';
  static String duplicateBody(String type, String distance, String when) =>
      'Un $type est déjà signalé $distance, $when.\n\n'
      'Confirmez-le plutôt que d\'en créer un second.';
  static const duplicateConfirm = 'Oui, confirmer';

  /// « au même endroit » plutôt que « à 0 m » : le pin est posé à la main,
  /// tomber à moins d'un mètre du danger existant est le cas courant.
  static const sameSpot = 'au même endroit';
  static String atDistance(int metres) => 'à $metres m';

  static const today = 'aujourd\'hui';
  static const yesterday = 'hier';
  static String daysAgo(int days) => 'il y a $days jours';
}
