import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/src/data/api_client.dart';
import 'package:app/src/data/device_identity.dart';
import 'package:app/src/data/hazard_repository.dart';
import 'package:app/src/data/local/database.dart';
import 'package:app/src/data/models/hazard.dart';
import 'package:app/src/location/location_service.dart';

void main() {
  late AppDatabase db;
  late _FakeServer server;
  late HazardRepository repo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() {
    db = AppDatabase.memory();
    server = _FakeServer();
    repo = HazardRepository(
      api: ApiClient(httpClient: server, baseUrl: 'http://test/rest/v1'),
      db: db,
      device: DeviceIdentity(),
    );
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  group('en ligne', () {
    test('déclare son terminal une fois, puis se tait', () async {
      FlutterSecureStorage.setMockInitialValues({});
      // §6.3 amendé (0250) : le quart d'heure avant « Plus là » part de
      // l'ouverture de l'app. Une fois par identifiant, pas à chaque lancement.
      await repo.declareDevice();
      await repo.declareDevice();
      expect(server.declared, 1);
      expect(server.writes, 0, reason: 'déclarer n\'est pas un geste');
    });

    test('un identifiant neuf se déclare à nouveau', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final device = DeviceIdentity();
      repo = HazardRepository(
        api: ApiClient(httpClient: server, baseUrl: 'http://test/rest/v1'),
        db: db,
        device: device,
      );
      await repo.declareDevice();
      await device.regenerate();
      await repo.declareDevice();
      expect(server.declared, 2);
    });

    test('une déclaration qui échoue ne gêne personne et sera retentée', () async {
      FlutterSecureStorage.setMockInitialValues({});
      server.offline = true;
      await repo.declareDevice();
      server.offline = false;
      await repo.declareDevice();
      expect(server.declared, 1);
    });

    test('déclare le palier calculé sur l\'appareil, jamais une position', () async {
      // Le serveur ne reçoit plus de coordonnée du déclarant : le palier est calculé ici
      // (§11.1). Ce test garde la promesse vérifiable sans lire le code du RPC.
      await repo.types();
      await repo.report(
        type: 'pothole',
        lat: 48.8532,
        lng: 2.3692,
        severity: 2,
        position: const DevicePosition(lat: 48.8532, lng: 2.3692, accuracy: 5),
      );

      expect(server.dernierSignalement!['proximity'], 1);
      expect(server.dernierSignalement!.containsKey('device_lat'), isFalse);
      expect(server.dernierSignalement!.containsKey('device_lng'), isFalse);
    });

    test('un geste fait de loin pèse le moins', () async {
      await repo.types();
      await repo.report(
        type: 'pothole',
        lat: 48.8532,
        lng: 2.3692,
        severity: 2,
        position: const DevicePosition(lat: 45.7640, lng: 4.8357, accuracy: 5),
      );

      expect(server.dernierSignalement!['proximity'], 3);
    });

    test('sans position, le palier le moins favorable plutôt qu\'un refus', () async {
      await repo.types();
      await repo.report(type: 'pothole', lat: 48.8532, lng: 2.3692, severity: 2);

      expect(server.dernierSignalement!['proximity'], 3);
    });

    test('applique la règle du serveur, pas celle qui est compilée', () async {
      // Deux versions de l'app installées en même temps doivent pondérer pareil :
      // c'est le serveur qui publie les seuils.
      server.tiers = const [
        {'tier': 1, 'max_distance_m': 10, 'weight': 1.0},
        {'tier': 2, 'max_distance_m': 200, 'weight': 0.5},
        {'tier': 3, 'max_distance_m': null, 'weight': 0.25},
      ];
      await repo.types();
      await repo.report(
        type: 'pothole',
        lat: 48.8532,
        lng: 2.3692,
        severity: 2,
        // 30 m : palier 1 avec la règle compilée, palier 2 avec celle-ci.
        position: DevicePosition(lat: 48.8532 + 30 / 111320.0, lng: 2.3692, accuracy: 5),
      );

      expect(server.dernierSignalement!['proximity'], 2);
    });

    test('une règle indisponible ne bloque pas le geste', () async {
      server.tiers = null;
      await repo.types();
      await repo.report(
        type: 'pothole',
        lat: 48.8532,
        lng: 2.3692,
        severity: 2,
        position: const DevicePosition(lat: 48.8532, lng: 2.3692, accuracy: 5),
      );

      expect(server.dernierSignalement!['proximity'], 1, reason: 'la règle compilée s\'applique');
    });

    test('rapporte la silhouette du type et la garde en cache', () async {
      server.icons = {'pothole': _silhouetteB64};

      final types = await repo.types();
      expect(types.single.iconPng, isNotNull);

      // Relue depuis le cache : hors ligne, le marqueur reste dessiné comme il
      // faut, sans repasser par le réseau.
      server.offline = true;
      final horsLigne = await repo.types();
      expect(horsLigne.single.iconPng, equals(types.single.iconPng));
    });

    test('un service d\'icônes en panne ne prive pas du catalogue', () async {
      // Les silhouettes sont un agrément : sans elles l'app dessine les glyphes
      // embarqués. Faire échouer le catalogue pour autant serait disproportionné.
      server.iconsEnPanne = true;

      final types = await repo.types();
      expect(types, hasLength(1));
      expect(types.single.iconPng, isNull);
    });

    test('sert le serveur et garnit le cache', () async {
      server.hazards = [_hazard('a')];
      final view = await repo.hazardsInBbox(
        minLng: 2.3,
        minLat: 48.8,
        maxLng: 2.4,
        maxLat: 48.9,
      );

      expect(view.hazards.single.id, 'a');
      expect(view.fromCache, isFalse);
      expect(await db.select(db.cachedHazards).get(), hasLength(1));
    });

    test('n\'empile rien dans la file', () async {
      server.hazards = [_hazard('a')];
      await repo.confirm('a');

      expect(repo.pendingCount, 0);
    });
  });

  group('hors ligne', () {
    test('rend le cache plutôt qu\'une erreur', () async {
      server.hazards = [_hazard('a')];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);

      server.offline = true;
      final view = await repo.hazardsInBbox(
        minLng: 2.3,
        minLat: 48.8,
        maxLng: 2.4,
        maxLat: 48.9,
      );

      expect(view.hazards.single.id, 'a');
    });

    test('applique au cache les mêmes filtres que le serveur', () async {
      // Le cache doit répondre comme `hazards_in_bbox` (§8), sinon la carte
      // change de sens quand le réseau tombe.
      server.hazards = [
        _hazard('grave', severity: 3),
        _hazard('bénin', severity: 1),
        _hazard('résolu', status: 'resolved'),
      ];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.offline = true;

      final filtered = await repo.hazardsInBbox(
        minLng: 2.3,
        minLat: 48.8,
        maxLng: 2.4,
        maxLat: 48.9,
        minSeverity: 2,
      );

      expect(filtered.hazards.map((h) => h.id), ['grave']);
    });

    test('montre le signalement tout de suite, sans l\'écrire en base', () async {
      server.offline = true;
      final outcome = await repo.report(
        type: 'pothole',
        lat: 48.85,
        lng: 2.35,
        severity: 2,
      );

      expect(outcome, isA<ReportQueued>());
      expect(repo.pendingCount, 1);
      // Le marqueur provisoire s'affiche...
      final view = await repo.hazardsInBbox(
        minLng: 2.3,
        minLat: 48.8,
        maxLng: 2.4,
        maxLat: 48.9,
      );
      expect(view.hazards, hasLength(1));
      // ...mais rien n'est allé sur le disque : sans l'action qui le porte, il
      // n'a plus de sens.
      expect(await db.select(db.cachedHazards).get(), isEmpty);
    });

    test('ne touche pas au danger quand le serveur n\'a pas tranché', () async {
      server.hazards = [_hazard('a', resolveWeight: 0.5)];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.offline = true;

      final outcome = await repo.confirm('a');

      // Deviner la décision du serveur serait mentir à l'utilisateur (§10).
      expect(outcome, isA<ActionQueued>());
      expect((outcome as ActionQueued).unchanged!.resolveWeight, 0.5);
    });
  });

  group('vidage de la file', () {
    test('envoie dans l\'ordre et remplace le provisoire', () async {
      server.offline = true;
      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);
      server.offline = false;

      final report = await repo.drain();

      expect(report.sent, 1);
      expect(repo.pendingCount, 0);
      final cached = await db.select(db.cachedHazards).get();
      expect(cached.single.id, server.createdId);
    });

    test('garde le geste tant que le réseau manque', () async {
      server.offline = true;
      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);

      final report = await repo.drain();

      expect(report.sent, 0);
      expect(report.remaining, 1);
      expect(repo.pendingCount, 1);
    });

    test('jette le geste que le serveur refuse', () async {
      // Un refus est une réponse : rejouer ne la changera pas (§10).
      server.hazards = [_hazard('a')];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.offline = true;
      await repo.confirm('a');

      server.offline = false;
      server.refuse = 'Vous avez déjà confirmé ce danger.';
      final report = await repo.drain();

      expect(report.refused, 1);
      expect(repo.pendingCount, 0);
    });

    test('garde le geste quand le serveur répond 5xx : ce n\'est pas un refus', () async {
      // PostgREST qui redémarre pendant un vidage répondait 503, que la file
      // prenait pour un refus définitif : le geste était jeté, et compté
      // « refusé » dans les mesures (AUDIT C4).
      server.hazards = [_hazard('a')];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.offline = true;
      await repo.confirm('a');

      server.offline = false;
      server.failWith = 503;
      final report = await repo.drain();

      expect(report.refused, 0);
      expect(report.remaining, 1);
      expect(repo.pendingCount, 1);

      // Le serveur revient : le geste part.
      server.failWith = null;
      expect((await repo.drain()).sent, 1);
    });

    test('ne vide pas la file deux fois en parallèle', () async {
      // Le minuteur, le retour au premier plan et le tap sur le bandeau peuvent
      // appeler `drain()` en même temps. Deux boucles sur la même file
      // enverraient chaque geste deux fois, et la seconde réponse — « déjà
      // voté » — passerait pour un refus (AUDIT I10).
      server.offline = true;
      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);
      server.offline = false;
      server.writes = 0;

      final reports = await Future.wait([repo.drain(), repo.drain(), repo.drain()]);

      expect(server.writes, 1);
      expect(reports.map((r) => r.sent), everyElement(1));
      expect(reports.map((r) => r.refused), everyElement(0));
    });

    test('s\'arrête au premier échec réseau sans marteler la suite', () async {
      server.hazards = [_hazard('a'), _hazard('b')];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.offline = true;
      await repo.confirm('a');
      await repo.confirm('b');

      server.calls = 0;
      final report = await repo.drain();

      expect(report.remaining, 2);
      expect(server.calls, 1);
    });

    test('annonce le compteur à chaque changement', () async {
      final seen = <int>[];
      final sub = repo.pendingChanges.listen(seen.add);

      server.offline = true;
      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);
      server.offline = false;
      await repo.drain();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen, [1, 0]);
    });
  });

  group('cache', () {
    test('distingue une zone jamais chargée d\'une zone vide', () async {
      // Sans cela, la carte afficherait un vide rassurant et faux (§10).
      expect(
        await repo.hasFreshCacheFor(minLat: 48.8, minLng: 2.3, maxLat: 48.9, maxLng: 2.4),
        isFalse,
      );

      server.hazards = [];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);

      expect(
        await repo.hasFreshCacheFor(minLat: 48.85, minLng: 2.35, maxLat: 48.86, maxLng: 2.36),
        isTrue,
      );
    });

    test('avoue ne pas savoir sur une zone jamais chargée', () async {
      // Hors ligne sur une zone inconnue, une carte sans marqueur se lit
      // « pas de danger ici ». C'est le pire mensonge possible pour ce produit.
      server.hazards = [_hazard('a')];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.offline = true;

      // Une zone déjà chargée : le silence du cache veut dire quelque chose.
      final connue = await repo.hazardsInBbox(
        minLng: 2.35,
        minLat: 48.85,
        maxLng: 2.36,
        maxLat: 48.86,
      );
      expect(connue.isBlind, isFalse);

      // Une zone jamais vue : il ne veut rien dire.
      final inconnue = await repo.hazardsInBbox(
        minLng: 2.5,
        minLat: 48.9,
        maxLng: 2.6,
        maxLat: 49.0,
      );
      expect(inconnue.hazards, isEmpty);
      expect(inconnue.isBlind, isTrue);
    });

    test('ne prétend jamais être aveugle quand le serveur répond', () async {
      server.hazards = [];
      final view = await repo.hazardsInBbox(
        minLng: 2.5,
        minLat: 48.9,
        maxLng: 2.6,
        maxLat: 49.0,
      );

      expect(view.isBlind, isFalse);
      expect(view.fromCache, isFalse);
    });

    test('une réponse tronquée n\'est pas une description de la zone', () async {
      // Au-delà du plafond, le serveur coupe. Mémoriser la zone comme complète
      // ferait ensuite affirmer « rien d'autre ici » sur ce qu'il a laissé
      // dehors, et l'élagage de la carte effacerait des dangers réels (AUDIT M11).
      server.hazards = [_hazard('a')];
      server.tronque = true;

      final view = await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      expect(view.truncated, isTrue);
      expect(view.covered, isFalse);

      server.offline = true;
      final horsLigne = await repo.hazardsInBbox(
        minLng: 2.3,
        minLat: 48.8,
        maxLng: 2.4,
        maxLat: 48.9,
      );
      expect(horsLigne.isBlind, isTrue, reason: 'la zone n\'a jamais été décrite en entier');
    });

    test('ne prétend pas couvrir une zone chargée avec un filtre', () async {
      // En ligne avec « très dangereux seulement », puis hors ligne sans filtre :
      // le cache ne connaît que les dangers graves de cette zone. Dire « rien
      // d'autre ici » serait faux (AUDIT I13).
      // Le faux serveur ne filtre pas : on lui donne ce qu'il renverrait pour ce filtre.
      server.hazards = [_hazard('grave', severity: 3)];
      await repo.hazardsInBbox(
        minLng: 2.3,
        minLat: 48.8,
        maxLng: 2.4,
        maxLat: 48.9,
        minSeverity: 3,
      );
      server.offline = true;

      final view = await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);

      expect(view.isBlind, isTrue, reason: 'la zone n\'a été vue qu\'à travers un filtre');
      expect(view.hazards.map((h) => h.id), ['grave'], reason: 'ce qu\'on a vu reste servi');
    });

    test('oublie un danger que le serveur ne renvoie plus dans la zone', () async {
      // Retiré par la console, résolu par d'autres : le garder en cache ferait
      // revivre un fantôme à la prochaine coupure (AUDIT C5).
      server.hazards = [_hazard('a'), _hazard('b')];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.hazards = [_hazard('a')];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.offline = true;

      final view = await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);

      expect(view.hazards.map((h) => h.id), ['a']);
    });

    test('le détail d\'un signalement en file se dit provisoire', () async {
      // Aucun geste ne doit porter dessus : le serveur ne le connaît pas (AUDIT I14).
      server.offline = true;
      final outcome = await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);
      final id = (outcome as ReportQueued).provisional.id;

      final detail = await repo.detail(id);

      expect(detail!.provisional, isTrue);
      expect(detail.hazard.resolveThreshold, 2, reason: 'le seuil publié, pas 1');
    });

    test('le marqueur provisoire annonce le seuil que le serveur publie', () async {
      // Le seuil est une règle du serveur (§6.1) : si elle change, un signalement
      // encore en file doit annoncer la nouvelle, pas celle compilée dans l'app.
      server.seuils = [
        {'min_resolve_votes': 4},
      ];
      await repo.types();
      server.offline = true;

      final outcome = await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);

      expect((outcome as ReportQueued).provisional.resolveThreshold, 4);
    });

    test('garde le seuil compilé quand le serveur ne publie rien', () async {
      // Premier lancement sans réseau : afficher « 1 vote sur 1 » serait faux
      // dès la première synchronisation.
      server.seuils = null;
      await repo.types();
      server.offline = true;

      final outcome = await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);

      expect((outcome as ReportQueued).provisional.resolveThreshold, 2);
    });

    test('sert le catalogue en cache quand le serveur répond 5xx', () async {
      // Un 500 au démarrage ne doit pas bloquer une app qui a déjà tout ce qu'il
      // lui faut pour consulter (AUDIT I12).
      await repo.types();
      server.failWith = 500;

      final types = await repo.types();

      expect(types.single.code, 'pothole');
    });

    test('sert le catalogue de la dernière fois', () async {
      await repo.types();
      server.offline = true;

      final types = await repo.types();

      expect(types.single.code, 'pothole');
    });

    test('laisse remonter l\'erreur si le catalogue n\'a jamais été lu', () async {
      // Sans catalogue il n'y a pas d'écran à dessiner : mieux vaut l'écran
      // d'erreur que du vide (§3).
      server.offline = true;
      expect(() => repo.types(), throwsA(isA<Exception>()));
    });

    test('efface tout à la demande sans toucher au serveur', () async {
      server.hazards = [_hazard('a')];
      await repo.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);
      server.offline = true;
      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);

      await repo.clearLocalData();

      expect(await db.select(db.cachedHazards).get(), isEmpty);
      expect(repo.pendingCount, 0);
    });
  });
}

