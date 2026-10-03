import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Un type de danger, tel que le serveur le décrit (§3).
///
/// Le type est une donnée, pas du code : libellés, icône, verbe de résolution et
/// rayon anti-doublon viennent tous de `hazard_types`. Ajouter un type est une
/// ligne en base, pas une release.
///
/// Les seuils de résolution n'y sont pas : ils sont les mêmes pour tous les types
/// et vivent dans `moderation_settings` (§6.1, voir [ModerationRules]).
class HazardType {
  const HazardType({
    required this.code,
    required this.label,
    required this.iconName,
    required this.resolvedLabel,
    required this.dedupRadiusM,
    required this.enabled,
    required this.sortOrder,
    this.iconPng,
  });

  final String code;
  final String label;
  final String iconName;

  /// « Réparé », « Nettoyé »... Le libellé du bouton de résolution (§4.1 F4).
  final String resolvedLabel;

  final int dedupRadiusM;

  /// Pilote la création, jamais l'affichage : un type désactivé garde ses dangers
  /// visibles et confirmables (§4.3).
  final bool enabled;

  final int sortOrder;

  /// Silhouette téléversée depuis la console (§4.3), ou `null`.
  ///
  /// Seule sa transparence sert : l'app peint la forme aux couleurs du marqueur,
  /// qui s'inversent quand le danger est contesté (§9). Une image en couleurs ne
  /// pourrait pas s'inverser, c'est pourquoi le serveur n'accepte qu'une
  /// silhouette. Absente, [icon] prend le relais.
  final Uint8List? iconPng;

  HazardType withIcon(Uint8List? png) => HazardType(
        code: code,
        label: label,
        iconName: iconName,
        resolvedLabel: resolvedLabel,
        dedupRadiusM: dedupRadiusM,
        enabled: enabled,
        sortOrder: sortOrder,
        iconPng: png,
      );

  factory HazardType.fromJson(Map<String, dynamic> json) => HazardType(
        code: json['code'] as String,
        label: json['label_fr'] as String,
        iconName: json['icon'] as String,
        resolvedLabel: json['resolved_label_fr'] as String,
        dedupRadiusM: json['dedup_radius_m'] as int,
        enabled: json['enabled'] as bool,
        sortOrder: json['sort_order'] as int,
      );

  /// Le glyphe de repli, utilisé tant qu'aucune silhouette n'a été téléversée —
  /// et au premier lancement, où le catalogue arrive avant les images.
  ///
  /// Le serveur envoie un nom, pas un glyphe : la correspondance est ici. Un nom
  /// inconnu retombe sur une icône générique plutôt que de casser l'écran.
  /// Le dessin du type, à utiliser partout plutôt que [icon] directement :
  /// silhouette téléversée si elle existe, glyphe embarqué sinon.
  ///
  /// `ImageIcon` teinte l'image par son canal alpha, exactement comme le fait le
  /// marqueur de carte — les deux surfaces montrent donc la même chose.
  Widget iconWidget({double size = 18, Color? color}) => iconPng != null
      ? ImageIcon(MemoryImage(iconPng!), size: size, color: color)
      : Icon(icon, size: size, color: color);

  IconData get icon => switch (iconName) {
        'pothole' => Icons.dangerous_outlined,
        'slippery' => Icons.waves,
        'manhole' => Icons.circle_outlined,
        'debris' => Icons.grass,
        'curb' => Icons.stairs,
        'works' => Icons.construction,
        'lighting' => Icons.lightbulb_outline,
        _ => Icons.report_problem_outlined,
      };
}
