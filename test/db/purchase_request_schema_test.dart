import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Schema v5 as a **fresh** database, checked at the SQL level.
///
/// These assertions are deliberately about the database rather than about the Dart
/// API on top of it. Every guardrail the Purchase Request tables carry is one the
/// application is also supposed to enforce, and a test that only exercises the use
/// cases would keep passing if a constraint were dropped — right up until a sync
/// payload or a hand-written statement did what the use case refuses to.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  Future<String> ddlOf(String table) async {
    final row = await context.database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?;",
          variables: [Variable<String>(table)],
        )
        .getSingle();
    return row.read<String>('sql');
  }

  Future<Set<String>> indexNames() async {
    final rows = await context.database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index';")
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
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

  /// Minimal master data: one branch, one room, one nurse, one branch head, two
  /// warehouse officers, one item. Written through the repositories so the rows are
  /// shaped exactly as production writes them.
  Future<
    ({
      String branchId,
      String roomId,
      String nurseId,
      String headId,
      String warehouseId,
      String secondWarehouseId,
      String itemId,
    })
  >
  seedMinimum() async {
    final fixture = await buildPurchaseRequestFixture(
      context,
      now: prWednesdayUtc(),
    );
    return (
      branchId: fixture.branch.id,
      roomId: fixture.roomOne.id,
      nurseId: fixture.nurse.id,
      headId: fixture.branchHead.id,
      warehouseId: fixture.warehouseUser.id,
      secondWarehouseId: fixture.secondWarehouseUser.id,
      itemId: fixture.simpleItem.id,
    );
  }

  /// Inserts a header straight through SQL, so a CHECK constraint is the only thing
  /// that can refuse it.
  Future<void> insertHeader({
    required String id,
    required String branchId,
    required String requestedBy,
    required String status,
    String? submittedAt,
    String? processingAt,
    String? processedBy,
    String? cancelledAt,
    String? cancelledBy,
    String? cancelReason,
    String? rejectedAt,
    String? rejectedBy,
    String? rejectReason,
    String? deletedAt,
    String? neededDate,
  }) {
    return context.database.customStatement(
      'INSERT INTO purchase_requests (id, created_at, updated_at, deleted_at, '
      'sync_status, doc_number, branch_id, requested_by, status, needed_date, '
      'note, submitted_at, processing_at, processed_by, cancelled_at, '
      'cancelled_by, cancel_reason, rejected_at, rejected_by, reject_reason) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        deletedAt,
        'pending',
        'TMP-PR-$id',
        branchId,
        requestedBy,
        status,
        neededDate,
        null,
        submittedAt,
        processingAt,
        processedBy,
        cancelledAt,
        cancelledBy,
        cancelReason,
        rejectedAt,
        rejectedBy,
        rejectReason,
      ],
    );
  }

  group('struktur tabel', () {
    test('tiga tabel Purchase Request tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'purchase_request%';",
          )
          .get();

      expect(rows.map((row) => row.read<String>('name')).toSet(), {
        'purchase_requests',
        'purchase_request_opnames',
        'purchase_request_lines',
      });
    });

    test('kolom kuantitas PR bertipe INTEGER, bukan REAL', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(purchase_request_lines);')
          .get();
      final types = {
        for (final row in rows)
          row.read<String>('name'): row.read<String>('type'),
      };

      // Q-3: REAL is forbidden on a quantity column. Milli-units are integers.
      expect(types['suggested_qty'], 'INTEGER');
      expect(types['requested_qty'], 'INTEGER');
      expect(types.values.any((type) => type.toUpperCase() == 'REAL'), isFalse);
    });

    test('needed_date disimpan sebagai TEXT tanggal, bukan angka', () async {
      // The whole schema stores timestamps as ISO-8601 TEXT
      // (`store_date_time_values_as_text`), which is what lets a civil date keep its
      // calendar fields verbatim (T-8).
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(purchase_requests);')
          .get();
      final types = {
        for (final row in rows)
          row.read<String>('name'): row.read<String>('type'),
      };

      expect(types['needed_date'], 'TEXT');
      expect(types['submitted_at'], 'TEXT');
      expect(types['processing_at'], 'TEXT');
      expect(types['cancelled_at'], 'TEXT');
      expect(types['rejected_at'], 'TEXT');
    });

    test('kolom audit transisi tersedia lengkap', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_xinfo(purchase_requests);')
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();

      // G-A3: every transition records an actor and a UTC instant.
      expect(names, containsAll(<String>['submitted_at']));
      expect(names, containsAll(<String>['processing_at', 'processed_by']));
      expect(
        names,
        containsAll(<String>['cancelled_at', 'cancelled_by', 'cancel_reason']),
      );
      expect(
        names,
        containsAll(<String>['rejected_at', 'rejected_by', 'reject_reason']),
      );
    });
  });

  group('constraint status', () {
    test('status di luar enum ditolak', () async {
      final ids = await seedMinimum();

      expect(
        () => insertHeader(
          id: 'pr-bogus',
          branchId: ids.branchId,
          requestedBy: ids.headId,
          status: 'approved',
        ),
        throwsA(anything),
      );
    });

    test('setiap nilai enum diterima oleh CHECK', () async {
      final ids = await seedMinimum();
      final sql = await ddlOf('purchase_requests');

      for (final status in [
        'draft',
        'submitted',
        'processing',
        'shipped',
        'closed',
        'rejected',
        'cancelled',
      ]) {
        expect(sql, contains("'$status'"));
      }

      // And the two forward states really are insertable, so `shipped`/`closed`
      // exist in the schema even though no use case can reach them yet.
      await insertHeader(
        id: 'pr-shipped',
        branchId: ids.branchId,
        requestedBy: ids.headId,
        status: 'shipped',
        submittedAt: '2026-07-29T04:00:00.000Z',
        processingAt: '2026-07-29T05:00:00.000Z',
        processedBy: ids.warehouseId,
      );
      await insertHeader(
        id: 'pr-closed',
        branchId: ids.branchId,
        requestedBy: ids.headId,
        status: 'closed',
        submittedAt: '2026-07-29T04:00:00.000Z',
        processingAt: '2026-07-29T05:00:00.000Z',
        processedBy: ids.warehouseId,
      );

      expect(await context.purchaseRequestStatusOf('pr-shipped'), 'shipped');
      expect(await context.purchaseRequestStatusOf('pr-closed'), 'closed');
    });

    test('draft tidak boleh membawa submitted_at', () async {
      final ids = await seedMinimum();

      expect(
        () => insertHeader(
          id: 'pr-bad-draft',
          branchId: ids.branchId,
          requestedBy: ids.headId,
          status: 'draft',
          submittedAt: '2026-07-29T04:00:00.000Z',
        ),
        throwsA(anything),
      );
    });

    test('submitted wajib membawa submitted_at', () async {
      final ids = await seedMinimum();

      expect(
        () => insertHeader(
          id: 'pr-bad-submitted',
          branchId: ids.branchId,
          requestedBy: ids.headId,
          status: 'submitted',
        ),
        throwsA(anything),
      );
    });

    test('processing wajib membawa processing_at dan processed_by', () async {
      final ids = await seedMinimum();

      expect(
        () => insertHeader(
          id: 'pr-bad-processing',
          branchId: ids.branchId,
          requestedBy: ids.headId,
          status: 'processing',
          submittedAt: '2026-07-29T04:00:00.000Z',
          processingAt: '2026-07-29T05:00:00.000Z',
        ),
        throwsA(anything),
        reason: 'processing_at tanpa processed_by harus ditolak.',
      );
    });

    test('rejected wajib membawa alasan yang tidak kosong', () async {
      final ids = await seedMinimum();

      // Missing reason.
      expect(
        () => insertHeader(
          id: 'pr-bad-reject-1',
          branchId: ids.branchId,
          requestedBy: ids.headId,
          status: 'rejected',
          submittedAt: '2026-07-29T04:00:00.000Z',
          processingAt: '2026-07-29T05:00:00.000Z',
          processedBy: ids.warehouseId,
          rejectedAt: '2026-07-29T06:00:00.000Z',
          rejectedBy: ids.warehouseId,
        ),
        throwsA(anything),
      );

      // Whitespace-only reason — `trim(...) <> ''` is what catches this, and it is
      // why the rule cannot be bypassed by raw SQL.
      expect(
        () => insertHeader(
          id: 'pr-bad-reject-2',
          branchId: ids.branchId,
          requestedBy: ids.headId,
          status: 'rejected',
          submittedAt: '2026-07-29T04:00:00.000Z',
          processingAt: '2026-07-29T05:00:00.000Z',
          processedBy: ids.warehouseId,
          rejectedAt: '2026-07-29T06:00:00.000Z',
          rejectedBy: ids.warehouseId,
          rejectReason: '   ',
        ),
        throwsA(anything),
      );
    });

    test('cancelled wajib membawa alasan yang tidak kosong', () async {
      final ids = await seedMinimum();

      expect(
        () => insertHeader(
          id: 'pr-bad-cancel',
          branchId: ids.branchId,
          requestedBy: ids.headId,
          status: 'cancelled',
          cancelledAt: '2026-07-29T06:00:00.000Z',
          cancelledBy: ids.headId,
          cancelReason: '  ',
        ),
        throwsA(anything),
      );

      // A draft cancelled before it was ever sent carries no submitted_at, and that
      // is the one status for which the absence is legitimate.
      await insertHeader(
        id: 'pr-cancelled-draft',
        branchId: ids.branchId,
        requestedBy: ids.headId,
        status: 'cancelled',
        cancelledAt: '2026-07-29T06:00:00.000Z',
        cancelledBy: ids.headId,
        cancelReason: 'Tidak dibutuhkan lagi',
      );
      expect(
        await context.purchaseRequestStatusOf('pr-cancelled-draft'),
        'cancelled',
      );
    });

    test('pemroses tidak boleh sama dengan pemohon (G-R4)', () async {
      final ids = await seedMinimum();

      expect(
        () => insertHeader(
          id: 'pr-self-process',
          branchId: ids.branchId,
          requestedBy: ids.headId,
          status: 'processing',
          submittedAt: '2026-07-29T04:00:00.000Z',
          processingAt: '2026-07-29T05:00:00.000Z',
          processedBy: ids.headId,
        ),
        throwsA(anything),
      );
    });

    test(
      'tidak ada CHECK perbandingan timestamp leksikal pada purchase_requests',
      () async {
        final sql = await ddlOf('purchase_requests');

        // Timestamps are ISO-8601 TEXT, so `>=` between two of them orders
        // characters rather than instants (§8.1). Ordering is
        // `DocumentTimestampPolicy`'s, on UTC DateTime values.
        expect(sql, isNot(contains('processing_at >= submitted_at')));
        expect(sql, isNot(contains('rejected_at >= processing_at')));
        expect(sql, isNot(contains('cancelled_at >= submitted_at')));
        expect(sql, isNot(contains('submitted_at <= processing_at')));
      },
    );
  });

  group('constraint kuantitas', () {
    test(
      'requested_qty harus lebih dari 0 dan suggested_qty tidak negatif',
      () async {
        final sql = await ddlOf('purchase_request_lines');

        expect(sql, contains('CHECK (requested_qty > 0)'));
        expect(sql, contains('CHECK (suggested_qty >= 0)'));
      },
    );

    test('requested_qty nol ditolak database', () async {
      final ids = await seedMinimum();
      await insertHeader(
        id: 'pr-qty',
        branchId: ids.branchId,
        requestedBy: ids.headId,
        status: 'draft',
      );

      expect(
        () => context.database.customStatement(
          'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
          'sync_status, pr_id, item_id, suggested_qty, requested_qty) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
          [
            'prl-zero',
            '2026-07-29T03:00:00.000Z',
            '2026-07-29T03:00:00.000Z',
            'pending',
            'pr-qty',
            ids.itemId,
            0,
            0,
          ],
        ),
        throwsA(anything),
      );
    });

    test('milli-unit tersimpan sebagai integer terskala', () async {
      final ids = await seedMinimum();
      await insertHeader(
        id: 'pr-scale',
        branchId: ids.branchId,
        requestedBy: ids.headId,
        status: 'draft',
      );
      await context.database.customStatement(
        'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
        'sync_status, pr_id, item_id, suggested_qty, requested_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'prl-scale',
          '2026-07-29T03:00:00.000Z',
          '2026-07-29T03:00:00.000Z',
          'pending',
          'pr-scale',
          ids.itemId,
          Quantity.parse('2.5').milliUnits,
          Quantity.parse('6.375').milliUnits,
        ],
      );

      final row = await context.database
          .customSelect(
            'SELECT suggested_qty, requested_qty FROM purchase_request_lines '
            "WHERE id = 'prl-scale';",
          )
          .getSingle();
      expect(row.read<int>('suggested_qty'), 2500);
      expect(row.read<int>('requested_qty'), 6375);
    });
  });

  group('index', () {
    test('seluruh index query tersedia', () async {
      final names = await indexNames();

      expect(
        names,
        containsAll(<String>[
          'idx_purchase_requests_branch_status',
          'idx_purchase_requests_requested_by_status',
          'idx_purchase_requests_created_at',
          'idx_purchase_requests_needed_date',
          'idx_purchase_request_opnames_pr',
          'idx_purchase_request_opnames_opname',
          'idx_purchase_request_lines_pr',
          'idx_purchase_request_lines_item',
        ]),
      );
    });

    test('index unik parsial memakai deleted_at IS NULL', () async {
      for (final name in [
        'idx_purchase_requests_doc_number',
        'idx_purchase_request_opnames_unique',
        'idx_purchase_request_lines_item_unique',
      ]) {
        final sql = await indexSql(name);
        expect(sql, contains('UNIQUE'));
        expect(
          sql,
          contains('deleted_at IS NULL'),
          reason:
              '$name harus parsial: keunikan berlaku untuk baris hidup saja, '
              'agar baris yang dihapus dari draft tidak memblokir posisi itu.',
        );
      }
    });

    test('index active PR per cabang adalah unik dan parsial (G-P4)', () async {
      final sql = await indexSql('idx_purchase_requests_active_branch');

      expect(sql, contains('UNIQUE'));
      expect(sql, contains('purchase_requests (branch_id)'));
      expect(sql, contains("status IN ('submitted', 'processing')"));
      expect(sql, contains('deleted_at IS NULL'));
    });

    test('satu item hanya satu baris hidup per PR (G-P2)', () async {
      final ids = await seedMinimum();
      await insertHeader(
        id: 'pr-dup',
        branchId: ids.branchId,
        requestedBy: ids.headId,
        status: 'draft',
      );

      Future<void> insertLine(String id) => context.database.customStatement(
        'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
        'sync_status, pr_id, item_id, suggested_qty, requested_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          '2026-07-29T03:00:00.000Z',
          '2026-07-29T03:00:00.000Z',
          'pending',
          'pr-dup',
          ids.itemId,
          0,
          1000,
        ],
      );

      await insertLine('prl-1');
      expect(() => insertLine('prl-2'), throwsA(anything));

      // Soft-deleting the first line releases the position, which is exactly what
      // the partial clause is for.
      await context.database.customStatement(
        "UPDATE purchase_request_lines SET deleted_at = ? WHERE id = 'prl-1';",
        ['2026-07-29T07:00:00.000Z'],
      );
      await insertLine('prl-3');

      expect(await context.purchaseRequestLineCount('pr-dup'), 1);
    });
  });

  group('integritas referensial', () {
    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await seedMinimum();

      final pragma = await context.database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      final violations = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });

    test('foreign key PR mengarah ke tabel yang benar', () async {
      Future<Map<String, String>> keysOf(String table) async {
        final rows = await context.database
            .customSelect('PRAGMA foreign_key_list($table);')
            .get();
        return {
          for (final row in rows)
            row.read<String>('from'): row.read<String>('table'),
        };
      }

      expect(await keysOf('purchase_requests'), {
        'branch_id': 'branches',
        'requested_by': 'users',
        'processed_by': 'users',
        'cancelled_by': 'users',
        'rejected_by': 'users',
      });
      expect(await keysOf('purchase_request_opnames'), {
        'pr_id': 'purchase_requests',
        'opname_id': 'stock_opnames',
      });
      expect(await keysOf('purchase_request_lines'), {
        'pr_id': 'purchase_requests',
        'item_id': 'items',
      });
    });

    test(
      'PR tidak memiliki kolom batch (batch dipilih Warehouse saat DO)',
      () async {
        final rows = await context.database
            .customSelect('PRAGMA table_xinfo(purchase_request_lines);')
            .get();
        final names = rows.map((row) => row.read<String>('name')).toSet();

        expect(
          names.contains('batch_id'),
          isFalse,
          reason:
              'PR meminta barang, bukan batch. Pemilihan batch adalah keputusan '
              'FEFO Warehouse pada Delivery Order (G-E3).',
        );
      },
    );
  });
}
