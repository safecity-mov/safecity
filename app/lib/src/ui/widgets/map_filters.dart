import 'package:flutter/material.dart';

import '../../data/models/hazard_type.dart';
import '../../data/models/severity.dart';
import 'severity_indicator.dart';
import '../labels.dart';

/// L'état des filtres de la carte (§4.1 F1).
class MapFilters {
  const MapFilters({
    this.types = const {},
    this.minSeverity,
  });

  /// Vide = tous les types activés. On ne filtre que si l'utilisateur a choisi.
  final Set<String> types;

  final Severity? minSeverity;

  bool get isActive => types.isNotEmpty || minSeverity != null;

  MapFilters copyWith({
    Set<String>? types,
    Severity? minSeverity,
    bool clearMinSeverity = false,
  }) =>
      MapFilters(
        types: types ?? this.types,
        minSeverity: clearMinSeverity ? null : (minSeverity ?? this.minSeverity),
      );
}

/// Feuille de filtres. Le sélecteur de type disparaît tant qu'un seul type est
/// activé : filtrer sur une liste d'un élément n'a pas de sens (§3).
class MapFiltersSheet extends StatefulWidget {
  const MapFiltersSheet({super.key, required this.filters, required this.types});

  final MapFilters filters;
  final List<HazardType> types;

  @override
  State<MapFiltersSheet> createState() => _MapFiltersSheetState();
}

class _MapFiltersSheetState extends State<MapFiltersSheet> {
  late MapFilters _filters = widget.filters;

  @override
  Widget build(BuildContext context) {
    final selectable = widget.types.where((t) => t.enabled).toList();

    return SafeArea(
      child: Padding(
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
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(FiltersLabels.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            if (selectable.length > 1) ...[
              const Text(
                FiltersLabels.typesSection,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in selectable)
                    FilterChip(
                      avatar: type.iconWidget(size: 18),
                      label: Text(type.label),
                      selected: _filters.types.contains(type.code),
                      onSelected: (on) => setState(() {
                        final next = Set<String>.from(_filters.types);
                        on ? next.add(type.code) : next.remove(type.code);
                        _filters = _filters.copyWith(types: next);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            const Text(
              FiltersLabels.severitySection,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text(FiltersLabels.allSeverities),
                  selected: _filters.minSeverity == null,
                  onSelected: (_) => setState(
                    () => _filters = _filters.copyWith(clearMinSeverity: true),
                  ),
                ),
                for (final severity in Severity.values)
                  ChoiceChip(
                    avatar: SeverityIndicator(severity, height: 14),
                    label: Text(severity.label),
                    tooltip: SeverityLabels.levelOutOf(severity.value),
                    selected: _filters.minSeverity == severity,
                    onSelected: (_) =>
                        setState(() => _filters = _filters.copyWith(minSeverity: severity)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_filters),
              child: const Text(FiltersLabels.apply),
            ),
          ],
        ),
      ),
    );
  }
}
