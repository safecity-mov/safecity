import 'dart:math' as math;

/// Un palier de proximité, tel que le serveur le publie (§6.2).
class ProximityTier {
  const ProximityTier({required this.tier, required this.maxDistanceM, required this.weight});

  final int tier;

  /// `null` sur le dernier palier : « au-delà », ou pas de position du tout.
  final int? maxDistanceM;

  final double weight;

  factory ProximityTier.fromJson(Map<String, dynamic> json) => ProximityTier(
        tier: json['tier'] as int,
        maxDistanceM: json['max_distance_m'] as int?,
        weight: (json['weight'] as num).toDouble(),
      );
}

/// Le palier de proximité d'un geste, calculé **sur l'appareil**.
///
/// Le serveur recevait naguère la coordonnée du déclarant, en déduisait le palier et la jetait.
/// Elle n'était jamais écrite, mais elle traversait le réseau : la promesse tenait à ce
/// qu'aucun journal ne l'attrape en chemin. Depuis que le calcul se fait ici, **la position ne
/// quitte jamais le téléphone** (§11.1).
///
/// Ce n'est pas une concession sur la triche : c'était déjà le client qui fournissait la
/// coordonnée. Envoyer celle du danger donnait le poids maximal depuis n'importe où, exactement
/// comme déclarer « palier 1 ». Le serveur n'a rien perdu qu'il avait.
///
/// La règle, elle, reste publiée par le serveur : sans cela, deux versions de l'app installées
/// en même temps pondéreraient différemment.
class ProximityRules {
  const ProximityRules(this.tiers);

  final List<ProximityTier> tiers;

  /// Le palier le moins favorable quand aucune règle n'est connue : « ailleurs ».
  /// Sous-pondérer un geste honnête est moins grave que sur-pondérer une déclaration vide.
  static const farthest = 2;

  /// Ce qui s'applique tant que le serveur n'a rien dit — premier lancement, hors ligne.
  /// Identique à ce que la migration installe (0200) ; un écart se verrait au prochain
  /// lancement en ligne, pas plus tard. Deux paliers : « sur place » jusqu'à 100 m, poids 1 ;
  /// « ailleurs, ou sans position », poids un tiers — trois gestes d'ailleurs valent un
  /// geste sur place (§6.2 amendé).
  static const fallback = ProximityRules([
    ProximityTier(tier: 1, maxDistanceM: 100, weight: 1),
    ProximityTier(tier: 2, maxDistanceM: null, weight: 1 / 3),
  ]);

  factory ProximityRules.fromJson(List<dynamic> rows) {
    final tiers = [
      for (final row in rows.cast<Map<String, dynamic>>()) ProximityTier.fromJson(row),
    ]..sort((a, b) => a.tier.compareTo(b.tier));
    // Une liste vide viderait la règle de son sens et ferait tout tomber au palier le plus
    // faible sans qu'on s'en aperçoive.
    return tiers.isEmpty ? fallback : ProximityRules(tiers);
  }

  /// Le dernier palier de la règle, celui sans limite : « ailleurs », ou pas de position.
  int get _last => tiers.isEmpty ? farthest : tiers.last.tier;

  /// Le palier d'un geste fait depuis [deviceLat] / [deviceLng] sur un danger donné.
  int tierFor({
    required double hazardLat,
    required double hazardLng,
    double? deviceLat,
    double? deviceLng,
  }) {
    if (deviceLat == null || deviceLng == null) return _last;

    final distance = distanceM(hazardLat, hazardLng, deviceLat, deviceLng);
    for (final tier in tiers) {
      if (tier.maxDistanceM != null && distance <= tier.maxDistanceM!) return tier.tier;
    }
    return _last;
  }

  /// Distance en mètres entre deux points, par la formule de haversine.
  ///
  /// Le rayon terrestre moyen suffit : la règle départage 100 m, où l'écart entre sphère et
  /// ellipsoïde se compte en centimètres.
  static double distanceM(double lat1, double lng1, double lat2, double lng2) {
    const rayonM = 6371008.8;
    const versRadians = math.pi / 180;

    final dLat = (lat2 - lat1) * versRadians;
    final dLng = (lng2 - lng1) * versRadians;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * versRadians) *
            math.cos(lat2 * versRadians) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * rayonM * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
