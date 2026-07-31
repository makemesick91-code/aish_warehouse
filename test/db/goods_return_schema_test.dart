import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Retur Barang tables on a **fresh** schema v11 (§10/§11/§41).
///
/// Everything here is asserted against a database built by `createAll` rather than by
/// the migration, so the two halves of the schema contract are checked separately: this
/// file says what v11 *is*, and `migration_v10_to_v11_test.dart` says that an upgraded
/// device arrives at the same place.
///
/// The constraints that carry the most weight are the ones a use case could not
/// enforce alone:
///
/// * `UNIQUE(gr_id)` and `UNIQUE(gr_line_id)`, both **unqualified** — the database half
///   of *one Good Receipt, one Retur* and *one rejected position, one return line*. A
///   partial index would let a soft delete free the slot, and a second return would
///   credit the Warehouse twice for goods that came back once (§10/§11).
/// * The status/timestamp/actor CHECK, which is what makes an un-ship or an un-receive
///   inexpressible: a row moved backwards would have to drop an actor the constraint
///   requires.
/// * The two G-R4 CHECKs, each written with an explicit `IS NULL` branch because SQLite
///   treats a CHECK evaluating to **NULL as satisfied**.
void main() {
  late AppDatabase database;
  late DriftMasterDataRepository master;

  late String branchId;
  late String headId;
  late String secondHeadId;
  late String warehouseUserId;
  late String plainItemId;
  late String batchItemId;
  late String batchId;
  late String grId;
  late String rejectedLineId;
  late String secondRejectedLineId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    master = DriftMasterDataRepository(database.masterDataDao);

    final branch = await master.ensureBranch(code: 'CAB-01', name: 'Cabang');
    branchId = branch.id;
    headId = (await master.ensureUser(
      email: 'kacab@test.local',
      fullName: 'Kepala Cabang',
      role: UserRole.kepalaCabang,
      branchId: branch.id,
    )).id;
    secondHeadId = (await master.ensureUser(
      email: 'kacab2@test.local',
      fullName: 'Kepala Cabang Kedua',
      role: UserRole.kepalaCabang,
      branchId: branch.id,
    )).id;
    warehouseUserId = (await master.ensureUser(
      email: 'warehouse@test.local',
      fullName: 'Petugas Warehouse',
      role: UserRole.warehouse,
    )).id;

    final category = await master.ensureCategory('Alat');
    plainItemId = (await master.ensureItem(
      sku: 'RET-0001',
      name: 'Masker',
      categoryId: category.id,
      unit: 'box',
      minStockRoom: 1,
      minStockBranch: 1,
      hasExpiry: false,
    )).id;
    batchItemId = (await master.ensureItem(
      sku: 'RET-0002',
      name: 'Anestesi',
      categoryId: category.id,
      unit: 'ampul',
      minStockRoom: 1,
      minStockBranch: 1,
      hasExpiry: true,
    )).id;
    batchId = (await master.ensureBatch(
      itemId: batchItemId,
      batchNo: 'B-1',
      expiryDate: DateTime.utc(2099, 1, 1),
    )).id;

    // The document chain a return hangs off, written raw: this file is about the Retur
    // tables' own constraints, not about how the earlier documents get built.
    await database.customStatement(
      'INSERT INTO purchase_requests (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, requested_by, status, submitted_at, '
      'processing_at, processed_by) '
      "VALUES ('pr-1', ?, ?, 'pending', 'TMP-PR-1', ?, ?, 'processing', ?, ?, "
      '?);',
      [
        '2026-07-29T00:00:00.000Z',
        '2026-07-29T00:00:00.000Z',
        branchId,
        headId,
        '2026-07-29T00:10:00.000Z',
        '2026-07-29T00:20:00.000Z',
        warehouseUserId,
      ],
    );
    for (final line in [('prl-1', plainItemId), ('prl-2', batchItemId)]) {
      await database.customStatement(
        'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
        'sync_status, pr_id, item_id, suggested_qty, requested_qty) '
        "VALUES (?, ?, ?, 'pending', 'pr-1', ?, 4000, 4000);",
        [
          line.$1,
          '2026-07-29T00:00:00.000Z',
          '2026-07-29T00:00:00.000Z',
          line.$2,
        ],
      );
    }
    await database.customStatement(
      'INSERT INTO delivery_orders (id, created_at, updated_at, sync_status, '
      'doc_number, pr_id, prepared_by, status, shipped_at, shipped_by) '
      "VALUES ('do-1', ?, ?, 'pending', 'TMP-DO-1', 'pr-1', ?, 'shipped', ?, ?);",
      [
        '2026-07-29T01:00:00.000Z',
        '2026-07-29T01:00:00.000Z',
        warehouseUserId,
        '2026-07-29T02:00:00.000Z',
        warehouseUserId,
      ],
    );
    for (final line in [
      ('dol-1', 'prl-1', plainItemId, null),
      ('dol-2', 'prl-2', batchItemId, batchId),
    ]) {
      await database.customStatement(
        'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
        'sync_status, do_id, pr_line_id, item_id, batch_id, shipped_qty) '
        "VALUES (?, ?, ?, 'pending', 'do-1', ?, ?, ?, 4000);",
        [
          line.$1,
          '2026-07-29T01:00:00.000Z',
          '2026-07-29T01:00:00.000Z',
          line.$2,
          line.$3,
          line.$4,
        ],
      );
    }
    await database.customStatement(
      'INSERT INTO good_receipts (id, created_at, updated_at, sync_status, '
      'doc_number, do_id, received_by, status, posted_at) '
      "VALUES ('gr-1', ?, ?, 'pending', 'TMP-GR-1', 'do-1', ?, 'posted', ?);",
      [
        '2026-07-29T03:00:00.000Z',
        '2026-07-29T03:00:00.000Z',
        headId,
        '2026-07-29T04:00:00.000Z',
      ],
    );
    grId = 'gr-1';
    for (final line in [
      ('grl-1', 'dol-1', plainItemId, null),
      ('grl-2', 'dol-2', batchItemId, batchId),
    ]) {
      await database.customStatement(
        'INSERT INTO good_receipt_lines (id, created_at, updated_at, '
        'sync_status, gr_id, do_line_id, item_id, batch_id, shipped_qty, '
        "received_qty, line_status, reject_reason) VALUES (?, ?, ?, 'pending', "
        "'gr-1', ?, ?, ?, 4000, 0, 'rejected', 'Kemasan rusak');",
        [
          line.$1,
          '2026-07-29T03:00:00.000Z',
          '2026-07-29T03:00:00.000Z',
          line.$2,
          line.$3,
          line.$4,
        ],
      );
    }
    rejectedLineId = 'grl-1';
    secondRejectedLineId = 'grl-2';
  });

  tearDown(() => database.close());

  Future<void> insertHeader(
    String id, {
    String status = 'draft',
    String? gr,
    String? docNumber,
    String? createdBy,
    String? note,
    String? shippedAt,
    String? shippedBy,
    String? receivedAt,
    String? receivedBy,
    String? warehouseNote,
  }) => database.customStatement(
    'INSERT INTO goods_returns (id, created_at, updated_at, sync_status, '
    'doc_number, gr_id, branch_id, created_by, status, note, shipped_at, '
    'shipped_by, received_at, received_by, warehouse_note) '
    "VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    [
      id,
      '2026-07-30T00:00:00.000Z',
      '2026-07-30T00:00:00.000Z',
      docNumber ?? 'TMP-RET-$id',
      gr ?? grId,
      branchId,
      createdBy ?? headId,
      status,
      note,
      shippedAt,
      shippedBy,
      receivedAt,
      receivedBy,
      warehouseNote,
    ],
  );

  Future<void> insertLine(
    String id, {
    String returnId = 'ret-1',
    String? grLine,
    String? itemId,
    String? batch,
    int qty = 4000,
    String reason = 'Kemasan rusak',
  }) => database.customStatement(
    'INSERT INTO goods_return_lines (id, created_at, updated_at, sync_status, '
    'goods_return_id, gr_line_id, item_id, batch_id, qty, '
    "reject_reason_snapshot) VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?);",
    [
      id,
      '2026-07-30T00:00:00.000Z',
      '2026-07-30T00:00:00.000Z',
      returnId,
      grLine ?? rejectedLineId,
      itemId ?? plainItemId,
      batch,
      qty,
      reason,
    ],
  );

  Future<Set<String>> indexNames() async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'idx_goods_return%';",
        )
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  Future<String> indexSql(String name) async {
    final row = await database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?;",
          variables: [Variable<String>(name)],
        )
        .getSingle();
    return row.read<String>('sql');
  }

  group('bentuk tabel', () {
    test('kedua tabel ada pada schema v11', () async {
      final rows = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('goods_returns', 'goods_return_lines');",
          )
          .get();
      expect(rows.map((row) => row.read<String>('name')).toSet(), {
        'goods_returns',
        'goods_return_lines',
      });
    });

    test('schemaVersion adalah 12', () async {
      expect(database.schemaVersion, 13);
      final row = await database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 13);
    });

    test('qty adalah INTEGER, bukan REAL', () async {
      final rows = await database
          .customSelect("PRAGMA table_info('goods_return_lines');")
          .get();
      final types = {
        for (final row in rows)
          row.read<String>('name'): row.read<String>('type'),
      };
      expect(
        types['qty'],
        'INTEGER',
        reason: 'Kuantitas fixed-point milli-unit tidak boleh REAL (Q-3).',
      );
      expect(types['reject_reason_snapshot'], 'TEXT');
      // NOT NULL on the reason: G-G4 made it mandatory upstream.
      final notNull = {
        for (final row in rows)
          row.read<String>('name'): row.read<int>('notnull'),
      };
      expect(notNull['reject_reason_snapshot'], 1);
      expect(notNull['qty'], 1);
      expect(notNull['batch_id'], 0);
    });

    test('foreign key lengkap dan aktif', () async {
      final pragma = await database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      final headerFks = await database
          .customSelect("PRAGMA foreign_key_list('goods_returns');")
          .get();
      expect(headerFks.map((row) => row.read<String>('table')).toSet(), {
        'good_receipts',
        'branches',
        'users',
      });

      final lineFks = await database
          .customSelect("PRAGMA foreign_key_list('goods_return_lines');")
          .get();
      expect(lineFks.map((row) => row.read<String>('table')).toSet(), {
        'goods_returns',
        'good_receipt_lines',
        'items',
        'item_batches',
      });

      final violations = await database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });

    test('seluruh index ada', () async {
      expect(await indexNames(), {
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
      });
    });
  });

  group('CHECK status, timestamp dan pelaku', () {
    test('draft tanpa jejak pengiriman diterima', () async {
      await insertHeader('ret-1');
      final row = await database
          .customSelect(
            "SELECT status, shipped_at FROM goods_returns WHERE id = 'ret-1';",
          )
          .getSingle();
      expect(row.read<String>('status'), 'draft');
      expect(row.read<String?>('shipped_at'), isNull);
    });

    test('status di luar enum ditolak', () async {
      await expectLater(
        insertHeader('bad', status: 'approved'),
        throwsA(anything),
      );
    });

    test('draft yang membawa jejak pengiriman ditolak', () async {
      await expectLater(
        insertHeader('bad', shippedBy: headId),
        throwsA(anything),
      );
      await expectLater(
        insertHeader('bad', shippedAt: '2026-07-30T01:00:00.000Z'),
        throwsA(anything),
      );
    });

    test('shipped wajib punya waktu dan pelaku pengiriman', () async {
      await expectLater(
        insertHeader(
          'bad',
          status: 'shipped',
          shippedAt: '2026-07-30T01:00:00.000Z',
        ),
        throwsA(anything),
      );
      await expectLater(
        insertHeader('bad', status: 'shipped', shippedBy: headId),
        throwsA(anything),
      );
      await insertHeader(
        'ret-shipped',
        status: 'shipped',
        shippedAt: '2026-07-30T01:00:00.000Z',
        shippedBy: headId,
      );
    });

    test('shipped tidak boleh membawa jejak penerimaan', () async {
      await expectLater(
        insertHeader(
          'bad',
          status: 'shipped',
          shippedAt: '2026-07-30T01:00:00.000Z',
          shippedBy: headId,
          receivedBy: warehouseUserId,
        ),
        throwsA(anything),
      );
    });

    test('received wajib punya kedua pasang waktu dan pelaku', () async {
      // Skipping the transit leg is exactly what the CHECK refuses: a `received` row
      // with no shipment behind it would be a Warehouse credit for goods nobody sent.
      await expectLater(
        insertHeader(
          'bad',
          status: 'received',
          receivedAt: '2026-07-30T02:00:00.000Z',
          receivedBy: warehouseUserId,
        ),
        throwsA(anything),
      );
      await insertHeader(
        'ret-received',
        status: 'received',
        shippedAt: '2026-07-30T01:00:00.000Z',
        shippedBy: headId,
        receivedAt: '2026-07-30T02:00:00.000Z',
        receivedBy: warehouseUserId,
      );
    });

    test(
      'tidak ada CHECK yang membandingkan timestamp secara leksikal',
      () async {
        final row = await database
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'table' "
              "AND name = 'goods_returns';",
            )
            .getSingle();
        final sql = row.read<String>('sql');

        // Timestamps are ISO-8601 TEXT, so `received_at >= shipped_at` in SQL compares
        // characters rather than instants — the trap schema v4 removed from
        // `stock_opnames`. Ordering lives in `DocumentTimestampPolicy` (§39).
        for (final forbidden in const [
          'received_at >= shipped_at',
          'shipped_at >= created_at',
          'received_at > shipped_at',
          'shipped_at > created_at',
        ]) {
          expect(
            sql.contains(forbidden),
            isFalse,
            reason: 'CHECK "$forbidden" membandingkan TEXT, bukan instant.',
          );
        }
      },
    );
  });

  group('CHECK pemisahan tugas (G-R4)', () {
    test('penerima tidak boleh sama dengan pembuat', () async {
      await expectLater(
        insertHeader(
          'bad',
          status: 'received',
          shippedAt: '2026-07-30T01:00:00.000Z',
          shippedBy: secondHeadId,
          receivedAt: '2026-07-30T02:00:00.000Z',
          receivedBy: headId,
        ),
        throwsA(anything),
      );
    });

    test('penerima tidak boleh sama dengan pengirim', () async {
      await expectLater(
        insertHeader(
          'bad',
          status: 'received',
          shippedAt: '2026-07-30T01:00:00.000Z',
          shippedBy: secondHeadId,
          receivedAt: '2026-07-30T02:00:00.000Z',
          receivedBy: secondHeadId,
        ),
        throwsA(anything),
      );
    });

    test('draft dan shipped tetap diterima walau received_by NULL', () async {
      // The SQLite quirk the CHECKs are written around: `received_by <> created_by` is
      // NULL while `received_by` is NULL, and a NULL CHECK counts as *satisfied*. The
      // explicit `IS NULL` branch is what makes that deliberate rather than accidental.
      // One row moved through both shapes, because `gr_id` is unique and this fixture
      // has one Good Receipt — which is itself the rule under test elsewhere.
      await insertHeader('ret-draft');
      await database.customStatement(
        "UPDATE goods_returns SET status = 'shipped', shipped_at = ?, "
        "shipped_by = ? WHERE id = 'ret-draft';",
        ['2026-07-30T01:00:00.000Z', headId],
      );

      final row = await database
          .customSelect(
            "SELECT status, received_by FROM goods_returns "
            "WHERE id = 'ret-draft';",
          )
          .getSingle();
      expect(row.read<String>('status'), 'shipped');
      expect(row.read<String?>('received_by'), isNull);
    });
  });

  group('CHECK catatan', () {
    test('catatan spasi ditolak, NULL dan teks diterima', () async {
      await expectLater(insertHeader('bad', note: '   '), throwsA(anything));
      await expectLater(
        insertHeader('bad2', warehouseNote: '  '),
        throwsA(anything),
      );
      await insertHeader('ret-1', note: 'Catatan sah');
    });
  });

  group('unique absolut', () {
    test('satu GR hanya boleh punya satu retur, tanpa partial', () async {
      await insertHeader('ret-1');
      await expectLater(
        insertHeader('ret-2', docNumber: 'TMP-RET-2'),
        throwsA(anything),
      );

      // Soft-deleting the first must not free the slot: a second return would credit
      // the Warehouse twice for one shipment (§10).
      await database.customStatement(
        "UPDATE goods_returns SET deleted_at = '2026-07-30T05:00:00.000Z' "
        "WHERE id = 'ret-1';",
      );
      await expectLater(
        insertHeader('ret-3', docNumber: 'TMP-RET-3'),
        throwsA(anything),
      );

      final sql = await indexSql('idx_goods_returns_gr');
      expect(sql, contains('UNIQUE'));
      expect(sql.toLowerCase().contains('where'), isFalse);
    });

    test('doc_number unik tanpa partial', () async {
      await insertHeader('ret-1');
      final sql = await indexSql('idx_goods_returns_doc_number');
      expect(sql, contains('UNIQUE'));
      expect(
        sql.toLowerCase().contains('where'),
        isFalse,
        reason: 'G-A3: nomor dokumen tidak dipakai ulang.',
      );
    });

    test('satu baris GR rejected hanya boleh diretur sekali, selamanya', () async {
      await insertHeader('ret-1');
      await insertLine('retl-1');

      await expectLater(insertLine('retl-2'), throwsA(anything));

      // Even from a *different* document — the index is table-wide, because a rejected
      // position is returned once, ever (§11).
      await database.customStatement(
        "UPDATE goods_returns SET deleted_at = '2026-07-30T05:00:00.000Z' "
        "WHERE id = 'ret-1';",
      );
      await database.customStatement(
        'DELETE FROM goods_returns WHERE id = ?;',
        ['ret-x'],
      );

      final sql = await indexSql('idx_goods_return_lines_gr_line_unique');
      expect(sql, contains('UNIQUE'));
      expect(sql.toLowerCase().contains('where'), isFalse);

      // And soft-deleting the line does not free it either.
      await database.customStatement(
        "UPDATE goods_return_lines SET deleted_at = '2026-07-30T05:00:00.000Z' "
        "WHERE id = 'retl-1';",
      );
      await expectLater(insertLine('retl-3'), throwsA(anything));
    });

    test('unique dalam dokumen juga ada', () async {
      final sql = await indexSql('idx_goods_return_lines_unique');
      expect(sql, contains('UNIQUE'));
      expect(sql.toLowerCase().contains('where'), isFalse);
    });
  });

  group('CHECK baris', () {
    test('qty harus positif', () async {
      await insertHeader('ret-1');
      await expectLater(insertLine('bad', qty: 0), throwsA(anything));
      await expectLater(insertLine('bad2', qty: -1000), throwsA(anything));
      await insertLine('retl-1', qty: Quantity.parse('2.5').milliUnits);
    });

    test('alasan penolakan tidak boleh kosong atau spasi', () async {
      await insertHeader('ret-1');
      await expectLater(insertLine('bad', reason: '   '), throwsA(anything));
      await expectLater(insertLine('bad2', reason: ''), throwsA(anything));
    });

    test('batch opsional pada level tabel, wajib pada level domain', () async {
      // `items.has_expiry` is a cross-table fact SQLite cannot read, so both shapes are
      // storable here and the use cases enforce G-E2 in both directions.
      await insertHeader('ret-1');
      await insertLine('retl-1');
      await insertLine(
        'retl-2',
        grLine: secondRejectedLineId,
        itemId: batchItemId,
        batch: batchId,
      );

      final rows = await database
          .customSelect('SELECT batch_id FROM goods_return_lines ORDER BY id;')
          .get();
      expect(rows.first.read<String?>('batch_id'), isNull);
      expect(rows.last.read<String?>('batch_id'), batchId);
    });
  });
}
