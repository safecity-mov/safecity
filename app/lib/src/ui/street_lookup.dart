import 'dart:math' as math;
import 'dart:ui';

import 'package:maplibre_gl/maplibre_gl.dart';

/// Le nom de la voie sous un point, lu dans le fond de carte déjà embarqué.
///
/// Ce n'est **pas** du géocodage inverse. Le §7 prévoit Photon auto-hébergé, qui
/// n'est pas en service — et qui recevrait de toute façon la coordonnée de
/// chaque danger consulté, soit exactement le genre de trace que le §11.5
/// cherche à éviter, fût-ce vers notre propre serveur.
///
/// Ici, rien ne sort de l'appareil : la réponse vient des tuiles vectorielles
/// que la carte affiche déjà, qui portent `name` sur leurs voies. Conséquences
/// assumées :
///
/// - c'est un **nom de voie**, pas une adresse postale : jamais de numéro ;
/// - il faut que la carte soit chargée à cet endroit, donc zoomée (le style ne
///   trace les voies mineures qu'à partir du zoom 12) ;
/// - hors ligne, cela marche sur les zones embarquées, et pas ailleurs.
///
/// Quand la réponse manque, l'appelant montre la coordonnée : une ligne fausse
/// serait pire qu'une ligne technique.
class StreetLookup {
  const StreetLookup._();

  /// Les couches de voirie du style. Elles partagent la source-layer `roads`,
  /// dont les entités portent `name`.
  static const layers = ['roads-minor', 'roads-medium', 'roads-major'];

  /// Deux passes : au plus près d'abord, puis un filet plus large. Sans la
  /// seconde, un danger posé sur un trottoir ne trouverait rien.
  static const radiiPx = <double>[28, 80];

  /// Au-delà, on préfère se taire. Nommer une rue à 80 m du danger induirait en
  /// erreur quelqu'un qui cherche un trou à vélo.
  static const maxDistanceM = 60.0;

  /// Interroge la carte sur un rectangle d'écran. Isolé pour que la sélection
  /// de la voie soit testable sans appareil.
  static Future<String?> nearest({
    required Future<List<dynamic>> Function(Rect rect, List<String> layerIds) query,
    required Offset screen,
    required LatLng position,
  }) async {
    for (final radius in radiiPx) {
      final rect = Rect.fromCenter(
        center: screen,
        width: radius * 2,
        height: radius * 2,
      );

      List<dynamic> features;
      try {
        features = await query(rect, layers);
      } on Exception {
        return null;
      }

      String? meilleur;
      var meilleure = double.infinity;
      for (final feature in features) {
        final nom = _name(feature);
        if (nom == null) continue;
        final distance = _distanceTo(feature, position);
        if (distance < meilleure) {
          meilleure = distance;
          meilleur = nom;
        }
      }
      if (meilleur != null && meilleure <= maxDistanceM) return meilleur;
    }
    return null;
  }

  static String? _name(dynamic feature) {
    if (feature is! Map) return null;
    final properties = feature['properties'];
    if (properties is! Map) return null;
    final nom = properties['name'];
    if (nom is! String) return null;
    final propre = nom.trim();
    return propre.isEmpty ? null : propre;
  }

  /// Distance en mètres du point à la géométrie de l'entité.
  ///
  /// Approximation équirectangulaire : à l'échelle d'une rue, l'erreur est
  /// centimétrique, et elle évite de dépendre d'une bibliothèque géodésique
  /// pour départager deux voies distantes de quelques dizaines de mètres.
  static double _distanceTo(dynamic feature, LatLng point) {
    final geometry = (feature as Map)['geometry'];
    if (geometry is! Map) return double.infinity;

    final lignes = switch (geometry['type']) {
      'LineString' => [geometry['coordinates']],
      'MultiLineString' => geometry['coordinates'] as List,
      _ => const [],
    };

    // Un degré de longitude rétrécit avec la latitude ; sans ce facteur, deux
    // rues parallèles seraient départagées à l'envers sous nos latitudes.
    const metresParDegre = 111320.0;
    final cos = math.cos(point.latitude * math.pi / 180);

    var minimum = double.infinity;
    for (final ligne in lignes) {
      if (ligne is! List || ligne.length < 2) continue;
      for (var i = 0; i < ligne.length - 1; i++) {
        final a = ligne[i] as List;
        final b = ligne[i + 1] as List;
        final d = _pointSegment(
          ((point.longitude - (a[0] as num)) * cos) * metresParDegre,
          (point.latitude - (a[1] as num)) * metresParDegre,
          (((b[0] as num) - (a[0] as num)) * cos) * metresParDegre,
          ((b[1] as num) - (a[1] as num)) * metresParDegre,
        );
        if (d < minimum) minimum = d;
      }
    }
    return minimum;
  }

  /// Distance du point `(px, py)` au segment partant de l'origine, de vecteur
  /// `(vx, vy)`. Tout est déjà exprimé en mètres relatifs au point cherché.
  static double _pointSegment(double px, double py, double vx, double vy) {
    final carre = vx * vx + vy * vy;
    if (carre == 0) return math.sqrt(px * px + py * py);
    // `px, py` pointe du sommet A vers le point ; la projection le ramène sur
    // le segment, bornée à ses extrémités.
    final t = ((px * vx + py * vy) / carre).clamp(0.0, 1.0);
    final dx = px - t * vx;
    final dy = py - t * vy;
    return math.sqrt(dx * dx + dy * dy);
  }
}
