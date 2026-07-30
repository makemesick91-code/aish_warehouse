import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v11 → v12: `export_logs` is added (§13, §54).
///
/// The step is **purely additive**, and most of this file proves exactly that: not
/// one existing column, row, index or constraint may move. That matters most for
/// the two things earlier migrations touched — the milli-unit scaling the `from < 2`
/// block applied and the `stock_opnames` rebuild the `from < 4` block performed —
/// because a v12 that re-scaled quantities would multiply every balance in the
/// clinic group by a thousand.
///
/// One absence is asserted rather than assumed, and on this milestone it is the
/// load-bearing one: **v12 must not invent an export log for anything already on
/// the device.** Before v12 nothing could export, so nothing did — and a migration
/// that filed rows would put entries in the Super Admin's audit screen that are
/// indistinguishable from real ones while describing files that never existed.
///
/// A v11 database is reproduced by creating the current schema, dropping
/// `export_logs`, and stamping `user_version` back to 11.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v11_to_v12.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  /// Every table schema v11 had. Anything v12 adds that is not `export_logs` is a
  /// migration that is not additive.
  const v11Tables = <String>[
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
    'goods_returns',
    'goods_return_lines',
  ];

  const exportLogTables = <String>['export_logs'];

  const exportLogIndexes = <String>[
    'idx_export_logs_actor',
    'idx_export_logs_type',
    'idx_export_logs_format',
    'idx_export_logs_scope',
    'idx_export_logs_branch',
    'idx_export_logs_location',
    'idx_export_logs_category',
    'idx_export_logs_item',
    'idx_export_logs_created_at',
  ];

  late String warehouseLocationId;
  late String itemId;
  late String userId;

  /// Writes a v11 database holding master data and ledger rows with milli-unit
  /// quantities, then removes `export_logs`.
  Future<void> createVersion11Database() async {
    final database = openDatabase();
    final master = DriftMasterDataRepository(database.masterDataDao);

    final branch = await master.ensureBranch(code: 'CAB-12', name: 'Cabang');
    final warehouse = await master.ensureLocation(
      type: StockLocationType.warehouse,
      name: 'Warehouse Pusat',
    );
    warehouseLocationId = warehouse.id;
    final user = await master.ensureUser(
      email: 'wh12@test.local',
      fullName: 'Petugas',
      role: UserRole.warehouse,
    );
    userId = user.id;
    final category = await master.ensureCategory('Obat');
    final item = await master.ensureItem(
      sku: 'MIG-0001',
      name: 'Anestesi',
      categoryId: category.id,
      unit: 'ampul',
      minStockRoom: 1,
      minStockBranch: 1,
      hasExpiry: false,
    );
    itemId = item.id;
    expect(branch.id, isNotEmpty);

    await database.customStatement(
      'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
      "location_id, item_id, qty_on_hand) VALUES ('bal-1', ?, ?, 'pending', "
      '?, ?, ?);',
      [
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        warehouse.id,
        item.id,
        Quantity.parse('7.5').milliUnits,
      ],
    );
    await database.customStatement(
      'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
      'item_id, to_location_id, qty, movement_type, actor_user_id) '
      "VALUES ('mov-1', ?, ?, 'pending', ?, ?, ?, 'inbound_warehouse', ?);",
      [
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        item.id,
        warehouse.id,
        Quantity.parse('7.5').milliUnits,
        user.id,
      ],
    );

    // Drop the v12 object, leaving exactly a v11 database. Indexes go with their
    // table in SQLite, so only the table has to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in exportLogTables) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 11;');
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

  group('v11 → v12', () {
    test('database v11 dibuka pada versi 12', () async {
      await createVersion11Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 12);

      await database.close();
    });

    test('satu tabel ditambahkan dan tidak ada yang lain', () async {
      await createVersion11Database();
      final database = openDatabase();

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(exportLogTables));
      // Exhaustive: v12 adds one table, no more.
      expect(tables, {...v11Tables, ...exportLogTables});

      await database.close();
    });

    test('seluruh index audit ditambahkan', () async {
      await createVersion11Database();
      final database = openDatabase();

      expect(
        await objectNames(database, 'index'),
        containsAll(exportLogIndexes),
      );

      await database.close();
    });

    test('index hasil migrasi identik dengan database v12 baru', () async {
      // The assertion that keeps the frozen migration SQL honest: an index created
      // by `_v12ExportLogIndexes` and one created by `createAll` must be the same
      // object, or two devices would disagree about how the audit is queried.
      await createVersion11Database();
      final migrated = openDatabase();
      final migratedIndexes = await indexSqlByName(migrated, 'export_logs');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v12.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshIndexes = await indexSqlByName(fresh, 'export_logs');
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

    test('tidak ada export log yang dibuat otomatis', () async {
      // The load-bearing absence of this milestone — see the file note.
      await createVersion11Database();
      final database = openDatabase();

      expect(await countOf(database, 'export_logs'), 0);

      await database.close();
    });

    test('data inventory tetap apa adanya', () async {
      await createVersion11Database();
      final database = openDatabase();

      final balance = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
          )
          .getSingle();
      expect(
        balance.read<int>('qty_on_hand'),
        Quantity.parse('7.5').milliUnits,
      );

      final movement = await database
          .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-1';")
          .getSingle();
      expect(movement.read<int>('qty'), Quantity.parse('7.5').milliUnits);

      await database.close();
    });

    test('kuantitas milli-unit tidak diskalakan ulang', () async {
      await createVersion11Database();
      final first = openDatabase();
      final firstValue =
          (await first
                  .customSelect(
                    "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
                  )
                  .getSingle())
              .read<int>('qty_on_hand');
      await first.close();

      final second = openDatabase();
      final secondValue =
          (await second
                  .customSelect(
                    "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
                  )
                  .getSingle())
              .read<int>('qty_on_hand');
      await second.close();

      expect(firstValue, secondValue);
      expect(firstValue, Quantity.parse('7.5').milliUnits);
    });

    test('index milestone sebelumnya tidak hilang', () async {
      await createVersion11Database();
      final database = openDatabase();

      expect(
        await objectNames(database, 'index'),
        containsAll(<String>[
          'idx_stock_opnames_doc_number',
          'idx_purchase_requests_active_branch',
          'idx_delivery_order_lines_batched',
          'idx_good_receipts_do',
          'idx_distribution_lines_batched',
          'idx_disposal_lines_position',
          'idx_consumption_lines_batched',
          'idx_goods_returns_gr',
        ]),
      );

      await database.close();
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion11Database();
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

    test('membuka ulang database v12 tidak menjalankan migrasi lagi', () async {
      await createVersion11Database();
      final first = openDatabase();
      await first.close();

      final second = openDatabase();
      expect(await countOf(second, 'export_logs'), 0);
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 12);
      await second.close();
    });

    test('CHECK export_logs ditegakkan setelah migrasi', () async {
      await createVersion11Database();
      final database = openDatabase();

      Future<void> insert({
        required String id,
        String scopeType = 'warehouse',
        String? locationId,
        String? branchId,
        String fileName = 'stok_lokasi_WH_20260730.xlsx',
        String syncSummary = 'Status sync: 0 tersinkron',
        int rowCount = 1,
      }) => database.customStatement(
        'INSERT INTO export_logs (id, created_at, updated_at, sync_status, '
        'report_type, format, scope_type, location_id, branch_id, '
        'period_start, period_end, exported_by, file_name, data_cutoff_at, '
        'sync_summary, row_count) '
        "VALUES (?, ?, ?, 'pending', 'stok_lokasi', 'xlsx', ?, ?, ?, ?, ?, ?, "
        '?, ?, ?, ?);',
        [
          id,
          '2026-07-30T14:00:00.000Z',
          '2026-07-30T14:00:00.000Z',
          scopeType,
          locationId,
          branchId,
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          userId,
          fileName,
          '2026-07-30T14:00:00.000Z',
          syncSummary,
          rowCount,
        ],
      );

      // Scope shape.
      await expectLater(
        insert(id: 'bad-1', locationId: null),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insert(
          id: 'bad-2',
          scopeType: 'branch_all',
          locationId: null,
          branchId: null,
        ),
        throwsA(isA<Exception>()),
      );
      // Text and number.
      await expectLater(
        insert(id: 'bad-3', locationId: warehouseLocationId, fileName: '  '),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insert(id: 'bad-4', locationId: warehouseLocationId, syncSummary: ''),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insert(id: 'bad-5', locationId: warehouseLocationId, rowCount: -1),
        throwsA(isA<Exception>()),
      );

      // The compliant row lands.
      await insert(id: 'good-1', locationId: warehouseLocationId);
      expect(await countOf(database, 'export_logs'), 1);

      await database.close();
    });

    test('foreign key export_logs ditegakkan setelah migrasi', () async {
      await createVersion11Database();
      final database = openDatabase();

      await expectLater(
        database.customStatement(
          'INSERT INTO export_logs (id, created_at, updated_at, sync_status, '
          'report_type, format, scope_type, location_id, period_start, '
          'period_end, exported_by, file_name, data_cutoff_at, sync_summary, '
          "row_count) VALUES ('fk-1', ?, ?, 'pending', 'stok_lokasi', 'xlsx', "
          "'warehouse', ?, ?, ?, 'pengguna-tidak-ada', 'x.xlsx', ?, 'sync', 0);",
          [
            '2026-07-30T14:00:00.000Z',
            '2026-07-30T14:00:00.000Z',
            warehouseLocationId,
            '2026-07-30T00:00:00.000Z',
            '2026-07-30T00:00:00.000Z',
            '2026-07-30T14:00:00.000Z',
          ],
        ),
        throwsA(isA<Exception>()),
      );

      await database.close();
    });

    test('dokumen milestone sebelumnya tidak tersentuh', () async {
      await createVersion11Database();
      final database = openDatabase();

      for (final table in v11Tables) {
        // Every earlier table still answers a query — the cheapest proof none of
        // them was rebuilt or dropped.
        await database.customSelect('SELECT COUNT(*) AS c FROM $table;').get();
      }
      expect(itemId, isNotEmpty);

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
        12: exportLogTables,
        11: ['goods_returns', 'goods_return_lines'],
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

    /// Every version between v1 and v11 must land on v12 with `export_logs` in
    /// place, no foreign key violation, and no invented audit row.
    for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]) {
      test('database v$from bermigrasi hingga v12', () async {
        await rewindTo(from);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 12);

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(exportLogTables));
        expect(tables, containsAll(v11Tables));
        expect(
          await objectNames(database, 'index'),
          containsAll(exportLogIndexes),
        );

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        expect(await countOf(database, 'export_logs'), 0);

        await database.close();
      });
    }

    test('generated column difference tetap bekerja sampai v12', () async {
      // The v4 rebuild reads the *current* Dart definition of `stock_opnames`, so a
      // v12 that changed that table would land a v3 device on the v12 shape and
      // then apply steps 5 to 12 on top. The generated `difference` column is the
      // cheapest proof the rebuild still produced a working table.
      await rewindTo(3);
      final database = openDatabase();
      final master = DriftMasterDataRepository(database.masterDataDao);

      final branch = await master.ensureBranch(code: 'CAB-C12', name: 'Cabang');
      final room = await master.ensureRoom(
        branchId: branch.id,
        code: 'R9',
        name: 'Ruang',
      );
      final nurse = await master.ensureUser(
        email: 'perawat12@test.local',
        fullName: 'Perawat',
        role: UserRole.perawat,
        branchId: branch.id,
      );
      final category = await master.ensureCategory('Obat');
      final item = await master.ensureItem(
        sku: 'CHAIN-12',
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
        "status) VALUES ('so-chain12', ?, ?, 'pending', 'TMP-SO-chain12', ?, ?, "
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
        "VALUES ('sol-chain12', ?, ?, 'pending', 'so-chain12', ?, ?, ?);",
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
            "SELECT difference FROM stock_opname_lines WHERE id = 'sol-chain12';",
          )
          .getSingle();
      expect(
        row.read<int>('difference'),
        Quantity.parse('3.5').milliUnits - Quantity.parse('5').milliUnits,
      );

      await database.close();
    });

    test('skala kuantitas v1 diterapkan tepat sekali sampai v12', () async {
      // A v1 database stores whole units. The chain must scale them once — and a
      // second open must not scale them again.
      final prepare = openDatabase();
      final master = DriftMasterDataRepository(prepare.masterDataDao);
      final location = await master.ensureLocation(
        type: StockLocationType.warehouse,
        name: 'Warehouse Pusat',
      );
      final user = await master.ensureUser(
        email: 'wh-v1-12@test.local',
        fullName: 'Petugas',
        role: UserRole.warehouse,
      );
      final category = await master.ensureCategory('Alat');
      final item = await master.ensureItem(
        sku: 'V1-12',
        name: 'Masker',
        categoryId: category.id,
        unit: 'box',
        minStockRoom: 1,
        minStockBranch: 1,
        hasExpiry: false,
      );

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
        'export_logs',
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
      expect(await countOf(migrated, 'export_logs'), 0);
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
