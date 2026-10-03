import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../data/api_client.dart';
import '../data/app_update.dart';
import '../data/device_identity.dart';
import '../data/hazard_repository.dart';
import '../data/trace_horizon.dart';
import '../location/location_service.dart';
import 'labels.dart';
import 'markdown_view.dart';

/// Paramètres (§4.1 F8).
///
/// Deux boutons qui font quelque chose d'irréversible, un texte qui explique
/// pourquoi on peut s'en passer, et de quoi savoir ce qu'on a installé. Rien
/// d'autre : il n'y a aucune préférence à régler dans cette app, et une page de
/// réglages vide de réglages est le bon endroit pour mettre les droits.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repo,
    required this.device,
    required this.location,
    this.updates,
  });

  final HazardRepository repo;
  final DeviceIdentity device;
  final LocationService location;

  /// Pour « vérifier les mises à jour » à la demande (§12.6). Nul, la ligne
  /// de version reste un simple texte.
  final UpdateChecker? updates;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  /// Nul tant que la réponse n'est pas arrivée.
  UpdateCheck? _updateCheck;

  @override
  void initState() {
    super.initState();
    unawaited(_checkUpdates());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(SettingsLabels.title),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: ListView(
        children: [
          _Heading(SettingsLabels.dataSection),
          // Retirer d'abord, effacer ensuite : dans cet ordre à l'écran, parce
          // que c'est le seul ordre qui marche. Une fois le lien coupé, le
          // serveur ne sait plus lesquels retirer.
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text(SettingsLabels.removeRecent),
            subtitle: const Text(SettingsLabels.removeRecentHint),
            onTap: _busy ? null : _removeRecent,
          ),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text(SettingsLabels.forget),
            subtitle: const Text(SettingsLabels.forgetHint),
            onTap: _busy ? null : _forget,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              SettingsLabels.dataNotice,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const Divider(),
          _Heading(SettingsLabels.privacySection),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text(SettingsLabels.privacy),
            subtitle: Text(SettingsLabels.privacyHint(TraceHorizon.maxAge.inMinutes)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
            ),
          ),
          const Divider(),
          _Heading(SettingsLabels.aboutSection),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text(AppLabels.appName),
            subtitle: Text(
              widget.updates == null
                  ? SettingsLabels.version(AppConfig.version)
                  : '${SettingsLabels.version(AppConfig.version)}\n$_updateLine',
            ),
            isThreeLine: widget.updates != null,
            onTap: _onVersionTap,
          ),
          const ListTile(
            leading: Icon(Icons.balance),
            title: Text(SettingsLabels.licences),
            subtitle: Text(SettingsLabels.licencesBody),
            isThreeLine: true,
          ),
          const ListTile(
            leading: Icon(Icons.map_outlined),
            title: Text(SettingsLabels.basemap),
            subtitle: Text(SettingsLabels.basemapBody),
            isThreeLine: true,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Demande au serveur s'il y a plus récent, dès l'ouverture de l'écran.
  ///
  /// Le bandeau de la carte ne parle qu'au lancement et quand il a quelque
  /// chose à dire. Ici la personne est venue voir sa version : on lui répond
  /// toujours, « à jour » compris, sous le numéro. Même requête que la carte,
  /// qui ne porte rien (§11.5).
  Future<void> _checkUpdates() async {
    final checker = widget.updates;
    if (checker == null) return;
    setState(() => _updateCheck = null);
    final result = await checker.probe();
    if (!mounted) return;
    setState(() => _updateCheck = result);
  }

  /// Ce que la ligne de version fait quand on la touche : télécharger s'il y
  /// a plus récent, revérifier si la dernière réponse n'était pas exploitable,
  /// rien sinon.
  VoidCallback? get _onVersionTap => switch (_updateCheck) {
        UpdateAvailable(:final update) => () => const ExternalLinks().open(update.url),
        UpdateUnavailable() => _checkUpdates,
        _ => null,
      };

  String get _updateLine => switch (_updateCheck) {
        null => SettingsLabels.checkingUpdates,
        UpToDate() => SettingsLabels.upToDate,
        UpdateAvailable(:final update) => SettingsLabels.updateFound(update.versionName),
        UpdateUnavailable() => SettingsLabels.updateCheckFailed,
      };

  /// Retire d'un coup ses signalements de moins de 24 h (§11.4 amendé).
  ///
  /// En ligne seulement, et rien ne bouge si le serveur ne répond pas : le
  /// geste reste à refaire, et on le dit. La carte se recharge au retour.
  Future<void> _removeRecent() async {
    final confirmed = await _confirm(
      title: SettingsLabels.removeRecentConfirmTitle,
      body: SettingsLabels.removeRecentConfirmBody,
      action: SettingsLabels.removeRecentConfirmAction,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final removed = await widget.repo.removeOwnRecent();
      if (!mounted) return;
      _say(removed == 0 ? SettingsLabels.nothingToRemove : SettingsLabels.removedRecent(removed));
    } on Object catch (error) {
      if (!mounted) return;
      _say(error is ApiException ? error.message : SettingsLabels.removeRecentUnreachable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Coupe le lien des deux côtés : le serveur oublie, le téléphone repart
  /// d'un numéro neuf (§11.4, amendé : les deux gestes n'en font plus qu'un).
  ///
  /// La partie locale ne dépend de personne et se fait toujours — c'est la
  /// promesse « jetable, sans rien demander ». Si le serveur est injoignable,
  /// on le dit : le lien avec l'ancien numéro tiendra jusqu'à la coupure
  /// automatique des 24 heures, et pas plus.
  Future<void> _forget() async {
    final confirmed = await _confirm(
      title: SettingsLabels.forgetConfirmTitle,
      body: SettingsLabels.forgetConfirmBody,
      action: SettingsLabels.forgetConfirmAction,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    int? detached;
    String? refusal;
    try {
      detached = await widget.repo.forgetOnServer();
    } on ApiException catch (error) {
      // Le serveur a répondu, et refusé : il a une raison, on la montre et on
      // ne touche à rien — un refus n'est pas une panne.
      refusal = error.message;
    } on Object {
      detached = null;
    }

    try {
      if (refusal == null) {
        await widget.device.regenerate();
        await widget.repo.clearLocalData();
        await widget.repo.measurements.clear();
        widget.location.forget();
      }
      if (!mounted) return;
      _say(switch ((refusal, detached)) {
        (final String message, _) => message,
        (_, null) => SettingsLabels.forgottenLocallyOnly,
        (_, 0) => SettingsLabels.nothingAttached,
        (_, final int count) => SettingsLabels.detached(count),
      },);
    } finally {
      // Sans `finally`, une écriture qui échoue laissait l'écran grisé pour de bon.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(SettingsLabels.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  /// Le dernier message remplace le précédent : deux gestes d'affilée ne
  /// doivent pas faire attendre le second compte rendu derrière le premier.
  void _say(String message) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Le texte de confidentialité, en deux longueurs.
///
/// La version courte, `assets/privacy.md`, tient en une page : c'est celle
/// qu'on ouvre depuis les Paramètres. La longue, `assets/privacy-full.md`,
/// copie de `PRIVACY.md`, dit où vérifier chaque phrase dans le code ; elle
/// s'ouvre depuis le bas de la courte. Affichées depuis les assets plutôt que
/// réécrites en widgets : deux formulations de la même promesse finiraient par
/// diverger, et c'est la version écrite qui engage.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, this.detailed = false});

  final bool detailed;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(detailed ? SettingsLabels.privacyDetailedTitle : SettingsLabels.privacyTitle),
        ),
        body: FutureBuilder<String>(
          future: rootBundle.loadString(detailed ? 'assets/privacy-full.md' : 'assets/privacy.md'),
          builder: (context, snapshot) {
            final text = snapshot.data;
            if (text == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MarkdownView(source: text),
                  if (!detailed) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivacyScreen(detailed: true),
                        ),
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text(SettingsLabels.privacyDetailed),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}
