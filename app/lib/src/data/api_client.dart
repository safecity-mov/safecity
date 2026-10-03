import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'announcements.dart';
import 'models/hazard.dart';
import 'models/hazard_type.dart';
import 'moderation.dart';
import 'proximity.dart';

/// Erreur renvoyée par le serveur, déjà traduite pour l'écran.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Accès à l'API de l'application (§8).
///
/// Le client déclare, le serveur décide : aucune règle de modération n'est
/// évaluée ici. L'app envoie un geste et affiche l'état que le serveur renvoie.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _http;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 15);

  Future<dynamic> _rpc(String function, Map<String, dynamic> body) async {
    final response = await _http
        .post(
          Uri.parse('$_baseUrl/rpc/$function'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFor(response), statusCode: response.statusCode);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// PostgREST renvoie le message de l'exception SQL : celles des RPC sont déjà
  /// écrites en français et lisibles (§8). Les réécrire ici ferait diverger deux
  /// formulations de la même règle.
  ///
  /// `allowMalformed` plutôt qu'un décodage strict : un octet inattendu ne doit
  /// pas coûter le message entier, qui est la seule explication que l'utilisateur
  /// verra. Au pire il y perd un accent.
  String _messageFor(http.Response response) {
    try {
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final message = decoded['message'] as String?;
      if (message != null && message.isNotEmpty) return message;
    } on FormatException {
      // Corps non-JSON : on retombe sur le message générique.
    } on TypeError {
      // JSON valide, mais pas un objet : idem.
    }
    return 'Le serveur a refusé la demande (${response.statusCode}).';
  }

  /// Catalogue des types (§3). Lu au démarrage, il pilote l'UI.
  Future<List<HazardType>> fetchTypes() async {
    final response =
        await _http.get(Uri.parse('$_baseUrl/hazard_types?order=sort_order')).timeout(_timeout);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFor(response), statusCode: response.statusCode);
    }
    final rows = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return rows.map((r) => HazardType.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Les silhouettes de marqueur, par code de type (§4.3).
  ///
  /// En base64 et non en binaire : PostgREST rendrait un `bytea` en hexadécimal,
  /// soit deux fois le poids. Quelques centaines d'octets par type, une fois par
  /// lancement.
  Future<Map<String, Uint8List>> fetchTypeIcons() async {
    final response = await _http
        .get(Uri.parse('$_baseUrl/hazard_type_icons_public?select=type_code,png_b64'))
        .timeout(_timeout);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFor(response), statusCode: response.statusCode);
    }
    final rows = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        row['type_code'] as String: base64Decode(row['png_b64'] as String),
    };
  }

  /// La règle de proximité du §6.2, publiée par le serveur.
  ///
  /// L'app calcule le palier elle-même, mais ne décide pas de la règle : sinon deux versions
  /// installées en même temps pondéreraient différemment.
  Future<ProximityRules> fetchProximityTiers() async {
    final response = await _http
        .get(Uri.parse('$_baseUrl/proximity_tiers?select=tier,max_distance_m,weight&order=tier'))
        .timeout(_timeout);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFor(response), statusCode: response.statusCode);
    }
    return ProximityRules.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>,
    );
  }

  /// Les seuils de résolution du §6.1, publiés par le serveur.
  ///
  /// Mêmes raisons que pour les paliers : l'app affiche la règle, elle n'en décide
  /// pas, et deux versions installées en même temps doivent annoncer le même seuil.
  Future<ModerationRules> fetchModerationRules() async {
    final response = await _http
        .get(Uri.parse('$_baseUrl/moderation_settings?select=min_resolve_votes,descriptions_enabled'))
        .timeout(_timeout);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFor(response), statusCode: response.statusCode);
    }
    return ModerationRules.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>,
    );
  }

  /// L'annonce en cours, s'il y en a une (§4.3 amendé).
  ///
  /// Une ligne écrite depuis la console, la plus récente si plusieurs courent.
  /// Même requête pour tout le monde, sans en-tête ni corps : le serveur n'en
  /// apprend rien (§11.5). Lue au lancement et au retour au premier plan, comme
  /// l'avis de version.
  Future<Announcement?> fetchAnnouncement() async {
    final response = await _http
        .get(
          Uri.parse(
            '$_baseUrl/announcements_public?select=id,body,ends_at&order=starts_at.desc&limit=1',
          ),
        )
        .timeout(_timeout);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFor(response), statusCode: response.statusCode);
    }
    final rows = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    if (rows.isEmpty) return null;
    return Announcement.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Les dangers d'une zone, et si le serveur a dû couper.
  ///
  /// Actifs et contestés uniquement : un danger résolu quitte la carte (§6.1).
  ///
  /// `truncated` vaut vrai quand le plafond de la requête est atteint : la
  /// réponse ne décrit alors plus la zone entière. Le client ne doit ni la
  /// mémoriser comme complète ni déduire une absence de ce qui manque (§10).
  Future<({List<Hazard> hazards, bool truncated})> hazardsInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    List<String>? types,
    int? minSeverity,
  }) async {
    final result = await _rpc('hazards_in_bbox', {
      'min_lon': minLng,
      'min_lat': minLat,
      'max_lon': maxLng,
      'max_lat': maxLat,
      if (types != null) 'types': types,
      if (minSeverity != null) 'min_severity': minSeverity,
    }) as Map<String, dynamic>;

    return (
      hazards: (result['features'] as List<dynamic>)
          .map((f) => Hazard.fromFeature(f as Map<String, dynamic>))
          .toList(),
      // Absent d'un serveur plus ancien : on suppose alors une réponse complète,
      // ce qui est le comportement d'avant.
      truncated: result['truncated'] as bool? ?? false,
    );
  }

  Future<HazardDetail?> hazardDetail(String id) async {
    final result = await _rpc('hazard_detail', {'id': id});
    if (result == null) return null;
    return HazardDetail.fromJson(result as Map<String, dynamic>);
  }

  /// Signaler (§4.1 F2). `proximity` est le palier calculé sur l'appareil, de
  /// 1 (sur place) à 3 (loin, ou sans position) : la position du déclarant ne
  /// part jamais, ni ici ni ailleurs (§6.2, §11.1).
  Future<ReportOutcome> reportHazard({
    required String clientId,
    required String deviceId,
    required String type,
    required double lat,
    required double lng,
    required int severity,
    String? description,
    required int proximity,
  }) async {
    final result = await _rpc('report_hazard', {
      'client_id': clientId,
      'device_id': deviceId,
      'type': type,
      'lat': lat,
      'lng': lng,
      'severity': severity,
      if (description != null && description.isNotEmpty) 'description': description,
      'proximity': proximity,
    }) as Map<String, dynamic>;

    if (result.containsKey('duplicate_of')) {
      return DuplicateFound(
        existing: Hazard.fromJson(result['hazard'] as Map<String, dynamic>),
        distanceM: (result['distance_m'] as num).toDouble(),
      );
    }
    return HazardCreated(Hazard.fromJson(result));
  }

  Future<Hazard> confirmHazard({
    required String clientId,
    required String deviceId,
    required String hazardId,
    required int proximity,
  }) async {
    final result = await _rpc('confirm_hazard', {
      'client_id': clientId,
      'id': hazardId,
      'device_id': deviceId,
      'proximity': proximity,
    });
    return Hazard.fromJson(result as Map<String, dynamic>);
  }

  Future<Hazard> markResolved({
    required String clientId,
    required String deviceId,
    required String hazardId,
    required int proximity,
  }) async {
    final result = await _rpc('mark_resolved', {
      'client_id': clientId,
      'id': hazardId,
      'device_id': deviceId,
      'proximity': proximity,
    });
    return Hazard.fromJson(result as Map<String, dynamic>);
  }

  /// Retrait par l'auteur, dans les 24 h (§6.1). Au-delà, le serveur refuse et
  /// renvoie un message qui renvoie vers le vote « résolu ».
  Future<Hazard> removeOwnHazard({
    required String clientId,
    required String deviceId,
    required String hazardId,
  }) async {
    final result = await _rpc('remove_own_hazard', {
      'client_id': clientId,
      'id': hazardId,
      'device_id': deviceId,
    });
    return Hazard.fromJson(result as Map<String, dynamic>);
  }

  /// « Effacer mes données » (§11.4).
  ///
  /// Le serveur met `device_id` à `NULL` sur tous les événements de ce terminal
  /// et `created_by` sur ses signalements, puis oublie le terminal lui-même. Les
  /// signalements restent : ce sont des données sur la voirie.
  ///
  /// Rend le nombre de gestes détachés, pour pouvoir le dire à l'écran plutôt
  /// que de se contenter d'un « c'est fait » invérifiable.
  /// « Retirer mes signalements récents » (§11.4 amendé) : tous ceux de ce
  /// terminal créés il y a moins de 24 h, d'un coup. Renvoie combien.
  Future<int> removeOwnRecentHazards(String deviceId) async {
    final result = await _rpc('remove_own_recent_hazards', {'device_id': deviceId});
    return ((result as Map<String, dynamic>)['removed'] as num?)?.toInt() ?? 0;
  }

  Future<int> forgetDevice(String deviceId) async {
    final result = await _rpc('forget_device', {'device_id': deviceId});
    final map = result as Map<String, dynamic>;
    return (map['events_anonymized'] as num?)?.toInt() ?? 0;
  }

  void dispose() => _http.close();
}
