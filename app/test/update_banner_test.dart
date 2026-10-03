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

/// Le bandeau de mise à jour (§12.6) : il apparaît quand le serveur annonce
/// plus récent, il se tait sinon, et le toucher passe l'adresse au navigateur
/// puis s'efface — pour cette version seulement.
void main() {
  late AppDatabase db;
  late HazardRepository repo;
  final opened = <String>[];
  late _FakeServer updates;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() {
    db = AppDatabase.memory();
    repo = HazardRepository(
      api: ApiClient(httpClient: _FakeServer(), baseUrl: 'http://test/rest/v1'),
      db: db,
      device: DeviceIdentity(),
    );
    opened.clear();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('me.safe/system'), (call) async {
      if (call.method == 'openUrl') {
        opened.add((call.arguments as Map)['url'] as String);
        return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('me.safe/location'), (_) async => null);
  });

  tearDown(() async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('me.safe/system'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('me.safe/location'), null);
    await repo.dispose();
    await db.close();
  });

  Future<void> pumpMap(WidgetTester tester, Map<String, dynamic>? latest) async {
    updates = _FakeServer(latest: latest);
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          repo: repo,
          device: DeviceIdentity(),
          location: LocationService(),
          types: const [_pothole],
          mapStyle: '{"version":8,"sources":{},"layers":[]}',
          updates: UpdateChecker(
            httpClient: updates,
            url: 'http://test/fdroid/latest.json',
            installedCode: AppConfig.versionCode,
          ),
          mapBuilder: (_) => const ColoredBox(color: Color(0xFFEFEFEF)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> latest({int? code, int minCode = 0, String note = ''}) => {
        'versionName': '9.9.9',
        'versionCode': code ?? AppConfig.versionCode + 1,
        'url': 'http://test/fdroid/app-latest.apk',
        'minVersionCode': minCode,
        'note': note,
      };

  testWidgets('reprend la ligne écrite au moment de publier', (tester) async {
    await pumpMap(tester, latest(note: 'Corrige l\'envoi hors ligne.'));
    expect(
      find.text(
        MapLabels.updateWithNote(
          MapLabels.updateAvailable('9.9.9'),
          'Corrige l\'envoi hors ligne.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('annonce une version plus récente, et s\'efface une fois ouverte', (tester) async {
    await pumpMap(tester, latest());

    expect(find.text(MapLabels.updateAvailable('9.9.9')), findsOneWidget);

    await tester.tap(find.text(MapLabels.updateAvailable('9.9.9')));
    await tester.pumpAndSettle();

    expect(opened, ['http://test/fdroid/app-latest.apk']);
    expect(find.text(MapLabels.updateAvailable('9.9.9')), findsNothing);
  });

  testWidgets('une fois ouverte, ne revient que pour une version plus récente encore', (tester) async {
    await pumpMap(tester, latest());
    await tester.tap(find.text(MapLabels.updateAvailable('9.9.9')));
    await tester.pumpAndSettle();
    expect(find.text(MapLabels.updateAvailable('9.9.9')), findsNothing);

    // Retour au premier plan, même version annoncée : ne pas installer est un
    // choix, on ne le rappelle pas.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(MapLabels.updateAvailable('9.9.9')), findsNothing);

    // Une version publiée entre-temps est une autre nouvelle.
    updates.latest = {...latest(code: AppConfig.versionCode + 2), 'versionName': '10.0.0'};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(MapLabels.updateAvailable('10.0.0')), findsOneWidget);
  });

  testWidgets('se tait quand rien de plus récent n\'est publié', (tester) async {
    await pumpMap(tester, latest(code: AppConfig.versionCode));
    expect(find.text(MapLabels.updateAvailable('9.9.9')), findsNothing);
  });

  testWidgets('se tait quand le serveur n\'a pas de fichier', (tester) async {
    await pumpMap(tester, null);
    expect(find.text(MapLabels.updateAvailable('9.9.9')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dit « nécessaire » sous la version minimale', (tester) async {
    await pumpMap(tester, latest(minCode: AppConfig.versionCode + 1));
    expect(find.text(MapLabels.updateRequired('9.9.9')), findsOneWidget);
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

/// Le strict nécessaire pour que l'écran se monte : un catalogue, des réglages,
/// une carte vide. Et, sur demande, le fichier de dernière version.
class _FakeServer extends http.BaseClient {
  _FakeServer({this.latest});

  Map<String, dynamic>? latest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('latest.json')) {
      final body = latest;
      if (body == null) return _json(null, status: 404);
      return _json(body);
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
