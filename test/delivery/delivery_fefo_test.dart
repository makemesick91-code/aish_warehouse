import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:aish_warehouse/features/delivery/domain/services/delivery_fefo_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// **G-E3** — *"FEFO: sistem otomatis menyarankan batch dengan ED terdekat lebih
/// dulu. Memilih batch yang lebih muda dari saran FEFO memunculkan peringatan +
/// catatan wajib."*
///
/// Two things are tested, and the second is the subtle one.
///
/// The **suggestion** must consume nearest expiry first, split across batches when
/// one is not enough, order deterministically when expiry dates tie, skip expired
/// stock entirely, and refuse to return a partial answer.
///
/// The **check** must fire exactly when the officer passed over stock that expires
/// sooner — and *not* fire when two batches share an expiry date. That case is why
/// the check is stated directly rather than as a diff against the canonical
/// allocation: the canonical answer has to pick one of two equally correct batches,
/// and an officer who picks the other has violated nothing.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);
  final today = DateOnly.of(2026, 7, 30);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A synthetic candidate list, for the pure-policy tests.
  DeliveryBatchCandidate candidate(
    String batchNo, {
    required int daysUntilExpiry,
    required String qty,
  }) => DeliveryBatchCandidate(
    batchId: 'batch-$batchNo',
    batchNo: batchNo,
    expiryDate: DateOnly.addDays(today, daysUntilExpiry),
    availableQty: Quantity.parse(qty),
  );

  /// Asks the allocator for [qty] of one position and **explicitly nothing** of the
  /// others.
  ///
  /// A position absent from the map gets its whole outstanding quantity — the
  /// behaviour the *Alokasikan FEFO* button wants — so isolating one position means
  /// naming zero for the rest rather than omitting them.
  Map<String, Quantity> only(String prLineId, String qty) => {
    for (final id in [
      fixture.simpleLineId,
      fixture.batchLineId,
      fixture.scarceLineId,
      fixture.tieLineId,
    ])
      id: id == prLineId ? Quantity.parse(qty) : Quantity.zero(),
  };

  DeliveryAllocation take(String batchNo, String qty, {String? reason}) =>
      DeliveryAllocation(
        prLineId: 'pr-line',
        itemId: 'item',
        batchId: 'batch-$batchNo',
        qty: Quantity.parse(qty),
        fefoOverrideReason: reason,
      );

  group('algoritme kanonik', () {
    test('expiry terdekat dipilih lebih dulu', () {
      final allocations = DeliveryFefoPolicy.allocate(
        prLineId: 'pr-line',
        itemId: 'item',
        candidates: [
          candidate('SAFE', daysUntilExpiry: 300, qty: '10'),
          candidate('NEAR', daysUntilExpiry: 10, qty: '5'),
          candidate('MID', daysUntilExpiry: 100, qty: '5'),
        ],
        qty: Quantity.parse('3'),
        nowUtc: nowUtc,
      );

      expect(allocations, hasLength(1));
      expect(allocations!.single.batchNo, 'NEAR');
      expect(allocations.single.qty, Quantity.parse('3'));
    });

    test('kuantitas dipecah ke beberapa batch dan berjumlah tepat', () {
      final allocations = DeliveryFefoPolicy.allocate(
        prLineId: 'pr-line',
        itemId: 'item',
        candidates: [
          candidate('NEAR', daysUntilExpiry: 10, qty: '1.5'),
          candidate('MID', daysUntilExpiry: 100, qty: '2'),
          candidate('SAFE', daysUntilExpiry: 300, qty: '10'),
        ],
        qty: Quantity.parse('2.375'),
        nowUtc: nowUtc,
      );

      expect(allocations!.map((allocation) => allocation.batchNo), [
        'NEAR',
        'MID',
      ]);
      expect(allocations[0].qty, Quantity.parse('1.5'));
      expect(allocations[1].qty, Quantity.parse('0.875'));
      // Exact fixed point: the split always sums back to what was asked for.
      expect(
        Quantity.sum(allocations.map((allocation) => allocation.qty)),
        Quantity.parse('2.375'),
      );
    });

    test('urutan deterministik saat expiry sama', () {
      // `(expiry_date, batch_no, batch_id)` — three keys, because the first two can
      // tie and an allocation that depended on the order rows came back in would
      // differ between two devices holding the same stock.
      final candidates = [
        candidate('T-B', daysUntilExpiry: 100, qty: '1'),
        candidate('T-A', daysUntilExpiry: 100, qty: '1'),
      ];
      final first = DeliveryFefoPolicy.allocate(
        prLineId: 'pr-line',
        itemId: 'item',
        candidates: candidates,
        qty: Quantity.parse('1.5'),
        nowUtc: nowUtc,
      );
      final second = DeliveryFefoPolicy.allocate(
        prLineId: 'pr-line',
        itemId: 'item',
        candidates: candidates.reversed.toList(),
        qty: Quantity.parse('1.5'),
        nowUtc: nowUtc,
      );

      expect(first!.map((allocation) => allocation.batchNo), ['T-A', 'T-B']);
      expect(
        second!.map((allocation) => allocation.batchNo),
        first.map((allocation) => allocation.batchNo),
      );
    });

    test('batch kedaluwarsa diabaikan sepenuhnya', () {
      final allocations = DeliveryFefoPolicy.allocate(
        prLineId: 'pr-line',
        itemId: 'item',
        candidates: [
          candidate('EXPIRED', daysUntilExpiry: -1, qty: '100'),
          candidate('SAFE', daysUntilExpiry: 300, qty: '2'),
        ],
        qty: Quantity.parse('2'),
        nowUtc: nowUtc,
      );

      expect(allocations!.single.batchNo, 'SAFE');
    });

    test('batch nol saldo diabaikan', () {
      final allocations = DeliveryFefoPolicy.allocate(
        prLineId: 'pr-line',
        itemId: 'item',
        candidates: [
          candidate('EMPTY', daysUntilExpiry: 5, qty: '0'),
          candidate('SAFE', daysUntilExpiry: 300, qty: '2'),
        ],
        qty: Quantity.parse('1'),
        nowUtc: nowUtc,
      );

      expect(allocations!.single.batchNo, 'SAFE');
    });

    test('stok valid kurang menolak seluruh alokasi, bukan sebagian', () {
      // A half-filled suggestion looks like an answer and is not one: the officer
      // would have to notice the shortfall themselves.
      final allocations = DeliveryFefoPolicy.allocate(
        prLineId: 'pr-line',
        itemId: 'item',
        candidates: [
          candidate('EXPIRED', daysUntilExpiry: -1, qty: '100'),
          candidate('SAFE', daysUntilExpiry: 300, qty: '1'),
        ],
        qty: Quantity.parse('2'),
        nowUtc: nowUtc,
      );

      expect(allocations, isNull);
    });

    test('qty nol menghasilkan alokasi kosong, bukan null', () {
      expect(
        DeliveryFefoPolicy.allocate(
          prLineId: 'pr-line',
          itemId: 'item',
          candidates: [candidate('SAFE', daysUntilExpiry: 300, qty: '1')],
          qty: Quantity.zero(),
          nowUtc: nowUtc,
        ),
        isEmpty,
      );
    });
  });

  group('deteksi pelanggaran', () {
    test(
      'mengambil batch lebih muda saat yang lebih tua bersaldo adalah pelanggaran',
      () {
        final violations = DeliveryFefoPolicy.violations(
          candidates: [
            candidate('NEAR', daysUntilExpiry: 10, qty: '5'),
            candidate('SAFE', daysUntilExpiry: 300, qty: '5'),
          ],
          selection: [take('SAFE', '2')],
          nowUtc: nowUtc,
        );

        expect(violations, hasLength(1));
        expect(violations.single.selectedBatchNo, 'SAFE');
        expect(violations.single.skippedBatchNo, 'NEAR');
        expect(violations.single.skippedAvailableQty, Quantity.parse('5'));
      },
    );

    test('menghabiskan batch tertua lalu lanjut bukan pelanggaran', () {
      final violations = DeliveryFefoPolicy.violations(
        candidates: [
          candidate('NEAR', daysUntilExpiry: 10, qty: '2'),
          candidate('SAFE', daysUntilExpiry: 300, qty: '5'),
        ],
        selection: [take('NEAR', '2'), take('SAFE', '1')],
        nowUtc: nowUtc,
      );

      expect(violations, isEmpty);
    });

    test('expiry yang sama bukan batch lebih muda', () {
      // The case a naive diff against the canonical allocation gets wrong: the
      // canonical answer picks `T-A` by batch number, and an officer picking `T-B`
      // has passed over nothing that expires sooner.
      final violations = DeliveryFefoPolicy.violations(
        candidates: [
          candidate('T-A', daysUntilExpiry: 100, qty: '2'),
          candidate('T-B', daysUntilExpiry: 100, qty: '2'),
        ],
        selection: [take('T-B', '2')],
        nowUtc: nowUtc,
      );

      expect(violations, isEmpty);
    });

    test('batch kedaluwarsa yang dilewati bukan pelanggaran', () {
      // Stock that may not legally move is not stock that was "passed over".
      final violations = DeliveryFefoPolicy.violations(
        candidates: [
          candidate('EXPIRED', daysUntilExpiry: -1, qty: '10'),
          candidate('SAFE', daysUntilExpiry: 300, qty: '5'),
        ],
        selection: [take('SAFE', '2')],
        nowUtc: nowUtc,
      );

      expect(violations, isEmpty);
    });

    test('batch tertua yang habis bukan pelanggaran', () {
      final violations = DeliveryFefoPolicy.violations(
        candidates: [
          candidate('EMPTY', daysUntilExpiry: 5, qty: '0'),
          candidate('SAFE', daysUntilExpiry: 300, qty: '5'),
        ],
        selection: [take('SAFE', '2')],
        nowUtc: nowUtc,
      );

      expect(violations, isEmpty);
    });

    test(
      'batch yang dilewati dilaporkan adalah yang paling dekat kedaluwarsa',
      () {
        final violations = DeliveryFefoPolicy.violations(
          candidates: [
            candidate('MID', daysUntilExpiry: 50, qty: '1'),
            candidate('NEAREST', daysUntilExpiry: 5, qty: '1'),
            candidate('SAFE', daysUntilExpiry: 300, qty: '5'),
          ],
          selection: [take('SAFE', '2')],
          nowUtc: nowUtc,
        );

        // Both older batches were skipped; the actionable one to name is the nearest.
        expect(violations.single.skippedBatchNo, 'NEAREST');
      },
    );

    test('alasan kosong dan spasi tidak sah, alasan terisi sah', () {
      expect(DeliveryFefoPolicy.hasValidReason(null), isFalse);
      expect(DeliveryFefoPolicy.hasValidReason(''), isFalse);
      expect(DeliveryFefoPolicy.hasValidReason('   '), isFalse);
      expect(
        DeliveryFefoPolicy.hasValidReason(' Cabang minta batch baru '),
        isTrue,
      );
    });
  });

  group('alokasi otomatis pada dokumen nyata', () {
    test('Alokasikan FEFO memilih batch terdekat lebih dulu', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
      );

      final lines = await context.deliveries.lineReferences(order.id);
      final batchLines = lines
          .where((line) => line.prLineId == fixture.batchLineId)
          .toList();

      // 4 requested; FEFO order is B-NEAR (12d, 1.5) → A-SOON (25d, 2) →
      // C-SAFE (300d, 6), so the answer is 1.5 + 2 + 0.5. The batch *numbers* are
      // deliberately not in expiry order, so an allocator sorting by name would
      // produce something else.
      final byBatch = {
        for (final line in batchLines) line.batchId: line.shippedQty,
      };
      expect(byBatch[fixture.nearBatch.id], Quantity.parse('1.5'));
      expect(byBatch[fixture.soonBatch.id], Quantity.parse('2'));
      expect(byBatch[fixture.safeBatch.id], Quantity.parse('0.5'));
      // The expired batch holds 3 units and is never touched.
      expect(byBatch.containsKey(fixture.expiredBatch.id), isFalse);
    });

    test(
      'alokasi otomatis tidak pernah mencentang konfirmasi near-expiry',
      () async {
        final order = await context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: fixture.purchaseRequestId,
        );
        await context.allocateFefo().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        );

        final lines = await context.deliveries.lineReferences(order.id);
        // G-E4's "konfirmasi eksplisit" would be a formality if the allocator ticked
        // it — even for its own nearest-expiry answer.
        expect(lines.every((line) => !line.nearExpiryConfirmed), isTrue);
        expect(lines.every((line) => line.fefoOverrideReason == null), isTrue);
      },
    );

    test(
      'alokasi otomatis tidak melanggar FEFO dan dapat dikirim setelah konfirmasi',
      () async {
        final order = await context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: fixture.purchaseRequestId,
        );
        await context.allocateFefo().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
          requestedByPrLineId: only(fixture.batchLineId, '1'),
        );

        final lines = await context.deliveries.lineReferences(order.id);
        expect(lines, hasLength(1));
        expect(lines.single.batchId, fixture.nearBatch.id);

        // 12 days left against a 30-day threshold, so it needs a confirmation — but
        // never a FEFO reason, because nearest-expiry-first is by definition
        // compliant.
        await expectLater(
          () => context.shipDeliveryOrder().call(
            actorUserId: fixture.warehouseUser.id,
            deliveryOrderId: order.id,
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
        await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        );
        expect(await context.deliveryOrderStatusOf(order.id), 'shipped');
      },
    );

    test(
      'kekurangan stok dilaporkan per posisi, bukan membatalkan dokumen',
      () async {
        final order = await context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: fixture.purchaseRequestId,
        );
        final outcomes = await context.allocateFefo().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        );

        final scarce = outcomes.firstWhere(
          (outcome) => outcome.prLineId == fixture.scarceLineId,
        );
        expect(scarce.isEmpty, isTrue);
        expect(scarce.isShort, isTrue);
        expect(scarce.availableQty, Quantity.zero());

        final simple = outcomes.firstWhere(
          (outcome) => outcome.prLineId == fixture.simpleLineId,
        );
        // 3 requested, 2.5 on the shelf: clamped and reported, not refused.
        expect(simple.allocatedQty, Quantity.parse('2.5'));
        expect(simple.isShort, isTrue);

        // And the other seven-eighths of the document is allocated regardless.
        expect(await context.deliveryLineCount(order.id), greaterThan(2));
      },
    );

    test('stok kedaluwarsa dilaporkan terpisah dari stok tersedia', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      final outcomes = await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
      );

      final batched = outcomes.firstWhere(
        (outcome) => outcome.prLineId == fixture.batchLineId,
      );
      // "There is stock, but not stock you may send" is a different answer from
      // "there is none", and an officer needs to be told which.
      expect(batched.availableQty, Quantity.parse('9.5'));
      expect(batched.expiredQty, Quantity.parse('3'));
    });

    test('alokasi ulang mengganti seluruh alokasi sebelumnya', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
      );
      final firstCount = await context.deliveryLineCount(order.id);

      await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
        requestedByPrLineId: only(fixture.simpleLineId, '1'),
      );

      // A document holding half of yesterday's answer and half of today's is not a
      // state anybody should be able to observe, let alone ship.
      expect(await context.deliveryLineCount(order.id), 1);
      expect(firstCount, greaterThan(1));
      final lines = await context.deliveries.lineReferences(order.id);
      expect(lines.single.prLineId, fixture.simpleLineId);
    });
  });

  group('penggantian batch manual', () {
    Future<String> preparedWithSafeBatch({String? reason}) async {
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
            fefoOverrideReason: reason,
          ),
        ],
      );
      return order.id;
    }

    test(
      'mengambil batch lebih muda tanpa alasan ditolak saat kirim',
      () async {
        final doId = await preparedWithSafeBatch();

        await expectLater(
          () => context.shipDeliveryOrder().call(
            actorUserId: fixture.warehouseUser.id,
            deliveryOrderId: doId,
          ),
          throwsA(
            isA<FefoOverrideReasonRequiredFailure>().having(
              (failure) => failure.skippedBatchNo,
              'batch yang dilewati',
              fixture.nearBatch.batchNo,
            ),
          ),
        );
        expect(await context.shipmentMovementCount(doId), 0);
      },
    );

    test('alasan berisi spasi saja ditolak', () async {
      final doId = await preparedWithSafeBatch(reason: '   ');

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<FefoOverrideReasonRequiredFailure>()),
      );
    });

    test('alasan valid diterima dan tersimpan', () async {
      final doId = await preparedWithSafeBatch(
        reason: 'Cabang minta batch dengan masa simpan panjang',
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final lines = await context.deliveries.lineReferences(doId);
      expect(
        lines.single.fefoOverrideReason,
        'Cabang minta batch dengan masa simpan panjang',
      );
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });

    test('use case edit menolak batch lebih muda tanpa alasan', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
        requestedByPrLineId: only(fixture.batchLineId, '1'),
      );
      final lines = await context.deliveries.lineReferences(order.id);

      // Switching FEFO's own answer for a younger batch, without saying why.
      await expectLater(
        () => context.updateDeliveryLine().call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lines.single.id,
          shippedQty: Quantity.parse('1'),
          batchId: fixture.safeBatch.id,
        ),
        throwsA(isA<FefoOverrideReasonRequiredFailure>()),
      );

      // With a reason it goes through.
      await context.updateDeliveryLine().call(
        actorUserId: fixture.warehouseUser.id,
        lineId: lines.single.id,
        shippedQty: Quantity.parse('1'),
        batchId: fixture.safeBatch.id,
        fefoOverrideReason: 'Permintaan khusus cabang',
      );
      final updated = await context.deliveries.lineReferences(order.id);
      expect(updated.single.batchId, fixture.safeBatch.id);
    });

    test('FEFO direvalidasi saat kirim dengan saldo terkini', () async {
      // Compliant when the form was filled in — the nearest-expiry batches were
      // empty — and a violation by the time it ships, because they were restocked.
      // The reason (or its absence) the line stores is not the authority.
      final tieDoId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          DeliveryAllocation(
            prLineId: fixture.tieLineId,
            itemId: fixture.tieItem.id,
            batchId: fixture.tieBatchB.id,
            qty: Quantity.parse('1'),
          ),
        ],
      );
      // Tie expiry: no violation, so this ships cleanly.
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: tieDoId,
      );

      // Now the same shape with a genuinely older batch appearing in between.
      final newerBatch = await context.master.ensureBatch(
        itemId: fixture.tieItem.id,
        batchNo: 'T-C',
        expiryDate: DateOnly.addDays(today, 10),
      );
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          DeliveryAllocation(
            prLineId: fixture.tieLineId,
            itemId: fixture.tieItem.id,
            batchId: fixture.tieBatchA.id,
            qty: Quantity.parse('1'),
          ),
        ],
      );
      // The older batch is stocked *after* the allocation was made.
      await context.posting.postInboundWarehouse(
        itemId: fixture.tieItem.id,
        batchId: newerBatch.id,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.parse('5'),
        actorUserId: fixture.warehouseUser.id,
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<FefoOverrideReasonRequiredFailure>().having(
            (failure) => failure.skippedBatchNo,
            'batch yang dilewati',
            'T-C',
          ),
        ),
      );
      expect(await context.shipmentMovementCount(doId), 0);
    });

    test('tidak ada penggantian batch otomatis saat kirim', () async {
      // The refusal above must be a refusal, not a silent substitution: the stored
      // allocation is exactly what it was.
      final doId = await preparedWithSafeBatch();

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<FefoOverrideReasonRequiredFailure>()),
      );

      final lines = await context.deliveries.lineReferences(doId);
      expect(lines.single.batchId, fixture.safeBatch.id);
      expect(lines.single.shippedQty, Quantity.parse('1'));
    });

    test('mengubah batch membatalkan konfirmasi near-expiry sebelumnya', () async {
      // The new batch's shelf life is a different fact; carrying the tick over would
      // be the silent auto-confirmation G-E4 forbids. The use case simply stores
      // what it is given, and the widget clears it — asserted here through the
      // use case's own refusal when a stale `true` is not passed.
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      final lines = await context.deliveries.lineReferences(order.id);

      await context.updateDeliveryLine().call(
        actorUserId: fixture.warehouseUser.id,
        lineId: lines.single.id,
        shippedQty: Quantity.parse('1'),
        batchId: fixture.safeBatch.id,
        fefoOverrideReason: 'Diminta cabang',
      );

      final updated = await context.deliveries.lineReferences(order.id);
      expect(updated.single.batchId, fixture.safeBatch.id);
      expect(updated.single.nearExpiryConfirmed, isFalse);
      expect(updated.single.nearExpiryNote, isNull);
    });
  });
}
