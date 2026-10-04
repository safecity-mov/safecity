import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../location/location_service.dart';
import 'api_client.dart';
import 'beta_measurements.dart';
import 'device_identity.dart';
import 'local/database.dart';
import 'models/hazard.dart';
import 'models/hazard_type.dart';
import 'models/severity.dart';
import 'moderation.dart';
import 'proximity.dart';
import 'trace_horizon.dart';

/// Ce qu'il est advenu d'un geste (§10).
sealed class ActionOutcome {
  const ActionOutcome();
}

/// Le serveur a répondu. C'est son état qui fait foi, pas celui du client.
class ActionApplied extends ActionOutcome {
  const ActionApplied(this.hazard);
  final Hazard hazard;
}

/// Le serveur est injoignable : le geste attend dans la file. Le danger est
/// renvoyé tel que le cache le connaît — **inchangé**, parce que deviner ce que
/// le serveur va décider serait mentir à l'utilisateur (§10).
class ActionQueued extends ActionOutcome {
  const ActionQueued(this.unchanged);
  final Hazard? unchanged;
}

/// Ce que la carte doit afficher pour une zone, et ce qu'elle en sait.
///
/// `covered` est le point délicat : un cache qui répond « rien » est ambigu. Il
/// faut pouvoir dire « je n'ai jamais chargé cette zone » plutôt que de laisser
/// croire qu'elle est sans danger (§10).
class HazardsView {
  const HazardsView({
    required this.hazards,
    required this.fromCache,
    required this.covered,
    this.truncated = false,
  });

  final List<Hazard> hazards;

  /// Vrai quand le serveur n'a pas répondu et qu'on sert le cache.
  final bool fromCache;

  /// Vrai si la zone demandée a été chargée, sans filtre restrictif, avant que
  /// l'horizon d'oubli ne l'efface. Toujours vrai quand la réponse vient du
  /// serveur, sauf si elle est tronquée.
  final bool covered;

  /// Le serveur a atteint son plafond : cette réponse ne décrit pas la zone
  /// entière. Ce qui n'y figure pas n'est donc pas absent, seulement coupé, et
  /// la carte ne doit rien en retirer (§10).
  final bool truncated;

  /// Le cas à dire à l'utilisateur : hors ligne, sur une zone jamais vue.
  bool get isBlind => fromCache && !covered;
}

/// Résultat d'un vidage de file.
class DrainReport {
  const DrainReport({this.sent = 0, this.refused = 0, this.remaining = 0});

  /// Actions acceptées par le serveur.
  final int sent;

  /// Actions que le serveur a refusées définitivement — déjà voté, délai de 24 h
  /// dépassé. Elles sortent de la file : les rejouer ne changerait rien.
  final int refused;

  /// Actions toujours en attente, faute de réseau.
  final int remaining;

  bool get changedSomething => sent > 0 || refused > 0;
}

/// Un geste qui attend le réseau. En mémoire, jamais sur le disque.
class _PendingAction {
  _PendingAction({
    required this.clientId,
    required this.kind,
    this.hazardId,
    this.payload = const {},
    this.position,
  });

  /// L'identifiant qui rend l'envoi idempotent côté serveur : rejouer la file ne
  /// crée jamais de doublon (§8).
  final String clientId;

  /// `report`, `confirm`, `resolve` ou `remove`.
  final String kind;

  /// Nul pour un `report` : le danger n'existe pas encore.
  final String? hazardId;

  final Map<String, dynamic> payload;
  final DevicePosition? position;
}

