import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/goods_return/data/repositories/drift_goods_return_repository.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The `return` movement, its shape and its effect (§22/§45).
///
/// ```text
/// movement_type    = return
/// from_location_id = NULL
/// to_location_id   = Warehouse Pusat
/// ref_doc_type     = RET
/// ref_doc_id       = goods_return.id
/// actor_user_id    = receivedBy
/// ```
///
/// The NULL source is the decision this milestone rests on, and it is the one worth
/// restating: a rejected Good Receipt line **never entered the branch store's balance**
/// — G-G5 credits `checked` lines only — while the Delivery Order that carried it
/// already debited the Warehouse and wrote `to_location_id = NULL`. So at the moment a
/// return is confirmed, no location holds this stock. Debiting the branch would create
/// a negative out of nothing (G-A2); debiting the Warehouse would debit it twice for
/// one shipment. One leg in, nothing out — the exact mirror of the shipment.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('bentuk movement', () {
    test('satu movement per baris, dengan kolom yang benar', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      final movements = await context.goodsReturnMovements(received.id);

      expect(movements.length, 2, reason: 'Satu movement per baris retur.');
      for (final movement in movements) {
        expect(movement['movement_type'], 'return');
        expect(
          movement['from_location_id'],
          isNull,
          reason:
              'Barang rejected tidak pernah masuk saldo cabang, dan pengiriman '
              'sudah mendebit Warehouse.',
        );
        expect(movement['to_location_id'], fixture.warehouse.id);
        expect(movement['ref_doc_type'], RefDocType.goodsReturn);
        expect(movement['ref_doc_id'], received.id);
        expect(movement['actor_user_id'], fixture.warehouseUser.id);
        expect(movement['note'], isNotNull);
        expect((movement['note']! as String).trim(), isNotEmpty);
      }
    });

    test('ref_doc_type RET, bukan GR', () async {
      final received = await receivedGoodsReturnFor(context, fixture);

      // Sharing `GR` would be the most tempting mistake here — a return *is* raised
      // from a receipt — and the most damaging: the stock card could no longer say
      // which document moved which quantity (§9).
      final rows = await context.database
          .customSelect(
            "SELECT COUNT(*) AS c FROM stock_movements WHERE ref_doc_id = ? "
            "AND ref_doc_type <> 'RET';",
            variables: [Variable<String>(received.id)],
          )
          .getSingle();
      expect(rows.read<int>('c'), 0);
    });

    test('kuantitas dan batch dipertahankan apa adanya', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      final movements = await context.goodsReturnMovements(received.id);

      final byItem = {
        for (final movement in movements)
          movement['item_id'] as String: movement,
      };
      expect(
        byItem[fixture.simpleItem.id]!['qty'],
        fixture.rejectedSimpleQty.milliUnits,
      );
      expect(
        byItem[fixture.simpleItem.id]!['batch_id'],
        isNull,
        reason: 'Barang tanpa expiry tidak membawa batch (G-E2).',
      );
      expect(
        byItem[fixture.batchItem.id]!['qty'],
        fixture.rejectedBatchQty.milliUnits,
      );
      expect(byItem[fixture.batchItem.id]!['batch_id'], fixture.nearBatch.id);
    });

    test('catatan movement memuat alasan penolakan', () async {
      final received = await receivedGoodsReturnFor(
        context,
        fixture,
        note: 'Dikirim via kurir internal',
        warehouseNote: 'Kardus penyok, isi lengkap',
      );
      final movements = await context.goodsReturnMovements(received.id);

      final byItem = {
        for (final movement in movements)
          movement['item_id'] as String: movement['note'] as String,
      };
      // The reject reason comes first, because the row is *about* it; the two optional
      // remarks follow (§22).
      expect(
        byItem[fixture.simpleItem.id],
        startsWith('Kemasan rusak saat diterima'),
      );
      expect(
        byItem[fixture.batchItem.id],
        startsWith('Sisa umur simpan terlalu pendek'),
      );
      for (final note in byItem.values) {
        expect(note, contains('Dikirim via kurir internal'));
        expect(note, contains('Kardus penyok, isi lengkap'));
      }
    });

    test('catatan tetap ada walau kedua remark kosong', () async {
      // G-G4 makes the reject reason mandatory all the way down, which is what lets
      // §22 promise a non-empty note without inventing one.
      final received = await receivedGoodsReturnFor(context, fixture);
      final movements = await context.goodsReturnMovements(received.id);

      for (final movement in movements) {
        expect((movement['note']! as String).trim(), isNotEmpty);
        expect(movement['note'], isNot(contains('Catatan cabang')));
        expect(movement['note'], isNot(contains('Catatan Warehouse')));
      }
    });
  });

  group('efek saldo', () {
    test('saldo Warehouse bertambah tepat sebesar yang diretur', () async {
      final before = await context.balancesAt(fixture.warehouse.id);

      final received = await receivedGoodsReturnFor(context, fixture);
      final after = await context.balancesAt(fixture.warehouse.id);

      expect(received.status, GoodsReturnStatus.received);
      expect(
        Quantity.fromMilliUnits(after['${fixture.simpleItem.id}|'] ?? 0) -
            Quantity.fromMilliUnits(before['${fixture.simpleItem.id}|'] ?? 0),
        fixture.rejectedSimpleQty,
      );
      final batchKey = '${fixture.batchItem.id}|${fixture.nearBatch.id}';
      expect(
        Quantity.fromMilliUnits(after[batchKey] ?? 0) -
            Quantity.fromMilliUnits(before[batchKey] ?? 0),
        fixture.rejectedBatchQty,
      );
    });

    test('saldo Gudang Cabang tidak berubah sama sekali', () async {
      final before = await context.balancesAt(fixture.branchStore.id);

      await receivedGoodsReturnFor(context, fixture);

      // The goods were never there: G-G5 credits `checked` lines only.
      expect(await context.balancesAt(fixture.branchStore.id), before);
    });

    test('saldo ruangan tidak berubah', () async {
      final rooms = await context.master.activeRooms(
        branchId: fixture.branch.id,
      );
      final locations = <String, Map<String, int>>{};
      for (final room in rooms) {
        final location = await context.master.activeRoomLocation(room.id);
        if (location == null) continue;
        locations[location.id] = await context.balancesAt(location.id);
      }

      await receivedGoodsReturnFor(context, fixture);

      for (final entry in locations.entries) {
        expect(await context.balancesAt(entry.key), entry.value);
      }
    });

    test('batch kedaluwarsa tetap masuk saldo Warehouse', () async {
      // Forty days on, `nearBatch` is past its date. §36: a rejection has to be able to
      // go home, and what happens to it afterwards is a Pemusnahan's business (G-E7).
      final at = fixture.expiredInstant;
      final before = await context.balancesAt(fixture.warehouse.id);

      final received = await receivedGoodsReturnFor(
        context,
        fixture,
        nowUtc: at,
      );

      expect(received.status, GoodsReturnStatus.received);
      final batchKey = '${fixture.batchItem.id}|${fixture.nearBatch.id}';
      final after = await context.balancesAt(fixture.warehouse.id);
      expect(
        Quantity.fromMilliUnits(after[batchKey] ?? 0) -
            Quantity.fromMilliUnits(before[batchKey] ?? 0),
        fixture.rejectedBatchQty,
      );
      // The badge is a question about *today*, so it is asked as of the instant this
      // scenario runs at rather than as of the repository's own clock (§36).
      expect(
        received.lines.any((line) => line.isExpired(at)),
        isTrue,
        reason: 'Baris kedaluwarsa ditandai, bukan ditolak.',
      );
      expect(
        DriftGoodsReturnRepository.buildProgress(
          received.lines,
          nowUtc: at,
        ).expiredCount,
        1,
      );
    });
  });

  group('ledger append-only', () {
    test('movement pengiriman lama tidak berubah', () async {
      final before = await context.shipmentMovements(fixture.deliveryOrderId);

      await receivedGoodsReturnFor(context, fixture);

      expect(await context.shipmentMovements(fixture.deliveryOrderId), before);
    });

    test('movement Good Receipt lama tidak berubah', () async {
      final before = await context.goodReceiptMovements(fixture.goodReceiptId);

      await receivedGoodsReturnFor(context, fixture);

      expect(await context.goodReceiptMovements(fixture.goodReceiptId), before);
    });

    test('status PR, DO dan GR tidak berubah', () async {
      final grStatus = await context.goodReceiptStatusOf(fixture.goodReceiptId);
      final doStatus = await context.deliveryOrderStatusOf(
        fixture.deliveryOrderId,
      );

      await receivedGoodsReturnFor(context, fixture);

      expect(
        await context.goodReceiptStatusOf(fixture.goodReceiptId),
        grStatus,
      );
      expect(
        await context.deliveryOrderStatusOf(fixture.deliveryOrderId),
        doStatus,
      );
      // And the receipt's lines are untouched — a posted receipt is final (G-S2).
      final lines = await context.goodReceiptLineRows(fixture.goodReceiptId);
      for (final lineId in fixture.rejectedLineIds) {
        expect(lines[lineId]!['line_status'], 'rejected');
        expect(lines[lineId]!['received_qty'], 0);
      }
    });

    test('tidak ada reversal otomatis', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      expect(received.id, isNotEmpty);

      expect(await context.movementCountOfType(StockMovementType.reversal), 0);
    });

    test('jumlah movement return sama dengan jumlah baris', () async {
      final received = await receivedGoodsReturnFor(context, fixture);

      expect(
        await context.goodsReturnMovementCount(received.id),
        await context.goodsReturnLineCount(received.id),
      );
      expect(
        await context.movementCountOfType(StockMovementType.itemReturn),
        2,
      );
    });
  });

  group('kartu stok', () {
    test('movement retur muncul di kartu stok Warehouse', () async {
      final received = await receivedGoodsReturnFor(context, fixture);

      final card = await context.inventory.stockCard(
        itemId: fixture.batchItem.id,
        locationId: fixture.warehouse.id,
      );
      final returnRow = card.singleWhere(
        (movement) =>
            movement.movementType == StockMovementType.itemReturn &&
            movement.refDocId == received.id,
      );
      expect(returnRow.refDocType, RefDocType.goodsReturn);
      expect(returnRow.toLocationId, fixture.warehouse.id);
      expect(returnRow.fromLocationId, isNull);
      expect(returnRow.qty, fixture.rejectedBatchQty);
      expect(returnRow.actorUserId, fixture.warehouseUser.id);
    });

    test('kartu stok Gudang Cabang tidak memuat movement retur', () async {
      await receivedGoodsReturnFor(context, fixture);

      final card = await context.inventory.stockCard(
        itemId: fixture.batchItem.id,
        locationId: fixture.branchStore.id,
      );
      expect(
        card.any(
          (movement) => movement.movementType == StockMovementType.itemReturn,
        ),
        isFalse,
        reason:
            'from_location_id NULL, dan barang rejected tidak pernah menjadi '
            'saldo cabang.',
      );
    });
  });
}
