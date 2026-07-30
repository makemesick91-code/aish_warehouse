import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v6 → v7: the two Good Receipt tables are added.
///
/// The step is **purely additive**, and almost everything here is about proving exactly
/// that: not one existing column, row, index or constraint may move. That matters most
/// for the four things earlier migrations touched — the milli-unit scaling the
/// `from < 2` block applied, the `stock_opnames` rebuild the `from < 4` block performed,
/// the Purchase Request tables `from < 5` created and the Delivery Order tables
/// `from < 6` created. A v7 that re-scaled quantities would double every balance in the
/// clinic group; a v7 that changed `stock_opnames` would make a v3 → v7 upgrade apply
/// the v4 rebuild to the v7 shape and then apply v5, v6 and v7 on top.
///
/// One absence is asserted rather than assumed: **v7 must not touch
/// `delivery_orders`**. Whether a shipment has been received is a fact a Good Receipt
/// establishes by being posted, and a migration that marked the rows already on a device
/// as `received` would be asserting a business event that never happened.
///
/// A v6 database is reproduced by creating the current schema, dropping the two Good
/// Receipt tables and their indexes, and stamping `user_version` back to 6. Because v7
/// adds nothing else, what remains *is* a v6 database — and one of the tests below pins
/// that assumption by comparing the surviving object list against the v6 inventory.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v6_to_v7.sqlite');
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
  late String doLineId;

  /// Every object schema v6 had. Anything added to this list by v7 that is not a Good
  /// Receipt object is a migration that is not additive.
  const v6Tables = <String>[
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
  ];

  const receiptTables = <String>['good_receipts', 'good_receipt_lines'];

  const distributionTables = <String>['distributions', 'distribution_lines'];

  /// Schema v9 own tables, named here so the exhaustive assertions below stay
  /// exhaustive rather than being loosened to `containsAll` every milestone.
  const disposalTables = <String>['disposals', 'disposal_lines'];

  const receiptIndexes = <String>[
    'idx_good_receipts_received_by_status',
    'idx_good_receipts_status_created',
    'idx_good_receipts_posted_at',
    'idx_good_receipts_do',
    'idx_good_receipts_doc_number',
    'idx_good_receipt_lines_gr',
    'idx_good_receipt_lines_do_line',
    'idx_good_receipt_lines_item',
    'idx_good_receipt_lines_batch',
    'idx_good_receipt_lines_status',
    'idx_good_receipt_lines_unique',
  ];

  /// Writes a v6 database holding master data, ledger rows with milli-unit quantities,
  /// opnames, a `shipped` Purchase Request and a `shipped` Delivery Order with a line —
  /// everything a Good Receipt will later point at.
  Future<void> createVersion6Database() async {
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
    await master.ensureLocation(
      type: StockLocationType.branchStore,
      name: 'Gudang Cabang Uji',
      branchId: branch.id,
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

    // Ledger and balance rows in milli-units — the values the `from < 2` scaling
    // produced. If v7 touched them, `10.5 box` would come back as `10500 box`.
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
        'Catatan v6',
      ],
    );

    // A `shipped` Purchase Request with a line, and the Delivery Order that shipped
    // it — what a v7 Good Receipt will reference by foreign key.
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
        'shipped',
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
        'Catatan PR v6',
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
        'shipped',
        '2026-07-29T07:00:00.000Z',
        warehouseUserId,
        'Catatan DO v6',
      ],
    );
    doLineId = 'dol-1';
    await database.customStatement(
      'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
      'sync_status, do_id, pr_line_id, item_id, shipped_qty) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
      [
        doLineId,
        '2026-07-29T06:00:00.000Z',
        '2026-07-29T06:00:00.000Z',
        'pending',
        'do-1',
        prLineId,
        itemId,
        Quantity.parse('2.5').milliUnits,
      ],
    );

    // Drop the Good Receipt objects, leaving exactly a v6 database. Indexes go with
    // their tables in SQLite, so only the tables have to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in receiptTables) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 6;');
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

  group('v6 → v7', () {
    test('database v6 dibuka pada versi 7', () async {
      await createVersion6Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 9);

      await database.close();
    });

    test('dua tabel Good Receipt ditambahkan dan tidak ada yang lain', () async {
      await createVersion6Database();
      final database = openDatabase();

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(receiptTables));
      // Exhaustive: v7 adds two tables, no more — and the versions after it add
      // their own, which is what `distributionTables` accounts for.
      expect(tables, {
        ...v6Tables,
        ...receiptTables,
        ...distributionTables,
        ...disposalTables,
      });

      await database.close();
    });

    test('seluruh index Good Receipt ditambahkan', () async {
      await createVersion6Database();
      final database = openDatabase();

      final indexes = await objectNames(database, 'index');
      expect(indexes, containsAll(receiptIndexes));

      await database.close();
    });

    test('index unik one-DO-one-GR dibuat tanpa klausa WHERE', () async {
      await createVersion6Database();
      final database = openDatabase();

      Future<String> sqlOf(String name) async {
        final row = await database
            .customSelect("SELECT sql FROM sqlite_master WHERE name = '$name';")
            .getSingle();
        return row.read<String>('sql');
      }

      // The two load-bearing ones. An upgrade that created them *partially* would let
      // a soft-deleted receipt free its shipment for a second one — and posting that
      // second receipt would credit the branch twice from one delivery.
      final receiptDo = await sqlOf('idx_good_receipts_do');
      expect(receiptDo, contains('UNIQUE'));
      expect(receiptDo, isNot(contains('WHERE')));

      final lineUnique = await sqlOf('idx_good_receipt_lines_unique');
      expect(lineUnique, contains('UNIQUE'));
      expect(lineUnique, isNot(contains('WHERE')));

      expect(
        await sqlOf('idx_good_receipts_doc_number'),
        allOf(contains('UNIQUE'), contains('deleted_at IS NULL')),
      );

      await database.close();
    });

    test('SQL index hasil migrasi identik dengan database v7 baru', () async {
      // The `from < 7` block creates the indexes from a **frozen literal list**,
      // because deriving them from `allSchemaEntities` would make a future v8 index
      // silently change what this step does. The cost of freezing them is that the list
      // can drift away from the `@TableIndex` declarations, and nothing in the Dart
      // compiler would notice. This test is the thing that notices.
      await createVersion6Database();
      final migrated = openDatabase();
      final migratedSql = await indexSqlByName(migrated, 'good_receipt');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v7.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshSql = await indexSqlByName(fresh, 'good_receipt');
      await fresh.close();
      await freshFile.delete();

      expect(migratedSql.keys, freshSql.keys);
      for (final name in freshSql.keys) {
        expect(
          _normalizeSql(migratedSql[name]!),
          _normalizeSql(freshSql[name]!),
          reason:
              '$name berbeda antara database yang bermigrasi dan database baru. '
              'Perbarui _v7GoodReceiptIndexes agar cocok dengan deklarasi '
              '@TableIndex.',
        );
      }
    });

    test('index inventory, opname, PR dan DO lama tidak hilang', () async {
      await createVersion6Database();
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
          'idx_delivery_orders_doc_number',
          'idx_delivery_order_lines_batched',
          'idx_delivery_order_lines_unbatched',
        ]),
      );

      await database.close();
    });

    test('kuantitas ledger tidak diskalakan ulang', () async {
      await createVersion6Database();
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

    test('dokumen opname, PR dan DO utuh', () async {
      await createVersion6Database();
      final database = openDatabase();

      final opnameLine = await database
          .customSelect("SELECT * FROM stock_opname_lines WHERE id = 'sol-1';")
          .getSingle();
      expect(opnameLine.read<int>('system_qty'), 10500);
      // The generated column still computes, so the v4 table was not rebuilt.
      expect(opnameLine.read<int>('difference'), -1000);
      expect(opnameLine.read<String>('note'), 'Catatan v6');

      final request = await database
          .customSelect("SELECT * FROM purchase_requests WHERE id = 'pr-1';")
          .getSingle();
      expect(request.read<String>('status'), 'shipped');
      expect(request.read<String>('processed_by'), warehouseUserId);

      final prLine = await database
          .customSelect(
            "SELECT * FROM purchase_request_lines WHERE id = 'prl-1';",
          )
          .getSingle();
      expect(prLine.read<int>('requested_qty'), 3000);

      final order = await database
          .customSelect("SELECT * FROM delivery_orders WHERE id = 'do-1';")
          .getSingle();
      expect(order.read<String>('note'), 'Catatan DO v6');
      expect(order.read<String>('shipped_by'), warehouseUserId);

      final doLine = await database
          .customSelect(
            "SELECT * FROM delivery_order_lines WHERE id = 'dol-1';",
          )
          .getSingle();
      expect(doLine.read<int>('shipped_qty'), 2500);

      await database.close();
    });

    test('Surat Jalan yang sudah dikirim tidak diubah menjadi received', () async {
      // Whether a shipment has been received is a fact a Good Receipt establishes by
      // being posted. A migration that decided it for the rows already on the device
      // would assert a business event that never happened — and would credit no stock
      // while claiming the goods arrived.
      await createVersion6Database();
      final database = openDatabase();

      final order = await database
          .customSelect("SELECT status FROM delivery_orders WHERE id = 'do-1';")
          .getSingle();
      expect(order.read<String>('status'), 'shipped');

      final receipts = await database
          .customSelect('SELECT COUNT(*) AS c FROM good_receipts;')
          .getSingle();
      expect(
        receipts.read<int>('c'),
        0,
        reason: 'Migrasi tidak boleh mengarang Good Receipt.',
      );

      await database.close();
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion6Database();
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

    test('constraint Good Receipt ditegakkan setelah migrasi', () async {
      await createVersion6Database();
      final database = openDatabase();

      Future<void> insertReceipt({
        required String id,
        String status = 'checking',
        String? postedAt,
      }) => database.customStatement(
        'INSERT INTO good_receipts (id, created_at, updated_at, sync_status, '
        'doc_number, do_id, received_by, status, posted_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-30T03:00:00.000Z',
          '2026-07-30T03:00:00.000Z',
          'pending',
          'TMP-GR-$id',
          'do-1',
          headId,
          status,
          postedAt,
        ],
      );

      // An unknown status cannot be introduced by a hand-written INSERT.
      expect(
        () => insertReceipt(id: 'bad', status: 'cancelled'),
        throwsA(anything),
      );
      // A `checking` receipt carries no posting instant…
      expect(
        () => insertReceipt(
          id: 'bad-checking',
          postedAt: '2026-07-30T04:00:00.000Z',
        ),
        throwsA(anything),
      );
      // …and a `posted` one carries it.
      expect(
        () => insertReceipt(id: 'bad-posted', status: 'posted'),
        throwsA(anything),
      );

      await insertReceipt(id: 'gr-1');
      // G-G1: one shipment, one receipt.
      expect(() => insertReceipt(id: 'gr-2'), throwsA(anything));

      Future<void> insertLine({
        required String id,
        int shipped = 2500,
        int received = 2500,
        String lineStatus = 'pending',
        String? rejectReason,
      }) => database.customStatement(
        'INSERT INTO good_receipt_lines (id, created_at, updated_at, '
        'sync_status, gr_id, do_line_id, item_id, shipped_qty, received_qty, '
        'line_status, reject_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-30T03:00:00.000Z',
          '2026-07-30T03:00:00.000Z',
          'pending',
          'gr-1',
          doLineId,
          itemId,
          shipped,
          received,
          lineStatus,
          rejectReason,
        ],
      );

      // G-G3, both bounds.
      expect(() => insertLine(id: 'over', received: 2501), throwsA(anything));
      expect(() => insertLine(id: 'neg', received: -1), throwsA(anything));
      // G-G4, including the NULL case SQLite would otherwise let through.
      expect(
        () => insertLine(id: 'no-reason', lineStatus: 'rejected', received: 0),
        throwsA(anything),
      );
      expect(
        () => insertLine(
          id: 'blank',
          lineStatus: 'rejected',
          received: 0,
          rejectReason: '  ',
        ),
        throwsA(anything),
      );

      await insertLine(id: 'gl-1', lineStatus: 'checked', received: 1000);
      // One allocation, one receipt line.
      expect(() => insertLine(id: 'gl-2'), throwsA(anything));

      await database.close();
    });

    test('membuka ulang database v7 tidak menjalankan migrasi lagi', () async {
      await createVersion6Database();

      final first = openDatabase();
      await first.customSelect('SELECT 1;').getSingle();
      await first.close();

      // Re-running the `from < 7` block would fail on `CREATE TABLE` for an existing
      // table; that it does not is what makes the step re-runnable.
      final second = openDatabase();
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 9);

      final tables = await objectNames(second, 'table');
      expect(tables, containsAll(receiptTables));
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
      for (final table in receiptTables) {
        await database.customStatement('DROP TABLE IF EXISTS $table;');
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

    /// Every version between v1 and v6 must land on v7 with the receipt tables in
    /// place, the quantities scaled exactly once, and no foreign key violation.
    for (final from in [1, 2, 3, 4, 5, 6]) {
      test('database v$from bermigrasi hingga v7', () async {
        await rewindTo(from);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 9);

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(receiptTables));
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
          ]),
        );

        final indexes = await objectNames(database, 'index');
        expect(indexes, containsAll(receiptIndexes));

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

/// Collapses whitespace so `IF NOT EXISTS` and line breaks do not make two equivalent
/// statements look different.
String _normalizeSql(String sql) => sql
    .replaceAll('IF NOT EXISTS ', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();
