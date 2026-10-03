import 'dart:async';
import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../config.dart';

/// Téléchargement du fond de carte pour un usage hors ligne (§10).
///
/// Le §10 réservait cela à la V2, en comptant sur le cache ambiant de MapLibre.
/// À l'usage ce cache tient une quarantaine de tuiles — trois ou quatre écrans —
/// et un trajet en sort immédiatement : les marqueurs flottaient sur du blanc.
/// Avancé en bêta, parce qu'un signalement posé sur un fond de carte vide n'est
/// pas un signalement qu'on peut ajuster à quelques mètres (§11.6).
///
/// Ce que le téléchargement embarque est **le même fond de carte que l'app**,
/// depuis la même instance : aucune donnée ne part vers un tiers, et rien de ce
/// qui est téléchargé ne dit où l'utilisateur va — c'est une zone qu'il choisit
/// sur une carte, pas un trajet observé (§11.1).
/// L'appel au plugin, isolé derrière un type pour être remplaçable en test.
///
/// Le comportement qui compte ici — quand ce téléchargement est-il fini — vient
/// entièrement du plugin, et s'est déjà avéré contre-intuitif une fois. Il doit
/// donc être vérifiable sans téléphone.
typedef DownloadRunner = Future<void> Function(
  OfflineRegionDefinition definition,
  Map<String, dynamic> metadata,
  void Function(DownloadRegionStatus) onEvent,
);

class OfflineMaps {
  const OfflineMaps({this.runner});

  /// `null` en production : le vrai plugin.
  final DownloadRunner? runner;

  /// Bornes du téléchargement.
  ///
  /// Au-delà de 15, les tuiles n'existent pas : le PMTiles s'y arrête et
  /// MapLibre sur-zoome. En deçà de 10, la carte ne charge plus de dangers
  /// (`minZoomToLoadHazards`), donc il n'y a rien à y faire hors ligne.
  static const minZoom = 10;
  static const maxZoom = 15;

  /// Taille moyenne d'une tuile de notre extrait, mesurée sur l'Île-de-France :
  /// 87 Ko au z15, 123 Ko au z13, 153 Ko au z10. Cent kilo-octets est une
  /// approximation honnête pour annoncer un ordre de grandeur avant de lancer.
  static const _averageTileBytes = 100 * 1024;

  /// Plafond de tuiles par téléchargement.
  ///
  /// Paris intra-muros pèse 424 tuiles ; la limite laisse de la marge pour la
  /// petite couronne sans permettre de lancer l'Île-de-France entière d'un
  /// geste, ce qui remplirait le téléphone sans prévenir.
  static const maxTiles = 5000;

  /// Nombre de tuiles couvrant une zone, tous zooms confondus.
  ///
  /// Le calcul est celui des tuiles Web Mercator, refait ici plutôt que demandé
  /// à MapLibre : il faut pouvoir annoncer la taille **avant** de lancer, et
  /// refuser une zone déraisonnable sans avoir commencé à télécharger.
  static int tileCount(LatLngBounds bounds) {
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final x0 = _tileX(bounds.southwest.longitude, z);
      final x1 = _tileX(bounds.northeast.longitude, z);
      // L'axe des tuiles descend vers le sud : le nord donne le plus petit y.
      final y0 = _tileY(bounds.northeast.latitude, z);
      final y1 = _tileY(bounds.southwest.latitude, z);
      total += ((x1 - x0).abs() + 1) * ((y1 - y0).abs() + 1);
    }
    return total;
  }

  /// Coût fixe du premier téléchargement : les glyphes de toutes les plages
  /// Unicode utilisées, plus le sprite. Mesuré à environ 5 Mo sur une zone de
  /// dix tuiles, où il pesait davantage que les tuiles elles-mêmes. L'annoncer
  /// évite de promettre 1 Mo et d'en écrire 6.
  static const _fixedAssetBytes = 5 * 1024 * 1024;

  static int estimatedBytes(LatLngBounds bounds) =>
      tileCount(bounds) * _averageTileBytes + _fixedAssetBytes;

  static int _tileX(double lon, int z) =>
      ((lon + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);

  static int _tileY(double lat, int z) {
    final r = lat * math.pi / 180;
    final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
    return (y * (1 << z)).floor().clamp(0, (1 << z) - 1);
  }

  /// Les zones déjà téléchargées.
  Future<List<OfflineRegion>> regions() => getListOfRegions();

  Future<void> remove(int id) async {
    await deleteOfflineRegion(id);
  }

  /// Télécharge une zone, en rendant compte de l'avancement.
  ///
  /// [onProgress] reçoit une fraction entre 0 et 1 et le nombre d'octets déjà
  /// écrits. La fonction se termine quand MapLibre a fini ou échoué.
  Future<void> download({
    required LatLngBounds bounds,
    required String name,
    required void Function(double fraction, int bytes) onProgress,
  }) async {
    await setOfflineTileCountLimit(maxTiles);

    final definition = OfflineRegionDefinition(
      bounds: bounds,
      mapStyleUrl: styleUrl,
      minZoom: minZoom.toDouble(),
      maxZoom: maxZoom.toDouble(),
    );

    // Le `Future` rendu par le plugin se termine dès que la **région est
    // créée**, pas quand le téléchargement est fini : la fin arrive plus tard,
    // en événement `Success`. S'en remettre à lui laissait la barre figée sur
    // son dernier pourcentage, et un second essai bloqué à 0 % — tout étant
    // déjà en cache, il ne restait plus aucun `progress` à émettre.
    final fini = Completer<void>();
    var derniersOctets = 0;

    await (runner ?? _run)(
      definition,
      {'name': name, 'createdAt': DateTime.now().toIso8601String()},
      (event) {
        switch (event) {
          case InProgress(:final progress, :final completedResourceSize):
            derniersOctets = completedResourceSize;
            onProgress(progress / 100, completedResourceSize);
          case Success():
            // 100 % explicitement : le compte de ressources annoncé par
            // MapLibre inclut les plages de glyphes idéographiques qu'il saute
            // ensuite, donc la progression plafonne sous 1 sans jamais
            // l'atteindre. Sans cette ligne, une zone complète s'afficherait
            // pour toujours « 87 % ».
            onProgress(1, derniersOctets);
            if (!fini.isCompleted) fini.complete();
          case Error(:final cause):
            if (!fini.isCompleted) fini.completeError(cause);
        }
      },
    );

    return fini.future;
  }

  static Future<void> _run(
    OfflineRegionDefinition definition,
    Map<String, dynamic> metadata,
    void Function(DownloadRegionStatus) onEvent,
  ) =>
      downloadOfflineRegion(definition, metadata: metadata, onEvent: onEvent);

  /// MapLibre télécharge une région à partir d'une **URL** de style, pas d'un
  /// contenu : il refuse un JSON en clair, un `file://` et un chemin nu
  /// (« Unable to parse resourceUrl »). L'instance le sert donc elle-même, sur
  /// la même origine que les tuiles — rien ne sort vers un tiers (§7, §11.5).
  ///
  /// Ce n'est pas le style que la carte affiche : celle-ci garde son asset, qui
  /// n'est pas négociable au runtime. Les deux viennent du même fichier, la
  /// copie servie étant produite par `tiles/fetch-assets.sh`.
  String get styleUrl => '${AppConfig.tilesBaseUrl}/style.json';
}
