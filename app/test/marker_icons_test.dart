import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/models/hazard.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/data/models/severity.dart';
import 'package:app/src/ui/marker_icons.dart';

void main() {
  group('hazardsToGeoJson', () {
    test('produit une FeatureCollection lisible par MapLibre', () {
      final geojson = hazardsToGeoJson([_hazard()]);

      expect(geojson['type'], 'FeatureCollection');
      final features = geojson['features'] as List;
      expect(features, hasLength(1));
      expect(
        (features.first as Map)['geometry'],
        {
          'type': 'Point',
          'coordinates': [2.3522, 48.8566],
        },
      );
    });

    test('n\'arrondit pas la position en passant par la carte', () {
      // §11.6 : aucune dégradation, ni au stockage ni à la restitution. Le
      // marqueur doit tomber là où le danger est.
      final geojson = hazardsToGeoJson([_hazard(lat: 48.85661234567, lng: 2.35223456789)]);
      final coords =
          ((geojson['features'] as List).first as Map)['geometry']['coordinates'] as List;

      expect(coords[0], 2.35223456789);
      expect(coords[1], 48.85661234567);
    });

    test('rend une carte vide sans cas particulier', () {
      // La carte démarre vide (§4.4).
      expect((hazardsToGeoJson(const [])['features'] as List), isEmpty);
    });

    test('ne met dans les propriétés que ce que la carte doit afficher', () {
      // Surtout pas le détail complet : le style n'a besoin que de l'icône, et
      // du même coup rien de sensible ne traîne dans la source (§11).
      final props = ((hazardsToGeoJson([_hazard()])['features'] as List).first
          as Map)['properties'] as Map;

      expect(props.keys.toSet(), {'id', 'icon'});
    });
  });

  group('MarkerIcons.nameFor', () {
    test('distingue les trois gravités', () {
      final names = Severity.values
          .map((s) => MarkerIcons.nameFor(typeCode: 'pothole', severity: s, disputed: false))
          .toSet();

      expect(names, hasLength(3));
    });

    test('distingue un danger contesté d\'un danger actif', () {
      // §6.1 : `disputed` reste visible, mais doit se voir comme tel.
      expect(
        MarkerIcons.nameFor(
          typeCode: 'pothole',
          severity: Severity.dangerous,
          disputed: true,
        ),
        isNot(
          MarkerIcons.nameFor(
            typeCode: 'pothole',
            severity: Severity.dangerous,
            disputed: false,
          ),
        ),
      );
    });

    test('distingue les types entre eux', () {
      expect(
        MarkerIcons.nameFor(
          typeCode: 'pothole',
          severity: Severity.dangerous,
          disputed: false,
        ),
        isNot(
          MarkerIcons.nameFor(
            typeCode: 'debris',
            severity: Severity.dangerous,
            disputed: false,
          ),
        ),
      );
    });

    test('nomme l\'image d\'un danger tel que la source GeoJSON la référence', () {
      // Si ces deux-là divergent, le marqueur disparaît sans erreur.
      final hazard = _hazard(status: 'disputed');
      final fromSource =
          ((hazardsToGeoJson([hazard])['features'] as List).first as Map)['properties']['icon'];

      expect(
        fromSource,
        MarkerIcons.nameFor(
          typeCode: hazard.type,
          severity: hazard.severity,
          disputed: true,
        ),
      );
    });
  });

  group('HazardType.icon', () {
    test('donne une icône à chaque type du catalogue', () {
      final icons = <String>[
        'pothole',
        'slippery',
        'manhole',
        'debris',
        'curb',
        'works',
        'lighting',
      ].map((code) => _type(code).icon).toSet();

      expect(icons, hasLength(7));
    });

    test('retombe sur une icône générique pour un type ajouté côté serveur', () {
      // Ajouter un type est une ligne en base (§3) : une app déjà installée doit
      // l'afficher, pas planter.
      expect(_type('quelque_chose_de_neuf').icon, isNotNull);
    });
  });
}

Hazard _hazard({double lat = 48.8566, double lng = 2.3522, String status = 'active'}) =>
    Hazard.fromJson({
      'id': '11111111-1111-1111-1111-111111111111',
      'type': 'pothole',
      'lat': lat,
      'lng': lng,
      'severity': 2,
      'status': status,
      'description': 'Trou profond',
      'address': null,
      'created_at': '2026-09-13T22:00:00+00:00',
      'last_confirmed_at': '2026-09-13T22:30:00+00:00',
      'resolve_weight': 1.0,
      'resolve_threshold': 2,
      'reported_remotely': false,
    });

HazardType _type(String code) => HazardType(
      code: code,
      label: code,
      iconName: code,
      resolvedLabel: 'Réparé',
      dedupRadiusM: 15,
      enabled: true,
      sortOrder: 10,
    );
