/// Configuration de l'app. Tout est surchargeable au build : `--dart-define`.
///
/// Aucune de ces adresses ne doit pointer ailleurs que sur l'instance de l'application.
/// Le fond de carte et le géocodage sont auto-hébergés, et ce n'est pas qu'une
/// question de coût : un fond de carte tiers reçoit la zone consultée à chaque
/// déplacement de la carte (SPEC §7, §11.5).
class AppConfig {
  const AppConfig._();

  /// Version affichée dans « À propos ».
  ///
  /// Recopiée de `pubspec.yaml` plutôt que lue par `package_info_plus` : une
  /// dépendance de plus pour une chaîne de six caractères, dans un projet qui
  /// doit justifier chaque paquet devant F-Droid (§12.6). `config_test.dart`
  /// casse si les deux divergent.
  static const String version = '0.7.3';

  /// Le `versionCode` du même `pubspec.yaml`, après le `+`. Le seul nombre
  /// qu'Android compare pour décider qu'il y a une mise à jour, donc celui que
  /// l'app compare à ce que le serveur annonce (`UpdateChecker`). Recopié pour
  /// la même raison que `version`, et vérifié par le même test.
  static const int versionCode = 27;

  /// Par défaut, l'instance de développement, jointe par `adb reverse
  /// tcp:8080 tcp:8080`. Cela vaut pour l'émulateur comme pour un téléphone
  /// branché en USB, et le point d'entrée en clair de Caddy peut rester publié
  /// sur `127.0.0.1` seulement : rien n'apparaît sur le Wi-Fi.
  ///
  /// **`127.0.0.1` et non `localhost`.** Le nom résout vers `::1` *et*
  /// `127.0.0.1` ; sans réseau, la tentative IPv6 traîne avant de basculer sur
  /// IPv4. Mesuré sur un Pixel 9 en mode avion : 8 123 ms pour échouer sur
  /// `localhost`, 121 ms sur `127.0.0.1`, pour la même erreur « connexion
  /// refusée ». C'est ce qui faisait attendre dix secondes devant un écran
  /// blanc au lancement, puis dix de plus avant que les dangers du cache
  /// n'apparaissent.
  ///
  /// Surchargeable par `--dart-define`, mais **seulement en build AOT**
  /// (`--release`, `--profile`) : en debug, ces constantes sont résolues au
  /// lancement par `flutter run`, et l'app ouverte depuis l'écran d'accueil
  /// retombe sur ces valeurs. D'où un défaut qui marche tel quel.
  static const String apiBaseUrl = String.fromEnvironment(
    'APP_API',
    defaultValue: 'http://127.0.0.1:8080/rest/v1',
  );

  static const String tilesBaseUrl = String.fromEnvironment(
    'APP_TILES',
    defaultValue: 'http://127.0.0.1:8080/tiles',
  );

  /// Ce que le serveur annonce comme dernière version publiée : un fichier
  /// écrit par `deploy/vps-publish.sh` à côté de la page de téléchargement, lu
  /// au lancement et à chaque retour au premier plan (`UpdateChecker`). Même
  /// domaine que le reste.
  static const String updateUrl = String.fromEnvironment(
    'APP_UPDATES',
    defaultValue: 'http://127.0.0.1:8080/fdroid/latest.json',
  );

  /// Centre par défaut : Paris (§9). La carte s'y ouvre avant d'avoir la position.
  static const double parisLat = 48.8566;
  static const double parisLng = 2.3522;
  static const double defaultZoom = 13;

  /// Zoom minimal imposé avant de pouvoir valider un signalement, pour que le
  /// geste d'ajustement du pin ait un sens (§11.6).
  static const double minZoomToReport = 17;

  /// Le zoom auquel on se rapproche pour poser un pin : au-dessus du minimum,
  /// assez près pour distinguer la chaussée du trottoir, assez loin pour voir
  /// encore la rue. C'est aussi ce que fait le bouton « Zoomer » de la barre de
  /// placement quand on est trop loin.
  static const double placementZoom = 18;

  /// Au-delà, on ne recharge pas : la bbox demandée deviendrait absurde.
  static const double minZoomToLoadHazards = 11;
}
