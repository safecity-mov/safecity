import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'data/api_client.dart';
import 'data/announcements.dart';
import 'data/app_update.dart';
import 'data/device_identity.dart';
import 'data/hazard_repository.dart';
import 'data/local/database.dart';
import 'data/models/hazard_type.dart';
import 'data/trace_horizon.dart';
import 'location/location_service.dart';
import 'ui/labels.dart';
import 'ui/map_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppLabels.appName,
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: const _Bootstrap(),
      );
}

/// Démarrage : catalogue, style de carte, onboarding.
///
/// Le catalogue vient du serveur et pilote l'UI (§3) : tant qu'il n'est pas
/// chargé, il n'y a pas d'écran à dessiner.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  static const _onboardingKey = 'onboarding_done';

  final _api = ApiClient();
  final _db = AppDatabase();
  final _device = DeviceIdentity();
  final _location = LocationService();
  final _traces = TraceHorizon();
  final _updates = UpdateChecker();
  late final _announcements = AnnouncementChecker(api: _api);
  late final _repo = HazardRepository(api: _api, db: _db, device: _device);
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  List<HazardType>? _types;
  String? _mapStyle;
  bool _onboarded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // Le natif purge à chaque entrée et sortie d'écran, et par alarme quand
    // l'app dort. Ce minuteur-ci ne couvre que la session qui dure plus que
    // l'horizon sans jamais passer en arrière-plan — une longue sortie à vélo,
    // précisément le cas qui compte (§11.1).
    _traces.start();
    _load();
  }

  @override
  void dispose() {
    _traces.stop();
    unawaited(_repo.dispose());
    unawaited(_db.close());
    _api.dispose();
    _updates.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // Le style est un asset : le fond de carte n'est pas négociable au runtime,
      // et l'app ne va chercher de style sur aucun domaine tiers (§7, §11.5).
      final style = (await rootBundle.loadString('assets/map_style.json'))
          .replaceAll('{{TILES_BASE}}', AppConfig.tilesBaseUrl);

      // Le dépôt sert le catalogue du serveur, ou celui de la dernière fois :
      // sans catalogue il n'y a pas d'écran à dessiner, pas même hors ligne (§3).
      final types = await _repo.types();
      final onboarded = await _storage.read(key: _onboardingKey) == 'true';
      // Le serveur apprend que ce terminal existe dès maintenant : le quart
      // d'heure avant « Plus là » (§6.3) court depuis l'ouverture, pas depuis
      // le premier geste. Sans attendre la réponse, l'écran n'en dépend pas.
      unawaited(_repo.declareDevice());

      if (!mounted) return;
      setState(() {
        _mapStyle = style;
        _types = types;
        _onboarded = onboarded;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _finishOnboarding() async {
    // La demande de permission fait partie de l'onboarding : elle arrive avec son
    // contexte, pas en pop-up nue au premier lancement (§9).
    await _location.requestPermission();
    await _storage.write(key: _onboardingKey, value: 'true');
    if (mounted) setState(() => _onboarded = true);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      // « Vérifiez votre connexion » n'est vrai que pour une panne réseau. Une
      // réponse illisible ou une migration locale qui échoue ne s'arrangent
      // pas en changeant de Wi-Fi : autant dire ce qui s'est passé.
      return _StartupError(
        message: switch (error) {
          ApiException(:final message) when !HazardRepository.isTransient(error) => message,
          _ when HazardRepository.isTransient(error) => StartupLabels.unreachable,
          _ => StartupLabels.failed('$error'),
        },
        onRetry: _load,
      );
    }

    final types = _types;
    final style = _mapStyle;
    if (types == null || style == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_onboarded) {
      return OnboardingScreen(onStart: _finishOnboarding);
    }

    return MapScreen(
      repo: _repo,
      device: _device,
      location: _location,
      types: types,
      mapStyle: style,
      updates: _updates,
      announcements: _announcements,
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 44, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: onRetry, child: const Text(StartupLabels.retry)),
              ],
            ),
          ),
        ),
      );
}
