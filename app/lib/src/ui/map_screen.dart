import 'dart:async';
import 'dart:math' show Point, pi;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../config.dart';
import '../data/api_client.dart';
import '../data/announcements.dart';
import '../data/app_update.dart';
import '../data/device_identity.dart';
import '../data/beta_measurements.dart';
import '../data/hazard_repository.dart';
import '../data/models/hazard.dart';
import '../data/models/hazard_type.dart';
import '../location/location_service.dart';
import '../data/offline_maps.dart';
import 'gesture_feedback.dart';
import 'gesture_timer.dart';
import 'hazard_detail_sheet.dart';
import 'hazard_merge.dart';
import 'offline_maps_sheet.dart';
import 'labels.dart';
import 'marker_icons.dart';
import 'street_lookup.dart';
import 'report_sheet.dart';
import 'settings_screen.dart';
import 'widgets/map_chrome.dart';
import 'widgets/map_filters.dart';

/// L'écran principal, et le seul (§9).
///
/// Trois modes : consultation, placement d'un pin, et envoi. Le mode placement
/// existe parce que le GPS grand public donne 5 à 15 m en ville dense : c'est le
/// pin déplacé à la main qui porte la précision réelle, pas le capteur (§11.6).
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.repo,
    required this.device,
    required this.location,
    required this.types,
    required this.mapStyle,
    this.updates,
    this.announcements,
    this.mapBuilder,
  });

  final HazardRepository repo;
  final DeviceIdentity device;
  final LocationService location;
  final List<HazardType> types;
  final String mapStyle;

  /// Demande au serveur s'il existe une version plus récente (§12.6). Nul, on
  /// ne demande rien : c'est le cas des tests qui ne s'y intéressent pas.
  final UpdateChecker? updates;

  /// Demande au serveur s'il a quelque chose à dire (§4.3 amendé) : une annonce
  /// écrite depuis la console. Mêmes moments que [updates], et nul, on ne
  /// demande rien.
  final AnnouncementChecker? announcements;

  /// Fabrique la vue de carte. Nulle en production : c'est `MapLibreMap`.
  ///
  /// Point d'entrée de test, et il est là pour une raison précise. Le plugin
  /// garde son canal natif dans un champ `late`, initialisé seulement quand une
  /// vue native lui répond. Un test n'en a pas : détruire une carte qui n'en a
  /// jamais reçu fait échouer la destruction, et laisse derrière un arbre à
  /// moitié défait dont les restes perturbent les tests suivants.
  ///
  /// C'est la seule chose de cet écran qu'un test ait besoin de remplacer. Le
  /// reste — mode placement, bandeaux, outils, retours de geste — se vérifie tel
  /// quel, et c'est là que vivaient les défauts relevés par l'audit.
  @visibleForTesting
  final WidgetBuilder? mapBuilder;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  MapLibreMapController? _controller;
  StreamSubscription<DevicePosition>? _positionSub;

  final _hazards = <String, Hazard>{};

  /// Le catalogue vivant. Celui du widget est celui du démarrage ; à chaque
  /// retour au premier plan on redemande au serveur, et s'il a changé — un type
  /// activé depuis la console (§3) — la carte et la feuille de signalement
  /// suivent sans que l'app ait à être fermée puis rouverte.
  late List<HazardType> _types = widget.types;
  MapFilters _filters = const MapFilters();

  StreamSubscription<int>? _pendingSub;
  int _pending = 0;

  /// Hors ligne, sur une zone que le cache n'a jamais vue.
  bool _blind = false;

  /// Ce que le serveur annonce de plus récent que cette app, s'il y a lieu.
  /// Une fois le téléchargement lancé, le bandeau s'efface pour cette version :
  /// la personne a fait ce qu'on lui demandait, le reste appartient à Android.
  /// Ne pas installer est son choix, on ne le lui rappelle pas. Mais si une
  /// version plus récente encore est publiée pendant que l'app tourne, elle est
  /// à nouveau annoncée : c'est une autre nouvelle.
  AppUpdate? _update;
  int? _openedCode;

  /// L'annonce de l'équipe à montrer, s'il y en a une. Elle s'efface au toucher,
  /// quand le serveur ne l'annonce plus, ou à sa date de fin ; un serveur
  /// injoignable ne la fait pas disparaître.
  Announcement? _announcement;

  bool _placing = false;
  bool _busy = false;
  bool _styleReady = false;
  double _zoom = AppConfig.defaultZoom;

  /// Orientation de la carte, en degrés dans le sens horaire depuis le nord.
  /// Zéro tant qu'on n'a pas tourné la carte : la boussole reste cachée.
  double _bearing = 0;

  Timer? _reloadDebounce;

  /// Numéro du dernier rechargement lancé. Une réponse peut mettre quinze
  /// secondes à arriver ; entre-temps un geste a pu être appliqué, ou un autre
  /// rechargement a pu répondre. Une réponse dont le numéro n'est plus le
  /// dernier est périmée, et ne doit pas écraser un état plus récent.
  int _reloadSeq = 0;

  /// Chronomètre du geste en cours, de l'entrée en mode placement à la réponse
  /// du serveur (§4.6). Sa règle vit dans `GestureTimer` : démarrer par les deux
  /// chemins d'entrée, s'annuler avec le placement, ne se relever qu'une fois.
  final _gesture = GestureTimer();

  static const _sourceId = 'hazards';
  static const _positionSource = 'user-position';
  static const _positionHalo = 'user-position-halo';
  static const _positionDot = 'user-position-dot';
  static const _markersLayer = 'hazard-markers';
  static const _clustersLayer = 'hazard-clusters';
  static const _clusterCountLayer = 'hazard-cluster-count';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingSub = widget.repo.pendingChanges.listen((count) {
      if (!mounted) return;
      // La file a avancé d'elle-même (minuteur du dépôt) : ce que le serveur a
      // accepté porte maintenant un vrai identifiant, et le marqueur provisoire
      // n'a plus lieu d'être. Le prochain rechargement l'élague.
      if (count < _pending) _scheduleReload();
      setState(() => _pending = count);
    });
    unawaited(_checkForUpdate());
    unawaited(_checkAnnouncement());
  }

  /// Mêmes moments que la mise à jour, même silence en cas d'échec. Un
  /// « rien d'annoncé » efface le bandeau : l'annonce a été retirée ou a pris
  /// fin. Un serveur injoignable ne change rien.
  Future<void> _checkAnnouncement() async {
    final checker = widget.announcements;
    if (checker == null) return;
    final result = await checker.check();
    if (!mounted) return;
    switch (result) {
      case Announced(:final announcement):
        setState(() => _announcement = announcement);
      case NothingAnnounced():
        setState(() => _announcement = null);
      case AnnouncementsUnavailable():
        break;
    }
  }

  /// Toucher le bandeau, c'est dire « lu » : il s'efface, et ne revient pas
  /// pour cette annonce-là.
  Future<void> _dismissAnnouncement() async {
    final announcement = _announcement;
    if (announcement == null) return;
    setState(() => _announcement = null);
    await widget.announcements?.dismiss(announcement);
  }

  /// Au lancement et à chaque retour au premier plan, et rien si la réponse
  /// n'arrive pas : une mise à jour qu'on n'annonce pas n'est pas une panne, la
  /// carte n'attend pas après.
  Future<void> _checkForUpdate() async {
    final checker = widget.updates;
    if (checker == null) return;
    final update = await checker.check();
    if (!mounted || update == null) return;
    setState(() => _update = update);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    unawaited(_pendingSub?.cancel());
    _stopFollowing();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Le suivi ne tourne que pendant que la carte est à l'écran : quitter l'app
  /// coupe le capteur, et aucune permission d'arrière-plan n'est déclarée (§11.1).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startFollowing();
      // Revenir sur l'app est le moment le plus probable d'avoir retrouvé du
      // réseau. La file réessaie aussi toute seule, mais plus lentement.
      unawaited(_flush());
      // Et le moment où le monde a pu changer sans nous : un type activé depuis
      // la console, une version publiée. Deux requêtes légères, vers notre
      // serveur seulement, qui ne portent rien (§11.5).
      unawaited(_refreshTypes());
      unawaited(_checkForUpdate());
      unawaited(_checkAnnouncement());
    } else {
      _stopFollowing();
      // `inactive` couvre aussi l'ouverture d'une boîte de dialogue système —
      // la demande de permission, typiquement. Oublier la position à ce
      // moment-là rouvrirait une attente de fix au retour, et c'est exactement
      // ce qui rendait un signalement long (§4.6).
      if (state != AppLifecycleState.inactive) widget.location.forget();
    }
  }

  /// Vide la file et rend compte. Silencieux quand il n'y avait rien à envoyer :
  /// c'est le cas courant, et un message à chaque retour sur l'app serait du
  /// bruit.
  Future<void> _flush() async {
    final DrainReport report;
    try {
      report = await widget.repo.drain();
      // Même raison que dans `_reload` : appelé sans être attendu au retour au
      // premier plan, ce vidage laisserait filer une `Error` de décodage.
    } on Object catch (error) {
      _showError(error);
      return;
    }
    if (!mounted || !report.changedSomething) return;
    await _reload();
    if (!mounted) return;
    final parts = [
      if (report.sent > 0) MapLabels.flushSent(report.sent),
      if (report.refused > 0) MapLabels.flushRefused(report.refused),
    ];
    _showMessage('${parts.join(', ')}.');
  }

  /// Lecture de position sur un geste d'intention.
  ///
  /// Elle peut ouvrir le dialogue système, et surtout elle relance le suivi
  /// quand la permission vient d'être rendue. Sans cela, un utilisateur qui
  /// accorde la position « une seule fois » — usage courant, et Android la
  /// révoque à chaque passage en arrière-plan — se retrouve avec un indicateur
  /// figé et une lecture ponctuelle à chaque geste, pour toute la session.
  Future<DevicePosition?> _readPosition() async {
    final position = await widget.location.currentPosition(mayAsk: true);
    if (!mounted || position == null) return position;
    _startFollowing();
    await _showPosition(position);
    return position;
  }

  void _startFollowing() {
    if (_positionSub != null) return;
    _positionSub = widget.location.positions.listen(
      (position) => unawaited(_showPosition(position)),
      // Capteur coupé, permission retirée en cours de route : l'indicateur
      // s'arrête, la carte continue de fonctionner.
      onError: (Object _) => _stopFollowing(),
    );
  }

  void _stopFollowing() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  HazardType _typeFor(String code) => _types.firstWhere(
        (t) => t.code == code,
        // Un type retiré du catalogue ne doit pas faire disparaître un écran.
        orElse: () => _types.first,
      );

  // --- Carte ---------------------------------------------------------------

  /// Les marqueurs sont dessinés ici, pas livrés en assets : un fichier PNG par
  /// type et par niveau serait à regénérer à chaque ajout de type. Rappelé
  /// quand le catalogue change : `addImage` remplace une image du même nom.
  Future<void> _registerIcons(MapLibreMapController controller) async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final icons = await MarkerIcons.buildAll(_types, devicePixelRatio: ratio);
    for (final entry in icons.entries) {
      await controller.addImage(entry.key, entry.value);
    }
  }

  /// Redemande le catalogue au serveur, et ne touche à rien s'il est le même
  /// ou si le serveur ne répond pas : le dépôt sert alors sa copie locale, qui
  /// est déjà celle qu'on affiche.
  Future<void> _refreshTypes() async {
    List<HazardType> fresh;
    try {
      fresh = await _fetchTypes();
    } on Object {
      return;
    }
    if (!mounted || _signature(fresh) == _signature(_types)) return;
    setState(() => _types = fresh);
    final controller = _controller;
    if (controller != null && _styleReady) {
      await _registerIcons(controller);
      await _pushToMap();
    }
  }

  Future<List<HazardType>> _fetchTypes() => widget.repo.types();

  static String _signature(List<HazardType> types) => [
        for (final t in types)
          '${t.code}|${t.label}|${t.iconName}|${t.resolvedLabel}|${t.dedupRadiusM}|'
              '${t.enabled}|${t.sortOrder}|${t.iconPng?.length}',
      ].join('\n');

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;

    await _registerIcons(controller);

    await controller.addSource(
      _sourceId,
      GeojsonSourceProperties(
        data: hazardsToGeoJson(const []),
        cluster: true,
        clusterMaxZoom: 13,
        clusterRadius: 48,
      ),
    );

    await controller.addCircleLayer(
      _sourceId,
      _clustersLayer,
      CircleLayerProperties(
        circleColor: '#1F5673',
        circleOpacity: 0.9,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
        circleRadius: [
          'step',
          ['get', 'point_count'],
          16,
          10,
          21,
          50,
          27,
        ],
      ),
      filter: ['has', 'point_count'],
    );

    await controller.addSymbolLayer(
      _sourceId,
      _clusterCountLayer,
      const SymbolLayerProperties(
        textField: ['get', 'point_count_abbreviated'],
        textFont: ['Noto Sans Medium'],
        textSize: 13,
        textColor: '#FFFFFF',
        textAllowOverlap: true,
      ),
      filter: ['has', 'point_count'],
    );

    await controller.addSymbolLayer(
      _sourceId,
      _markersLayer,
      const SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconSize: 1,
        iconAllowOverlap: true,
        iconAnchor: 'center',
      ),
      filter: [
        '!',
        ['has', 'point_count'],
      ],
    );

    // Indicateur de position, dessiné par nous.
    //
    // `myLocationEnabled` de MapLibre activerait son LocationComponent, qui
    // passe par les Google Play Services : exclu par la contrainte F-Droid
    // (§12.6). Deux cercles suffisent, alimentés par le canal natif.
    //
    // Le point suit l'utilisateur tant que la carte est au premier plan
    // (`_startFollowing`). Le suivi s'arrête dès que l'app le quitte, et aucune
    // permission d'arrière-plan n'est déclarée : la position alimente
    // l'indicateur et pèse les gestes, elle n'est ni écrite, ni mise en cache
    // sur le disque (§11.1).
    await controller.addSource(
      _positionSource,
      const GeojsonSourceProperties(
        data: {'type': 'FeatureCollection', 'features': []},
      ),
    );
    await controller.addCircleLayer(
      _positionSource,
      _positionHalo,
      const CircleLayerProperties(
        circleColor: '#1F5673',
        circleOpacity: 0.15,
        circleRadius: 22,
      ),
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _positionSource,
      _positionDot,
      const CircleLayerProperties(
        circleColor: '#1F5673',
        circleRadius: 7,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
      enableInteraction: false,
    );

    if (!mounted) return;
    setState(() => _styleReady = true);
    _startFollowing();
    await _reload();
    unawaited(_recenterOnUser(silent: true));
  }

  /// Recharge les dangers de la zone visible. Debouncé : un déplacement de carte
  /// génère des dizaines d'événements de caméra.
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;
    if (_zoom < AppConfig.minZoomToLoadHazards) return;

    final seq = ++_reloadSeq;
    try {
      final bounds = await controller.getVisibleRegion();
      final view = await widget.repo.hazardsInBbox(
        minLng: bounds.southwest.longitude,
        minLat: bounds.southwest.latitude,
        maxLng: bounds.northeast.longitude,
        maxLat: bounds.northeast.latitude,
        types: _filters.types.isEmpty ? null : _filters.types.toList(),
        minSeverity: _filters.minSeverity?.value,
      );

      // Périmée : un geste a été appliqué, ou un rechargement plus récent a
      // déjà répondu. L'appliquer remettrait un ancien statut par-dessus.
      if (!mounted || seq != _reloadSeq) return;

      // Fusion : repasser sur une zone déjà vue ne fait pas clignoter les
      // marqueurs, mais ce que le serveur ne renvoie plus dans la zone en sort.
      final merged = mergeHazards(
        current: _hazards,
        fetched: view.hazards,
        bbox: (
          minLat: bounds.southwest.latitude,
          minLng: bounds.southwest.longitude,
          maxLat: bounds.northeast.latitude,
          maxLng: bounds.northeast.longitude,
        ),
        // Une réponse tronquée ne dit rien de ce qu'elle a laissé dehors :
        // élaguer sur sa foi effacerait des dangers bien réels (§10).
        authoritative: !view.fromCache && !view.truncated,
      );
      _hazards
        ..clear()
        ..addAll(merged);
      // Hors ligne sur une zone jamais chargée, l'absence de marqueur ne veut
      // rien dire. Le taire laisserait lire « pas de danger ici » (§10).
      if (_blind != view.isBlind) setState(() => _blind = view.isBlind);
      await _pushToMap();
      // `Object` et non `Exception` : le décodage d'un danger fait des casts, et
      // un champ que le serveur renommerait lèverait un `TypeError`, qui est une
      // `Error`. Personne n'attend ce `Future` — il part d'un minuteur — donc
      // l'erreur filerait dans la zone : pas de message, pas de trace, une carte
      // qui se fige. C'est le mode de panne le plus pénible à diagnostiquer.
    } on Object catch (error) {
      _showError(error);
    }
  }

  /// Un geste vient d'être appliqué : ce que la carte affiche est plus récent
  /// que tout rechargement encore en vol, qui ne doit plus l'écraser.
  void _supersedeReloads() => _reloadSeq++;

  Future<void> _pushToMap() async {
    await _controller?.setGeoJsonSource(_sourceId, hazardsToGeoJson(_hazards.values));
  }

  /// Place l'indicateur de position au dernier point lu. La position n'est
  /// affichée que si on vient de la lire : elle n'est ni suivie ni conservée.
  Future<void> _showPosition(DevicePosition? position) async {
    if (position == null || !_styleReady) return;
    await _controller?.setGeoJsonSource(_positionSource, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [position.lng, position.lat],
          },
          'properties': const <String, dynamic>{},
        },
      ],
    });
  }

  Future<void> _recenterOnUser({bool silent = false}) async {
    // Le suivi alimente déjà le cache : recentrer doit être immédiat, pas
    // rouvrir une attente de fix de dix secondes.
    // `silent` distingue le recentrage automatique du lancement de l'appui sur
    // le bouton, et cette distinction porte plus que le message : **un
    // recentrage automatique ne demande jamais la permission.** Ce serait la
    // pop-up nue à l'ouverture que le §9 écarte, et avec une autorisation
    // « une seule fois » — qu'Android révoque à chaque passage en arrière-plan
    // — elle reviendrait à chaque lancement, devant une carte encore vide.
    var position = widget.location.cachedPosition;
    if (position == null && !silent) {
      // Sans position en cache il faut attendre un fix, qui peut ne jamais
      // venir en intérieur. Le dire vaut mieux qu'un bouton qui ne répond pas
      // pendant dix secondes (§4.6).
      _showMessage(MapLabels.searchingPosition);
    }
    position ??= silent ? await widget.location.currentPosition() : await _readPosition();
    if (!mounted) return;
    await _showPosition(position);

    if (position == null) {
      if (!silent) {
        _showMessage(MapLabels.positionUnavailable);
      }
      return;
    }
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.lat, position.lng),
        16,
      ),
    );
  }

  // --- Signalement ----------------------------------------------------------

  /// Tap sur une zone vide de la carte : on place le pin là, plutôt que
  /// d'obliger à viser le bouton puis à recadrer.
  ///
  /// Aucun risque de signalement involontaire : ce geste ouvre le mode placement,
  /// il ne crée rien. Il reste la feuille de niveau et « Envoyer » derrière.
  /// Le plugin n'appelle pas ce callback quand le tap touche un marqueur, donc
  /// ouvrir un détail et poser un pin ne se marchent pas dessus.
  Future<void> _onMapClick(Point<double> point, LatLng coordinates) async {
    if (_busy) return;

    // Déjà en placement : le tap déplace le pin sans toucher au zoom, ce qui
    // évite de recadrer au doigt quand on s'est trompé de quelques mètres.
    if (_placing) {
      await _controller?.animateCamera(CameraUpdate.newLatLng(coordinates));
      return;
    }

    // Même mesure que par le bouton « Signaler » (§4.6) : un placement par tap
    // direct est un signalement comme un autre, il compte dans les quinze
    // secondes.
    _gesture.start();
    setState(() => _placing = true);
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        coordinates,
        // Le zoom minimal reste imposé : en dessous, ajuster le pin n'a pas de
        // sens et la précision du §11.6 n'est plus tenue.
        _zoom < AppConfig.minZoomToReport ? AppConfig.placementZoom : _zoom,
      ),
    );
  }

  Future<void> _startPlacing() async {
    // Mesure du §4.6 : « le signalement tient-il sous 15 secondes ? ». Le geste
    // commence ici, à l'appui sur « Signaler » — pas à l'ouverture de la
    // feuille, qui laisserait dehors l'ajustement du pin.
    _gesture.start();
    setState(() => _placing = true);

    // **Le capteur ne doit jamais retarder l'ouverture du mode placement.** Le
    // bouton de validation dépend du zoom, et le zoom attendait ici une lecture
    // de position : sans fix disponible, l'app restait dix secondes avec un
    // bouton grisé et rien à expliquer (§4.6).
    //
    // On se rapproche donc tout de suite. Si une position récente est déjà là,
    // on se centre dessus — c'est l'intention du §4.1 F2, le pin posé à ma
    // position puis ajusté. Sinon on se contente de zoomer là où l'utilisateur
    // regardait, ce qui reste un point de départ raisonnable puisque le pin est
    // fait pour être déplacé (§11.6).
    // La lecture part en premier et sans être attendue. C'est ici, et nulle
    // part ailleurs dans le signalement, que la permission peut être
    // redemandée : l'utilisateur vient d'appuyer sur « Signaler », le dialogue
    // arrive avec son contexte, et il ne suspend aucun envoi (§9). En le
    // lançant avant l'animation, le dialogue s'ouvre tout de suite et la carte
    // se rapproche derrière lui.
    unawaited(_readPosition());

    final known = widget.location.cachedPosition;
    if (known != null) {
      await _showPosition(known);
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(known.lat, known.lng), AppConfig.placementZoom),
      );
    } else if (_zoom < AppConfig.placementZoom) {
      await _zoomForPlacement();
    }
  }

  /// Le bouton « Zoomer » de la barre : on se rapproche sur place, sans
  /// déplacer la carte, jusqu'au zoom où le pin s'ajuste au mètre. Le seuil est
  /// atteint d'un seul appui, pas au pincement.
  Future<void> _zoomForPlacement() async {
    await _controller?.animateCamera(CameraUpdate.zoomTo(AppConfig.placementZoom));
  }

  Future<void> _confirmPlacement() async {
    final controller = _controller;
    if (controller == null) return;

    final target = controller.cameraPosition?.target;
    if (target == null) return;

    final sheetClock = Stopwatch()..start();
    final draft = await showModalBottomSheet<ReportDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => ReportSheet(
        types: _types,
        address: null,
        allowDescription: widget.repo.rules.descriptionsEnabled,
      ),
    );
    if (draft == null || !mounted) return;

    setState(() {
      _placing = false;
      _busy = true;
    });

    try {
      // Déjà lue à l'ouverture du mode placement, et normalement encore
      // valable. Si elle ne l'est plus, on attend trois secondes et pas
      // davantage : un geste ne doit pas rester suspendu à un fix qui ne vient
      // pas (§4.6). Sans position il part quand même, il pèse simplement moins.
      // `mayAsk` reste faux : un envoi ne s'interrompt pas pour un dialogue
      // système. Sans position il part quand même, il pèse moins, et l'app le
      // dit (§4.6, §11.1).
      final position = await widget.location.currentPosition(
        timeout: LocationService.gestureTimeout,
      );
      final denied = position == null && !await widget.location.hasPermission();
      if (!mounted) return;
      final outcome = await widget.repo.report(
        type: draft.type.code,
        lat: target.latitude,
        lng: target.longitude,
        severity: draft.severity.value,
        description: draft.description,
        position: position,
      );
      if (!mounted) return;
      await _measureGesture(sheetClock, position: position, denied: denied);

      _supersedeReloads();
      switch (outcome) {
        case HazardCreated(:final hazard):
          await widget.repo.measurements.record(BetaMeasurements.sent);
          _hazards[hazard.id] = hazard;
          await _pushToMap();
          _showMessage(
            position == null
                ? withoutPosition(MapLabels.reportSent, permissionDenied: denied)
                : MapLabels.reportSentThanks,
          );
        case DuplicateFound(:final existing, :final distanceM):
          await widget.repo.measurements.record(BetaMeasurements.duplicateProposed);
          _hazards[existing.id] = existing;
          await _pushToMap();
          await _askAboutDuplicate(existing, distanceM);
        case ReportQueued(:final provisional):
          await widget.repo.measurements.record(BetaMeasurements.queued);
          _hazards[provisional.id] = provisional;
          await _pushToMap();
          _showMessage(
            position == null ? withoutPosition(_horsLigne, permissionDenied: denied) : _horsLigne,
          );
      }
    } on Exception catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Relève les mesures du §4.6 pour un geste qui vient d'aboutir.
  ///
  /// Deux durées : celle du geste entier, qui répond à la question des quinze
  /// secondes, et celle depuis la feuille, au sens littéral de la spec. Et deux
  /// compteurs de position, parce qu'un geste parti sans elle pèse 0,25 au lieu
  /// de 1 (§6.2) : savoir à quelle fréquence ça arrive change la lecture de
  /// toutes les autres mesures.
  Future<void> _measureGesture(
    Stopwatch sheetClock, {
    required DevicePosition? position,
    required bool denied,
  }) async {
    final m = widget.repo.measurements;
    final gesture = _gesture.take();
    if (gesture != null) await m.record(BetaMeasurements.gesture, duration: gesture);
    await m.record(BetaMeasurements.sheet, duration: sheetClock.elapsed);
    if (position == null) await m.record(BetaMeasurements.withoutPosition);
    if (denied) await m.record(BetaMeasurements.permissionDenied);
  }

  /// « Est-ce celui-ci ? » (§4.1 F2b).
  ///
  /// Le serveur refuse de créer un second danger du même type dans le rayon : on
  /// ne propose donc pas de « créer quand même », on propose de confirmer. Le bon
  /// réglage de ce rayon est l'une des questions de la bêta (§4.6).
  Future<void> _askAboutDuplicate(Hazard existing, double distanceM) async {
    final type = _typeFor(existing.type);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(MapLabels.duplicateTitle),
        content: Text(
          MapLabels.duplicateBody(
            type.label.toLowerCase(),
            distanceLabel(distanceM),
            relativeDateShort(existing.createdAt),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(MapLabels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(MapLabels.duplicateConfirm),
          ),
        ],
      ),
    );

    // Mesure du §4.6 : « le rayon anti-doublon de 15 m est-il le bon ? ». Un
    // refus est une détection à tort — la personne dit que ce n'est pas le même
    // trou. C'est le seul endroit où ce désaccord existe, et jusqu'ici il ne
    // laissait aucune trace.
    await widget.repo.measurements.record(
      confirm == true ? BetaMeasurements.duplicateAccepted : BetaMeasurements.duplicateRefused,
    );

    if (confirm == true && mounted) {
      await _act(existing.id, DetailAction.confirm);
    }
  }

  // --- Détail et gestes -----------------------------------------------------

  /// Tap sur un marqueur.
  ///
  /// `onMapClick` ne suffit pas : le plugin ne le déclenche pas quand le geste
  /// touche une couche interactive. C'est `onFeatureTapped` qui reçoit le tap,
  /// et il ne donne que l'identifiant de la feature — d'où la requête sur la
  /// couche rendue, pour nos propriétés, quand cet identifiant ne correspond à
  /// aucun danger connu.
  Future<void> _onFeatureTapped(
    Point<double> point,
    String id,
    String layerId,
  ) async {
    if (_placing) return;

    if (layerId == _clustersLayer || layerId == _clusterCountLayer) {
      await _expandCluster(point);
      return;
    }
    if (layerId != _markersLayer) return;

    if (_hazards.containsKey(id)) {
      await _openDetail(id);
      return;
    }

    final controller = _controller;
    if (controller == null) return;

    final features = await controller.queryRenderedFeatures(
      point,
      [_markersLayer],
      null,
    );
    if (features.isEmpty || !mounted) return;

    final properties = features.first['properties'] as Map<dynamic, dynamic>?;
    final hazardId = properties?['id'] as String?;
    if (hazardId != null) await _openDetail(hazardId);
  }

  /// Tap sur une grappe : on zoome jusqu'au niveau où elle se sépare.
  ///
  /// Une grappe agrège des dangers distincts ; il n'y a rien de sensé à
  /// ouvrir. Ne rien faire est pire : le geste a l'air d'avoir échoué. La
  /// source sait à quel zoom la grappe éclate, on y va.
  Future<void> _expandCluster(Point<double> point) async {
    final controller = _controller;
    if (controller == null) return;

    final features = await controller.queryRenderedFeatures(
      point,
      [_clustersLayer],
      null,
    );
    if (features.isEmpty || !mounted) return;

    final feature = features.first as Map<dynamic, dynamic>;
    final coordinates =
        (feature['geometry'] as Map<dynamic, dynamic>?)?['coordinates'] as List<dynamic>?;
    if (coordinates == null || coordinates.length < 2) return;
    final center = LatLng(
      (coordinates[1] as num).toDouble(),
      (coordinates[0] as num).toDouble(),
    );

    final properties = feature['properties'] as Map<dynamic, dynamic>?;
    final clusterId = (properties?['cluster_id'] as num?)?.toInt();

    // `getClusterExpansionZoom` répond 0 si la grappe n'est plus celle que la
    // source connaît — la carte a pu bouger entre le tap et la réponse. Un
    // cran de zoom vaut mieux qu'un geste sans effet.
    var target = _zoom + 1;
    if (clusterId != null) {
      final expansion = await controller.getClusterExpansionZoom(_sourceId, clusterId);
      if (expansion > 0) target = expansion + 0.5;
    }
    if (!mounted) return;

    await controller.animateCamera(CameraUpdate.newLatLngZoom(center, target));
  }

  Future<void> _openDetail(String id) async {
    setState(() => _busy = true);
    HazardDetail? detail;
    try {
      detail = await widget.repo.detail(id);
    } on Exception catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (detail == null || !mounted) return;
    // Le détail est plus frais que la carte : on le lui donne aussi.
    _hazards[detail.hazard.id] = detail.hazard;
    await _pushToMap();

    final street = await _streetAt(detail.hazard.lat, detail.hazard.lng);
    if (!mounted) return;

    final action = await showModalBottomSheet<DetailAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HazardDetailSheet(
        detail: detail!,
        type: _typeFor(detail.hazard.type),
        street: street,
      ),
    );

    if (action != null && mounted) await _act(id, action);
  }

  /// Le nom de la voie sous un danger, demandé à la carte elle-même.
  ///
  /// Aucune requête ne part : la réponse vient des tuiles déjà affichées (§7).
  /// `null` si la carte ne sait pas — l'appelant montre alors la coordonnée.
  Future<String?> _streetAt(double lat, double lng) async {
    final controller = _controller;
    if (controller == null) return null;
    final position = LatLng(lat, lng);
    try {
      final screen = await controller.toScreenLocation(position);
      return await StreetLookup.nearest(
        query: (rect, layerIds) => controller.queryRenderedFeaturesInRect(rect, layerIds, null),
        screen: Offset(screen.x.toDouble(), screen.y.toDouble()),
        position: position,
      );
    } on Exception {
      return null;
    }
  }

  Future<void> _act(String hazardId, DetailAction action) async {
    setState(() => _busy = true);
    try {
      final position = await widget.location.currentPosition(
        timeout: LocationService.gestureTimeout,
      );
      final denied = position == null && !await widget.location.hasPermission();
      if (!mounted) return;

      final outcome = switch (action) {
        DetailAction.confirm => await widget.repo.confirm(hazardId, position: position),
        DetailAction.resolve => await widget.repo.markResolved(hazardId, position: position),
        DetailAction.removeOwn => await widget.repo.removeOwn(hazardId),
      };
      if (!mounted) return;

      switch (outcome) {
        case ActionApplied(:final hazard):
          // Le serveur a toujours raison : on réaffiche l'état qu'il renvoie (§10),
          // et aucun rechargement parti avant ne doit le recouvrir.
          _supersedeReloads();
          if (hazard.status == HazardStatus.removed ||
              hazard.status == HazardStatus.resolved) {
            _hazards.remove(hazard.id);
          } else {
            _hazards[hazard.id] = hazard;
          }
          await _pushToMap();
          final feedback = feedbackFor(action, hazard, _typeFor(hazard.type));
          _showMessage(
            position == null && action != DetailAction.removeOwn
                ? withoutPosition(feedback, permissionDenied: denied)
                : feedback,
          );
        case ActionQueued():
          // Rien ne bouge sur la carte : le serveur n'a pas encore tranché, et
          // deviner sa décision serait mentir (§10).
          _showMessage(
            position == null && action != DetailAction.removeOwn
                ? withoutPosition(_horsLigne, permissionDenied: denied)
                : _horsLigne,
          );
      }
    } on Exception catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Le même message pour tous les gestes mis en file : ce qui compte est que
  /// l'utilisateur sache que son geste n'est pas perdu, et qu'il n'est pas parti.
  static const _horsLigne = MapLabels.queued;

  // --- Mise à jour (§12.6) ------------------------------------------------

  /// À annoncer sans attendre : la version installée est sous le minimum.
  AppUpdate? get _requiredUpdate {
    final update = _update;
    if (update == null || update.versionCode == _openedCode) return null;
    return update.isRequiredFor(AppConfig.versionCode) ? update : null;
  }

  /// À annoncer quand rien de plus pressant n'occupe le bandeau.
  AppUpdate? get _availableUpdate {
    final update = _update;
    if (update == null || update.versionCode == _openedCode) return null;
    return update;
  }

  /// Le texte du bandeau, suivi de la ligne écrite au moment de publier.
  String _updateText(String base) {
    final note = _update?.note ?? '';
    return note.isEmpty ? base : MapLabels.updateWithNote(base, note);
  }

  /// Le navigateur télécharge l'APK, Android propose l'installation. Si aucun
  /// navigateur ne répond, on donne l'adresse de la page, qui se tape.
  Future<void> _openUpdate() async {
    final update = _update;
    if (update == null) return;
    final opened = await const ExternalLinks().open(update.url);
    if (!mounted) return;
    if (opened) {
      setState(() => _openedCode = update.versionCode);
    } else {
      _showMessage(MapLabels.updateOpenFailed(update.url.resolve('/apk').toString()));
    }
  }

  // --- Retours -------------------------------------------------------------

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error) {
    final message = error is ApiException ? error.message : MapLabels.networkError;
    _showMessage(message);
  }

  // --- Construction ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          widget.mapBuilder?.call(context) ??
              MapLibreMap(
            styleString: widget.mapStyle,
            initialCameraPosition: const CameraPosition(
              target: LatLng(AppConfig.parisLat, AppConfig.parisLng),
              zoom: AppConfig.defaultZoom,
            ),
            trackCameraPosition: true,
            myLocationEnabled: false,
            // La boussole du SDK natif se cale tout en haut à droite, sous la
            // barre d'état et sous notre colonne de boutons, qui lui vole les
            // touches. On la remplace par un bouton Flutter dans cette colonne.
            compassEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            onMapClick: _onMapClick,
            onMapCreated: (controller) {
              _controller = controller;
              // En développement, le serveur est joint par `adb reverse`, donc
              // par le câble. MapLibre, lui, interroge `ConnectivityManager`
              // avant toute requête et se déclare hors ligne en mode avion :
              // il ne demande alors aucune tuile, et les marqueurs flottent sur
              // du blanc pendant que nos appels REST, eux, passent. On le force
              // à essayer. Jamais en release, où son refus est le bon
              // comportement : sans réseau, il n'y a rien à demander.
              if (kDebugMode) unawaited(controller.forceOnlineMode());
              controller.onFeatureTapped.add(
                (point, coordinates, id, layerId, _) => _onFeatureTapped(point, id, layerId),
              );
            },
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraMove: (position) {
              // Un demi-degré suffit à l'œil ; en deçà on ne redessine pas.
              if ((position.bearing - _bearing).abs() >= 0.5) {
                setState(() => _bearing = position.bearing);
              }
            },
            onCameraIdle: () {
              final zoom = _controller?.cameraPosition?.zoom;
              if (zoom != null && zoom != _zoom) setState(() => _zoom = zoom);
              _scheduleReload();
            },
          ),

          // Le pin de placement est fixe au centre de l'écran : c'est la carte
          // qui bouge dessous. Plus précis qu'un marqueur à faire glisser.
          if (_placing) const CenterPin(),

          // Ce qui attend le réseau se voit, et se relance au doigt. Sans cela,
          // un geste fait hors ligne n'aurait aucune trace à l'écran.
          //
          // Un seul bandeau à la fois, du plus pressant au moins pressant : une
          // mise à jour exigée passe devant tout, parce que l'app installée ne
          // devrait plus servir ; une annonce de l'équipe attend que la file
          // soit vidée ; une mise à jour simplement disponible passe après,
          // elle peut patienter.
          if (!_placing)
            if (_requiredUpdate != null)
              TopBanner(
                icon: Icons.system_update,
                text: _updateText(MapLabels.updateRequired(_requiredUpdate!.versionName)),
                onTap: _openUpdate,
              )
            else if (_blind)
              const TopBanner(
                icon: Icons.help_outline,
                text: MapLabels.blind,
              )
            else if (_pending > 0)
              TopBanner(
                icon: Icons.cloud_off,
                text: MapLabels.pending(_pending),
                onTap: _flush,
              )
            else if (_announcement != null && _announcement!.endsAt.isAfter(DateTime.now()))
              TopBanner(
                icon: Icons.campaign_outlined,
                text: _announcement!.body,
                onTap: _dismissAnnouncement,
              )
            else if (_availableUpdate != null)
              TopBanner(
                icon: Icons.system_update,
                text: _updateText(MapLabels.updateAvailable(_availableUpdate!.versionName)),
                onTap: _openUpdate,
              ),

          if (_busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),

          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    RoundButton(
                      icon: Icons.settings_outlined,
                      tooltip: MapLabels.settings,
                      onPressed: _placing ? null : _openSettings,
                    ),
                    const SizedBox(height: 10),
                    RoundButton(
                      icon: Icons.download_for_offline_outlined,
                      tooltip: MapLabels.offlineMaps,
                      onPressed: _placing ? null : _openOfflineMaps,
                    ),
                    const SizedBox(height: 10),
                    RoundButton(
                      icon: _filters.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
                      tooltip: MapLabels.filters,
                      highlighted: _filters.isActive,
                      onPressed: _placing ? null : _openFilters,
                    ),
                    const SizedBox(height: 10),
                    RoundButton(
                      icon: Icons.my_location,
                      tooltip: MapLabels.recenter,
                      onPressed: () => _recenterOnUser(),
                    ),
                    // La boussole n'apparaît qu'une fois la carte tournée, et
                    // sa flèche pointe le nord réel : la toucher le remet en haut.
                    // En dernier dans la colonne : elle peut aller et venir sans
                    // faire bouger les autres boutons.
                    if (_bearing.abs() >= 0.5) ...[
                      const SizedBox(height: 10),
                      RoundButton(
                        icon: Icons.navigation,
                        iconAngle: -_bearing * pi / 180,
                        tooltip: MapLabels.resetNorth,
                        onPressed: _resetNorth,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          if (_placing)
            PlacementBar(
              canValidate: _zoom >= AppConfig.minZoomToReport,
              onZoomIn: _zoomForPlacement,
              // Annuler arrête aussi le chronomètre : sinon le prochain
              // signalement hériterait de dix minutes de trajet (§4.6).
              onCancel: () => setState(() {
                _placing = false;
                _gesture.cancel();
              }),
              onValidate: _confirmPlacement,
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _placing
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _startPlacing,
              icon: const Icon(Icons.add_location_alt),
              label: const Text(MapLabels.report),
            ),
    );
  }

  /// Remettre le nord en haut sans toucher au centre ni au zoom.
  Future<void> _resetNorth() async {
    await _controller?.animateCamera(CameraUpdate.bearingTo(0));
  }

  /// Embarquer le fond de carte de la zone affichée (§10).
  ///
  /// La zone proposée est celle qu'on a sous les yeux : c'est le cadrage que
  /// l'utilisateur vient de faire lui-même, et le seul dont on puisse dire qu'il
  /// l'a choisi.
  Future<void> _openOfflineMaps() async {
    final bounds = await _controller?.getVisibleRegion();
    if (bounds == null || !mounted) return;

    // La voie au centre de l'écran sert de nom à la zone : « Boulevard Voltaire »
    // se retrouve dans une liste, « autour de 48.856, 2.379 » non.
    final centre = await _streetAt(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OfflineMapsSheet(
        maps: const OfflineMaps(),
        visible: bounds,
        aroundStreet: centre,
      ),
    );
  }

  /// Les paramètres peuvent effacer le cache sous les pieds de la carte
  /// (§11.4) : au retour, on repart de ce que le serveur dit, pas de ce qu'on
  /// croyait savoir.
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          repo: widget.repo,
          device: widget.device,
          location: widget.location,
          updates: widget.updates,
        ),
      ),
    );
    if (!mounted) return;
    setState(_hazards.clear);
    // La carte se vide tout de suite, même si le rechargement ne part pas
    // (sous le zoom minimal) : sinon les anciens marqueurs restent dessinés.
    await _pushToMap();
    await _reload();
  }

  Future<void> _openFilters() async {
    final filters = await showModalBottomSheet<MapFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MapFiltersSheet(filters: _filters, types: _types),
    );
    if (filters == null || !mounted) return;

    setState(() {
      _filters = filters;
      // Les filtres changent ce que le serveur renvoie : on repart d'une carte
      // vide plutôt que de garder des marqueurs que le filtre exclut désormais.
      _hazards.clear();
    });
    await _pushToMap();
    await _reload();
  }
}
