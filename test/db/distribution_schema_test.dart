import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/distribution/domain/services/distribution_fefo_policy.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The Distribusi half of the schema as a **fresh** database gets it (§36).
///
/// The version assertion tracks the *current* schema rather than v8: a fresh
/// database is always created at `schemaVersion`, so pinning it to 8 would fail
/// the moment a later milestone lands. What stays pinned to Milestone 6 is
/// everything below it — the two tables, their constraints and their indexes.
///
/// Everything here is asserted against the objects SQLite actually holds rather than
/// against the Dart declarations that produced them, because the two can disagree in
/// exactly one direction that matters: a constraint written in a `@TableIndex.sql`
/// string, or a CHECK in `customConstraints`, is not type-checked by anything. If a
/// clause is missing, the Dart still compiles and the use cases still pass — and the
/// database stops being the last line of defence.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  /// Column type of one column, read from the table's own definition.
  Future<String> columnType(String table, String column) async {
    final rows = await context.database
        .customSelect('PRAGMA table_xinfo($table);')
        .get();
    final match = rows.where((row) => row.read<String>('name') == column);
    expect(match, isNotEmpty, reason: '$table.$column tidak ada.');
    return match.first.read<String>('type');
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
    test('schemaVersion adalah 9', () async {
      final row = await context.database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 9);
      expect(context.database.schemaVersion, 9);
    });

    test('dua tabel Distribusi tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'distribution%';",
          )
          .get();

      expect(rows.map((row) => row.read<String>('name')).toSet(), {
        'distributions',
        'distribution_lines',
      });
    });

    test('kolom standar hadir di kedua tabel', () async {
      for (final table in ['distributions', 'distribution_lines']) {
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

    test('kolom bisnis header sesuai spesifikasi §2.3', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(distributions);')
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();
      expect(
        names,
        containsAll(<String>[
          'doc_number',
          'branch_id',
          'distributed_by',
          'status',
          'posted_at',
          'note',
        ]),
      );
    });

    test('kolom bisnis baris sesuai spesifikasi §2.3', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(distribution_lines);')
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();
      expect(
        names,
        containsAll(<String>[
          'distribution_id',
          'room_id',
          'item_id',
          'batch_id',
          'qty',
          'fefo_override_reason',
        ]),
      );
    });

    test('qty adalah INTEGER milli-unit, bukan REAL', () async {
      // Q-3. A REAL quantity would accumulate binary rounding error and could drift
      // away from the ledger it mirrors.
      expect(await columnType('distribution_lines', 'qty'), 'INTEGER');
    });

    test('tidak ada kolom lokasi sumber atau tujuan pada baris', () async {
      // §14/G-T1. Both are resolved from the branch and the room by type at posting
      // time. A stored column would let a line name a location that contradicts its
      // own room, and a UI that could submit one is exactly the hole G-T1 closes.
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(distribution_lines);')
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();
      expect(names, isNot(contains('from_location_id')));
      expect(names, isNot(contains('to_location_id')));
      expect(names, isNot(contains('source_location_id')));
      expect(names, isNot(contains('destination_location_id')));
    });

    test('header tidak menyimpan total turunan', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(distributions);')
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();
      expect(names, isNot(contains('line_count')));
      expect(names, isNot(contains('room_count')));
      expect(names, isNot(contains('total_qty')));
      // One document targets many rooms (G-T3), so the room is a line-level fact.
      expect(names, isNot(contains('room_id')));
    });
  });

  group('constraint', () {
    test('status dibatasi draft dan posted', () async {
      final sql = await tableSql('distributions');
      expect(sql, contains("status IN ('draft', 'posted')"));
    });

    test('posted_at hadir tepat ketika status posted', () async {
      final sql = await tableSql('distributions');
      expect(sql, contains("status = 'draft' AND posted_at IS NULL"));
      expect(sql, contains("status = 'posted' AND posted_at IS NOT NULL"));
    });

    test('qty harus lebih besar dari nol', () async {
      expect(await tableSql('distribution_lines'), contains('qty > 0'));
    });

    test('CHECK alasan FEFO menolak string kosong dan menerima NULL', () async {
      final sql = await tableSql('distribution_lines');
      // The NULL branch is explicit rather than relying on `trim(NULL) <> ''`,
      // which SQLite evaluates to NULL and therefore treats as satisfied.
      expect(sql, contains('fefo_override_reason IS NULL'));
      expect(sql, contains("trim(fefo_override_reason) <> ''"));
    });

    test('tidak ada perbandingan timestamp leksikal', () async {
      // Timestamps are ISO-8601 TEXT, so `posted_at >= created_at` in SQL compares
      // characters rather than instants — the trap schema v4 removed from
      // `stock_opnames`. Ordering is `DocumentTimestampPolicy`'s job.
      final sql = await tableSql('distributions');
      expect(sql, isNot(contains('posted_at >= created_at')));
      expect(sql, isNot(contains('posted_at > created_at')));
      expect(sql, isNot(contains('created_at <= posted_at')));
    });

    test('foreign key header menunjuk branches dan users', () async {
      expect(await foreignKeys('distributions'), {
        'branch_id': 'branches',
        'distributed_by': 'users',
      });
    });

    test('foreign key baris menunjuk empat tabel', () async {
      expect(await foreignKeys('distribution_lines'), {
        'distribution_id': 'distributions',
        'room_id': 'rooms',
        'item_id': 'items',
        'batch_id': 'item_batches',
      });
    });
  });

  group('index', () {
    test('seluruh index v8 dibuat', () async {
      expect(await indexNames('distribution'), {
        'idx_distributions_branch_status',
        'idx_distributions_distributed_by_status',
        'idx_distributions_created_at',
        'idx_distributions_posted_at',
        'idx_distributions_doc_number',
        'idx_distribution_lines_distribution',
        'idx_distribution_lines_room',
        'idx_distribution_lines_item',
        'idx_distribution_lines_batch',
        'idx_distribution_lines_batched',
        'idx_distribution_lines_unbatched',
      });
    });

    test('doc_number unik hanya untuk baris hidup', () async {
      final sql = await indexSql('idx_distributions_doc_number');
      expect(sql, contains('UNIQUE'));
      expect(sql, contains('deleted_at IS NULL'));
    });

    test('index unik batch bersifat partial', () async {
      final sql = await indexSql('idx_distribution_lines_batched');
      expect(sql, contains('UNIQUE'));
      expect(sql, contains('batch_id IS NOT NULL'));
      expect(sql, contains('deleted_at IS NULL'));
    });

    test('index unik non-batch bersifat partial', () async {
      final sql = await indexSql('idx_distribution_lines_unbatched');
      expect(sql, contains('UNIQUE'));
      expect(sql, contains('batch_id IS NULL'));
      expect(sql, contains('deleted_at IS NULL'));
    });
  });

  group('penegakan runtime', () {
    late String branchId;
    late String otherBranchId;
    late String roomId;
    late String secondRoomId;
    late String headId;
    late String itemId;
    late String batchItemId;
    late String batchId;

    setUp(() async {
      final master = context.master;
      final branch = await master.ensureBranch(
        code: 'CAB-01',
        name: 'Cabang Uji',
      );
      branchId = branch.id;
      otherBranchId = (await master.ensureBranch(
        code: 'CAB-02',
        name: 'Cabang Lain',
      )).id;
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
      headId = (await master.ensureUser(
        email: 'kacab@test.local',
        fullName: 'Kepala Cabang Uji',
        role: UserRole.kepalaCabang,
        branchId: branch.id,
      )).id;
      final category = await master.ensureCategory('Alat Sekali Pakai');
      itemId = (await master.ensureItem(
        sku: 'DIST-0001',
        name: 'Masker Bedah',
        categoryId: category.id,
        unit: 'box',
        minStockRoom: 1,
        minStockBranch: 5,
        hasExpiry: false,
      )).id;
      batchItemId = (await master.ensureItem(
        sku: 'DIST-0002',
        name: 'Anestesi Lokal',
        categoryId: category.id,
        unit: 'ampul',
        minStockRoom: 1,
        minStockBranch: 5,
        hasExpiry: true,
      )).id;
      batchId = (await master.ensureBatch(
        itemId: batchItemId,
        batchNo: 'BATCH-A',
        expiryDate: DateTime.utc(2027, 3, 31),
      )).id;
    });

    Future<void> insertHeader({
      required String id,
      String? status,
      String? postedAt,
      String? docNumber,
      String? branch,
      String? deletedAt,
    }) => context.database.customStatement(
      'INSERT INTO distributions (id, created_at, updated_at, deleted_at, '
      'sync_status, doc_number, branch_id, distributed_by, status, posted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-30T03:00:00.000Z',
        '2026-07-30T03:00:00.000Z',
        deletedAt,
        'pending',
        docNumber ?? 'TMP-DIST-$id',
        branch ?? branchId,
        headId,
        status ?? 'draft',
        postedAt,
      ],
    );

    Future<void> insertLine({
      required String id,
      String parent = 'dist-1',
      String? room,
      String? item,
      String? batch,
      int qty = 1000,
      String? reason,
      String? deletedAt,
    }) => context.database.customStatement(
      'INSERT INTO distribution_lines (id, created_at, updated_at, deleted_at, '
      'sync_status, distribution_id, room_id, item_id, batch_id, qty, '
      'fefo_override_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-30T03:00:00.000Z',
        '2026-07-30T03:00:00.000Z',
        deletedAt,
        'pending',
        parent,
        room ?? roomId,
        item ?? itemId,
        batch,
        qty,
        reason,
      ],
    );

    test('status di luar enum ditolak', () async {
      expect(
        () => insertHeader(id: 'bad', status: 'cancelled'),
        throwsA(anything),
      );
      expect(
        () => insertHeader(id: 'bad2', status: 'reopened'),
        throwsA(anything),
      );
    });

    test('draft dengan posted_at ditolak', () async {
      expect(
        () => insertHeader(id: 'bad', postedAt: '2026-07-30T04:00:00.000Z'),
        throwsA(anything),
      );
    });

    test('posted tanpa posted_at ditolak', () async {
      expect(
        () => insertHeader(id: 'bad', status: 'posted'),
        throwsA(anything),
      );
    });

    test('posted dengan posted_at diterima', () async {
      await insertHeader(
        id: 'dist-posted',
        status: 'posted',
        postedAt: '2026-07-30T04:00:00.000Z',
      );
      final row = await context.database
          .customSelect(
            "SELECT status, posted_at FROM distributions "
            "WHERE id = 'dist-posted';",
          )
          .getSingle();
      expect(row.read<String>('status'), 'posted');
    });

    test('doc_number tidak dapat dipakai dua kali oleh baris hidup', () async {
      await insertHeader(id: 'dist-1');
      expect(
        () => insertHeader(id: 'dist-2', docNumber: 'TMP-DIST-dist-1'),
        throwsA(anything),
      );
    });

    test('baris qty nol dan negatif ditolak', () async {
      await insertHeader(id: 'dist-1');
      expect(() => insertLine(id: 'zero', qty: 0), throwsA(anything));
      expect(() => insertLine(id: 'neg', qty: -500), throwsA(anything));
    });

    test('alasan FEFO kosong atau spasi ditolak, NULL diterima', () async {
      await insertHeader(id: 'dist-1');
      expect(() => insertLine(id: 'empty', reason: ''), throwsA(anything));
      expect(() => insertLine(id: 'blank', reason: '   '), throwsA(anything));

      // NULL is the compliant case: a line that followed FEFO carries no reason.
      await insertLine(id: 'ok-null');
      final row = await context.database
          .customSelect(
            "SELECT fefo_override_reason FROM distribution_lines "
            "WHERE id = 'ok-null';",
          )
          .getSingle();
      expect(row.read<String?>('fefo_override_reason'), isNull);
    });

    test('alasan FEFO non-kosong diterima', () async {
      await insertHeader(id: 'dist-1');
      await insertLine(id: 'ok', reason: 'Diminta dokter untuk ED panjang');
      final row = await context.database
          .customSelect(
            "SELECT fefo_override_reason FROM distribution_lines "
            "WHERE id = 'ok';",
          )
          .getSingle();
      expect(
        row.read<String>('fefo_override_reason'),
        'Diminta dokter untuk ED panjang',
      );
    });

    test('alasan hanya tab lolos SQLite tetapi ditolak domain', () async {
      // SQLite's `trim(X)` strips **spaces only** — not tabs, not newlines — so a
      // reason of `"\t"` satisfies the CHECK. Dart's `String.trim()` strips all
      // Unicode whitespace, which is why `DistributionFefoPolicy.hasValidReason`
      // is the authority and the CHECK is the floor underneath it. Asserted rather
      // than assumed, so nobody later "simplifies" the domain check away on the
      // grounds that the database already covers it.
      await insertHeader(id: 'dist-1');
      await insertLine(id: 'tab', reason: '\t');

      final row = await context.database
          .customSelect(
            "SELECT fefo_override_reason FROM distribution_lines "
            "WHERE id = 'tab';",
          )
          .getSingle();
      expect(row.read<String>('fefo_override_reason'), '\t');
      expect(DistributionFefoPolicy.hasValidReason('\t'), isFalse);
    });

    test('posisi non-batch ganda dalam satu ruangan ditolak', () async {
      await insertHeader(id: 'dist-1');
      await insertLine(id: 'dl-1');
      expect(() => insertLine(id: 'dl-dup'), throwsA(anything));
    });

    test('item yang sama ke ruangan berbeda diterima (G-T3)', () async {
      await insertHeader(id: 'dist-1');
      await insertLine(id: 'dl-1');
      await insertLine(id: 'dl-2', room: secondRoomId);

      final rows = await context.database
          .customSelect(
            "SELECT COUNT(DISTINCT room_id) AS c FROM distribution_lines "
            "WHERE distribution_id = 'dist-1' AND deleted_at IS NULL;",
          )
          .getSingle();
      expect(rows.read<int>('c'), 2);
    });

    test('posisi batch ganda dalam satu ruangan ditolak', () async {
      await insertHeader(id: 'dist-1');
      await insertLine(id: 'dl-1', item: batchItemId, batch: batchId);
      expect(
        () => insertLine(id: 'dl-dup', item: batchItemId, batch: batchId),
        throwsA(anything),
      );
    });

    test('baris yang dihapus lunak membebaskan posisinya kembali', () async {
      await insertHeader(id: 'dist-1');
      await insertLine(id: 'dl-1', deletedAt: '2026-07-30T05:00:00.000Z');
      // The partial index is what lets a line removed from a draft be added back.
      await insertLine(id: 'dl-2');
    });

    test('referensi asing yang tidak ada ditolak', () async {
      await insertHeader(id: 'dist-1');
      expect(
        () => insertLine(id: 'ghost-room', room: 'tidak-ada'),
        throwsA(anything),
      );
      expect(
        () => insertLine(id: 'ghost-item', item: 'tidak-ada'),
        throwsA(anything),
      );
      expect(
        () => insertLine(id: 'ghost-batch', batch: 'tidak-ada'),
        throwsA(anything),
      );
      expect(
        () => insertHeader(id: 'ghost-branch', branch: 'tidak-ada'),
        throwsA(anything),
      );
    });

    test(
      'database tidak menegakkan room.branch_id = distribution.branch_id',
      () async {
        // Stated as a test rather than left implicit: SQLite cannot express a
        // cross-table equality, so a hand-written INSERT *can* file a room from
        // another branch. G-T1 therefore lives in the use cases and is revalidated
        // inside the posting transaction — and the security tests prove that.
        final foreignRoom = await context.master.ensureRoom(
          branchId: otherBranchId,
          code: 'R1',
          name: 'Ruang Dental 1 Cabang Lain',
        );
        await insertHeader(id: 'dist-1');
        await insertLine(id: 'cross', room: foreignRoom.id);

        final violations = await context.database
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(
          violations,
          isEmpty,
          reason:
              'Justru karena constraint ini lolos di database, G-T1 harus '
              'ditegakkan di use case.',
        );
      },
    );

    test('foreign_key_check bersih setelah dokumen lengkap ditulis', () async {
      await insertHeader(id: 'dist-1');
      await insertLine(id: 'dl-1', qty: Quantity.parse('2.375').milliUnits);
      await insertLine(
        id: 'dl-2',
        room: secondRoomId,
        item: batchItemId,
        batch: batchId,
        qty: Quantity.parse('0.5').milliUnits,
        reason: 'Permintaan khusus',
      );

      final pragma = await context.database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      final violations = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });

    test('qty desimal dibaca kembali persis', () async {
      await insertHeader(id: 'dist-1');
      await insertLine(id: 'dl-1', qty: Quantity.parse('2.375').milliUnits);

      final row = await context.database
          .customSelect("SELECT qty FROM distribution_lines WHERE id = 'dl-1';")
          .getSingle();
      expect(row.read<int>('qty'), 2375);
      expect(Quantity.fromMilliUnits(row.read<int>('qty')).format(), '2.375');
    });
  });
}
