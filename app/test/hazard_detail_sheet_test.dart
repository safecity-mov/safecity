import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/models/hazard.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/ui/hazard_detail_sheet.dart';
import 'package:app/src/ui/labels.dart';
import 'package:app/src/ui/widgets/weight_balance.dart';

void main() {
  group('HazardDetailSheet', () {
    // §4.1 F4 amendé : les deux boutons sont les deux réponses à la même
    // question, et ils se répondent mot pour mot. Le verbe du catalogue —
    // « Réparé », « Nettoyé » — raconte encore quelque chose sur le bandeau
    // d'un danger déjà signalé résolu, plus sur le bouton.
    testWidgets('oppose « Toujours là » et « Plus là », quel que soit le type', (tester) async {
      await tester.pumpWidget(_host(_detail(), _type()));
      await _open(tester);

      expect(find.widgetWithText(FilledButton, DetailLabels.confirm), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, DetailLabels.gone), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Réparé'), findsNothing);
    });

    testWidgets('garde le verbe du catalogue là où il dit quelque chose', (tester) async {
      await tester.pumpWidget(_host(_detail(type: 'debris', status: 'resolved'), _debrisType()));
      await _open(tester);

      expect(find.text(DetailLabels.resolved('nettoyé')), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, DetailLabels.gone), findsOneWidget);
    });

    testWidgets('montre la voie quand la carte la connaît', (tester) async {
      await tester.pumpWidget(_host(_detail(), _type(), street: 'Rue Antoine Vollon'));
      await _open(tester);

      expect(find.text('Rue Antoine Vollon'), findsOneWidget);
    });

    testWidgets('ne montre jamais la coordonnée', (tester) async {
      // Elle ne disait rien à qui regarde déjà le pin sur la carte. Le §11.6
      // protège la précision en base, pas son affichage.
      await tester.pumpWidget(_host(_detail(), _type()));
      await _open(tester);

      expect(find.textContaining('48.85'), findsNothing);
      expect(find.textContaining('2.35'), findsNothing);
    });

    testWidgets('renvoie l\'action choisie', (tester) async {
      DetailAction? action;
      await tester.pumpWidget(_host(_detail(), _type(), onPop: (a) => action = a));
      await _open(tester);

      await tester.tap(find.widgetWithText(FilledButton, DetailLabels.confirm));
      await tester.pumpAndSettle();

      expect(action, DetailAction.confirm);
    });

    testWidgets('explique un danger contesté au lieu de le masquer', (tester) async {
      // §6.1 : un danger `disputed` reste visible, grisé, avec la mention
      // « signalé résolu ». C'est le point de la suppression douce.
      await tester.pumpWidget(_host(_detail(status: 'disputed'), _type()));
      await _open(tester);

      expect(find.text(DetailLabels.disputed), findsOneWidget);
      expect(find.widgetWithText(FilledButton, DetailLabels.confirm), findsOneWidget);
    });

    testWidgets('invite à confirmer un danger déjà résolu', (tester) async {
      await tester.pumpWidget(_host(_detail(status: 'resolved'), _type()));
      await _open(tester);

      expect(find.text(DetailLabels.resolved('réparé')), findsOneWidget);
    });

    testWidgets('signale un danger créé à distance sans y consacrer une bande',
        (tester) async {
      // §6.2 : la nuance n'engage aucun geste, l'icône suffit à la porter. La
      // phrase vient au doigt, pour qui se demande ce qu'elle veut dire.
      await tester.pumpWidget(_host(_detail(reportedRemotely: true), _type()));
      await _open(tester);

      expect(find.text(DetailLabels.reportedRemotely), findsNothing);

      await tester.tap(find.byIcon(Icons.location_off_outlined));
      await tester.pumpAndSettle();

      expect(find.text(DetailLabels.reportedRemotely), findsOneWidget);
    });

    testWidgets('ne montre l\'icône « à distance » que quand elle est vraie', (tester) async {
      await tester.pumpWidget(_host(_detail(), _type()));
      await _open(tester);

      expect(find.byIcon(Icons.location_off_outlined), findsNothing);
    });

    testWidgets('met les deux poids en balance, avec le seuil qui tranche', (tester) async {
      // §6.1 amendé : « confirmé 4 fois » ne disait ni contre quoi, ni ce que
      // pèse une confirmation faite d'ailleurs. La barre dit les deux.
      await tester.pumpWidget(
        _host(_detail(confirmWeight: 7, resolveWeight: 1.5, resolveThreshold: 3), _type()),
      );
      await _open(tester);

      expect(find.byType(WeightBalance), findsOneWidget);
      expect(find.text(DetailLabels.balancePresent('7')), findsOneWidget);
      expect(find.text(DetailLabels.balanceGone('1,5', 3)), findsOneWidget);
    });

    testWidgets('arrondit les poids au dixième, virgule française', (tester) async {
      // Un tiers s'écrit « 0,3 » : deux décimales et un point ne se lisent pas
      // d'un coup d'œil sur un vélo.
      await tester.pumpWidget(
        _host(_detail(confirmWeight: 1, resolveWeight: 0.33333334), _type()),
      );
      await _open(tester);

      expect(find.text(DetailLabels.balanceGone('0,3', 2)), findsOneWidget);
      expect(find.textContaining('0.33'), findsNothing);
    });

    testWidgets('préfère l\'adresse quand elle est connue', (tester) async {
      await tester.pumpWidget(_host(_detail(address: '12 rue de Rivoli'), _type()));
      await _open(tester);

      expect(find.text('12 rue de Rivoli'), findsOneWidget);
    });

    testWidgets('ne propose aucun geste sur un signalement encore en file', (tester) async {
      // §10 : le serveur ne connaît pas encore ce danger. Confirmer son
      // identifiant provisoire serait refusé — ou mis en file, puis refusé.
      await tester.pumpWidget(_host(_provisional(), _type()));
      await _open(tester);

      expect(find.text(DetailLabels.pending), findsOneWidget);
      expect(find.widgetWithText(FilledButton, DetailLabels.confirm), findsNothing);
      expect(find.widgetWithText(OutlinedButton, DetailLabels.gone), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // Ses poids valent zéro et son seuil est celui d'un danger neuf : la
      // balance se lirait comme un danger que personne n'a confirmé.
      expect(find.byType(WeightBalance), findsNothing);
    });

    testWidgets('le retrait par l\'auteur tient dans une poubelle', (tester) async {
      // Une phrase entière sous les deux gestes du produit tirait l'œil vers la
      // sortie, pour une action rare que le serveur refuse le plus souvent.
      DetailAction? action;
      await tester.pumpWidget(_host(_detail(), _type(), onPop: (a) => action = a));
      await _open(tester);

      expect(find.text(DetailLabels.removeOwn), findsNothing);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(action, DetailAction.removeOwn);
    });

    testWidgets('n\'affiche aucun identifiant de terminal dans l\'historique', (tester) async {
      // §11 : la chronologie est publique, le lien device → actions ne l'est pas.
      await tester.pumpWidget(_host(_detail(), _type()));
      await _open(tester);
      await tester.tap(find.text(DetailLabels.timeline(2)));
      await tester.pumpAndSettle();

      expect(find.text(DetailLabels.event('create')), findsOneWidget);
      expect(find.text(DetailLabels.event('confirm')), findsOneWidget);
      expect(find.textContaining('-1111-'), findsNothing);
    });
  });
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

HazardDetail _provisional() =>
    HazardDetail(hazard: _detail().hazard, timeline: const [], provisional: true);

HazardDetail _detail({
  String type = 'pothole',
  String status = 'active',
  bool reportedRemotely = false,
  double confirmWeight = 3,
  double resolveWeight = 0,
  int resolveThreshold = 2,
  String? address,
}) =>
    HazardDetail.fromJson({
      'id': '11111111-1111-1111-1111-111111111111',
      'type': type,
      'lat': 48.856600,
      'lng': 2.352200,
      'severity': 3,
      'status': status,
      'description': 'Trou profond',
      'address': address,
      'created_at': '2026-09-13T22:00:00+00:00',
      'last_confirmed_at': '2026-09-13T22:30:00+00:00',
      'confirm_weight': confirmWeight,
      'resolve_weight': resolveWeight,
      'resolve_threshold': resolveThreshold,
      'reported_remotely': reportedRemotely,
      'timeline': [
        {'type': 'create', 'proximity': 1, 'created_at': '2026-09-13T22:00:00+00:00'},
        {'type': 'confirm', 'proximity': 2, 'created_at': '2026-09-13T22:30:00+00:00'},
      ],
      'photos': <dynamic>[],
    });

HazardType _type() => const HazardType(
      code: 'pothole',
      label: 'Nid-de-poule',
      iconName: 'pothole',
      resolvedLabel: 'Réparé',
      dedupRadiusM: 15,
      enabled: true,
      sortOrder: 10,
    );

HazardType _debrisType() => const HazardType(
      code: 'debris',
      label: 'Verre brisé, gravats, débris',
      iconName: 'debris',
      resolvedLabel: 'Nettoyé',
      dedupRadiusM: 15,
      enabled: true,
      sortOrder: 40,
    );

Widget _host(
  HazardDetail detail,
  HazardType type, {
  void Function(DetailAction?)? onPop,
  String? street,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final action = await showModalBottomSheet<DetailAction>(
                context: context,
                isScrollControlled: true,
                builder: (_) => HazardDetailSheet(
                  detail: detail,
                  type: type,
                  street: street,
                ),
              );
              onPop?.call(action);
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
