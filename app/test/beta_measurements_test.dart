import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/beta_measurements.dart';
import 'package:app/src/data/local/database.dart';

void main() {
  late AppDatabase db;
  late BetaMeasurements m;

  setUp(() {
    db = AppDatabase.memory();
    m = BetaMeasurements(db);
  });

  tearDown(() => db.close());

  group('BetaMeasurements', () {
    test('agrège compte, moyenne, minimum et maximum', () async {
      await m.record(BetaMeasurements.gesture, duration: const Duration(seconds: 8));
      await m.record(BetaMeasurements.gesture, duration: const Duration(seconds: 12));
      await m.record(BetaMeasurements.gesture, duration: const Duration(seconds: 4));

      final row = (await m.all()).single;
      expect(row.count, 3);
      expect(row.totalMs, 24000);
      expect(row.minMs, 4000);
      expect(row.maxMs, 12000);
    });

    test('compte aussi ce qui n\'a pas de durée', () async {
      await m.record(BetaMeasurements.duplicateRefused);
      await m.record(BetaMeasurements.duplicateRefused);

      final row = (await m.all()).single;
      expect(row.count, 2);
      expect(row.totalMs, 0);
      expect(row.minMs, isNull);
    });

    test('le rapport répond à la question des quinze secondes', () async {
      await m.record(BetaMeasurements.gesture, duration: const Duration(seconds: 9));
      await m.record(BetaMeasurements.gesture, duration: const Duration(seconds: 21));
      await m.record(BetaMeasurements.sent);

      final report = await m.report(deviceModel: 'Google Pixel 9');
      expect(report, contains('Google Pixel 9'));
      expect(report, contains('${BetaMeasurements.labels[BetaMeasurements.gesture]} : 2 fois'));
      expect(report, contains('moyenne 15.0s'));
      expect(report, contains('max 21.0s'));
      expect(report, contains('Signalements envoyés : 1'));
    });

    test('ne contient ni position, ni horodatage, ni identifiant', () async {
      // Le garde-fou qui compte : la table n'a que quatre colonnes de chiffres,
      // et rien ne peut y glisser un lieu ou une heure (§11.1, §11.7).
      await m.record(BetaMeasurements.gesture, duration: const Duration(seconds: 3));
      final row = (await m.all()).single;
      expect(
        row.toJson().keys.toSet(),
        {'key', 'count', 'totalMs', 'minMs', 'maxMs'},
      );
    });

    test('un rapport vide le dit plutôt que de mentir par omission', () async {
      expect(await m.report(), contains('Aucune mesure'));
    });

    test('remettre à zéro efface tout', () async {
      await m.record(BetaMeasurements.sent);
      await m.clear();
      expect(await m.all(), isEmpty);
    });

    test('chaque indicateur suivi a un libellé lisible', () async {
      // Une mesure sans libellé s'afficherait en « signalement.geste » dans le
      // rapport que le testeur nous envoie.
      for (final key in [
        BetaMeasurements.gesture,
        BetaMeasurements.sheet,
        BetaMeasurements.sent,
        BetaMeasurements.queued,
        BetaMeasurements.duplicateProposed,
        BetaMeasurements.duplicateAccepted,
        BetaMeasurements.duplicateRefused,
        BetaMeasurements.queueSent,
        BetaMeasurements.queueRefused,
        BetaMeasurements.withoutPosition,
        BetaMeasurements.permissionDenied,
      ]) {
        expect(BetaMeasurements.labels, contains(key));
      }
    });
  });
}
