import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/ui/labels.dart';
import 'package:app/src/ui/widgets/weight_balance.dart';

/// La balance du §6.1 : deux poids sur une même échelle, et le seuil qui
/// tranche. Ce qui est testé ici, c'est que la barre ne puisse pas mentir —
/// qu'une longueur dise bien un poids, et que le repère du seuil reste dans le
/// cadre quelles que soient les valeurs.
void main() {
  /// La largeur des deux moitiés colorées, dans l'ordre : « présent », « plus là ».
  List<double> bars(WidgetTester tester) => tester
      .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
      .map((b) => b.widthFactor!)
      .toList();

  Future<void> pump(
    WidgetTester tester, {
    required double present,
    required double gone,
    int threshold = 2,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: WeightBalance(present: present, gone: gone, threshold: threshold),
          ),
        ),
      ),
    );
  }

  testWidgets('les deux moitiés partagent une échelle : la longueur dit le poids',
      (tester) async {
    // Échelle commune = 6. « Présent » remplit sa moitié, « plus là » en
    // occupe la moitié : c'est exactement leur rapport.
    await pump(tester, present: 6, gone: 3, threshold: 2);

    expect(bars(tester), [1.0, 0.5]);
  });

  testWidgets('un danger neuf penche entièrement du côté « toujours là »', (tester) async {
    await pump(tester, present: 3, gone: 0, threshold: 2);

    expect(bars(tester), [1.0, 0.0]);
  });

  testWidgets('le seuil entre dans l\'échelle, même sans aucun geste', (tester) async {
    // Sans cela, le repère d'un danger sans poids tomberait hors du cadre.
    await pump(tester, present: 0, gone: 0, threshold: 5);

    expect(bars(tester), [0.0, 0.0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une balance vide ne divise pas par zéro', (tester) async {
    await pump(tester, present: 0, gone: 0, threshold: 0);

    expect(bars(tester), [0.0, 0.0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un poids qui dépasse le seuil reste dans le cadre', (tester) async {
    // Le serveur recalcule après coup : un danger peut porter plus de « plus
    // là » que son seuil le temps d'un rafraîchissement.
    await pump(tester, present: 1, gone: 9, threshold: 2);

    expect(bars(tester), [1 / 9, 1.0]);
  });

  testWidgets('écrit les poids en français, arrondis au dixième', (tester) async {
    await pump(tester, present: 1, gone: 0.33333334, threshold: 2);

    expect(find.text(DetailLabels.balancePresent('1')), findsOneWidget);
    expect(find.text(DetailLabels.balanceGone('0,3', 2)), findsOneWidget);
  });

  testWidgets('se lit sans la voir', (tester) async {
    // §9, accessibilité : une barre seule ne dit rien à un lecteur d'écran.
    await pump(tester, present: 3, gone: 1, threshold: 2);

    expect(
      find.bySemanticsLabel(DetailLabels.balanceSemantics('3', '1', 2)),
      findsOneWidget,
    );
  });
}