/// Le dépôt : seul point d'accès aux dangers pour l'interface (§10).
///
/// Il arbitre entre trois sources — le réseau, le cache local, la file d'attente
/// — selon une règle unique : **le serveur a toujours raison**. Le cache ne sert
/// qu'à répondre quand il se tait, et la file qu'à lui reparler plus tard.
///
/// **La file vit en mémoire**, contrairement à ce que prévoyait le §10. Un geste
/// fait sans réseau repart dès que le réseau revient, tant que l'app est en vie ;
/// si Android tue le processus avant, il est perdu. Périmètre assumé pour la
/// bêta (§10 amendé) : le cas nominal est un trajet app au premier plan, et une
/// file durable coûtait une table, `workmanager`, et la question de savoir ce que
/// la position du déclarant fait sur un disque (§11.1).
///
/// Conséquence : **rien de ce que le disque contient ne concerne la personne.**
class HazardRepository {
  HazardRepository({
    required ApiClient api,
    required AppDatabase db,
    required DeviceIdentity device,
  })  : _api = api,
        _db = db,
        _device = device,
        measurements = BetaMeasurements(db);

  final ApiClient _api;
  final AppDatabase _db;
  final DeviceIdentity _device;

  /// Les mesures de la bêta (§4.6). Locales, agrégées, jamais transmises
  /// autrement que par un geste explicite du testeur (§11.1).
  final BetaMeasurements measurements;

  /// Les gestes qui attendent le réseau, dans l'ordre où ils ont été faits.
  final _queue = <_PendingAction>[];

  /// Les signalements en attente, affichés tout de suite pour que le geste ait
  /// un effet visible, par `client_id`.
  final _provisional = <String, Hazard>{};

  final _pendingChanges = StreamController<int>.broadcast();
  Timer? _retry;

  /// Le vidage en cours, s'il y en a un. `drain()` est appelé par le minuteur,
  /// au retour au premier plan et au tap sur le bandeau : deux boucles sur la
  /// même file enverraient chaque geste deux fois, et la seconde réponse —
  /// « déjà voté » — serait comptée comme un refus.
  Future<DrainReport>? _draining;

  /// Cadence de reprise tant qu'il reste quelque chose à envoyer. Assez lente
  /// pour ne pas peser sur la batterie d'un trajet (§4.6), assez rapide pour que
  /// le retour du réseau se voie.
  static const retryInterval = Duration(seconds: 30);

  /// Durée de validité d'une zone chargée (§10), et durée de vie de tout ce
  /// que le cache contient : 45 minutes.
  ///
  /// Elle n'est pas choisie pour le confort hors ligne mais pour la vie privée
  /// (§11.1, §11.7). Un danger pris à part ne dit rien de personne : c'est une
  /// donnée publique sur la voirie, identique pour tout le monde. Ce qui parle,
  /// c'est **la sélection** : les dangers en cache sont exactement ceux des
  /// cadres que ce téléphone a chargés, donc des endroits où il est passé.
  /// L'empreinte est la même trace que celle de `CachedAreas`, et elle s'efface
  /// avec elle. Le cache sert la sortie en cours ; il l'a oubliée avant qu'on
  /// rentre. Voir `TraceHorizon` et, côté natif, `TraceSweeper`.
  ///
  /// **Conséquence assumée** : une « zone hors ligne » téléchargée (§10) embarque
  /// le fond de carte, pas les dangers. Une heure sans réseau sur une zone
  /// téléchargée montre les rues, et un bandeau « zone jamais chargée ». La
  /// feuille de téléchargement le dit (`OfflineLabels.noHazards`), plutôt que de
  /// laisser découvrir l'écart en roulant.
  static const cacheTtl = TraceHorizon.maxAge;

  /// Nombre d'actions en attente, à chaque changement (§10).
  Stream<int> get pendingChanges => _pendingChanges.stream;

  int get pendingCount => _queue.length;

  Future<void> dispose() async {
    _retry?.cancel();
    await _pendingChanges.close();
  }

  // --- Catalogue ------------------------------------------------------------

  /// La règle de proximité en vigueur (§6.2).
  ///
  /// Le palier se calcule ici, sur l'appareil : la position du déclarant ne part jamais
  /// (§11.1). La règle, elle, vient du serveur — sans quoi deux versions de l'app
  /// pondéreraient différemment. Tant qu'il n'a rien dit, celle qui est compilée s'applique.
  ProximityRules _proximity = ProximityRules.fallback;

