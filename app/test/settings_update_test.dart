import 'dart:convert';
import 'dart:io';

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
import 'package:app/src/location/location_service.dart';
import 'package:app/src/ui/labels.dart';
import 'package:app/src/ui/settings_screen.dart';

/// La ligne de version des Paramètres interroge le serveur à l'ouverture et
/// dit ce qu'il a répondu (§12.6) : à jour, plus récent, ou pas de réponse.
void main() {
  late AppDatabase db;
  late HazardRepository repo;
  final opened = <String>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() {
    db = AppDatabase.memory();
    repo = HazardRepository(
      api: ApiClient(httpClient: _Client(null), baseUrl: 'http://test/rest/v1'),
      db: db,
      device: DeviceIdentity(),
    );
    opened.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('me.safe/system'), (call) async {
      opened.add((call.arguments as Map)['url'] as String);
      return true;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('me.safe/system'), null);
    await repo.dispose();
    await db.close();
  });

  Future<void> open(WidgetTester tester, _Client client) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          repo: repo,
          device: DeviceIdentity(),
          location: LocationService(),
          updates: UpdateChecker(
            httpClient: client,
            url: 'http://test/fdroid/latest.json',
            installedCode: AppConfig.versionCode,
          ),
        ),
      ),
    );
    // « À propos » est en bas de liste : une ListView ne construit pas ce qui
    // est hors écran, il faut y aller pour le voir.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> latest(int code) => {
        'versionName': '9.9.9',
        'versionCode': code,
        'url': 'http://test/fdroid/app-latest.apk',
      };

  testWidgets('dit « à jour » quand rien de plus récent n\'est publié', (tester) async {
    await open(tester, _Client(latest(AppConfig.versionCode)));
    expect(find.textContaining(SettingsLabels.upToDate), findsOneWidget);
    expect(find.textContaining(SettingsLabels.version(AppConfig.version)), findsOneWidget);
  });

  testWidgets('propose la version plus récente, et la télécharge au toucher', (tester) async {
    await open(tester, _Client(latest(AppConfig.versionCode + 1)));

    final line = find.textContaining(SettingsLabels.updateFound('9.9.9'));
    expect(line, findsOneWidget);

    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(opened, ['http://test/fdroid/app-latest.apk']);
  });

  testWidgets('sans réponse, le dit et permet de réessayer', (tester) async {
    final client = _Client(null, offline: true);
    await open(tester, client);
    expect(find.textContaining(SettingsLabels.updateCheckFailed), findsOneWidget);

    // Le réseau revient : toucher la ligne relance la demande.
    client.offline = false;
    client.latest = latest(AppConfig.versionCode);
    await tester.tap(find.textContaining(SettingsLabels.updateCheckFailed));
    await tester.pumpAndSettle();
    expect(find.textContaining(SettingsLabels.upToDate), findsOneWidget);
  });
}

/// Répond `latest.json` — ou 404 sans fichier, ou une panne réseau — et un
/// catalogue vide pour tout le reste.
class _Client extends http.BaseClient {
  _Client(this.latest, {this.offline = false});

  Map<String, dynamic>? latest;
  bool offline;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw const SocketException('réseau coupé');
    if (request.url.path.endsWith('latest.json')) {
      final body = latest;
      if (body == null) return _json('', status: 404);
      return _json(jsonEncode(body));
    }
    return _json('[]');
  }

  http.StreamedResponse _json(String body, {int status = 200}) => http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        status,
        headers: const {'content-type': 'application/json'},
      );
}
