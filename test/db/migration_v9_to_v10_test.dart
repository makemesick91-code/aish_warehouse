import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v9 → v10: the two Pemakaian tables are added (§37).
///
/// The step is **purely additive**, and almost everything here is about proving
/// exactly that: not one existing column, row, index or constraint may move. That
/// matters most for the seven things earlier migrations touched — the milli-unit
/// scaling the `from < 2` block applied, the `stock_opnames` rebuild the `from < 4`
/// block performed, and the Purchase Request, Delivery Order, Good Receipt,
/// Distribusi and Pemusnahan tables `from < 5` through `< 9` created. A v10 that
/// re-scaled quantities would multiply every balance in the clinic group by a
/// thousand; a v10 that changed `stock_opnames` would make a v3 → v10 upgrade apply
/// the v4 rebuild to the v10 shape and then apply v5 to v10 on top.
///
/// One absence is asserted rather than assumed, and it is the interesting one:
/// **v10 must not invent consumptions for the room stock that has already been
/// used.** Some has been — nothing before this milestone could record it — and
/// whatever explained those balances is already in the ledger, most likely as an
/// opname adjustment. Writing documents to reinterpret it would be a migration
/// asserting that a named nurse consumed a named batch on a date, which nobody
/// recorded. The rooms simply start with the balances they have.
///
/// A v9 database is reproduced by creating the current schema, dropping the two
/// Pemakaian tables and their indexes, and stamping `user_version` back to 9. Because
/// v10 adds nothing else, what remains *is* a v9 database — and one of the tests below
/// pins that assumption by comparing the surviving object list against the v9
/// inventory.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v9_to_v10.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  late String branchId;
  late String roomId;
  late String headId;
  late String nurseId;
  late String warehouseUserId;
  late String itemId;
  late String batchItemId;
  late String batchId;
  late String warehouseLocationId;
  late String branchStoreLocationId;
  late String roomLocationId;

  /// Every table schema v9 had. Anything added to this list by v10 that is not a
  /// Pemakaian table is a migration that is not additive.
  const v9Tables = <String>[
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
    'distributions',
    'distribution_lines',
    'disposals',
    'disposal_lines',
  ];

  const consumptionTables = <String>['consumptions', 'consumption_lines'];

  const consumptionIndexes = <String>[
    'idx_consumptions_branch_status',
    'idx_consumptions_room_status',
    'idx_consumptions_created_by_status',
    'idx_consumptions_posted_by_status',
    'idx_consumptions_created_at',
    'idx_consumptions_posted_at',
    'idx_consumptions_doc_number',
    'idx_consumption_lines_consumption',
    'idx_consumption_lines_item',
    'idx_consumption_lines_batch',
    'idx_consumption_lines_batched',
    'idx_consumption_lines_unbatched',
  ];

  /// Writes a v9 database holding master data, ledger rows with milli-unit
  /// quantities, an opname, a Purchase Request, a Delivery Order, a posted Good
  /// Receipt, a posted Distribusi and a posted Pemusnahan — everything a Pemakaian
  /// will later sit beside, plus the balances it will later draw on. One of those
  /// balances is deliberately a **room** position, because that is the row a v10 might
  /// be tempted to write a consumption document for.
  Future<void> createVersion9Database() async {
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
    branchStoreLocationId = (await master.ensureLocation(
      type: StockLocationType.branchStore,
      name: 'Gudang Cabang Uji',
      branchId: branch.id,
    )).id;
    roomLocationId = (await master.ensureLocation(
      type: StockLocationType.room,
      name: 'Ruang Dental 1',
      branchId: branch.id,
      roomId: roomId,
    )).id;

    headId = (await master.ensureUser(
      email: 'kacab@test.local',
      fullName: 'Kepala Cabang Uji',
      role: UserRole.kepalaCabang,
      branchId: branch.id,
    )).id;
    nurseId = (await master.ensureUser(
      email: 'perawat@test.local',
      fullName: 'Perawat Uji',
      role: UserRole.perawat,
      branchId: branch.id,
    )).id;
    warehouseUserId = (await master.ensureUser(
      email: 'warehouse@test.local',
      fullName: 'Petugas Warehouse Uji',
      role: UserRole.warehouse,
    )).id;

    final category = await master.ensureCategory('Alat Sekali Pakai');
    itemId = (await master.ensureItem(
      sku: 'MIG-0001',
      name: 'Masker Bedah',
      categoryId: category.id,
      unit: 'box',
      minStockRoom: 5,
      minStockBranch: 20,
      hasExpiry: false,
    )).id;
    batchItemId = (await master.ensureItem(
      sku: 'MIG-0002',
      name: 'Anestesi Lokal',
      categoryId: category.id,
      unit: 'ampul',
      minStockRoom: 10,
      minStockBranch: 40,
      hasExpiry: true,
    )).id;
    batchId = (await master.ensureBatch(
      itemId: batchItemId,
      batchNo: 'B-VALID',
      // Comfortably in date, on any plausible day this test runs — a consumption
      // candidate rather than a disposal one.
      expiryDate: DateTime.utc(2099, 1, 1),
    )).id;

    // Balances and ledger rows, written directly so the fixture does not depend on
    // the posting service's own rules — what matters here is that the rows survive.
    Future<void> balance(
      String id,
      String locationId,
      String item,
      String? batch,
      String qty,
    ) => database.customStatement(
      'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
      'location_id, item_id, batch_id, qty_on_hand) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        'pending',
        locationId,
        item,
        batch,
        Quantity.parse(qty).milliUnits,
      ],
    );

    await balance('bal-1', warehouseLocationId, itemId, null, '10.5');
    await balance('bal-2', branchStoreLocationId, itemId, null, '4');
    // The room positions a v10 must leave exactly where they are.
    await balance('bal-3', roomLocationId, batchItemId, batchId, '2.5');
    await balance('bal-4', roomLocationId, itemId, null, '1.25');

    await database.customStatement(
      'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
      'item_id, batch_id, from_location_id, to_location_id, qty, movement_type, '
      'ref_doc_type, ref_doc_id, actor_user_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'mov-1',
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        'pending',
        itemId,
        null,
        null,
        warehouseLocationId,
        Quantity.parse('10.5').milliUnits,
        'inbound_warehouse',
        'SEED',
        'seed-1',
        warehouseUserId,
      ],
    );

    // One row of every earlier document, so "nothing else moved" has something to be
    // asserted about.
    await database.customStatement(
      'INSERT INTO stock_opnames (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, room_id, period_year, period_week, counted_by, '
      'status, submitted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'so-1',
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        'pending',
        'TMP-SO-so-1',
        branchId,
        roomId,
        2026,
        31,
        nurseId,
        'submitted',
        // The v3 CHECK pairs each status with the timestamps it must carry.
        '2026-07-29T00:30:00.000Z',
      ],
    );
    await database.customStatement(
      'INSERT INTO purchase_requests (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, requested_by, status, submitted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'pr-1',
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        'pending',
        'TMP-PR-pr-1',
        branchId,
        headId,
        'submitted',
        '2026-07-29T00:30:00.000Z',
      ],
    );
    await database.customStatement(
      'INSERT INTO delivery_orders (id, created_at, updated_at, sync_status, '
      'doc_number, pr_id, prepared_by, status, shipped_at, shipped_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'do-1',
        '2026-07-29T01:00:00.000Z',
        '2026-07-29T01:00:00.000Z',
        'pending',
        'TMP-DO-do-1',
        'pr-1',
        warehouseUserId,
        'shipped',
        '2026-07-29T02:00:00.000Z',
        warehouseUserId,
      ],
    );
    await database.customStatement(
      'INSERT INTO good_receipts (id, created_at, updated_at, sync_status, '
      'doc_number, do_id, received_by, status, posted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'gr-1',
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        'pending',
        'TMP-GR-gr-1',
        'do-1',
        headId,
        'posted',
        '2026-07-29T04:00:00.000Z',
      ],
    );
    await database.customStatement(
      'INSERT INTO distributions (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, distributed_by, status, posted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'dist-1',
        '2026-07-29T05:00:00.000Z',
        '2026-07-29T05:00:00.000Z',
        'pending',
        'TMP-DIST-dist-1',
        branchId,
        headId,
        'posted',
        '2026-07-29T06:00:00.000Z',
      ],
    );
    await database.customStatement(
      'INSERT INTO distribution_lines (id, created_at, updated_at, sync_status, '
      'distribution_id, room_id, item_id, batch_id, qty) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'distl-1',
        '2026-07-29T05:00:00.000Z',
        '2026-07-29T05:00:00.000Z',
        'pending',
        'dist-1',
        roomId,
        itemId,
        null,
        Quantity.parse('1.5').milliUnits,
      ],
    );
    await database.customStatement(
      'INSERT INTO disposals (id, created_at, updated_at, sync_status, '
      'doc_number, source_location_id, created_by, status, reason, posted_at, '
      'posted_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'dsp-1',
        '2026-07-29T07:00:00.000Z',
        '2026-07-29T07:00:00.000Z',
        'pending',
        'TMP-DSP-dsp-1',
        branchStoreLocationId,
        headId,
        'posted',
        'Kedaluwarsa',
        '2026-07-29T08:00:00.000Z',
        headId,
      ],
    );

    // Drop the Pemakaian objects, leaving exactly a v9 database. Indexes go with
    // their tables in SQLite, so only the tables have to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in consumptionTables) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 9;');
    await database.close();
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

  Future<int> countOf(AppDatabase database, String table) async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM $table;')
        .getSingle();
    return row.read<int>('c');
  }

  group('v9 → v10', () {
    test('database v9 dibuka pada versi 10', () async {
      await createVersion9Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 10);

      await database.close();
    });

    test('dua tabel Pemakaian ditambahkan dan tidak ada yang lain', () async {
      await createVersion9Database();
      final database = openDatabase();

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(consumptionTables));
      // Exhaustive: v10 adds two tables, no more.
      expect(tables, {...v9Tables, ...consumptionTables});

      await database.close();
    });

    test('seluruh index Pemakaian ditambahkan', () async {
      await createVersion9Database();
      final database = openDatabase();

      expect(
        await objectNames(database, 'index'),
        containsAll(consumptionIndexes),
      );

      await database.close();
    });

    test('index hasil migrasi identik dengan database v10 baru', () async {
      // The assertion that keeps the frozen migration SQL honest: an index created by
      // `_v10ConsumptionIndexes` and one created by `createAll` must be the same
      // object, or two devices would disagree about which rows are unique.
      await createVersion9Database();
      final migrated = openDatabase();
      final migratedIndexes = await indexSqlByName(migrated, 'consumption');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v10.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshIndexes = await indexSqlByName(fresh, 'consumption');
      await fresh.close();
      await freshFile.delete();

      expect(migratedIndexes.keys.toSet(), freshIndexes.keys.toSet());
      for (final name in freshIndexes.keys) {
        expect(
          _normalize(migratedIndexes[name]!),
          _normalize(freshIndexes[name]!),
          reason: 'SQL index $name berbeda antara migrasi dan schema baru.',
        );
      }
    });

    test('doc_number unik tanpa partial juga setelah migrasi', () async {
      await createVersion9Database();
      final database = openDatabase();

      final sql = (await indexSqlByName(
        database,
        'consumptions_doc_number',
      ))['idx_consumptions_doc_number']!;
      expect(sql, contains('UNIQUE'));
      expect(sql.toLowerCase().contains('where'), isFalse);

      await database.close();
    });

    test('tidak ada dokumen Pemakaian yang dibuat otomatis', () async {
      // The load-bearing absence. The room shelf holds two positions, and a
      // migration that "helpfully" filed a consumption for them would be asserting a
      // business event — with an actor and a date — that never happened.
      await createVersion9Database();
      final database = openDatabase();

      expect(await countOf(database, 'consumptions'), 0);
      expect(await countOf(database, 'consumption_lines'), 0);

      final movements = await database
          .customSelect(
            "SELECT COUNT(*) AS c FROM stock_movements "
            "WHERE movement_type = 'consumption' OR ref_doc_type = 'CONS';",
          )
          .getSingle();
      expect(movements.read<int>('c'), 0);

      await database.close();
    });

    test('saldo ruangan tetap utuh, tidak berkurang', () async {
      await createVersion9Database();
      final database = openDatabase();

      final rows = await database
          .customSelect(
            "SELECT id, qty_on_hand FROM stock_balances "
            "WHERE id IN ('bal-3', 'bal-4') ORDER BY id;",
          )
          .get();
      expect(
        {
          for (final row in rows)
            row.read<String>('id'): row.read<int>('qty_on_hand'),
        },
        {
          'bal-3': Quantity.parse('2.5').milliUnits,
          'bal-4': Quantity.parse('1.25').milliUnits,
        },
      );

      await database.close();
    });

    test('kuantitas milli-unit tidak diskalakan ulang', () async {
      await createVersion9Database();
      final database = openDatabase();

      final balances = await database
          .customSelect(
            'SELECT id, qty_on_hand FROM stock_balances ORDER BY id;',
          )
          .get();
      expect(
        {
          for (final row in balances)
            row.read<String>('id'): row.read<int>('qty_on_hand'),
        },
        {
          'bal-1': Quantity.parse('10.5').milliUnits,
          'bal-2': Quantity.parse('4').milliUnits,
          'bal-3': Quantity.parse('2.5').milliUnits,
          'bal-4': Quantity.parse('1.25').milliUnits,
        },
      );

      final movement = await database
          .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-1';")
          .getSingle();
      expect(movement.read<int>('qty'), Quantity.parse('10.5').milliUnits);

      await database.close();
    });

    test('dokumen milestone sebelumnya tidak tersentuh', () async {
      await createVersion9Database();
      final database = openDatabase();

      for (final table in const [
        'stock_opnames',
        'purchase_requests',
        'delivery_orders',
        'good_receipts',
        'distributions',
        'distribution_lines',
        'disposals',
      ]) {
        expect(
          await countOf(database, table),
          1,
          reason: '$table berubah pada migrasi v10.',
        );
      }

      // And their statuses, which a migration inventing events would have moved.
      final statuses = await database
          .customSelect(
            "SELECT (SELECT status FROM stock_opnames) AS so, "
            "(SELECT status FROM purchase_requests) AS pr, "
            "(SELECT status FROM delivery_orders) AS dord, "
            "(SELECT status FROM good_receipts) AS gr, "
            "(SELECT status FROM distributions) AS dist, "
            "(SELECT status FROM disposals) AS dsp;",
          )
          .getSingle();
      expect(statuses.read<String>('so'), 'submitted');
      expect(statuses.read<String>('pr'), 'submitted');
      expect(statuses.read<String>('dord'), 'shipped');
      expect(statuses.read<String>('gr'), 'posted');
      expect(statuses.read<String>('dist'), 'posted');
      expect(statuses.read<String>('dsp'), 'posted');

      await database.close();
    });

    test('index milestone sebelumnya tidak hilang', () async {
      await createVersion9Database();
      final database = openDatabase();

      expect(
        await objectNames(database, 'index'),
        containsAll(<String>[
          'idx_stock_opnames_branch_status',
          'idx_purchase_requests_active_branch',
          'idx_delivery_order_lines_batched',
          'idx_good_receipts_do',
          'idx_distribution_lines_batched',
          'idx_disposals_doc_number',
          'idx_disposal_lines_position',
        ]),
      );

      await database.close();
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion9Database();
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

    test('membuka ulang database v10 tidak menjalankan migrasi lagi', () async {
      await createVersion9Database();

      final first = openDatabase();
      await first.customSelect('SELECT 1;').getSingle();
      await first.close();

      // Re-running the `from < 10` block would fail on `CREATE TABLE` for an existing
      // table; that it does not is what makes the step re-runnable.
      final second = openDatabase();
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 10);
      expect(
        await objectNames(second, 'table'),
        containsAll(consumptionTables),
      );
      await second.close();
    });

    test('CHECK Pemakaian ditegakkan setelah migrasi', () async {
      await createVersion9Database();
      final database = openDatabase();

      // A posted row with no `posted_by` must be refused by a *migrated* database
      // too, not only a fresh one.
      await expectLater(
        database.customStatement(
          'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
          'doc_number, branch_id, room_id, created_by, status, posted_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            'bad-1',
            '2026-07-30T00:00:00.000Z',
            '2026-07-30T00:00:00.000Z',
            'pending',
            'TMP-CNS-bad-1',
            branchId,
            roomId,
            nurseId,
            'posted',
            '2026-07-30T01:00:00.000Z',
          ],
        ),
        throwsA(anything),
      );

      // And a status the enum does not know.
      await expectLater(
        database.customStatement(
          'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
          'doc_number, branch_id, room_id, created_by, status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            'bad-2',
            '2026-07-30T00:00:00.000Z',
            '2026-07-30T00:00:00.000Z',
            'pending',
            'TMP-CNS-bad-2',
            branchId,
            roomId,
            nurseId,
            'approved',
          ],
        ),
        throwsA(anything),
      );

      await database.close();
    });

    test('index posisi Pemakaian ditegakkan setelah migrasi', () async {
      await createVersion9Database();
      final database = openDatabase();

      await database.customStatement(
        'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
        'doc_number, branch_id, room_id, created_by, status) '
        "VALUES ('cns-1', ?, ?, 'pending', 'TMP-CNS-cns-1', ?, ?, ?, 'draft');",
        [
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          branchId,
          roomId,
          nurseId,
        ],
      );

      Future<void> insertBatched(String id) => database.customStatement(
        'INSERT INTO consumption_lines (id, created_at, updated_at, '
        'sync_status, consumption_id, item_id, batch_id, qty) '
        "VALUES (?, ?, ?, 'pending', 'cns-1', ?, ?, 1000);",
        [
          id,
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          batchItemId,
          batchId,
        ],
      );
      await insertBatched('cl-1');
      await expectLater(insertBatched('cl-2'), throwsA(anything));

      Future<void> insertUnbatched(String id) => database.customStatement(
        'INSERT INTO consumption_lines (id, created_at, updated_at, '
        'sync_status, consumption_id, item_id, batch_id, qty) '
        "VALUES (?, ?, ?, 'pending', 'cns-1', ?, NULL, 1000);",
        [id, '2026-07-30T00:00:00.000Z', '2026-07-30T00:00:00.000Z', itemId],
      );
      await insertUnbatched('cl-3');
      await expectLater(insertUnbatched('cl-4'), throwsA(anything));

      await database.close();
    });
  });

  group('rantai lengkap', () {
    /// Rewinds a freshly created database to [version] by removing everything the
    /// migrations after it added, so the real `MigrationStrategy` runs on reopen.
    Future<void> rewindTo(int version) async {
      final database = openDatabase();
      await database.customStatement('PRAGMA foreign_keys = OFF;');

      const byVersion = <int, List<String>>{
        10: consumptionTables,
        9: ['disposals', 'disposal_lines'],
        8: ['distributions', 'distribution_lines'],
        7: ['good_receipts', 'good_receipt_lines'],
        6: ['delivery_orders', 'delivery_order_lines'],
        5: [
          'purchase_requests',
          'purchase_request_opnames',
          'purchase_request_lines',
        ],
        3: ['stock_opnames', 'stock_opname_lines'],
      };
      for (final entry in byVersion.entries) {
        if (entry.key <= version) continue;
        for (final table in entry.value) {
          await database.customStatement('DROP TABLE IF EXISTS $table;');
        }
      }

      await database.customStatement('PRAGMA foreign_keys = ON;');
      await database.customStatement('PRAGMA user_version = $version;');
      await database.close();
    }

    /// Every version between v1 and v9 must land on v10 with the Pemakaian tables in
    /// place and no foreign key violation.
    ///
    /// v1 and v2 are the interesting ones: the `from < 2` block scales every ledger
    /// quantity by 1000, and it must run **exactly once** whichever version the device
    /// started from. A v10 that re-triggered it would multiply every balance in the
    /// clinic group by a thousand.
    for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9]) {
      test('database v$from bermigrasi hingga v10', () async {
        await rewindTo(from);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 10);

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(consumptionTables));
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
            'distributions',
            'distribution_lines',
            'disposals',
            'disposal_lines',
          ]),
        );
        expect(
          await objectNames(database, 'index'),
          containsAll(consumptionIndexes),
        );

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        // No consumption invented anywhere on the chain.
        expect(await countOf(database, 'consumptions'), 0);
        expect(await countOf(database, 'consumption_lines'), 0);

        await database.close();
      });
    }

    test('generated column difference tetap bekerja sampai v10', () async {
      // The v4 rebuild reads the *current* Dart definition of `stock_opnames`, so a
      // v10 that changed that table would land a v3 device on the v10 shape and then
      // apply steps 5 to 10 on top. The generated `difference` column is the cheapest
      // proof the rebuild still produced a working table.
      await rewindTo(3);
      final database = openDatabase();
      final master = DriftMasterDataRepository(database.masterDataDao);

      final branch = await master.ensureBranch(code: 'CAB-09', name: 'Cabang');
      final room = await master.ensureRoom(
        branchId: branch.id,
        code: 'R9',
        name: 'Ruang',
      );
      final nurse = await master.ensureUser(
        email: 'perawat9@test.local',
        fullName: 'Perawat',
        role: UserRole.perawat,
        branchId: branch.id,
      );
      final category = await master.ensureCategory('Obat');
      final item = await master.ensureItem(
        sku: 'CHAIN-0001',
        name: 'Anestesi',
        categoryId: category.id,
        unit: 'ampul',
        minStockRoom: 1,
        minStockBranch: 1,
        hasExpiry: false,
      );

      await database.customStatement(
        'INSERT INTO stock_opnames (id, created_at, updated_at, sync_status, '
        'doc_number, branch_id, room_id, period_year, period_week, counted_by, '
        "status) VALUES ('so-chain', ?, ?, 'pending', 'TMP-SO-chain', ?, ?, "
        "2026, 31, ?, 'draft');",
        [
          '2026-07-29T00:00:00.000Z',
          '2026-07-29T00:00:00.000Z',
          branch.id,
          room.id,
          nurse.id,
        ],
      );
      await database.customStatement(
        'INSERT INTO stock_opname_lines (id, created_at, updated_at, '
        'sync_status, opname_id, item_id, system_qty, counted_qty) '
        "VALUES ('sol-chain', ?, ?, 'pending', 'so-chain', ?, ?, ?);",
        [
          '2026-07-29T00:00:00.000Z',
          '2026-07-29T00:00:00.000Z',
          item.id,
          Quantity.parse('5').milliUnits,
          Quantity.parse('3.5').milliUnits,
        ],
      );

      final row = await database
          .customSelect(
            "SELECT difference FROM stock_opname_lines WHERE id = 'sol-chain';",
          )
          .getSingle();
      expect(
        row.read<int>('difference'),
        Quantity.parse('3.5').milliUnits - Quantity.parse('5').milliUnits,
      );

      await database.close();
    });

    test('skala kuantitas v1 diterapkan tepat sekali sampai v10', () async {
      // A v1 database stores whole units. The chain must scale them once — and a
      // second open must not scale them again.
      final prepare = openDatabase();
      final master = DriftMasterDataRepository(prepare.masterDataDao);
      final branch = await master.ensureBranch(code: 'CAB-01', name: 'Cabang');
      final location = await master.ensureLocation(
        type: StockLocationType.warehouse,
        name: 'Warehouse Pusat',
      );
      final user = await master.ensureUser(
        email: 'wh@test.local',
        fullName: 'Petugas',
        role: UserRole.warehouse,
      );
      final category = await master.ensureCategory('Alat');
      final item = await master.ensureItem(
        sku: 'V1-0001',
        name: 'Masker',
        categoryId: category.id,
        unit: 'box',
        minStockRoom: 1,
        minStockBranch: 1,
        hasExpiry: false,
      );
      expect(branch.id, isNotEmpty);

      await prepare.customStatement(
        'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
        "location_id, item_id, qty_on_hand) VALUES ('v1-bal', ?, ?, 'pending', "
        '?, ?, 7);',
        [
          '2026-07-29T00:00:00.000Z',
          '2026-07-29T00:00:00.000Z',
          location.id,
          item.id,
        ],
      );
      await prepare.customStatement(
        'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
        'item_id, to_location_id, qty, movement_type, actor_user_id) '
        "VALUES ('v1-mov', ?, ?, 'pending', ?, ?, 7, 'inbound_warehouse', ?);",
        [
          '2026-07-29T00:00:00.000Z',
          '2026-07-29T00:00:00.000Z',
          item.id,
          location.id,
          user.id,
        ],
      );
      await prepare.customStatement('PRAGMA foreign_keys = OFF;');
      for (final table in const [
        'consumptions',
        'consumption_lines',
        'disposals',
        'disposal_lines',
        'distributions',
        'distribution_lines',
        'good_receipts',
        'good_receipt_lines',
        'delivery_orders',
        'delivery_order_lines',
        'purchase_requests',
        'purchase_request_opnames',
        'purchase_request_lines',
        'stock_opnames',
        'stock_opname_lines',
      ]) {
        await prepare.customStatement('DROP TABLE IF EXISTS $table;');
      }
      await prepare.customStatement('PRAGMA foreign_keys = ON;');
      await prepare.customStatement('PRAGMA user_version = 1;');
      await prepare.close();

      final migrated = openDatabase();
      final scaled = await migrated
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'v1-bal';",
          )
          .getSingle();
      expect(scaled.read<int>('qty_on_hand'), 7 * Quantity.scale);
      final scaledMovement = await migrated
          .customSelect("SELECT qty FROM stock_movements WHERE id = 'v1-mov';")
          .getSingle();
      expect(scaledMovement.read<int>('qty'), 7 * Quantity.scale);
      await migrated.close();

      final reopened = openDatabase();
      final again = await reopened
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'v1-bal';",
          )
          .getSingle();
      expect(
        again.read<int>('qty_on_hand'),
        7 * Quantity.scale,
        reason: 'Skala v1 → v2 diterapkan lebih dari sekali.',
      );
      await reopened.close();
    });
  });
}

/// Collapses whitespace so two identical statements formatted differently compare
/// equal — the SQL a migration writes and the SQL `createAll` writes are the same
/// object even when drift lays them out differently.
String _normalize(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ').trim();
