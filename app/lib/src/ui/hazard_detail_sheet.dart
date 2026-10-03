import 'package:flutter/material.dart';

import '../data/models/hazard.dart';
import '../data/models/hazard_type.dart';
import 'labels.dart';
import 'widgets/severity_indicator.dart';
import 'theme.dart';
import 'widgets/weight_balance.dart';

/// L'action demandée au retour de la feuille de détail.
enum DetailAction { confirm, resolve, removeOwn }

/// Détail d'un danger (§9, écran 3).
///
/// Deux gros boutons, et rien d'autre au premier plan : « Toujours là » et le
/// verbe de résolution du type — « Réparé » pour un nid-de-poule, « Nettoyé »
/// pour des débris. Ce verbe vient du catalogue, pas du code (§3).
class HazardDetailSheet extends StatelessWidget {
  const HazardDetailSheet({
    super.key,
    required this.detail,
    required this.type,
    this.street,
  });

  final HazardDetail detail;
  final HazardType type;

  /// Le nom de la voie sous le danger, lu dans le fond de carte (§7). `null`
  /// quand la carte ne le connaît pas : on retombe alors sur la coordonnée.
  final String? street;

  @override
  Widget build(BuildContext context) {
    final hazard = detail.hazard;
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // L'icône dit le type, sans libellé (amendement) ; le nom reste
                // au lecteur d'écran.
                Semantics(
                  label: type.label,
                  image: true,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: hazard.severity.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: type.iconWidget(size: 26, color: hazard.severity.color),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SeverityIndicator(hazard.severity, height: 14, withLabel: true),
                          // « Signalé à distance » tenait une bande entière pour
                          // une nuance qui n'engage aucun geste. L'icône suffit
                          // à la signaler ; la phrase vient au doigt, pour qui
                          // se demande ce qu'elle veut dire.
                          if (hazard.reportedRemotely)
                            Tooltip(
                              message: DetailLabels.reportedRemotely,
                              triggerMode: TooltipTriggerMode.tap,
                              showDuration: const Duration(seconds: 5),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.location_off_outlined,
                                  size: 17,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: DetailLabels.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),

            if (detail.provisional) ...[
              const SizedBox(height: 12),
              _Banner(
                icon: Icons.cloud_upload_outlined,
                color: theme.colorScheme.outline,
                text: DetailLabels.pending,
              ),
            ],
            if (hazard.status.isDisputed) ...[
              const SizedBox(height: 12),
              _Banner(
                icon: Icons.help_outline,
                color: theme.colorScheme.tertiary,
                text: DetailLabels.disputed,
              ),
            ],
            if (hazard.status == HazardStatus.resolved) ...[
              const SizedBox(height: 12),
              _Banner(
                icon: Icons.check_circle_outline,
                color: theme.colorScheme.primary,
                text: DetailLabels.resolved(type.resolvedLabel.toLowerCase()),
              ),
            ],

            if (hazard.description != null) ...[
              const SizedBox(height: 16),
              Text(hazard.description!, style: theme.textTheme.bodyLarge),
            ],

            const SizedBox(height: 16),
            // Pas de « confirmé N fois » : depuis que les confirmations pèsent
            // comme les votes (§6.1 amendé), il n'y a plus de compte à montrer,
            // et la chronologie plus bas dit déjà qui a fait quoi.
            _Line(
              icon: Icons.schedule,
              text: DetailLabels.reportedOn(relativeDate(hazard.createdAt)),
            ),
            _Line(
              icon: Icons.visibility_outlined,
              text: DetailLabels.lastSeen(relativeDate(hazard.lastConfirmedAt)),
            ),
            // La coordonnée a disparu : elle ne dit rien à qui regarde la
            // carte sous le pin, et le §11.6 la protège en base, pas à l'écran.
            if (hazard.address != null)
              _Line(icon: Icons.place_outlined, text: hazard.address!)
            else if (street != null)
              _Line(icon: Icons.place_outlined, text: street!),

            // Où en est le danger, en une barre. Rien à montrer tant que le
            // serveur ne l'a pas vu : ses poids valent zéro et son seuil est un
            // seuil de danger neuf, ce qui se lirait comme une balance vide.
            if (!detail.provisional) ...[
              const SizedBox(height: 16),
              WeightBalance(
                present: hazard.confirmWeight,
                gone: hazard.resolveWeight,
                threshold: hazard.resolveThreshold,
              ),
            ],

            const SizedBox(height: 20),

            // Les deux gestes du §9. Ils pèsent d'autant plus que l'on est près
            // du danger, le palier étant calculé sur l'appareil (§6.2). Aucun
            // geste sur un signalement que le serveur ne connaît pas encore.
            if (!detail.provisional) ...[
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(DetailAction.confirm),
                icon: const Icon(Icons.check),
                label: const Text(DetailLabels.confirm),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(DetailAction.resolve),
                icon: const Icon(Icons.done_all),
                label: const Text(DetailLabels.gone),
              ),
              const SizedBox(height: 8),
              // Une phrase entière pour une action rare, juste sous les deux
              // gestes du produit, tirait l'œil vers la sortie. L'icône dit
              // « jeter » sans se faire remarquer, et son libellé reste au
              // doigt comme au lecteur d'écran.
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(DetailAction.removeOwn),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: DetailLabels.removeOwn,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              _Timeline(events: detail.timeline),
            ],
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
}

/// Historique du danger. Aucune identité n'y figure : le serveur ne renvoie pas
/// les identifiants de device, seulement les gestes et leur date (§11).
class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<HazardEvent> events;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          DetailLabels.timeline(events.length),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        children: [
          for (final event in events.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconFor(event.type), size: 18),
              title: Text(DetailLabels.event(event.type), style: const TextStyle(fontSize: 13)),
              trailing: Text(
                relativeDate(event.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      );

  static IconData _iconFor(String type) => switch (type) {
        'create' => Icons.add_location_alt_outlined,
        'confirm' => Icons.check,
        'mark_resolved' => Icons.done_all,
        'remove' => Icons.undo,
        'restore' => Icons.restore,
        _ => Icons.circle_outlined,
      };
}
