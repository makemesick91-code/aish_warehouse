import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v4 → v5: the three Purchase Request tables are added.
///
/// The step is **purely additive**, and almost everything here is about proving
/// exactly that: not one existing column, row, index or constraint may move. That
/// matters most for the two things earlier migrations touched — the milli-unit
/// scaling the `from < 2` block applied, and the `stock_opnames` rebuild the
/// `from < 4` block performed. A v5 that re-scaled quantities would double every
/// balance in the clinic group, and a v5 that changed `stock_opnames` would make a
/// v3 → v5 upgrade apply the v4 rebuild to the v5 shape and then apply v5 on top.
///
/// A v4 database is reproduced by creating the current schema, dropping the three
/// Purchase Request tables and their indexes, and stamping `user_version` back to 4.
/// Because v5 adds nothing else, what remains *is* a v4 database — and the last test
/// in this file pins that assumption by comparing the surviving object list against
/// the v4 inventory.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v4_to_v5.sqlite');
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
  late String itemId;
  late String warehouseLocationId;

  /// Every object schema v4 had. Anything added to this list by v5 that is not a
  /// Purchase Request object is a migration that is not additive.
  const v4Tables = <String>[
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
  ];

  const purchaseRequestTables = <String>[
    'purchase_requests',
    'purchase_request_opnames',
    'purchase_request_lines',
  ];

  const purchaseRequestIndexes = <String>[
    'idx_purchase_requests_branch_status',
    'idx_purchase_requests_requested_by_status',
    'idx_purchase_requests_created_at',
    'idx_purchase_requests_needed_date',
    'idx_purchase_requests_active_branch',
    'idx_purchase_requests_doc_number',
    'idx_purchase_request_opnames_pr',
    'idx_purchase_request_opnames_opname',
    'idx_purchase_request_opnames_unique',
    'idx_purchase_request_lines_pr',
    'idx_purchase_request_lines_item',
    'idx_purchase_request_lines_item_unique',
  ];

  /// Writes a v4 database holding master data, ledger rows with milli-unit
  /// quantities, and an opname in each status.
  Future<void> createVersion4Database() async {
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
    // produced. If v5 touched them, `10.5 box` would come back as `10500 box`.
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

    // One opname in each status, with lines, so the rebuilt-in-v4 table can be
    // checked for having survived v5 untouched.
    Future<void> insertOpname({
      required String id,
      required int week,
      required String status,
      String? submittedAt,
      String? reviewedAt,
      String? reviewedBy,
    }) => database.customStatement(
      'INSERT INTO stock_opnames (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, room_id, period_year, period_week, counted_by, '
      'status, submitted_at, reviewed_at, reviewed_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
        'pending',
        'TMP-SO-$id',
        branchId,
        roomId,
        2026,
        week,
        nurseId,
        status,
        submittedAt,
        reviewedAt,
        reviewedBy,
      ],
    );

    await insertOpname(id: 'so-draft', week: 29, status: 'draft');
    await insertOpname(
      id: 'so-submitted',
      week: 30,
      status: 'submitted',
      submittedAt: '2026-07-24T02:00:00.000Z',
    );
    await insertOpname(
      id: 'so-reviewed',
      week: 31,
      status: 'reviewed',
      submittedAt: '2026-07-29T02:00:00.000Z',
      reviewedAt: '2026-07-29T08:00:00.000Z',
      reviewedBy: headId,
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
        'Catatan v4',
      ],
    );

    // Drop the Purchase Request objects, leaving exactly a v4 database. Indexes go
    // with their tables in SQLite, so only the tables have to be named.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    for (final table in purchaseRequestTables) {
      await database.customStatement('DROP TABLE IF EXISTS $table;');
    }
    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 4;');
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

  group('v4 → v5', () {
    test('database v4 dibuka pada versi 5', () async {
      await createVersion4Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 5);

      await database.close();
    });

    test('tiga tabel Purchase Request ditambahkan', () async {
      await createVersion4Database();
      final database = openDatabase();

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(purchaseRequestTables));
      // And nothing else appeared: v5 adds three tables, no more.
      expect(tables, {...v4Tables, ...purchaseRequestTables});

      await database.close();
    });

    test('seluruh index Purchase Request ditambahkan', () async {
      await createVersion4Database();
      final database = openDatabase();

      final indexes = await objectNames(database, 'index');
      expect(indexes, containsAll(purchaseRequestIndexes));

      await database.close();
    });

    test('index unik parsial dibuat dengan klausa WHERE yang benar', () async {
      await createVersion4Database();
      final database = openDatabase();

      Future<String> sqlOf(String name) async {
        final row = await database
            .customSelect("SELECT sql FROM sqlite_master WHERE name = '$name';")
            .getSingle();
        return row.read<String>('sql');
      }

      // The two load-bearing ones. An upgrade that created them without the WHERE
      // clause would leave the use cases as the only guard behind G-P4 and G-P2 —
      // exactly what a concurrent submit defeats.
      expect(
        await sqlOf('idx_purchase_requests_active_branch'),
        allOf(
          contains('UNIQUE'),
          contains("status IN ('submitted', 'processing')"),
          contains('deleted_at IS NULL'),
        ),
      );
      expect(
        await sqlOf('idx_purchase_request_lines_item_unique'),
        allOf(contains('UNIQUE'), contains('deleted_at IS NULL')),
      );

      await database.close();
    });

    test('SQL index hasil migrasi identik dengan database v5 baru', () async {
      // The `from < 5` block creates the indexes from a **frozen literal list**,
      // because deriving them from `allSchemaEntities` would make a future v6 index
      // silently change what this step does. The cost of freezing them is that the
      // list can drift away from the `@TableIndex` declarations, and nothing in the
      // Dart compiler would notice. This test is the thing that notices: it compares
      // the SQL a migrated database ends up with against the SQL a fresh one gets
      // from `createAll`.
      await createVersion4Database();
      final migrated = openDatabase();
      final migratedSql = await indexSqlByName(migrated, 'purchase_request');
      await migrated.close();

      final freshFile = File('${workDir.path}/fresh_v5.sqlite');
      if (freshFile.existsSync()) await freshFile.delete();
      final fresh = AppDatabase(NativeDatabase(freshFile));
      final freshSql = await indexSqlByName(fresh, 'purchase_request');
      await fresh.close();
      await freshFile.delete();

      expect(migratedSql.keys, freshSql.keys);
      for (final name in freshSql.keys) {
        expect(
          _normalizeSql(migratedSql[name]!),
          _normalizeSql(freshSql[name]!),
          reason:
              '$name berbeda antara database yang bermigrasi dan database '
              'baru. Perbarui _v5PurchaseRequestIndexes agar cocok dengan '
              'deklarasi @TableIndex.',
        );
      }
    });

    test('index inventory dan opname lama tidak hilang', () async {
      await createVersion4Database();
      final database = openDatabase();

      final indexes = await objectNames(database, 'index');
      expect(
        indexes,
        containsAll(<String>[
          'idx_stock_opnames_branch_status',
          'idx_stock_opnames_room_period',
          'idx_stock_opnames_counted_by_status',
          'idx_stock_opnames_doc_number',
          'idx_stock_opname_lines_opname',
          'idx_stock_opname_lines_item',
          'idx_stock_opname_lines_batched',
          'idx_stock_opname_lines_unbatched',
        ]),
      );

      await database.close();
    });

    test('kuantitas ledger tidak diskalakan ulang', () async {
      await createVersion4Database();
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

    test('dokumen opname dan barisnya utuh', () async {
      await createVersion4Database();
      final database = openDatabase();

      final rows = await database
          .customSelect('SELECT * FROM stock_opnames ORDER BY period_week;')
          .get();
      expect(rows.map((row) => row.read<String>('id')), [
        'so-draft',
        'so-submitted',
        'so-reviewed',
      ]);
      expect(rows.last.read<String>('status'), 'reviewed');
      expect(rows.last.read<String>('reviewed_by'), headId);

      final line = await database
          .customSelect("SELECT * FROM stock_opname_lines WHERE id = 'sol-1';")
          .getSingle();
      expect(line.read<int>('system_qty'), 10500);
      expect(line.read<int>('counted_qty'), 9500);
      // The generated column still computes, so the v4 table was not rebuilt.
      expect(line.read<int>('difference'), -1000);
      expect(line.read<String>('note'), 'Catatan v4');

      await database.close();
    });

    test(
      'CHECK opname hasil hardening v4 tetap tanpa perbandingan leksikal',
      () async {
        await createVersion4Database();
        final database = openDatabase();

        final row = await database
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'stock_opnames';",
            )
            .getSingle();
        final sql = row.read<String>('sql');

        expect(sql, isNot(contains('reviewed_at >= submitted_at')));
        expect(sql, contains("status IN ('draft', 'submitted', 'reviewed')"));
        expect(
          sql,
          contains('reviewed_by IS NULL OR reviewed_by <> counted_by'),
        );

        await database.close();
      },
    );

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion4Database();
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

    test('active PR index menegakkan G-P4 setelah migrasi', () async {
      await createVersion4Database();
      final database = openDatabase();

      Future<void> insertSubmitted(String id) => database.customStatement(
        'INSERT INTO purchase_requests (id, created_at, updated_at, '
        'sync_status, doc_number, branch_id, requested_by, status, '
        'submitted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-29T03:00:00.000Z',
          '2026-07-29T03:00:00.000Z',
          'pending',
          'TMP-PR-$id',
          branchId,
          headId,
          'submitted',
          '2026-07-29T04:00:00.000Z',
        ],
      );

      await insertSubmitted('pr-1');
      expect(
        () => insertSubmitted('pr-2'),
        throwsA(anything),
        reason:
            'Index parsial harus menolak PR submitted kedua pada cabang yang '
            'sama.',
      );

      await database.close();
    });

    test('membuka ulang database v5 tidak menjalankan migrasi lagi', () async {
      await createVersion4Database();

      final first = openDatabase();
      await first.customSelect('SELECT 1;').getSingle();
      await first.close();

      // Re-running the `from < 5` block would fail on `CREATE TABLE` for an existing
      // table; that it does not is what makes the step re-runnable.
      final second = openDatabase();
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 5);

      final tables = await objectNames(second, 'table');
      expect(tables, containsAll(purchaseRequestTables));
      await second.close();
    });
  });

  group('rantai lengkap', () {
    /// Rewinds a freshly created database to [version] by removing everything the
    /// migrations after it added, so the real [MigrationStrategy] runs on reopen.
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
      for (final table in purchaseRequestTables) {
        await database.customStatement('DROP TABLE IF EXISTS $table;');
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

    test('database v1 bermigrasi hingga v5 dengan skala tepat sekali', () async {
      await rewindTo(1);
      final database = openDatabase();

      final version = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 5);

      // `10` whole units became `10000` milli-units — scaled once, not twice. A
      // second application of the `from < 2` block would leave `10000000`.
      final balance = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
          )
          .getSingle();
      expect(balance.read<int>('qty_on_hand'), 10 * Quantity.scale);

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(purchaseRequestTables));
      expect(
        tables,
        containsAll(<String>['stock_opnames', 'stock_opname_lines']),
      );

      final violations = await database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);

      await database.close();
    });

    test('database v2 bermigrasi hingga v5 tanpa skala ulang', () async {
      await rewindTo(2);
      final database = openDatabase();

      final balance = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
          )
          .getSingle();
      expect(balance.read<int>('qty_on_hand'), 10500);

      final tables = await objectNames(database, 'table');
      expect(tables, containsAll(purchaseRequestTables));

      await database.close();
    });

    test(
      'database v3 bermigrasi hingga v5 dengan hardening v4 diterapkan',
      () async {
        await rewindTo(3);
        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 5);

        // v4's rebuild must still have happened on the way through.
        final row = await database
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'stock_opnames';",
            )
            .getSingle();
        expect(
          row.read<String>('sql'),
          isNot(contains('reviewed_at >= submitted_at')),
        );

        final tables = await objectNames(database, 'table');
        expect(tables, containsAll(purchaseRequestTables));

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        await database.close();
      },
    );
  });
}

/// Collapses whitespace so `IF NOT EXISTS` and line breaks do not make two equivalent
/// statements look different.
String _normalizeSql(String sql) => sql
    .replaceAll('IF NOT EXISTS ', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();
