import 'package:drift/drift.dart';

import '../enums/app_enums.dart';
import '../quantity/quantity.dart';
import 'converters/enum_converters.dart';
import 'daos/delivery_order_dao.dart';
import 'daos/distribution_dao.dart';
import 'daos/good_receipt_dao.dart';
import 'daos/inventory_dao.dart';
import 'daos/master_data_dao.dart';
import 'daos/opname_dao.dart';
import 'daos/purchase_request_dao.dart';
import 'tables/base_columns.dart';
import 'tables/delivery_tables.dart';
import 'tables/distribution_tables.dart';
import 'tables/good_receipt_tables.dart';
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
    DeliveryOrders,
    DeliveryOrderLines,
    GoodReceipts,
    GoodReceiptLines,
    Distributions,
    DistributionLines,
  ],
  daos: [
    MasterDataDao,
    InventoryDao,
    OpnameDao,
    PurchaseRequestDao,
    DeliveryOrderDao,
    GoodReceiptDao,
    DistributionDao,
  ],
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
  /// * v6 — Milestone 4, Delivery Order (`delivery_orders`,
  ///   `delivery_order_lines`).
  /// * v7 — Milestone 5, Good Receipt (`good_receipts`, `good_receipt_lines`).
  /// * v8 — Milestone 6, Distribusi (`distributions`, `distribution_lines`).
  @override
  int get schemaVersion => 8;

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
      if (from < 6) {
        // Milestone 4, purely additive in the sense the `from < 3` block
        // established: two new tables and their indexes, and not one statement
        // touching an existing column.
        //
        // The Delivery Order is the first document that *does* post to the
        // ledger (spec §2.5), and this step still does not migrate stock — the
        // posting happens when a document is shipped, at runtime, not when the
        // schema is upgraded. So ledger quantities keep the scaling the
        // `from < 2` block gave them, `stock_opnames` keeps the shape the
        // `from < 4` rebuild left it in, and every Purchase Request row is
        // untouched.
        //
        // It also has to leave `stock_opnames` alone for the second reason the
        // `from < 5` block spells out: the `from < 4` block reads the *current*
        // Dart definition of that table through `alterTable`, so a v6 that
        // changed its shape would make a v3 → v6 upgrade land on the v6 shape at
        // step 4 and then apply step 5 and step 6 on top. Delivery Order only
        // references `purchase_requests`, `items`, `item_batches` and `users` by
        // foreign key, so that trap stays shut.
        await m.createTable(deliveryOrders);
        await m.createTable(deliveryOrderLines);
        for (final statement in _v6DeliveryOrderIndexes) {
          await customStatement(statement);
        }
      }
      if (from < 7) {
        // Milestone 5, purely additive in the sense the `from < 3` block
        // established: two new tables and their indexes, and not one statement
        // touching an existing column.
        //
        // The Good Receipt is the document that *credits* the branch store
        // (spec §2.5), and this step still does not migrate stock — the posting
        // happens when a receipt is posted, at runtime, not when the schema is
        // upgraded. So ledger quantities keep the scaling the `from < 2` block
        // gave them, `stock_opnames` keeps the shape the `from < 4` rebuild left
        // it in, and every Purchase Request and Delivery Order row is untouched.
        //
        // In particular this step does **not** touch `delivery_orders`. A
        // shipment that is already `shipped` stays `shipped`: whether it has been
        // received is a fact a Good Receipt establishes by being posted, and
        // inventing one for the rows already on the device would be a migration
        // asserting a business event that never happened.
        //
        // It also has to leave `stock_opnames` alone for the second reason the
        // `from < 5` block spells out: the `from < 4` block reads the *current*
        // Dart definition of that table through `alterTable`, so a v7 that
        // changed its shape would make a v3 → v7 upgrade land on the v7 shape at
        // step 4 and then apply steps 5, 6 and 7 on top. Good Receipt only
        // references `delivery_orders`, `delivery_order_lines`, `items`,
        // `item_batches` and `users` by foreign key, so that trap stays shut.
        await m.createTable(goodReceipts);
        await m.createTable(goodReceiptLines);
        for (final statement in _v7GoodReceiptIndexes) {
          await customStatement(statement);
        }
      }
      if (from < 8) {
        // Milestone 6, purely additive in the sense the `from < 3` block
        // established: two new tables and their indexes, and not one statement
        // touching an existing column.
        //
        // The Distribusi is the document that moves stock *within* a branch — the
        // branch store down, a room up (spec §2.5) — and this step still does not
        // migrate stock: the posting happens when a document is posted, at runtime,
        // not when the schema is upgraded. So ledger quantities keep the scaling the
        // `from < 2` block gave them, `stock_opnames` keeps the shape the `from < 4`
        // rebuild left it in, and every Purchase Request, Delivery Order and Good
        // Receipt row is untouched.
        //
        // In particular this step invents no distributions for the stock already
        // sitting in rooms. How that stock got there is whatever the ledger already
        // records — an opname adjustment, a seeded opening balance — and writing
        // documents to explain it would be a migration asserting business events
        // that never happened.
        //
        // It also has to leave `stock_opnames` alone for the second reason the
        // `from < 5` block spells out: the `from < 4` block reads the *current* Dart
        // definition of that table through `alterTable`, so a v8 that changed its
        // shape would make a v3 → v8 upgrade land on the v8 shape at step 4 and then
        // apply steps 5, 6, 7 and 8 on top. Distribusi only references `branches`,
        // `rooms`, `users`, `items` and `item_batches` by foreign key, so that trap
        // stays shut.
        await m.createTable(distributions);
        await m.createTable(distributionLines);
        for (final statement in _v8DistributionIndexes) {
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

  /// The Delivery Order indexes **exactly as schema v6 defined them**.
  ///
  /// Frozen as literal SQL for the reason [_v3OpnameIndexes] spells out: a
  /// migration step must keep doing what it did the day it shipped, so this list
  /// must not be derived from `allSchemaEntities` — that getter always describes
  /// the current schema, and a v7 index added to one of these tables would
  /// silently change what the `from < 6` block creates.
  ///
  /// The two partial unique indexes on `delivery_order_lines` are the
  /// load-bearing ones: they are what stops the same `(PR line, batch)` position
  /// being allocated twice on one document, which would double the quantity a
  /// shipment takes out of the warehouse while every per-line check still
  /// passed. `deleted_at IS NULL` is what lets an allocation removed from a
  /// `preparing` document be added back afterwards.
  ///
  /// There is deliberately **no** unique index on `delivery_orders.pr_id`: spec
  /// §2.3 allows one Purchase Request to have several Delivery Orders, and
  /// partial shipment (G-D2) depends on it.
  static const List<String> _v6DeliveryOrderIndexes = [
    'CREATE INDEX IF NOT EXISTS idx_delivery_orders_pr_status '
        'ON delivery_orders (pr_id, status);',
    'CREATE INDEX IF NOT EXISTS idx_delivery_orders_status_created '
        'ON delivery_orders (status, created_at);',
    'CREATE INDEX IF NOT EXISTS idx_delivery_orders_prepared_by_status '
        'ON delivery_orders (prepared_by, status);',
    'CREATE INDEX IF NOT EXISTS idx_delivery_orders_shipped_at '
        'ON delivery_orders (shipped_at);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_orders_doc_number '
        'ON delivery_orders (doc_number) WHERE deleted_at IS NULL;',
    'CREATE INDEX IF NOT EXISTS idx_delivery_order_lines_do '
        'ON delivery_order_lines (do_id);',
    'CREATE INDEX IF NOT EXISTS idx_delivery_order_lines_pr_line '
        'ON delivery_order_lines (pr_line_id);',
    'CREATE INDEX IF NOT EXISTS idx_delivery_order_lines_item '
        'ON delivery_order_lines (item_id);',
    'CREATE INDEX IF NOT EXISTS idx_delivery_order_lines_batch '
        'ON delivery_order_lines (batch_id);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_order_lines_batched '
        'ON delivery_order_lines (do_id, pr_line_id, batch_id) '
        'WHERE batch_id IS NOT NULL AND deleted_at IS NULL;',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_order_lines_unbatched '
        'ON delivery_order_lines (do_id, pr_line_id) '
        'WHERE batch_id IS NULL AND deleted_at IS NULL;',
  ];

  /// The Good Receipt indexes **exactly as schema v7 defined them**.
  ///
  /// Frozen as literal SQL for the reason [_v3OpnameIndexes] spells out: a
  /// migration step must keep doing what it did the day it shipped, so this list
  /// must not be derived from `allSchemaEntities` — that getter always describes
  /// the current schema, and a v8 index added to one of these tables would
  /// silently change what the `from < 7` block creates.
  ///
  /// Two of these are load-bearing, and both are **unqualified** unique indexes
  /// rather than the partial `WHERE deleted_at IS NULL` shape the document-number
  /// indexes use:
  ///
  /// * `idx_good_receipts_do` is the database half of G-G1 (*1 DO = 1 GR*). A
  ///   partial index would let a soft-deleted receipt be followed by a second one
  ///   for the same shipment, and posting that second receipt would credit the
  ///   branch twice from one delivery.
  /// * `idx_good_receipt_lines_unique` is what keeps the snapshot faithful: one
  ///   receipt line per shipped allocation. Nothing removes a receipt line —
  ///   rejecting is a decision, not a deletion (G-G4) — so "live rows only" would
  ///   be a qualification with nothing behind it.
  ///
  /// Losing either on an upgrade path would leave the use cases as the only
  /// guard, which is exactly what two devices checking the same shipment in
  /// defeat.
  static const List<String> _v7GoodReceiptIndexes = [
    'CREATE INDEX IF NOT EXISTS idx_good_receipts_received_by_status '
        'ON good_receipts (received_by, status);',
    'CREATE INDEX IF NOT EXISTS idx_good_receipts_status_created '
        'ON good_receipts (status, created_at);',
    'CREATE INDEX IF NOT EXISTS idx_good_receipts_posted_at '
        'ON good_receipts (posted_at);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_good_receipts_do '
        'ON good_receipts (do_id);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_good_receipts_doc_number '
        'ON good_receipts (doc_number) WHERE deleted_at IS NULL;',
    'CREATE INDEX IF NOT EXISTS idx_good_receipt_lines_gr '
        'ON good_receipt_lines (gr_id);',
    'CREATE INDEX IF NOT EXISTS idx_good_receipt_lines_do_line '
        'ON good_receipt_lines (do_line_id);',
    'CREATE INDEX IF NOT EXISTS idx_good_receipt_lines_item '
        'ON good_receipt_lines (item_id);',
    'CREATE INDEX IF NOT EXISTS idx_good_receipt_lines_batch '
        'ON good_receipt_lines (batch_id);',
    'CREATE INDEX IF NOT EXISTS idx_good_receipt_lines_status '
        'ON good_receipt_lines (line_status);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_good_receipt_lines_unique '
        'ON good_receipt_lines (gr_id, do_line_id);',
  ];

  /// The Distribusi indexes **exactly as schema v8 defined them**.
  ///
  /// Frozen as literal SQL for the reason [_v3OpnameIndexes] spells out: a
  /// migration step must keep doing what it did the day it shipped, so this list
  /// must not be derived from `allSchemaEntities` — that getter always describes the
  /// current schema, and a v9 index added to one of these tables would silently
  /// change what the `from < 8` block creates.
  ///
  /// The two partial unique indexes on `distribution_lines` are the load-bearing
  /// ones: they are what stops the same `(room, item, batch)` position appearing
  /// twice on one document, which would take double the quantity out of the branch
  /// store while every per-line check still passed. `deleted_at IS NULL` is what
  /// lets a line removed from a draft be added back afterwards, and the split
  /// between the batched and unbatched shapes exists because SQLite treats every
  /// NULL as distinct — one index over `(…, batch_id)` would let an item without
  /// expiry be added to the same room any number of times.
  ///
  /// There is deliberately **no** unique index involving `branch_id` and `room_id`:
  /// one document targets several rooms by design (G-T3), and the rule that every
  /// room belongs to the header's branch is a cross-table one SQLite cannot express
  /// at all — it lives in the use cases and is revalidated inside the posting
  /// transaction.
  static const List<String> _v8DistributionIndexes = [
    'CREATE INDEX IF NOT EXISTS idx_distributions_branch_status '
        'ON distributions (branch_id, status);',
    'CREATE INDEX IF NOT EXISTS idx_distributions_distributed_by_status '
        'ON distributions (distributed_by, status);',
    'CREATE INDEX IF NOT EXISTS idx_distributions_created_at '
        'ON distributions (created_at);',
    'CREATE INDEX IF NOT EXISTS idx_distributions_posted_at '
        'ON distributions (posted_at);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_distributions_doc_number '
        'ON distributions (doc_number) WHERE deleted_at IS NULL;',
    'CREATE INDEX IF NOT EXISTS idx_distribution_lines_distribution '
        'ON distribution_lines (distribution_id);',
    'CREATE INDEX IF NOT EXISTS idx_distribution_lines_room '
        'ON distribution_lines (room_id);',
    'CREATE INDEX IF NOT EXISTS idx_distribution_lines_item '
        'ON distribution_lines (item_id);',
    'CREATE INDEX IF NOT EXISTS idx_distribution_lines_batch '
        'ON distribution_lines (batch_id);',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_distribution_lines_batched '
        'ON distribution_lines (distribution_id, room_id, item_id, batch_id) '
        'WHERE batch_id IS NOT NULL AND deleted_at IS NULL;',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_distribution_lines_unbatched '
        'ON distribution_lines (distribution_id, room_id, item_id) '
        'WHERE batch_id IS NULL AND deleted_at IS NULL;',
  ];
}
