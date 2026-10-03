
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:app/src/ui/street_lookup.dart';

/// Un point de la place Léon Blum, et deux voies : celle sur laquelle il se
/// trouve, et un boulevard à une centaine de mètres.
const _point = LatLng(48.8570, 2.3800);

Map<String, dynamic> _voie(String nom, List<List<double>> points) => {
      'type': 'Feature',
      'properties': {'name': nom, 'kind': 'minor_road'},
      'geometry': {'type': 'LineString', 'coordinates': points},
    };

void main() {
  group('StreetLookup.nearest', () {
    test('retient la voie la plus proche, pas la première rendue', () async {
      // MapLibre ne rend aucun ordre utile : c'est à nous de départager. Sans
      // ce calcul, un danger dans une rue adjacente porterait le nom du
      // boulevard d'à côté.
      final nom = await StreetLookup.nearest(
        query: (_, __) async => [
          _voie('Boulevard Voltaire', [
            [2.3810, 48.8560],
            [2.3810, 48.8580],
          ]),
          _voie('Rue Antoine Vollon', [
            [2.3801, 48.8560],
            [2.3801, 48.8580],
          ]),
        ],
        screen: const Offset(200, 300),
        position: _point,
      );

      expect(nom, 'Rue Antoine Vollon');
    });

    test('ignore les voies sans nom', () async {
      final nom = await StreetLookup.nearest(
        query: (_, __) async => [
          {
            'type': 'Feature',
            'properties': <String, dynamic>{'kind': 'minor_road'},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [2.38001, 48.8560],
                [2.38001, 48.8580],
              ],
            },
          },
          _voie('Rue Antoine Vollon', [
            [2.3802, 48.8560],
            [2.3802, 48.8580],
          ]),
        ],
        screen: const Offset(200, 300),
        position: _point,
      );

      expect(nom, 'Rue Antoine Vollon');
    });

    test('se tait plutôt que de nommer une voie trop lointaine', () async {
      // Nommer une rue à 200 m tromperait quelqu'un qui cherche un trou à vélo.
      final nom = await StreetLookup.nearest(
        query: (_, __) async => [
          _voie('Avenue Ledru-Rollin', [
            [2.3830, 48.8560],
            [2.3830, 48.8580],
          ]),
        ],
        screen: const Offset(200, 300),
        position: _point,
      );

      expect(nom, isNull);
    });

    test('élargit la recherche quand la première passe ne trouve rien', () async {
      final rayons = <double>[];
      final nom = await StreetLookup.nearest(
        query: (rect, __) async {
          rayons.add(rect.width / 2);
          // Rien au plus près, la voie n'apparaît qu'au filet large.
          return rayons.length == 1
              ? const []
              : [
                  _voie('Rue Antoine Vollon', [
                    [2.3802, 48.8560],
                    [2.3802, 48.8580],
                  ]),
                ];
        },
        screen: const Offset(200, 300),
        position: _point,
      );

      expect(rayons, StreetLookup.radiiPx);
      expect(nom, 'Rue Antoine Vollon');
    });

    test('une carte qui refuse de répondre ne casse rien', () async {
      final nom = await StreetLookup.nearest(
        query: (_, __) async => throw Exception('carte pas prête'),
        screen: const Offset(200, 300),
        position: _point,
      );

      expect(nom, isNull);
    });

    test('n\'interroge que les couches de voirie', () async {
      late List<String> demandees;
      await StreetLookup.nearest(
        query: (_, layerIds) async {
          demandees = layerIds;
          return const [];
        },
        screen: const Offset(200, 300),
        position: _point,
      );

      expect(demandees, StreetLookup.layers);
    });
  });
}
