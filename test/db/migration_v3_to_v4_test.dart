import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v3 → v4: `stock_opnames` is rebuilt without the lexical
/// timestamp-order CHECK.
///
/// SQLite cannot drop a table CHECK in place, so this is a full table rebuild —
/// the one migration in this project that touches existing rows of an existing
/// table. Everything below is therefore about what must survive it: every
/// document in every status, the lines that hang off them, the foreign keys,
/// all four indexes including the two *partial* ones whose `WHERE` clauses are
/// what enforce G-O1, and quantities that must not be rescaled by a migration
/// that has nothing to do with quantities.
///
/// A v3 database is reproduced faithfully: the current schema is created, the
/// v3 CHECK is put back by rebuilding the table by hand, data is written, and
/// `user_version` is stamped to 3. Drift then runs the real
/// [MigrationStrategy] on reopen.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v3_to_v4.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  late String branchId;
  late String roomId;
  late String secondRoomId;
  late String thirdRoomId;
  late String nurseId;
  late String headId;
  late String itemId;
  late String warehouseId;

  /// The exact `stock_opnames` DDL of schema v3 — CHECK constraints in the
  /// order drift emitted them, lexical timestamp comparison included.
  const v3StockOpnamesDdl = '''
CREATE TABLE "stock_opnames" (
  "id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL,
  "updated_at" TEXT NOT NULL,
  "deleted_at" TEXT NULL,
  "sync_status" TEXT NOT NULL,
  "doc_number" TEXT NOT NULL,
  "branch_id" TEXT NOT NULL REFERENCES branches (id),
  "room_id" TEXT NOT NULL REFERENCES rooms (id),
  "period_year" INTEGER NOT NULL,
  "period_week" INTEGER NOT NULL,
  "counted_by" TEXT NOT NULL REFERENCES users (id),
  "status" TEXT NOT NULL,
  "submitted_at" TEXT NULL,
  "reviewed_at" TEXT NULL,
  "reviewed_by" TEXT NULL REFERENCES users (id),
  PRIMARY KEY ("id"),
  CHECK (period_week BETWEEN 1 AND 53),
  CHECK (period_year BETWEEN 2000 AND 2999),
  CHECK (status IN ('draft', 'submitted', 'reviewed')),
  CHECK ((status = 'draft' AND submitted_at IS NULL AND reviewed_at IS NULL AND reviewed_by IS NULL) OR (status = 'submitted' AND submitted_at IS NOT NULL AND reviewed_at IS NULL AND reviewed_by IS NULL) OR (status = 'reviewed' AND submitted_at IS NOT NULL AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL)),
  CHECK (reviewed_by IS NULL OR reviewed_by <> counted_by),
  CHECK (reviewed_at IS NULL OR submitted_at IS NULL OR reviewed_at >= submitted_at)
)''';

  const v3Indexes = [
    'CREATE INDEX idx_stock_opnames_branch_status '
        'ON stock_opnames (branch_id, status);',
    'CREATE UNIQUE INDEX idx_stock_opnames_room_period '
        'ON stock_opnames (room_id, period_year, period_week) '
        'WHERE deleted_at IS NULL;',
    'CREATE INDEX idx_stock_opnames_counted_by_status '
        'ON stock_opnames (counted_by, status);',
    'CREATE UNIQUE INDEX idx_stock_opnames_doc_number '
        'ON stock_opnames (doc_number) WHERE deleted_at IS NULL;',
  ];

  /// Writes a v3 database holding one draft, one submitted and one reviewed
  /// document, each with lines, plus ledger rows that must not move.
  Future<void> createVersion3Database() async {
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
    thirdRoomId = (await master.ensureRoom(
      branchId: branch.id,
      code: 'R3',
      name: 'Ruang Dental 3',
    )).id;

    warehouseId = (await master.ensureLocation(
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
      minStockRoom: 1,
      minStockBranch: 5,
      hasExpiry: false,
    )).id;

    const stamp = "'2026-01-01T00:00:00.000Z'";
    await database.customStatement(
      'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
      'location_id, item_id, qty_on_hand) '
      "VALUES ('bal-1', $stamp, $stamp, 'synced', '$warehouseId', "
      "'$itemId', 10500);",
    );
    await database.customStatement(
      'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
      'item_id, to_location_id, qty, movement_type, ref_doc_type, ref_doc_id, '
      'actor_user_id) '
      "VALUES ('mov-1', $stamp, $stamp, 'synced', '$itemId', "
      "'$warehouseId', 2375, 'inbound_warehouse', 'SEED', 'seed-1', "
      "'$nurseId');",
    );

    // Roll `stock_opnames` back to its v3 shape: the current schema no longer
    // has the lexical CHECK, and the migration has to be shown removing it.
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    await database.customStatement('DROP TABLE stock_opnames;');
    await database.customStatement(v3StockOpnamesDdl);
    for (final statement in v3Indexes) {
      await database.customStatement(statement);
    }

    Future<void> insertOpname({
      required String id,
      required String docNumber,
      required String targetRoomId,
      required int week,
      required String status,
      String? submittedAt,
      String? reviewedAt,
      String? reviewedBy,
      String? deletedAt,
    }) {
      String literal(String? value) => value == null ? 'NULL' : "'$value'";
      return database.customStatement(
        'INSERT INTO stock_opnames (id, created_at, updated_at, deleted_at, '
        'sync_status, doc_number, branch_id, room_id, period_year, '
        'period_week, counted_by, status, submitted_at, reviewed_at, '
        'reviewed_by) '
        "VALUES ('$id', $stamp, $stamp, ${literal(deletedAt)}, 'pending', "
        "'$docNumber', '$branchId', '$targetRoomId', 2026, $week, "
        "'$nurseId', '$status', ${literal(submittedAt)}, "
        '${literal(reviewedAt)}, ${literal(reviewedBy)});',
      );
    }

    Future<void> insertLine(String id, String opnameId, int counted) {
      return database.customStatement(
        'INSERT INTO stock_opname_lines (id, created_at, updated_at, '
        'sync_status, opname_id, item_id, system_qty, counted_qty, note) '
        "VALUES ('$id', $stamp, $stamp, 'pending', '$opnameId', '$itemId', "
        "10500, $counted, 'Catatan v3');",
      );
    }

    await insertOpname(
      id: 'so-draft',
      docNumber: 'TMP-SO-DRAFT',
      targetRoomId: roomId,
      week: 31,
      status: 'draft',
    );
    await insertOpname(
      id: 'so-submitted',
      docNumber: 'TMP-SO-SUBMITTED',
      targetRoomId: secondRoomId,
      week: 31,
      status: 'submitted',
      submittedAt: '2026-07-29T06:00:00.000Z',
    );
    await insertOpname(
      id: 'so-reviewed',
      docNumber: 'TMP-SO-REVIEWED',
      targetRoomId: thirdRoomId,
      week: 31,
      status: 'reviewed',
      submittedAt: '2026-07-29T06:00:00.000Z',
      reviewedAt: '2026-07-29T08:00:00.000Z',
      reviewedBy: headId,
    );
    // A soft-deleted draft, so the *partial* unique indexes have something to
    // prove: it must not block its room from being counted again.
    await insertOpname(
      id: 'so-deleted',
      docNumber: 'TMP-SO-DELETED',
      targetRoomId: roomId,
      week: 30,
      status: 'draft',
      deletedAt: '2026-07-20T00:00:00.000Z',
    );

    await insertLine('sol-draft', 'so-draft', 8000);
    await insertLine('sol-submitted', 'so-submitted', 9500);
    await insertLine('sol-reviewed', 'so-reviewed', 10500);

    await database.customStatement('PRAGMA foreign_keys = ON;');
    await database.customStatement('PRAGMA user_version = 3;');
    await database.close();
  }

  Future<String> stockOpnamesSql(AppDatabase database) async {
    final row = await database
        .customSelect(
          "SELECT sql FROM sqlite_master "
          "WHERE type = 'table' AND name = 'stock_opnames';",
        )
        .getSingle();
    return row.read<String>('sql').replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<Set<String>> indexNames(AppDatabase database) async {
    final rows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index';")
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  group('v3 → v4', () {
    test('menaikkan versi schema menjadi 4', () async {
      await createVersion3Database();
      final database = openDatabase();

      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 15);

      await database.close();
    });

    test('CHECK perbandingan leksikal timestamp dihapus', () async {
      // The constraint really is in the v3 shape this test starts from —
      // asserted against the DDL constant, because merely opening the file
      // runs the migration that removes it.
      expect(v3StockOpnamesDdl, contains('reviewed_at >= submitted_at'));

      await createVersion3Database();
      final database = openDatabase();

      final sql = await stockOpnamesSql(database);
      expect(sql, isNot(contains('reviewed_at >= submitted_at')));
      expect(sql, isNot(contains('reviewed_at > submitted_at')));
      expect(sql, isNot(contains('submitted_at <= reviewed_at')));
      expect(sql, isNot(contains('submitted_at < reviewed_at')));

      await database.close();
    });

    test('CHECK status dan null dipertahankan', () async {
      await createVersion3Database();
      final database = openDatabase();

      final sql = await stockOpnamesSql(database);
      expect(sql, contains("status IN ('draft', 'submitted', 'reviewed')"));
      expect(sql, contains('reviewed_by IS NULL OR reviewed_by <> counted_by'));
      expect(sql, contains('period_week BETWEEN 1 AND 53'));
      expect(sql, contains('period_year BETWEEN 2000 AND 2999'));
      expect(
        sql,
        contains(
          "status = 'reviewed' AND submitted_at IS NOT NULL "
          'AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL',
        ),
      );

      await database.close();
    });

    test('setiap dokumen dan seluruh kolomnya utuh', () async {
      await createVersion3Database();
      final database = openDatabase();

      final rows = await database
          .customSelect(
            'SELECT id, doc_number, branch_id, room_id, period_year, '
            'period_week, counted_by, status, submitted_at, reviewed_at, '
            'reviewed_by, sync_status, deleted_at, created_at '
            'FROM stock_opnames ORDER BY id;',
          )
          .get();
      final byId = {for (final row in rows) row.read<String>('id'): row};

      expect(byId.keys, {
        'so-deleted',
        'so-draft',
        'so-reviewed',
        'so-submitted',
      });

      final draft = byId['so-draft']!;
      expect(draft.read<String>('doc_number'), 'TMP-SO-DRAFT');
      expect(draft.read<String>('branch_id'), branchId);
      expect(draft.read<String>('room_id'), roomId);
      expect(draft.read<int>('period_year'), 2026);
      expect(draft.read<int>('period_week'), 31);
      expect(draft.read<String>('counted_by'), nurseId);
      expect(draft.read<String>('status'), 'draft');
      expect(draft.read<String?>('submitted_at'), isNull);
      expect(draft.read<String>('sync_status'), 'pending');
      expect(draft.read<String>('created_at'), startsWith('2026-01-01'));

      final submitted = byId['so-submitted']!;
      expect(submitted.read<String>('status'), 'submitted');
      expect(
        submitted.read<String>('submitted_at'),
        '2026-07-29T06:00:00.000Z',
      );
      expect(submitted.read<String?>('reviewed_at'), isNull);

      final reviewed = byId['so-reviewed']!;
      expect(reviewed.read<String>('status'), 'reviewed');
      expect(reviewed.read<String>('reviewed_at'), '2026-07-29T08:00:00.000Z');
      expect(reviewed.read<String>('reviewed_by'), headId);

      // Soft deletion survives too, or the weekly key would change meaning.
      expect(
        byId['so-deleted']!.read<String>('deleted_at'),
        '2026-07-20T00:00:00.000Z',
      );

      await database.close();
    });

    test('baris tetap terhubung ke headernya', () async {
      await createVersion3Database();
      final database = openDatabase();

      final rows = await database
          .customSelect(
            'SELECT l.id, l.opname_id, l.system_qty, l.counted_qty, '
            'l.difference, l.note, o.doc_number '
            'FROM stock_opname_lines l '
            'JOIN stock_opnames o ON o.id = l.opname_id ORDER BY l.id;',
          )
          .get();

      expect(rows, hasLength(3));
      final byId = {for (final row in rows) row.read<String>('id'): row};

      expect(byId['sol-submitted']!.read<String>('opname_id'), 'so-submitted');
      expect(
        byId['sol-submitted']!.read<String>('doc_number'),
        'TMP-SO-SUBMITTED',
      );
      // Quantities are untouched, and the generated column still recomputes.
      expect(byId['sol-submitted']!.read<int>('system_qty'), 10500);
      expect(byId['sol-submitted']!.read<int>('counted_qty'), 9500);
      expect(byId['sol-submitted']!.read<int>('difference'), -1000);
      expect(byId['sol-submitted']!.read<String>('note'), 'Catatan v3');
      expect(byId['sol-reviewed']!.read<int>('difference'), 0);

      await database.close();
    });

    test('kolom generated difference masih dihitung database', () async {
      await createVersion3Database();
      final database = openDatabase();

      await database.customStatement(
        "UPDATE stock_opname_lines SET counted_qty = 12500 "
        "WHERE id = 'sol-draft';",
      );
      final row = await database
          .customSelect(
            "SELECT difference FROM stock_opname_lines WHERE id = 'sol-draft';",
          )
          .getSingle();
      expect(row.read<int>('difference'), 2000);

      await database.close();
    });

    test('seluruh index termasuk partial unique index kembali', () async {
      await createVersion3Database();
      final database = openDatabase();

      final indexes = await indexNames(database);
      expect(indexes, contains('idx_stock_opnames_branch_status'));
      expect(indexes, contains('idx_stock_opnames_room_period'));
      expect(indexes, contains('idx_stock_opnames_counted_by_status'));
      expect(indexes, contains('idx_stock_opnames_doc_number'));
      expect(indexes, contains('idx_stock_opname_lines_opname'));
      expect(indexes, contains('idx_stock_opname_lines_item'));
      expect(indexes, contains('idx_stock_opname_lines_batched'));
      expect(indexes, contains('idx_stock_opname_lines_unbatched'));

      // The `WHERE deleted_at IS NULL` clauses have to survive verbatim; a
      // rebuild that dropped them would turn G-O1 into a rule that a
      // soft-deleted draft can block forever.
      final sql = await database
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_stock_opnames_room_period';",
          )
          .getSingle();
      expect(sql.read<String>('sql'), contains('WHERE deleted_at IS NULL'));

      await database.close();
    });

    test('kunci unik mingguan masih bekerja setelah rebuild', () async {
      await createVersion3Database();
      final database = openDatabase();

      const stamp = "'2026-01-01T00:00:00.000Z'";
      // Same room, same ISO week as `so-draft` — G-O1 must still refuse it.
      await expectLater(
        database.customStatement(
          'INSERT INTO stock_opnames (id, created_at, updated_at, '
          'sync_status, doc_number, branch_id, room_id, period_year, '
          'period_week, counted_by, status) '
          "VALUES ('so-dupe', $stamp, $stamp, 'pending', 'TMP-SO-DUPE', "
          "'$branchId', '$roomId', 2026, 31, '$nurseId', 'draft');",
        ),
        throwsA(isA<Exception>()),
      );

      // …but the week the soft-deleted draft occupies is free again.
      await database.customStatement(
        'INSERT INTO stock_opnames (id, created_at, updated_at, '
        'sync_status, doc_number, branch_id, room_id, period_year, '
        'period_week, counted_by, status) '
        "VALUES ('so-week30', $stamp, $stamp, 'pending', 'TMP-SO-W30', "
        "'$branchId', '$roomId', 2026, 30, '$nurseId', 'draft');",
      );

      await database.close();
    });

    test('nomor dokumen tetap unik untuk dokumen hidup', () async {
      await createVersion3Database();
      final database = openDatabase();

      const stamp = "'2026-01-01T00:00:00.000Z'";
      await expectLater(
        database.customStatement(
          'INSERT INTO stock_opnames (id, created_at, updated_at, '
          'sync_status, doc_number, branch_id, room_id, period_year, '
          'period_week, counted_by, status) '
          "VALUES ('so-dupe-doc', $stamp, $stamp, 'pending', "
          "'TMP-SO-DRAFT', '$branchId', '$roomId', 2026, 29, "
          "'$nurseId', 'draft');",
        ),
        throwsA(isA<Exception>()),
      );

      await database.close();
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await createVersion3Database();
      final database = openDatabase();

      final pragma = await database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      final violations = await database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);

      // And the rebuilt table's own foreign keys are still declared.
      final keys = await database
          .customSelect('PRAGMA foreign_key_list(stock_opnames);')
          .get();
      expect(keys.map((row) => row.read<String>('table')).toSet(), {
        'branches',
        'rooms',
        'users',
      });

      await database.close();
    });

    test('foreign key baris opname tetap menunjuk header', () async {
      await createVersion3Database();
      final database = openDatabase();

      // The rebuild dropped and re-created the parent table. If the child's
      // reference had been left pointing at the temporary name, this insert
      // would succeed instead of being refused.
      const stamp = "'2026-01-01T00:00:00.000Z'";
      await expectLater(
        database.customStatement(
          'INSERT INTO stock_opname_lines (id, created_at, updated_at, '
          'sync_status, opname_id, item_id, system_qty, counted_qty) '
          "VALUES ('sol-orphan', $stamp, $stamp, 'pending', "
          "'opname-tidak-ada', '$itemId', 1000, 1000);",
        ),
        throwsA(isA<Exception>()),
      );

      final keys = await database
          .customSelect('PRAGMA foreign_key_list(stock_opname_lines);')
          .get();
      expect(
        keys.map((row) => row.read<String>('table')),
        contains('stock_opnames'),
      );

      await database.close();
    });

    test('ledger dan saldo tidak tersentuh', () async {
      await createVersion3Database();
      final database = openDatabase();

      final balance = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
          )
          .getSingle();
      expect(balance.read<int>('qty_on_hand'), 10500);

      final movement = await database
          .customSelect(
            'SELECT qty, ref_doc_id, sync_status FROM stock_movements '
            "WHERE id = 'mov-1';",
          )
          .getSingle();
      expect(movement.read<int>('qty'), 2375);
      expect(movement.read<String>('ref_doc_id'), 'seed-1');
      expect(movement.read<String>('sync_status'), 'synced');

      await database.close();
    });

    test('membuka ulang database v4 tidak menjalankan migrasi lagi', () async {
      await createVersion3Database();

      final first = openDatabase();
      expect(await stockOpnamesSql(first), isNot(contains('reviewed_at >=')));
      await first.close();

      final second = openDatabase();
      final rows = await second
          .customSelect('SELECT COUNT(*) AS c FROM stock_opnames;')
          .getSingle();
      // A second rebuild would still leave four rows, so the assertion that
      // matters is that nothing was duplicated or lost either way.
      expect(rows.read<int>('c'), 4);
      final version = await second
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 15);
      await second.close();
    });

    test('tabel sementara rebuild tidak tertinggal', () async {
      await createVersion3Database();
      final database = openDatabase();

      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%';",
          )
          .get();
      final names = tables.map((row) => row.read<String>('name')).toSet();

      expect(names, {
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
        'consumptions',
        'consumption_lines',
        'goods_returns',
        'goods_return_lines',
        'export_logs',
        'import_logs',
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
        'disposals',
        'disposal_lines',
      });

      await database.close();
    });
  });

  group('rantai lengkap', () {
    test(
      'database v1 bermigrasi hingga v4 dengan skala tepat sekali',
      () async {
        await createVersion3Database();

        // Rewind the same file to v1: whole-unit quantities, no opname tables.
        final prepare = openDatabase();
        await prepare.customStatement('PRAGMA foreign_keys = OFF;');
        await prepare.customStatement('DROP TABLE stock_opname_lines;');
        await prepare.customStatement('DROP TABLE stock_opnames;');
        await prepare.customStatement(
          "UPDATE stock_balances SET qty_on_hand = 10 WHERE id = 'bal-1';",
        );
        await prepare.customStatement(
          "UPDATE stock_movements SET qty = 2 WHERE id = 'mov-1';",
        );
        await prepare.customStatement('PRAGMA user_version = 1;');
        await prepare.close();

        final database = openDatabase();

        final version = await database
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(version.read<int>('user_version'), 15);

        // v1 → v2 scaling ran exactly once…
        final balance = await database
            .customSelect(
              "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
            )
            .getSingle();
        expect(balance.read<int>('qty_on_hand'), 10000);
        expect(
          Quantity.fromMilliUnits(balance.read<int>('qty_on_hand')).format(),
          '10',
        );
        final movement = await database
            .customSelect(
              'SELECT qty, ref_doc_id FROM stock_movements '
              "WHERE id = 'mov-1';",
            )
            .getSingle();
        expect(movement.read<int>('qty'), 2000);
        // The reversal reference chain is part of the ledger and must survive.
        expect(movement.read<String>('ref_doc_id'), 'seed-1');

        // …v3 added the opname tables…
        final tables = await database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table';",
            )
            .get();
        final names = tables.map((row) => row.read<String>('name')).toSet();
        expect(names, contains('stock_opnames'));
        expect(names, contains('stock_opname_lines'));

        // …and v4 was applied on top of what v3 had just created.
        expect(
          await stockOpnamesSql(database),
          isNot(contains('reviewed_at >= submitted_at')),
        );
        expect(
          await indexNames(database),
          contains('idx_stock_opnames_doc_number'),
        );

        final violations = await database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations, isEmpty);

        await database.close();
      },
    );

    test('database v2 bermigrasi hingga v4 tanpa skala ulang', () async {
      await createVersion3Database();

      final prepare = openDatabase();
      await prepare.customStatement('PRAGMA foreign_keys = OFF;');
      await prepare.customStatement('DROP TABLE stock_opname_lines;');
      await prepare.customStatement('DROP TABLE stock_opnames;');
      await prepare.customStatement('PRAGMA user_version = 2;');
      await prepare.close();

      final database = openDatabase();

      final version = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(version.read<int>('user_version'), 15);

      // Already milli-units at v2: 10500 becoming 10500000 is exactly the bug
      // the `from < 2` guard prevents.
      final balance = await database
          .customSelect(
            "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
          )
          .getSingle();
      expect(balance.read<int>('qty_on_hand'), 10500);

      expect(
        await stockOpnamesSql(database),
        isNot(contains('reviewed_at >= submitted_at')),
      );

      final violations = await database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);

      await database.close();
    });
  });
}
