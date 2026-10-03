import 'package:drift/drift.dart';

import '../ui/labels.dart';
import 'local/database.dart';

/// Les mesures que la bêta doit rendre (§4.6), calculées et gardées ici.
///
/// **Ce n'est pas de la télémétrie** (§11.1). Rien ne part tout seul : il n'y a
/// aucun appel réseau dans ce fichier, et le seul chemin de sortie est un bouton
/// « copier » dans les paramètres, actionné par le testeur.
///
/// Ce sont des **agrégats** : un compte et des durées par indicateur, jamais une
/// liste de ce qui s'est passé et quand. Un journal d'événements horodatés
/// répondrait aux mêmes questions et serait une trace de plus sur le disque,
/// après une journée passée à en effacer (§11.7).
class BetaMeasurements {
  BetaMeasurements(this._db);

  final AppDatabase _db;

  /// Du bouton « Signaler » à la réponse du serveur. **C'est la mesure du §4.6**
  /// — « le signalement tient-il sous 15 secondes ? ».
  ///
  /// La spec dit « entre l'ouverture de la feuille et l'envoi » ; elle a été
  /// écrite avant que le parcours ne place le pin *avant* la feuille. Mesurer à
  /// partir de la feuille laisserait dehors l'ajustement du pin, qui est la
  /// partie lente. Les deux sont donc relevées, et c'est celle-ci qui répond à
  /// la question.
  static const gesture = 'signalement.geste';

  /// De l'ouverture de la feuille à la réponse, au sens littéral de la spec.
  static const sheet = 'signalement.feuille';

  static const sent = 'signalement.envoye';
  static const queued = 'signalement.en_attente';

  /// Anti-doublon (§4.6) : le serveur a proposé un danger existant, et ce que la
  /// personne en a fait. `refuse` est la « détection à tort » que la spec veut
  /// compter — sans ça, elle ne laissait aucune trace nulle part.
  static const duplicateProposed = 'doublon.propose';
  static const duplicateAccepted = 'doublon.confirme';
  static const duplicateRefused = 'doublon.refuse';

  /// File hors-ligne (§10, §4.6).
  static const queueSent = 'file.partie';
  static const queueRefused = 'file.refusee';

  /// Gestes partis sans position : ils pèsent 0,25 au lieu de 1 (§6.2), et la
  /// bêta doit savoir à quelle fréquence ça arrive.
  static const withoutPosition = 'position.absente';
  static const permissionDenied = 'position.refusee';

  /// Libellés d'affichage. Une clé sans libellé reste affichée telle quelle :
  /// mieux vaut une clé brute qu'une mesure invisible.
  static const labels = {
    gesture: 'Durée du geste complet',
    sheet: 'Durée depuis la feuille',
    sent: 'Signalements envoyés',
    queued: 'Signalements mis en attente',
    duplicateProposed: 'Doublons proposés',
    duplicateAccepted: 'Doublons confirmés',
    duplicateRefused: 'Doublons refusés',
    queueSent: 'Gestes partis après coup',
    queueRefused: 'Gestes refusés par le serveur',
    withoutPosition: 'Gestes sans position',
    permissionDenied: 'Permission refusée au moment du geste',
  };

  /// Incrémente un compteur, et enrichit ses durées si [duration] est donnée.
  Future<void> record(String key, {Duration? duration}) async {
    final ms = duration?.inMilliseconds;
    await _db.transaction(() async {
      final existing = await (_db.select(_db.measurements)
            ..where((m) => m.key.equals(key)))
          .getSingleOrNull();

      if (existing == null) {
        await _db.into(_db.measurements).insert(
              MeasurementsCompanion.insert(
                key: key,
                count: const Value(1),
                totalMs: Value(ms ?? 0),
                minMs: Value(ms),
                maxMs: Value(ms),
              ),
            );
        return;
      }

      await (_db.update(_db.measurements)..where((m) => m.key.equals(key))).write(
        MeasurementsCompanion(
          count: Value(existing.count + 1),
          totalMs: Value(existing.totalMs + (ms ?? 0)),
          minMs: Value(_lowest(existing.minMs, ms)),
          maxMs: Value(_highest(existing.maxMs, ms)),
        ),
      );
    });
  }

  Future<List<MeasurementRow>> all() =>
      (_db.select(_db.measurements)..orderBy([(m) => OrderingTerm(expression: m.key)]))
          .get();

  Future<void> clear() => _db.delete(_db.measurements).go();

  /// Le rapport que le testeur copie et nous envoie par le canal qu'il veut.
  ///
  /// Le modèle de téléphone y figure parce que le §4.6 le demande : un geste
  /// perdu peut l'être par la surcouche du constructeur et pas par le code, et
  /// sans le modèle la mesure ne se lit pas.
  Future<String> report({String? deviceModel}) async {
    final rows = await all();
    final lines = <String>[
      '${AppLabels.appName} — mesures de la bêta',
      if (deviceModel != null) 'Appareil : $deviceModel',
      '',
    ];
    if (rows.isEmpty) {
      lines.add('Aucune mesure : aucun signalement n\'a encore été fait.');
    }
    for (final row in rows) {
      final label = labels[row.key] ?? row.key;
      if (row.totalMs > 0) {
        final moyenne = (row.totalMs / row.count / 1000).toStringAsFixed(1);
        lines.add('$label : ${row.count} fois, '
            'moyenne ${moyenne}s, '
            'min ${(row.minMs! / 1000).toStringAsFixed(1)}s, '
            'max ${(row.maxMs! / 1000).toStringAsFixed(1)}s');
      } else {
        lines.add('$label : ${row.count}');
      }
    }
    return lines.join('\n');
  }

  static int? _lowest(int? a, int? b) =>
      a == null ? b : (b == null ? a : (a < b ? a : b));

  static int? _highest(int? a, int? b) =>
      a == null ? b : (b == null ? a : (a > b ? a : b));
}
