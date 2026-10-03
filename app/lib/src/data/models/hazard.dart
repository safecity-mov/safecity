import 'severity.dart';

enum HazardStatus {
  active,
  disputed,
  resolved,
  removed,
  archived;

  static HazardStatus parse(String raw) =>
      HazardStatus.values.firstWhere((s) => s.name == raw, orElse: () => HazardStatus.active);

  /// « Signalé résolu » : grisé, toujours visible, en attente d'un quorum (§6.1).
  bool get isDisputed => this == HazardStatus.disputed;
}

/// Un danger, tel que le serveur le renvoie.
///
/// Les poids (`confirmWeight`, `resolveWeight`, `resolveThreshold`) sont
/// calculés par le serveur à partir du journal d'événements : le client ne les
/// recalcule jamais et ne les devine pas. Il déclare, le serveur décide (§8).
class Hazard {
  const Hazard({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.severity,
    required this.status,
    required this.createdAt,
    required this.lastConfirmedAt,
    required this.confirmWeight,
    required this.resolveWeight,
    required this.resolveThreshold,
    required this.reportedRemotely,
    this.description,
    this.address,
  });

  final String id;
  final String type;
  final double lat;
  final double lng;
  final Severity severity;
  final HazardStatus status;
  final DateTime createdAt;
  final DateTime lastConfirmedAt;

  /// Ce qui dit « toujours là » : le signalement, qui vaut plusieurs
  /// confirmations, plus chaque « toujours là », chacun pesé par sa proximité
  /// (§6.1, §6.2). C'est lui qui fixe [resolveThreshold].
  final double confirmWeight;

  /// Ce qui dit « plus là », à la même échelle. Le danger quitte la carte quand
  /// il atteint [resolveThreshold].
  final double resolveWeight;
  final int resolveThreshold;

  /// Badge « signalé à distance » : le signalement a été créé hors du palier
  /// « sur place », ou sans position (§6.2).
  final bool reportedRemotely;

  final String? description;
  final String? address;

  factory Hazard.fromJson(Map<String, dynamic> json) => Hazard(
        id: json['id'] as String,
        type: json['type'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        severity: Severity.fromValue(json['severity'] as int),
        status: HazardStatus.parse(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        lastConfirmedAt: DateTime.parse(json['last_confirmed_at'] as String).toLocal(),
        // Zéro par défaut : un serveur antérieur à l'amendement du §6.1 ne
        // publie pas ce poids, et la balance vaut mieux vide que fausse.
        confirmWeight: (json['confirm_weight'] as num?)?.toDouble() ?? 0,
        resolveWeight: (json['resolve_weight'] as num).toDouble(),
        resolveThreshold: json['resolve_threshold'] as int,
        reportedRemotely: json['reported_remotely'] as bool? ?? false,
        description: json['description'] as String?,
        address: json['address'] as String?,
      );

  /// Une entrée de la FeatureCollection GeoJSON : la géométrie porte la position,
  /// les propriétés portent le reste.
  factory Hazard.fromFeature(Map<String, dynamic> feature) {
    final coords =
        (feature['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>;
    final props = Map<String, dynamic>.from(feature['properties'] as Map<String, dynamic>);
    props['lng'] = (coords[0] as num).toDouble();
    props['lat'] = (coords[1] as num).toDouble();
    return Hazard.fromJson(props);
  }
}

/// Une entrée de la chronologie d'un danger (§4.1 F5).
///
/// Volontairement dépourvue d'identifiant de device : le serveur ne l'expose pas.
/// La chronologie d'un danger est publique, le lien entre un terminal et ses
/// actions ne l'est pas (§11).
class HazardEvent {
  const HazardEvent({required this.type, required this.createdAt, this.proximity});

  final String type;
  final DateTime createdAt;
  final int? proximity;

  factory HazardEvent.fromJson(Map<String, dynamic> json) => HazardEvent(
        type: json['type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        proximity: json['proximity'] as int?,
      );

}

/// Détail d'un danger : l'objet et son historique.
class HazardDetail {
  const HazardDetail({
    required this.hazard,
    required this.timeline,
    this.provisional = false,
  });

  final Hazard hazard;
  final List<HazardEvent> timeline;

  /// Le signalement attend encore dans la file : le serveur ne le connaît pas,
  /// donc aucun geste ne peut porter dessus — confirmer un identifiant que le
  /// serveur ignore serait refusé, ou pire, mis en file puis refusé (§10).
  final bool provisional;

  factory HazardDetail.fromJson(Map<String, dynamic> json) => HazardDetail(
        hazard: Hazard.fromJson(json),
        timeline: (json['timeline'] as List<dynamic>)
            .map((e) => HazardEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Résultat d'une tentative de signalement (§4.1 F2b).
///
/// Le serveur répond l'un ou l'autre : soit le danger créé, soit un danger
/// existant assez proche pour qu'on propose de le confirmer plutôt que d'en
/// créer un second.
sealed class ReportOutcome {
  const ReportOutcome();
}

class HazardCreated extends ReportOutcome {
  const HazardCreated(this.hazard);
  final Hazard hazard;
}

class DuplicateFound extends ReportOutcome {
  const DuplicateFound({required this.existing, required this.distanceM});
  final Hazard existing;
  final double distanceM;
}

/// Le serveur est injoignable : le signalement attend dans la file (§10).
///
/// `provisional` est ce que la carte affiche en attendant. Ce n'est pas un
/// danger validé — le serveur peut encore le refuser, ou le reconnaître comme le
/// doublon d'un autre.
class ReportQueued extends ReportOutcome {
  const ReportQueued(this.provisional);
  final Hazard provisional;
}