// --- Doublures ---------------------------------------------------------------

Map<String, dynamic> _hazard(
  String id, {
  int severity = 2,
  String status = 'active',
  double resolveWeight = 0,
}) =>
    {
      'id': id,
      'type': 'pothole',
      'lat': 48.85,
      'lng': 2.35,
      'severity': severity,
      'status': status,
      'created_at': '2026-09-13T22:00:00+00:00',
      'last_confirmed_at': '2026-09-13T22:00:00+00:00',
      'resolve_weight': resolveWeight,
      'resolve_threshold': 2,
      'reported_remotely': false,
    };

/// Un serveur qu'on peut débrancher. `offline` lève une `SocketException`, comme
/// le ferait une vraie coupure ; `refuse` répond une erreur métier, qui n'est pas
/// la même chose du tout (§10).
class _FakeServer extends http.BaseClient {
  List<Map<String, dynamic>> hazards = [];
  /// Silhouettes servies par `hazard_type_icons_public`, en base64 (§4.3).
  Map<String, String> icons = {};
  /// Pour vérifier que le catalogue survit à leur absence.
  bool iconsEnPanne = false;
  /// Le dernier corps envoyé à `report_hazard`, pour lire le palier déclaré.
  Map<String, dynamic>? dernierSignalement;
  /// Règle de proximité servie ; `null` pour ne rien servir du tout.
  List<Map<String, dynamic>>? tiers = const [
    {'tier': 1, 'max_distance_m': 50, 'weight': 1.0},
    {'tier': 2, 'max_distance_m': 500, 'weight': 0.5},
    {'tier': 3, 'max_distance_m': null, 'weight': 0.25},
  ];
  /// Seuils de résolution servis ; `null` pour ne rien servir du tout.
  List<Map<String, dynamic>>? seuils = const [
    {'min_resolve_votes': 2},
  ];
  bool offline = false;
  /// Le serveur a atteint son plafond : la réponse ne décrit pas toute la zone.
  bool tronque = false;
  String? refuse;
  /// Un serveur qui répond, mais mal : 503 pendant un redémarrage de PostgREST,
  /// 502 d'un frontal sans amont. Ce n'est pas un refus (§10).
  int? failWith;
  int calls = 0;
  /// Appels aux RPC d'écriture, pour compter ce qui part vraiment.
  int writes = 0;
  /// Déclarations de terminal reçues (0250).
  int declared = 0;
  String createdId = 'créé-par-le-serveur';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    if (offline) throw const SocketException('réseau coupé');
    if (failWith != null) return _json({'message': 'indisponible'}, failWith!);

