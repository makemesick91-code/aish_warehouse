import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Schema v9 as a **fresh** database gets it (§38).
///
/// Everything here is asserted against the objects SQLite actually holds rather than
/// against the Dart declarations that produced them, because the two can disagree in
/// exactly one direction that matters: a constraint written in a `@TableIndex.sql`
/// string, or a CHECK in `customConstraints`, is not type-checked by anything. If a
/// clause is missing, the Dart still compiles and the use cases still pass — and the
/// database stops being the last line of defence.
///
/// Two constraints get more attention than the rest, because both are easy to write
/// in a way that compiles and does nothing:
///
/// * the posted-status CHECK, which has to say `reason IS NOT NULL AND trim(reason)
///   <> ''` rather than `trim(reason) <> ''` alone — SQLite treats a CHECK evaluating
///   to NULL as **satisfied**, so the short form would let a posted row through with
///   no reason at all, which is the one row G-E7 exists to prevent;
/// * `idx_disposals_doc_number`, which is deliberately **unqualified** where every
///   other document number index in this schema carries `WHERE deleted_at IS NULL`
///   (G-A3: *"nomor dokumen … tidak dipakai ulang"*).
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  Future<String> columnType(String table, String column) async {
    final rows = await context.database
        .customSelect('PRAGMA table_xinfo($table);')
        .get();
    final match = rows.where((row) => row.read<String>('name') == column);
    expect(match, isNotEmpty, reason: '$table.$column tidak ada.');
    return match.first.read<String>('type');
  }

  Future<int> columnNotNull(String table, String column) async {
    final rows = await context.database
        .customSelect('PRAGMA table_xinfo($table);')
        .get();
    final match = rows.where((row) => row.read<String>('name') == column);
    expect(match, isNotEmpty, reason: '$table.$column tidak ada.');
    return match.first.read<int>('notnull');
  }

  Future<String> tableSql(String table) async {
    final row = await context.database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?;",
          variables: [Variable<String>(table)],
        )
        .getSingle();
    return row.read<String>('sql');
  }

  Future<String> indexSql(String name) async {
    final row = await context.database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?;",
          variables: [Variable<String>(name)],
        )
        .getSingle();
    return row.read<String>('sql');
  }

  Future<Set<String>> indexNames(String needle) async {
    final rows = await context.database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE '%$needle%' AND name NOT LIKE 'sqlite_%';",
        )
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  Future<Map<String, String>> foreignKeys(String table) async {
    final rows = await context.database
        .customSelect('PRAGMA foreign_key_list($table);')
        .get();
    return {
      for (final row in rows)
        row.read<String>('from'): row.read<String>('table'),
    };
  }

  group('struktur tabel', () {
    test('schemaVersion adalah 12', () async {
      // The *current* version, not the one this milestone introduced: a fresh
      // database is always built at head, and pinning the number here is what makes
      // a forgotten `schemaVersion` bump fail the suite.
      final row = await context.database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 13);
      expect(context.database.schemaVersion, 13);
    });

    test('dua tabel Pemusnahan tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'disposal%';",
          )
          .get();

      expect(rows.map((row) => row.read<String>('name')).toSet(), {
        'disposals',
        'disposal_lines',
      });
    });

    test('kolom standar hadir di kedua tabel', () async {
      for (final table in ['disposals', 'disposal_lines']) {
        final rows = await context.database
            .customSelect('PRAGMA table_xinfo($table);')
            .get();
        final names = rows.map((row) => row.read<String>('name')).toSet();
        expect(
          names,
          containsAll(<String>[
            'id',
            'created_at',
            'updated_at',
            'deleted_at',
            'sync_status',
          ]),
          reason: '$table kehilangan kolom standar §2.',
        );
      }
    });

    test('kolom bisnis header sesuai §8', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(disposals);')
          .get();
      expect(
        rows.map((row) => row.read<String>('name')).toSet(),
        containsAll(<String>[
          'doc_number',
          'source_location_id',
          'created_by',
          'status',
          'reason',
          'posted_at',
          'posted_by',
        ]),
      );
    });

    test('kolom bisnis baris sesuai §9', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(disposal_lines);')
          .get();
      expect(
        rows.map((row) => row.read<String>('name')).toSet(),
        containsAll(<String>[
          'disposal_id',
          'item_id',
          'batch_id',
          'qty',
          'note',
        ]),
      );
    });

    test('qty bertipe INTEGER, bukan REAL', () async {
      // Q-3: milli-units. A REAL column would accumulate binary rounding error and
      // drift away from the ledger it mirrors.
      expect(await columnType('disposal_lines', 'qty'), 'INTEGER');
    });

    test('batch_id baris bersifat NOT NULL', () async {
      // §9: this milestone destroys expired stock and nothing else, and only a
      // batch-tracked item has a date to be past. A nullable column here would make
      // "dispose of an item without expiry" expressible.
      expect(await columnNotNull('disposal_lines', 'batch_id'), 1);
    });

    test('posted_by header nullable, created_by tidak', () async {
      expect(await columnNotNull('disposals', 'created_by'), 1);
      expect(await columnNotNull('disposals', 'posted_by'), 0);
      expect(await columnNotNull('disposals', 'reason'), 0);
    });

    test('foreign key lengkap', () async {
      expect(await foreignKeys('disposals'), {
        'source_location_id': 'stock_locations',
        'created_by': 'users',
        'posted_by': 'users',
      });
      expect(await foreignKeys('disposal_lines'), {
        'disposal_id': 'disposals',
        'item_id': 'items',
        'batch_id': 'item_batches',
      });
    });
  });

  group('CHECK', () {
    test('status dibatasi dua nilai', () async {
      final sql = await tableSql('disposals');
      expect(sql, contains("status IN ('draft', 'posted')"));
    });

    test('CHECK posted menuntut reason IS NOT NULL, bukan hanya trim', () async {
      // The load-bearing half: `trim(NULL)` is NULL, and SQLite counts a CHECK that
      // evaluates to NULL as satisfied. Without the explicit `IS NOT NULL` a posted
      // row with no reason would pass.
      final sql = await tableSql('disposals');
      expect(sql, contains('reason IS NOT NULL'));
      expect(sql, contains("trim(reason) <> ''"));
    });

    test(
      'CHECK menuntut posted_at dan posted_by konsisten dengan status',
      () async {
        final sql = await tableSql('disposals');
        expect(sql, contains('posted_at IS NULL'));
        expect(sql, contains('posted_by IS NULL'));
        expect(sql, contains('posted_at IS NOT NULL'));
        expect(sql, contains('posted_by IS NOT NULL'));
      },
    );

    test('tidak ada perbandingan timestamp leksikal', () async {
      // Timestamps are ISO-8601 TEXT, so `posted_at >= created_at` in SQL compares
      // characters rather than instants — the trap schema v4 removed from
      // `stock_opnames`. Ordering is `DocumentTimestampPolicy`'s, on UTC DateTimes.
      final sql = await tableSql('disposals');
      expect(sql.contains('posted_at >= created_at'), isFalse);
      expect(sql.contains('posted_at > created_at'), isFalse);
    });

    test('CHECK qty > 0 pada baris', () async {
      expect(await tableSql('disposal_lines'), contains('qty > 0'));
    });

    test('CHECK note baris menerima NULL dan menolak string kosong', () async {
      final sql = await tableSql('disposal_lines');
      expect(sql, contains('note IS NULL OR'));
      expect(sql, contains("trim(note) <> ''"));
    });
  });

  group('CHECK ditegakkan oleh SQLite', () {
    /// Master rows the raw inserts below need, created through the repository so the
    /// foreign keys resolve.
    Future<({String location, String user, String item, String batch})>
    seedMaster() async {
      final location = await context.master.ensureLocation(
        type: StockLocationType.warehouse,
        name: 'Warehouse Pusat',
      );
      final user = await context.master.ensureUser(
        email: 'wh@test.local',
        fullName: 'Petugas Warehouse',
        role: UserRole.warehouse,
      );
      final category = await context.master.ensureCategory('Obat');
      final item = await context.master.ensureItem(
        sku: 'SKU-1',
        name: 'Anestesi',
        categoryId: category.id,
        unit: 'ampul',
        minStockRoom: 1,
        minStockBranch: 1,
        hasExpiry: true,
      );
      final batch = await context.master.ensureBatch(
        itemId: item.id,
        batchNo: 'B-1',
        expiryDate: DateTime.utc(2026, 1, 1),
      );
      return (
        location: location.id,
        user: user.id,
        item: item.id,
        batch: batch.id,
      );
    }

    Future<void> insertHeader({
      required String id,
      required String status,
      String? reason,
      String? postedAt,
      String? postedBy,
      required String location,
      required String user,
    }) => context.database.customStatement(
      'INSERT INTO disposals (id, created_at, updated_at, sync_status, '
      'doc_number, source_location_id, created_by, status, reason, posted_at, '
      'posted_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-30T00:00:00.000Z',
        '2026-07-30T00:00:00.000Z',
        'pending',
        'TMP-DSP-$id',
        location,
        user,
        status,
        reason,
        postedAt,
        postedBy,
      ],
    );

    test('draft dengan posted_at ditolak', () async {
      final master = await seedMaster();
      await expectLater(
        insertHeader(
          id: 'd1',
          status: 'draft',
          postedAt: '2026-07-30T01:00:00.000Z',
          location: master.location,
          user: master.user,
        ),
        throwsA(anything),
      );
    });

    test('posted tanpa reason ditolak', () async {
      // The row the `IS NOT NULL` half of the CHECK exists for.
      final master = await seedMaster();
      await expectLater(
        insertHeader(
          id: 'd2',
          status: 'posted',
          postedAt: '2026-07-30T01:00:00.000Z',
          postedBy: master.user,
          location: master.location,
          user: master.user,
        ),
        throwsA(anything),
      );
    });

    test('posted dengan reason spasi ditolak', () async {
      final master = await seedMaster();
      await expectLater(
        insertHeader(
          id: 'd3',
          status: 'posted',
          reason: '   ',
          postedAt: '2026-07-30T01:00:00.000Z',
          postedBy: master.user,
          location: master.location,
          user: master.user,
        ),
        throwsA(anything),
      );
    });

    test('posted tanpa posted_by ditolak', () async {
      final master = await seedMaster();
      await expectLater(
        insertHeader(
          id: 'd4',
          status: 'posted',
          reason: 'Kedaluwarsa',
          postedAt: '2026-07-30T01:00:00.000Z',
          location: master.location,
          user: master.user,
        ),
        throwsA(anything),
      );
    });

    test('status di luar enum ditolak', () async {
      final master = await seedMaster();
      await expectLater(
        insertHeader(
          id: 'd5',
          status: 'approved',
          location: master.location,
          user: master.user,
        ),
        throwsA(anything),
      );
    });

    test('draft dengan reason spasi ditolak', () async {
      // The second CHECK: a *stored* reason must say something, whatever the status.
      final master = await seedMaster();
      await expectLater(
        insertHeader(
          id: 'd6',
          status: 'draft',
          reason: '  ',
          location: master.location,
          user: master.user,
        ),
        throwsA(anything),
      );
    });

    test('qty nol pada baris ditolak', () async {
      final master = await seedMaster();
      await insertHeader(
        id: 'd7',
        status: 'draft',
        location: master.location,
        user: master.user,
      );

      await expectLater(
        context.database.customStatement(
          'INSERT INTO disposal_lines (id, created_at, updated_at, sync_status, '
          'disposal_id, item_id, batch_id, qty) VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
          [
            'l1',
            '2026-07-30T00:00:00.000Z',
            '2026-07-30T00:00:00.000Z',
            'pending',
            'd7',
            master.item,
            master.batch,
            0,
          ],
        ),
        throwsA(anything),
      );
    });

    test('baris tanpa batch ditolak', () async {
      final master = await seedMaster();
      await insertHeader(
        id: 'd8',
        status: 'draft',
        location: master.location,
        user: master.user,
      );

      await expectLater(
        context.database.customStatement(
          'INSERT INTO disposal_lines (id, created_at, updated_at, sync_status, '
          'disposal_id, item_id, batch_id, qty) VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
          [
            'l2',
            '2026-07-30T00:00:00.000Z',
            '2026-07-30T00:00:00.000Z',
            'pending',
            'd8',
            master.item,
            null,
            Quantity.parse('1').milliUnits,
          ],
        ),
        throwsA(anything),
      );
    });
  });

  group('index', () {
    test('seluruh index Pemusnahan hadir', () async {
      expect(await indexNames('disposal'), {
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
      });
    });

    test('doc_number unik tanpa klausa partial (G-A3)', () async {
      final sql = await indexSql('idx_disposals_doc_number');
      expect(sql, contains('UNIQUE'));
      // Deliberately different from every other document number index: a destruction
      // record's number must never be reissued, so a soft-deleted row keeps holding
      // it.
      expect(sql.toLowerCase().contains('where'), isFalse);
    });

    test('posisi baris unik hanya untuk baris hidup', () async {
      final sql = await indexSql('idx_disposal_lines_position');
      expect(sql, contains('UNIQUE'));
      expect(sql, contains('disposal_id, item_id, batch_id'));
      // What lets a line removed from a draft be added back afterwards.
      expect(sql, contains('deleted_at IS NULL'));
    });

    test('index posisi menolak batch ganda pada satu dokumen', () async {
      final master = await seedPositionFixture(context);
      await context.database.customStatement(
        'INSERT INTO disposals (id, created_at, updated_at, sync_status, '
        'doc_number, source_location_id, created_by, status) '
        "VALUES ('p1', ?, ?, 'pending', 'TMP-DSP-p1', ?, ?, 'draft');",
        [
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          master.location,
          master.user,
        ],
      );

      Future<void> insertLine(String id) => context.database.customStatement(
        'INSERT INTO disposal_lines (id, created_at, updated_at, sync_status, '
        'disposal_id, item_id, batch_id, qty) '
        "VALUES (?, ?, ?, 'pending', 'p1', ?, ?, ?);",
        [
          id,
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          master.item,
          master.batch,
          1000,
        ],
      );

      await insertLine('pl1');
      await expectLater(insertLine('pl2'), throwsA(anything));

      // Soft-deleting the first frees the position again.
      await context.database.customStatement(
        "UPDATE disposal_lines SET deleted_at = ? WHERE id = 'pl1';",
        ['2026-07-30T01:00:00.000Z'],
      );
      await insertLine('pl3');
    });
  });

  group('integritas', () {
    test('foreign_key_check bersih pada database baru', () async {
      final rows = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(rows, isEmpty);
    });

    test('foreign_keys pragma aktif', () async {
      final row = await context.database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });
  });
}

/// The master rows a raw-SQL position test needs.
Future<({String location, String user, String item, String batch})>
seedPositionFixture(TestContext context) async {
  final location = await context.master.ensureLocation(
    type: StockLocationType.warehouse,
    name: 'Warehouse Pusat',
  );
  final user = await context.master.ensureUser(
    email: 'wh@test.local',
    fullName: 'Petugas Warehouse',
    role: UserRole.warehouse,
  );
  final category = await context.master.ensureCategory('Obat');
  final item = await context.master.ensureItem(
    sku: 'SKU-1',
    name: 'Anestesi',
    categoryId: category.id,
    unit: 'ampul',
    minStockRoom: 1,
    minStockBranch: 1,
    hasExpiry: true,
  );
  final batch = await context.master.ensureBatch(
    itemId: item.id,
    batchNo: 'B-1',
    expiryDate: DateTime.utc(2026, 1, 1),
  );
  return (location: location.id, user: user.id, item: item.id, batch: batch.id);
}
