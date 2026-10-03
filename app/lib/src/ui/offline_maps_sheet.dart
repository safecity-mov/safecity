import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../data/offline_maps.dart';
import 'labels.dart';

/// Cartes hors-ligne (§10).
///
/// Le cache de MapLibre tient une quarantaine de tuiles : trois ou quatre
/// écrans, dont un trajet sort tout de suite. Cet écran permet d'embarquer une
/// zone entière, jusqu'au zoom où le pin se place.
///
/// Rien n'y est deviné à la place de l'utilisateur : c'est lui qui cadre la zone
/// sur la carte, et le téléchargement ne parle qu'à l'instance de l'application (§7).
class OfflineMapsSheet extends StatefulWidget {
  const OfflineMapsSheet({
    super.key,
    required this.maps,
    required this.visible,
    this.aroundStreet,
  });

  final OfflineMaps maps;

  /// La zone actuellement à l'écran, celle qu'on propose d'embarquer.
  final LatLngBounds visible;

  /// La voie au centre de la zone, lue dans le fond de carte (§7). Sert à
  /// nommer ce qu'on embarque ; `null` si la carte ne la connaît pas.
  final String? aroundStreet;

  @override
  State<OfflineMapsSheet> createState() => _OfflineMapsSheetState();
}

class _OfflineMapsSheetState extends State<OfflineMapsSheet> {
  List<OfflineRegion>? _regions;
  double? _progress;
  int _downloadedBytes = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final regions = await widget.maps.regions();
      if (mounted) setState(() => _regions = regions);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _downloadedBytes = 0;
      _error = null;
    });
    try {
      await widget.maps.download(
        bounds: widget.visible,
        name: widget.aroundStreet ?? OfflineLabels.defaultAreaName(_today()),
        onProgress: (fraction, bytes) {
          if (mounted) {
            setState(() {
              _progress = fraction;
              _downloadedBytes = bytes;
            });
          }
        },
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _progress = null);
      await _refresh();
    }
  }

  /// La zone affichée est-elle déjà entièrement embarquée ?
  ///
  /// La comparaison porte sur l'inclusion, pas sur l'égalité : une zone plus
  /// large déjà téléchargée couvre celle-ci, et la retélécharger n'ajouterait
  /// rien — sinon une seconde région, et deux entrées dans la liste pour le
  /// même fond de carte.
  bool get _alreadyCovered => (_regions ?? const []).any((region) {
        final r = region.definition.bounds;
        final v = widget.visible;
        return r.southwest.latitude <= v.southwest.latitude &&
            r.southwest.longitude <= v.southwest.longitude &&
            r.northeast.latitude >= v.northeast.latitude &&
            r.northeast.longitude >= v.northeast.longitude;
      });

  Future<void> _remove(OfflineRegion region) async {
    await widget.maps.remove(region.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = OfflineMaps.tileCount(widget.visible);
    final tooLarge = tiles > OfflineMaps.maxTiles;
    final busy = _progress != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(OfflineLabels.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(OfflineLabels.intro, style: theme.textTheme.bodyMedium),

            const SizedBox(height: 10),
            // Ce qu'une zone embarquée ne contient pas. Dit avant de télécharger,
            // pas découvert sans réseau une heure plus tard (§10, §11.7).
            Text(
              OfflineLabels.noHazards,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 20),
            _Row(
              icon: Icons.crop_free,
              title: OfflineLabels.visibleArea,
              subtitle: tooLarge
                  ? OfflineLabels.tooLarge(tiles)
                  : OfflineLabels.areaSize(
                      tiles,
                      formatBytes(OfflineMaps.estimatedBytes(widget.visible)),
                    ),
            ),

            if (busy) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(
                OfflineLabels.progress(
                  ((_progress ?? 0) * 100).round(),
                  formatBytes(_downloadedBytes),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              ),
            ],

            const SizedBox(height: 16),
            // Couverte, le bouton le dit et ne propose plus rien : garder
            // « Télécharger » actif laisserait croire qu'il reste à faire.
            FilledButton.icon(
              onPressed: busy || tooLarge || _alreadyCovered ? null : _download,
              icon: Icon(
                _alreadyCovered
                    ? Icons.download_done_outlined
                    : Icons.download_for_offline_outlined,
              ),
              label: Text(
                _alreadyCovered ? OfflineLabels.alreadyDownloaded : OfflineLabels.download,
              ),
            ),

            const SizedBox(height: 20),
            Text(OfflineLabels.downloadedSection, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (_regions == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_regions!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(OfflineLabels.none, style: theme.textTheme.bodyMedium),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final region in _regions!)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.map_outlined, size: 20),
                        title: Text(
                          region.metadata['name'] as String? ?? OfflineLabels.unnamed,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          _describe(region.definition.bounds),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          tooltip: OfflineLabels.remove,
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: busy ? null : () => _remove(region),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}';
  }

  /// Sous-titre d'une zone embarquée : son étendue au sol.
  ///
  /// La coordonnée du centre y figurait ; elle ne disait rien d'utile — on sait
  /// déjà où on est par le nom de la voie — et c'était la seule donnée de
  /// l'écran qui concerne la personne plutôt que la voirie : la zone qu'elle a
  /// choisi d'emporter. La dimension répond à la vraie question, « est-ce que
  /// ça couvre mon trajet ».
  static String _describe(LatLngBounds bounds) {
    const kmParDegre = 111.32;
    final milieu = (bounds.southwest.latitude + bounds.northeast.latitude) / 2;
    final hauteur = (bounds.northeast.latitude - bounds.southwest.latitude) * kmParDegre;
    final largeur = (bounds.northeast.longitude - bounds.southwest.longitude) *
        kmParDegre *
        math.cos(milieu * math.pi / 180);
    return '${_distance(largeur)} × ${_distance(hauteur)}';
  }

  /// En mètres tant qu'on est sous le kilomètre : « 700 m » se décide plus vite
  /// que « 0,7 km ».
  static String _distance(double km) =>
      km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
}

/// Un volume en unités lisibles. Les tailles de zone se comptent en mégaoctets,
/// et « 44 Mo » se décide plus vite que « 46 137 344 octets ».
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} Ko';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).round()} Mo';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      );
}
