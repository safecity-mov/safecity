import 'package:flutter/material.dart';

/// Niveau d'un danger, sur trois crans (§4.1 F2, amendé).
///
/// Le niveau est un simple indicateur, 1, 2 ou 3, sans libellé : les mots
/// (« gênant », « dangereux »…) ne voulaient pas dire la même chose pour tout
/// le monde. La couleur ne porte jamais l'information seule : chaque cran a
/// aussi un chiffre, une jauge (`SeverityIndicator`) et une taille de marqueur
/// distincts (§9, accessibilité).
enum Severity {
  annoying(1, Color(0xFFB26A00)),
  dangerous(2, Color(0xFFC24D00)),
  veryDangerous(3, Color(0xFFA4161A));

  const Severity(this.value, this.color);

  /// Le nombre de crans : ce que le serveur accepte (`CHECK (severity BETWEEN 1 AND 3)`).
  static const max = 3;

  final int value;
  final Color color;

  /// Le chiffre, tel qu'il s'affiche.
  String get label => '$value';

  static Severity fromValue(int value) =>
      Severity.values.firstWhere((s) => s.value == value, orElse: () => Severity.dangerous);

  /// Rayon du marqueur : le niveau reste lisible sans la couleur.
  double get markerRadius => switch (this) {
        Severity.annoying => 9,
        Severity.dangerous => 12,
        Severity.veryDangerous => 15,
      };
}