  /// La règle de proximité, sans jamais faire échouer le catalogue pour autant.
  Future<void> _refreshProximity() async {
    try {
      _proximity = await _api.fetchProximityTiers();
    } catch (_) {
      // On garde la dernière connue, ou celle compilée. Un geste doit pouvoir partir.
      // `catch (_)` et non `on Exception` : une réponse mal formée lève un `TypeError`,
      // qui n'est pas une `Exception` et emporterait tout le catalogue avec lui.
    }
  }

  /// Les seuils de résolution en vigueur (§6.1).
  ///
  /// Sert au marqueur provisoire d'un signalement pas encore parti : afficher
  /// « 1 vote sur 1 » là où le serveur en demande 2 serait faux dès l'écran suivant.
  ModerationRules _rules = ModerationRules.fallback;

  /// Les règles telles que lues en dernier : ce que la feuille de signalement
  /// consulte pour savoir si la précision libre est ouverte.
  ModerationRules get rules => _rules;

  Future<void> _refreshRules() async {
    try {
      _rules = await _api.fetchModerationRules();
    } catch (_) {
      // Idem : la dernière connue, ou celle compilée.
    }
  }

  /// Le palier d'un geste sur un danger déjà connu.
  ///
  /// Le danger vient du cache local : il y est forcément, puisqu'il a été affiché pour qu'on
  /// puisse agir dessus. Absent malgré tout, on retombe sur le palier le moins favorable.
  Future<int> _proximityForHazard(String hazardId, DevicePosition? position) async {
    if (position == null) return ProximityRules.farthest;
    final hazard = await _cachedHazard(hazardId);
    if (hazard == null) return ProximityRules.farthest;
    return _proximity.tierFor(
      hazardLat: hazard.lat,
      hazardLng: hazard.lng,
      deviceLat: position.lat,
      deviceLng: position.lng,
    );
  }

  /// Les silhouettes, sans jamais faire échouer le catalogue pour autant.
  Future<Map<String, Uint8List>> _fetchIcons() async {
    try {
      return await _api.fetchTypeIcons();
    } on Exception {
      return const {};
    }
  }