    final path = request.url.path;
    if (refuse != null && path.contains('rpc/')) {
      return _json({'message': refuse}, 400);
    }

    if (path.endsWith('hazard_type_icons_public')) {
      if (iconsEnPanne) return _json({'message': 'indisponible'}, 500);
      return _json([
        for (final entry in icons.entries)
          {'type_code': entry.key, 'png_b64': entry.value},
      ]);
    }
    if (path.endsWith('hazard_types')) {
      return _json([
        {
          'code': 'pothole',
          'label_fr': 'Nid-de-poule',
          'icon': 'pothole',
          'resolved_label_fr': 'Réparé',
          'dedup_radius_m': 15,
          'enabled': true,
          'sort_order': 10,
        },
      ]);
    }
    if (path.endsWith('hazards_in_bbox')) {
      return _json({
        'type': 'FeatureCollection',
        'truncated': tronque,
        'features': [
          for (final h in hazards)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [h['lng'], h['lat']],
              },
              'properties': h,
            },
        ],
      });
    }
    if (path.endsWith('moderation_settings')) {
      final regle = seuils;
      if (regle == null) return _json({'message': 'indisponible'}, 500);
      return _json(regle);
    }
    if (path.endsWith('proximity_tiers')) {
      final regle = tiers;
      if (regle == null) return _json({'message': 'indisponible'}, 500);
      return _json(regle);
    }
    if (path.endsWith('declare_device')) {
      declared++;
      return _json({'since': '2026-10-04T10:00:00Z'});
    }
    if (path.endsWith('report_hazard')) {
      writes++;
      dernierSignalement =
          jsonDecode(utf8.decode(await request.finalize().toBytes())) as Map<String, dynamic>;
      return _json(_hazard(createdId));
    }
    if (path.endsWith('confirm_hazard') ||
        path.endsWith('mark_resolved') ||
        path.endsWith('remove_own_hazard')) {
      writes++;
      final body =
          jsonDecode(utf8.decode(await request.finalize().toBytes())) as Map<String, dynamic>;
      return _json(_hazard(body['id'] as String, resolveWeight: 1));
    }
    return _json({'message': 'chemin inattendu : $path'}, 404);
  }

  http.StreamedResponse _json(Object body, [int status = 200]) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(Stream.value(bytes), status);
  }
}

/// Un PNG 64 × 64, disque opaque sur fond transparent.
const _silhouetteB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII=';
