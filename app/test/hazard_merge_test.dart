import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/models/hazard.dart';
import 'package:app/src/data/models/severity.dart';
import 'package:app/src/ui/hazard_merge.dart';

void main() {
  const paris = (minLat: 48.8, minLng: 2.3, maxLat: 48.9, maxLng: 2.4);

  group('mergeHazards', () {
    test('oublie ce que le serveur ne renvoie plus dans la zone', () {
      // Retiré par la console, ou résolu par d'autres : il ne doit pas rester
      // affiché « actif » toute la session (AUDIT C5).
      final current = {'a': _hazard('a'), 'b': _hazard('b')};

      final merged = mergeHazards(
        current: current,
        fetched: [_hazard('a')],
        bbox: paris,
        authoritative: true,
      );

      expect(merged.keys, ['a']);
    });

    test('garde ce qui est hors de la zone chargée', () {
      // Une réponse ne parle que de sa zone : un danger vu ailleurs n'est pas
      // démenti par elle.
      final current = {'loin': _hazard('loin', lat: 45.76, lng: 4.83)};

      final merged = mergeHazards(
        current: current,
        fetched: const [],
        bbox: paris,
        authoritative: true,
      );

      expect(merged.keys, ['loin']);
    });

    test('ne retire rien quand la réponse vient du cache', () {
      // Le cache ne fait pas foi : il peut ignorer un danger que la carte a
      // reçu il y a une minute d'un geste appliqué.
      final current = {'a': _hazard('a'), 'b': _hazard('b')};

      final merged = mergeHazards(
        current: current,
        fetched: [_hazard('a')],
        bbox: paris,
        authoritative: false,
      );

      expect(merged.keys, containsAll(['a', 'b']));
    });

    test('élague le provisoire une fois son vrai identifiant arrivé', () {
      // Le signalement fait hors ligne est affiché sous son `client_id`. Une
      // fois envoyé, le dépôt ne l'ajoute plus à la réponse, et le serveur le
      // renvoie sous le sien : sans élagage, deux marqueurs, dont un fantôme.
      final current = {'client-1': _hazard('client-1')};

      final merged = mergeHazards(
        current: current,
        fetched: [_hazard('serveur-9')],
        bbox: paris,
        authoritative: true,
      );

      expect(merged.keys, ['serveur-9']);
    });

    test('garde le provisoire tant que le dépôt le renvoie', () {
      // Avant l'envoi, le dépôt ajoute lui-même les provisoires à ce qu'il rend :
      // ils font partie de la réponse et survivent à l'élagage.
      final merged = mergeHazards(
        current: {'client-1': _hazard('client-1')},
        fetched: [_hazard('client-1'), _hazard('a')],
        bbox: paris,
        authoritative: true,
      );

      expect(merged.keys, containsAll(['client-1', 'a']));
    });

    test('rend l\'état le plus frais pour ce qui est dans les deux', () {
      final merged = mergeHazards(
        current: {'a': _hazard('a', resolveWeight: 0)},
        fetched: [_hazard('a', resolveWeight: 1)],
        bbox: paris,
        authoritative: true,
      );

      expect(merged['a']!.resolveWeight, 1);
    });
  });
}

Hazard _hazard(String id, {double lat = 48.85, double lng = 2.35, double resolveWeight = 0}) =>
    Hazard(
      id: id,
      type: 'pothole',
      lat: lat,
      lng: lng,
      severity: Severity.fromValue(2),
      status: HazardStatus.active,
      createdAt: DateTime(2026, 9, 13),
      lastConfirmedAt: DateTime(2026, 9, 13),
      confirmWeight: 3,
      resolveWeight: resolveWeight,
      resolveThreshold: 2,
      reportedRemotely: false,
    );
