import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/models/hazard.dart';
import 'package:app/src/data/models/severity.dart';
import 'package:app/src/ui/labels.dart';

void main() {
  group('Hazard.fromJson', () {
    test('conserve la position à la précision où le serveur l\'envoie', () {
      // §11.6 : aucun arrondi, ni au stockage ni à la restitution. Un nid-de-poule
      // doit rester localisé à quelques mètres.
      final hazard = Hazard.fromJson(_json(lat: 48.85661234567, lng: 2.35223456789));

      expect(hazard.lat, 48.85661234567);
      expect(hazard.lng, 2.35223456789);
    });

    test('lit une FeatureCollection GeoJSON comme un objet RPC', () {
      final feature = {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [2.35223456789, 48.85661234567],
        },
        'properties': _json()
          ..remove('lat')
          ..remove('lng'),
      };

      final hazard = Hazard.fromFeature(feature);

      expect(hazard.lat, 48.85661234567);
      expect(hazard.lng, 2.35223456789);
      expect(hazard.type, 'pothole');
    });

    test('accepte un statut inconnu sans casser l\'écran', () {
      // Un statut ajouté côté serveur ne doit pas faire planter une app déjà
      // installée : le catalogue et le modèle évoluent sans release (§3).
      final hazard = Hazard.fromJson(_json(status: 'quelque_chose_de_neuf'));

      expect(hazard.status, HazardStatus.active);
    });

    test('considère un danger sans badge comme signalé sur place', () {
      final json = _json()..remove('reported_remotely');

      expect(Hazard.fromJson(json).reportedRemotely, isFalse);
    });
  });

  group('Severity', () {
    test('mappe les trois niveaux du produit', () {
      expect(Severity.fromValue(1), Severity.annoying);
      expect(Severity.fromValue(2), Severity.dangerous);
      expect(Severity.fromValue(3), Severity.veryDangerous);
    });

    test('retombe sur « dangereux » pour une valeur hors bornes', () {
      expect(Severity.fromValue(9), Severity.dangerous);
    });

    test('donne un diamètre croissant : le niveau est lisible sans la couleur', () {
      // §9, accessibilité : le type et le niveau doivent rester lisibles pour
      // quelqu'un qui ne distingue pas les couleurs.
      expect(Severity.annoying.markerRadius, lessThan(Severity.dangerous.markerRadius));
      expect(Severity.dangerous.markerRadius, lessThan(Severity.veryDangerous.markerRadius));
    });

    test('affiche chaque niveau par son chiffre, de 1 à 3', () {
      // Un simple indicateur, sans libellé (§4.1 amendé) : le chiffre est la
      // valeur envoyée au serveur, telle quelle.
      expect(Severity.values.map((s) => s.label), ['1', '2', '3']);
      expect(Severity.max, 3);
    });
  });

  group('HazardEvent', () {
    test('chaque type du journal a un libellé, un type inconnu s\'affiche tel quel', () {
      // Le mot lui-même vit dans labels.dart ; ce qui compte ici est qu'aucun
      // type connu ne retombe sur son identifiant technique.
      for (final type in ['create', 'confirm', 'mark_resolved', 'remove', 'restore', 'photo_add']) {
        expect(DetailLabels.event(type), isNot(type));
      }
      expect(DetailLabels.event('type_futur'), 'type_futur');
    });

    test('n\'expose aucun identifiant de terminal', () {
      // §11 : la chronologie d'un danger est publique, le lien entre un device
      // et ses actions ne l'est pas. Le serveur ne l'envoie pas, le modèle n'a
      // nulle part où le mettre.
      final event = HazardEvent.fromJson({
        'type': 'confirm',
        'created_at': '2026-09-13T22:00:00+00:00',
        'proximity': 2,
        'device_id': 'ne-devrait-jamais-arriver',
      });

      expect(event.toString(), isNot(contains('ne-devrait-jamais-arriver')));
      expect(
        HazardEvent.fromJson({
          'type': 'confirm',
          'created_at': '2026-09-13T22:00:00+00:00',
        }).proximity,
        isNull,
      );
    });
  });
}

Map<String, dynamic> _json({
  double lat = 48.8566,
  double lng = 2.3522,
  String status = 'active',
  int severity = 2,
}) =>
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'type': 'pothole',
      'lat': lat,
      'lng': lng,
      'severity': severity,
      'status': status,
      'description': null,
      'address': null,
      'created_at': '2026-09-13T22:00:00+00:00',
      'last_confirmed_at': '2026-09-13T22:30:00+00:00',
      'resolve_weight': 0.5,
      'resolve_threshold': 2,
      'reported_remotely': false,
    };
