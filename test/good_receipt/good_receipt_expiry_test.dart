import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_expiry_policy.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_line_decision_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-E5 — *"Di Good Receipt, ED per batch tampil di tiap baris; barang kedaluwarsa /
/// terlalu dekat ED ditolak dengan alasan `kedaluwarsa`"* (§45).
///
/// The rule is **stricter than the shipment's**. On a Delivery Order a near-expiry batch
/// may still be sent after an explicit confirmation (G-E4). Here there is no
/// confirmation that accepts it: both verdicts force `rejected`, and the goods go on the
/// return list.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A receipt whose only position ships [batchId] of the batch-tracked item.
  ///
  /// [confirmNearExpiry] is what the *shipment* needs for a batch inside its alert
  /// window (G-E4) — and the whole point of these tests is that the receipt refuses it
  /// anyway.
  Future<({String grId, String lineId})> receiptOfBatch(
    String batchId, {
    String qty = '1',
    bool confirmNearExpiry = false,
    String? fefoOverrideReason,
    DateTime? shipAt,
  }) async {
    final doId = await shipDeliveryOrderFor(
      context,
      fixture,
      nowUtc: shipAt ?? nowUtc,
      shippedAtUtc: shipAt ?? nowUtc,
      allocations: [
        batchAllocation(
          fixture,
          batchId: batchId,
          qty: qty,
          nearExpiryConfirmed: confirmNearExpiry,
          nearExpiryNote: confirmNearExpiry ? 'Disetujui warehouse' : null,
          fefoOverrideReason: fefoOverrideReason,
        ),
      ],
    );
    final grId = await startGoodReceiptFor(
      context,
      fixture,
      deliveryOrderId: doId,
      nowUtc: nowUtc,
    );
    final detail = await context.receipts.getDetail(grId);
    return (grId: grId, lineId: detail!.lines.single.id);
  }

  Future<void> check(
    ({String grId, String lineId}) target, {
    String qty = '1',
    DateTime? at,
  }) => context
      .checkGoodReceiptLine(clock: at == null ? null : () => at)
      .call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
        goodReceiptLineId: target.lineId,
        receivedQty: Quantity.parse(qty),
      );

  group('kebijakan verdict', () {
    test('batch jauh dari ED valid', () {
      expect(
        GoodReceiptExpiryPolicy.verdictFor(
          expiryDate: DateOnly.addDays(operationalToday(nowUtc), 300),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        GoodReceiptExpiryVerdict.valid,
      );
    });

    test('sisa hari sama dengan ambang masih valid', () {
      // *"sisa umur < expiry_alert_days"*: 30 days left against a 30-day threshold may
      // be accepted, 29 may not. An off-by-one here would either refuse deliveries the
      // branch should take or let a nearly expired batch through unremarked.
      expect(
        GoodReceiptExpiryPolicy.verdictFor(
          expiryDate: DateOnly.addDays(operationalToday(nowUtc), 30),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        GoodReceiptExpiryVerdict.valid,
      );
      expect(
        GoodReceiptExpiryPolicy.verdictFor(
          expiryDate: DateOnly.addDays(operationalToday(nowUtc), 29),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        GoodReceiptExpiryVerdict.nearExpiry,
      );
    });

    test('batch valid pada hari ED itu sendiri', () {
      // A batch is usable for the whole of its expiry day (T-10) — but it is inside its
      // alert window by then, so the verdict is near-expiry rather than valid.
      expect(
        GoodReceiptExpiryPolicy.isExpired(
          expiryDate: operationalToday(nowUtc),
          nowUtc: nowUtc,
        ),
        isFalse,
      );
      expect(
        GoodReceiptExpiryPolicy.verdictFor(
          expiryDate: operationalToday(nowUtc),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        GoodReceiptExpiryVerdict.nearExpiry,
      );
      // With no alert window at all, the expiry day itself is simply valid.
      expect(
        GoodReceiptExpiryPolicy.verdictFor(
          expiryDate: operationalToday(nowUtc),
          expiryAlertDays: 0,
          nowUtc: nowUtc,
        ),
        GoodReceiptExpiryVerdict.valid,
      );
    });

    test('batch kedaluwarsa sehari setelah ED', () {
      expect(
        GoodReceiptExpiryPolicy.verdictFor(
          expiryDate: DateOnly.addDays(operationalToday(nowUtc), -1),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        GoodReceiptExpiryVerdict.expired,
      );
    });

    test('batas hari operasional GMT+8 pada 15:59 dan 16:00 UTC', () {
      // `2026-07-30` GMT+8 starts at `2026-07-29T16:00:00Z`. A batch expiring on
      // 2026-07-29 is therefore still valid at 15:59Z and expired at 16:00Z — one
      // minute apart, and the device's own timezone never enters into it (T-3/T-4).
      final expiry = DateOnly.of(2026, 7, 29);

      expect(
        GoodReceiptExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 29, 15, 59),
        ),
        isFalse,
      );
      expect(
        GoodReceiptExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 29, 16),
        ),
        isTrue,
      );
    });

    test('item tanpa expiry tidak menjalankan kebijakan', () {
      // G-E2: no batch, no verdict. Invoking the policy on a box of masks would be
      // asking a question that has no answer.
      expect(
        GoodReceiptExpiryPolicy.mustBeRejected(
          expiryDate: null,
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        isFalse,
      );
    });

    test('preset penolakan yang dipaksakan adalah kedaluwarsa', () {
      expect(
        GoodReceiptExpiryPolicy.forcedRejectPreset,
        GoodReceiptRejectReasonPreset.expired,
      );
    });
  });

  group('penerimaan batch valid', () {
    test('batch jauh dari ED dapat diterima', () async {
      final target = await receiptOfBatch(
        fixture.safeBatch.id,
        fefoOverrideReason: 'Cabang meminta batch panjang',
      );

      await check(target);

      final line = (await context.receipts.getDetail(
        target.grId,
      ))!.lines.single;
      expect(line.isChecked, isTrue);
      expect(line.mustBeRejectedOn(nowUtc), isFalse);
    });

    test('batch valid dapat diposting dan menambah stok', () async {
      final target = await receiptOfBatch(
        fixture.safeBatch.id,
        fefoOverrideReason: 'Cabang meminta batch panjang',
      );
      await check(target);

      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
      );

      final balances = await context.balancesAt(fixture.branchStore.id);
      expect(
        balances['${fixture.batchItem.id}|${fixture.safeBatch.id}'],
        Quantity.parse('1').milliUnits,
      );
    });
  });

  group('batch terlalu dekat ED wajib ditolak', () {
    test(
      'near-expiry tidak dapat di-check meski dikonfirmasi warehouse',
      () async {
        // `B-NEAR` expires in 12 days against a 30-day threshold. The warehouse's
        // confirmation is what let it *ship* (G-E4); it buys nothing here.
        final target = await receiptOfBatch(
          fixture.nearBatch.id,
          confirmNearExpiry: true,
        );

        final failure = await check(
          target,
        ).then<Object?>((_) => null, onError: (Object error, _) => error);

        expect(failure, isA<GoodReceiptNearExpiryBatchMustBeRejectedFailure>());
        final typed =
            failure as GoodReceiptNearExpiryBatchMustBeRejectedFailure;
        expect(typed.remainingDays, 12);
        expect(typed.expiryAlertDays, 30);
        expect(typed.batchNo, 'B-NEAR');

        final line = (await context.receipts.getDetail(
          target.grId,
        ))!.lines.single;
        expect(line.isPending, isTrue);
      },
    );

    test('near-expiry dapat ditolak dengan alasan kedaluwarsa', () async {
      final target = await receiptOfBatch(
        fixture.nearBatch.id,
        confirmNearExpiry: true,
      );

      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
        goodReceiptLineId: target.lineId,
        reason: GoodReceiptLineDecisionPolicy.composeReason(
          preset: GoodReceiptExpiryPolicy.forcedRejectPreset,
        ),
      );

      final line = (await context.receipts.getDetail(
        target.grId,
      ))!.lines.single;
      expect(line.isRejected, isTrue);
      expect(line.rejectReason, contains('Kedaluwarsa'));
      expect(line.isNearExpiryOn(nowUtc), isTrue);
      expect(line.mustBeRejectedOn(nowUtc), isTrue);
    });

    test('GR dengan near-expiry ditolak dapat diposting tanpa stok', () async {
      final target = await receiptOfBatch(
        fixture.nearBatch.id,
        confirmNearExpiry: true,
      );
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
        goodReceiptLineId: target.lineId,
        reason: 'Kedaluwarsa / terlalu dekat ED',
      );

      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
      );

      expect(await context.goodReceiptStatusOf(target.grId), 'posted');
      expect(await context.goodReceiptMovementCount(target.grId), 0);
      expect(await context.balancesAt(fixture.branchStore.id), isEmpty);
    });
  });

  group('batch kedaluwarsa saat diperiksa', () {
    /// A batch shipped while still valid, checked in after its date passed.
    ///
    /// A shipment refuses an expired batch outright (G-E4), so the only way a receipt
    /// can be holding one is exactly this: the goods travelled, and the date went by on
    /// the way. The *checking* clock moves rather than the shipment's, because the
    /// timestamp policy would refuse a shipment stamped before the request it belongs to
    /// (§36) — which is that rule working, not an obstacle to route around.
    final arrivedUtc = nowUtc.add(const Duration(days: 20));

    Future<({String grId, String lineId})> shippedNearBatch() =>
        receiptOfBatch(fixture.nearBatch.id, confirmNearExpiry: true);

    test('batch yang sudah lewat ED tidak dapat di-check', () async {
      // `B-NEAR` expires 12 days out; twenty days later it is eight days gone.
      final target = await shippedNearBatch();

      final failure = await check(
        target,
        at: arrivedUtc,
      ).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(failure, isA<GoodReceiptExpiredBatchMustBeRejectedFailure>());
      final typed = failure as GoodReceiptExpiredBatchMustBeRejectedFailure;
      expect(typed.batchNo, 'B-NEAR');
      expect(typed.expiryDate, fixture.nearBatch.expiryDate);

      final line = (await context.receipts.getDetail(
        target.grId,
      ))!.lines.single;
      expect(line.isPending, isTrue);
      expect(line.isExpiredOn(arrivedUtc), isTrue);
    });

    test('batch kedaluwarsa harus ditolak, dan lalu dapat diposting', () async {
      final target = await shippedNearBatch();

      await context
          .rejectGoodReceiptLine(clock: () => arrivedUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            goodReceiptId: target.grId,
            goodReceiptLineId: target.lineId,
            reason: 'Kedaluwarsa / terlalu dekat ED',
          );
      await context
          .postGoodReceipt(clock: () => arrivedUtc)
          .call(actorUserId: fixture.branchHead.id, goodReceiptId: target.grId);

      expect(await context.goodReceiptStatusOf(target.grId), 'posted');
      expect(await context.goodReceiptMovementCount(target.grId), 0);
      expect(await context.balancesAt(fixture.branchStore.id), isEmpty);
    });
  });

  group('revalidasi saat posting', () {
    test(
      'batch yang menjadi near-expiry selama checking ditolak saat post',
      () async {
        // Accepted while the batch had plenty of shelf life, posted after it crossed the
        // threshold. Validating only at entry would let this receipt through, and the
        // goods would reach the shelf with nothing to say they should not.
        final target = await receiptOfBatch(
          fixture.safeBatch.id,
          fefoOverrideReason: 'Cabang meminta batch panjang',
        );
        await check(target);

        final laterUtc = nowUtc.add(const Duration(days: 280));

        await expectLater(
          context
              .postGoodReceipt(clock: () => laterUtc)
              .call(
                actorUserId: fixture.branchHead.id,
                goodReceiptId: target.grId,
              ),
          throwsA(isA<GoodReceiptNearExpiryBatchMustBeRejectedFailure>()),
        );
        expect(await context.goodReceiptStatusOf(target.grId), 'checking');
        expect(await context.goodReceiptMovementCount(target.grId), 0);
      },
    );

    test(
      'batch yang menjadi kedaluwarsa selama checking ditolak saat post',
      () async {
        final target = await receiptOfBatch(
          fixture.safeBatch.id,
          fefoOverrideReason: 'Cabang meminta batch panjang',
        );
        await check(target);

        final laterUtc = nowUtc.add(const Duration(days: 400));

        await expectLater(
          context
              .postGoodReceipt(clock: () => laterUtc)
              .call(
                actorUserId: fixture.branchHead.id,
                goodReceiptId: target.grId,
              ),
          throwsA(isA<GoodReceiptExpiredBatchMustBeRejectedFailure>()),
        );
        expect(await context.balancesAt(fixture.branchStore.id), isEmpty);
      },
    );

    test('baris rejected tidak divalidasi ulang terhadap expiry', () async {
      // A refusal is already the answer G-E5 wants, so a batch that expired in the
      // meantime must not block the receipt from being filed.
      final target = await receiptOfBatch(
        fixture.safeBatch.id,
        fefoOverrideReason: 'Cabang meminta batch panjang',
      );
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
        goodReceiptLineId: target.lineId,
        reason: 'Rusak',
      );

      final laterUtc = nowUtc.add(const Duration(days: 400));
      await context
          .postGoodReceipt(clock: () => laterUtc)
          .call(actorUserId: fixture.branchHead.id, goodReceiptId: target.grId);

      expect(await context.goodReceiptStatusOf(target.grId), 'posted');
    });
  });

  group('batch historis dan referensi rusak', () {
    test('batch yang diarsipkan tetap dapat diproses', () async {
      final target = await receiptOfBatch(
        fixture.safeBatch.id,
        fefoOverrideReason: 'Cabang meminta batch panjang',
      );
      // Archiving is not deletion: the stock it holds is real, and the goods are on the
      // branch's counter either way.
      await context.archive('item_batches', fixture.safeBatch.id);

      await check(target);
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
      );

      final line = (await context.receipts.getDetail(
        target.grId,
      ))!.lines.single;
      expect(line.batchIsHistorical, isTrue);
      expect(await context.goodReceiptStatusOf(target.grId), 'posted');
    });

    test('batch yang hilang secara fisik gagal eksplisit', () async {
      final target = await receiptOfBatch(
        fixture.safeBatch.id,
        fefoOverrideReason: 'Cabang meminta batch panjang',
      );
      await check(target);
      await context.corruptByDeleting('item_batches', fixture.safeBatch.id);

      await expectLater(
        context.postGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: target.grId,
        ),
        throwsA(isA<GoodReceiptHistoricalReferenceMissingFailure>()),
      );
      expect(await context.goodReceiptMovementCount(target.grId), 0);
    });

    test('batch milik barang lain ditolak', () async {
      final target = await receiptOfBatch(
        fixture.safeBatch.id,
        fefoOverrideReason: 'Cabang meminta batch panjang',
      );
      // Repointed underneath the receipt, which nothing in the app can do — the point
      // is that the guard notices rather than posting the wrong item's batch.
      await context.database.customStatement(
        'UPDATE good_receipt_lines SET batch_id = ? WHERE id = ?;',
        [fixture.tieBatchA.id, target.lineId],
      );

      await expectLater(
        check(target),
        throwsA(isA<InvalidGoodReceiptBatchFailure>()),
      );
    });

    test('item non-expiry dengan batch ditolak', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final lineId = (await context.receipts.getDetail(grId))!.lines.single.id;
      await context.database.customStatement(
        'UPDATE good_receipt_lines SET batch_id = ? WHERE id = ?;',
        [fixture.safeBatch.id, lineId],
      );

      // G-E2, both directions: an item without expiry never carries a batch.
      await expectLater(
        context.checkGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: lineId,
          receivedQty: Quantity.parse('1'),
        ),
        throwsA(isA<InvalidGoodReceiptBatchFailure>()),
      );
    });
  });

  group('model baris', () {
    test('sisa hari dan badge dihitung dari tanggal operasional', () async {
      final target = await receiptOfBatch(
        fixture.nearBatch.id,
        confirmNearExpiry: true,
      );
      final line = (await context.receipts.getDetail(
        target.grId,
      ))!.lines.single;

      expect(line.remainingDays(nowUtc), 12);
      expect(line.isNearExpiryOn(nowUtc), isTrue);
      expect(line.isExpiredOn(nowUtc), isFalse);
      // Two months later the same line is expired, and *only* expired: the two
      // predicates are kept apart so a badge can say which.
      final later = nowUtc.add(const Duration(days: 60));
      expect(line.isExpiredOn(later), isTrue);
      expect(line.isNearExpiryOn(later), isFalse);
    });

    test('item tanpa expiry tidak melaporkan sisa hari', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final line = (await context.receipts.getDetail(grId))!.lines.single;

      expect(line.hasExpiry, isFalse);
      expect(line.batchId, isNull);
      expect(line.expiryDate, isNull);
      expect(line.remainingDays(nowUtc), isNull);
      expect(line.mustBeRejectedOn(nowUtc), isFalse);
    });
  });
}