  /// Le catalogue vient du serveur (§3). À défaut, celui de la dernière fois :
  /// sans lui il n'y a pas d'écran à dessiner, pas même en consultation.
  ///
  /// « À défaut » couvre **toute** erreur, pas seulement une coupure réseau :
  /// un serveur qui répond 500 au démarrage, ou une réponse qu'on ne sait plus
  /// lire, ne doivent pas bloquer une app qui a déjà tout ce qu'il faut pour
  /// consulter. L'erreur ne remonte que si le cache est vide — au premier
  /// lancement, où il n'y a rien d'autre à montrer qu'elle.
  Future<List<HazardType>> types() async {
    try {
      final brut = await _api.fetchTypes();
      // Les silhouettes sont un agrément, pas une condition : si ce second appel
      // échoue, le catalogue reste utilisable et les glyphes embarqués prennent
      // le relais. L'inverse n'est pas vrai, d'où deux appels et non un seul.
      final icones = await _fetchIcons();
      await _refreshProximity();
      await _refreshRules();
      final types = [for (final t in brut) t.withIcon(icones[t.code])];

      await _db.batch((batch) {
        batch.deleteWhere(_db.cachedTypes, (_) => const Constant(true));
        batch.insertAll(_db.cachedTypes, [
          for (final t in types)
            CachedTypesCompanion.insert(
              code: t.code,
              label: t.label,
              iconName: t.iconName,
              resolvedLabel: t.resolvedLabel,
              dedupRadiusM: t.dedupRadiusM,
              enabled: t.enabled,
              sortOrder: t.sortOrder,
              iconPng: Value(t.iconPng),
            ),
        ]);
      });
      return types;
    } catch (_) {
      final rows = await (_db.select(_db.cachedTypes)
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();
      if (rows.isEmpty) rethrow;
      return rows.map(_typeFromRow).toList();
    }
  }

  // --- Lecture --------------------------------------------------------------

  /// Les dangers d'une zone. Le réseau d'abord, le cache à défaut (§10).
  Future<HazardsView> hazardsInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    List<String>? types,
    int? minSeverity,
  }) async {
    List<Hazard> hazards;
    var fromCache = false;
    var covered = true;
    var truncated = false;
    try {
      final response = await _api.hazardsInBbox(
        minLng: minLng,
        minLat: minLat,
        maxLng: maxLng,
        maxLat: maxLat,
        types: types,
        minSeverity: minSeverity,
      );
      hazards = response.hazards;
      truncated = response.truncated;
      // Une zone n'est « couverte » que si on l'a chargée en entier et sans
      // filtre restrictif. Sinon, hors ligne et sans filtre, le cache répondrait
      // « rien d'autre ici » sur une zone dont il n'a vu qu'une partie (§10).
      final complete = (types == null || types.isEmpty) && minSeverity == null && !truncated;
      if (complete) {
        await _rememberArea(
          hazards,
          minLat: minLat,
          minLng: minLng,
          maxLat: maxLat,
          maxLng: maxLng,
        );
      } else {
        await _cache(hazards);
      }
    } on Exception catch (error) {
      if (!isTransient(error)) rethrow;
      hazards = await _cachedHazardsIn(
        minLat: minLat,
        minLng: minLng,
        maxLat: maxLat,
        maxLng: maxLng,
        types: types,
        minSeverity: minSeverity,
      );
      fromCache = true;
      covered = await hasFreshCacheFor(
        minLat: minLat,
        minLng: minLng,
        maxLat: maxLat,
        maxLng: maxLng,
      );
    }
    return HazardsView(
      hazards: [
        ...hazards,
        // Les signalements en attente s'ajoutent : ni le serveur ni le cache ne
        // les connaissent encore.
        ..._provisional.values.where(
          (h) => h.lat >= minLat && h.lat <= maxLat && h.lng >= minLng && h.lng <= maxLng,
        ),
      ],
      fromCache: fromCache,
      covered: covered && !truncated,
      truncated: truncated,
    );
  }

  /// Le détail d'un danger. Hors ligne, ce que le cache sait, **sans
  /// historique** : la chronologie n'est pas mise en cache, et une chronologie
  /// partielle serait plus trompeuse qu'une chronologie absente.
  ///
  /// Un signalement encore en file se dit `provisional` : le serveur ne le
  /// connaît pas, aucun geste ne peut donc porter dessus.
  Future<HazardDetail?> detail(String id) async {
    final provisional = _provisional[id];
    if (provisional != null) {
      return HazardDetail(hazard: provisional, timeline: const [], provisional: true);
    }
    try {
      return await _api.hazardDetail(id);
    } on Exception catch (error) {
      if (!isTransient(error)) rethrow;
      final hazard = await _cachedHazard(id);
      return hazard == null ? null : HazardDetail(hazard: hazard, timeline: const []);
    }
  }

  // --- Gestes ---------------------------------------------------------------

  Future<ReportOutcome> report({
    required String type,
    required double lat,
    required double lng,
    required int severity,
    String? description,
    DevicePosition? position,
  }) async {
    final clientId = _device.newClientId();
    final deviceId = await _device.id;
    try {
      final outcome = await _api.reportHazard(
        clientId: clientId,
        deviceId: deviceId,
        type: type,
        lat: lat,
        lng: lng,
        severity: severity,
        description: description,
        proximity: _proximity.tierFor(
          hazardLat: lat,
          hazardLng: lng,
          deviceLat: position?.lat,
          deviceLng: position?.lng,
        ),
      );
      await _cache([_hazardOf(outcome)]);
      return outcome;
    } on Exception catch (error) {
      if (!isTransient(error)) rethrow;

      _enqueue(
        _PendingAction(
          clientId: clientId,
          kind: 'report',
          payload: {
            'type': type,
            'lat': lat,
            'lng': lng,
            'severity': severity,
            if (description != null) 'description': description,
          },
          position: position,
        ),
      );

      // Le marqueur provisoire porte les compteurs d'un danger neuf — c'est ce
      // qu'il sera si le serveur l'accepte. Il disparaît au profit de la réponse
      // du serveur, quelle qu'elle soit.
      final now = DateTime.now();
      final provisional = Hazard(
        id: clientId,
        type: type,
        lat: lat,
        lng: lng,
        severity: Severity.fromValue(severity),
        status: HazardStatus.active,
        createdAt: now,
        lastConfirmedAt: now,
        // Un danger que le serveur ne connaît pas encore n'a pas de balance :
        // elle arrivera avec sa réponse, quelle qu'elle soit.
        confirmWeight: 0,
        resolveWeight: 0,
        resolveThreshold: _rules.minResolveVotes,
        reportedRemotely: position == null,
        description: description,
      );
      _provisional[clientId] = provisional;
      return ReportQueued(provisional);
    }
  }

  Future<ActionOutcome> confirm(String hazardId, {DevicePosition? position}) =>
      _gesture('confirm', hazardId, position);

  Future<ActionOutcome> markResolved(String hazardId, {DevicePosition? position}) =>
      _gesture('resolve', hazardId, position);

  /// Le retrait par l'auteur n'a pas de position : il ne se pèse pas (§6.1).
  Future<ActionOutcome> removeOwn(String hazardId) => _gesture('remove', hazardId, null);

  Future<ActionOutcome> _gesture(
    String kind,
    String hazardId,
    DevicePosition? position,
  ) async {
    final clientId = _device.newClientId();
    try {
      final hazard = await _call(
        kind: kind,
        clientId: clientId,
        deviceId: await _device.id,
        hazardId: hazardId,
        proximity: await _proximityForHazard(hazardId, position),
      );
      await _cache([hazard]);
      return ActionApplied(hazard);
    } on Exception catch (error) {
      if (!isTransient(error)) rethrow;
      _enqueue(
        _PendingAction(
          clientId: clientId,
          kind: kind,
          hazardId: hazardId,
          position: position,
        ),
      );
      return ActionQueued(await _cachedHazard(hazardId));
    }
  }

  // --- File d'attente -------------------------------------------------------

  /// Vide la file, dans l'ordre où les gestes ont été faits.
  ///
  /// Trois issues par action : acceptée, refusée définitivement, ou toujours
  /// sans réseau. Un refus sort de la file — le serveur a tranché, rejouer ne
  /// changerait rien (§10). Une panne arrête le vidage : marteler les suivantes
  /// ne ferait qu'échouer autant de fois.
  ///
  /// Un seul vidage à la fois : un second appel pendant le premier reçoit le
  /// même compte rendu, au lieu de renvoyer chaque geste une seconde fois.
  Future<DrainReport> drain() =>
      _draining ??= _drain().whenComplete(() => _draining = null);

  Future<DrainReport> _drain() async {
    if (_queue.isEmpty) return const DrainReport();

    final deviceId = await _device.id;
    var sent = 0;
    var refused = 0;

    for (final action in List.of(_queue)) {
      try {
        final Hazard hazard;
        if (action.kind == 'report') {
          final p = action.payload;
          hazard = _hazardOf(
            await _api.reportHazard(
              clientId: action.clientId,
              deviceId: deviceId,
              type: p['type'] as String,
              lat: (p['lat'] as num).toDouble(),
              lng: (p['lng'] as num).toDouble(),
              severity: p['severity'] as int,
              description: p['description'] as String?,
              proximity: _proximity.tierFor(
                hazardLat: (p['lat'] as num).toDouble(),
                hazardLng: (p['lng'] as num).toDouble(),
                deviceLat: action.position?.lat,
                deviceLng: action.position?.lng,
              ),
            ),
          );
        } else {
          hazard = await _call(
            kind: action.kind,
            clientId: action.clientId,
            deviceId: deviceId,
            hazardId: action.hazardId!,
            proximity: await _proximityForHazard(action.hazardId!, action.position),
          );
        }
        await _cache([hazard]);
        _drop(action);
        sent++;
      } on Exception catch (error) {
        if (isTransient(error)) break;
        // Refus du serveur : il a tranché, l'action n'a plus de raison d'être.
        _drop(action);
        refused++;
      }
    }

    // Mesure du §4.6 : « la synchronisation hors-ligne tient-elle un vrai
    // trajet ? ». Comptée ici parce que c'est le seul endroit qui voit à la fois
    // ce qui est parti et ce que le serveur a refusé.
    for (var i = 0; i < sent; i++) {
      await measurements.record(BetaMeasurements.queueSent);
    }
    for (var i = 0; i < refused; i++) {
      await measurements.record(BetaMeasurements.queueRefused);
    }

    _announce();
    return DrainReport(sent: sent, refused: refused, remaining: _queue.length);
  }

  void _enqueue(_PendingAction action) {
    _queue.add(action);
    _announce();
    _retry ??= Timer.periodic(retryInterval, (_) => unawaited(_drainQuietly()));
  }

  /// Le vidage déclenché par le minuteur, dont personne n'attend le résultat.
  ///
  /// Il attrape `Object` et non `Exception` : le décodage d'un danger fait des
  /// casts, et un champ que le serveur renommerait lèverait un `TypeError`, qui
  /// est une `Error`. Sans ce filet, elle partirait dans la zone — silencieuse,
  /// et la file cesserait de se vider sans que rien ne le dise. Le prochain tour
  /// réessaiera ; c'est ce qu'un minuteur de reprise doit faire.
  Future<void> _drainQuietly() async {
    try {
      await drain();
    } on Object {
      // Rien à dire ici : aucun écran n'écoute, et le tour suivant reprendra.
    }
  }

  void _drop(_PendingAction action) {
    _queue.remove(action);
    _provisional.remove(action.clientId);
  }

  void _announce() {
    if (_queue.isEmpty) {
      _retry?.cancel();
      _retry = null;
    }
    if (!_pendingChanges.isClosed) _pendingChanges.add(_queue.length);
  }

  // --- Interne --------------------------------------------------------------

  /// Ce qui distingue « le serveur est injoignable » de « le serveur refuse ».
  ///
  /// Un refus est une réponse : il a un sens, un message, et rejouer l'action ne
  /// le changera pas. Une panne n'est pas une réponse — et un serveur qui
  /// redémarre (503), un mandataire qui expire (408, 504) ou qui demande de
  /// ralentir (429) sont des pannes, pas des refus. Confondre les deux
  /// remplirait la file de gestes morts, ou jetterait des gestes valides :
  /// PostgREST qui redémarre pendant un vidage vidait la file entière.
  ///
  /// `IOException` plutôt que la seule `SocketException` : un portail captif
  /// lève une `HandshakeException`, qui n'est pas plus une réponse du serveur.
  static bool isTransient(Object error) =>
      error is IOException ||
      error is TimeoutException ||
      error is http.ClientException ||
      (error is ApiException && _isTransientStatus(error.statusCode));

  static bool _isTransientStatus(int? status) =>
      status == null || status >= 500 || status == 408 || status == 429;

  static Hazard _hazardOf(ReportOutcome outcome) => switch (outcome) {
        HazardCreated(:final hazard) => hazard,
        DuplicateFound(:final existing) => existing,
        ReportQueued(:final provisional) => provisional,
      };

  Future<Hazard> _call({
    required String kind,
    required String clientId,
    required String deviceId,
    required String hazardId,
    required int proximity,
  }) =>
      switch (kind) {
        'confirm' => _api.confirmHazard(
            clientId: clientId,
            deviceId: deviceId,
            hazardId: hazardId,
            proximity: proximity,
          ),
        'resolve' => _api.markResolved(
            clientId: clientId,
            deviceId: deviceId,
            hazardId: hazardId,
            proximity: proximity,
          ),
        'remove' => _api.removeOwnHazard(
            clientId: clientId,
            deviceId: deviceId,
            hazardId: hazardId,
          ),
        _ => throw ArgumentError('geste inconnu : $kind'),
      };

  Future<void> _cache(Iterable<Hazard> hazards) async {
    final now = DateTime.now();
    await _db.batch((batch) {
      for (final h in hazards) {
        batch.insert(
          _db.cachedHazards,
          CachedHazardsCompanion.insert(
            id: h.id,
            type: h.type,
            lat: h.lat,
            lng: h.lng,
            severity: h.severity.value,
            status: h.status.name,
            description: Value(h.description),
            address: Value(h.address),
            createdAt: h.createdAt,
            lastConfirmedAt: h.lastConfirmedAt,
            confirmWeight: h.confirmWeight,
            resolveWeight: h.resolveWeight,
            resolveThreshold: h.resolveThreshold,
            reportedRemotely: h.reportedRemotely,
            cachedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Une zone que le serveur vient de décrire en entier.
  ///
  /// Ce qu'il ne renvoie plus dans cette zone n'y est plus — retiré par la
  /// console, résolu par d'autres : le cache l'oublie, sans quoi un fantôme
  /// reviendrait à la prochaine coupure.
  ///
  /// Une seule transaction pour les quatre écritures : `onCameraIdle` appelle
  /// ceci à chaque arrêt de la carte.
  Future<void> _rememberArea(
    List<Hazard> hazards, {
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    final now = DateTime.now();
    final seen = [for (final h in hazards) h.id];
    final refreshed = [HazardStatus.active.name, HazardStatus.disputed.name];
    await _db.transaction(() async {
      await (_db.delete(_db.cachedHazards)
            ..where(
              (t) =>
                  t.lat.isBetweenValues(minLat, maxLat) &
                  t.lng.isBetweenValues(minLng, maxLng) &
                  t.status.isIn(refreshed) &
                  t.id.isNotIn(seen),
            ))
          .go();
      await _cache(hazards);
      await _db.into(_db.cachedAreas).insert(
            CachedAreasCompanion.insert(
              minLat: minLat,
              minLng: minLng,
              maxLat: maxLat,
              maxLng: maxLng,
              fetchedAt: now,
            ),
          );
      await (_db.delete(_db.cachedAreas)
            ..where((t) => t.fetchedAt.isSmallerThanValue(now.subtract(cacheTtl))))
          .go();
      await (_db.delete(_db.cachedHazards)
            ..where((t) => t.cachedAt.isSmallerThanValue(now.subtract(cacheTtl))))
          .go();
    });
  }

  /// Vrai si la zone demandée a été chargée, sans filtre restrictif, il y a
  /// moins de [cacheTtl]. Une zone plus large qui la contient compte : les
  /// dangers y sont déjà.
  ///
  /// Sans cela, impossible de distinguer « il n'y a rien ici » de « je ne sais
  /// pas » : la carte afficherait un vide rassurant et faux.
  Future<bool> hasFreshCacheFor({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    final since = DateTime.now().subtract(cacheTtl);
    final rows = await (_db.select(_db.cachedAreas)
          ..where((t) => t.fetchedAt.isBiggerThanValue(since)))
        .get();
    return rows.any(
      (a) =>
          a.minLat <= minLat && a.minLng <= minLng && a.maxLat >= maxLat && a.maxLng >= maxLng,
    );
  }

  /// Le cache rejoué avec les mêmes filtres que `hazards_in_bbox` (§8).
  ///
  Future<List<Hazard>> _cachedHazardsIn({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    List<String>? types,
    int? minSeverity,
  }) async {
    final rows = await (_db.select(_db.cachedHazards)
          ..where(
            (t) =>
                t.lat.isBetweenValues(minLat, maxLat) & t.lng.isBetweenValues(minLng, maxLng),
          ))
        .get();

    return rows
        .where((r) => r.status == 'active' || r.status == 'disputed')
        .where((r) => types == null || types.contains(r.type))
        .where((r) => minSeverity == null || r.severity >= minSeverity)
        .map(_hazardFromRow)
        .toList();
  }

  Future<Hazard?> _cachedHazard(String id) async {
    final row =
        await (_db.select(_db.cachedHazards)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _hazardFromRow(row);
  }

  /// « Effacer mes données » (§11.4), les deux moitiés du geste.
  ///
  /// Le serveur détache les gestes du terminal ; le terminal jette son cache et
  /// sa file. Rend le nombre de gestes détachés : dire « 7 gestes ne vous sont
  /// plus rattachés » vaut mieux qu'un « c'est fait » que personne ne peut
  /// vérifier.
  ///
  /// L'ordre compte. Le serveur d'abord : s'il est injoignable, l'erreur
  /// remonte et le cache local reste, donc le geste pourra être refait en
  /// entier. Effacer le local d'abord donnerait une réussite apparente pour un
  /// travail à moitié fait.
  /// « Retirer mes signalements récents » (§11.4 amendé). En ligne seulement :
  /// c'est un geste de nettoyage fait depuis les Paramètres, pas un geste de
  /// terrain à mettre en file. Le cache local n'est pas touché ici — la carte
  /// se recharge au retour des Paramètres, et le serveur dit ce qui reste.
  Future<int> removeOwnRecent() async => _api.removeOwnRecentHazards(await _device.id);

  /// Déclare le terminal au serveur, une fois par identifiant (§6.3 amendé,
  /// 0250) : le quart d'heure avant « Plus là » part de l'ouverture de l'app,
  /// pas du premier geste. Silencieux en cas d'échec : la prochaine ouverture
  /// réessaiera, et au pire le compteur partira du premier geste, comme avant.
  Future<void> declareDevice() async {
    final id = await _device.id;
    if (await _device.isDeclared(id)) return;
    try {
      await _api.declareDevice(id);
      await _device.markDeclared(id);
    } on Object {
      // Rien à montrer : ce n'est pas un geste de la personne.
    }
  }

  Future<int> forgetOnServer() async {
    final detached = await _api.forgetDevice(await _device.id);
    await clearLocalData();
    return detached;
  }

  /// « Effacer mes données » côté terminal (§11.4) : le cache et la file
  /// disparaissent. Les signalements déjà partis restent sur le serveur — ce
  /// sont des données sur la voirie, pas sur la personne.
  Future<void> clearLocalData() async {
    await _db.batch((batch) {
      batch.deleteWhere(_db.cachedHazards, (_) => const Constant(true));
      batch.deleteWhere(_db.cachedAreas, (_) => const Constant(true));
    });
    _queue.clear();
    _provisional.clear();
    _announce();
  }

  static Hazard _hazardFromRow(CachedHazardRow r) => Hazard(
        id: r.id,
        type: r.type,
        lat: r.lat,
        lng: r.lng,
        severity: Severity.fromValue(r.severity),
        status: HazardStatus.parse(r.status),
        createdAt: r.createdAt,
        lastConfirmedAt: r.lastConfirmedAt,
        confirmWeight: r.confirmWeight,
        resolveWeight: r.resolveWeight,
        resolveThreshold: r.resolveThreshold,
        reportedRemotely: r.reportedRemotely,
        description: r.description,
        address: r.address,
      );

  static HazardType _typeFromRow(CachedTypeRow r) => HazardType(
        code: r.code,
        label: r.label,
        iconName: r.iconName,
        resolvedLabel: r.resolvedLabel,
        dedupRadiusM: r.dedupRadiusM,
        enabled: r.enabled,
        sortOrder: r.sortOrder,
        iconPng: r.iconPng,
      );
}
