import 'package:flutter/material.dart';

import '../../data/models/severity.dart';
import '../labels.dart';

/// Le niveau d'un danger, en trois crans, à la manière d'une jauge de signal :
/// autant de barres pleines que le niveau, dans sa couleur, les autres grisées.
///
/// C'est le nombre de barres qui porte l'information ; la couleur ne fait que
/// l'appuyer (§9, accessibilité). Le lecteur d'écran lit « Niveau 2 sur 3 ».
class SeverityIndicator extends StatelessWidget {
  const SeverityIndicator(
    this.severity, {
    super.key,
    this.height = 16,
    this.withLabel = false,
  });

  final Severity severity;

  /// Hauteur de la barre la plus haute ; les deux autres en découlent.
  final double height;

  /// Ajoute « Niveau n » à droite des barres.
  final bool withLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bars = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var cran = 1; cran <= Severity.max; cran++) ...[
          if (cran > 1) SizedBox(width: height / 6),
          Container(
            width: height / 3.2,
            height: height * (0.45 + 0.275 * (cran - 1)),
            decoration: BoxDecoration(
              color: cran <= severity.value ? severity.color : theme.dividerColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ],
    );
    return Semantics(
      label: SeverityLabels.levelOutOf(severity.value),
      excludeSemantics: true,
      child: withLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                bars,
                const SizedBox(width: 6),
                Text(SeverityLabels.level(severity.value), style: theme.textTheme.bodyMedium),
              ],
            )
          : bars,
    );
  }
}
