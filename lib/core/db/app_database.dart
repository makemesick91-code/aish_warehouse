import 'package:drift/drift.dart';

import '../enums/app_enums.dart';
import '../quantity/quantity.dart';
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

  /// * v1 — initial Milestone 1 schema, quantities in whole units.
  /// * v2 — Milestone 1.1, ledger quantities become fixed-point milli-units.
  ///
  /// Stok Opname must introduce v3 rather than extend v2 (spec §6.3).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // v1 already stored both quantity columns as INTEGER — only their
        // meaning changed, from whole units to milli-units. Scaling the
        // existing rows by `Quantity.scale` is therefore the entire migration:
        // no table rebuild, so every id, timestamp, sync status, foreign key,
        // reversal reference and partial unique index survives untouched.
        //
        // Guarded by `from < 2`, this runs exactly once per database.
        await customStatement(
          'UPDATE stock_balances SET qty_on_hand = qty_on_hand * '
          '${Quantity.scale};',
        );
        await customStatement(
          'UPDATE stock_movements SET qty = qty * ${Quantity.scale};',
        );
      }
    },
    beforeOpen: (details) async {
      // SQLite does not enforce foreign keys unless explicitly asked to.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
