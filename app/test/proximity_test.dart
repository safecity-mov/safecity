import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/proximity.dart';

/// Un danger place de la Bastille, et des points à distance connue.
const _hazardLat = 48.8532;
const _hazardLng = 2.3692;

/// 1° de latitude ≈ 111 320 m : de quoi fabriquer une distance exacte vers le nord.
double _northOf(double metres) => _hazardLat + metres / 111320.0;

void main() {
  group('distanceM', () {
    test('mesure une distance connue à quelques mètres près', () {
      // Paris–Lyon à vol d'oiseau, 392 km. La formule doit tomber dessus.
      final d = ProximityRules.distanceM(48.8566, 2.3522, 45.7640, 4.8357);
      expect(d / 1000, closeTo(392, 3));
    });

    test('rend zéro sur le même point', () {
      expect(ProximityRules.distanceM(48.8532, 2.3692, 48.8532, 2.3692), closeTo(0, 0.001));
    });

    test('tient à quelques centimètres sur la distance de la règle', () {
      // C'est là que ça compte : la règle départage 100 m.
      expect(
        ProximityRules.distanceM(_hazardLat, _hazardLng, _northOf(100), _hazardLng),
        closeTo(100, 0.5),
      );
    });
  });

  group('tierFor', () {
    const regle = ProximityRules.fallback;

    test('sur place, palier 1', () {
      expect(
        regle.tierFor(
          hazardLat: _hazardLat,
          hazardLng: _hazardLng,
          deviceLat: _northOf(10),
          deviceLng: _hazardLng,
        ),
        1,
      );
    });

    test('au feu suivant, encore sur place', () {
      expect(
        regle.tierFor(
          hazardLat: _hazardLat,
          hazardLng: _hazardLng,
          deviceLat: _northOf(80),
          deviceLng: _hazardLng,
        ),
        1,
      );
    });

    test('ailleurs, palier 2', () {
      expect(
        regle.tierFor(
          hazardLat: _hazardLat,
          hazardLng: _hazardLng,
          deviceLat: _northOf(200),
          deviceLng: _hazardLng,
        ),
        2,
      );
      expect(
        regle.tierFor(
          hazardLat: _hazardLat,
          hazardLng: _hazardLng,
          deviceLat: _northOf(2000),
          deviceLng: _hazardLng,
        ),
        2,
        reason: 'il n\'y a plus de palier intermédiaire : 200 m ou 2 km, c\'est ailleurs',
      );
    });

    test('sans position, le palier le moins favorable', () {
      // Ce n'est pas un échec : c'est un geste qui compte moins (§6.2). Refuser
      // le geste priverait la carte d'un signalement juste.
      expect(regle.tierFor(hazardLat: _hazardLat, hazardLng: _hazardLng), 2);
      expect(
        regle.tierFor(hazardLat: _hazardLat, hazardLng: _hazardLng, deviceLat: 48.85),
        2,
      );
    });

    test('la borne est inclusive', () {
      // 100 m exactement appartient au premier palier, comme ST_DWithin côté serveur.
      expect(
        regle.tierFor(
          hazardLat: _hazardLat,
          hazardLng: _hazardLng,
          deviceLat: _northOf(99.5),
          deviceLng: _hazardLng,
        ),
        1,
      );
    });

    test('la règle compilée est celle de la migration', () {
      expect(regle.tiers.map((t) => t.maxDistanceM), [100, null]);
      expect(regle.tiers.map((t) => t.weight), [1, closeTo(1 / 3, 1e-9)]);
    });
  });

  group('la règle vient du serveur', () {
    test('une règle publiée remplace celle qui est compilée', () {
      // Sans cela, deux versions de l'app installées en même temps pondéreraient
      // différemment le même geste.
      final serveur = ProximityRules.fromJson([
        {'tier': 1, 'max_distance_m': 20, 'weight': 1.0},
        {'tier': 2, 'max_distance_m': null, 'weight': 0.5},
      ]);

      final aTrenteMetres = serveur.tierFor(
        hazardLat: _hazardLat,
        hazardLng: _hazardLng,
        deviceLat: _northOf(30),
        deviceLng: _hazardLng,
      );

      expect(aTrenteMetres, 2, reason: 'le seuil resserré à 20 m doit s\'appliquer');
      expect(
        ProximityRules.fallback.tierFor(
          hazardLat: _hazardLat,
          hazardLng: _hazardLng,
          deviceLat: _northOf(30),
          deviceLng: _hazardLng,
        ),
        1,
        reason: 'là où la règle compilée dirait encore palier 1',
      );
    });

    test('« ailleurs » est le dernier palier publié, quel que soit son numéro', () {
      // Une règle à trois paliers — un serveur d'avant 0200 — envoie 3 pour « loin »,
      // pas la constante de l'app : c'est le serveur qui nomme ses paliers.
      final ancienne = ProximityRules.fromJson([
        {'tier': 1, 'max_distance_m': 50, 'weight': 1.0},
        {'tier': 2, 'max_distance_m': 500, 'weight': 0.5},
        {'tier': 3, 'max_distance_m': null, 'weight': 0.25},
      ]);

      expect(
        ancienne.tierFor(
          hazardLat: _hazardLat,
          hazardLng: _hazardLng,
          deviceLat: _northOf(2000),
          deviceLng: _hazardLng,
        ),
        3,
      );
      expect(ancienne.tierFor(hazardLat: _hazardLat, hazardLng: _hazardLng), 3);
    });

    test('les paliers sont remis dans l\'ordre, quel que soit celui du serveur', () {
      final desordre = ProximityRules.fromJson([
        {'tier': 2, 'max_distance_m': null, 'weight': 0.25},
        {'tier': 1, 'max_distance_m': 100, 'weight': 1.0},
      ]);

      expect(desordre.tiers.map((t) => t.tier), [1, 2]);
      expect(
        desordre.tierFor(
          hazardLat: _hazardLat,
          hazardLng: _hazardLng,
          deviceLat: _northOf(10),
          deviceLng: _hazardLng,
        ),
        1,
      );
    });

    test('une règle vide ne remplace rien', () {
      // Tout serait tombé au palier le plus faible sans que personne ne s'en aperçoive.
      expect(ProximityRules.fromJson(const []).tiers.length, 2);
    });
  });
}
