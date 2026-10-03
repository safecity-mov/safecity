import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/data/models/severity.dart';
import 'package:app/src/ui/widgets/map_filters.dart';
import 'package:app/src/ui/labels.dart';

void main() {
  group('MapFilters', () {
    test('part sans aucun filtre actif', () {
      const filters = MapFilters();

      expect(filters.isActive, isFalse);
      expect(filters.types, isEmpty);
      expect(filters.minSeverity, isNull);
    });

    test('sait effacer la gravité, pas seulement la remplacer', () {
      // copyWith avec un null ne peut pas distinguer « ne change pas » de
      // « efface » : d'où le drapeau explicite.
      const filters = MapFilters(minSeverity: Severity.veryDangerous);

      expect(filters.copyWith().minSeverity, Severity.veryDangerous);
      expect(filters.copyWith(clearMinSeverity: true).minSeverity, isNull);
    });

    test('se dit actif dès qu\'un seul critère est posé', () {
      expect(const MapFilters(minSeverity: Severity.annoying).isActive, isTrue);
      expect(const MapFilters(types: {'pothole'}).isActive, isTrue);
    });
  });

  group('MapFiltersSheet', () {
    testWidgets('masque le filtre de type tant qu\'un seul type est activé', (tester) async {
      // Filtrer sur une liste d'un élément n'a pas de sens (§3).
      await _open(tester, types: _types());

      expect(find.text(FiltersLabels.typesSection), findsNothing);
      expect(find.text(FiltersLabels.severitySection), findsOneWidget);
    });

    testWidgets('affiche le filtre de type dès qu\'il y a un choix à faire', (tester) async {
      await _open(tester, types: _types(debrisEnabled: true));

      expect(find.text(FiltersLabels.typesSection), findsOneWidget);
    });

    testWidgets('renvoie le niveau choisi', (tester) async {
      MapFilters? result;
      await _open(tester, types: _types(), onPop: (f) => result = f);

      await tester.tap(find.text(Severity.veryDangerous.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, FiltersLabels.apply));
      await tester.pumpAndSettle();

      expect(result!.minSeverity, Severity.veryDangerous);
      expect(result!.isActive, isTrue);
    });

    testWidgets('« Tous » remet le niveau à zéro', (tester) async {
      MapFilters? result;
      await _open(
        tester,
        types: _types(),
        initial: const MapFilters(minSeverity: Severity.veryDangerous),
        onPop: (f) => result = f,
      );

      await tester.tap(find.text(FiltersLabels.allSeverities));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, FiltersLabels.apply));
      await tester.pumpAndSettle();

      expect(result!.minSeverity, isNull);
    });

    testWidgets('ne propose aucun calque des résolus', (tester) async {
      // Un danger résolu quitte la carte, sans option pour l'y ramener (§6.1).
      await _open(tester, types: _types());

      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('résolus'), findsNothing);
    });

    testWidgets('ne propose de filtrer que sur les types activés', (tester) async {
      // Un type désactivé n'a pas à apparaître dans le filtre, même si des
      // dangers de ce type restent sur la carte (§4.3).
      await _open(tester, types: _types(debrisEnabled: true));

      expect(find.byTooltip('Nid-de-poule'), findsOneWidget);
      expect(find.byTooltip('Éclairage défaillant'), findsNothing);
      // Et sans libellé visible : l'icône suffit (amendement).
      expect(find.text('Nid-de-poule'), findsNothing);
    });
  });
}

Future<void> _open(
  WidgetTester tester, {
  required List<HazardType> types,
  MapFilters initial = const MapFilters(),
  void Function(MapFilters?)? onPop,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showModalBottomSheet<MapFilters>(
                context: context,
                isScrollControlled: true,
                builder: (_) => MapFiltersSheet(filters: initial, types: types),
              );
              onPop?.call(result);
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

List<HazardType> _types({bool debrisEnabled = false}) => [
      const HazardType(
        code: 'pothole',
        label: 'Nid-de-poule',
        iconName: 'pothole',
        resolvedLabel: 'Réparé',
        dedupRadiusM: 15,
        enabled: true,
        sortOrder: 10,
      ),
      HazardType(
        code: 'debris',
        label: 'Verre brisé, gravats, débris',
        iconName: 'debris',
        resolvedLabel: 'Nettoyé',
        dedupRadiusM: 15,
        enabled: debrisEnabled,
        sortOrder: 40,
      ),
      const HazardType(
        code: 'lighting',
        label: 'Éclairage défaillant',
        iconName: 'lighting',
        resolvedLabel: 'Rétabli',
        dedupRadiusM: 15,
        enabled: false,
        sortOrder: 70,
      ),
    ];
