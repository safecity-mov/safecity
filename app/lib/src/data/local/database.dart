import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Base locale (§10).
///
/// Elle ne contient que deux choses : un **cache** de ce que le serveur a déjà
/// dit, et une **file** de ce qu'on n'a pas encore pu lui dire. Jamais une
/// vérité propre. En cas de désaccord, le serveur a raison et le client
/// réaffiche l'état renvoyé.
///
/// **La file d'attente n'est pas ici.** Le §10 la prévoyait sur disque ; elle
/// vit en mémoire, dans `HazardRepository`. Un geste fait sans réseau part dès
/// que le réseau revient, tant que l'app est en vie ; si Android tue le
/// processus avant, il est perdu. Périmètre assumé pour la bêta : la file
/// durable coûtait une table, `workmanager`, et la question de savoir ce que la
/// position du déclarant fait sur un disque (§11.1).
///
/// Conséquence : **rien de ce que cette base contient ne concerne la personne.**
/// Uniquement le catalogue et des dangers, c'est-à-dire des faits sur la voirie.
/// Le fichier est tout de même exclu des sauvegardes Android (voir
/// `AndroidManifest.xml`) : ce qui ne part pas n'a pas à être protégé ailleurs.

/// Le catalogue des types (§3), gardé pour que l'app démarre sans réseau.
@DataClassName('CachedTypeRow')
class CachedTypes extends Table {
  TextColumn get code => text()();
  TextColumn get label => text()();
  TextColumn get iconName => text()();
  TextColumn get resolvedLabel => text()();
  IntColumn get dedupRadiusM => integer()();
  BoolColumn get enabled => boolean()();
  IntColumn get sortOrder => integer()();

  /// La silhouette de marqueur téléversée depuis la console (§4.3).
  ///
  /// Gardée avec le catalogue et non avec le cache de dangers : ce n'est pas une
  /// donnée de position, elle n'a rien à faire dans l'horizon d'oubli du §11.1.
  /// Quelques centaines d'octets par type.
  BlobColumn get iconPng => blob().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

/// Les dangers connus localement, tels que le serveur les a donnés.
///
/// Un signalement créé hors ligne n'est **pas** ici : il n'existe que dans la
/// file en mémoire, avec le marqueur provisoire qui l'accompagne. Sans l'action
/// qui le porte, il n'aurait plus de sens.
@DataClassName('CachedHazardRow')
class CachedHazards extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  IntColumn get severity => integer()();
  TextColumn get status => text()();
  TextColumn get description => text().nullable()();
  TextColumn get address => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastConfirmedAt => dateTime()();
  RealColumn get confirmWeight => real()();
  RealColumn get resolveWeight => real()();
  IntColumn get resolveThreshold => integer()();
  BoolColumn get reportedRemotely => boolean()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Les zones déjà chargées, avec leur date.
///
/// Sans elles, impossible de distinguer « cette zone est vide » de « cette zone
/// n'a jamais été chargée » — la carte afficherait un blanc rassurant et faux.
///
/// Elles s'effacent avec l'horizon d'oubli, au bout de 45 minutes
/// (`HazardRepository.cacheTtl`, §11.7) : la liste des cadres qu'un téléphone a
/// chargés dit où il est passé, même si chaque danger, pris à part, est une
/// donnée publique sur la voirie.
@DataClassName('CachedAreaRow')
class CachedAreas extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get minLat => real()();
  RealColumn get minLng => real()();
  RealColumn get maxLat => real()();
  RealColumn get maxLng => real()();
  DateTimeColumn get fetchedAt => dateTime()();
}

/// Les mesures de la bêta (§4.6), agrégées.
///
/// **Des agrégats, jamais des événements.** Une ligne par indicateur, avec son
/// compte et ses durées — pas une liste horodatée de ce que la personne a fait.
/// Un journal « signalement à 18 h 29 » serait une trace de plus sur le disque,
/// et le §11.7 vient d'en effacer (§11.1 : les mesures sont calculées et
/// stockées sur le terminal, et ne partent que si le testeur les envoie).
///
/// Aucune position, aucun identifiant de danger, aucun horodatage.
@DataClassName('MeasurementRow')
class Measurements extends Table {
  TextColumn get key => text()();
  IntColumn get count => integer().withDefault(const Constant(0))();
  IntColumn get totalMs => integer().withDefault(const Constant(0))();
  IntColumn get minMs => integer().nullable()();
  IntColumn get maxMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [CachedTypes, CachedHazards, CachedAreas, Measurements])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// Pour les tests : une base en mémoire, sans fichier ni répertoire.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // 1 → 2 : les mesures de la bêta. Le cache, lui, se reconstruit tout
          // seul : rien à migrer, et rien à sauver s'il disparaît.
          if (from < 2) await m.createTable(measurements);
          // 2 → 3 : les silhouettes de marqueur. Nullable, donc rien à remplir :
          // le glyphe embarqué continue de servir tant qu'aucune image n'arrive.
          if (from < 3) await m.addColumn(cachedTypes, cachedTypes.iconPng);
          // 3 → 4 : les seuils de résolution ont quitté le catalogue pour une
          // règle unique, côté serveur (§6.1). On jette la table plutôt que de
          // la recopier colonne par colonne : c'est un cache, il se remplit au
          // prochain démarrage et rien n'y est irremplaçable.
          if (from < 4) {
            await m.deleteTable(cachedTypes.actualTableName);
            await m.createTable(cachedTypes);
          }
          // 4 → 6 : le compte de confirmations a disparu au profit du poids
          // « présent », que la feuille de détail met en balance avec le poids
          // « résolu » (§6.1 amendé). Même traitement : c'est un cache.
          if (from < 6) {
            await m.deleteTable(cachedHazards.actualTableName);
            await m.createTable(cachedHazards);
          }
        },
      );

  static QueryExecutor _open() => LazyDatabase(() async {
        // `getApplicationSupportDirectory` plutôt que `Documents` : ce n'est pas
        // un contenu que l'utilisateur manipule, et il ne doit pas apparaître
        // dans un explorateur de fichiers.
        final dir = await getApplicationSupportDirectory();
        return NativeDatabase.createInBackground(
          File(p.join(dir.path, 'app.sqlite')),
        );
      });
}
