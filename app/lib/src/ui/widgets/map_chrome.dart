import 'package:flutter/material.dart';

import '../labels.dart';

/// Le chrome de l'écran carte : ce qui se dessine par-dessus la carte sans rien
/// savoir d'elle.
///
/// Sorti de `map_screen.dart`, qui faisait 1200 lignes et n'avait aucun test
/// widget. Ces quatre-là n'ont ni état ni dépendance : ils se vérifient en les
/// affichant, ce qui est exactement ce qu'on veut d'un bandeau qui doit dire la
/// bonne chose au bon moment (§9, §10).

/// Bandeau d'état en haut de carte (§10).
///
/// Deux usages, jamais ensemble : ce qui attend le réseau, et le fait que la
/// zone visible n'a jamais été chargée. Le second prime, parce qu'il change le
/// sens de ce que l'utilisateur voit.
class TopBanner extends StatelessWidget {
  const TopBanner({super.key, required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, left: 72, right: 72),
          child: Material(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: theme.colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le pin de placement, fixe au centre de l'écran : c'est la carte qui bouge
/// dessous. Plus précis qu'un marqueur à faire glisser.
class CenterPin extends StatelessWidget {
  const CenterPin({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          // Le pin pointe vers le bas : sa pointe est au centre exact de l'écran.
          child: Transform.translate(
            offset: const Offset(0, -22),
            child: Icon(
              Icons.location_on,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
              shadows: const [Shadow(blurRadius: 6, color: Colors.black38)],
            ),
          ),
        ),
      );
}

/// La barre du mode placement : ce qu'on peut faire, et pourquoi on ne peut pas
/// encore valider. Trop loin, le bouton principal ne se grise pas : il zoome,
/// et c'est « Continuer » qui prend sa place une fois assez près.
class PlacementBar extends StatelessWidget {
  const PlacementBar({
    super.key,
    required this.canValidate,
    required this.onCancel,
    required this.onZoomIn,
    required this.onValidate,
  });

  /// Faux sous le zoom minimal : ajuster le pin n'aurait pas de sens, et la
  /// précision du §11.6 ne serait plus tenue.
  final bool canValidate;
  final VoidCallback onCancel;

  /// Rapproche la carte juste ce qu'il faut, sans la déplacer.
  final VoidCallback onZoomIn;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  canValidate ? MapLabels.placeReady : MapLabels.placeZoomIn,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child:
                          OutlinedButton(onPressed: onCancel, child: const Text(MapLabels.cancel)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: canValidate
                          ? FilledButton(
                              onPressed: onValidate,
                              child: const Text(MapLabels.placeContinue),
                            )
                          : FilledButton.icon(
                              onPressed: onZoomIn,
                              icon: const Icon(Icons.zoom_in),
                              label: const Text(MapLabels.placeZoom),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

/// Les outils de la colonne de droite. `onPressed` nul les grise, ce qui est le
/// cas pendant un placement : on ne quitte pas un geste en cours par mégarde.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.highlighted = false,
    this.iconAngle = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool highlighted;

  /// Rotation de l'icône, en radians. Sert à la boussole, dont la flèche
  /// suit le nord quand la carte est tournée.
  final double iconAngle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: highlighted ? scheme.primaryContainer : scheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Transform.rotate(angle: iconAngle, child: Icon(icon)),
        // Cible tactile d'au moins 44 points (§9, accessibilité).
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    );
  }
}
