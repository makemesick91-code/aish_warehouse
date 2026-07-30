import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// **G-D4** — *"Warehouse tidak bisa menambahkan item yang tidak ada di PR."*
///
/// The rule is enforced in three layers, and each is tested here:
///
/// * **By schema.** `delivery_order_lines.pr_line_id` is NOT NULL and a foreign key,
///   so a line that descends from nothing cannot be stored at all.
/// * **By API shape.** The line writer takes no `pr_line_id` and no `item_id`, so
///   repointing an allocation is not expressible — it can only be removed and
///   re-allocated. The architecture test asserts that absence; here it is asserted by
///   behaviour.
/// * **By use case.** Every allocation is checked against the parent request's own
///   positions before anything ships, because a hand-written row (or a sync payload)
///   can still reach the table.
///
/// Batch consistency (G-E1/G-E2) belongs to the same family and lives here too: an
/// expiry-tracked item always ships per batch, one without expiry never carries one,
/// and a batch always belongs to the item it is allocated against.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// Inserts one allocation by hand, bypassing the use case — the only way to
  /// produce the states the use case exists to refuse.
  Future<void> insertRawLine({
    required String doId,
    required String id,
    required String prLineId,
    required String itemId,
    String? batchId,
    int qty = 1000,
  }) => context.database.customStatement(
    'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
    'sync_status, do_id, pr_line_id, item_id, batch_id, shipped_qty) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
    [
      id,
      nowUtc.toIso8601String(),
      nowUtc.toIso8601String(),
      'pending',
      doId,
      prLineId,
      itemId,
      batchId,
      qty,
    ],
  );

  group('barang harus berasal dari PR', () {
    test('barang yang ada pada PR diterima', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });

    test('baris PR dari PR lain ditolak', () async {
      final otherPrId = await writeProcessingPurchaseRequest(
        context,
        branchId: fixture.otherBranch.id,
        requestedBy: fixture.otherBranchHead.id,
        processedBy: fixture.warehouseUser.id,
        nowUtc: nowUtc,
        lines: {fixture.simpleItem.id: '5'},
        prId: 'pr-other',
      );
      final otherLines = await purchaseRequestLineIdsByItem(context, otherPrId);

      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await insertRawLine(
        doId: order.id,
        id: 'dol-foreign',
        prLineId: otherLines[fixture.simpleItem.id]!,
        itemId: fixture.simpleItem.id,
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        ),
        throwsA(isA<DeliveryPrLineMismatchFailure>()),
      );
      expect(await context.shipmentMovementCount(order.id), 0);
    });

    test('item_id yang tidak cocok dengan baris PR ditolak', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      // The PR line asks for `simpleItem`; the allocation names `scarceItem`. Both
      // are on the request, which is exactly what makes this the interesting case:
      // a check that only asked "is the item on the PR" would pass it.
      await insertRawLine(
        doId: order.id,
        id: 'dol-swapped',
        prLineId: fixture.simpleLineId,
        itemId: fixture.scarceItem.id,
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        ),
        throwsA(isA<DeliveryItemNotInPurchaseRequestFailure>()),
      );
      expect(await context.shipmentMovementCount(order.id), 0);
    });

    test('menambah baris untuk baris PR asing ditolak oleh use case', () async {
      final otherPrId = await writeProcessingPurchaseRequest(
        context,
        branchId: fixture.otherBranch.id,
        requestedBy: fixture.otherBranchHead.id,
        processedBy: fixture.warehouseUser.id,
        nowUtc: nowUtc,
        lines: {fixture.simpleItem.id: '5'},
        prId: 'pr-other',
      );
      final otherLines = await purchaseRequestLineIdsByItem(context, otherPrId);

      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      await expectLater(
        () => context.updateDeliveryLine().add(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
          prLineId: otherLines[fixture.simpleItem.id]!,
          shippedQty: Quantity.parse('1'),
        ),
        throwsA(isA<DeliveryPrLineMismatchFailure>()),
      );
      expect(await context.deliveryLineCount(order.id), 0);
    });

    test('baris tanpa baris PR tidak dapat disimpan sama sekali', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      // NOT NULL plus a foreign key: G-D4 expressed in the schema, so a line that
      // descends from nothing is not storable even by hand.
      await expectLater(
        () => context.database.customStatement(
          'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
          'sync_status, do_id, pr_line_id, item_id, shipped_qty) '
          'VALUES (?, ?, ?, ?, ?, NULL, ?, ?);',
          [
            'dol-null',
            nowUtc.toIso8601String(),
            nowUtc.toIso8601String(),
            'pending',
            order.id,
            fixture.simpleItem.id,
            1000,
          ],
        ),
        throwsA(anything),
      );
      await expectLater(
        () => insertRawLine(
          doId: order.id,
          id: 'dol-ghost',
          prLineId: 'tidak-ada',
          itemId: fixture.simpleItem.id,
        ),
        throwsA(anything),
      );
    });
  });

  group('konsistensi batch', () {
    test('batch milik barang lain ditolak', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await insertRawLine(
        doId: order.id,
        id: 'dol-wrong-batch',
        prLineId: fixture.tieLineId,
        itemId: fixture.tieItem.id,
        // A batch of `batchItem`, allocated against `tieItem`.
        batchId: fixture.safeBatch.id,
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        ),
        throwsA(isA<InvalidDeliveryBatchFailure>()),
      );
    });

    test('barang ber-ED tanpa batch ditolak', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await insertRawLine(
        doId: order.id,
        id: 'dol-no-batch',
        prLineId: fixture.batchLineId,
        itemId: fixture.batchItem.id,
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        ),
        throwsA(isA<InvalidDeliveryBatchFailure>()),
      );
    });

    test('barang tanpa ED dengan batch ditolak', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await insertRawLine(
        doId: order.id,
        id: 'dol-extra-batch',
        prLineId: fixture.simpleLineId,
        itemId: fixture.simpleItem.id,
        batchId: fixture.safeBatch.id,
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        ),
        throwsA(isA<InvalidDeliveryBatchFailure>()),
      );
    });

    test('use case menolak batch tidak konsisten saat edit', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final lineIds = await deliveryLineIdsByAllocation(context, doId);

      await expectLater(
        () => context.updateDeliveryLine().call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lineIds['${fixture.simpleLineId}|']!,
          shippedQty: Quantity.parse('1'),
          batchId: fixture.safeBatch.id,
        ),
        throwsA(isA<InvalidDeliveryBatchFailure>()),
      );
    });
  });

  group('alokasi ganda', () {
    test('posisi batch yang sama dua kali ditolak database', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(fixture, batchId: fixture.safeBatch.id, qty: '1'),
        ],
      );

      await expectLater(
        () => insertRawLine(
          doId: doId,
          id: 'dol-dup',
          prLineId: fixture.batchLineId,
          itemId: fixture.batchItem.id,
          batchId: fixture.safeBatch.id,
        ),
        throwsA(anything),
      );
    });

    test('menambah alokasi batch yang sama ditolak use case', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(fixture, batchId: fixture.safeBatch.id, qty: '1'),
        ],
      );

      await expectLater(
        () => context.updateDeliveryLine().add(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
          prLineId: fixture.batchLineId,
          shippedQty: Quantity.parse('1'),
          batchId: fixture.safeBatch.id,
          fefoOverrideReason: 'Sisa batch lain untuk cabang lain',
        ),
        throwsA(isA<DuplicateDeliveryAllocationFailure>()),
      );
      expect(await context.deliveryLineCount(doId), 1);
    });

    test('batch berbeda pada baris PR yang sama diterima', () async {
      // The legitimate case the uniqueness rule must not block: a FEFO split.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1.5',
            nearExpiryConfirmed: true,
          ),
          batchAllocation(
            fixture,
            batchId: fixture.soonBatch.id,
            qty: '2',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      expect(await context.deliveryLineCount(doId), 2);
    });

    test('posisi tanpa batch hanya boleh satu kali', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );

      await expectLater(
        () => insertRawLine(
          doId: doId,
          id: 'dol-dup-nobatch',
          prLineId: fixture.simpleLineId,
          itemId: fixture.simpleItem.id,
        ),
        throwsA(anything),
      );
    });

    test('alokasi yang dihapus membebaskan posisinya kembali', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final lineIds = await deliveryLineIdsByAllocation(context, doId);

      await context.removeDeliveryLine.call(
        actorUserId: fixture.warehouseUser.id,
        lineId: lineIds['${fixture.simpleLineId}|']!,
      );
      expect(await context.deliveryLineCount(doId), 0);

      // `deleted_at IS NULL` in both partial unique indexes is what makes this
      // possible: the position may be allocated again.
      await context.updateDeliveryLine().add(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
        prLineId: fixture.simpleLineId,
        shippedQty: Quantity.parse('2'),
      );
      expect(await context.deliveryLineCount(doId), 1);
    });
  });

  group('kuantitas alokasi', () {
    test('qty nol dan negatif ditolak database', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      for (final qty in [0, -1000]) {
        await expectLater(
          () => insertRawLine(
            doId: order.id,
            id: 'dol-$qty',
            prLineId: fixture.simpleLineId,
            itemId: fixture.simpleItem.id,
            qty: qty,
          ),
          throwsA(anything),
        );
      }
    });

    test('qty nol ditolak use case', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final lineIds = await deliveryLineIdsByAllocation(context, doId);

      await expectLater(
        () => context.updateDeliveryLine().call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lineIds['${fixture.simpleLineId}|']!,
          shippedQty: Quantity.zero(),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('desimal tiga angka tersimpan dan dikirim tepat', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.375')],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final movements = await context.shipmentMovements(doId);
      expect(movements.single['qty'], 2375);
      // 2.5 − 2.375 = 0.125, exactly.
      final balances = await context.balancesAt(fixture.warehouse.id);
      expect(balances['${fixture.simpleItem.id}|'], 125);
    });
  });

  group('integritas himpunan baris', () {
    test('baris dengan barang yang hilang menolak pengiriman', () async {
      // The joined read inner-joins `items`, so this line would simply be absent
      // from the loaded document — and the shipment would go out one allocation
      // short of what the document says.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '1'),
          DeliveryAllocation(
            prLineId: fixture.scarceLineId,
            itemId: fixture.scarceItem.id,
            qty: Quantity.parse('1'),
          ),
        ],
      );
      await context.corruptByDeleting('items', fixture.scarceItem.id);

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<HistoricalDeliveryReferenceMissingFailure>()),
      );
      expect(await context.shipmentMovementCount(doId), 0);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
    });

    test('baris PR yang barangnya hilang menolak pengiriman', () async {
      // The PR line is still there, but the join on `items` drops it — so
      // `purchaseRequestPositions` returns three positions where the request has
      // four. A shipment measured against the remainder could complete it, and
      // G-D5 would read that as a fulfilled order (§21).
      //
      // The allocation itself is untouched, which is the point: the hole is on the
      // *order* side, and only the plain-select count can see it.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      await context.corruptByDeleting('items', fixture.scarceItem.id);

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<HistoricalDeliveryReferenceMissingFailure>().having(
            (failure) => failure.entity,
            'entity',
            'purchase_request_lines',
          ),
        ),
      );
      expect(await context.shipmentMovementCount(doId), 0);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'processing',
      );
    });

    test('baris PR yang dihapus fisik tidak diam-diam melengkapi PR', () async {
      // A physically deleted PR line is invisible from both sides — the plain
      // select and the join lose it together, so no count can disagree. What must
      // still hold is the conclusion: the positions that *do* remain are not
      // complete, so the request stays `processing` rather than being marked
      // shipped on the strength of a shrunken order.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      await context.corruptByDeleting(
        'purchase_request_lines',
        fixture.scarceLineId,
      );

      final result = await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      expect(result.purchaseRequestCompleted, isFalse);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'processing',
      );
    });
  });
}
