import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/hazard_repository.dart';
import 'package:app/src/data/trace_horizon.dart';

/// L'effacement lui-même est en Kotlin et n'est pas testable ici : ce qui l'est,
/// c'est que l'app le réclame, et que les deux côtés parlent du même horizon.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(TraceHorizon.channelName);
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return 3;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('TraceHorizon', () {
    test('demande la purge au natif et rend le compte', () async {
      expect(await TraceHorizon().sweep(), 3);
      expect(calls, ['sweep']);
    });

    test('ne fait pas tomber l\'app quand la plateforme refuse', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'sqlite');
      });
      expect(await TraceHorizon().sweep(), isNull);
    });

    test('le minuteur du premier plan passe avant l\'horizon', () {
      // Sans cela, une sortie à vélo d'une heure garderait sur le disque des
      // tuiles plus vieilles que ce qu'on promet.
      expect(TraceHorizon.interval, lessThan(TraceHorizon.maxAge));
    });

    test('le cache de dangers ne survit pas à l\'horizon', () {
      // Une zone chargée et ses dangers disent où l'appareil est passé : leur
      // durée de vie est celle des traces, pas celle du confort hors ligne.
      expect(HazardRepository.cacheTtl, TraceHorizon.maxAge);
    });

    test('le pire cas reste sous le plafond annoncé', () {
      // Le calcul qui autorise à écrire « au plus tard une heure et demie »
      // dans PRIVACY.md, plutôt que de l'espérer. Les deux termes venus du
      // natif sont en dur ici : si TraceSweeper change, ce test doit tomber.
      const alarmDelay = Duration(minutes: 20);
      const androidWindow = Duration(minutes: 15); // 75 % du délai, mesuré
      final pireCas =
          TraceHorizon.maxAge + TraceHorizon.interval + alarmDelay + androidWindow;

      expect(pireCas, lessThanOrEqualTo(TraceHorizon.guarantee));
      expect(TraceHorizon.guarantee, const Duration(minutes: 90));
    });
  });
}
