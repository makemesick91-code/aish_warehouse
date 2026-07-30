import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:aish_warehouse/features/delivery/domain/services/delivery_expiry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// **G-E4** — *"Barang sudah kedaluwarsa diblokir total dari DO dan distribusi.
/// Warehouse juga tidak boleh mengirim barang dengan sisa umur <
/// `expiry_alert_days` tanpa konfirmasi eksplisit."*
///
/// Two rules with different strengths, and the difference is the point of most of
/// these tests: an expired batch is refused *whatever* the line says, while a
/// near-expiry one may ship once somebody has said so on the record.
///
/// Every date question is answered in operational time, GMT+8 (T-3/T-10). A batch is
/// usable for the whole of its expiry day and refused from the next day onwards —
/// which is why the boundary tests pin instants either side of the 16:00 UTC
/// changeover rather than either side of UTC midnight.
void main() {
  /// Created only by the groups that need a database. The pure-policy group needs
  /// none at all — the whole point of a policy that is a function of two dates and a
  /// threshold.
  late TestContext context;
  var hasContext = false;

  /// 2026-07-30 11:00 GMT+8.
  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);
  final today = DateOnly.of(2026, 7, 30);

  tearDown(() async {
    if (!hasContext) return;
    await context.dispose();
    hasContext = false;
  });

  Future<DeliveryFixture> setUpAt(DateTime instant) async {
    context = TestContext.create(clock: () => instant);
    hasContext = true;
    return buildDeliveryFixture(context, nowUtc: instant);
  }

  group('kebijakan tanggal operasional', () {
    test('batch valid sebelum tanggal kedaluwarsa', () {
      expect(
        DeliveryExpiryPolicy.isExpired(
          expiryDate: DateOnly.of(2026, 7, 31),
          nowUtc: nowUtc,
        ),
        isFalse,
      );
    });

    test('batch valid pada tanggal kedaluwarsa itu sendiri', () {
      // T-10: valid until the *end* of the expiry date.
      expect(
        DeliveryExpiryPolicy.isExpired(expiryDate: today, nowUtc: nowUtc),
        isFalse,
      );
      expect(
        DeliveryExpiryPolicy.remainingDays(expiryDate: today, nowUtc: nowUtc),
        0,
      );
    });

    test('batch kedaluwarsa pada H+1', () {
      expect(
        DeliveryExpiryPolicy.isExpired(
          expiryDate: DateOnly.of(2026, 7, 29),
          nowUtc: nowUtc,
        ),
        isTrue,
      );
    });

    test('batas hari operasional GMT+8, bukan UTC', () {
      final expiry = DateOnly.of(2026, 7, 30);

      // 2026-07-30 15:59 UTC is still 2026-07-30 23:59 GMT+8 — the batch's last day.
      expect(
        DeliveryExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 30, 15, 59),
        ),
        isFalse,
      );
      // One minute later it is 2026-07-31 00:00 GMT+8, and the batch is out.
      expect(
        DeliveryExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 30, 16, 0),
        ),
        isTrue,
      );
      // A naive UTC-midnight rule would have called both of these valid, and would
      // have called 2026-07-29 17:00 UTC expired when it is already 07-30 GMT+8.
      expect(
        DeliveryExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 29, 17, 0),
        ),
        isFalse,
      );
    });

    test('konfirmasi diperlukan saat sisa umur kurang dari ambang', () {
      bool needs(int daysLeft, int threshold) =>
          DeliveryExpiryPolicy.requiresNearExpiryConfirmation(
            expiryDate: DateOnly.addDays(today, daysLeft),
            expiryAlertDays: threshold,
            nowUtc: nowUtc,
          );

      // The specification says `<`, so equality is *not* inside the window: 30 days
      // left against a 30-day threshold ships unremarked, 29 does not. An off-by-one
      // here would either nag on every shipment or let a nearly-expired batch
      // through silently.
      expect(needs(31, 30), isFalse);
      expect(needs(30, 30), isFalse);
      expect(needs(29, 30), isTrue);
      expect(needs(0, 30), isTrue);
    });

    test('kandidat yang dapat dipakai mengecualikan kedaluwarsa dan nol', () {
      final candidates = [
        DeliveryBatchCandidate(
          batchId: 'expired',
          batchNo: 'X',
          expiryDate: DateOnly.addDays(today, -1),
          availableQty: Quantity.parse('5'),
        ),
        DeliveryBatchCandidate(
          batchId: 'empty',
          batchNo: 'E',
          expiryDate: DateOnly.addDays(today, 10),
          availableQty: Quantity.zero(),
        ),
        DeliveryBatchCandidate(
          batchId: 'ok',
          batchNo: 'O',
          expiryDate: DateOnly.addDays(today, 10),
          availableQty: Quantity.parse('2'),
        ),
      ];

      expect(
        DeliveryExpiryPolicy.usableCandidates(
          candidates: candidates,
          nowUtc: nowUtc,
        ).map((candidate) => candidate.batchId),
        ['ok'],
      );
      expect(
        DeliveryExpiryPolicy.expiredCandidates(
          candidates: candidates,
          nowUtc: nowUtc,
        ).map((candidate) => candidate.batchId),
        ['expired'],
      );
      expect(
        DeliveryExpiryPolicy.usableTotal(
          candidates: candidates,
          nowUtc: nowUtc,
        ),
        Quantity.parse('2'),
      );
    });
  });

  group('batch kedaluwarsa diblokir total', () {
    test('tidak muncul sebagai kandidat FEFO', () async {
      final fixture = await setUpAt(nowUtc);
      final candidates = await context.deliveryStock.batchCandidates(
        warehouseLocationId: fixture.warehouse.id,
        itemId: fixture.batchItem.id,
      );

      // The expired batch holds 3 units, so it is *in* the raw candidate list — the
      // form has to be able to say why it cannot be picked — and out of the usable
      // one.
      expect(
        candidates.map((candidate) => candidate.batchId),
        contains(fixture.expiredBatch.id),
      );
      expect(
        DeliveryExpiryPolicy.usableCandidates(
          candidates: candidates,
          nowUtc: nowUtc,
        ).map((candidate) => candidate.batchId),
        isNot(contains(fixture.expiredBatch.id)),
      );
    });

    test('tidak dipilih oleh alokasi otomatis', () async {
      final fixture = await setUpAt(nowUtc);
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
      );

      final lines = await context.deliveries.lineReferences(order.id);
      expect(
        lines.map((line) => line.batchId),
        isNot(contains(fixture.expiredBatch.id)),
      );
    });

    test('dipilih manual ditolak saat edit', () async {
      final fixture = await setUpAt(nowUtc);
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.safeBatch.id,
            qty: '1',
            fefoOverrideReason: 'Diminta cabang',
          ),
        ],
      );
      final lines = await context.deliveries.lineReferences(order.id);

      await expectLater(
        () => context.updateDeliveryLine().call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lines.single.id,
          shippedQty: Quantity.parse('1'),
          batchId: fixture.expiredBatch.id,
        ),
        throwsA(isA<ExpiredBatchForDeliveryFailure>()),
      );
    });

    test('ditolak lagi saat kirim, meski tersimpan lewat SQL', () async {
      final fixture = await setUpAt(nowUtc);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(fixture, batchId: fixture.expiredBatch.id, qty: '1'),
        ],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<ExpiredBatchForDeliveryFailure>().having(
            (failure) => failure.batchNo,
            'batch',
            fixture.expiredBatch.batchNo,
          ),
        ),
      );
      // Nothing posted, nothing moved, and the batch keeps its stock — which leaves
      // via `disposal` (G-E7), not via a shipment.
      expect(await context.shipmentMovementCount(doId), 0);
      final balances = await context.balancesAt(fixture.warehouse.id);
      expect(
        balances['${fixture.batchItem.id}|${fixture.expiredBatch.id}'],
        3000,
      );
    });

    test(
      'konfirmasi near-expiry tidak dapat meloloskan batch kedaluwarsa',
      () async {
        final fixture = await setUpAt(nowUtc);
        final doId = await prepareDeliveryOrder(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [
            batchAllocation(
              fixture,
              batchId: fixture.expiredBatch.id,
              qty: '1',
              nearExpiryConfirmed: true,
              nearExpiryNote: 'Sudah dikonfirmasi cabang',
              fefoOverrideReason: 'Diminta cabang',
            ),
          ],
        );

        // Expiry is checked *first*, so a stored confirmation is irrelevant. That is
        // the difference between "the officer accepted a short shelf life" and "the
        // officer accepted goods that may not be used".
        await expectLater(
          () => context.shipDeliveryOrder().call(
            actorUserId: fixture.warehouseUser.id,
            deliveryOrderId: doId,
          ),
          throwsA(isA<ExpiredBatchForDeliveryFailure>()),
        );
        expect(await context.shipmentMovementCount(doId), 0);
      },
    );

    test(
      'batch yang kedaluwarsa antara penyiapan dan pengiriman ditolak',
      () async {
        // Prepared while the batch was valid; shipped the next operational day. The
        // check at ship time is against "now", not against when the form was filled.
        final fixture = await setUpAt(nowUtc);
        final expiringToday = await context.master.ensureBatch(
          itemId: fixture.batchItem.id,
          batchNo: 'E-TODAY',
          expiryDate: today,
        );
        await context
            .postingWithClock(() => nowUtc)
            .postInboundWarehouse(
              itemId: fixture.batchItem.id,
              batchId: expiringToday.id,
              toLocationId: fixture.warehouse.id,
              qty: Quantity.parse('2'),
              actorUserId: fixture.warehouseUser.id,
            );

        final doId = await prepareDeliveryOrder(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [
            batchAllocation(
              fixture,
              batchId: expiringToday.id,
              qty: '1',
              nearExpiryConfirmed: true,
            ),
          ],
        );

        // Today it ships — 0 days left is still valid (T-10)…
        final tomorrow = DateTime.utc(2026, 7, 31, 3, 0);
        // …but a day later it does not.
        await expectLater(
          () => context
              .shipDeliveryOrder(clock: () => tomorrow)
              .call(
                actorUserId: fixture.warehouseUser.id,
                deliveryOrderId: doId,
              ),
          throwsA(isA<ExpiredBatchForDeliveryFailure>()),
        );
        expect(await context.shipmentMovementCount(doId), 0);
      },
    );

    test('batch yang berlaku hari ini dapat dikirim hari ini', () async {
      final fixture = await setUpAt(nowUtc);
      final expiringToday = await context.master.ensureBatch(
        itemId: fixture.batchItem.id,
        batchNo: 'E-TODAY',
        expiryDate: today,
      );
      await context
          .postingWithClock(() => nowUtc)
          .postInboundWarehouse(
            itemId: fixture.batchItem.id,
            batchId: expiringToday.id,
            toLocationId: fixture.warehouse.id,
            qty: Quantity.parse('2'),
            actorUserId: fixture.warehouseUser.id,
          );

      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: expiringToday.id,
            qty: '1',
            nearExpiryConfirmed: true,
            nearExpiryNote: 'Dikirim hari ini, dipakai segera',
          ),
        ],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });
  });

  group('konfirmasi near-expiry', () {
    test('tanpa konfirmasi ditolak dengan sisa hari yang tepat', () async {
      final fixture = await setUpAt(nowUtc);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(fixture, batchId: fixture.nearBatch.id, qty: '1'),
        ],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<NearExpiryConfirmationRequiredFailure>()
              .having((failure) => failure.remainingDays, 'sisa hari', 12)
              .having((failure) => failure.expiryAlertDays, 'ambang', 30),
        ),
      );
      expect(await context.shipmentMovementCount(doId), 0);
    });

    test('dengan konfirmasi diterima dan tersimpan untuk audit', () async {
      final fixture = await setUpAt(nowUtc);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
            nearExpiryNote: 'Cabang setuju, dipakai minggu ini',
          ),
        ],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final lines = await context.deliveries.lineReferences(doId);
      expect(lines.single.nearExpiryConfirmed, isTrue);
      expect(lines.single.nearExpiryNote, 'Cabang setuju, dipakai minggu ini');
    });

    test('batch di luar ambang tidak memerlukan konfirmasi', () async {
      final fixture = await setUpAt(nowUtc);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          // 300 days out, and FEFO-compliant only with a reason — the near-expiry
          // rule itself has nothing to say about it.
          batchAllocation(
            fixture,
            batchId: fixture.safeBatch.id,
            qty: '1',
            fefoOverrideReason: 'Cabang minta masa simpan panjang',
          ),
        ],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      final lines = await context.deliveries.lineReferences(doId);
      expect(lines.single.nearExpiryConfirmed, isFalse);
    });

    test('konfirmasi diperlukan lagi bila ambang barang dinaikkan', () async {
      // The threshold is the item's, not a constant: raising it brings batches that
      // were outside the window inside it, and the check is re-run at ship time.
      final fixture = await setUpAt(nowUtc);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.safeBatch.id,
            qty: '1',
            fefoOverrideReason: 'Cabang minta masa simpan panjang',
          ),
        ],
      );
      await context.database.customStatement(
        'UPDATE items SET expiry_alert_days = 400 WHERE id = ?;',
        [fixture.batchItem.id],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<NearExpiryConfirmationRequiredFailure>()),
      );
    });

    test('use case edit menolak batch near-expiry tanpa konfirmasi', () async {
      final fixture = await setUpAt(nowUtc);
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [
          batchAllocation(fixture, batchId: fixture.nearBatch.id, qty: '1'),
        ],
      );
      final lines = await context.deliveries.lineReferences(order.id);

      await expectLater(
        () => context.updateDeliveryLine().call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lines.single.id,
          shippedQty: Quantity.parse('1'),
          batchId: fixture.nearBatch.id,
        ),
        throwsA(isA<NearExpiryConfirmationRequiredFailure>()),
      );

      await context.updateDeliveryLine().call(
        actorUserId: fixture.warehouseUser.id,
        lineId: lines.single.id,
        shippedQty: Quantity.parse('1'),
        batchId: fixture.nearBatch.id,
        nearExpiryConfirmed: true,
      );
      final updated = await context.deliveries.lineReferences(order.id);
      expect(updated.single.nearExpiryConfirmed, isTrue);
    });

    test('barang tanpa ED tidak pernah memerlukan konfirmasi', () async {
      final fixture = await setUpAt(nowUtc);
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

      final lines = await context.deliveries.lineReferences(doId);
      expect(lines.single.batchId, isNull);
      expect(lines.single.nearExpiryConfirmed, isFalse);
      expect(lines.single.nearExpiryNote, isNull);
      expect(lines.single.fefoOverrideReason, isNull);
    });
  });

  group('batch historis', () {
    test('batch yang diarsipkan setelah penyiapan tetap dapat dikirim', () async {
      // The row is history, not absence: the stock it holds is real, and a document
      // already allocated against it must not be strandable by an administrator
      // tidying up master data (§7.2).
      final fixture = await setUpAt(nowUtc);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      await context.archive('item_batches', fixture.nearBatch.id);

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');

      final detail = await context.deliveries.getForWarehouse(doId);
      expect(detail!.lines.single.batchIsHistorical, isTrue);
      expect(detail.usesHistoricalMaster, isTrue);
    });

    test('batch yang hilang menghasilkan kegagalan eksplisit', () async {
      final fixture = await setUpAt(nowUtc);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      await context.corruptByDeleting('item_batches', fixture.nearBatch.id);

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<HistoricalDeliveryReferenceMissingFailure>().having(
            (failure) => failure.entity,
            'entity',
            'item_batches',
          ),
        ),
      );
      expect(await context.shipmentMovementCount(doId), 0);
    });
  });
}
