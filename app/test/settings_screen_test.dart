import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/src/config.dart';
import 'package:app/src/data/api_client.dart';
import 'package:app/src/data/device_identity.dart';
import 'package:app/src/data/hazard_repository.dart';
import 'package:app/src/data/local/database.dart';
import 'package:app/src/location/location_service.dart';
import 'package:app/src/ui/settings_screen.dart';
import 'package:app/src/ui/labels.dart';

void main() {
  late AppDatabase db;
  late _Server server;
  late HazardRepository repo;
  late DeviceIdentity device;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() {
    db = AppDatabase.memory();
    server = _Server();
    device = DeviceIdentity();
    repo = HazardRepository(
      api: ApiClient(httpClient: server, baseUrl: 'http://test/rest/v1'),
      db: db,
      device: device,
    );
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(repo: repo, device: device, location: LocationService()),
    ),);
    await tester.pump();
  }

  group('SettingsScreen', () {
    testWidgets('annonce la version et les trois licences', (tester) async {
      await open(tester);
      // « À propos » est en bas de liste : une ListView ne construit pas ce qui
      // est hors écran, il faut y aller pour le voir.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.textContaining(AppConfig.version), findsOneWidget);
      // L'attribution OpenStreetMap n'est pas une politesse : l'ODbL l'impose,
      // et c'est le seul endroit de l'app où elle peut vivre (§12).
      expect(find.text(SettingsLabels.basemapBody), findsOneWidget);
      expect(find.text(SettingsLabels.licencesBody), findsOneWidget);
    });

    testWidgets('ne fait rien sans confirmation explicite', (tester) async {
      await open(tester);
      await tester.tap(find.text(SettingsLabels.forget));
      await tester.pumpAndSettle();

      // Le dialogue dit ce qui est perdu, pas seulement ce qui est effacé.
      expect(find.text(SettingsLabels.forgetConfirmBody), findsOneWidget);
      expect(find.text(SettingsLabels.dataNotice), findsOneWidget);

      await tester.tap(find.text(SettingsLabels.cancel));
      await tester.pumpAndSettle();
      expect(server.forgotten, isEmpty);
    });

    testWidgets('efface côté serveur, change d\'identifiant, et rend compte',
        (tester) async {
      final before = await device.id;
      await open(tester);
      await tester.tap(find.text(SettingsLabels.forget));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsLabels.forgetConfirmAction));
      await tester.pumpAndSettle();

      // Les deux bouts du lien, en un geste (§11.4 amendé) : le serveur a
      // reçu l'ancien numéro, et le téléphone n'a plus le même.
      expect(server.forgotten, [before]);
      expect(await device.id, isNot(before));
      // Et le numéro neuf est déclaré aussitôt : son quart d'heure avant
      // « Plus là » part d'ici (0250).
      expect(server.declared, [await device.id]);
      expect(find.text(SettingsLabels.detached(3)), findsOneWidget);
    });

    testWidgets('serveur injoignable : le téléphone change quand même de numéro, et le dit',
        (tester) async {
      server.offline = true;
      final before = await device.id;
      await open(tester);
      await tester.tap(find.text(SettingsLabels.forget));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsLabels.forgetConfirmAction));
      await tester.pumpAndSettle();

      // La partie locale ne dépend de personne. Le pire message serait
      // « le serveur a oublié » alors qu'il n'a rien reçu : on dit ce qui
      // s'est passé, et ce qui reste à attendre.
      expect(await device.id, isNot(before));
      expect(server.forgotten, isEmpty);
      expect(find.text(SettingsLabels.forgottenLocallyOnly), findsOneWidget);
    });

    testWidgets('retirer mes signalements récents demande confirmation, puis dit combien',
        (tester) async {
      await open(tester);
      await tester.tap(find.text(SettingsLabels.removeRecent));
      await tester.pumpAndSettle();
      expect(find.text(SettingsLabels.removeRecentConfirmBody), findsOneWidget);

      await tester.tap(find.text(SettingsLabels.cancel));
      await tester.pumpAndSettle();
      expect(server.removedFor, isEmpty);

      await tester.tap(find.text(SettingsLabels.removeRecent));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsLabels.removeRecentConfirmAction));
      await tester.pumpAndSettle();

      expect(server.removedFor, [await device.id]);
      expect(find.text(SettingsLabels.removedRecent(2)), findsOneWidget);
      // Retirer ne coupe pas le lien : l'identifiant reste le même.
      expect(server.forgotten, isEmpty);
    });

    testWidgets('retirer sans rien à retirer le dit, et injoignable ne ment pas',
        (tester) async {
      server.removed = 0;
      await open(tester);
      await tester.tap(find.text(SettingsLabels.removeRecent));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsLabels.removeRecentConfirmAction));
      await tester.pumpAndSettle();
      expect(find.text(SettingsLabels.nothingToRemove), findsOneWidget);

      server.offline = true;
      await tester.tap(find.text(SettingsLabels.removeRecent));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsLabels.removeRecentConfirmAction));
      await tester.pumpAndSettle();
      expect(find.text(SettingsLabels.removeRecentUnreachable), findsOneWidget);
    });
  });
}

class _Server extends http.BaseClient {
  final forgotten = <String>[];
  final removedFor = <String>[];
  /// Identifiants déclarés au serveur (0250) : le neuf, après « Effacer mes données ».
  final declared = <String>[];
  bool offline = false;

  /// Ce que le serveur répond à « retirer mes signalements récents ».
  int removed = 2;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw const SocketExceptionStub();
    final body = jsonDecode(await (request as http.Request).finalize().bytesToString())
        as Map<String, dynamic>;
    if (request.url.path.endsWith('declare_device')) {
      declared.add(body['device_id'] as String);
      return http.StreamedResponse(Stream.value(utf8.encode('{"since":"2026-10-04T10:00:00Z"}')), 200);
    }
    if (request.url.path.endsWith('remove_own_recent_hazards')) {
      removedFor.add(body['device_id'] as String);
      return http.StreamedResponse(Stream.value(utf8.encode('{"removed":$removed}')), 200);
    }
    forgotten.add(body['device_id'] as String);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"events_anonymized":3,"hazards_anonymized":1}')),
      200,
    );
  }
}

/// `SocketException` demande `dart:io`, que les tests de widget évitent : ce
/// que le dépôt regarde, c'est le type de la panne, pas son origine.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
