import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/config.dart';
import 'package:app/src/data/hazard_repository.dart';
import 'package:app/src/data/trace_horizon.dart';
import 'package:app/src/ui/markdown_view.dart';

/// Le texte de confidentialité est une promesse publique, en deux longueurs :
/// la courte que l'écran ouvre, la longue qui dit où vérifier dans le code.
/// Ce qui est testé ici, ce n'est pas leur prose mais le fait qu'elles restent
/// vraies, et d'accord entre elles : si un chiffre du code change sans que les
/// textes suivent, ces tests tombent.
void main() {
  final court = File('assets/privacy.md').readAsStringSync();
  final long = File('assets/privacy-full.md').readAsStringSync();

  group('PRIVACY.md', () {
    test('la version détaillée embarquée est la copie conforme de la source', () {
      // Flutter ne sait pas embarquer un fichier hors du paquet, d'où la copie.
      // Sans ce test, l'app pourrait afficher une version périmée du texte qui
      // l'engage.
      final canonical = File('../PRIVACY.md').readAsStringSync();
      expect(
        long,
        canonical,
        reason: 'assets/privacy-full.md a divergé de ../PRIVACY.md. '
            'Recopier : cp PRIVACY.md app/assets/privacy-full.md',
      );
    });

    test('la version courte tient en une page', () {
      // C'est sa raison d'être : la longue faisait peur, et un texte qu'on ne
      // lit pas ne promet rien.
      expect(court.split('\n').where((l) => l.trim().isNotEmpty).length, lessThanOrEqualTo(30));
      expect(court.length, lessThan(long.length ~/ 3));
    });

    for (final (nom, source) in [('courte', court), ('détaillée', long)]) {
      group('version $nom', () {
        test('les durées annoncées sont celles que le code applique', () {
          // Une seule durée est promise, le plafond : les 45 minutes de
          // `TraceHorizon.maxAge` sont un détail de mécanisme, pas une garantie.
          expect(source, anyOf(contains('une heure et demie'), contains('1h30')));
          expect(TraceHorizon.guarantee, const Duration(minutes: 90));
          expect(HazardRepository.cacheTtl, TraceHorizon.maxAge);
          // La fenêtre de corrélation, côté serveur : db/migrations/0050.
          expect(source, contains('24 heures'));
        });

        test('la mauvaise nouvelle y est', () {
          // Une politique sans mauvaise nouvelle n'est pas crédible. Celle-ci en
          // a une seule et elle doit rester visible dans les deux longueurs.
          expect(source, contains('public'));
          expect(source, contains('définitif'));
        });

        test('nomme les droits que l\'écran Paramètres offre', () {
          expect(source.toLowerCase(), contains('retirer'));
          expect(source.toLowerCase(), contains('effacer mes données'));
          // « Régénérer » n'existe plus comme bouton (§11.4 amendé).
          expect(source, isNot(contains('Régénérer mon identifiant')));
        });

        test('décrit la vérification de mise à jour', () {
          // Une requête vers notre serveur à chaque lancement : anodine, mais
          // elle existe, et un texte qui promet « rien d'autre » doit la nommer.
          expect(source, anyOf(contains('dernière version'), contains('version plus récente')));
        });
      });
    }

    test('la version détaillée n\'annonce aucune fonctionnalité qui n\'existe pas', () {
      // Les photos sont abandonnées pour la bêta (§4.6 amendé) : le texte doit
      // le dire au présent, pas les décrire comme à venir.
      expect(long, contains('ne permet pas d\'ajouter de photo'));
      expect(long, isNot(contains('la photo part sur notre serveur')));
    });
  });

  group('MarkdownView', () {
    testWidgets('rend la version détaillée sans rien avaler', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MarkdownView(source: long)),
        ),
      ),);
      await tester.pump();

      expect(find.text('Vie privée'), findsOneWidget);
      expect(find.textContaining('Il n\'y a pas de compte'), findsOneWidget);
      // Un tableau devient des blocs empilés, et ses cellules restent lisibles.
      expect(find.textContaining('Anti-double-vote'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rend la version courte', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MarkdownView(source: court)),
        ),
      ),);
      await tester.pump();

      expect(find.text('Vie privée, en bref'), findsOneWidget);
      expect(find.textContaining('Pas de compte'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppConfig', () {
    test('la version affichée est celle du pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared = RegExp(r'^version:\s*([0-9.]+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1);
      expect(AppConfig.version, declared);
    });

    test('le versionCode comparé au serveur est celui du pubspec', () {
      // C'est ce nombre que `UpdateChecker` compare à `latest.json` : s'il
      // reste en arrière, l'app se proposerait sa propre version.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared = RegExp(r'^version:\s*[0-9.]+\+(\d+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1);
      expect(AppConfig.versionCode, int.parse(declared!));
    });
  });
}
