import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Schema v7 as a **fresh** database gets it (§38).
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
    test('dua tabel Good Receipt tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'good_receipt%';",
          )
          .get();

      expect(rows.map((row) => row.read<String>('name')).toSet(), {
        'good_receipts',
        'good_receipt_lines',
      });
    });

    test('kolom kuantitas bertipe INTEGER, bukan REAL', () async {
      // Q-3. A REAL column would reintroduce exactly the rounding drift `Quantity`
      // exists to prevent, and it would do so silently: `0.1 + 0.2` would still
      // *look* like `0.3` in most rows.
      expect(await columnType('good_receipt_lines', 'shipped_qty'), 'INTEGER');
      expect(await columnType('good_receipt_lines', 'received_qty'), 'INTEGER');

      final sql = await tableSql('good_receipt_lines');
      expect(sql, isNot(contains('REAL')));
    });

    test('kolom standar dan kolom bisnis lengkap', () async {
      for (final column in [
        'id',
        'created_at',
        'updated_at',
        'deleted_at',
        'sync_status',
        'doc_number',
        'do_id',
        'received_by',
        'status',
        'posted_at',
      ]) {
        expect(
          await columnType('good_receipts', column),
          isNotEmpty,
          reason: 'good_receipts.$column tidak ada.',
        );
      }
      for (final column in [
        'id',
        'created_at',
        'updated_at',
        'deleted_at',
        'sync_status',
        'gr_id',
        'do_line_id',
        'item_id',
        'batch_id',
        'shipped_qty',
        'received_qty',
        'line_status',
        'reject_reason',
      ]) {
        expect(
          await columnType('good_receipt_lines', column),
          isNotEmpty,
          reason: 'good_receipt_lines.$column tidak ada.',
        );
      }
    });

    test('foreign key mengarah ke tabel yang benar', () async {
      expect(await foreignKeys('good_receipts'), {
        'do_id': 'delivery_orders',
        'received_by': 'users',
      });
      expect(await foreignKeys('good_receipt_lines'), {
        'gr_id': 'good_receipts',
        'do_line_id': 'delivery_order_lines',
        'item_id': 'items',
        'batch_id': 'item_batches',
      });
    });

    test('tidak ada perbandingan timestamp leksikal', () async {
      // Timestamps are ISO-8601 TEXT, so `posted_at >= created_at` in SQL compares
      // characters rather than instants — the bug schema v4 removed from
      // `stock_opnames`. Ordering is `DocumentTimestampPolicy`'s, on UTC DateTimes.
      final sql = await tableSql('good_receipts');
      expect(sql, isNot(contains('posted_at >= created_at')));
      expect(sql, isNot(contains('posted_at >=')));
    });

    test('tidak ada kolom selisih tersimpan', () async {
      // `shipped_qty - received_qty` is derivable, and a stored copy would be a
      // second version of the same fact that a writer could contradict.
      final sql = await tableSql('good_receipt_lines');
      expect(sql, isNot(contains('discrepancy')));
    });
  });

  group('index', () {
    test('seluruh index Good Receipt dibuat', () async {
      expect(await indexNames('good_receipt'), {
        'idx_good_receipts_received_by_status',
        'idx_good_receipts_status_created',
        'idx_good_receipts_posted_at',
        'idx_good_receipts_do',
        'idx_good_receipts_doc_number',
        'idx_good_receipt_lines_gr',
        'idx_good_receipt_lines_do_line',
        'idx_good_receipt_lines_item',
        'idx_good_receipt_lines_batch',
        'idx_good_receipt_lines_status',
        'idx_good_receipt_lines_unique',
      });
    });

    test('index satu DO satu GR bersifat unik dan tanpa klausa WHERE', () async {
      // G-G1's database half. A partial `WHERE deleted_at IS NULL` would let a
      // soft-deleted receipt be followed by a second one for the same shipment, and
      // posting that second receipt would credit the branch twice from one delivery.
      final row = await context.database
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'idx_good_receipts_do';",
          )
          .getSingle();
      final sql = row.read<String>('sql');

      expect(sql, contains('UNIQUE'));
      expect(sql, contains('(do_id)'));
      expect(
        sql,
        isNot(contains('WHERE')),
        reason:
            'Index parsial akan mengizinkan GR kedua setelah soft delete, '
            'sehingga stok cabang bertambah dua kali dari satu pengiriman.',
      );
    });

    test('index satu baris DO satu baris GR unik tanpa WHERE', () async {
      final row = await context.database
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE name = 'idx_good_receipt_lines_unique';",
          )
          .getSingle();
      final sql = row.read<String>('sql');

      expect(sql, contains('UNIQUE'));
      expect(sql, contains('gr_id'));
      expect(sql, contains('do_line_id'));
      expect(sql, isNot(contains('WHERE')));
    });

    test('index nomor dokumen unik hanya untuk baris hidup', () async {
      final row = await context.database
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE name = 'idx_good_receipts_doc_number';",
          )
          .getSingle();
      final sql = row.read<String>('sql');

      expect(sql, contains('UNIQUE'));
      expect(sql, contains('deleted_at IS NULL'));
    });
  });

  group('constraint status', () {
    /// A shipment to hang receipts off, written directly so the CHECKs are exercised
    /// without the whole workflow in the way.
    Future<void> seedShipment() async {
      final fixture = await buildDeliveryFixture(
        context,
        nowUtc: fixedWednesdayUtc(),
      );
      await context.database.customStatement(
        'INSERT INTO delivery_orders (id, created_at, updated_at, sync_status, '
        'doc_number, pr_id, prepared_by, status, shipped_at, shipped_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'do-1',
          '2026-07-29T03:00:00.000Z',
          '2026-07-29T03:00:00.000Z',
          'pending',
          'TMP-DO-do-1',
          fixture.purchaseRequestId,
          fixture.warehouseUser.id,
          'shipped',
          '2026-07-29T04:00:00.000Z',
          fixture.warehouseUser.id,
        ],
      );
      await context.database.customStatement(
        'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
        'sync_status, do_id, pr_line_id, item_id, shipped_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'dol-1',
          '2026-07-29T03:00:00.000Z',
          '2026-07-29T03:00:00.000Z',
          'pending',
          'do-1',
          fixture.simpleLineId,
          fixture.simpleItem.id,
          Quantity.parse('2').milliUnits,
        ],
      );
      _headId = fixture.branchHead.id;
      _itemId = fixture.simpleItem.id;
    }

    Future<void> insertReceipt({
      required String id,
      required String status,
      String? postedAt,
      String doId = 'do-1',
    }) => context.database.customStatement(
      'INSERT INTO good_receipts (id, created_at, updated_at, sync_status, '
      'doc_number, do_id, received_by, status, posted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-29T05:00:00.000Z',
        '2026-07-29T05:00:00.000Z',
        'pending',
        'TMP-GR-$id',
        doId,
        _headId,
        status,
        postedAt,
      ],
    );

    test('status di luar enum ditolak', () async {
      await seedShipment();
      // Defence in depth behind the type converter: a hand-written UPDATE cannot
      // introduce a status the Dart enum does not know.
      expect(
        () => insertReceipt(id: 'bad', status: 'cancelled'),
        throwsA(anything),
      );
      expect(
        () => insertReceipt(id: 'bad2', status: 'draft'),
        throwsA(anything),
      );
    });

    test('checking wajib tanpa posted_at, posted wajib dengan', () async {
      await seedShipment();

      expect(
        () => insertReceipt(
          id: 'bad-checking',
          status: 'checking',
          postedAt: '2026-07-29T06:00:00.000Z',
        ),
        throwsA(anything),
      );
      expect(
        () => insertReceipt(id: 'bad-posted', status: 'posted'),
        throwsA(anything),
      );

      await insertReceipt(id: 'gr-1', status: 'checking');
      await context.database.customStatement(
        'DELETE FROM good_receipts WHERE id = ?;',
        ['gr-1'],
      );
      await insertReceipt(
        id: 'gr-1',
        status: 'posted',
        postedAt: '2026-07-29T06:00:00.000Z',
      );
    });

    test('satu DO hanya boleh punya satu GR', () async {
      await seedShipment();
      await insertReceipt(id: 'gr-1', status: 'checking');

      expect(
        () => insertReceipt(id: 'gr-2', status: 'checking'),
        throwsA(anything),
        reason: 'G-G1: 1 DO = 1 GR.',
      );
    });

    test('GR kedua tetap ditolak setelah GR pertama di-soft-delete', () async {
      await seedShipment();
      await insertReceipt(id: 'gr-1', status: 'checking');
      await context.database.customStatement(
        'UPDATE good_receipts SET deleted_at = ? WHERE id = ?;',
        ['2026-07-29T07:00:00.000Z', 'gr-1'],
      );

      // This is the whole reason the index is not partial: a soft delete must not
      // free the shipment for a second receipt.
      expect(
        () => insertReceipt(id: 'gr-2', status: 'checking'),
        throwsA(anything),
      );
    });
  });

  group('constraint baris', () {
    setUp(() async {
      final fixture = await buildDeliveryFixture(
        context,
        nowUtc: fixedWednesdayUtc(),
      );
      _headId = fixture.branchHead.id;
      _itemId = fixture.simpleItem.id;

      await context.database.customStatement(
        'INSERT INTO delivery_orders (id, created_at, updated_at, sync_status, '
        'doc_number, pr_id, prepared_by, status, shipped_at, shipped_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'do-1',
          '2026-07-29T03:00:00.000Z',
          '2026-07-29T03:00:00.000Z',
          'pending',
          'TMP-DO-do-1',
          fixture.purchaseRequestId,
          fixture.warehouseUser.id,
          'shipped',
          '2026-07-29T04:00:00.000Z',
          fixture.warehouseUser.id,
        ],
      );
      for (final lineId in ['dol-1', 'dol-2']) {
        await context.database.customStatement(
          'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
          'sync_status, do_id, pr_line_id, item_id, shipped_qty) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
          [
            lineId,
            '2026-07-29T03:00:00.000Z',
            '2026-07-29T03:00:00.000Z',
            'pending',
            'do-1',
            lineId == 'dol-1' ? fixture.simpleLineId : fixture.scarceLineId,
            lineId == 'dol-1' ? fixture.simpleItem.id : fixture.scarceItem.id,
            2000,
          ],
        );
      }
      await context.database.customStatement(
        'INSERT INTO good_receipts (id, created_at, updated_at, sync_status, '
        'doc_number, do_id, received_by, status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'gr-1',
          '2026-07-29T05:00:00.000Z',
          '2026-07-29T05:00:00.000Z',
          'pending',
          'TMP-GR-gr-1',
          'do-1',
          fixture.branchHead.id,
          'checking',
        ],
      );
    });

    Future<void> insertLine({
      required String id,
      String doLineId = 'dol-1',
      int shipped = 2000,
      int received = 2000,
      String lineStatus = 'pending',
      String? rejectReason,
    }) => context.database.customStatement(
      'INSERT INTO good_receipt_lines (id, created_at, updated_at, sync_status, '
      'gr_id, do_line_id, item_id, shipped_qty, received_qty, line_status, '
      'reject_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-29T05:00:00.000Z',
        '2026-07-29T05:00:00.000Z',
        'pending',
        'gr-1',
        doLineId,
        _itemId,
        shipped,
        received,
        lineStatus,
        rejectReason,
      ],
    );

    test('shipped_qty harus positif', () async {
      expect(() => insertLine(id: 'zero', shipped: 0), throwsA(anything));
      expect(() => insertLine(id: 'neg', shipped: -1000), throwsA(anything));
    });

    test('received_qty tidak boleh negatif', () async {
      expect(() => insertLine(id: 'neg', received: -1), throwsA(anything));
    });

    test('received_qty tidak boleh melebihi shipped_qty', () async {
      // G-G3's upper bound, in SQL as well as in the policy: this is what stops a
      // hand-written UPDATE receiving more than was sent.
      expect(
        () => insertLine(id: 'over', shipped: 2000, received: 2001),
        throwsA(anything),
      );
      await insertLine(id: 'exact', shipped: 2000, received: 2000);
    });

    test('line_status di luar enum ditolak', () async {
      expect(
        () => insertLine(id: 'bad', lineStatus: 'removed'),
        throwsA(anything),
      );
    });

    test('pending dan checked tidak boleh menyimpan alasan', () async {
      expect(
        () => insertLine(id: 'p', lineStatus: 'pending', rejectReason: 'Rusak'),
        throwsA(anything),
      );
      expect(
        () => insertLine(id: 'c', lineStatus: 'checked', rejectReason: 'Rusak'),
        throwsA(anything),
      );
    });

    test('rejected wajib beralasan, nol, dan bukan spasi', () async {
      // G-G4, all three halves. `trim(NULL) <> ''` is NULL rather than true, which is
      // what makes a missing reason fail here as well as whitespace.
      expect(
        () => insertLine(id: 'no-reason', lineStatus: 'rejected', received: 0),
        throwsA(anything),
      );
      expect(
        () => insertLine(
          id: 'blank',
          lineStatus: 'rejected',
          received: 0,
          rejectReason: '   ',
        ),
        throwsA(anything),
      );
      expect(
        () => insertLine(
          id: 'with-qty',
          lineStatus: 'rejected',
          received: 500,
          rejectReason: 'Rusak',
        ),
        throwsA(anything),
      );
      await insertLine(
        id: 'ok',
        lineStatus: 'rejected',
        received: 0,
        rejectReason: 'Rusak',
      );
    });

    test('checked boleh menerima kurang, termasuk nol', () async {
      await insertLine(
        id: 'short',
        lineStatus: 'checked',
        shipped: 2000,
        received: 500,
      );
      await insertLine(
        id: 'zero',
        doLineId: 'dol-2',
        lineStatus: 'checked',
        shipped: 2000,
        received: 0,
      );
    });

    test('satu baris DO hanya boleh satu baris GR', () async {
      await insertLine(id: 'first');
      expect(
        () => insertLine(id: 'second'),
        throwsA(anything),
        reason: 'Snapshot harus satu banding satu dengan alokasi Surat Jalan.',
      );
      // A different allocation is fine.
      await insertLine(id: 'other', doLineId: 'dol-2');
    });

    test('foreign key aktif dan tidak ada pelanggaran', () async {
      await insertLine(id: 'ok');

      final pragma = await context.database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      final violations = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });
  });
}

/// Shared between the two constraint groups, which each seed their own shipment.
String _headId = '';
String _itemId = '';
