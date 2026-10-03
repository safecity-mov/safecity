import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'src/app.dart';

void main() {
  // La carte est rendue dans un `TextureView` composé par Flutter, et non dans
  // le `GLSurfaceView` embarqué par Virtual Display que le plugin choisit par
  // défaut.
  //
  // En Virtual Display, la surface est perdue quand l'écran s'éteint : au
  // déverrouillage la carte reste figée sur sa dernière image, jusqu'à ce qu'un
  // aller-retour vers une autre app force la recréation de la vue. Les journaux
  // le disaient — `Creating virtual display: flutter-vd#0`, puis
  // `getUniqueId: Invalid operation on virtual display`.
  //
  // Le `TextureView` coûte un peu plus cher à dessiner. Une carte qui ne se
  // rafraîchit pas après un déverrouillage coûte davantage : à vélo, l'écran
  // s'éteint entre deux signalements.
  //
  // À assigner avant `runApp` : une carte déjà construite garde son mode.
  MapLibreMap.useHybridComposition = true;

  runApp(const App());
}
