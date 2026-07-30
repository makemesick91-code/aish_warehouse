import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v8 → v9: the two Pemusnahan tables are added (§38).
///
/// The step is **purely additive**, and almost everything here is about proving
/// exactly that: not one existing column, row, index or constraint may move. That
/// matters most for the six things earlier migrations touched — the milli-unit
/// scaling the `from < 2` block applied, the `stock_opnames` rebuild the `from < 4`
/// block performed, and the Purchase Request, Delivery Order, Good Receipt and
/// Distribusi tables `from < 5`, `< 6`, `< 7` and `< 8` created. A v9 that re-scaled
/// quantities would double every balance in the clinic group; a v9 that changed
/// `stock_opnames` would make a v3 → v9 upgrade apply the v4 rebuild to the v9 shape
/// and then apply v5 to v9 on top.
///
/// One absence is asserted rather than assumed, and it is the interesting one:
/// **v9 must not invent disposals for the expired stock already on the devices'
/// shelves.** There will be some — nothing before this milestone could remove it —
/// and writing documents for it would be a migration asserting that somebody
/// destroyed goods and wrote a reason, on a date, which nobody did. The stock
/// surfaces instead as a *candidate* the moment somebody opens the new screen, which
/// is the honest outcome: it is still on the shelf.
///
/// A v8 database is reproduced by creating the current schema, dropping the two
/// Pemusnahan tables and their indexes, and stamping `user_version` back to 8.
/// Because v9 adds nothing else, what remains *is* a v8 database — and one of the
/// tests below pins that assumption by comparing the surviving object list against
/// the v8 inventory.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v8_to_v9.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  late String branchId;
  late String roomId;
  late String headId;
  late String warehouseUserId;
  late String itemId;
  late String batchItemId;
  late String batchId;
  late String warehouseLocationId;
  late String branchStoreLocationId;
  late String roomLocationId;

  /// Every table schema v8 had. Anything added to this list by v9 that is not a
  /// Pemusnahan table is a migration that is not additive.
  const v8Tables = <String>[
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
  ];

  const disposalTables = <String>['disposals', 'disposal_lines'];

  /// The tables versions **after** this migration add. Named here rather than
  /// omitted so the exhaustive table assertion below stays exhaustive: a v11 that
  /// added a table would fail this test until somebody accounted for it.
  const consumptionTables = <String>['consumptions', 'consumption_lines'];

  /// Milestone 9's tables. Declared here — in a test about an *earlier* step — because
  /// every migration lands a device on the current schema, so the exhaustive table
  /// assertions below have to know about every table that exists today.
  const goodsReturnTables = <String>['goods_returns', 'goods_return_lines'];

  const disposalIndexes = <String>[
    'idx_disposals_source_location_status',
    'idx_disposals_created_by_status',
    'idx_disposals_posted_by_status',
    'idx_disposals_created_at',
    'idx_disposals_posted_at',
    'idx_disposals_doc_number',
    'idx_disposal_lines_disposal',
    'idx_disposal_lines_item',
    'idx_disposal_lines_batch',
    'idx_disposal_lines_position',
  ];

  /// Writes a v8 database holding master data, ledger rows with milli-unit
  /// quantities, an opname, a Purchase Request, a Delivery Order, a posted Good
  /// Receipt and a posted Distribusi — everything a Pemusnahan will later sit beside,
  /// plus the balances it will later draw on. One of those balances is deliberately
  /// an **expired** batch on a room shelf, because that is the row a v9 might be
  /// tempted to write a document for.
  Future<void> createVersion8Database() async {
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
      batchNo: 'B-EXPIRED',
      // Already past, on any plausible day this test runs.
      expiryDate: DateTime.utc(2020, 1, 1),
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
    // The expired position a v9 must leave exactly where it is.
    await balance('bal-3', roomLocationId, batchItemId, batchId, '2.5');

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
        headId,
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
        // The v5 CHECK: anything past `draft` carries a submission instant.
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
        // The v6 CHECK pairs the shipping instant with the shipping actor.
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

    // Drop the Pemusnahan objects, leaving exactly a v8 database. Indexes go with
    // their tables in SQLite, so only the tables have to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in [
      ...goodsReturnTables,
      // Opening an older database migrates it to the current schema, so
      // v12's export audit table is present too.
      'export_logs',
      ...consumptionTables,
      ...disposalTables,
    ]) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 8;');
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

  group('v8 → v9', () {
    test('database v8 dibuka pada versi 9', () async {
      await createVersion8Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 12);

      await database.close();
    });

    test('dua tabel Pemusnahan ditambahkan dan tidak ada yang lain', () async {
      await createVersion8Database();
      final database = openDatabase();

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(disposalTables));
      // Exhaustive: v9 adds two tables, no more.
      expect(tables, {
        ...v8Tables,
        ...disposalTables,
        ...consumptionTables,
        ...goodsReturnTables,
        // Opening an older database migrates it to the current schema, so
        // v12's export audit table is present too.
        'export_logs',
      });

      await database.close();
    });

    test('seluruh index Pemusnahan ditambahkan', () async {
      await createVersion8Database();
      final database = openDatabase();

      expect(
        await objectNames(database, 'index'),
        containsAll(disposalIndexes),
      );

      await database.close();
    });

    test('index hasil migrasi identik dengan database v9 baru', () async {
      // The assertion that keeps the frozen migration SQL honest: an index created by
      // `_v9DisposalIndexes` and one created by `createAll` must be the same object,
      // or two devices would disagree about which rows are unique.
      await createVersion8Database();
      final migrated = openDatabase();
      final migratedIndexes = await indexSqlByName(migrated, 'disposal');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v9.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshIndexes = await indexSqlByName(fresh, 'disposal');
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
      await createVersion8Database();
      final database = openDatabase();

      final sql = (await indexSqlByName(
        database,
        'disposals_doc_number',
      ))['idx_disposals_doc_number']!;
      expect(sql, contains('UNIQUE'));
      expect(sql.toLowerCase().contains('where'), isFalse);

      await database.close();
    });

    test('tidak ada dokumen Pemusnahan yang dibuat otomatis', () async {
      // The load-bearing absence. The room shelf holds an expired batch, and a
      // migration that "helpfully" filed a disposal for it would be asserting a
      // business event — with a reason and an actor — that never happened.
      await createVersion8Database();
      final database = openDatabase();

      expect(await countOf(database, 'disposals'), 0);
      expect(await countOf(database, 'disposal_lines'), 0);

      final movements = await database
          .customSelect(
            "SELECT COUNT(*) AS c FROM stock_movements "
            "WHERE movement_type = 'disposal' OR ref_doc_type = 'DSP';",
          )
          .getSingle();
      expect(movements.read<int>('c'), 0);

      await database.close();
    });

    test('stok kedaluwarsa tetap di rak, tidak berkurang', () async {
      await createVersion8Database();
      final database = openDatabase();

      final row = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-3';",
          )
          .getSingle();
      expect(row.read<int>('qty_on_hand'), Quantity.parse('2.5').milliUnits);

      await database.close();
    });

    test('kuantitas milli-unit tidak diskalakan ulang', () async {
      await createVersion8Database();
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
        },
      );

      final movement = await database
          .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-1';")
          .getSingle();
      expect(movement.read<int>('qty'), Quantity.parse('10.5').milliUnits);

      await database.close();
    });

    test('dokumen milestone sebelumnya tidak tersentuh', () async {
      await createVersion8Database();
      final database = openDatabase();

      for (final table in const [
        'stock_opnames',
        'purchase_requests',
        'delivery_orders',
        'good_receipts',
        'distributions',
        'distribution_lines',
      ]) {
        expect(
          await countOf(database, table),
          1,
          reason: '$table berubah pada migrasi v9.',
        );
      }

      // And their statuses, which a migration inventing events would have moved.
      final statuses = await database
          .customSelect(
            "SELECT (SELECT status FROM stock_opnames) AS so, "
            "(SELECT status FROM purchase_requests) AS pr, "
            "(SELECT status FROM delivery_orders) AS dord, "
            "(SELECT status FROM good_receipts) AS gr, "
            "(SELECT status FROM distributions) AS dist;",
          )
          .getSingle();
      expect(statuses.read<String>('so'), 'submitted');
      expect(statuses.read<String>('pr'), 'submitted');
      expect(statuses.read<String>('dord'), 'shipped');
      expect(statuses.read<String>('gr'), 'posted');
      expect(statuses.read<String>('dist'), 'posted');

      await database.close();
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion8Database();
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

    test('membuka ulang database v9 tidak menjalankan migrasi lagi', () async {
      await createVersion8Database();

      final first = openDatabase();
      await first.customSelect('SELECT 1;').getSingle();
      await first.close();

      // Re-running the `from < 9` block would fail on `CREATE TABLE` for an existing
      // table; that it does not is what makes the step re-runnable.
      final second = openDatabase();
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 12);
      expect(await objectNames(second, 'table'), containsAll(disposalTables));
      await second.close();
    });

    test('CHECK Pemusnahan ditegakkan setelah migrasi', () async {
      await createVersion8Database();
      final database = openDatabase();

      // A posted row with no reason — the one the `IS NOT NULL` half of the CHECK
      // exists for — must be refused by a *migrated* database too, not only a fresh
      // one.
      await expectLater(
        database.customStatement(
          'INSERT INTO disposals (id, created_at, updated_at, sync_status, '
          'doc_number, source_location_id, created_by, status, posted_at, '
          'posted_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            'bad-1',
            '2026-07-30T00:00:00.000Z',
            '2026-07-30T00:00:00.000Z',
            'pending',
            'TMP-DSP-bad-1',
            warehouseLocationId,
            warehouseUserId,
            'posted',
            '2026-07-30T01:00:00.000Z',
            warehouseUserId,
          ],
        ),
        throwsA(anything),
      );

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
        11: goodsReturnTables,
        10: consumptionTables,
        9: disposalTables,
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

    /// Every version between v1 and v8 must land on v9 with the Pemusnahan tables in
    /// place and no foreign key violation.
    ///
    /// v1 and v2 are the interesting ones: the `from < 2` block scales every ledger
    /// quantity by 1000, and it must run **exactly once** whichever version the
    /// device started from. A v9 that re-triggered it would multiply every balance in
    /// the clinic group by a thousand.
    for (final from in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('database v$from bermigrasi hingga v9', () async {
        await rewindTo(from);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 12);

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(disposalTables));
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
          ]),
        );
        expect(
          await objectNames(database, 'index'),
          containsAll(disposalIndexes),
        );

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        // No disposal invented anywhere on the chain.
        expect(await countOf(database, 'disposals'), 0);

        await database.close();
      });
    }

    test('skala kuantitas v1 diterapkan tepat sekali sampai v9', () async {
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
