import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/src/data/api_client.dart';
import 'package:app/src/data/device_identity.dart';
import 'package:app/src/data/hazard_repository.dart';
import 'package:app/src/data/local/database.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/location/location_service.dart';
import 'package:app/src/ui/map_screen.dart';
import 'package:app/src/ui/widgets/map_chrome.dart';
import 'package:app/src/ui/labels.dart';

/// L'écran carte, monté pour de vrai.
///
/// Seule la vue de carte est remplacée, par le point d'entrée `mapBuilder` : un
/// test n'a pas de vue native, et le plugin ne survit pas à la destruction d'une
/// carte qui n'en a jamais reçu. Aucun contrôleur n'arrive donc, et tout ce qui
/// en dépend reste au repos — c'est la partie qu'un test unitaire ne peut pas
/// vérifier de toute façon.
///
/// Tout ce qui l'entoure, si : le mode placement, les bandeaux, les outils. Et
/// c'est là que vivaient les défauts relevés par l'audit, dans un fichier de
/// 1200 lignes qui n'avait pas un seul test.
void main() {
  late AppDatabase db;
  late _FakeServer server;
  late HazardRepository repo;
  late _FakeLocation location;

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
    location = _FakeLocation()..install();
  });

  tearDown(() async {
    location.remove();
    await repo.dispose();
    await db.close();
  });

  Future<void> pumpMap(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          repo: repo,
          device: DeviceIdentity(),
          location: LocationService(),
          types: const [_pothole],
          mapStyle: '{"version":8,"sources":{},"layers":[]}',
          mapBuilder: (_) => const ColoredBox(color: Color(0xFFEFEFEF)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Deux frames, pas une : le dépôt annonce sa file par un flux, et l'écran ne
  /// se redessine qu'à la frame d'après. Une seule suffisait tant que
  /// `report()` lisait la base avant de rendre la main ; elle ne le fait plus.
  Future<void> queued(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// Rend la main sans minuteur en vie : `testWidgets` refuse de finir sur un
  /// minuteur en attente, et il y en a deux ici. La reprise d'envoi du dépôt,
  /// que vider la file arrête ; et le debounce de rechargement, qu'on laisse
  /// s'écouler — il ne fait rien, faute de contrôleur de carte.
  Future<void> unmount(WidgetTester tester) async {
    await repo.clearLocalData();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('consultation', () {
    testWidgets('propose de signaler, et rien d\'autre au premier plan', (tester) async {
      // §9 : un seul écran, un seul geste évident. Les outils sont en colonne, le
      // mode placement n'est pas encore ouvert.
      await pumpMap(tester);

      expect(find.widgetWithText(FloatingActionButton, MapLabels.report), findsOneWidget);
      expect(find.byType(PlacementBar), findsNothing);
      expect(find.byType(CenterPin), findsNothing);
      expect(find.byType(RoundButton), findsNWidgets(4));
      await unmount(tester);
    });

    testWidgets('ne montre aucun bandeau quand rien n\'attend', (tester) async {
      await pumpMap(tester);

      expect(find.byType(TopBanner), findsNothing);
      await unmount(tester);
    });
  });

  group('gestes en attente', () {
    testWidgets('le bandeau paraît dès qu\'un geste est mis en file', (tester) async {
      // §10 : un geste fait hors ligne doit laisser une trace à l'écran, sinon
      // rien ne dit qu'il n'est pas parti.
      await pumpMap(tester);
      server.offline = true;

      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);
      await queued(tester);

      expect(find.text(MapLabels.pending(1)), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('il compte les gestes et s\'accorde', (tester) async {
      await pumpMap(tester);
      server.offline = true;

      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);
      await queued(tester);
      expect(find.text(MapLabels.pending(1)), findsOneWidget);

      await repo.report(type: 'pothole', lat: 48.86, lng: 2.36, severity: 2);
      await queued(tester);
      expect(find.text(MapLabels.pending(2)), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('il disparaît quand la file se vide', (tester) async {
      await pumpMap(tester);
      server.offline = true;
      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);
      await queued(tester);

      server.offline = false;
      await repo.drain();
      await tester.pumpAndSettle();

      expect(find.byType(TopBanner), findsNothing);
      await unmount(tester);
    });
  });

  group('mode placement', () {
    testWidgets('« Signaler » ouvre le placement et cache le bouton', (tester) async {
      await pumpMap(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, MapLabels.report));
      await tester.pumpAndSettle();

      expect(find.byType(PlacementBar), findsOneWidget);
      expect(find.byType(CenterPin), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, MapLabels.report), findsNothing);
      await unmount(tester);
    });

    testWidgets('les outils se grisent pendant le placement', (tester) async {
      // On ne quitte pas un geste en cours par mégarde en visant un bouton voisin.
      // Recentrer reste actif : c'est ce qui aide à poser le pin.
      await pumpMap(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, MapLabels.report));
      await tester.pumpAndSettle();

      final buttons = tester.widgetList<RoundButton>(find.byType(RoundButton)).toList();
      expect(buttons.where((b) => b.onPressed == null), hasLength(3));
      expect(
        buttons.singleWhere((b) => b.tooltip == MapLabels.recenter).onPressed,
        isNotNull,
      );
      await unmount(tester);
    });

    testWidgets('le bandeau d\'attente s\'efface pendant le placement', (tester) async {
      // Il recouvrirait le haut de la carte au moment où l'on vise, et il n'a
      // rien à dire sur le geste en cours.
      await pumpMap(tester);
      server.offline = true;
      await repo.report(type: 'pothole', lat: 48.85, lng: 2.35, severity: 2);
      await queued(tester);
      expect(find.byType(TopBanner), findsOneWidget);

      await tester.tap(find.widgetWithText(FloatingActionButton, MapLabels.report));
      await tester.pumpAndSettle();

      expect(find.byType(TopBanner), findsNothing);
      await unmount(tester);
    });

    testWidgets('« Annuler » referme le placement et rend le bouton', (tester) async {
      await pumpMap(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, MapLabels.report));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, MapLabels.cancel));
      await tester.pumpAndSettle();

      expect(find.byType(PlacementBar), findsNothing);
      expect(find.byType(CenterPin), findsNothing);
      expect(find.widgetWithText(FloatingActionButton, MapLabels.report), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('sans contrôleur de carte, on ne peut pas encore valider', (tester) async {
      // Le zoom par défaut est sous le seuil de placement : la barre l'explique
      // et propose de zoomer plutôt que de présenter un bouton muet (§11.6).
      await pumpMap(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, MapLabels.report));
      await tester.pumpAndSettle();

      expect(find.text(MapLabels.placeZoomIn), findsOneWidget);
      expect(find.widgetWithText(FilledButton, MapLabels.placeZoom), findsOneWidget);
      expect(find.text(MapLabels.placeContinue), findsNothing);
      await unmount(tester);
    });
  });
}

const _pothole = HazardType(
  code: 'pothole',
  label: 'Nid-de-poule',
  iconName: 'pothole',
  resolvedLabel: 'Réparé',
  dedupRadiusM: 15,
  enabled: true,
  sortOrder: 10,
);

/// Le canal natif de localisation, muet : refuser la position est un usage
/// normal (§6.2), et c'est l'état le plus simple à tenir en test.
class _FakeLocation {
  static const _method = MethodChannel('me.safe/location');
  static const _stream = MethodChannel('me.safe/location/stream');

  void install() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _method,
      (call) async => switch (call.method) {
        'hasPermission' => false,
        'requestPermission' => false,
        'isLocationEnabled' => true,
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(_stream, (_) async => null);
  }

  void remove() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockMethodCallHandler(_stream, null);
  }
}

/// Un serveur qu'on peut débrancher, comme dans `hazard_repository_test`.
class _FakeServer extends http.BaseClient {
  bool offline = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw const SocketException('réseau coupé');

    final path = request.url.path;
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
    if (path.endsWith('moderation_settings')) {
      return _json([
        {'min_resolve_votes': 2},
      ]);
    }
    if (path.endsWith('hazards_in_bbox')) {
      return _json({'type': 'FeatureCollection', 'features': <dynamic>[]});
    }
    if (path.endsWith('report_hazard')) {
      return _json({
        'id': 'créé-par-le-serveur',
        'type': 'pothole',
        'lat': 48.85,
        'lng': 2.35,
        'severity': 2,
        'status': 'active',
        'created_at': '2026-09-13T22:00:00+00:00',
        'last_confirmed_at': '2026-09-13T22:00:00+00:00',
        'resolve_weight': 0,
        'resolve_threshold': 2,
        'reported_remotely': false,
      });
    }
    return _json(<String, dynamic>{}, 200);
  }

  http.StreamedResponse _json(Object body, [int status = 200]) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status);
}
