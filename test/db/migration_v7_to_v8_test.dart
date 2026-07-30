import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v7 → v8: the two Distribusi tables are added.
///
/// The step is **purely additive**, and almost everything here is about proving exactly
/// that: not one existing column, row, index or constraint may move. That matters most
/// for the five things earlier migrations touched — the milli-unit scaling the
/// `from < 2` block applied, the `stock_opnames` rebuild the `from < 4` block performed,
/// and the Purchase Request, Delivery Order and Good Receipt tables `from < 5`, `< 6` and
/// `< 7` created. A v8 that re-scaled quantities would double every balance in the
/// clinic group; a v8 that changed `stock_opnames` would make a v3 → v8 upgrade apply
/// the v4 rebuild to the v8 shape and then apply v5, v6, v7 and v8 on top.
///
/// One absence is asserted rather than assumed: **v8 must not invent distributions for
/// the stock already sitting in rooms**. How that stock got there is whatever the ledger
/// already records, and writing documents to explain it would be a migration asserting
/// business events that never happened.
///
/// A v7 database is reproduced by creating the current schema, dropping the two
/// Distribusi tables and their indexes, and stamping `user_version` back to 7. Because v8
/// adds nothing else, what remains *is* a v7 database — and one of the tests below pins
/// that assumption by comparing the surviving object list against the v7 inventory.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v7_to_v8.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  late String branchId;
  late String roomId;
  late String secondRoomId;
  late String nurseId;
  late String headId;
  late String warehouseUserId;
  late String itemId;
  late String batchItemId;
  late String batchId;
  late String warehouseLocationId;
  late String branchStoreLocationId;

  /// Every object schema v7 had. Anything added to this list by v8 that is not a
  /// Distribusi object is a migration that is not additive.
  const v7Tables = <String>[
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
    'delivery_orders',
    'delivery_order_lines',
    'good_receipts',
    'good_receipt_lines',
  ];

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

  const distributionIndexes = <String>[
    'idx_distributions_branch_status',
    'idx_distributions_distributed_by_status',
    'idx_distributions_created_at',
    'idx_distributions_posted_at',
    'idx_distributions_doc_number',
    'idx_distribution_lines_distribution',
    'idx_distribution_lines_room',
    'idx_distribution_lines_item',
    'idx_distribution_lines_batch',
    'idx_distribution_lines_batched',
    'idx_distribution_lines_unbatched',
  ];

  /// Writes a v7 database holding master data, ledger rows with milli-unit quantities,
  /// an opname, a Purchase Request, a Delivery Order and a posted Good Receipt —
  /// everything a Distribusi will later sit beside, plus the branch-store balance it
  /// will later draw on.
  Future<void> createVersion7Database() async {
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
    secondRoomId = (await master.ensureRoom(
      branchId: branch.id,
      code: 'R2',
      name: 'Ruang Dental 2',
    )).id;
    warehouseLocationId = (await master.ensureLocation(
      type: StockLocationType.warehouse,
      name: 'Warehouse Pusat',
    )).id;
    branchStoreLocationId = (await master.ensureLocation(
      type: StockLocationType.branchStore,
      name: 'Gudang Cabang Uji',
      branchId: branch.id,
    )).id;
    await master.ensureLocation(
      type: StockLocationType.room,
      name: 'Ruang Dental 1',
      branchId: branch.id,
      roomId: roomId,
    );
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
    batchItemId = (await master.ensureItem(
      sku: 'TEST-0002',
      name: 'Anestesi Lokal',
      categoryId: category.id,
      unit: 'ampul',
      minStockRoom: 5,
      minStockBranch: 20,
      hasExpiry: true,
    )).id;
    batchId = (await master.ensureBatch(
      itemId: batchItemId,
      batchNo: 'BATCH-A',
      expiryDate: DateTime.utc(2027, 1, 31),
    )).id;

    // Ledger and balance rows in milli-units — the values the `from < 2` scaling
    // produced. If v8 touched them, `10.5 box` would come back as `10500 box`.
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
    // The branch store already holds stock — what a v8 distribution would draw on.
    await database.customStatement(
      'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
      'location_id, item_id, qty_on_hand) VALUES (?, ?, ?, ?, ?, ?, ?);',
      [
        'bal-2',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
        'synced',
        branchStoreLocationId,
        itemId,
        Quantity.parse('4.25').milliUnits,
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
      'INSERT INTO stock_opname_lines (id, created_at, updated_at, sync_status, '
      'opname_id, item_id, system_qty, counted_qty, note) '
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
        'Catatan v7',
      ],
    );

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
        'closed',
        '2026-07-29T04:00:00.000Z',
        '2026-07-29T05:00:00.000Z',
        warehouseUserId,
      ],
    );
    await database.customStatement(
      'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
      'sync_status, pr_id, item_id, suggested_qty, requested_qty, note) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'prl-1',
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        'pending',
        'pr-1',
        itemId,
        2500,
        Quantity.parse('3').milliUnits,
        'Catatan PR v7',
      ],
    );
    await database.customStatement(
      'INSERT INTO delivery_orders (id, created_at, updated_at, sync_status, '
      'doc_number, pr_id, prepared_by, status, shipped_at, shipped_by, note) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'do-1',
        '2026-07-29T06:00:00.000Z',
        '2026-07-29T06:00:00.000Z',
        'pending',
        'TMP-DO-do-1',
        'pr-1',
        warehouseUserId,
        'received',
        '2026-07-29T07:00:00.000Z',
        warehouseUserId,
        'Catatan DO v7',
      ],
    );
    await database.customStatement(
      'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
      'sync_status, do_id, pr_line_id, item_id, shipped_qty) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'dol-1',
        '2026-07-29T06:00:00.000Z',
        '2026-07-29T06:00:00.000Z',
        'pending',
        'do-1',
        'prl-1',
        itemId,
        Quantity.parse('2.5').milliUnits,
      ],
    );
    await database.customStatement(
      'INSERT INTO good_receipts (id, created_at, updated_at, sync_status, '
      'doc_number, do_id, received_by, status, posted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'gr-1',
        '2026-07-29T08:00:00.000Z',
        '2026-07-29T08:00:00.000Z',
        'pending',
        'TMP-GR-gr-1',
        'do-1',
        headId,
        'posted',
        '2026-07-29T09:00:00.000Z',
      ],
    );
    await database.customStatement(
      'INSERT INTO good_receipt_lines (id, created_at, updated_at, sync_status, '
      'gr_id, do_line_id, item_id, shipped_qty, received_qty, line_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'grl-1',
        '2026-07-29T08:00:00.000Z',
        '2026-07-29T08:00:00.000Z',
        'pending',
        'gr-1',
        'dol-1',
        itemId,
        Quantity.parse('2.5').milliUnits,
        Quantity.parse('2.5').milliUnits,
        'checked',
      ],
    );

    // Drop the Distribusi objects, leaving exactly a v7 database. Indexes go with
    // their tables in SQLite, so only the tables have to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in distributionTables) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 7;');
    await database.close();
  }

  /// Index name → its `CREATE INDEX` SQL, for every index whose name mentions [needle].
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

  group('v7 → v8', () {
    test('database v7 dibuka pada versi 8', () async {
      await createVersion7Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 12);

      await database.close();
    });

    test('dua tabel Distribusi ditambahkan dan tidak ada yang lain', () async {
      await createVersion7Database();
      final database = openDatabase();

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(distributionTables));
      // Exhaustive: v8 adds two tables, no more.
      expect(tables, {
        ...v7Tables,
        ...distributionTables,
        ...disposalTables,
        ...consumptionTables,
        ...goodsReturnTables,
        // Opening an older database migrates it to the current schema, so
        // v12's export audit table is present too.
        'export_logs',
      });

      await database.close();
    });

    test('seluruh index Distribusi ditambahkan', () async {
      await createVersion7Database();
      final database = openDatabase();

      final indexes = await objectNames(database, 'index');
      expect(indexes, containsAll(distributionIndexes));

      await database.close();
    });

    test('index unik posisi baris dibuat sebagai index partial', () async {
      await createVersion7Database();
      final database = openDatabase();

      Future<String> sqlOf(String name) async {
        final row = await database
            .customSelect("SELECT sql FROM sqlite_master WHERE name = '$name';")
            .getSingle();
        return row.read<String>('sql');
      }

      // The two load-bearing ones. An upgrade that created them without the partial
      // `WHERE` would refuse a line that was removed from a draft and added back;
      // one that created only the batched shape would let an item without expiry be
      // added to the same room twice, and posting that would take double the
      // quantity out of the store.
      final batched = await sqlOf('idx_distribution_lines_batched');
      expect(batched, contains('UNIQUE'));
      expect(batched, contains('batch_id IS NOT NULL'));
      expect(batched, contains('deleted_at IS NULL'));

      final unbatched = await sqlOf('idx_distribution_lines_unbatched');
      expect(unbatched, contains('UNIQUE'));
      expect(unbatched, contains('batch_id IS NULL'));
      expect(unbatched, contains('deleted_at IS NULL'));

      expect(
        await sqlOf('idx_distributions_doc_number'),
        allOf(contains('UNIQUE'), contains('deleted_at IS NULL')),
      );

      await database.close();
    });

    test('SQL index hasil migrasi identik dengan database v8 baru', () async {
      // The `from < 8` block creates the indexes from a **frozen literal list**,
      // because deriving them from `allSchemaEntities` would make a future v9 index
      // silently change what this step does. The cost of freezing them is that the
      // list can drift away from the `@TableIndex` declarations, and nothing in the
      // Dart compiler would notice. This test is the thing that notices.
      await createVersion7Database();
      final migrated = openDatabase();
      final migratedSql = await indexSqlByName(migrated, 'distribution');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v8.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshSql = await indexSqlByName(fresh, 'distribution');
      await fresh.close();
      await freshFile.delete();

      expect(migratedSql.keys, freshSql.keys);
      for (final name in freshSql.keys) {
        expect(
          _normalizeSql(migratedSql[name]!),
          _normalizeSql(freshSql[name]!),
          reason:
              '$name berbeda antara database yang bermigrasi dan database baru. '
              'Perbarui _v8DistributionIndexes agar cocok dengan deklarasi '
              '@TableIndex.',
        );
      }
    });

    test('index inventory, opname, PR, DO dan GR lama tidak hilang', () async {
      await createVersion7Database();
      final database = openDatabase();

      final indexes = await objectNames(database, 'index');
      expect(
        indexes,
        containsAll(<String>[
          'idx_stock_balances_batched',
          'idx_stock_balances_unbatched',
          'idx_stock_opnames_room_period',
          'idx_stock_opnames_doc_number',
          'idx_stock_opname_lines_batched',
          'idx_stock_opname_lines_unbatched',
          'idx_purchase_requests_active_branch',
          'idx_purchase_requests_doc_number',
          'idx_purchase_request_lines_item_unique',
          'idx_delivery_orders_doc_number',
          'idx_delivery_order_lines_batched',
          'idx_delivery_order_lines_unbatched',
          'idx_good_receipts_do',
          'idx_good_receipts_doc_number',
          'idx_good_receipt_lines_unique',
        ]),
      );

      await database.close();
    });

    test('kuantitas ledger tidak diskalakan ulang', () async {
      await createVersion7Database();
      final database = openDatabase();

      final balance = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
          )
          .getSingle();
      final branchStore = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-2';",
          )
          .getSingle();
      final movement = await database
          .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-1';")
          .getSingle();

      expect(balance.read<int>('qty_on_hand'), 10500);
      expect(branchStore.read<int>('qty_on_hand'), 4250);
      expect(movement.read<int>('qty'), 10500);

      await database.close();
    });

    test('dokumen opname, PR, DO dan GR utuh', () async {
      await createVersion7Database();
      final database = openDatabase();

      final opnameLine = await database
          .customSelect("SELECT * FROM stock_opname_lines WHERE id = 'sol-1';")
          .getSingle();
      expect(opnameLine.read<int>('system_qty'), 10500);
      // The generated column still computes, so the v4 table was not rebuilt.
      expect(opnameLine.read<int>('difference'), -1000);
      expect(opnameLine.read<String>('note'), 'Catatan v7');

      final request = await database
          .customSelect("SELECT * FROM purchase_requests WHERE id = 'pr-1';")
          .getSingle();
      expect(request.read<String>('status'), 'closed');

      final order = await database
          .customSelect("SELECT * FROM delivery_orders WHERE id = 'do-1';")
          .getSingle();
      expect(order.read<String>('status'), 'received');
      expect(order.read<String>('note'), 'Catatan DO v7');

      final receipt = await database
          .customSelect("SELECT * FROM good_receipts WHERE id = 'gr-1';")
          .getSingle();
      expect(receipt.read<String>('status'), 'posted');
      expect(receipt.read<String>('posted_at'), '2026-07-29T09:00:00.000Z');

      final receiptLine = await database
          .customSelect("SELECT * FROM good_receipt_lines WHERE id = 'grl-1';")
          .getSingle();
      expect(receiptLine.read<int>('received_qty'), 2500);
      expect(receiptLine.read<String>('line_status'), 'checked');

      await database.close();
    });

    test('migrasi tidak mengarang dokumen Distribusi', () async {
      // How the stock already in a room got there is whatever the ledger records.
      // A migration that wrote distributions to explain it would be asserting
      // business events that never happened — and would move no stock while
      // claiming it had.
      await createVersion7Database();
      final database = openDatabase();

      final documents = await database
          .customSelect('SELECT COUNT(*) AS c FROM distributions;')
          .getSingle();
      expect(documents.read<int>('c'), 0);

      final lines = await database
          .customSelect('SELECT COUNT(*) AS c FROM distribution_lines;')
          .getSingle();
      expect(lines.read<int>('c'), 0);

      final movements = await database
          .customSelect(
            "SELECT COUNT(*) AS c FROM stock_movements "
            "WHERE movement_type = 'distribution';",
          )
          .getSingle();
      expect(movements.read<int>('c'), 0);

      await database.close();
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion7Database();
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

    test('constraint Distribusi ditegakkan setelah migrasi', () async {
      await createVersion7Database();
      final database = openDatabase();

      Future<void> insertDistribution({
        required String id,
        String status = 'draft',
        String? postedAt,
        String? docNumber,
      }) => database.customStatement(
        'INSERT INTO distributions (id, created_at, updated_at, sync_status, '
        'doc_number, branch_id, distributed_by, status, posted_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-30T03:00:00.000Z',
          '2026-07-30T03:00:00.000Z',
          'pending',
          docNumber ?? 'TMP-DIST-$id',
          branchId,
          headId,
          status,
          postedAt,
        ],
      );

      // An unknown status cannot be introduced by a hand-written INSERT.
      expect(
        () => insertDistribution(id: 'bad', status: 'cancelled'),
        throwsA(anything),
      );
      // A `draft` carries no posting instant…
      expect(
        () => insertDistribution(
          id: 'bad-draft',
          postedAt: '2026-07-30T04:00:00.000Z',
        ),
        throwsA(anything),
      );
      // …and a `posted` one carries it.
      expect(
        () => insertDistribution(id: 'bad-posted', status: 'posted'),
        throwsA(anything),
      );

      await insertDistribution(id: 'dist-1');
      // The document number is unique among live rows.
      expect(
        () => insertDistribution(id: 'dist-2', docNumber: 'TMP-DIST-dist-1'),
        throwsA(anything),
      );

      Future<void> insertLine({
        required String id,
        String? room,
        String? item,
        String? batch,
        int qty = 1000,
        String? reason,
      }) => database.customStatement(
        'INSERT INTO distribution_lines (id, created_at, updated_at, '
        'sync_status, distribution_id, room_id, item_id, batch_id, qty, '
        'fefo_override_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-30T03:00:00.000Z',
          '2026-07-30T03:00:00.000Z',
          'pending',
          'dist-1',
          room ?? roomId,
          item ?? itemId,
          batch,
          qty,
          reason,
        ],
      );

      // Quantity must be strictly positive.
      expect(() => insertLine(id: 'zero', qty: 0), throwsA(anything));
      expect(() => insertLine(id: 'neg', qty: -1), throwsA(anything));
      // A stored FEFO reason must say something. NULL is legitimate — a compliant
      // line carries none — but whitespace is not a reason.
      expect(() => insertLine(id: 'blank', reason: '   '), throwsA(anything));
      expect(() => insertLine(id: 'empty', reason: ''), throwsA(anything));

      await insertLine(id: 'dl-1');
      // The unbatched partial unique index: one position per room/item.
      expect(() => insertLine(id: 'dl-dup'), throwsA(anything));
      // The same item into a *different* room is a different position (G-T3).
      await insertLine(id: 'dl-2', room: secondRoomId);

      await insertLine(id: 'dl-3', item: batchItemId, batch: batchId);
      // The batched partial unique index: one position per room/item/batch.
      expect(
        () => insertLine(id: 'dl-3-dup', item: batchItemId, batch: batchId),
        throwsA(anything),
      );

      // A non-blank reason is accepted.
      await insertLine(
        id: 'dl-4',
        room: secondRoomId,
        item: batchItemId,
        batch: batchId,
        reason: 'Cabang meminta batch dengan sisa umur panjang',
      );

      final violations = await database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);

      await database.close();
    });

    test('membuka ulang database v8 tidak menjalankan migrasi lagi', () async {
      await createVersion7Database();

      final first = openDatabase();
      await first.customSelect('SELECT 1;').getSingle();
      await first.close();

      // Re-running the `from < 8` block would fail on `CREATE TABLE` for an existing
      // table; that it does not is what makes the step re-runnable.
      final second = openDatabase();
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 12);

      final tables = await objectNames(second, 'table');
      expect(tables, containsAll(distributionTables));
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
      for (final table in distributionTables) {
        await database.customStatement('DROP TABLE IF EXISTS $table;');
      }
      if (version < 7) {
        await database.customStatement(
          'DROP TABLE IF EXISTS good_receipt_lines;',
        );
        await database.customStatement('DROP TABLE IF EXISTS good_receipts;');
      }
      if (version < 6) {
        await database.customStatement(
          'DROP TABLE IF EXISTS delivery_order_lines;',
        );
        await database.customStatement('DROP TABLE IF EXISTS delivery_orders;');
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

    /// Every version between v1 and v7 must land on v8 with the distribution tables in
    /// place, the quantities scaled exactly once, and no foreign key violation.
    for (final from in [1, 2, 3, 4, 5, 6, 7]) {
      test('database v$from bermigrasi hingga v8', () async {
        await rewindTo(from);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 12);

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(distributionTables));
        expect(
          tables,
          containsAll(<String>[
            'stock_opnames',
            'stock_opname_lines',
            'purchase_requests',
            'purchase_request_opnames',
            'purchase_request_lines',
            'delivery_orders',
            'delivery_order_lines',
            'good_receipts',
            'good_receipt_lines',
          ]),
        );

        final indexes = await objectNames(database, 'index');
        expect(indexes, containsAll(distributionIndexes));

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

        // The generated opname difference column still computes.
        final generated = await database
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'stock_opname_lines';",
            )
            .getSingle();
        expect(generated.read<String>('sql'), contains('difference'));

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        await database.close();
      });
    }
  });
}

/// Collapses whitespace so `IF NOT EXISTS` and line breaks do not make two equivalent
/// statements look different.
String _normalizeSql(String sql) => sql
    .replaceAll('IF NOT EXISTS ', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();
