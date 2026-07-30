import 'package:drift/drift.dart';

import '../enums/app_enums.dart';
import '../quantity/quantity.dart';
import 'converters/enum_converters.dart';
import 'daos/inventory_dao.dart';
import 'daos/master_data_dao.dart';
import 'daos/opname_dao.dart';
import 'daos/purchase_request_dao.dart';
import 'tables/base_columns.dart';
import 'tables/inventory_tables.dart';
import 'tables/master_tables.dart';
import 'tables/opname_tables.dart';
import 'tables/purchase_request_tables.dart';

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
    StockOpnames,
    StockOpnameLines,
    PurchaseRequests,
    PurchaseRequestOpnames,
    PurchaseRequestLines,
  ],
  daos: [MasterDataDao, InventoryDao, OpnameDao, PurchaseRequestDao],
)
class AppDatabase extends _$AppDatabase {
  /// The executor is injected so tests can pass an in-memory database while the
  /// app passes the lazily opened file connection.
  AppDatabase(super.executor);

  /// * v1 — initial Milestone 1 schema, quantities in whole units.
  /// * v2 — Milestone 1.1, ledger quantities become fixed-point milli-units.
  /// * v3 — Milestone 2, Stok Opname (`stock_opnames`, `stock_opname_lines`).
  /// * v4 — Milestone 2.1, Stok Opname hardening: `stock_opnames` is rebuilt
  ///   without the lexical timestamp-order CHECK.
  /// * v5 — Milestone 3, Purchase Request (`purchase_requests`,
  ///   `purchase_request_opnames`, `purchase_request_lines`).
  @override
  int get schemaVersion => 5;

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
      if (from < 3) {
        // Milestone 2 is purely additive: two new tables and their indexes.
        // No existing column is touched, so ledger quantities, balances,
        // master data and the v1 → v2 scaling above all stay exactly as they
        // are — a v1 database upgrading straight to v3 is scaled once by the
        // block above and then gains the opname tables here.
        await m.createTable(stockOpnames);
        await m.createTable(stockOpnameLines);
        for (final statement in _v3OpnameIndexes) {
          await customStatement(statement);
        }
      }
      if (from < 4) {
        // Milestone 2.1: drop the lexical timestamp-order CHECK from
        // `stock_opnames` (see the note in `opname_tables.dart`). SQLite
        // cannot remove a table CHECK in place, so the table has to be
        // rebuilt.
        //
        // `alterTable` runs sqlite's own 12-step procedure, which is what
        // makes this safe on a device that already holds documents *and*
        // lines: it disables foreign keys for the duration, copies every row
        // across, and re-creates the indexes by reading their DDL back out of
        // `sqlite_master` — so the four opname indexes, partial `WHERE`
        // clauses and all, come back exactly as this database had them rather
        // than as some later version would write them. `stock_opname_lines` is
        // untouched, and its `opname_id` foreign key still resolves because
        // the rebuilt table takes the original name.
        //
        // Unlike the frozen index SQL below, this step *does* read the current
        // Dart definition of `StockOpnames` — that is how it gets the shape
        // without the CHECK. A future v5 that changes the table must therefore
        // rebuild here too, or a device upgrading v3 → v5 would land on the v5
        // shape and then have v5's own step applied on top of it.
        // `migration_v3_to_v4_test.dart` pins the resulting SQL so that
        // mistake fails the suite instead of shipping.
        await m.alterTable(TableMigration(stockOpnames));
      }
      if (from < 5) {
        // Milestone 3 is purely additive, in the sense the `from < 3` block
        // established: three new tables and their indexes, and not one
        // statement touching an existing column. Ledger quantities keep the
        // scaling the `from < 2` block gave them, `stock_opnames` keeps the
        // shape the `from < 4` rebuild left it in, and every opname line,
        // balance and movement is untouched — a Purchase Request never posts to
        // the ledger (spec §2.5), so there is nothing about stock for this step
        // to migrate.
        //
        // It also has to leave `stock_opnames` alone for a second reason: the
        // `from < 4` block above reads the *current* Dart definition of that
        // table through `alterTable`. A v5 that changed its shape would make a
        // v3 → v5 upgrade land on the v5 shape at step 4 and then apply step 5
        // on top. Purchase Request only references `stock_opnames` by foreign
        // key, so that trap stays shut.
        await m.createTable(purchaseRequests);
        await m.createTable(purchaseRequestOpnames);
        await m.createTable(purchaseRequestLines);
        for (final statement in _v5PurchaseRequestIndexes) {
          await customStatement(statement);
        }
      }
    },
    beforeOpen: (details) async {
      // SQLite does not enforce foreign keys unless explicitly asked to.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// The Stok Opname indexes **exactly as schema v3 defined them**.
  ///
  /// `Migrator.createTable` issues only the CREATE TABLE statement, so an
  /// upgrade has to create the indexes itself; a fresh database gets them from
  /// `createAll` instead.
  ///
  /// They are frozen here as literal SQL rather than read from
  /// `allSchemaEntities`, because that getter always describes the *current*
  /// schema, not v3. Deriving the list would mean that adding an opname index
  /// in some future v4 silently changes what the `from < 3` block creates: a
  /// device on v2 would get the v4 index here and then hit
  /// `index … already exists` when the `from < 4` block created it again. A
  /// migration step must keep doing what it did the day it shipped.
  ///
  /// `IF NOT EXISTS` makes the step re-runnable on a database that already has
  /// the tables, which `CREATE TABLE IF NOT EXISTS` above already is.
  static const List<String> _v3OpnameIndexes = [
    'CREATE INDEX IF NOT EXISTS idx_stock_opnames_branch_status '
        'ON stock_opnames (branch_id, status);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_opnames_room_period '
        'ON stock_opnames (room_id, period_year, period_week) '
        'WHERE deleted_at IS NULL;',
    'CREATE INDEX IF NOT EXISTS idx_stock_opnames_counted_by_status '
        'ON stock_opnames (counted_by, status);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_opnames_doc_number '
        'ON stock_opnames (doc_number) WHERE deleted_at IS NULL;',
    'CREATE INDEX IF NOT EXISTS idx_stock_opname_lines_opname '
        'ON stock_opname_lines (opname_id);',
    'CREATE INDEX IF NOT EXISTS idx_stock_opname_lines_item '
        'ON stock_opname_lines (item_id);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_opname_lines_batched '
        'ON stock_opname_lines (opname_id, item_id, batch_id) '
        'WHERE batch_id IS NOT NULL AND deleted_at IS NULL;',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_opname_lines_unbatched '
        'ON stock_opname_lines (opname_id, item_id) '
        'WHERE batch_id IS NULL AND deleted_at IS NULL;',
  ];

  /// The Purchase Request indexes **exactly as schema v5 defined them**.
  ///
  /// Frozen as literal SQL for the reason [_v3OpnameIndexes] spells out: a
  /// migration step must keep doing what it did the day it shipped, so this list
  /// must not be derived from `allSchemaEntities` — that getter always describes
  /// the current schema, and a v6 index added to one of these tables would
  /// silently change what the `from < 5` block creates.
  ///
  /// The two partial unique indexes are the load-bearing ones:
  /// `idx_purchase_requests_active_branch` is the database half of G-P4, and
  /// `idx_purchase_request_lines_item_unique` the database half of G-P2. Losing
  /// either on an upgrade path would leave the use cases as the only guard —
  /// which is exactly what a concurrent submit defeats.
  static const List<String> _v5PurchaseRequestIndexes = [
    'CREATE INDEX IF NOT EXISTS idx_purchase_requests_branch_status '
        'ON purchase_requests (branch_id, status);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_requests_requested_by_status '
        'ON purchase_requests (requested_by, status);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_requests_created_at '
        'ON purchase_requests (created_at);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_requests_needed_date '
        'ON purchase_requests (needed_date);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_requests_active_branch '
        'ON purchase_requests (branch_id) '
        "WHERE status IN ('submitted', 'processing') "
        'AND deleted_at IS NULL;',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_requests_doc_number '
        'ON purchase_requests (doc_number) WHERE deleted_at IS NULL;',
    'CREATE INDEX IF NOT EXISTS idx_purchase_request_opnames_pr '
        'ON purchase_request_opnames (pr_id);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_request_opnames_opname '
        'ON purchase_request_opnames (opname_id);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_request_opnames_unique '
        'ON purchase_request_opnames (pr_id, opname_id) '
        'WHERE deleted_at IS NULL;',
    'CREATE INDEX IF NOT EXISTS idx_purchase_request_lines_pr '
        'ON purchase_request_lines (pr_id);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_request_lines_item '
        'ON purchase_request_lines (item_id);',
    'CREATE UNIQUE INDEX IF NOT EXISTS '
        'idx_purchase_request_lines_item_unique '
        'ON purchase_request_lines (pr_id, item_id) '
        'WHERE deleted_at IS NULL;',
  ];
}
