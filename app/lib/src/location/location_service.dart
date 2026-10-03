import 'package:flutter/services.dart';

/// Une position ponctuelle, telle que le capteur la donne.
///
/// Elle ne quitte jamais le terminal : l'app en déduit elle-même un palier de
/// proximité sur deux valeurs (`ProximityRules`), et seul ce palier part dans
/// l'appel RPC. Ni la coordonnée ni la distance exacte ne touchent le disque ni
/// le réseau (§6.2, §11.1).
class DevicePosition {
  const DevicePosition({required this.lat, required this.lng, required this.accuracy});

  final double lat;
  final double lng;
  final double accuracy;
}

/// Localisation, par le `LocationManager` d'Android et rien d'autre.
///
/// **Contrainte F-Droid, non négociable (§12.6).** Le paquet `geolocator` lie
/// `play-services-location` dans l'APK même configuré avec
/// `forceLocationManager: true` : cette option ne change que le chemin
/// d'exécution, pas le contenu du binaire. L'APK construit avec lui embarquait
/// 17 classes `com.google.android.gms`. D'où ce canal natif, qui n'a besoin que
/// d'une méthode : une position, à la demande, et d'un flux tant que la carte
/// est affichée.
///
/// La position est suivie pendant que la carte est à l'écran (voir [positions]),
/// jamais en arrière-plan, jamais écrite, jamais transmise : il n'y a aucune
/// collecte de trajet (§11.1).
class LocationService {
  static const _channel = MethodChannel('me.safe/location');
  static const _stream = EventChannel('me.safe/location/stream');

  /// Durée pendant laquelle une position déjà lue est réutilisée.
  ///
  /// Elle ne sert qu'à choisir un palier parmi deux — sur place à moins de
  /// 100 m, ou ailleurs (§6.2) — donc une position d'une minute donne le même
  /// résultat, sauf à rouler vite. Sans ce cache, chaque envoi rouvrait une attente de fix : le
  /// signalement prenait 5 à 10 secondes là où la spec en vise moins de 15 pour
  /// l'ensemble du geste (§4.6). Rien n'est écrit sur le disque (§11.1).
  static const _freshness = Duration(seconds: 60);

  DevicePosition? _last;
  DateTime? _lastAt;

  /// Suivi de la position pendant que la carte est à l'écran.
  ///
  /// **Écart assumé avec le §11.1**, qui décrit une lecture au seul moment d'un
  /// geste explicite. Un indicateur qui ne bouge qu'à l'appui sur un bouton s'est
  /// révélé déroutant à l'usage, et l'attente d'un fix rendait chaque envoi lent.
  ///
  /// Ce que la bascule ne change pas : le suivi ne tourne **que** pendant que la
  /// carte est visible — l'abonnement est coupé dès que l'app quitte le premier
  /// plan — aucune permission d'arrière-plan n'est déclarée, et **aucune position
  /// n'est écrite ni transmise**. Elles servent à dessiner l'indicateur et à peser
  /// les gestes (§6.2). Le trajet n'est donc toujours pas collecté (§11.1).
  Stream<DevicePosition> get positions => _stream.receiveBroadcastStream().map((event) {
        final map = (event as Map).cast<String, dynamic>();
        final position = DevicePosition(
          lat: (map['lat'] as num).toDouble(),
          lng: (map['lng'] as num).toDouble(),
          accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
        );
        _last = position;
        _lastAt = DateTime.now();
        return position;
      });

  /// Dernière position connue, si elle est encore utilisable. Sert à afficher
  /// l'indicateur de position sans relancer le capteur.
  DevicePosition? get cachedPosition {
    final at = _lastAt;
    if (at == null || DateTime.now().difference(at) > _freshness) return null;
    return _last;
  }

  /// Attente maximale quand un geste attend la position pour partir.
  ///
  /// Le suivi tourne pendant que la carte est visible : dehors, `cachedPosition`
  /// est toujours frais et la lecture est instantanée. Si le suivi n'a rien
  /// donné depuis une minute, c'est qu'il n'y a pas de signal — sous un porche,
  /// dans un tunnel, en intérieur — et attendre douze secondes de plus ne le
  /// fera pas apparaître. Cela ne faisait que retarder de 5 à 10 secondes un
  /// geste que la spec veut sous quinze (§4.6).
  static const gestureTimeout = Duration(seconds: 3);

  /// Renvoie la position, ou `null` si elle est refusée ou indisponible.
  ///
  /// Un `null` n'est pas une erreur : le serveur accepte une action sans
  /// position, elle pèse simplement moins (palier 3, poids 0,25 — §6.2). Refuser
  /// la localisation doit rester un usage possible de l'app, pas un mur.
  /// [mayAsk] autorise la lecture à ouvrir le dialogue système de permission.
  ///
  /// **À réserver aux moments d'intention.** Une permission accordée « une seule
  /// fois » est révoquée par Android dès que l'app repasse en arrière-plan :
  /// après chaque mise en veille, le premier accès à la position rouvre le
  /// dialogue. S'il s'ouvre au milieu d'un envoi, le geste reste suspendu à une
  /// réponse humaine — dix secondes observées sur un Pixel 9, là où la spec en
  /// vise quinze pour le geste entier (§4.6).
  ///
  /// La demande a donc lieu quand l'utilisateur vient d'exprimer une intention —
  /// il ouvre le mode placement, il appuie sur « recentrer » — et jamais pendant
  /// un envoi, qui part sans position plutôt que d'attendre (§11.1).
  Future<DevicePosition?> currentPosition({
    Duration timeout = const Duration(seconds: 12),
    bool allowCached = true,
    bool mayAsk = false,
  }) async {
    if (allowCached) {
      final cached = cachedPosition;
      if (cached != null) return cached;
    }

    try {
      if (!await hasPermission()) {
        if (!mayAsk) return null;
        if (!await requestPermission()) return null;
      }

      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getCurrentPosition',
        {'timeoutMs': timeout.inMilliseconds},
      );
      if (result == null) return null;

      final position = DevicePosition(
        lat: (result['lat'] as num).toDouble(),
        lng: (result['lng'] as num).toDouble(),
        accuracy: (result['accuracy'] as num?)?.toDouble() ?? 0,
      );
      _last = position;
      _lastAt = DateTime.now();
      return position;
    } on PlatformException {
      // Capteur muet, service coupé en cours de route : on continue sans
      // position plutôt que d'interrompre le signalement.
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<bool> isLocationEnabled() async =>
      await _channel.invokeMethod<bool>('isLocationEnabled') ?? false;

  /// Oublie la dernière position connue.
  ///
  /// Appelée quand l'app passe en arrière-plan, et par « Régénérer mon
  /// identifiant » et « Effacer mes données » (§11.4) : ni l'un ni l'autre ne
  /// doit laisser quoi que ce soit derrière lui, pas même en mémoire.
  void forget() {
    _last = null;
    _lastAt = null;
  }
}
