import 'dart:async';

import 'package:flutter/services.dart';

/// Oubli des traces de localisation laissées sur l'appareil (§11.1).
///
/// Exigence : quelqu'un qui volerait le téléphone et obtiendrait un accès
/// complet à son contenu ne doit y trouver aucune trace de plus d'une heure de
/// l'endroit où l'appareil est passé. Les positions GPS, elles, ne touchent
/// jamais le disque — c'est la carte qui laisse des traces, pas le capteur.
///
/// Le travail lui-même est en Kotlin (`TraceSweeper`), pour deux raisons :
/// rien de Flutter ne tourne quand l'app est en arrière-plan, et la purge doit
/// se faire à l'âge plutôt qu'en bloc, faute de quoi la carte deviendrait
/// blanche en pleine sortie. Cette classe ne couvre que le cas restant : une
/// session qui reste au premier plan plus longtemps que l'horizon.
class TraceHorizon {
  TraceHorizon({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'me.safe/traces';

  /// Doit rester égal à `TraceSweeper.MAX_TRACE_AGE_MS`.
  static const maxAge = Duration(minutes: 45);

  /// Assez fin pour que rien n'atteigne l'horizon entre deux passages, assez
  /// large pour ne pas réveiller SQLite sans raison pendant un trajet.
  static const interval = Duration(minutes: 5);

  /// Le plafond annoncé, celui qui compte pour la personne.
  ///
  /// `maxAge` n'est que l'âge toléré pendant qu'on regarde la carte. Le pire
  /// cas ajoute l'intervalle entre deux passages, le délai de l'alarme (20 min,
  /// `TraceSweeper.ALARM_DELAY_MS`) et la fenêtre de report qu'Android
  /// s'accorde, mesurée à 75 % du délai : 45 + 5 + 20 + 15 = 85 minutes.
  static const guarantee = Duration(minutes: 90);

  final MethodChannel _channel;
  Timer? _timer;

  /// Rend le nombre de lignes effacées, ou `null` si la plateforme n'a pas
  /// répondu — sur un appareil non Android, ou dans un test de widget.
  Future<int?> sweep() async {
    try {
      return await _channel.invokeMethod<int>('sweep');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(sweep()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Marque et modèle du téléphone, pour le rapport de mesures (§4.6).
  ///
  /// Lu à la demande et jamais gardé : il n'apparaît que dans le texte que le
  /// testeur copie lui-même. `null` hors Android.
  Future<String?> deviceModel() async {
    try {
      return await _channel.invokeMethod<String>('deviceModel');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
