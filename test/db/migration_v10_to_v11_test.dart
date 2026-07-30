import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v10 → v11: the two Retur Barang tables are added (§12/§41).
///
/// The step is **purely additive**, and almost everything here is about proving
/// exactly that: not one existing column, row, index or constraint may move. That
/// matters most for the eight things earlier migrations touched — the milli-unit
/// scaling the `from < 2` block applied, the `stock_opnames` rebuild the `from < 4`
/// block performed, and the Purchase Request, Delivery Order, Good Receipt,
/// Distribusi, Pemusnahan and Pemakaian tables `from < 5` through `< 10` created. A
/// v11 that re-scaled quantities would multiply every balance in the clinic group by
/// a thousand; a v11 that changed `stock_opnames` would make a v3 → v11 upgrade apply
/// the v4 rebuild to the v11 shape and then apply v5 to v11 on top.
///
/// One absence is asserted rather than assumed, and on this milestone it is the most
/// consequential one in the whole suite: **v11 must not invent a return for the
/// rejected Good Receipt lines already on the device.** There will be some — nothing
/// before this milestone could send them back — and a migration that filed a document
/// for them would be asserting that a named Kepala Cabang raised it and shipped it on
/// a date nobody recorded. Worse, that document would then be one Warehouse
/// confirmation away from crediting stock that may have sat in a branch corridor for
/// months, or been thrown away. The fixture below therefore holds a posted Good
/// Receipt with a rejected line, and the test asserts the tables come up empty.
///
/// A v10 database is reproduced by creating the current schema, dropping the two Retur
/// tables and their indexes, and stamping `user_version` back to 10. Because v11 adds
/// nothing else, what remains *is* a v10 database — and one of the tests below pins
/// that assumption by comparing the surviving object list against the v10 inventory.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v10_to_v11.sqlite');
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

  /// Every table schema v10 had. Anything added to this list by v11 that is not a
  /// Retur table is a migration that is not additive.
  const v10Tables = <String>[
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
    'consumptions',
    'consumption_lines',
  ];

  const goodsReturnTables = <String>['goods_returns', 'goods_return_lines'];

  const goodsReturnIndexes = <String>[
    'idx_goods_returns_branch_status',
    'idx_goods_returns_created_by_status',
    'idx_goods_returns_shipped_by_status',
    'idx_goods_returns_received_by_status',
    'idx_goods_returns_created_at',
    'idx_goods_returns_shipped_at',
    'idx_goods_returns_received_at',
    'idx_goods_returns_gr',
    'idx_goods_returns_doc_number',
    'idx_goods_return_lines_return',
    'idx_goods_return_lines_gr_line',
    'idx_goods_return_lines_item',
    'idx_goods_return_lines_batch',
    'idx_goods_return_lines_gr_line_unique',
    'idx_goods_return_lines_unique',
  ];

  /// Writes a v10 database holding master data, ledger rows with milli-unit
  /// quantities, an opname, a Purchase Request, a Delivery Order, a **posted Good
  /// Receipt carrying one rejected and one checked-with-shortage line**, a posted
  /// Distribusi, a posted Pemusnahan and a posted Pemakaian.
  ///
  /// The two Good Receipt lines are the point of the fixture: one is the rejection a
  /// v11 might be tempted to file a return for, and the other is a shortage that must
  /// never be treated as one — a shortage is a delivery discrepancy, not goods coming
  /// back (§16.10).
  Future<void> createVersion10Database() async {
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
      expiryDate: DateTime.utc(2099, 1, 1),
    )).id;

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

    // The warehouse balance a return would later credit — asserted unchanged below,
    // because the migration must not post one.
    await balance('bal-1', warehouseLocationId, itemId, null, '10.5');
    await balance('bal-2', branchStoreLocationId, itemId, null, '4');
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
    // Two request lines, because `delivery_order_lines` is unique on
    // `(do_id, pr_line_id)` for an unbatched allocation — and the fixture needs two
    // shipped positions so it can carry one rejection *and* one shortage.
    for (final line in [('prl-1', itemId), ('prl-2', batchItemId)]) {
      await database.customStatement(
        'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
        'sync_status, pr_id, item_id, suggested_qty, requested_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          line.$1,
          '2026-07-29T00:00:00.000Z',
          '2026-07-29T00:00:00.000Z',
          'pending',
          'pr-1',
          line.$2,
          Quantity.parse('6').milliUnits,
          Quantity.parse('6').milliUnits,
        ],
      );
    }
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
    for (final line in [
      ('dol-1', 'prl-1', itemId, null, '4'),
      ('dol-2', 'prl-2', batchItemId, batchId, '2'),
    ]) {
      await database.customStatement(
        'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
        'sync_status, do_id, pr_line_id, item_id, batch_id, shipped_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          line.$1,
          '2026-07-29T01:00:00.000Z',
          '2026-07-29T01:00:00.000Z',
          'pending',
          'do-1',
          line.$2,
          line.$3,
          line.$4,
          Quantity.parse(line.$5).milliUnits,
        ],
      );
    }
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
    // The rejection a v11 must not file a return for.
    await database.customStatement(
      'INSERT INTO good_receipt_lines (id, created_at, updated_at, sync_status, '
      'gr_id, do_line_id, item_id, batch_id, shipped_qty, received_qty, '
      'line_status, reject_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'grl-rejected',
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        'pending',
        'gr-1',
        'dol-1',
        itemId,
        null,
        Quantity.parse('4').milliUnits,
        0,
        'rejected',
        'Kemasan rusak',
      ],
    );
    // The shortage that is *not* a return, ever (§16.10).
    await database.customStatement(
      'INSERT INTO good_receipt_lines (id, created_at, updated_at, sync_status, '
      'gr_id, do_line_id, item_id, batch_id, shipped_qty, received_qty, '
      'line_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'grl-short',
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        'pending',
        'gr-1',
        'dol-2',
        batchItemId,
        batchId,
        Quantity.parse('2').milliUnits,
        Quantity.parse('1').milliUnits,
        'checked',
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
    await database.customStatement(
      'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, room_id, created_by, status, posted_at, posted_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'cns-1',
        '2026-07-29T09:00:00.000Z',
        '2026-07-29T09:00:00.000Z',
        'pending',
        'TMP-CNS-cns-1',
        branchId,
        roomId,
        nurseId,
        'posted',
        '2026-07-29T10:00:00.000Z',
        nurseId,
      ],
    );

    // Drop the Retur objects, leaving exactly a v10 database. Indexes go with their
    // tables in SQLite, so only the tables have to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in goodsReturnTables) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 10;');
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

  group('v10 → v11', () {
    test('database v10 dibuka pada versi 11', () async {
      await createVersion10Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 11);

      await database.close();
    });

    test('dua tabel Retur ditambahkan dan tidak ada yang lain', () async {
      await createVersion10Database();
      final database = openDatabase();

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(goodsReturnTables));
      // Exhaustive: v11 adds two tables, no more.
      expect(tables, {...v10Tables, ...goodsReturnTables});

      await database.close();
    });

    test('seluruh index Retur ditambahkan', () async {
      await createVersion10Database();
      final database = openDatabase();

      expect(
        await objectNames(database, 'index'),
        containsAll(goodsReturnIndexes),
      );

      await database.close();
    });

    test('index hasil migrasi identik dengan database v11 baru', () async {
      // The assertion that keeps the frozen migration SQL honest: an index created by
      // `_v11GoodsReturnIndexes` and one created by `createAll` must be the same
      // object, or two devices would disagree about which rows are unique — and on
      // this table "which rows are unique" is what stops a Good Receipt being returned
      // twice.
      await createVersion10Database();
      final migrated = openDatabase();
      final migratedIndexes = await indexSqlByName(migrated, 'goods_return');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v11.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshIndexes = await indexSqlByName(fresh, 'goods_return');
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

    test('unique gr_id dan gr_line_id tanpa partial setelah migrasi', () async {
      await createVersion10Database();
      final database = openDatabase();

      final indexes = await indexSqlByName(database, 'goods_return');
      for (final name in const [
        'idx_goods_returns_gr',
        'idx_goods_returns_doc_number',
        'idx_goods_return_lines_gr_line_unique',
        'idx_goods_return_lines_unique',
      ]) {
        final sql = indexes[name]!;
        expect(sql, contains('UNIQUE'), reason: '$name bukan unique.');
        expect(
          sql.toLowerCase().contains('where'),
          isFalse,
          reason:
              '$name partial: soft delete akan membebaskan slot retur dan '
              'saldo Warehouse bisa bertambah dua kali.',
        );
      }

      await database.close();
    });

    test('tidak ada dokumen Retur yang dibuat otomatis', () async {
      // The load-bearing absence of this milestone. The fixture holds a posted Good
      // Receipt with a rejected line — exactly the row a migration might "helpfully"
      // file a return for — and doing so would assert a shipment nobody performed.
      await createVersion10Database();
      final database = openDatabase();

      expect(await countOf(database, 'goods_returns'), 0);
      expect(await countOf(database, 'goods_return_lines'), 0);

      final movements = await database
          .customSelect(
            'SELECT COUNT(*) AS c FROM stock_movements '
            "WHERE movement_type = 'return' OR ref_doc_type = 'RET';",
          )
          .getSingle();
      expect(movements.read<int>('c'), 0);

      await database.close();
    });

    test('baris rejected dan shortage GR tetap apa adanya', () async {
      await createVersion10Database();
      final database = openDatabase();

      final rows = await database
          .customSelect(
            'SELECT id, line_status, shipped_qty, received_qty, reject_reason '
            'FROM good_receipt_lines ORDER BY id;',
          )
          .get();
      expect(rows.length, 2);
      expect(rows.first.read<String>('id'), 'grl-rejected');
      expect(rows.first.read<String>('line_status'), 'rejected');
      expect(rows.first.read<int>('received_qty'), 0);
      expect(rows.first.read<String>('reject_reason'), 'Kemasan rusak');
      // The shortage is still a shortage: `checked`, and nothing about it changed.
      expect(rows.last.read<String>('id'), 'grl-short');
      expect(rows.last.read<String>('line_status'), 'checked');
      expect(
        rows.last.read<int>('received_qty'),
        Quantity.parse('1').milliUnits,
      );

      await database.close();
    });

    test('saldo Warehouse tidak bertambah oleh migrasi', () async {
      await createVersion10Database();
      final database = openDatabase();

      final row = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
          )
          .getSingle();
      expect(row.read<int>('qty_on_hand'), Quantity.parse('10.5').milliUnits);

      await database.close();
    });

    test('kuantitas milli-unit tidak diskalakan ulang', () async {
      await createVersion10Database();
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
      await createVersion10Database();
      final database = openDatabase();

      for (final table in const [
        'stock_opnames',
        'purchase_requests',
        'delivery_orders',
        'good_receipts',
        'distributions',
        'disposals',
        'consumptions',
      ]) {
        expect(
          await countOf(database, table),
          1,
          reason: '$table berubah pada migrasi v11.',
        );
      }

      // And their statuses, which a migration inventing events would have moved.
      final statuses = await database
          .customSelect(
            'SELECT (SELECT status FROM stock_opnames) AS so, '
            '(SELECT status FROM purchase_requests) AS pr, '
            '(SELECT status FROM delivery_orders) AS dord, '
            '(SELECT status FROM good_receipts) AS gr, '
            '(SELECT status FROM distributions) AS dist, '
            '(SELECT status FROM disposals) AS dsp, '
            '(SELECT status FROM consumptions) AS cns;',
          )
          .getSingle();
      expect(statuses.read<String>('so'), 'submitted');
      expect(statuses.read<String>('pr'), 'submitted');
      expect(statuses.read<String>('dord'), 'shipped');
      expect(statuses.read<String>('gr'), 'posted');
      expect(statuses.read<String>('dist'), 'posted');
      expect(statuses.read<String>('dsp'), 'posted');
      expect(statuses.read<String>('cns'), 'posted');

      await database.close();
    });

    test('index milestone sebelumnya tidak hilang', () async {
      await createVersion10Database();
      final database = openDatabase();

      expect(
        await objectNames(database, 'index'),
        containsAll(<String>[
          'idx_stock_opnames_branch_status',
          'idx_purchase_requests_active_branch',
          'idx_delivery_order_lines_batched',
          'idx_good_receipts_do',
          'idx_good_receipt_lines_unique',
          'idx_distribution_lines_batched',
          'idx_disposals_doc_number',
          'idx_disposal_lines_position',
          'idx_consumptions_doc_number',
          'idx_consumption_lines_batched',
        ]),
      );

      await database.close();
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion10Database();
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

    test('membuka ulang database v11 tidak menjalankan migrasi lagi', () async {
      await createVersion10Database();

      final first = openDatabase();
      await first.customSelect('SELECT 1;').getSingle();
      await first.close();

      // Re-running the `from < 11` block would fail on `CREATE TABLE` for an existing
      // table; that it does not is what makes the step re-runnable.
      final second = openDatabase();
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 11);
      expect(
        await objectNames(second, 'table'),
        containsAll(goodsReturnTables),
      );
      await second.close();
    });

    test('CHECK Retur ditegakkan setelah migrasi', () async {
      await createVersion10Database();
      final database = openDatabase();

      Future<void> insertHeader(
        String id,
        String status, {
        String? shippedAt,
        String? shippedBy,
        String? receivedAt,
        String? receivedBy,
        String? note,
      }) => database.customStatement(
        'INSERT INTO goods_returns (id, created_at, updated_at, sync_status, '
        'doc_number, gr_id, branch_id, created_by, status, note, shipped_at, '
        'shipped_by, received_at, received_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          'pending',
          'TMP-RET-$id',
          'gr-1',
          branchId,
          headId,
          status,
          note,
          shippedAt,
          shippedBy,
          receivedAt,
          receivedBy,
        ],
      );

      // A status the enum does not know.
      await expectLater(
        insertHeader('bad-status', 'approved'),
        throwsA(anything),
      );
      // Shipped without an actor.
      await expectLater(
        insertHeader(
          'bad-shipped',
          'shipped',
          shippedAt: '2026-07-30T01:00:00.000Z',
        ),
        throwsA(anything),
      );
      // Received without having been shipped.
      await expectLater(
        insertHeader(
          'bad-received',
          'received',
          receivedAt: '2026-07-30T02:00:00.000Z',
          receivedBy: warehouseUserId,
        ),
        throwsA(anything),
      );
      // G-R4: the creator may not be the receiver.
      await expectLater(
        insertHeader(
          'bad-sod',
          'received',
          shippedAt: '2026-07-30T01:00:00.000Z',
          shippedBy: headId,
          receivedAt: '2026-07-30T02:00:00.000Z',
          receivedBy: headId,
        ),
        throwsA(anything),
      );
      // A draft carrying a shipping actor it has no business having.
      await expectLater(
        insertHeader('bad-draft', 'draft', shippedBy: headId),
        throwsA(anything),
      );
      // Whitespace pretending to be a note.
      await expectLater(
        insertHeader('bad-note', 'draft', note: '   '),
        throwsA(anything),
      );

      await database.close();
    });

    test('index gr_id Retur ditegakkan setelah migrasi', () async {
      await createVersion10Database();
      final database = openDatabase();

      Future<void> insert(String id) => database.customStatement(
        'INSERT INTO goods_returns (id, created_at, updated_at, sync_status, '
        'doc_number, gr_id, branch_id, created_by, status) '
        "VALUES (?, ?, ?, 'pending', ?, 'gr-1', ?, ?, 'draft');",
        [
          id,
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          'TMP-RET-$id',
          branchId,
          headId,
        ],
      );
      await insert('ret-1');
      // One Good Receipt, one Retur.
      await expectLater(insert('ret-2'), throwsA(anything));

      Future<void> insertLine(String id, String returnId) =>
          database.customStatement(
            'INSERT INTO goods_return_lines (id, created_at, updated_at, '
            'sync_status, goods_return_id, gr_line_id, item_id, batch_id, qty, '
            "reject_reason_snapshot) VALUES (?, ?, ?, 'pending', ?, "
            "'grl-rejected', ?, NULL, 4000, 'Kemasan rusak');",
            [
              id,
              '2026-07-30T00:00:00.000Z',
              '2026-07-30T00:00:00.000Z',
              returnId,
              itemId,
            ],
          );
      await insertLine('retl-1', 'ret-1');
      // One rejected position, one return line, ever.
      await expectLater(insertLine('retl-2', 'ret-1'), throwsA(anything));

      // And a zero quantity, and a blank reason.
      await expectLater(
        database.customStatement(
          'INSERT INTO goods_return_lines (id, created_at, updated_at, '
          'sync_status, goods_return_id, gr_line_id, item_id, batch_id, qty, '
          "reject_reason_snapshot) VALUES ('retl-zero', ?, ?, 'pending', "
          "'ret-1', 'grl-short', ?, NULL, 0, 'Alasan');",
          ['2026-07-30T00:00:00.000Z', '2026-07-30T00:00:00.000Z', itemId],
        ),
        throwsA(anything),
      );
      await expectLater(
        database.customStatement(
          'INSERT INTO goods_return_lines (id, created_at, updated_at, '
          'sync_status, goods_return_id, gr_line_id, item_id, batch_id, qty, '
          "reject_reason_snapshot) VALUES ('retl-blank', ?, ?, 'pending', "
          "'ret-1', 'grl-short', ?, NULL, 1000, '   ');",
          ['2026-07-30T00:00:00.000Z', '2026-07-30T00:00:00.000Z', itemId],
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
        10: ['consumptions', 'consumption_lines'],
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

    /// Every version between v1 and v10 must land on v11 with the Retur tables in
    /// place and no foreign key violation.
    ///
    /// v1 and v2 are the interesting ones: the `from < 2` block scales every ledger
    /// quantity by 1000, and it must run **exactly once** whichever version the device
    /// started from. A v11 that re-triggered it would multiply every balance in the
    /// clinic group by a thousand.
    for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      test('database v$from bermigrasi hingga v11', () async {
        await rewindTo(from);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 11);

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(goodsReturnTables));
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
            'consumptions',
            'consumption_lines',
          ]),
        );
        expect(
          await objectNames(database, 'index'),
          containsAll(goodsReturnIndexes),
        );

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        // No return invented anywhere on the chain.
        expect(await countOf(database, 'goods_returns'), 0);
        expect(await countOf(database, 'goods_return_lines'), 0);

        await database.close();
      });
    }

    test('generated column difference tetap bekerja sampai v11', () async {
      // The v4 rebuild reads the *current* Dart definition of `stock_opnames`, so a
      // v11 that changed that table would land a v3 device on the v11 shape and then
      // apply steps 5 to 11 on top. The generated `difference` column is the cheapest
      // proof the rebuild still produced a working table.
      await rewindTo(3);
      final database = openDatabase();
      final master = DriftMasterDataRepository(database.masterDataDao);

      final branch = await master.ensureBranch(code: 'CAB-11', name: 'Cabang');
      final room = await master.ensureRoom(
        branchId: branch.id,
        code: 'R9',
        name: 'Ruang',
      );
      final nurse = await master.ensureUser(
        email: 'perawat11@test.local',
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

    test('skala kuantitas v1 diterapkan tepat sekali sampai v11', () async {
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
        'goods_returns',
        'goods_return_lines',
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
