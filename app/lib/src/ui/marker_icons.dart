import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/models/hazard.dart';
import '../data/models/hazard_type.dart';
import '../data/models/severity.dart';

/// Marqueurs de carte, dessinés à l'exécution plutôt que livrés en PNG.
///
/// Un marqueur porte **deux** informations redondantes avec la couleur, parce que
/// la couleur seule ne suffit pas (§9) : l'icône donne le type, le diamètre donne
/// le niveau. Un danger contesté est en outre creux plutôt que plein.
class MarkerIcons {
  const MarkerIcons._();

  /// Identifiant de l'image dans le style, et valeur de la propriété `icon` de
  /// chaque point de la source GeoJSON.
  static String nameFor({
    required String typeCode,
    required Severity severity,
    required bool disputed,
  }) =>
      '$typeCode-${severity.value}-${disputed ? 'disputed' : 'active'}';

  /// Toutes les combinaisons utiles : un type activé, trois niveaux, deux états.
  static Future<Map<String, Uint8List>> buildAll(
    List<HazardType> types, {
    double devicePixelRatio = 3,
  }) async {
    final images = <String, Uint8List>{};
    for (final type in types) {
      // Décodée une fois pour les six variantes du type, puis libérée : décoder
      // à chaque rendu multiplierait le travail par six sans rien changer.
      final silhouette = await _decode(type.iconPng);
      try {
        for (final severity in Severity.values) {
          for (final disputed in [false, true]) {
            images[nameFor(typeCode: type.code, severity: severity, disputed: disputed)] =
                await _render(
              icon: type.icon,
              silhouette: silhouette,
              severity: severity,
              disputed: disputed,
              devicePixelRatio: devicePixelRatio,
            );
          }
        }
      } finally {
        silhouette?.dispose();
      }
    }
    return images;
  }

  /// Décode une silhouette téléversée, ou rend `null` si elle est illisible.
  ///
  /// Une image abîmée ne doit pas vider la carte : le glyphe embarqué reprend
  /// simplement la main, et le danger reste visible.
  static Future<ui.Image?> _decode(Uint8List? png) async {
    if (png == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Exception {
      return null;
    }
  }

  static Future<Uint8List> _render({
    required IconData icon,
    required ui.Image? silhouette,
    required Severity severity,
    required bool disputed,
    required double devicePixelRatio,
  }) async {
    final radius = severity.markerRadius;
    final size = (radius + 3) * 2;
    final scaled = size * devicePixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(devicePixelRatio);

    final center = Offset(size / 2, size / 2);
    final fill = disputed ? Colors.white : severity.color;
    final stroke = disputed ? severity.color.withValues(alpha: 0.75) : Colors.white;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(center, radius, Paint()..color = fill);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = disputed ? 2.5 : 2
        ..color = stroke,
    );

    final encre = disputed ? severity.color : Colors.white;

    if (silhouette != null) {
      // Seul le canal alpha sert : `srcIn` remplace la couleur du fichier par
      // l'encre du marqueur. C'est ce qui permet à la silhouette de s'inverser
      // quand le danger est contesté, ce qu'une image en couleurs ne ferait pas.
      final cote = radius * 1.3;
      canvas.drawImageRect(
        silhouette,
        Rect.fromLTWH(0, 0, silhouette.width.toDouble(), silhouette.height.toDouble()),
        Rect.fromCenter(center: center, width: cote, height: cote),
        Paint()
          ..colorFilter = ColorFilter.mode(encre, BlendMode.srcIn)
          ..filterQuality = FilterQuality.medium,
      );
    } else {
      final glyph = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: radius * 1.15,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: encre,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      glyph.paint(canvas, center - Offset(glyph.width / 2, glyph.height / 2));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(scaled.ceil(), scaled.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    // `toByteData` rend null quand l'encodage échoue : mieux vaut une erreur
    // qui dit laquelle qu'un `!` qui parle de null.
    if (bytes == null) throw StateError('encodage PNG du marqueur impossible');
    return bytes.buffer.asUint8List();
  }
}

/// La source GeoJSON que consomme la carte.
///
/// Chaque point porte le nom de son image de marqueur, calculé ici : le style ne
/// contient aucune logique métier.
Map<String, dynamic> hazardsToGeoJson(Iterable<Hazard> hazards) => {
      'type': 'FeatureCollection',
      'features': [
        for (final hazard in hazards)
          {
            'type': 'Feature',
            'id': hazard.id,
            'geometry': {
              'type': 'Point',
              'coordinates': [hazard.lng, hazard.lat],
            },
            'properties': {
              'id': hazard.id,
              'icon': MarkerIcons.nameFor(
                typeCode: hazard.type,
                severity: hazard.severity,
                disputed: hazard.status.isDisputed,
              ),
            },
          },
      ],
    };
