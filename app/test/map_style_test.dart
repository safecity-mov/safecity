import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le fond de carte est une donnée, pas du code : rien ne le compile, rien ne
/// le relit. Deux fautes y sont passées inaperçues jusqu'à ce qu'on regarde le
/// Canal Saint-Martin — d'où ces garde-fous.
void main() {
  final style = jsonDecode(File('assets/map_style.json').readAsStringSync())
      as Map<String, dynamic>;
  final layers = (style['layers'] as List<dynamic>).cast<Map<String, dynamic>>();
  final fontsDir = Directory('../server/tiles/data/fonts');

  /// Les couches du schéma Protomaps basemap v4. `physical_line` n'en fait pas
  /// partie : les axes des cours d'eau vivent dans `water`, en LineString.
  const knownSourceLayers = {
    'earth',
    'landuse',
    'water',
    'buildings',
    'roads',
    'transit',
    'pois',
    'places',
    'boundaries',
  };

  group('map_style.json', () {
    test('ne vise que des couches qui existent dans les tuiles', () {
      for (final layer in layers) {
        final sourceLayer = layer['source-layer'] as String?;
        if (sourceLayer == null) continue; // background
        expect(
          knownSourceLayers,
          contains(sourceLayer),
          reason: 'La couche "${layer['id']}" vise "$sourceLayer", absent des '
              'tuiles : elle ne dessinerait rien.',
        );
      }
    });

    test('ne remplit que des polygones', () {
      // `water` mêle polygones d'eau, axes de cours d'eau et ancres de libellé.
      // Un calque `fill` sans filtre referme les LineString sur elles-mêmes :
      // le Canal Saint-Martin devenait un coin de 2,7 km² sur le 10e.
      for (final layer in layers.where((l) => l['type'] == 'fill')) {
        expect(
          jsonEncode(layer['filter']),
          contains('"Polygon"'),
          reason: 'Le calque "${layer['id']}" remplit tout ce qu\'il trouve, '
              'y compris les géométries qui ne sont pas des polygones.',
        );
      }
    });

    test('déclare les polices qu\'il utilise de façon récupérable', () {
      // fetch-assets.sh dérive la liste des polices à télécharger de ce
      // fichier. Une police absente du serveur fait taire TOUS les libellés.
      if (!fontsDir.existsSync()) {
        markTestSkipped('Tuiles non téléchargées sur cette machine.');
        return;
      }
      final fonts = <String>{};
      for (final layer in layers) {
        final layout = layer['layout'] as Map<String, dynamic>?;
        for (final font in (layout?['text-font'] as List<dynamic>?) ?? const []) {
          fonts.add(font as String);
        }
      }
      expect(fonts, isNotEmpty);
      for (final font in fonts) {
        expect(
          Directory('${fontsDir.path}/$font').existsSync(),
          isTrue,
          reason: 'La police "$font" est demandée par le style mais absente de '
              'server/tiles/data/fonts. Relancer fetch-assets.sh.',
        );
      }
    });
  });
}
