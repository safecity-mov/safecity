import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/data/models/severity.dart';
import 'package:app/src/ui/report_sheet.dart';
import 'package:app/src/ui/labels.dart';

void main() {
  group('ReportSheet', () {
    testWidgets('masque le sélecteur de type tant qu\'un seul type est activé', (tester) async {
      // §3 : « le sélecteur de type est masqué tant qu'un seul type est activé,
      // et l'écran se réduit à gravité + photo + texte. »
      await tester.pumpWidget(_host(ReportSheet(types: _types(), address: null)));
      await _open(tester);

      expect(find.text(ReportLabels.severitySection), findsOneWidget);
      expect(find.text(ReportLabels.typeSection), findsNothing);
      expect(find.byTooltip('Nid-de-poule'), findsNothing);
    });

    testWidgets('affiche le sélecteur dès qu\'un second type est activé', (tester) async {
      // Activer un type est un UPDATE en base, pas une release : l'UI doit suivre
      // le catalogue sans qu'on y touche (§3).
      await tester.pumpWidget(
        _host(ReportSheet(types: _types(debrisEnabled: true), address: null)),
      );
      await _open(tester);

      expect(find.text(ReportLabels.typeSection), findsOneWidget);
      // Le type se reconnaît à son icône ; son nom n'est plus affiché, il reste
      // au lecteur d'écran et à l'appui long.
      expect(find.byTooltip('Nid-de-poule'), findsOneWidget);
      expect(find.byTooltip('Verre brisé, gravats, débris'), findsOneWidget);
      expect(find.text('Nid-de-poule'), findsNothing);
    });

    testWidgets('n\'autorise l\'envoi qu\'une fois le niveau choisi', (tester) async {
      await tester.pumpWidget(_host(ReportSheet(types: _types(), address: null)));
      await _open(tester);

      final button = find.widgetWithText(FilledButton, ReportLabels.send);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.tap(find.text(Severity.dangerous.label));
      await tester.pump();

      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('renvoie ce que l\'utilisateur a saisi, sans rien inventer', (tester) async {
      ReportDraft? draft;
      await tester.pumpWidget(
        _host(ReportSheet(types: _types(), address: null), onPop: (r) => draft = r),
      );
      await _open(tester);

      await tester.tap(find.text(Severity.veryDangerous.label));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Trou profond');
      await tester.tap(find.widgetWithText(FilledButton, ReportLabels.send));
      await tester.pumpAndSettle();

      expect(draft, isNotNull);
      expect(draft!.severity, Severity.veryDangerous);
      expect(draft!.type.code, 'pothole');
      expect(draft!.description, 'Trou profond');
    });

    testWidgets('ne renvoie pas de commentaire quand le champ est laissé vide', (tester) async {
      ReportDraft? draft;
      await tester.pumpWidget(
        _host(ReportSheet(types: _types(), address: null), onPop: (r) => draft = r),
      );
      await _open(tester);

      await tester.tap(find.text(Severity.annoying.label));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, ReportLabels.send));
      await tester.pumpAndSettle();

      expect(draft!.description, isNull);
    });

    testWidgets('borne le commentaire à 140 caractères', (tester) async {
      // La contrainte existe aussi en base (§5) : la respecter ici évite un
      // aller-retour réseau pour se faire refuser.
      await tester.pumpWidget(_host(ReportSheet(types: _types(), address: null)));
      await _open(tester);

      await tester.enterText(find.byType(TextField), 'x' * 200);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text.length, 140);
    });

    testWidgets('prévient que le commentaire est public', (tester) async {
      // §11.2 : « le libellé du champ prévient qu'il est public. »
      await tester.pumpWidget(_host(ReportSheet(types: _types(), address: null)));
      await _open(tester);

      expect(find.text(ReportLabels.descriptionHelper), findsOneWidget);
    });
  });
}

Future<void> _open(WidgetTester tester) async {
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
    ];

Widget _host(Widget child, {void Function(ReportDraft?)? onPop}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showModalBottomSheet<ReportDraft>(
                context: context,
                isScrollControlled: true,
                builder: (_) => child,
              );
              onPop?.call(result);
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
