import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:aish_warehouse/features/delivery/domain/services/delivery_quantity_policy.dart';
import 'package:aish_warehouse/features/delivery/domain/use_cases/ship_delivery_order_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// **G-D2** — *"`shipped_qty` kumulatif per baris PR tidak boleh melebihi
/// `requested_qty`."*
///
/// The rule has two halves and both are tested here: the arithmetic, which is exact
/// fixed point and must never accumulate a residue; and the *authority*, which is
/// the revalidation inside the shipping transaction rather than anything a form
/// computed. The concurrency test is the second half stated as sharply as it can be:
/// two shipments racing for the same last unit must produce one commit and one
/// rollback, never two half-shipments.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// Cumulative shipped quantity of the fixture's non-expiry position, read from
  /// the database rather than from any cached model.
  Future<Quantity> cumulativeSimple() async {
    final map = await context.deliveries.cumulativeShippedByPrLine(
      prId: fixture.purchaseRequestId,
    );
    return map[fixture.simpleLineId] ?? Quantity.zero();
  }

  group('kebijakan murni', () {
    test('sisa dihitung eksak dalam fixed point', () {
      expect(
        DeliveryQuantityPolicy.remaining(
          requestedQty: Quantity.parse('2.375'),
          cumulativeShippedQty: Quantity.parse('0.5'),
        ),
        Quantity.parse('1.875'),
      );
    });

    test('tepat sama dengan permintaan diterima, lebih ditolak', () {
      bool exceeds(String requested, String shipped, String extra) =>
          DeliveryQuantityPolicy.exceedsRequested(
            requestedQty: Quantity.parse(requested),
            cumulativeShippedQty: Quantity.parse(shipped),
            additionalQty: Quantity.parse(extra),
          );

      // The boundary is `>`, not `>=`: shipping the last 0.5 of a 2.5 request is
      // exactly complete and G-D5 depends on it being accepted.
      expect(exceeds('2.5', '2', '0.5'), isFalse);
      expect(exceeds('2.5', '2', '0.501'), isTrue);
      expect(exceeds('2.5', '2.5', '0.001'), isTrue);
    });

    test('tiga pengiriman desimal berjumlah tepat tanpa residu', () {
      // The property binary floating point does not have: 0.1 + 0.2 + 0.3 is
      // exactly 0.6, so a request of 0.6 shipped this way leaves *nothing*.
      final total = Quantity.sum([
        Quantity.parse('0.1'),
        Quantity.parse('0.2'),
        Quantity.parse('0.3'),
      ]);
      expect(total, Quantity.parse('0.6'));
      expect(
        DeliveryQuantityPolicy.isFullyShipped(
          requestedQty: Quantity.parse('0.6'),
          cumulativeShippedQty: total,
        ),
        isTrue,
      );
    });

    test('dokumen tanpa posisi bukan dokumen yang terpenuhi', () {
      // "Nothing outstanding" and "fully shipped" are different facts, and treating
      // a corrupt document as complete would move the request forward.
      expect(
        DeliveryQuantityPolicy.completesRequest(const <ShipmentProgress>[]),
        isFalse,
      );
    });
  });

  group('pengiriman kumulatif', () {
    test('pengiriman penuh satu Surat Jalan', () async {
      // `tieItem` is requested 3 and the warehouse holds 2 + 2 across two batches,
      // so it can go out in one shipment.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          DeliveryAllocation(
            prLineId: fixture.tieLineId,
            itemId: fixture.tieItem.id,
            batchId: fixture.tieBatchA.id,
            qty: Quantity.parse('2'),
          ),
          DeliveryAllocation(
            prLineId: fixture.tieLineId,
            itemId: fixture.tieItem.id,
            batchId: fixture.tieBatchB.id,
            qty: Quantity.parse('1'),
          ),
        ],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final map = await context.deliveries.cumulativeShippedByPrLine(
        prId: fixture.purchaseRequestId,
      );
      // Two allocations of one position sum to one cumulative total.
      expect(map[fixture.tieLineId], Quantity.parse('3'));
    });

    test('pengiriman parsial menyisakan permintaan', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );

      final result = await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      expect(await cumulativeSimple(), Quantity.parse('1'));
      expect(result.isPartialShipment, isTrue);
      expect(result.purchaseRequestCompleted, isFalse);

      final progress = result.progress.firstWhere(
        (entry) => entry.prLineId == fixture.simpleLineId,
      );
      expect(progress.remainingAfterCurrentDo, Quantity.parse('2'));
      expect(progress.isFullyShipped, isFalse);
    });

    test('beberapa Surat Jalan mencapai jumlah penuh, desimal eksak', () async {
      // `simpleItem` is requested 3 with only 2.5 in the warehouse, so the
      // remaining 0.5 needs restocking — which is exactly the real-world shape of a
      // partial order and lets the arithmetic be checked across three documents.
      Future<void> ship(String qty) async {
        final doId = await prepareDeliveryOrder(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [simpleAllocation(fixture, qty: qty)],
        );
        await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        );
      }

      await ship('1.5');
      expect(await cumulativeSimple(), Quantity.parse('1.5'));
      await ship('1');
      expect(await cumulativeSimple(), Quantity.parse('2.5'));

      // Restock the last half unit and complete the order.
      await context.posting.postInboundWarehouse(
        itemId: fixture.simpleItem.id,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.parse('0.5'),
        actorUserId: fixture.warehouseUser.id,
      );
      await ship('0.5');

      expect(await cumulativeSimple(), Quantity.parse('3'));
      expect(
        DeliveryQuantityPolicy.isFullyShipped(
          requestedQty: Quantity.parse('3'),
          cumulativeShippedQty: await cumulativeSimple(),
        ),
        isTrue,
      );
    });

    test('kumulatif melebihi permintaan ditolak saat kirim', () async {
      final first = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2')],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: first,
      );

      // 2 already shipped, 3 requested, so 1.5 more overshoots by 0.5.
      await context.posting.postInboundWarehouse(
        itemId: fixture.simpleItem.id,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.parse('5'),
        actorUserId: fixture.warehouseUser.id,
      );
      final second = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1.5')],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: second,
        ),
        throwsA(
          isA<DeliveryQuantityExceedsRequestedFailure>().having(
            (failure) => failure.remaining,
            'sisa',
            Quantity.parse('1'),
          ),
        ),
      );

      // The refused document changed nothing: no movement, no balance, still
      // `preparing`, and the cumulative total is untouched.
      expect(await context.shipmentMovementCount(second), 0);
      expect(await context.deliveryOrderStatusOf(second), 'preparing');
      expect(await cumulativeSimple(), Quantity.parse('2'));
    });

    test('Surat Jalan preparing tidak dihitung sebagai terkirim', () async {
      // A draft allocation is an intention, not a shipment. Counting it would
      // refuse a second officer's legitimate partial while the first document sat
      // unposted.
      await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );

      expect(await cumulativeSimple(), Quantity.zero());
    });

    test('Surat Jalan received tetap dihitung sebagai terkirim', () async {
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

      // Good Receipt does not exist yet, so the status is written directly — which
      // is exactly what the next milestone's use case will do.
      await context.database.customStatement(
        "UPDATE delivery_orders SET status = 'received' WHERE id = ?;",
        [doId],
      );

      // The goods left the warehouse and Good Receipt does not send them back.
      expect(await cumulativeSimple(), Quantity.parse('1'));
    });

    test('Surat Jalan yang di-soft-delete tidak dihitung', () async {
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
      expect(await cumulativeSimple(), Quantity.parse('1'));

      await context.archive('delivery_orders', doId);
      expect(await cumulativeSimple(), Quantity.zero());
    });

    test('baris PR berbeda dihitung terpisah', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '1'),
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1.5',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final map = await context.deliveries.cumulativeShippedByPrLine(
        prId: fixture.purchaseRequestId,
      );
      expect(map[fixture.simpleLineId], Quantity.parse('1'));
      expect(map[fixture.batchLineId], Quantity.parse('1.5'));
      // A position with nothing shipped is absent rather than zero-valued, and the
      // calculator treats that as zero.
      expect(map[fixture.scarceLineId], isNull);
    });

    test('beberapa batch pada satu baris PR dijumlahkan', () async {
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
          // 25 days left is also inside the 30-day alert window, so this one
          // needs an explicit confirmation too (G-E4).
          batchAllocation(
            fixture,
            batchId: fixture.soonBatch.id,
            qty: '2',
            nearExpiryConfirmed: true,
          ),
          batchAllocation(fixture, batchId: fixture.safeBatch.id, qty: '0.5'),
        ],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final map = await context.deliveries.cumulativeShippedByPrLine(
        prId: fixture.purchaseRequestId,
      );
      expect(map[fixture.batchLineId], Quantity.parse('4'));
    });
  });

  group('validasi saat edit', () {
    test('melebihi sisa ditolak saat menyimpan baris', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final lineIds = await deliveryLineIdsByAllocation(context, doId);
      final lineId = lineIds['${fixture.simpleLineId}|']!;

      await expectLater(
        () => context.updateDeliveryLine().call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lineId,
          shippedQty: Quantity.parse('4'),
        ),
        throwsA(isA<DeliveryQuantityExceedsRequestedFailure>()),
      );
    });

    test('alokasi FEFO tidak melebihi sisa permintaan', () async {
      final first = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2')],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: first,
      );
      await context.posting.postInboundWarehouse(
        itemId: fixture.simpleItem.id,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.parse('10'),
        actorUserId: fixture.warehouseUser.id,
      );

      final second = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      final outcomes = await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: second.id,
      );

      final simple = outcomes.firstWhere(
        (outcome) => outcome.prLineId == fixture.simpleLineId,
      );
      // 3 requested, 2 already shipped: the allocator asks for 1 even though the
      // shelf now holds 10.
      expect(simple.allocatedQty, Quantity.parse('1'));
    });

    test('meminta lebih dari sisa pada alokasi FEFO ditolak', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      await expectLater(
        () => context.allocateFefo().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
          requestedByPrLineId: {fixture.simpleLineId: Quantity.parse('99')},
        ),
        throwsA(isA<DeliveryQuantityExceedsRequestedFailure>()),
      );
      expect(await context.deliveryLineCount(order.id), 0);
    });
  });

  group('konkurensi', () {
    test(
      'dua pengiriman memperebutkan sisa yang sama, maksimal satu berhasil',
      () async {
        // Both documents allocate 2 of a 3-unit request against a 2.5-unit shelf.
        // Either alone is legal; together they would ship 4 and take the balance
        // negative. Exactly one must commit.
        final first = await prepareDeliveryOrder(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [simpleAllocation(fixture, qty: '2')],
        );
        final second = await prepareDeliveryOrder(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [simpleAllocation(fixture, qty: '2')],
        );

        final outcomes = await Future.wait<Object?>([
          context
              .shipDeliveryOrder()
              .call(
                actorUserId: fixture.warehouseUser.id,
                deliveryOrderId: first,
              )
              .then<Object?>((result) => result)
              .onError<Object>((error, _) => error),
          context
              .shipDeliveryOrder()
              .call(
                actorUserId: fixture.secondWarehouseUser.id,
                deliveryOrderId: second,
              )
              .then<Object?>((result) => result)
              .onError<Object>((error, _) => error),
        ]);

        final succeeded = outcomes.whereType<ShipmentResult>().length;
        expect(
          succeeded,
          1,
          reason:
              'Tepat satu pengiriman boleh berhasil; total keduanya melebihi sisa '
              'permintaan dan saldo warehouse.',
        );

        // The cumulative total is the one that committed, and nothing partial was
        // left behind by the other.
        expect(await cumulativeSimple(), Quantity.parse('2'));
        final statuses = [
          await context.deliveryOrderStatusOf(first),
          await context.deliveryOrderStatusOf(second),
        ];
        expect(statuses.where((status) => status == 'shipped').length, 1);
        expect(statuses.where((status) => status == 'preparing').length, 1);

        // And the balance never went negative: 2.5 − 2 = 0.5.
        final balances = await context.balancesAt(fixture.warehouse.id);
        expect(balances['${fixture.simpleItem.id}|'], 500);
      },
    );

    test('pengiriman ganda dokumen yang sama ditolak', () async {
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
      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<DeliveryOrderAlreadyShippedFailure>()),
      );

      // Exactly one movement, and the balance dropped exactly once.
      expect(await context.shipmentMovementCount(doId), 1);
      expect(await cumulativeSimple(), Quantity.parse('1'));
      final balances = await context.balancesAt(fixture.warehouse.id);
      expect(balances['${fixture.simpleItem.id}|'], 1500);
    });

    test('status DO shipped tidak dapat diedit lagi', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final lineIds = await deliveryLineIdsByAllocation(context, doId);
      final lineId = lineIds['${fixture.simpleLineId}|']!;

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await expectLater(
        () => context.updateDeliveryLine().call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lineId,
          shippedQty: Quantity.parse('2'),
        ),
        throwsA(isA<DeliveryOrderAlreadyShippedFailure>()),
      );
      await expectLater(
        () => context.removeDeliveryLine.call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lineId,
        ),
        throwsA(isA<DeliveryOrderAlreadyShippedFailure>()),
      );
      await expectLater(
        () => context.allocateFefo().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<DeliveryOrderAlreadyShippedFailure>()),
      );

      // The posted allocation is exactly what the movement was written from.
      expect(await context.deliveryLineCount(doId), 1);
      expect(await context.shipmentMovementCount(doId), 1);
    });

    test('DO received bersifat read-only permanen', () async {
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
      await context.database.customStatement(
        "UPDATE delivery_orders SET status = 'received' WHERE id = ?;",
        [doId],
      );

      final lineIds = await deliveryLineIdsByAllocation(context, doId);
      await expectLater(
        () => context.updateDeliveryLine().call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lineIds['${fixture.simpleLineId}|']!,
          shippedQty: Quantity.parse('2'),
        ),
        throwsA(isA<InvalidDeliveryOrderStateFailure>()),
      );
      expect(
        await context.deliveryOrderStatusOf(doId),
        DeliveryOrderStatus.received.dbValue,
      );
    });
  });
}
