import 'package:drift/drift.dart';

import '../enums/app_enums.dart';
import 'converters/enum_converters.dart';
import 'daos/inventory_dao.dart';
import 'daos/master_data_dao.dart';
import 'tables/base_columns.dart';
import 'tables/inventory_tables.dart';
import 'tables/master_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Branches,
    Rooms,
    Users,
    ItemCategories,
    Items,
    ItemBatches,
    StockLocations,
    StockBalances,
    StockMovements,
  ],
  daos: [MasterDataDao, InventoryDao],
)
class AppDatabase extends _$AppDatabase {
  /// The executor is injected so tests can pass an in-memory database while the
  /// app passes the lazily opened file connection.
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Schema is still at version 1; no upgrade steps exist yet. Later
      // milestones add explicit `if (from < n)` blocks here.
    },
    beforeOpen: (details) async {
      // SQLite does not enforce foreign keys unless explicitly asked to.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
