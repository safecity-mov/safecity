import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:app/src/data/offline_maps.dart';
import 'package:app/src/ui/offline_maps_sheet.dart';
import 'package:app/src/ui/labels.dart';

void main() {
  group('OfflineMaps.tileCount', () {
    test('chiffre Paris intra-muros dans l\'ordre de grandeur mesuré', () {
      // 424 tuiles du zoom 10 au 15, comptées sur le serveur de tuiles. Le
      // calcul doit tomber dessus : c'est lui qui annonce la taille à
      // l'utilisateur avant qu'il ne lance un téléchargement.
      final paris = LatLngBounds(
        southwest: const LatLng(48.815, 2.224),
        northeast: const LatLng(48.902, 2.470),
      );

      expect(OfflineMaps.tileCount(paris), closeTo(424, 20));
    });

    test('grandit avec la zone', () {
      final petite = LatLngBounds(
        southwest: const LatLng(48.85, 2.34),
        northeast: const LatLng(48.86, 2.36),
      );
      final grande = LatLngBounds(
        southwest: const LatLng(48.70, 2.10),
        northeast: const LatLng(49.00, 2.60),
      );

      expect(OfflineMaps.tileCount(grande), greaterThan(OfflineMaps.tileCount(petite)));
    });

    test('compte au moins une tuile par niveau, même sur un point', () {
      // Une zone réduite à un point reste six niveaux de zoom : refuser zéro
      // évite d'annoncer « 0 Mo » puis de télécharger quelque chose.
      final point = LatLngBounds(
        southwest: const LatLng(48.8566, 2.3522),
        northeast: const LatLng(48.8566, 2.3522),
      );

      expect(OfflineMaps.tileCount(point), OfflineMaps.maxZoom - OfflineMaps.minZoom + 1);
    });

    test('refuse l\'Île-de-France entière par le plafond', () {
      // Personne ne doit pouvoir remplir son téléphone d'un geste : le plafond
      // laisse passer la petite couronne, pas la région.
      final idf = LatLngBounds(
        southwest: const LatLng(48.12, 1.4462),
        northeast: const LatLng(49.2413, 3.5592),
      );

      expect(OfflineMaps.tileCount(idf), greaterThan(OfflineMaps.maxTiles));
    });

    test('s\'arrête au zoom où les tuiles existent', () {
      // Au-delà de 15 le PMTiles n'a rien : télécharger plus loin ne
      // rapporterait que des 404 (§7).
      expect(OfflineMaps.maxZoom, 15);
    });
  });

  group('OfflineMaps.estimatedBytes', () {
    test('compte les polices, pas seulement les tuiles', () {
      // Une zone de dix tuiles a pesé 6 Mo à l'usage, dont l'essentiel en
      // glyphes : annoncer 1 Mo puis en écrire 6 ferait douter du reste.
      final petite = LatLngBounds(
        southwest: const LatLng(48.8560, 2.3500),
        northeast: const LatLng(48.8624, 2.3544),
      );

      expect(OfflineMaps.estimatedBytes(petite), greaterThan(4 * 1024 * 1024));
    });
  });

  group('formatBytes', () {
    test('rend des ordres de grandeur décidables', () {
      expect(formatBytes(512), '512 o');
      expect(formatBytes(2048), '2 Ko');
      expect(formatBytes(44 * 1024 * 1024), '44 Mo');
      expect(formatBytes(9 * 1024 * 1024 * 1024), '9.0 Go');
    });
  });

  group('fin du téléchargement', () {
    // Le plugin rend la main dès que la région est créée. Tout ce qui suit
    // vérifie qu'on ne s'y fie pas : ce qui termine, c'est `Success`.

    // `download()` commence par poser le plafond de tuiles, un appel natif. Sans
    // ce faux canal, il ne rendrait jamais la main et rien ne démarrerait.
    const canal = MethodChannel('plugins.flutter.io/maplibre_gl');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, (_) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, null);
    });

    test('ne se termine pas tant que Success n\'est pas arrivé', () async {
      late void Function(DownloadRegionStatus) emettre;
      final maps = OfflineMaps(
        runner: (_, __, onEvent) async => emettre = onEvent,
      );

      var termine = false;
      final futur = maps
          .download(bounds: _zone, name: 'essai', onProgress: (_, __) {})
          .then((_) => termine = true);

      // Le plugin a rendu la main, et pourtant rien n'est fini.
      await pumpEventQueue();
      emettre(InProgress(87, completedResourceSize: 1000));
      await pumpEventQueue();
      expect(termine, isFalse, reason: 'la progression seule ne termine rien');

      emettre(Success());
      await futur;
      expect(termine, isTrue);
    });

    test('annonce 100 % à la fin, même si MapLibre plafonne plus bas', () async {
      // Le compte de ressources annoncé inclut des plages de glyphes que
      // MapLibre saute ensuite : la progression n'atteint jamais 1 toute seule.
      late void Function(DownloadRegionStatus) emettre;
      final maps = OfflineMaps(runner: (_, __, onEvent) async => emettre = onEvent);

      final vus = <double>[];
      final futur = maps.download(
        bounds: _zone,
        name: 'essai',
        onProgress: (fraction, _) => vus.add(fraction),
      );

      await pumpEventQueue();
      emettre(InProgress(87, completedResourceSize: 1000));
      emettre(Success());
      await futur;

      expect(vus.first, closeTo(0.87, 0.001), reason: 'la fraction est ramenée de 0-100 à 0-1');
      expect(vus.last, 1);
    });

    test('un second téléchargement déjà en cache se termine quand même', () async {
      // Tout étant déjà sur l'appareil, MapLibre n'a plus rien à signaler : il
      // passe directement à Success. C'est ce cas qui laissait la barre à 0 %.
      late void Function(DownloadRegionStatus) emettre;
      final maps = OfflineMaps(runner: (_, __, onEvent) async => emettre = onEvent);

      var derniere = -1.0;
      final futur = maps.download(
        bounds: _zone,
        name: 'essai',
        onProgress: (fraction, _) => derniere = fraction,
      );

      await pumpEventQueue();
      emettre(Success());
      await futur;

      expect(derniere, 1);
    });

    test('remonte l\'échec plutôt que de le taire', () async {
      late void Function(DownloadRegionStatus) emettre;
      final maps = OfflineMaps(runner: (_, __, onEvent) async => emettre = onEvent);

      final futur = maps.download(bounds: _zone, name: 'essai', onProgress: (_, __) {});
      await pumpEventQueue();
      emettre(Error(PlatformException(code: 'plein', message: 'disque plein')));

      await expectLater(futur, throwsA(isA<PlatformException>()));
    });
  });

  group('OfflineMapsSheet', () {
    testWidgets('dit l\'étendue de la zone, pas la coordonnée de son centre',
        (tester) async {
      // La coordonnée du centre ne répondait à aucune question : on sait déjà où
      // on est par le nom de la voie. L'étendue répond à la vraie — « est-ce que
      // ça couvre mon trajet » — et c'était la seule donnée de l'écran qui
      // concerne la personne plutôt que la voirie.
      await tester.pumpWidget(
        _hote(zones: [_zoneEmbarquee(_large, 'Boulevard Voltaire')], visible: _petite),
      );
      await tester.pumpAndSettle();

      expect(find.text('Boulevard Voltaire'), findsOneWidget);
      expect(find.textContaining('×'), findsOneWidget);
      expect(find.textContaining('autour de'), findsNothing);
      expect(find.textContaining('48.8'), findsNothing);
    });

    testWidgets('ne propose plus de télécharger une zone déjà couverte', (tester) async {
      await tester.pumpWidget(
        _hote(zones: [_zoneEmbarquee(_large, 'Boulevard Voltaire')], visible: _petite),
      );
      await tester.pumpAndSettle();

      expect(find.text(OfflineLabels.alreadyDownloaded), findsOneWidget);
      final bouton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(bouton.onPressed, isNull);
    });

    testWidgets('mais le propose pour une zone qui déborde de ce qui est embarqué',
        (tester) async {
      // L'inclusion, pas l'égalité : une zone plus large couvre celle-ci, une
      // plus petite non.
      await tester.pumpWidget(
        _hote(zones: [_zoneEmbarquee(_petite, 'Rue Antoine Vollon')], visible: _large),
      );
      await tester.pumpAndSettle();

      expect(find.text(OfflineLabels.download), findsOneWidget);
      final bouton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(bouton.onPressed, isNotNull);
    });
  });
}

final _petite = LatLngBounds(
  southwest: const LatLng(48.855, 2.375),
  northeast: const LatLng(48.860, 2.385),
);
final _large = LatLngBounds(
  southwest: const LatLng(48.840, 2.350),
  northeast: const LatLng(48.880, 2.410),
);

OfflineRegion _zoneEmbarquee(LatLngBounds bounds, String nom) => OfflineRegion(
      id: 1,
      definition: OfflineRegionDefinition(
        bounds: bounds,
        mapStyleUrl: 'http://test/style.json',
        minZoom: 10,
        maxZoom: 15,
      ),
      metadata: {'name': nom},
    );

Widget _hote({required List<OfflineRegion> zones, required LatLngBounds visible}) =>
    MaterialApp(
      home: Scaffold(
        body: OfflineMapsSheet(maps: _FausseCarte(zones), visible: visible),
      ),
    );

class _FausseCarte extends OfflineMaps {
  const _FausseCarte(this.zones);

  final List<OfflineRegion> zones;

  @override
  Future<List<OfflineRegion>> regions() async => zones;
}

final _zone = LatLngBounds(
  southwest: const LatLng(48.85, 2.34),
  northeast: const LatLng(48.86, 2.36),
);
