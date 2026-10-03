import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/src/config.dart';
import 'package:app/src/data/api_client.dart';
import 'package:app/src/data/app_update.dart';
import 'package:app/src/data/device_identity.dart';
import 'package:app/src/data/hazard_repository.dart';
import 'package:app/src/data/local/database.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/location/location_service.dart';
import 'package:app/src/ui/labels.dart';
import 'package:app/src/ui/map_screen.dart';

/// Le retour au premier plan est le moment où le monde a pu changer sans
/// l'app : un type activé depuis la console (§3), une version publiée (§12.6).
/// Elle redemande les deux au serveur, sans que personne n'ait à la fermer.
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
          updates: UpdateChecker(
            httpClient: server,
            url: 'http://test/fdroid/latest.json',
            installedCode: AppConfig.versionCode,
          ),
          mapBuilder: (_) => const ColoredBox(color: Color(0xFFEFEFEF)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('un type activé depuis la console apparaît au retour au premier plan',
      (tester) async {
    await pumpMap(tester);

    // Un seul type : la feuille des filtres n'a pas de choix à proposer.
    await tester.tap(find.byTooltip(MapLabels.filters));
    await tester.pumpAndSettle();
    expect(find.text('Éclairage défaillant'), findsNothing);
    await tester.tap(find.text(FiltersLabels.apply));
    await tester.pumpAndSettle();

    // La console active un second type ; l'utilisateur revient sur l'app.
    server.types = [_potholeJson, _lightingJson];
    await resume(tester);

    await tester.tap(find.byTooltip(MapLabels.filters));
    await tester.pumpAndSettle();
    expect(find.text('Éclairage défaillant'), findsOneWidget);
  });

  testWidgets('une version publiée entre-temps est annoncée au retour au premier plan',
      (tester) async {
    await pumpMap(tester);
    expect(find.text(MapLabels.updateAvailable('9.9.9')), findsNothing);

    server.latest = {
      'versionName': '9.9.9',
      'versionCode': AppConfig.versionCode + 1,
      'url': 'http://test/fdroid/app-latest.apk',
    };
    await resume(tester);

    expect(find.text(MapLabels.updateAvailable('9.9.9')), findsOneWidget);
  });

  testWidgets('un serveur muet au retour ne change rien', (tester) async {
    await pumpMap(tester);
    server.offline = true;
    await resume(tester);

    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip(MapLabels.filters));
    await tester.pumpAndSettle();
    expect(find.text(FiltersLabels.apply), findsOneWidget);
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

const _potholeJson = {
  'code': 'pothole',
  'label_fr': 'Nid-de-poule',
  'icon': 'pothole',
  'resolved_label_fr': 'Réparé',
  'dedup_radius_m': 15,
  'enabled': true,
  'sort_order': 10,
};

const _lightingJson = {
  'code': 'lighting',
  'label_fr': 'Éclairage défaillant',
  'icon': 'lighting',
  'resolved_label_fr': 'Rétabli',
  'dedup_radius_m': 25,
  'enabled': true,
  'sort_order': 20,
};

/// Un serveur dont le catalogue et la dernière version changent en cours de
/// test, comme la console et une publication le feraient.
class _FakeServer extends http.BaseClient {
  List<Map<String, dynamic>> types = [_potholeJson];
  Map<String, dynamic>? latest;
  bool offline = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw http.ClientException('réseau coupé');
    final path = request.url.path;
    if (path.endsWith('latest.json')) {
      final body = latest;
      return body == null ? _json(null, status: 404) : _json(body);
    }
    if (path.endsWith('hazard_types')) return _json(types);
    if (path.endsWith('moderation_settings')) {
      return _json([
        {'min_resolve_votes': 2},
      ]);
    }
    if (path.endsWith('proximity_tiers')) {
      return _json([
        {'tier': 0, 'max_distance_m': 50, 'weight': 3},
        {'tier': 1, 'max_distance_m': 500, 'weight': 2},
        {'tier': 2, 'max_distance_m': null, 'weight': 1},
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
