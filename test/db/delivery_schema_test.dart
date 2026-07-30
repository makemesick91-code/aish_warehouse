import 'dart:io';

import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Schema v6 as a **fresh** database gets it from `createAll`.
///
/// The migration test proves an upgraded database ends up in the right shape; this
/// proves the shape itself is right, which is a different question. A constraint
/// that only exists on the migration path, or only on the fresh path, is a
/// constraint half the installed base does not have.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<Map<String, String>> columnTypes(String table) async {
    final rows = await context.database
        .customSelect('PRAGMA table_xinfo($table);')
        .get();
    return {
      for (final row in rows)
        row.read<String>('name'): row.read<String>('type'),
    };
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

  group('struktur tabel', () {
    test('kedua tabel Delivery Order tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%';",
          )
          .get();
      final tables = rows.map((row) => row.read<String>('name')).toSet();

      expect(tables, containsAll(['delivery_orders', 'delivery_order_lines']));
    });

    test('shipped_qty bertipe INTEGER, bukan REAL', () async {
      // Q-3: REAL is forbidden on a quantity column. A REAL `shipped_qty` would
      // accumulate binary rounding error across partial shipments, and the
      // cumulative total G-D2 compares would eventually disagree with the sum of
      // its own parts.
      final types = await columnTypes('delivery_order_lines');
      expect(types['shipped_qty'], 'INTEGER');
      expect(
        types.values.any((type) => type.toUpperCase().contains('REAL')),
        isFalse,
      );
    });

    test('kolom bisnis dan audit lengkap', () async {
      final header = await columnTypes('delivery_orders');
      expect(
        header.keys,
        containsAll([
          'id',
          'created_at',
          'updated_at',
          'deleted_at',
          'sync_status',
          'doc_number',
          'pr_id',
          'prepared_by',
          'status',
          'shipped_at',
          'shipped_by',
          'note',
        ]),
      );

      final lines = await columnTypes('delivery_order_lines');
      expect(
        lines.keys,
        containsAll([
          'id',
          'created_at',
          'updated_at',
          'deleted_at',
          'sync_status',
          'do_id',
          'pr_line_id',
          'item_id',
          'batch_id',
          'shipped_qty',
          'fefo_override_reason',
          'near_expiry_confirmed',
          'near_expiry_note',
        ]),
      );
    });

    test('tidak ada CHECK perbandingan timestamp leksikal', () async {
      // Timestamps are ISO-8601 TEXT, so `shipped_at >= created_at` in SQL compares
      // characters rather than instants — the defect schema v4 removed from
      // `stock_opnames`. Ordering is `DocumentTimestampPolicy`'s job, on UTC
      // `DateTime`s.
      final sql = await tableSql('delivery_orders');
      expect(sql, isNot(contains('shipped_at >= created_at')));
      expect(sql, isNot(contains('shipped_at > created_at')));
      expect(sql, isNot(contains('>= submitted_at')));
      // What it *does* state is which timestamps each status must carry.
      expect(sql, contains("status IN ('preparing', 'shipped', 'received')"));
    });

    test('seluruh foreign key dideklarasikan', () async {
      Future<Set<String>> foreignTables(String table) async {
        final rows = await context.database
            .customSelect('PRAGMA foreign_key_list($table);')
            .get();
        return rows.map((row) => row.read<String>('table')).toSet();
      }

      expect(
        await foreignTables('delivery_orders'),
        containsAll(['purchase_requests', 'users']),
      );
      expect(
        await foreignTables('delivery_order_lines'),
        containsAll([
          'delivery_orders',
          'purchase_request_lines',
          'items',
          'item_batches',
        ]),
      );
    });

    test('index query dan index unik parsial tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'idx_delivery%';",
          )
          .get();
      final indexes = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        indexes,
        containsAll([
          'idx_delivery_orders_pr_status',
          'idx_delivery_orders_status_created',
          'idx_delivery_orders_prepared_by_status',
          'idx_delivery_orders_shipped_at',
          'idx_delivery_orders_doc_number',
          'idx_delivery_order_lines_do',
          'idx_delivery_order_lines_pr_line',
          'idx_delivery_order_lines_item',
          'idx_delivery_order_lines_batch',
          'idx_delivery_order_lines_batched',
          'idx_delivery_order_lines_unbatched',
        ]),
      );
    });

    test('foreign_key_check kosong pada database v6 baru', () async {
      final violations = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });

    test('generated manager tetap dinonaktifkan', () {
      // The manager API is a second, unguarded write path into every table: it would
      // let any caller mark a shipment `received`, edit the lines of a posted
      // document, or hard delete business rows — the exact things the DAO is written
      // to make impossible.
      expect(_readFile('build.yaml'), contains('generate_manager: false'));
    });
  });

  group('constraint pada database baru', () {
    test(
      'doc_number unik untuk dokumen hidup, bebas setelah soft delete',
      () async {
        Future<void> insert(String id, String docNumber) =>
            context.database.customStatement(
              'INSERT INTO delivery_orders (id, created_at, updated_at, '
              'sync_status, doc_number, pr_id, prepared_by, status) '
              'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
              [
                id,
                nowUtc.toIso8601String(),
                nowUtc.toIso8601String(),
                'pending',
                docNumber,
                fixture.purchaseRequestId,
                fixture.warehouseUser.id,
                'preparing',
              ],
            );

        await insert('do-a', 'TMP-DO-shared');
        expect(() => insert('do-b', 'TMP-DO-shared'), throwsA(anything));

        // Soft-deleting the first releases the number: once the backend issues real
        // ones, a deleted row must not hold one hostage.
        await context.database.customStatement(
          "UPDATE delivery_orders SET deleted_at = ? WHERE id = 'do-a';",
          [nowUtc.toIso8601String()],
        );
        await insert('do-b', 'TMP-DO-shared');
      },
    );

    test('alokasi per batch unik, dan bebas setelah soft delete', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(fixture, batchId: fixture.safeBatch.id, qty: '1'),
        ],
      );

      Future<void> insertSameBatch(String id) =>
          context.database.customStatement(
            'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
            'sync_status, do_id, pr_line_id, item_id, batch_id, shipped_qty) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
            [
              id,
              nowUtc.toIso8601String(),
              nowUtc.toIso8601String(),
              'pending',
              doId,
              fixture.batchLineId,
              fixture.batchItem.id,
              fixture.safeBatch.id,
              1000,
            ],
          );

      expect(() => insertSameBatch('dup'), throwsA(anything));

      // A *different* batch of the same PR line is legitimate — that is how FEFO
      // splits a quantity.
      await context.database.customStatement(
        'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
        'sync_status, do_id, pr_line_id, item_id, batch_id, shipped_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'split',
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'pending',
          doId,
          fixture.batchLineId,
          fixture.batchItem.id,
          fixture.soonBatch.id,
          1000,
        ],
      );

      expect(await context.deliveryLineCount(doId), 2);
    });

    test('saldo tetap tidak boleh negatif', () async {
      expect(
        () => context.database.customStatement(
          'UPDATE stock_balances SET qty_on_hand = -1 WHERE location_id = ?;',
          [fixture.warehouse.id],
        ),
        throwsA(anything),
      );
    });

    test('kuantitas milli-unit tersimpan tepat untuk nilai desimal', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.375')],
      );

      final row = await context.database
          .customSelect(
            'SELECT shipped_qty FROM delivery_order_lines WHERE do_id = ?;',
            variables: [Variable<String>(doId)],
          )
          .getSingle();
      expect(row.read<int>('shipped_qty'), 2375);
      expect(
        Quantity.fromMilliUnits(row.read<int>('shipped_qty')).format(),
        '2.375',
      );
    });
  });
}

String _readFile(String path) => File(path).readAsStringSync();
