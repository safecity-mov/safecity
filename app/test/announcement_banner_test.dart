import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/src/data/announcements.dart';
import 'package:app/src/data/api_client.dart';
import 'package:app/src/data/device_identity.dart';
import 'package:app/src/data/hazard_repository.dart';
import 'package:app/src/data/local/database.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/location/location_service.dart';
import 'package:app/src/ui/map_screen.dart';

/// Le bandeau d'annonce (§4.3 amendé) : il reprend ce que la console a écrit,
/// se ferme au toucher et ne revient pas pour la même annonce, s'efface quand
/// le serveur ne l'annonce plus, et tient si le serveur ne répond pas.
void main() {
  late AppDatabase db;
  late HazardRepository repo;
  late _FakeServer server;

  const message = 'Les signalements du 21 au 27/09 ont été perdus : merci de les refaire.';

  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    server = _FakeServer();
    db = AppDatabase.memory();
    repo = HazardRepository(
      api: ApiClient(httpClient: server, baseUrl: 'http://test/rest/v1'),
      db: db,
      device: DeviceIdentity(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('me.safe/location'), (_) async => null);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('me.safe/location'), null);
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
          announcements: AnnouncementChecker(
            api: ApiClient(httpClient: server, baseUrl: 'http://test/rest/v1'),
            storage: const FlutterSecureStorage(),
          ),
          mapBuilder: (_) => const ColoredBox(color: Color(0xFFEFEFEF)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> announcement({int id = 1, String body = message}) =>
      {'id': id, 'body': body, 'ends_at': '2099-01-01T00:00:00+00:00'};

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('affiche ce que la console a écrit', (tester) async {
    server.announcements = [announcement()];
    await pumpMap(tester);
    expect(find.text(message), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
  });

  testWidgets('se tait quand rien n\'est annoncé, ou que le serveur ne répond pas', (tester) async {
    await pumpMap(tester);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);

    server.fail = true;
    await resume(tester);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('se ferme au toucher, et ne revient pas pour la même annonce', (tester) async {
    server.announcements = [announcement()];
    await pumpMap(tester);
    await tester.tap(find.text(message));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);

    // Retour au premier plan, même annonce : déjà lue.
    await resume(tester);
    expect(find.text(message), findsNothing);

    // Une autre annonce est une autre nouvelle.
    server.announcements = [announcement(id: 2, body: 'Le serveur redémarre à midi.')];
    await resume(tester);
    expect(find.text('Le serveur redémarre à midi.'), findsOneWidget);
  });

  testWidgets('la fermeture survit à un redémarrage de l\'app', (tester) async {
    server.announcements = [announcement()];
    await pumpMap(tester);
    await tester.tap(find.text(message));
    await tester.pumpAndSettle();

    // Un second écran, neuf, avec le même stockage : l'identifiant fermé y est encore.
    await pumpMap(tester);
    expect(find.text(message), findsNothing);
  });

  testWidgets('s\'efface quand l\'annonce est retirée, tient quand le serveur est injoignable',
      (tester) async {
    server.announcements = [announcement()];
    await pumpMap(tester);
    expect(find.text(message), findsOneWidget);

    server.fail = true;
    await resume(tester);
    expect(find.text(message), findsOneWidget, reason: 'pas de réseau : rien ne change');

    server.fail = false;
    server.announcements = [];
    await resume(tester);
    expect(find.text(message), findsNothing, reason: 'retirée depuis la console');
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

/// Le strict nécessaire pour que l'écran se monte, plus la vue des annonces.
class _FakeServer extends http.BaseClient {
  List<Map<String, dynamic>> announcements = [];
  bool fail = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('announcements_public')) {
      if (fail) return _json({'message': 'panne'}, status: 503);
      return _json(announcements);
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
    if (path.endsWith('moderation_settings')) {
      return _json([
        {'min_resolve_votes': 2},
      ]);
    }
    if (path.endsWith('proximity_tiers')) {
      return _json([
        {'tier': 1, 'max_distance_m': 100, 'weight': 1},
        {'tier': 2, 'max_distance_m': null, 'weight': 0.3333},
      ]);
    }
    if (path.endsWith('hazards_in_bbox')) {
      return _json({'type': 'FeatureCollection', 'features': <dynamic>[]});
    }
    return _json(<dynamic>[]);
  }

  http.StreamedResponse _json(Object? body, {int status = 200}) => http.StreamedResponse(
        Stream.value(utf8.encode(body == null ? '' : jsonEncode(body))),
        status,
        headers: const {'content-type': 'application/json'},
      );
}
