import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v12 → v13: `import_logs` is added (§8, §12).
///
/// The step is **purely additive**, and most of this file proves exactly that:
/// not one existing column, row, index or constraint may move. That matters most
/// for the two things earlier migrations touched — the milli-unit scaling the
/// `from < 2` block applied and the `stock_opnames` rebuild the `from < 4` block
/// performed — because a v13 that re-scaled quantities would multiply every
/// balance in the clinic group by a thousand.
///
/// Two absences are asserted rather than assumed, and on this milestone they are
/// the load-bearing ones:
///
/// * **v13 must not touch master data.** This is the master-data milestone, and
///   it is the one with the strongest reason to reach into `items` or lower-case
///   an email. It does not: a migration that tidied a SKU would be doing exactly
///   what G-M5 forbids the import itself to do, with nobody's name on it.
/// * **v13 must not invent an import log.** Before v13 nothing could import, so
///   nothing did — and every fabricated row would claim a named person uploaded a
///   named file whose SHA-256 the migration would have had to invent.
///
/// A v12 database is reproduced by creating the current schema, dropping
/// `import_logs`, and stamping `user_version` back to 12.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v12_to_v13.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  /// Every table schema v12 had. Anything v13 adds that is not `import_logs` is
  /// a migration that is not additive.
  const v12Tables = <String>[
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
    'export_logs',
  ];

  const importLogTables = <String>['import_logs'];

  const importLogIndexes = <String>[
    'idx_import_logs_entity_status',
    'idx_import_logs_status',
    'idx_import_logs_actor',
    'idx_import_logs_created_at',
    'idx_import_logs_sha256',
    'idx_import_logs_sync',
  ];

  late String warehouseLocationId;
  late String itemId;
  late String userId;
  late String branchId;
  late String categoryId;

  /// Writes a v12 database holding master data, ledger rows with milli-unit
  /// quantities and one export log, then removes `import_logs`.
  Future<void> createVersion12Database() async {
    final database = openDatabase();
    final master = DriftMasterDataRepository(database.masterDataDao);

    final branch = await master.ensureBranch(code: 'CAB-13', name: 'Cabang');
    branchId = branch.id;
    final warehouse = await master.ensureLocation(
      type: StockLocationType.warehouse,
      name: 'Warehouse Pusat',
    );
    warehouseLocationId = warehouse.id;
    final user = await master.ensureUser(
      email: 'wh13@test.local',
      fullName: 'Petugas',
      role: UserRole.warehouse,
    );
    userId = user.id;
    final category = await master.ensureCategory('Obat');
    categoryId = category.id;
    final item = await master.ensureItem(
      sku: 'MIG-0013',
      name: 'Anestesi',
      categoryId: category.id,
      unit: 'ampul',
      minStockRoom: 1,
      minStockBranch: 2,
      hasExpiry: false,
    );
    itemId = item.id;

    await database.customStatement(
      'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
      "location_id, item_id, qty_on_hand) VALUES ('bal-13', ?, ?, 'pending', "
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
      "VALUES ('mov-13', ?, ?, 'pending', ?, ?, ?, 'inbound_warehouse', ?);",
      [
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        item.id,
        warehouse.id,
        Quantity.parse('7.5').milliUnits,
        user.id,
      ],
    );
    // One export log, so the "v12's audit survives v13 untouched" assertion has
    // something to be about.
    await database.customStatement(
      'INSERT INTO export_logs (id, created_at, updated_at, sync_status, '
      'report_type, format, scope_type, location_id, period_start, '
      'period_end, exported_by, file_name, data_cutoff_at, sync_summary, '
      'row_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'exp-13',
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        'pending',
        'stok_lokasi',
        'xlsx',
        'warehouse',
        warehouse.id,
        '2026-07-01T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        user.id,
        'stok_lokasi_warehouse_2026-W31.xlsx',
        '2026-07-29T00:00:00.000Z',
        '1 tersinkron · 0 pending · 0 konflik',
        1,
      ],
    );

    // Drop the v13 object, leaving exactly a v12 database. Indexes go with their
    // table in SQLite, so only the table has to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in importLogTables) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 12;');
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

  group('v12 → v13', () {
    test('database v12 dibuka pada versi 13', () async {
      await createVersion12Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 15);

      await database.close();
    });

    test('satu tabel ditambahkan dan tidak ada yang lain', () async {
      await createVersion12Database();
      final database = openDatabase();

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(importLogTables));
      // Exhaustive: v13 adds one table, no more.
      expect(tables, {
        ...v12Tables,
        ...importLogTables,
        'sync_devices',
        'sync_outbox',
        'sync_entity_states',
        'sync_attempt_logs',
        'sync_conflict_logs',
        'sync_file_uploads',
        'sync_pull_cursors',
        'sync_entity_snapshots',
        'sync_field_versions',
        'sync_tombstones',
        'sync_pull_logs',
      });

      await database.close();
    });

    test('seluruh index import ditambahkan', () async {
      await createVersion12Database();
      final database = openDatabase();

      expect(
        await objectNames(database, 'index'),
        containsAll(importLogIndexes),
      );

      await database.close();
    });

    test('index hasil migrasi identik dengan database v13 baru', () async {
      // The assertion that keeps the frozen migration SQL honest: an index
      // created by `_v13ImportLogIndexes` and one created by `createAll` must be
      // the same object, or two devices would disagree about how the audit is
      // queried.
      await createVersion12Database();
      final migrated = openDatabase();
      final migratedIndexes = await indexSqlByName(migrated, 'import_logs');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v13.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshIndexes = await indexSqlByName(fresh, 'import_logs');
      await fresh.close();
      await freshFile.delete();

      expect(migratedIndexes.keys.toSet(), freshIndexes.keys.toSet());
      expect(migratedIndexes.keys, containsAll(importLogIndexes));
      for (final name in freshIndexes.keys) {
        expect(
          _normalize(migratedIndexes[name]!),
          _normalize(freshIndexes[name]!),
          reason: 'SQL index $name berbeda antara migrasi dan schema baru.',
        );
      }
    });

    test('tidak ada import log yang dibuat otomatis', () async {
      // The load-bearing absence of this milestone — see the file note.
      await createVersion12Database();
      final database = openDatabase();

      expect(await countOf(database, 'import_logs'), 0);

      await database.close();
    });

    test('tidak ada file sumber yang dibuat saat migrasi', () async {
      // `import_logs` points at retained bytes; a row pointing at a path that
      // was never written would fail its own hash check the first time anybody
      // looked. Zero rows means zero files, and the audit directory is only ever
      // created by a validation.
      await createVersion12Database();
      final database = openDatabase();
      expect(await countOf(database, 'import_logs'), 0);
      expect(
        Directory('${workDir.path}/aish_import_audit').existsSync(),
        isFalse,
      );
      await database.close();
    });

    test('data master tetap apa adanya', () async {
      // The strongest claim of this milestone's migration.
      await createVersion12Database();
      final database = openDatabase();

      final item = await database
          .customSelect(
            'SELECT sku, name, unit, min_stock_room, min_stock_branch, '
            'has_expiry, expiry_alert_days, is_active, sync_status '
            'FROM items WHERE id = ?;',
            variables: [Variable<String>(itemId)],
          )
          .getSingle();
      expect(item.read<String>('sku'), 'MIG-0013');
      expect(item.read<String>('unit'), 'ampul');
      expect(item.read<int>('min_stock_room'), 1);
      expect(item.read<int>('min_stock_branch'), 2);
      expect(item.read<int>('expiry_alert_days'), 30);
      expect(item.read<int>('is_active'), 1);

      final user = await database
          .customSelect(
            'SELECT email, role, is_active FROM users WHERE id = ?;',
            variables: [Variable<String>(userId)],
          )
          .getSingle();
      // Not lower-cased, not normalized, not touched.
      expect(user.read<String>('email'), 'wh13@test.local');
      expect(user.read<String>('role'), 'warehouse');

      final branch = await database
          .customSelect(
            'SELECT code, name, is_active FROM branches WHERE id = ?;',
            variables: [Variable<String>(branchId)],
          )
          .getSingle();
      expect(branch.read<String>('code'), 'CAB-13');
      expect(branch.read<int>('is_active'), 1);

      expect(await countOf(database, 'item_categories'), 1);
      expect(categoryId, isNotEmpty);

      await database.close();
    });

    test('kuantitas ledger tidak diskalakan ulang', () async {
      await createVersion12Database();
      final database = openDatabase();

      final balance = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-13';",
          )
          .getSingle();
      expect(
        balance.read<int>('qty_on_hand'),
        Quantity.parse('7.5').milliUnits,
      );

      final movement = await database
          .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-13';")
          .getSingle();
      expect(movement.read<int>('qty'), Quantity.parse('7.5').milliUnits);
      expect(warehouseLocationId, isNotEmpty);

      await database.close();
    });

    test('export log v12 tetap utuh', () async {
      await createVersion12Database();
      final database = openDatabase();

      expect(await countOf(database, 'export_logs'), 1);
      final row = await database
          .customSelect(
            "SELECT report_type, file_name, row_count, sync_status "
            "FROM export_logs WHERE id = 'exp-13';",
          )
          .getSingle();
      expect(row.read<String>('report_type'), 'stok_lokasi');
      expect(
        row.read<String>('file_name'),
        'stok_lokasi_warehouse_2026-W31.xlsx',
      );
      expect(row.read<int>('row_count'), 1);
      expect(row.read<String>('sync_status'), 'pending');

      await database.close();
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion12Database();
      final database = openDatabase();

      final violations = await database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);

      final pragma = await database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      await database.close();
    });

    test('CHECK import_logs ditegakkan setelah migrasi', () async {
      await createVersion12Database();
      final database = openDatabase();

      final validSha = 'a' * 64;

      Future<void> insert({
        String id = 'log-1',
        String entity = 'items',
        String status = 'validated',
        int total = 1,
        int inserted = 1,
        int updated = 0,
        int failed = 0,
        String? errorDetail,
        String? sha,
        int size = 10,
        String templateVersion = 'aish-master-v1',
        String fileName = 'file.xlsx',
        String storedPath = '/tmp/file.xlsx',
      }) => database.customStatement(
        'INSERT INTO import_logs (id, created_at, updated_at, sync_status, '
        'entity, file_name, total_rows, inserted_rows, updated_rows, '
        'failed_rows, error_detail, status, imported_by, stored_file_path, '
        'file_sha256, file_size_bytes, template_version) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-31T00:00:00.000Z',
          '2026-07-31T00:00:00.000Z',
          'pending',
          entity,
          fileName,
          total,
          inserted,
          updated,
          failed,
          errorDetail,
          status,
          userId,
          storedPath,
          sha ?? validSha,
          size,
          templateVersion,
        ],
      );

      // A well-formed row is accepted.
      await insert();
      expect(await countOf(database, 'import_logs'), 1);

      // An entity outside the six.
      await expectLater(
        insert(id: 'log-bad-entity', entity: 'suppliers'),
        throwsA(isA<Exception>()),
      );
      // A status outside the three.
      await expectLater(
        insert(id: 'log-bad-status', status: 'pending'),
        throwsA(isA<Exception>()),
      );
      // The counting invariant of §31.
      await expectLater(
        insert(id: 'log-bad-total', total: 5, inserted: 1),
        throwsA(isA<Exception>()),
      );
      // G-M3: a committed import cannot carry failures.
      await expectLater(
        insert(
          id: 'log-committed-with-failures',
          status: 'committed',
          total: 2,
          inserted: 1,
          failed: 1,
          errorDetail: '[]',
        ),
        throwsA(isA<Exception>()),
      );
      // A failure count with no explanation.
      await expectLater(
        insert(id: 'log-no-detail', total: 1, inserted: 0, failed: 1),
        throwsA(isA<Exception>()),
      );
      // A hash that is not 64 lowercase hex characters.
      await expectLater(
        insert(id: 'log-bad-hash', sha: 'A' * 64),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insert(id: 'log-short-hash', sha: 'a' * 10),
        throwsA(isA<Exception>()),
      );
      // A zero-byte file.
      await expectLater(
        insert(id: 'log-empty-file', size: 0),
        throwsA(isA<Exception>()),
      );
      // Blank text columns.
      await expectLater(
        insert(id: 'log-blank-name', fileName: '   '),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insert(id: 'log-blank-path', storedPath: '  '),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insert(id: 'log-blank-version', templateVersion: ' '),
        throwsA(isA<Exception>()),
      );
      // Negative counts.
      await expectLater(
        insert(id: 'log-negative', total: 0, inserted: -1, updated: 1),
        throwsA(isA<Exception>()),
      );

      expect(await countOf(database, 'import_logs'), 1);
      await database.close();
    });

    test('foreign key imported_by ditegakkan', () async {
      await createVersion12Database();
      final database = openDatabase();

      await expectLater(
        database.customStatement(
          'INSERT INTO import_logs (id, created_at, updated_at, sync_status, '
          'entity, file_name, total_rows, inserted_rows, updated_rows, '
          'failed_rows, status, imported_by, stored_file_path, file_sha256, '
          'file_size_bytes, template_version) '
          "VALUES ('log-fk', ?, ?, 'pending', 'items', 'f.xlsx', 0, 0, 0, 0, "
          "'validated', 'tidak-ada', '/tmp/f.xlsx', ?, 10, 'aish-master-v1');",
          ['2026-07-31T00:00:00.000Z', '2026-07-31T00:00:00.000Z', 'a' * 64],
        ),
        throwsA(isA<Exception>()),
      );

      await database.close();
    });

    test('membuka ulang database v13 tidak menjalankan migrasi lagi', () async {
      await createVersion12Database();

      final first = openDatabase();
      await first.customSelect('SELECT 1;').getSingle();
      await first.close();

      // Re-running the `from < 13` block would fail on `CREATE TABLE` for an
      // existing table; that it does not is what makes the step re-runnable.
      final second = openDatabase();
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 15);
      expect(await objectNames(second, 'table'), containsAll(importLogTables));
      expect(await countOf(second, 'import_logs'), 0);
      await second.close();
    });
  });

  group('rantai lengkap', () {
    /// Rewinds a fresh current-schema database to [target] by dropping every
    /// table introduced after it, then stamping `user_version`.
    Future<void> rewindTo(int target) async {
      final database = openDatabase();
      final master = DriftMasterDataRepository(database.masterDataDao);

      final warehouse = await master.ensureLocation(
        type: StockLocationType.warehouse,
        name: 'Warehouse Pusat',
      );
      final user = await master.ensureUser(
        email: 'chain13@test.local',
        fullName: 'Petugas',
        role: UserRole.warehouse,
      );
      final category = await master.ensureCategory('Obat');
      final item = await master.ensureItem(
        sku: 'CHAIN-13',
        name: 'Anestesi',
        categoryId: category.id,
        unit: 'ampul',
        minStockRoom: 1,
        minStockBranch: 1,
        hasExpiry: false,
      );

      // v1 quantities are whole units; every later version's are milli-units.
      // The `from < 2` block scales them exactly once, and the assertions below
      // are what prove it did not run twice.
      final qty = target == 1 ? 7 : Quantity.parse('7').milliUnits;
      await database.customStatement(
        'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
        "location_id, item_id, qty_on_hand) VALUES ('bal-c', ?, ?, 'pending', "
        '?, ?, ?);',
        [
          '2026-07-29T00:00:00.000Z',
          '2026-07-29T00:00:00.000Z',
          warehouse.id,
          item.id,
          qty,
        ],
      );
      await database.customStatement(
        'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
        'item_id, to_location_id, qty, movement_type, actor_user_id) '
        "VALUES ('mov-c', ?, ?, 'pending', ?, ?, ?, 'inbound_warehouse', ?);",
        [
          '2026-07-29T00:00:00.000Z',
          '2026-07-29T00:00:00.000Z',
          item.id,
          warehouse.id,
          qty,
          user.id,
        ],
      );

      await database.customStatement('PRAGMA foreign_keys = OFF;');
      for (final entry in _tablesByVersion.entries) {
        if (entry.key <= target) continue;
        for (final table in entry.value) {
          await database.customStatement('DROP TABLE IF EXISTS $table;');
        }
      }
      await database.customStatement('PRAGMA foreign_keys = ON;');
      await database.customStatement('PRAGMA user_version = $target;');
      await database.close();
    }

    /// v1 and v2 are the interesting ones: the `from < 2` block scales every
    /// ledger quantity by 1000, and it must run **exactly once** whichever
    /// version the device started from. A v13 that re-triggered it would
    /// multiply every balance in the clinic group by a thousand.
    for (final from in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]) {
      test('database v$from bermigrasi hingga v13', () async {
        await rewindTo(from);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 15);

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(importLogTables));
        expect(tables, containsAll(v12Tables));

        expect(
          await objectNames(database, 'index'),
          containsAll(importLogIndexes),
        );

        // Scaled exactly once, whichever version we started from.
        final balance = await database
            .customSelect(
              "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-c';",
            )
            .getSingle();
        expect(
          balance.read<int>('qty_on_hand'),
          Quantity.parse('7').milliUnits,
        );
        final movement = await database
            .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-c';")
            .getSingle();
        expect(movement.read<int>('qty'), Quantity.parse('7').milliUnits);

        // The v4 rebuild ran once and left no temporary table behind.
        expect(tables.where((name) => name.contains('_new')), isEmpty);

        // No import log invented on any path.
        expect(await countOf(database, 'import_logs'), 0);

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        await database.close();
      });
    }
  });
}

/// Tables by the schema version that introduced them, for the rewind helper.
const Map<int, List<String>> _tablesByVersion = {
  3: ['stock_opnames', 'stock_opname_lines'],
  5: [
    'purchase_requests',
    'purchase_request_opnames',
    'purchase_request_lines',
  ],
  6: ['delivery_orders', 'delivery_order_lines'],
  7: ['good_receipts', 'good_receipt_lines'],
  8: ['distributions', 'distribution_lines'],
  9: ['disposals', 'disposal_lines'],
  10: ['consumptions', 'consumption_lines'],
  11: ['goods_returns', 'goods_return_lines'],
  12: ['export_logs'],
  13: ['import_logs'],
};

/// Whitespace-insensitive SQL comparison, so formatting is not the assertion.
String _normalize(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ').trim();
