import 'package:flutter/material.dart';

import '../../ui/labels.dart';

/// Gravité sur trois niveaux (§4.1 F2).
///
/// La couleur ne porte jamais l'information seule : chaque niveau a aussi un
/// libellé, une taille de marqueur et une icône distincts (§9, accessibilité).
enum Severity {
  annoying(1, SeverityLabels.annoying, Color(0xFFB26A00), Icons.remove),
  dangerous(2, SeverityLabels.dangerous, Color(0xFFC24D00), Icons.priority_high),
  veryDangerous(3, SeverityLabels.veryDangerous, Color(0xFFA4161A), Icons.warning_amber_rounded);

  const Severity(this.value, this.label, this.color, this.icon);

  final int value;
  final String label;
  final Color color;
  final IconData icon;

  static Severity fromValue(int value) =>
      Severity.values.firstWhere((s) => s.value == value, orElse: () => Severity.dangerous);

  /// Rayon du marqueur : la gravité reste lisible sans la couleur.
  double get markerRadius => switch (this) {
        Severity.annoying => 9,
        Severity.dangerous => 12,
        Severity.veryDangerous => 15,
      };
}
