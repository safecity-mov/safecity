import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde-fou du regroupement des libellés.
///
/// Rassembler les textes une fois ne sert à rien si le suivant en réécrit un en
/// dur dans un widget : le fichier cesse alors d'être la liste complète de ce
/// que l'app raconte, sans que personne ne s'en aperçoive. Ce test relit les
/// écrans et refuse un texte visible posé ailleurs que dans `labels.dart`.
void main() {
  test('aucun libellé visible n\'est écrit en dur dans un widget', () {
    // Les emplacements par lesquels un texte arrive à l'écran. Un littéral juste
    // après l'un d'eux est un libellé qui a échappé au regroupement.
    final suspect = RegExp(
      r"""(Text\(|tooltip:|labelText:|helperText:|title:|subtitle:|label:|content:)\s*(const\s+)?'[^']{4,}'""",
    );

    final fautifs = <String>[];
    for (final fichier in Directory('lib/src/ui').listSync(recursive: true)) {
      if (fichier is! File || !fichier.path.endsWith('.dart')) continue;
      if (fichier.path.endsWith('labels.dart')) continue;

      final lignes = fichier.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        if (suspect.hasMatch(lignes[i])) {
          fautifs.add('${fichier.path}:${i + 1}  ${lignes[i].trim()}');
        }
      }
    }

    expect(
      fautifs,
      isEmpty,
      reason: 'Ces textes doivent rejoindre lib/src/ui/labels.dart :\n${fautifs.join('\n')}',
    );
  });

  test('labels.dart ne met rien en forme', () {
    // Le jour où un widget entre ici, le fichier cesse d'être lisible comme une
    // liste de textes, et devient un second endroit où l'interface se décide.
    final source = File('lib/src/ui/labels.dart').readAsStringSync();

    expect(
      source.contains('package:flutter/'),
      isFalse,
      reason: 'labels.dart ne doit pas importer Flutter : il ne décrit que des textes',
    );
    expect(source.contains('Widget'), isFalse);
  });
}
