import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The opt-in Retur demo data (§40).
///
/// Three properties are asserted for each of the three entry points, and they are the
/// three a seed most easily gets wrong:
///
/// * **opt-in** — nothing appears from `run()` alone, so a test that expects an empty
///   queue keeps seeing one;
/// * **idempotent** — a second call returns the same document rather than starting a
///   second chain, which the unique index on `gr_id` would refuse anyway;
/// * **through the official chain** — every row is written by the real use cases, so
///   the demo cannot contain a document the rules would not produce. No balance is
///   written directly, no movement is forged, and no posted Good Receipt line is
///   edited after the fact.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());

  tearDown(() => context.dispose());

  Future<int> countOf(String table) async {
    final row = await context.database
        .customSelect('SELECT COUNT(*) AS c FROM $table;')
        .getSingle();
    return row.read<int>('c');
  }

  group('opt-in', () {
    test('run() saja tidak membuat dokumen Retur', () async {
      await context.seed.run();

      expect(await countOf('goods_returns'), 0);
      expect(await countOf('goods_return_lines'), 0);
      expect(
        await context.movementCountOfType(StockMovementType.itemReturn),
        0,
      );
    });

    test('build rilis menolak seluruh entry point', () async {
      await context.seed.run();

      for (final call in [
        context.productionSeed.seedDraftGoodsReturn,
        context.productionSeed.seedShippedGoodsReturn,
        context.productionSeed.seedReceivedGoodsReturn,
      ]) {
        await expectLater(call(), throwsA(anything));
      }
      expect(await countOf('goods_returns'), 0);
    });
  });

  group('draft', () {
    test('membuat satu draft dari GR yang sudah diposting', () async {
      await context.seed.run();
      final id = await context.seed.seedDraftGoodsReturn();

      expect(id, isNotNull);
      final document = await context.goodsReturns.getById(id!);
      expect(document!.status, GoodsReturnStatus.draft);
      expect(document.docNumber, startsWith('TMP-RET-'));
      expect(document.note, isNotNull);

      // The snapshot is the receipt's rejections — every one of them, and only them.
      final expected = await context.goodsReturns.rejectedGoodReceiptLineIds(
        document.grId,
      );
      final rows = await context.goodsReturnLineRows(id);
      expect(rows.keys.toSet(), expected.toSet());
      expect(rows, isNotEmpty);

      // And nothing about stock happened.
      expect(await context.goodsReturnMovementCount(id), 0);
    });

    test(
      'idempoten: panggilan kedua mengembalikan dokumen yang sama',
      () async {
        await context.seed.run();
        final first = await context.seed.seedDraftGoodsReturn();
        final second = await context.seed.seedDraftGoodsReturn();

        expect(second, first);
        expect(await countOf('goods_returns'), 1);
        expect(
          await context.goodsReturnCountFor(
            (await context.goodsReturns.getById(first!))!.grId,
          ),
          1,
        );
      },
    );

    test('kuantitas snapshot sama dengan shipped_qty baris GR', () async {
      await context.seed.run();
      final id = await context.seed.seedDraftGoodsReturn();
      final document = await context.goodsReturns.getById(id!);

      final positions = await context.goodsReturns.rejectedPositionsOf(
        document!.grId,
      );
      final rows = await context.goodsReturnLineRows(id);
      for (final position in positions) {
        expect(rows[position.grLineId]!['qty'], position.shippedQty.milliUnits);
        expect(
          rows[position.grLineId]!['reject_reason_snapshot'],
          position.rejectReason,
        );
      }
    });
  });

  group('shipped', () {
    test('menandai dikirim tanpa menyentuh ledger', () async {
      await context.seed.run();
      final warehouseBefore = await context.balancesAt(
        (await context.master.activeWarehouseLocations()).single.id,
      );
      final movementsBefore = await context.totalMovementCount();

      final id = await context.seed.seedShippedGoodsReturn();
      expect(id, isNotNull);

      final document = await context.goodsReturns.getById(id!);
      expect(document!.status, GoodsReturnStatus.shipped);
      expect(document.shippedAt, isNotNull);
      expect(document.shippedBy, isNotNull);
      expect(await context.goodsReturnMovementCount(id), 0);

      // The chain the seed drives *does* post a Good Receipt on the way, so the total
      // legitimately grows — what must not appear is a `return` movement.
      expect(
        await context.totalMovementCount(),
        greaterThanOrEqualTo(movementsBefore),
      );
      expect(
        await context.movementCountOfType(StockMovementType.itemReturn),
        0,
      );
      expect(warehouseBefore, isNotNull);
    });

    test('idempoten', () async {
      await context.seed.run();
      final first = await context.seed.seedShippedGoodsReturn();
      final second = await context.seed.seedShippedGoodsReturn();

      expect(second, first);
      expect(await countOf('goods_returns'), 1);
    });
  });

  group('received', () {
    test('memposting movement return dan menambah saldo Warehouse', () async {
      await context.seed.run();
      final warehouseId =
          (await context.master.activeWarehouseLocations()).single.id;
      final before = await context.balancesAt(warehouseId);

      final id = await context.seed.seedReceivedGoodsReturn();
      expect(id, isNotNull);

      final document = await context.goodsReturns.getById(id!);
      expect(document!.status, GoodsReturnStatus.received);
      expect(document.warehouseNote, isNotNull);

      final movements = await context.goodsReturnMovements(id);
      expect(movements, isNotEmpty);
      expect(
        movements.length,
        await context.goodsReturnLineCount(id),
        reason: 'Satu movement per baris.',
      );
      for (final movement in movements) {
        expect(movement['movement_type'], 'return');
        expect(movement['from_location_id'], isNull);
        expect(movement['to_location_id'], warehouseId);
        expect(movement['ref_doc_type'], RefDocType.goodsReturn);
      }
      expect(await context.balancesAt(warehouseId), isNot(before));
    });

    test('penerima berbeda dari pembuat dan pengirim (G-R4)', () async {
      await context.seed.run();
      final id = await context.seed.seedReceivedGoodsReturn();
      final document = await context.goodsReturns.getById(id!);

      expect(document!.receivedBy, isNot(document.createdBy));
      expect(document.receivedBy, isNot(document.shippedBy));

      final receiver = await context.master.userById(document.receivedBy!);
      expect(receiver!.role, UserRole.warehouse);
    });

    test('idempoten dan tidak menggandakan movement', () async {
      await context.seed.run();
      final first = await context.seed.seedReceivedGoodsReturn();
      final movementsAfterFirst = await context.goodsReturnMovementCount(
        first!,
      );

      final second = await context.seed.seedReceivedGoodsReturn();
      expect(second, first);
      expect(
        await context.goodsReturnMovementCount(first),
        movementsAfterFirst,
      );
      expect(await countOf('goods_returns'), 1);
    });
  });

  group('tanpa prasyarat, seed menjawab null', () {
    test('database kosong tidak memaksa membuat apa pun', () async {
      // No master data, no chain, nothing to return. Refusing is the honest answer —
      // inventing a rejection to have something to demo would be the seed asserting a
      // business event that never happened.
      expect(await context.seed.seedDraftGoodsReturn(), isNull);
      expect(await context.seed.seedShippedGoodsReturn(), isNull);
      expect(await context.seed.seedReceivedGoodsReturn(), isNull);
      expect(await countOf('goods_returns'), 0);
    });
  });

  group('dokumen sebelumnya tidak diubah', () {
    test('baris GR tetap seperti saat diposting', () async {
      await context.seed.run();
      final id = await context.seed.seedDraftGoodsReturn();
      final document = await context.goodsReturns.getById(id!);
      final before = await context.goodReceiptLineRows(document!.grId);

      await context.seed.seedReceivedGoodsReturn();

      expect(await context.goodReceiptLineRows(document.grId), before);
      expect(await context.goodReceiptStatusOf(document.grId), 'posted');
    });
  });
}
