import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/data/models/severity.dart';
import 'package:app/src/ui/marker_icons.dart';

/// Un PNG 64 × 64 : disque blanc opaque sur fond transparent, tel que la console
/// en accepte (§4.3). Seul son canal alpha compte.
const _silhouette =
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAmElEQVR42u3awRHEIAwEQfJPWk7B5TIg2J4Mtl93RmNIkrSkelnc4OtAalKxw9tD1Kaix7dAqCZFj9+CUE2LHr8EoQ4pevw0hGiAOjQAyeN/Q4gGqEsCAABA7vjPCAAAAAAAAAAAAH4N+i8AAICvQr4JBgN4FwDgaQyA53EHEk5kHEk5k3Mo6VTWsbRz+U0Q45biBkuSmvcAc6YgsCodK1MAAAAASUVORK5CYII=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('silhouette téléversée', () {
    test('remplace le glyphe embarqué dans le marqueur', () async {
      final sans = await MarkerIcons.buildAll([_type()], devicePixelRatio: 1);
      final avec = await MarkerIcons.buildAll(
        [_type(png: base64Decode(_silhouette))],
        devicePixelRatio: 1,
      );

      final nom = MarkerIcons.nameFor(
        typeCode: 'pothole',
        severity: Severity.dangerous,
        disputed: false,
      );
      expect(sans[nom], isNotNull);
      expect(avec[nom], isNotNull);
      expect(
        avec[nom],
        isNot(equals(sans[nom])),
        reason: 'le marqueur doit changer, sinon l\'image téléversée ne sert à rien',
      );
    });

    test('une image illisible retombe sur le glyphe plutôt que de vider la carte', () async {
      final sans = await MarkerIcons.buildAll([_type()], devicePixelRatio: 1);
      final abime = await MarkerIcons.buildAll(
        [
          _type(png: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8, 9])),
        ],
        devicePixelRatio: 1,
      );

      final nom = MarkerIcons.nameFor(
        typeCode: 'pothole',
        severity: Severity.dangerous,
        disputed: false,
      );
      expect(abime[nom], equals(sans[nom]));
    });

    test('couvre les six variantes de chaque type, silhouette comprise', () async {
      final images = await MarkerIcons.buildAll(
        [_type(png: base64Decode(_silhouette))],
        devicePixelRatio: 1,
      );
      // Trois gravités × deux états (§9).
      expect(images, hasLength(6));
    });

    test('le marqueur contesté n\'est pas le même que l\'actif', () async {
      // La silhouette s'inverse avec l'état : c'est ce que permet de ne peindre
      // que le canal alpha, et ce qu'une image en couleurs interdirait.
      final images = await MarkerIcons.buildAll(
        [_type(png: base64Decode(_silhouette))],
        devicePixelRatio: 1,
      );
      final actif = images[
          MarkerIcons.nameFor(typeCode: 'pothole', severity: Severity.dangerous, disputed: false)];
      final conteste = images[
          MarkerIcons.nameFor(typeCode: 'pothole', severity: Severity.dangerous, disputed: true)];

      expect(conteste, isNot(equals(actif)));
    });
  });

  group('iconWidget', () {
    testWidgets('dessine l\'image téléversée quand elle existe', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: _type(png: base64Decode(_silhouette)).iconWidget()),
        ),
      );

      expect(find.byType(ImageIcon), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('et le glyphe embarqué sinon', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _type().iconWidget())));

      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(ImageIcon), findsNothing);
    });
  });
}

HazardType _type({Uint8List? png}) => HazardType(
      code: 'pothole',
      label: 'Nid-de-poule',
      iconName: 'pothole',
      resolvedLabel: 'Réparé',
      dedupRadiusM: 15,
      enabled: true,
      sortOrder: 10,
      iconPng: png,
    );
