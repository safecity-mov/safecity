import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../labels.dart';

/// La balance d'un danger : ce qui dit « toujours là » contre ce qui dit
/// « plus là » (§6.1).
///
/// Une seule barre, ancrée au centre : elle pousse à gauche pour le poids
/// « présent », à droite pour le poids « résolu ». Les deux moitiés partagent
/// la même échelle, donc la **longueur** dit le poids en valeur absolue et la
/// **comparaison des deux** dit où penche le danger. C'est ce qu'un compteur ne
/// montrait pas : « confirmé 4 fois » ne disait ni contre quoi, ni combien pèse
/// une confirmation faite d'ailleurs.
///
/// **Le trait vertical à droite est le seuil, et c'est lui qui décide.** Le
/// danger quitte la carte quand la barre droite l'atteint, pas quand elle
/// dépasse la gauche. Sans ce repère la balance mentirait : le seuil monte avec
/// le poids « présent », donc une barre gauche plus longue que la droite ne
/// veut pas dire que le danger reste.
class WeightBalance extends StatelessWidget {
  const WeightBalance({
    super.key,
    required this.present,
    required this.gone,
    required this.threshold,
  });

  /// Poids « toujours là » : le signalement, qui vaut plusieurs confirmations,
  /// plus chaque « toujours là ».
  final double present;

  /// Poids « plus là », à la même échelle.
  final double gone;

  /// Ce qu'il faut à [gone] pour que le danger quitte la carte.
  final int threshold;

  static const _barHeight = 12.0;

  /// L'échelle commune aux deux moitiés. Le seuil en fait partie : sans lui, un
  /// danger neuf montrerait un repère hors de la barre.
  double get _domain =>
      math.max(1, [present, gone, threshold.toDouble()].reduce(math.max));

  /// Un poids en français : 0,33 s'affiche « 0,3 », 3 s'affiche « 3 ».
  static String _weight(double value) {
    final rounded = (value * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return text.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final caption = theme.textTheme.bodySmall;

    final presentText = _weight(present);
    final goneText = _weight(gone);

    return Semantics(
      label: DetailLabels.balanceSemantics(presentText, goneText, threshold),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DetailLabels.balancePresent(presentText),
                  style: caption?.copyWith(color: colors.primary),
                ),
              ),
              Expanded(
                child: Text(
                  DetailLabels.balanceGone(goneText, threshold),
                  textAlign: TextAlign.right,
                  style: caption?.copyWith(color: colors.tertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: _barHeight,
            child: Row(
              children: [
                // À gauche, la barre part du centre vers l'extérieur : elle se
                // lit du pivot vers le bord, comme celle de droite.
                Expanded(
                  child: _Track(
                    color: colors.primary,
                    factor: present / _domain,
                    alignment: Alignment.centerRight,
                  ),
                ),
                // Le pivot, pour que les deux longueurs se comparent à l'œil.
                Container(width: 2, color: colors.outlineVariant),
                Expanded(
                  child: _Track(
                    color: colors.tertiary,
                    factor: gone / _domain,
                    alignment: Alignment.centerLeft,
                    markerFactor: threshold / _domain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Une moitié de la balance : un fond neutre qui montre l'échelle, la barre
/// par-dessus, et pour la moitié droite le repère du seuil.
class _Track extends StatelessWidget {
  const _Track({
    required this.color,
    required this.factor,
    required this.alignment,
    this.markerFactor,
  });

  final Color color;
  final double factor;
  final Alignment alignment;
  final double? markerFactor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(3);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final marker = markerFactor;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Le fond dit jusqu'où la barre pourrait aller : sans lui, un poids
            // nul ne se distingue pas d'un écran qui n'a rien chargé.
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.outlineVariant.withValues(alpha: 0.35),
                borderRadius: radius,
              ),
            ),
            Align(
              alignment: alignment,
              child: FractionallySizedBox(
                widthFactor: factor.clamp(0.0, 1.0),
                // `Align` passe des contraintes lâches, et une boîte sans enfant
                // s'y effondre à zéro : sans cette hauteur, la barre existait
                // dans l'arbre mais ne peignait rien.
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: color, borderRadius: radius),
                ),
              ),
            ),
            if (marker != null)
              Positioned(
                // Collé au bord quand le seuil ferme l'échelle, pour que le
                // trait reste visible au lieu de déborder.
                left: (width * marker.clamp(0.0, 1.0) - 1).clamp(0.0, width - 2),
                top: -2,
                bottom: -2,
                width: 2,
                child: ColoredBox(color: colors.onSurface),
              ),
          ],
        );
      },
    );
  }
}
