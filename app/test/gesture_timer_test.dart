import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/ui/gesture_timer.dart';

void main() {
  group('GestureTimer', () {
    test('ne relève rien tant qu\'aucun geste n\'a commencé', () {
      // Un signalement arrivé par un chemin non instrumenté ne doit pas hériter
      // du chronomètre d'un autre : mieux vaut ne rien mesurer.
      expect(GestureTimer().take(), isNull);
    });

    test('mesure le geste commencé', () {
      final timer = GestureTimer()..start();
      expect(timer.running, isTrue);
      expect(timer.take(), isNotNull);
    });

    test('ne se relève qu\'une fois', () {
      // Deux relevés du même geste compteraient deux signalements pour un.
      final timer = GestureTimer()..start();
      expect(timer.take(), isNotNull);
      expect(timer.take(), isNull);
    });

    test('un placement annulé ne laisse rien tourner', () {
      // C'est le défaut que la mesure du §4.6 avait : annuler un placement, rouler
      // dix minutes, puis signaler enregistrait six cents secondes pour un geste
      // qui en avait pris quinze.
      final timer = GestureTimer()..start();
      timer.cancel();

      expect(timer.running, isFalse);
      expect(timer.take(), isNull);
    });

    test('repasser en placement repart de zéro', () async {
      // Entrer deux fois en mode placement, c'est recommencer, pas continuer.
      final timer = GestureTimer()..start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      timer.start();

      final elapsed = timer.take()!;
      expect(elapsed, lessThan(const Duration(milliseconds: 30)));
    });
  });
}
