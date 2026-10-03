import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/ui/widgets/map_chrome.dart';
import 'package:app/src/ui/labels.dart';

void main() {
  group('TopBanner', () {
    testWidgets('affiche son texte et reste muet sans action', (tester) async {
      await tester.pumpWidget(
        _host(TopBanner(icon: Icons.cloud_off, text: MapLabels.pending(2))),
      );

      expect(find.text(MapLabels.pending(2)), findsOneWidget);
      // Toucher un bandeau sans action ne doit rien déclencher ni rien casser :
      // c'est le cas du bandeau « zone jamais chargée », qui n'est qu'un avis.
      await tester.tap(find.text(MapLabels.pending(2)));
      await tester.pump();
    });

    testWidgets('relance la file au doigt quand une action est fournie', (tester) async {
      // Le bandeau des gestes en attente est le seul endroit où l'on peut
      // relancer un envoi à la main (§10).
      var taps = 0;
      await tester.pumpWidget(
        _host(TopBanner(icon: Icons.cloud_off, text: MapLabels.pending(1), onTap: () => taps++)),
      );

      await tester.tap(find.text(MapLabels.pending(1)));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('PlacementBar', () {
    testWidgets('sous le zoom minimal, elle explique et propose de zoomer', (tester) async {
      // Un bouton grisé sans un mot laisse croire à une panne, et pincer pour
      // atteindre le seuil se fait à tâtons. La précision du §11.6 ne tient
      // pas si le pin se pose de trop loin : le bouton principal rapproche.
      var zoomed = 0;
      var validated = 0;
      await tester.pumpWidget(
        _host(
          PlacementBar(
            canValidate: false,
            onCancel: () {},
            onZoomIn: () => zoomed++,
            onValidate: () => validated++,
          ),
        ),
      );

      expect(find.text(MapLabels.placeZoomIn), findsOneWidget);
      expect(find.text(MapLabels.placeContinue), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, MapLabels.placeZoom));
      await tester.pump();

      expect(zoomed, 1);
      expect(validated, 0);
    });

    testWidgets('au bon zoom, elle invite à placer et laisse continuer', (tester) async {
      var validated = 0;
      await tester.pumpWidget(
        _host(
          PlacementBar(
            canValidate: true,
            onCancel: () {},
            onZoomIn: () {},
            onValidate: () => validated++,
          ),
        ),
      );

      expect(find.text(MapLabels.placeReady), findsOneWidget);
      expect(find.text(MapLabels.placeZoom), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, MapLabels.placeContinue));
      await tester.pump();

      expect(validated, 1);
    });

    testWidgets('annuler est toujours possible, même sans pouvoir valider', (tester) async {
      // C'est le seul moyen de sortir du mode placement : le griser aussi
      // enfermerait dans un geste qu'on ne peut ni finir ni abandonner.
      var cancelled = 0;
      await tester.pumpWidget(
        _host(
          PlacementBar(
            canValidate: false,
            onCancel: () => cancelled++,
            onZoomIn: () {},
            onValidate: () {},
          ),
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, MapLabels.cancel));
      await tester.pump();

      expect(cancelled, 1);
    });
  });

  group('RoundButton', () {
    testWidgets('porte une cible tactile d\'au moins 48 points', (tester) async {
      // §9, accessibilité : les outils sont visés d'une main, en roulant.
      await tester.pumpWidget(
        _host(RoundButton(icon: Icons.filter_alt, tooltip: 'Filtres', onPressed: () {})),
      );

      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('se grise quand aucune action n\'est possible', (tester) async {
      await tester.pumpWidget(
        const _Host(child: RoundButton(icon: Icons.settings, tooltip: 'Paramètres', onPressed: null)),
      );

      expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    });

    testWidgets('son libellé reste lisible par un lecteur d\'écran', (tester) async {
      await tester.pumpWidget(
        _host(RoundButton(icon: Icons.my_location, tooltip: 'Recentrer', onPressed: () {})),
      );

      expect(find.byTooltip('Recentrer'), findsOneWidget);
    });
  });

  testWidgets('CenterPin ne capte aucun geste : la carte glisse dessous', (tester) async {
    await tester.pumpWidget(_host(const CenterPin()));

    expect(
      find.descendant(of: find.byType(CenterPin), matching: find.byType(IgnorePointer)),
      findsOneWidget,
    );
  });
}

Widget _host(Widget child) => _Host(child: child);

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: Stack(children: [child])));
}
