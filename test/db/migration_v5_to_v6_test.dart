import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v5 → v6: the two Delivery Order tables are added.
///
/// The step is **purely additive**, and almost everything here is about proving
/// exactly that: not one existing column, row, index or constraint may move. That
/// matters most for the three things earlier migrations touched — the milli-unit
/// scaling the `from < 2` block applied, the `stock_opnames` rebuild the `from < 4`
/// block performed, and the Purchase Request tables `from < 5` created. A v6 that
/// re-scaled quantities would double every balance in the clinic group; a v6 that
/// changed `stock_opnames` would make a v3 → v6 upgrade apply the v4 rebuild to the
/// v6 shape and then apply v5 and v6 on top.
///
/// A v5 database is reproduced by creating the current schema, dropping the two
/// Delivery Order tables and their indexes, and stamping `user_version` back to 5.
/// Because v6 adds nothing else, what remains *is* a v5 database — and one of the
/// tests below pins that assumption by comparing the surviving object list against
/// the v5 inventory.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v5_to_v6.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  late String branchId;
  late String roomId;
  late String nurseId;
  late String headId;
  late String warehouseUserId;
  late String itemId;
  late String warehouseLocationId;
  late String prLineId;

  /// Every object schema v5 had. Anything added to this list by v6 that is not a
  /// Delivery Order object is a migration that is not additive.
  const v5Tables = <String>[
    'branches',
    'rooms',
    'users',
    'item_categories',
    'items',
    'item_batches',
    'stock_locations',
    'stock_balances',
    'stock_movements',
    'stock_opnames',
    'stock_opname_lines',
    'purchase_requests',
    'purchase_request_opnames',
    'purchase_request_lines',
  ];

  const deliveryTables = <String>['delivery_orders', 'delivery_order_lines'];

  const goodReceiptTables = <String>['good_receipts', 'good_receipt_lines'];

  const distributionTables = <String>['distributions', 'distribution_lines'];

  /// Schema v9 own tables, named here so the exhaustive assertions below stay
  /// exhaustive rather than being loosened to `containsAll` every milestone.
  const disposalTables = <String>['disposals', 'disposal_lines'];

  /// The tables versions **after** this migration add. Named here rather than
  /// omitted so the exhaustive table assertion below stays exhaustive: a v11 that
  /// added a table would fail this test until somebody accounted for it.
  const consumptionTables = <String>['consumptions', 'consumption_lines'];

  /// Milestone 9's tables. Declared here — in a test about an *earlier* step — because
  /// every migration lands a device on the current schema, so the exhaustive table
  /// assertions below have to know about every table that exists today.
  const goodsReturnTables = <String>['goods_returns', 'goods_return_lines'];

  const deliveryIndexes = <String>[
    'idx_delivery_orders_pr_status',
    'idx_delivery_orders_status_created',
    'idx_delivery_orders_prepared_by_status',
    'idx_delivery_orders_shipped_at',
    'idx_delivery_orders_doc_number',
    'idx_delivery_order_lines_do',
    'idx_delivery_order_lines_pr_line',
    'idx_delivery_order_lines_item',
    'idx_delivery_order_lines_batch',
    'idx_delivery_order_lines_batched',
    'idx_delivery_order_lines_unbatched',
  ];

  /// Writes a v5 database holding master data, ledger rows with milli-unit
  /// quantities, opnames in every status, and a `processing` Purchase Request with
  /// a line — everything a Delivery Order will later point at.
  Future<void> createVersion5Database() async {
    final database = openDatabase();
    final master = DriftMasterDataRepository(database.masterDataDao);

    final branch = await master.ensureBranch(
      code: 'CAB-01',
      name: 'Cabang Uji',
    );
    branchId = branch.id;
    roomId = (await master.ensureRoom(
      branchId: branch.id,
      code: 'R1',
      name: 'Ruang Dental 1',
    )).id;
    warehouseLocationId = (await master.ensureLocation(
      type: StockLocationType.warehouse,
      name: 'Warehouse Pusat',
    )).id;
    nurseId = (await master.ensureUser(
      email: 'perawat@test.local',
      fullName: 'Perawat Uji',
      role: UserRole.perawat,
      branchId: branch.id,
    )).id;
    headId = (await master.ensureUser(
      email: 'kacab@test.local',
      fullName: 'Kepala Cabang Uji',
      role: UserRole.kepalaCabang,
      branchId: branch.id,
    )).id;
    warehouseUserId = (await master.ensureUser(
      email: 'warehouse@test.local',
      fullName: 'Petugas Warehouse Uji',
      role: UserRole.warehouse,
    )).id;

    final category = await master.ensureCategory('Alat Sekali Pakai');
    itemId = (await master.ensureItem(
      sku: 'TEST-0001',
      name: 'Masker Bedah',
      categoryId: category.id,
      unit: 'box',
      minStockRoom: 5,
      minStockBranch: 20,
      hasExpiry: false,
    )).id;

    // Ledger and balance rows in milli-units — the values the `from < 2` scaling
    // produced. If v6 touched them, `10.5 box` would come back as `10500 box`.
    await database.customStatement(
      'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
      'location_id, item_id, qty_on_hand) VALUES (?, ?, ?, ?, ?, ?, ?);',
      [
        'bal-1',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
        'synced',
        warehouseLocationId,
        itemId,
        Quantity.parse('10.5').milliUnits,
      ],
    );
    await database.customStatement(
      'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
      'item_id, to_location_id, qty, movement_type, ref_doc_type, ref_doc_id, '
      'actor_user_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'mov-1',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
        'synced',
        itemId,
        warehouseLocationId,
        Quantity.parse('10.5').milliUnits,
        'inbound_warehouse',
        'SEED',
        'seed-1',
        nurseId,
      ],
    );

    await database.customStatement(
      'INSERT INTO stock_opnames (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, room_id, period_year, period_week, counted_by, '
      'status, submitted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'so-submitted',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
        'pending',
        'TMP-SO-so-submitted',
        branchId,
        roomId,
        2026,
        30,
        nurseId,
        'submitted',
        '2026-07-24T02:00:00.000Z',
      ],
    );
    await database.customStatement(
      'INSERT INTO stock_opname_lines (id, created_at, updated_at, '
      'sync_status, opname_id, item_id, system_qty, counted_qty, note) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'sol-1',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
        'pending',
        'so-submitted',
        itemId,
        10500,
        9500,
        'Catatan v5',
      ],
    );

    // A `processing` Purchase Request with one line — what a v6 Delivery Order
    // will reference by foreign key.
    await database.customStatement(
      'INSERT INTO purchase_requests (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, requested_by, status, submitted_at, '
      'processing_at, processed_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'pr-1',
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        'pending',
        'TMP-PR-pr-1',
        branchId,
        headId,
        'processing',
        '2026-07-29T04:00:00.000Z',
        '2026-07-29T05:00:00.000Z',
        warehouseUserId,
      ],
    );
    prLineId = 'prl-1';
    await database.customStatement(
      'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
      'sync_status, pr_id, item_id, suggested_qty, requested_qty, note) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        prLineId,
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        'pending',
        'pr-1',
        itemId,
        2500,
        Quantity.parse('3').milliUnits,
        'Catatan PR v5',
      ],
    );
    await database.customStatement(
      'INSERT INTO purchase_request_opnames (id, created_at, updated_at, '
      'sync_status, pr_id, opname_id) VALUES (?, ?, ?, ?, ?, ?);',
      [
        'pro-1',
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        'pending',
        'pr-1',
        'so-submitted',
      ],
    );

    // Drop the Delivery Order objects, leaving exactly a v5 database. Indexes go
    // with their tables in SQLite, so only the tables have to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in deliveryTables) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 5;');
    await database.close();
  }

  /// Index name → its `CREATE INDEX` SQL, for every index whose name mentions
  /// [needle].
  Future<Map<String, String>> indexSqlByName(
    AppDatabase database,
    String needle,
  ) async {
    final rows = await database
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
          "AND sql IS NOT NULL AND name LIKE '%$needle%' ORDER BY name;",
        )
        .get();
    return {
      for (final row in rows) row.read<String>('name'): row.read<String>('sql'),
    };
  }

  Future<Set<String>> objectNames(AppDatabase database, String type) async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = '$type' "
          "AND name NOT LIKE 'sqlite_%';",
        )
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  group('v5 → v6', () {
    test('database v5 dibuka pada versi 6', () async {
      await createVersion5Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 14);

      await database.close();
    });

    test(
      'dua tabel Delivery Order ditambahkan dan tidak ada yang lain',
      () async {
        await createVersion5Database();
        final database = openDatabase();

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(deliveryTables));
        // Exhaustive: v6 adds two tables, no more. Later versions add their
        // own, and naming them here is what keeps this assertion honest rather
        // than loosening it to `containsAll`.
        expect(tables, {
          ...v5Tables,
          ...deliveryTables,
          ...goodReceiptTables,
          ...distributionTables,
          ...disposalTables,
          ...consumptionTables,
          ...goodsReturnTables,
          // Opening an older database migrates it to the current schema, so
          // v12's export audit table is present too.
          'export_logs',
          'import_logs',
          'sync_devices',
          'sync_outbox',
          'sync_entity_states',
          'sync_attempt_logs',
          'sync_conflict_logs',
          'sync_file_uploads',
        });

        await database.close();
      },
    );

    test('seluruh index Delivery Order ditambahkan', () async {
      await createVersion5Database();
      final database = openDatabase();

      final indexes = await objectNames(database, 'index');
      expect(indexes, containsAll(deliveryIndexes));

      await database.close();
    });

    test('index unik parsial dibuat dengan klausa WHERE yang benar', () async {
      await createVersion5Database();
      final database = openDatabase();

      Future<String> sqlOf(String name) async {
        final row = await database
            .customSelect("SELECT sql FROM sqlite_master WHERE name = '$name';")
            .getSingle();
        return row.read<String>('sql');
      }

      // The three load-bearing ones. An upgrade that created them without their
      // WHERE clauses would let the same `(PR line, batch)` position be allocated
      // twice on one document — doubling what the shipment takes out of the
      // warehouse while every per-line check still passed.
      expect(
        await sqlOf('idx_delivery_order_lines_batched'),
        allOf(
          contains('UNIQUE'),
          contains('batch_id IS NOT NULL'),
          contains('deleted_at IS NULL'),
        ),
      );
      expect(
        await sqlOf('idx_delivery_order_lines_unbatched'),
        allOf(
          contains('UNIQUE'),
          contains('batch_id IS NULL'),
          contains('deleted_at IS NULL'),
        ),
      );
      expect(
        await sqlOf('idx_delivery_orders_doc_number'),
        allOf(contains('UNIQUE'), contains('deleted_at IS NULL')),
      );

      await database.close();
    });

    test('tidak ada index unik pada pr_id — satu PR boleh banyak DO', () async {
      // Spec §2.3: "1 PR bisa >1 DO untuk pengiriman parsial". A unique index here
      // would make G-D2's partial shipment impossible, and it is the kind of
      // constraint that looks tidy and quietly breaks the workflow.
      await createVersion5Database();
      final database = openDatabase();

      final rows = await database
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE '%delivery_orders%' AND sql IS NOT NULL;",
          )
          .get();
      for (final row in rows) {
        final sql = row.read<String>('sql');
        if (!sql.contains('UNIQUE')) continue;
        expect(
          sql.contains('(pr_id)'),
          isFalse,
          reason:
              '${row.read<String>('name')} membuat pr_id unik, sehingga '
              'pengiriman parsial tidak mungkin.',
        );
      }

      await database.close();
    });

    test('SQL index hasil migrasi identik dengan database v6 baru', () async {
      // The `from < 6` block creates the indexes from a **frozen literal list**,
      // because deriving them from `allSchemaEntities` would make a future v7 index
      // silently change what this step does. The cost of freezing them is that the
      // list can drift away from the `@TableIndex` declarations, and nothing in the
      // Dart compiler would notice. This test is the thing that notices: it
      // compares the SQL a migrated database ends up with against the SQL a fresh
      // one gets from `createAll`.
      await createVersion5Database();
      final migrated = openDatabase();
      final migratedSql = await indexSqlByName(migrated, 'delivery_order');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v6.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshSql = await indexSqlByName(fresh, 'delivery_order');
      await fresh.close();
      await freshFile.delete();

      expect(migratedSql.keys, freshSql.keys);
      for (final name in freshSql.keys) {
        expect(
          _normalizeSql(migratedSql[name]!),
          _normalizeSql(freshSql[name]!),
          reason:
              '$name berbeda antara database yang bermigrasi dan database baru. '
              'Perbarui _v6DeliveryOrderIndexes agar cocok dengan deklarasi '
              '@TableIndex.',
        );
      }
    });

    test('index inventory, opname dan PR lama tidak hilang', () async {
      await createVersion5Database();
      final database = openDatabase();

      final indexes = await objectNames(database, 'index');
      expect(
        indexes,
        containsAll(<String>[
          'idx_stock_opnames_room_period',
          'idx_stock_opnames_doc_number',
          'idx_stock_opname_lines_batched',
          'idx_stock_opname_lines_unbatched',
          'idx_purchase_requests_active_branch',
          'idx_purchase_requests_doc_number',
          'idx_purchase_request_lines_item_unique',
        ]),
      );

      await database.close();
    });

    test('kuantitas ledger tidak diskalakan ulang', () async {
      await createVersion5Database();
      final database = openDatabase();

      final balance = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
          )
          .getSingle();
      final movement = await database
          .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-1';")
          .getSingle();

      expect(balance.read<int>('qty_on_hand'), 10500);
      expect(movement.read<int>('qty'), 10500);

      await database.close();
    });

    test('dokumen opname dan Purchase Request utuh', () async {
      await createVersion5Database();
      final database = openDatabase();

      final opnameLine = await database
          .customSelect("SELECT * FROM stock_opname_lines WHERE id = 'sol-1';")
          .getSingle();
      expect(opnameLine.read<int>('system_qty'), 10500);
      expect(opnameLine.read<int>('counted_qty'), 9500);
      // The generated column still computes, so the v4 table was not rebuilt.
      expect(opnameLine.read<int>('difference'), -1000);
      expect(opnameLine.read<String>('note'), 'Catatan v5');

      final request = await database
          .customSelect("SELECT * FROM purchase_requests WHERE id = 'pr-1';")
          .getSingle();
      expect(request.read<String>('status'), 'processing');
      expect(request.read<String>('processed_by'), warehouseUserId);

      final prLine = await database
          .customSelect(
            "SELECT * FROM purchase_request_lines WHERE id = 'prl-1';",
          )
          .getSingle();
      expect(prLine.read<int>('requested_qty'), 3000);
      expect(prLine.read<String>('note'), 'Catatan PR v5');

      final link = await database
          .customSelect('SELECT COUNT(*) AS c FROM purchase_request_opnames;')
          .getSingle();
      expect(link.read<int>('c'), 1);

      await database.close();
    });

    test(
      'CHECK opname hasil hardening v4 tetap tanpa perbandingan leksikal',
      () async {
        await createVersion5Database();
        final database = openDatabase();

        final row = await database
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'stock_opnames';",
            )
            .getSingle();
        final sql = row.read<String>('sql');

        expect(sql, isNot(contains('reviewed_at >= submitted_at')));
        expect(sql, contains("status IN ('draft', 'submitted', 'reviewed')"));

        await database.close();
      },
    );

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion5Database();
      final database = openDatabase();

      final pragma = await database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      final violations = await database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);

      await database.close();
    });

    test('index unik alokasi menolak duplikasi setelah migrasi', () async {
      await createVersion5Database();
      final database = openDatabase();

      Future<void> insertDeliveryOrder(String id) => database.customStatement(
        'INSERT INTO delivery_orders (id, created_at, updated_at, sync_status, '
        'doc_number, pr_id, prepared_by, status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-30T03:00:00.000Z',
          '2026-07-30T03:00:00.000Z',
          'pending',
          'TMP-DO-$id',
          'pr-1',
          warehouseUserId,
          'preparing',
        ],
      );
      Future<void> insertLine(String id) => database.customStatement(
        'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
        'sync_status, do_id, pr_line_id, item_id, shipped_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-30T03:00:00.000Z',
          '2026-07-30T03:00:00.000Z',
          'pending',
          'do-1',
          prLineId,
          itemId,
          1000,
        ],
      );

      await insertDeliveryOrder('do-1');
      await insertLine('dol-1');
      expect(
        () => insertLine('dol-2'),
        throwsA(anything),
        reason:
            'Index parsial harus menolak alokasi kedua untuk baris PR yang sama '
            'tanpa batch.',
      );

      // A second Delivery Order against the same request must be accepted — that
      // is what partial shipment depends on.
      await insertDeliveryOrder('do-2');
      final count = await database
          .customSelect(
            "SELECT COUNT(*) AS c FROM delivery_orders WHERE pr_id = 'pr-1';",
          )
          .getSingle();
      expect(count.read<int>('c'), 2);

      await database.close();
    });

    test('CHECK status dan timestamp pengiriman ditegakkan', () async {
      await createVersion5Database();
      final database = openDatabase();

      Future<void> insert({
        required String id,
        required String status,
        String? shippedAt,
        String? shippedBy,
      }) => database.customStatement(
        'INSERT INTO delivery_orders (id, created_at, updated_at, sync_status, '
        'doc_number, pr_id, prepared_by, status, shipped_at, shipped_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-30T03:00:00.000Z',
          '2026-07-30T03:00:00.000Z',
          'pending',
          'TMP-DO-$id',
          'pr-1',
          warehouseUserId,
          status,
          shippedAt,
          shippedBy,
        ],
      );

      // An unknown status cannot be introduced by a hand-written INSERT.
      expect(
        () => insert(id: 'bad-status', status: 'cancelled'),
        throwsA(anything),
      );
      // A `preparing` document carries no shipping pair…
      expect(
        () => insert(
          id: 'bad-preparing',
          status: 'preparing',
          shippedAt: '2026-07-30T04:00:00.000Z',
          shippedBy: warehouseUserId,
        ),
        throwsA(anything),
      );
      // …and a `shipped` one carries both halves of it.
      expect(
        () => insert(
          id: 'bad-shipped',
          status: 'shipped',
          shippedAt: '2026-07-30T04:00:00.000Z',
        ),
        throwsA(anything),
      );
      await insert(
        id: 'good-shipped',
        status: 'shipped',
        shippedAt: '2026-07-30T04:00:00.000Z',
        shippedBy: warehouseUserId,
      );

      await database.close();
    });

    test(
      'CHECK baris menolak qty nol, alasan kosong dan audit tanpa batch',
      () async {
        await createVersion5Database();
        final database = openDatabase();

        await database.customStatement(
          'INSERT INTO delivery_orders (id, created_at, updated_at, sync_status, '
          'doc_number, pr_id, prepared_by, status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
          [
            'do-1',
            '2026-07-30T03:00:00.000Z',
            '2026-07-30T03:00:00.000Z',
            'pending',
            'TMP-DO-do-1',
            'pr-1',
            warehouseUserId,
            'preparing',
          ],
        );

        Future<void> insertLine({
          required String id,
          int qty = 1000,
          String? reason,
          int nearExpiryConfirmed = 0,
          String? nearExpiryNote,
        }) => database.customStatement(
          'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
          'sync_status, do_id, pr_line_id, item_id, shipped_qty, '
          'fefo_override_reason, near_expiry_confirmed, near_expiry_note) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            id,
            '2026-07-30T03:00:00.000Z',
            '2026-07-30T03:00:00.000Z',
            'pending',
            'do-1',
            prLineId,
            itemId,
            qty,
            reason,
            nearExpiryConfirmed,
            nearExpiryNote,
          ],
        );

        // `shipped_qty > 0`: a zero allocation is an absent line, not a shipment.
        expect(() => insertLine(id: 'zero', qty: 0), throwsA(anything));
        // Whitespace is not a reason — `trim(...) <> ''` says so in SQL too.
        expect(() => insertLine(id: 'blank', reason: '   '), throwsA(anything));
        // The item has no expiry, so the line carries no batch — and therefore no
        // FEFO override and no near-expiry confirmation either.
        expect(
          () => insertLine(id: 'audit-no-batch', reason: 'alasan'),
          throwsA(anything),
        );
        expect(
          () => insertLine(id: 'confirm-no-batch', nearExpiryConfirmed: 1),
          throwsA(anything),
        );
        // A note without a confirmation would explain a decision nobody made.
        expect(
          () => insertLine(id: 'note-only', nearExpiryNote: 'catatan'),
          throwsA(anything),
        );

        await insertLine(id: 'ok');

        await database.close();
      },
    );

    test('membuka ulang database v6 tidak menjalankan migrasi lagi', () async {
      await createVersion5Database();

      final first = openDatabase();
      await first.customSelect('SELECT 1;').getSingle();
      await first.close();

      // Re-running the `from < 6` block would fail on `CREATE TABLE` for an
      // existing table; that it does not is what makes the step re-runnable.
      final second = openDatabase();
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 14);

      final tables = await objectNames(second, 'table');
      expect(tables, containsAll(deliveryTables));
      await second.close();
    });
  });

  group('rantai lengkap', () {
    /// Rewinds a freshly created database to [version] by removing everything the
    /// migrations after it added, so the real `MigrationStrategy` runs on reopen.
    Future<void> rewindTo(int version) async {
      final database = openDatabase();
      final master = DriftMasterDataRepository(database.masterDataDao);

      final branch = await master.ensureBranch(
        code: 'CAB-01',
        name: 'Cabang Uji',
      );
      branchId = branch.id;
      warehouseLocationId = (await master.ensureLocation(
        type: StockLocationType.warehouse,
        name: 'Warehouse Pusat',
      )).id;
      final category = await master.ensureCategory('Alat Sekali Pakai');
      itemId = (await master.ensureItem(
        sku: 'TEST-0001',
        name: 'Masker Bedah',
        categoryId: category.id,
        unit: 'box',
        minStockRoom: 5,
        minStockBranch: 20,
        hasExpiry: false,
      )).id;

      // v1 stored whole units, so a v1 database holds `10`, not `10500`.
      final qty = version < 2 ? 10 : 10500;
      await database.customStatement(
        'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
        'location_id, item_id, qty_on_hand) VALUES (?, ?, ?, ?, ?, ?, ?);',
        [
          'bal-1',
          '2026-01-01T00:00:00.000Z',
          '2026-01-01T00:00:00.000Z',
          'synced',
          warehouseLocationId,
          itemId,
          qty,
        ],
      );

      await database.customStatement('PRAGMA foreign_keys = OFF;');
      for (final table in deliveryTables) {
        await database.customStatement('DROP TABLE IF EXISTS $table;');
      }
      if (version < 5) {
        await database.customStatement(
          'DROP TABLE IF EXISTS purchase_request_lines;',
        );
        await database.customStatement(
          'DROP TABLE IF EXISTS purchase_request_opnames;',
        );
        await database.customStatement(
          'DROP TABLE IF EXISTS purchase_requests;',
        );
      }
      if (version < 3) {
        await database.customStatement(
          'DROP TABLE IF EXISTS stock_opname_lines;',
        );
        await database.customStatement('DROP TABLE IF EXISTS stock_opnames;');
      }
      await database.customStatement('PRAGMA foreign_keys = ON;');
      await database.customStatement('PRAGMA user_version = $version;');
      await database.close();
    }

    /// Every version between v1 and v5 must land on v6 with the delivery tables in
    /// place, the quantities scaled exactly once, and no foreign key violation.
    for (final from in [1, 2, 3, 4, 5]) {
      test('database v$from bermigrasi hingga v6', () async {
        await rewindTo(from);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 14);

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(deliveryTables));
        expect(
          tables,
          containsAll(<String>[
            'stock_opnames',
            'stock_opname_lines',
            'purchase_requests',
            'purchase_request_opnames',
            'purchase_request_lines',
          ]),
        );

        final indexes = await objectNames(database, 'index');
        expect(indexes, containsAll(deliveryIndexes));

        // Scaled exactly once: a v1 `10` becomes `10000`, and anything already in
        // milli-units stays where it was.
        final balance = await database
            .customSelect(
              "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
            )
            .getSingle();
        expect(
          balance.read<int>('qty_on_hand'),
          from < 2 ? 10 * Quantity.scale : 10500,
        );

        // v4's rebuild must still have happened on the way through.
        final opnameSql = await database
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'stock_opnames';",
            )
            .getSingle();
        expect(
          opnameSql.read<String>('sql'),
          isNot(contains('reviewed_at >= submitted_at')),
        );

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        await database.close();
      });
    }
  });
}

/// Collapses whitespace so `IF NOT EXISTS` and line breaks do not make two
/// equivalent statements look different.
String _normalizeSql(String sql) => sql
    .replaceAll('IF NOT EXISTS ', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();
