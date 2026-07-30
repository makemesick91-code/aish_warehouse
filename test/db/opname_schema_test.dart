import 'dart:io';

import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Schema-level guarantees of Stok Opname on a **fresh** v3 database.
///
/// These assertions deliberately go through raw SQL rather than the
/// repository: they are about what the database refuses on its own, with every
/// Dart guard bypassed.
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildOpnameFixture(context);
  });

  tearDown(() => context.dispose());

  const stamp = "'2026-07-29T00:00:00.000Z'";

  Future<void> insertOpname({
    String id = 'so-1',
    String docNumber = 'TMP-SO-1',
    int year = 2026,
    int week = 31,
    String status = 'draft',
    String? roomId,
    String? countedBy,
    String? submittedAt,
    String? reviewedAt,
    String? reviewedBy,
  }) {
    String literal(String? value) => value == null ? 'NULL' : "'$value'";

    return context.database.customStatement(
      'INSERT INTO stock_opnames (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, room_id, period_year, period_week, counted_by, '
      'status, submitted_at, reviewed_at, reviewed_by) '
      "VALUES ('$id', $stamp, $stamp, 'pending', '$docNumber', "
      "'${fixture.branch.id}', '${roomId ?? fixture.room.id}', $year, $week, "
      "'${countedBy ?? fixture.nurse.id}', '$status', ${literal(submittedAt)}, "
      '${literal(reviewedAt)}, ${literal(reviewedBy)});',
    );
  }

  Future<void> insertLine({
    String id = 'sol-1',
    String opnameId = 'so-1',
    String? itemId,
    String? batchId,
    int systemQty = 1000,
    int countedQty = 1000,
    String? note,
  }) {
    return context.database.customStatement(
      'INSERT INTO stock_opname_lines (id, created_at, updated_at, '
      'sync_status, opname_id, item_id, batch_id, system_qty, counted_qty, '
      'note) '
      "VALUES ('$id', $stamp, $stamp, 'pending', '$opnameId', "
      "'${itemId ?? fixture.simpleItem.id}', "
      '${batchId == null ? 'NULL' : "'$batchId'"}, $systemQty, $countedQty, '
      '${note == null ? 'NULL' : "'$note'"});',
    );
  }

  group('struktur tabel', () {
    test('semua tabel schema v5 tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%';",
          )
          .get();
      final tables = rows.map((row) => row.read<String>('name')).toSet();

      expect(tables, {
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
      });
    });

    test('kolom kuantitas opname bertipe INTEGER, bukan REAL', () async {
      // `table_xinfo`, not `table_info`: the latter hides generated columns,
      // so `difference` would simply be missing from the result.
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(stock_opname_lines);')
          .get();
      final columns = {for (final row in rows) row.read<String>('name'): row};

      expect(columns['system_qty']!.read<String>('type'), 'INTEGER');
      expect(columns['counted_qty']!.read<String>('type'), 'INTEGER');
      expect(columns['difference']!.read<String>('type'), 'INTEGER');

      // `hidden` is 0 for an ordinary column, 2 for VIRTUAL and 3 for STORED —
      // so this is the assertion that `difference` really is computed by the
      // database rather than written by the application.
      expect(columns['system_qty']!.read<int>('hidden'), 0);
      expect(columns['counted_qty']!.read<int>('hidden'), 0);
      expect(columns['difference']!.read<int>('hidden'), 3);
    });

    test('index kueri dan partial unique index tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'idx_stock_opname%';",
          )
          .get();
      final indexes = rows.map((row) => row.read<String>('name')).toSet();

      expect(indexes, {
        'idx_stock_opnames_branch_status',
        'idx_stock_opnames_room_period',
        'idx_stock_opnames_counted_by_status',
        'idx_stock_opnames_doc_number',
        'idx_stock_opname_lines_opname',
        'idx_stock_opname_lines_item',
        'idx_stock_opname_lines_batched',
        'idx_stock_opname_lines_unbatched',
      });
    });
  });

  group('generated difference', () {
    test('dihitung database sebagai counted - system', () async {
      await insertOpname();
      await insertLine(systemQty: 1500, countedQty: 500);

      final row = await context.database
          .customSelect(
            "SELECT difference FROM stock_opname_lines WHERE id = 'sol-1';",
          )
          .getSingle();

      // 1.5 system, 0.5 counted → exactly -1 unit, no floating point residue.
      expect(row.read<int>('difference'), -1000);
      expect(
        Quantity.fromMilliUnits(row.read<int>('difference')).format(),
        '-1',
      );
    });

    test('mengikuti perubahan counted_qty', () async {
      await insertOpname();
      await insertLine(systemQty: 2375, countedQty: 2375);

      await context.database.customStatement(
        "UPDATE stock_opname_lines SET counted_qty = 3375 WHERE id = 'sol-1';",
      );

      final row = await context.database
          .customSelect(
            "SELECT difference FROM stock_opname_lines WHERE id = 'sol-1';",
          )
          .getSingle();
      expect(row.read<int>('difference'), 1000);
    });

    test('tidak dapat ditulis langsung', () async {
      await insertOpname();
      await insertLine();

      await expectLater(
        context.database.customStatement(
          'UPDATE stock_opname_lines SET difference = 999999 '
          "WHERE id = 'sol-1';",
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('constraint header', () {
    test('satu opname per ruangan per minggu ISO (G-O1)', () async {
      await insertOpname(id: 'so-1', docNumber: 'TMP-SO-1');

      await expectLater(
        insertOpname(id: 'so-2', docNumber: 'TMP-SO-2'),
        throwsA(isA<Exception>()),
      );
    });

    test('ruangan berbeda pada minggu yang sama diizinkan', () async {
      await insertOpname(id: 'so-1', docNumber: 'TMP-SO-1');
      await insertOpname(
        id: 'so-2',
        docNumber: 'TMP-SO-2',
        roomId: fixture.secondRoom.id,
      );

      final rows = await context.database
          .customSelect('SELECT id FROM stock_opnames;')
          .get();
      expect(rows, hasLength(2));
    });

    test('minggu berikutnya untuk ruangan yang sama diizinkan', () async {
      await insertOpname(id: 'so-1', docNumber: 'TMP-SO-1', week: 31);
      await insertOpname(id: 'so-2', docNumber: 'TMP-SO-2', week: 32);

      final rows = await context.database
          .customSelect('SELECT id FROM stock_opnames;')
          .get();
      expect(rows, hasLength(2));
    });

    test('nomor dokumen unik', () async {
      await insertOpname(id: 'so-1', docNumber: 'TMP-SO-SAMA');

      await expectLater(
        insertOpname(
          id: 'so-2',
          docNumber: 'TMP-SO-SAMA',
          roomId: fixture.secondRoom.id,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('minggu di luar 1..53 ditolak', () async {
      await expectLater(insertOpname(week: 54), throwsA(isA<Exception>()));
      await expectLater(insertOpname(week: 0), throwsA(isA<Exception>()));
    });

    test('status di luar enum ditolak', () async {
      await expectLater(
        insertOpname(status: 'approved'),
        throwsA(isA<Exception>()),
      );
    });

    test('draft tidak boleh membawa metadata submit atau review', () async {
      await expectLater(
        insertOpname(status: 'draft', submittedAt: '2026-07-29T01:00:00.000Z'),
        throwsA(isA<Exception>()),
      );
    });

    test('submitted wajib memiliki submitted_at', () async {
      await expectLater(
        insertOpname(status: 'submitted'),
        throwsA(isA<Exception>()),
      );
    });

    test('reviewed wajib memiliki reviewer dan kedua timestamp', () async {
      await expectLater(
        insertOpname(
          status: 'reviewed',
          submittedAt: '2026-07-29T01:00:00.000Z',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('reviewer tidak boleh sama dengan penghitung (G-R4)', () async {
      await expectLater(
        insertOpname(
          status: 'reviewed',
          submittedAt: '2026-07-29T01:00:00.000Z',
          reviewedAt: '2026-07-29T02:00:00.000Z',
          reviewedBy: fixture.nurse.id,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('dokumen reviewed yang konsisten diterima', () async {
      await insertOpname(
        status: 'reviewed',
        submittedAt: '2026-07-29T01:00:00.000Z',
        reviewedAt: '2026-07-29T02:00:00.000Z',
        reviewedBy: fixture.branchHead.id,
      );

      final row = await context.database
          .customSelect("SELECT status FROM stock_opnames WHERE id = 'so-1';")
          .getSingle();
      expect(row.read<String>('status'), 'reviewed');
    });

    test('foreign key ruangan ditegakkan', () async {
      await expectLater(
        insertOpname(roomId: 'ruangan-tidak-ada'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('urutan timestamp bukan urusan database (schema v4)', () {
    /// The CREATE TABLE statement SQLite actually holds, not the Dart source
    /// that produced it. A constraint can only be proven absent by asking the
    /// database what it has.
    Future<String> stockOpnamesSql() async {
      final row = await context.database
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE type = 'table' AND name = 'stock_opnames';",
          )
          .getSingle();
      return row.read<String>('sql');
    }

    test('tidak ada CHECK perbandingan leksikal timestamp', () async {
      final sql = (await stockOpnamesSql()).replaceAll(RegExp(r'\s+'), ' ');

      // Every spelling of the ordering comparison, in both directions.
      for (final forbidden in [
        'reviewed_at >= submitted_at',
        'reviewed_at > submitted_at',
        'submitted_at <= reviewed_at',
        'submitted_at < reviewed_at',
      ]) {
        expect(
          sql,
          isNot(contains(forbidden)),
          reason:
              'stock_opnames masih membandingkan timestamp sebagai teks: '
              '$forbidden',
        );
      }
    });

    test('tidak ada julianday atau strftime pada constraint', () async {
      final sql = (await stockOpnamesSql()).toLowerCase();

      // Rewriting the comparison with a date function would move the rule back
      // into SQL rather than fix it (§8.3).
      expect(sql, isNot(contains('julianday')));
      expect(sql, isNot(contains('strftime')));
      expect(sql, isNot(contains('datetime(')));
    });

    test('constraint konsistensi status dan null tetap ada', () async {
      final sql = (await stockOpnamesSql()).replaceAll(RegExp(r'\s+'), ' ');

      // What the database *can* state unambiguously is still stated.
      expect(sql, contains("status IN ('draft', 'submitted', 'reviewed')"));
      expect(
        sql,
        contains(
          "status = 'draft' AND submitted_at IS NULL "
          'AND reviewed_at IS NULL AND reviewed_by IS NULL',
        ),
      );
      expect(
        sql,
        contains(
          "status = 'submitted' AND submitted_at IS NOT NULL "
          'AND reviewed_at IS NULL AND reviewed_by IS NULL',
        ),
      );
      expect(
        sql,
        contains(
          "status = 'reviewed' AND submitted_at IS NOT NULL "
          'AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL',
        ),
      );
      expect(sql, contains('reviewed_by IS NULL OR reviewed_by <> counted_by'));
    });

    test(
      'database menerima reviewed_at lebih awal, domain yang menolak',
      () async {
        // The database deliberately no longer has an opinion about which
        // timestamp came first — so this insert succeeds. Everything that stops
        // a document reaching this state lives in `DocumentTimestampPolicy`,
        // which `opname_timestamp_test.dart` exercises.
        await insertOpname(
          status: 'reviewed',
          submittedAt: '2026-07-29T02:00:00.000Z',
          reviewedAt: '2026-07-29T01:00:00.000Z',
          reviewedBy: fixture.branchHead.id,
        );

        final row = await context.database
            .customSelect("SELECT status FROM stock_opnames WHERE id = 'so-1';")
            .getSingle();
        expect(row.read<String>('status'), 'reviewed');
      },
    );

    test('DAO tidak membandingkan timestamp lewat SQL', () {
      // Comments are stripped first: the constraint that was removed is
      // *described* in prose there, and a test that cannot tell an explanation
      // from a statement would force the explanation to be deleted.
      final dao = File('lib/core/db/daos/opname_dao.dart')
          .readAsStringSync()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      for (final forbidden in [
        'reviewed_at >=',
        'reviewed_at >',
        'submitted_at <=',
        'submitted_at <',
        'julianday',
        'strftime',
      ]) {
        expect(
          dao,
          isNot(contains(forbidden)),
          reason: 'opname_dao.dart mengurutkan timestamp lewat SQL: $forbidden',
        );
      }
    });

    test('alur opname tidak memakai toLocal', () {
      // T-4: the device timezone must never enter a display or calculation
      // path. UTC in, GMT+8 out, and nothing in between.
      for (final file in [
        ...Directory('lib/features/opname')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
        File('lib/core/time/document_timestamp_policy.dart'),
        File('lib/core/db/daos/opname_dao.dart'),
      ]) {
        expect(
          file.readAsStringSync(),
          isNot(contains('toLocal()')),
          reason: '${file.path} memakai zona waktu perangkat.',
        );
      }
    });
  });

  group('constraint baris', () {
    setUp(() => insertOpname());

    test('counted_qty negatif ditolak (G-O3)', () async {
      await expectLater(insertLine(countedQty: -1), throwsA(isA<Exception>()));
    });

    test('system_qty negatif ditolak', () async {
      await expectLater(insertLine(systemQty: -1), throwsA(isA<Exception>()));
    });

    test('barang tanpa batch unik per opname dan item', () async {
      await insertLine(id: 'sol-1');

      // SQLite treats NULLs as distinct in a plain UNIQUE, so this duplicate
      // is exactly what the partial unique index has to reject.
      await expectLater(insertLine(id: 'sol-2'), throwsA(isA<Exception>()));
    });

    test('barang ber-batch unik per opname, item dan batch', () async {
      await insertLine(
        id: 'sol-1',
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
      );

      await expectLater(
        insertLine(
          id: 'sol-2',
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('batch berbeda untuk item yang sama diizinkan', () async {
      await insertLine(
        id: 'sol-1',
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
      );
      await insertLine(
        id: 'sol-2',
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
      );

      final rows = await context.database
          .customSelect('SELECT id FROM stock_opname_lines;')
          .get();
      expect(rows, hasLength(2));
    });

    test('foreign key opname ditegakkan', () async {
      await expectLater(
        insertLine(opnameId: 'opname-tidak-ada'),
        throwsA(isA<Exception>()),
      );
    });

    test('catatan opsional saat selisih nol', () async {
      await insertLine(systemQty: 1000, countedQty: 1000);

      final row = await context.database
          .customSelect(
            "SELECT note, difference FROM stock_opname_lines WHERE id = 'sol-1';",
          )
          .getSingle();
      expect(row.read<String?>('note'), isNull);
      expect(row.read<int>('difference'), 0);
    });
  });

  test('DAO opname tidak menyediakan update atau delete tanpa penjaga', () {
    // G-S2 is enforced structurally: there must be no way to mutate a final
    // document. Guard the source so a generic writer cannot be reintroduced.
    final source = File('lib/core/db/daos/opname_dao.dart').readAsStringSync();

    // Every status write goes through the one guarded transition method.
    expect(source, contains('transitionStatus'));
    expect(source, isNot(contains('deleteOpname')));
    expect(source, isNot(contains('delete(stockOpnames)')));
    expect(source, isNot(contains('delete(stockOpnameLines)')));

    // The only `update(stockOpnames)` calls are the two guarded ones, and both
    // carry a status predicate in the same statement.
    final unguarded = RegExp(
      r'update\(stockOpnames\)\)\s*\.write',
    ).hasMatch(source);
    expect(
      unguarded,
      isFalse,
      reason: 'setiap update header wajib memakai where() berpenjaga status',
    );

    // system_qty must have no writer at all (G-O2).
    expect(source, isNot(contains('systemQty: Value(')));
    expect(source, isNot(contains('SET system_qty')));
  });

  test('domain opname tidak bergantung pada file generated drift', () {
    // The domain layer must stay free of drift row classes so it can be tested
    // and reasoned about without the database.
    final domainDir = Directory('lib/features/opname/domain');
    final files = domainDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains("import 'package:drift/drift.dart'")),
        reason: '${file.path} must not import drift',
      );
      expect(
        source,
        isNot(contains('app_database.dart')),
        reason: '${file.path} must not import generated drift classes',
      );
      expect(
        source,
        isNot(contains('milliUnits')),
        reason: '${file.path} must speak Quantity, not milli-units',
      );
    }
  });

  test('tidak ada double pada jalur kuantitas opname', () {
    String codeOnly(String source) => source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    final sources = {
      'opname_dao.dart': File(
        'lib/core/db/daos/opname_dao.dart',
      ).readAsStringSync(),
      'opname_tables.dart': File(
        'lib/core/db/tables/opname_tables.dart',
      ).readAsStringSync(),
      'drift_opname_repository.dart': File(
        'lib/features/opname/data/repositories/drift_opname_repository.dart',
      ).readAsStringSync(),
      'opname_models.dart': File(
        'lib/features/opname/domain/models/opname_models.dart',
      ).readAsStringSync(),
    };

    for (final entry in sources.entries) {
      final code = codeOnly(entry.value);
      expect(
        code,
        isNot(matches(RegExp(r'\bdouble\b'))),
        reason: '${entry.key} must not use double for quantities',
      );
      expect(
        code,
        isNot(contains('real()')),
        reason: '${entry.key} must not declare a REAL quantity column',
      );
      expect(
        code,
        isNot(contains('AS REAL')),
        reason: '${entry.key} must not cast quantities to REAL',
      );
    }
  });
}
