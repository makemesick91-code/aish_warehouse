import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/distribution/domain/models/distribution_models.dart';
import 'package:aish_warehouse/features/distribution/domain/services/distribution_fefo_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-E3 — FEFO for a distribution, and the aggregate evaluation §16 requires (§41).
///
/// The fixture's batch item is built for this: `B-OLD` expires in 10 days and holds
/// only `2`, `A-NEW` expires in 200 days and holds `4`, and `C-EXPIRED` holds `3` that
/// may never move. So the interesting cases are all reachable — a request that must
/// split, a choice that skips older stock, and a tie that is not a violation at all.
///
/// The batch numbers deliberately run against the expiry order (`A-NEW` sorts before
/// `B-OLD`), so an allocator that ordered by name rather than by date would fail here.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);
  final today = DateOnly.from(DateTime.utc(2026, 7, 30));

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draft() =>
      createDistributionDraft(context, fixture, nowUtc: nowUtc);

  DistributionBatchCandidate candidate(
    String id,
    String batchNo,
    int daysFromToday,
    String qty,
  ) => DistributionBatchCandidate(
    batchId: id,
    batchNo: batchNo,
    expiryDate: DateOnly.addDays(today, daysFromToday),
    availableQty: Quantity.parse(qty),
  );

  DistributionAllocation allocation({
    required String roomId,
    required String batchId,
    required String qty,
    String? reason,
  }) => DistributionAllocation(
    roomId: roomId,
    itemId: 'item',
    batchId: batchId,
    qty: Quantity.parse(qty),
    fefoOverrideReason: reason,
  );

  group('alokasi otomatis', () {
    test('batch ED terdekat dipilih lebih dulu', () async {
      final id = await draft();
      final result = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      expect(result.allocations.single.batchId, fixture.oldBatch.id);
    });

    test('alokasi terpecah lintas batch dan berjumlah tepat', () async {
      final id = await draft();
      final result = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '2.5',
        nowUtc: nowUtc,
      );

      expect(result.lineCount, 2);
      // Exact fixed point: 2 + 0.5 is 2.5 with no residue (Q-2).
      expect(result.totalQty, Quantity.parse('2.5'));
      final byBatch = {for (final a in result.allocations) a.batchId: a.qty};
      expect(byBatch[fixture.oldBatch.id], Quantity.parse('2'));
      expect(byBatch[fixture.newBatch.id], Quantity.parse('0.5'));
    });

    test('urutan deterministik pada ED yang sama', () {
      // `(expiry_date, batch_no, batch_id)` — three keys, because the first two can
      // tie and an allocation that depended on row order would differ between two
      // devices holding the same stock.
      final allocations = DistributionFefoPolicy.allocate(
        roomId: 'r1',
        itemId: 'item',
        candidates: [
          candidate('b-2', 'T-B', 100, '2'),
          candidate('b-1', 'T-A', 100, '2'),
        ],
        qty: Quantity.parse('3'),
        nowUtc: nowUtc,
      );

      expect(allocations, isNotNull);
      expect(allocations!.map((a) => a.batchNo), <String>['T-A', 'T-B']);
      expect(allocations.first.qty, Quantity.parse('2'));
      expect(allocations.last.qty, Quantity.parse('1'));
    });

    test('batch kedaluwarsa tidak ikut dialokasikan', () {
      final allocations = DistributionFefoPolicy.allocate(
        roomId: 'r1',
        itemId: 'item',
        candidates: [
          candidate('expired', 'X-EXP', -1, '10'),
          candidate('valid', 'Y-OK', 30, '2'),
        ],
        qty: Quantity.parse('2'),
        nowUtc: nowUtc,
      );

      expect(allocations, hasLength(1));
      expect(allocations!.single.batchId, 'valid');
    });

    test('stok valid kurang mengembalikan null, bukan alokasi sebagian', () {
      final allocations = DistributionFefoPolicy.allocate(
        roomId: 'r1',
        itemId: 'item',
        candidates: [candidate('valid', 'Y-OK', 30, '2')],
        qty: Quantity.parse('3'),
        nowUtc: nowUtc,
      );

      // A half-filled suggestion looks like an answer and is not one.
      expect(allocations, isNull);
    });

    test('barang tanpa ED tidak memakai FEFO', () async {
      final id = await draft();
      final result = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '3',
        nowUtc: nowUtc,
      );

      expect(result.lineCount, 1);
      expect(result.allocations.single.batchId, isNull);
      expect(result.allocations.single.fefoOverrideReason, isNull);
    });
  });

  group('deteksi override', () {
    test('memilih batch lebih muda tanpa alasan ditolak', () async {
      final id = await draft();

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.newBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionFefoOverrideReasonRequiredFailure>()),
      );
      expect(await context.distributionLineCount(id), 0);
    });

    test('alasan hanya spasi ditolak', () async {
      final id = await draft();

      for (final reason in ['', '   ', '\t', '\n  ']) {
        expect(
          () => addManualDistributionAllocation(
            context,
            fixture,
            distributionId: id,
            roomId: fixture.roomOne.id,
            itemId: fixture.batchItem.id,
            batchId: fixture.newBatch.id,
            qty: '1',
            nowUtc: nowUtc,
            fefoOverrideReason: reason,
          ),
          throwsA(isA<DistributionFefoOverrideReasonRequiredFailure>()),
          reason: 'Alasan "$reason" seharusnya ditolak.',
        );
      }
    });

    test('alasan yang sah diterima dan disimpan terpangkas', () async {
      final id = await draft();
      final stored = await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.newBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        fefoOverrideReason: '  Diminta dokter untuk ED panjang  ',
      );

      expect(stored.fefoOverrideReason, 'Diminta dokter untuk ED panjang');
      final rows = await context.distributionLineRows(id);
      expect(
        rows.values.single['fefo_override_reason'],
        'Diminta dokter untuk ED panjang',
      );
    });

    test('kesalahan menyebut batch yang dilewati', () async {
      final id = await draft();

      await expectLater(
        addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.newBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(
          isA<DistributionFefoOverrideReasonRequiredFailure>()
              .having(
                (failure) => failure.skippedBatchNo,
                'skippedBatchNo',
                'B-OLD',
              )
              .having(
                (failure) => failure.selectedBatchNo,
                'selectedBatchNo',
                'A-NEW',
              )
              .having(
                (failure) => failure.message,
                'message',
                allOf(contains('B-OLD'), contains('A-NEW')),
              ),
        ),
      );
    });

    test('ED sama bukan override meski nomor batch berbeda', () async {
      final id = await draft();

      // `T-A` and `T-B` share an expiry date. Choosing `T-B` first skips nothing that
      // expires sooner, so no reason is required — the tie case a naive diff against
      // the canonical allocation gets wrong.
      final stored = await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.tieItem.id,
        batchId: fixture.tieBatchB.id,
        qty: '2',
        nowUtc: nowUtc,
      );

      expect(stored.fefoOverrideReason, isNull);
    });

    test(
      'mengosongkan batch tua lalu memakai yang muda bukan override',
      () async {
        final id = await draft();
        // R1 empties `B-OLD`. R2 may then take `A-NEW` without a reason: nothing older
        // is left to pass over.
        await addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.oldBatch.id,
          qty: '2',
          nowUtc: nowUtc,
        );

        final second = await addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomTwo.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.newBatch.id,
          qty: '2',
          nowUtc: nowUtc,
        );
        expect(second.fefoOverrideReason, isNull);
      },
    );

    test('alasan tanpa pelanggaran tidak disimpan', () async {
      // §9: *reason null jika tidak override*. An audit note explaining a decision
      // nobody made is worse than no note.
      final id = await draft();
      final stored = await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        fefoOverrideReason: 'Alasan yang tidak diperlukan',
      );

      expect(stored.fefoOverrideReason, isNull);
      final rows = await context.distributionLineRows(id);
      expect(rows.values.single['fefo_override_reason'], isNull);
    });

    test('barang tanpa ED tidak pernah menyimpan alasan', () async {
      final id = await draft();
      final stored = await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
        fefoOverrideReason: 'Tidak relevan',
      );

      expect(stored.fefoOverrideReason, isNull);
      final rows = await context.distributionLineRows(id);
      expect(rows.values.single['fefo_override_reason'], isNull);
    });
  });

  group('evaluasi agregat lintas ruangan (§16)', () {
    test('memecah batch muda ke dua ruangan tidak menghindari peringatan', () async {
      // The escape a per-room evaluation would allow: 1 to R1 and 1 to R2 from
      // `A-NEW`, each "only 1" while `B-OLD` still holds 2. Judged per item across
      // every room, both are violations — and the first one already is.
      final id = await draft();

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.newBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionFefoOverrideReasonRequiredFailure>()),
      );

      // With a reason, the first lands. The second room still needs its own reason,
      // because `B-OLD` is *still* untouched.
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.newBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        fefoOverrideReason: 'Permintaan dokter R1',
      );
      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomTwo.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.newBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionFefoOverrideReasonRequiredFailure>()),
      );
    });

    test('violations menjumlahkan pengambilan dari seluruh ruangan', () {
      final candidates = [
        candidate('old', 'B-OLD', 10, '2'),
        candidate('new', 'A-NEW', 200, '4'),
      ];

      // Two rooms each taking 1 of the younger batch: the older batch still has 2, so
      // both draws are violations.
      final split = DistributionFefoPolicy.violations(
        itemId: 'item',
        candidates: candidates,
        selection: [
          allocation(roomId: 'r1', batchId: 'new', qty: '1'),
          allocation(roomId: 'r2', batchId: 'new', qty: '1'),
        ],
        nowUtc: nowUtc,
      );
      expect(split, hasLength(1));
      expect(split.single.selectedBatchNo, 'A-NEW');
      expect(split.single.skippedBatchNo, 'B-OLD');
      expect(split.single.skippedAvailableQty, Quantity.parse('2'));

      // The same total, but the older batch is emptied first: compliant.
      final compliant = DistributionFefoPolicy.violations(
        itemId: 'item',
        candidates: candidates,
        selection: [
          allocation(roomId: 'r1', batchId: 'old', qty: '2'),
          allocation(roomId: 'r2', batchId: 'new', qty: '2'),
        ],
        nowUtc: nowUtc,
      );
      expect(compliant, isEmpty);
    });

    test('candidate netting mencegah batch yang sama dijanjikan dua kali', () {
      final candidates = [candidate('old', 'B-OLD', 10, '2')];
      final remaining = DistributionFefoPolicy.remainingCandidates(
        candidates: candidates,
        alreadyTaken: {'old': Quantity.parse('2')},
      );
      // Nothing left, so the second room cannot be offered the same 2 units.
      expect(remaining, isEmpty);

      final partial = DistributionFefoPolicy.remainingCandidates(
        candidates: candidates,
        alreadyTaken: {'old': Quantity.parse('0.5')},
      );
      expect(partial.single.availableQty, Quantity.parse('1.5'));
    });

    test('alokasi otomatis ruangan kedua meluber ke batch berikutnya', () async {
      final id = await draft();
      // R1 takes 2, emptying `B-OLD`. R2 asks for 2 more, which FEFO can only take
      // from `A-NEW` — and that is not an override, because nothing older remains.
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      final second = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.batchItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );

      expect(second.allocations.single.batchId, fixture.newBatch.id);
      expect(second.allocations.single.fefoOverrideReason, isNull);
    });
  });

  group('revalidasi saat posting', () {
    test('restock batch tua membuat draft lama butuh alasan', () async {
      // §41.15. The draft was compliant when it was built: `B-OLD` was empty, so
      // taking `A-NEW` skipped nothing. A later delivery refills `B-OLD`, and the same
      // selection is now an override — which the posting catches, because it re-asks
      // against live balances rather than trusting the reason the draft stored.
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      // Move the whole allocation onto the younger batch while the older one is
      // drained by another document, so no reason is required yet.
      final other = await draft();
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: other,
        roomId: fixture.roomTwo.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: other);

      final lines = await distributionLineIdsByPosition(context, id);
      final lineId =
          lines['${fixture.roomOne.id}|${fixture.batchItem.id}|'
              '${fixture.oldBatch.id}']!;
      await context
          .updateDistributionLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            distributionId: id,
            lineId: lineId,
            qty: Quantity.parse('2'),
            batchId: fixture.newBatch.id,
          );

      final rows = await context.distributionLineRows(id);
      expect(rows.values.single['fefo_override_reason'], isNull);

      // Now the warehouse refills `B-OLD`.
      final refill = context.postingWithClock(() => nowUtc);
      await refill.postInboundWarehouse(
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.parse('5'),
        actorUserId: fixture.warehouseUser.id,
      );
      await refill.postTransfer(
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: Quantity.parse('5'),
        movementType: StockMovementType.goodReceipt,
        actorUserId: fixture.warehouseUser.id,
      );

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionFefoOverrideReasonRequiredFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
      expect(await context.distributionMovementCount(id), 0);
    });

    test('alasan yang sudah tersimpan tetap lolos saat posting', () async {
      final id = await draft();
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.newBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        fefoOverrideReason: 'Permintaan dokter',
      );

      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(result.distribution.isPosted, isTrue);
      expect(result.hasFefoOverride, isTrue);
      expect(result.progress.overrideCount, 1);
    });

    test('tidak ada substitusi batch otomatis saat posting', () async {
      // The document names `A-NEW`; posting must move `A-NEW` or refuse. Quietly
      // swapping in the FEFO-correct batch would post something the branch head never
      // agreed to.
      final id = await draft();
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.newBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        fefoOverrideReason: 'Permintaan dokter',
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      final movements = await context.distributionMovements(id);
      expect(movements.single['batch_id'], fixture.newBatch.id);
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.batchItem.id,
          batchId: fixture.oldBatch.id,
        ),
        Quantity.parse('2'),
      );
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.batchItem.id,
          batchId: fixture.newBatch.id,
        ),
        Quantity.parse('3'),
      );
    });
  });

  group('kebijakan alasan', () {
    test('hasValidReason menolak seluruh bentuk spasi', () {
      expect(DistributionFefoPolicy.hasValidReason(null), isFalse);
      expect(DistributionFefoPolicy.hasValidReason(''), isFalse);
      expect(DistributionFefoPolicy.hasValidReason('   '), isFalse);
      expect(DistributionFefoPolicy.hasValidReason('\t\n'), isFalse);
      expect(DistributionFefoPolicy.hasValidReason(' ok '), isTrue);
    });

    test('normalizeReason memangkas dan mengosongkan', () {
      expect(DistributionFefoPolicy.normalizeReason('  ok  '), 'ok');
      expect(DistributionFefoPolicy.normalizeReason('   '), isNull);
      expect(DistributionFefoPolicy.normalizeReason(null), isNull);
    });

    test('overriddenBatchIds menyebut hanya batch yang melanggar', () {
      final ids = DistributionFefoPolicy.overriddenBatchIds(
        itemId: 'item',
        candidates: [
          candidate('old', 'B-OLD', 10, '2'),
          candidate('new', 'A-NEW', 200, '4'),
        ],
        selection: [
          allocation(roomId: 'r1', batchId: 'old', qty: '1'),
          allocation(roomId: 'r1', batchId: 'new', qty: '1'),
        ],
        nowUtc: nowUtc,
      );

      // `B-OLD` still has 1 left, so drawing on `A-NEW` at all is the violation — and
      // the reason belongs on that line, not on the compliant one.
      expect(ids, {'new'});
    });
  });
}
