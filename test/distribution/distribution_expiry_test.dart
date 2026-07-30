import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/distribution/domain/models/distribution_models.dart';
import 'package:aish_warehouse/features/distribution/domain/services/distribution_expiry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-E4 — *"Barang sudah kedaluwarsa diblokir total dari DO dan distribusi"* (§42).
///
/// One rule, absolutely: an expired batch cannot be picked, cannot be saved, cannot be
/// posted, and no note or confirmation changes that. The stock stays on the shelf and
/// leaves through disposal (G-E7), a document this milestone does not open — so the
/// tests below also assert that the expired balance is still *there* afterwards.
///
/// Every date question is answered in operational time (GMT+8). A batch is usable for
/// the whole of its expiry day and refused from the next day onwards (T-10), which puts
/// the boundary at 16:00 UTC — and there is a test for each side of it.
///
/// The near-expiry rule is deliberately **not** a gate here. G-E4 gives the explicit
/// confirmation requirement to the warehouse building a Delivery Order; widening it to
/// the branch head's distribution would invent a rule the specification does not state,
/// and a near-expiry batch in a branch store is exactly the stock that should be used
/// next. What the branch head gets is the badge G-E6 asks for.
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

  group('batas hari operasional', () {
    test('batch valid sebelum tanggal ED', () {
      expect(
        DistributionExpiryPolicy.isExpired(
          expiryDate: DateOnly.addDays(today, 1),
          nowUtc: nowUtc,
        ),
        isFalse,
      );
    });

    test('batch valid pada tanggal ED itu sendiri', () {
      // A batch is usable for the whole of its expiry day (T-10).
      expect(
        DistributionExpiryPolicy.isExpired(expiryDate: today, nowUtc: nowUtc),
        isFalse,
      );
      expect(
        DistributionExpiryPolicy.remainingDays(
          expiryDate: today,
          nowUtc: nowUtc,
        ),
        0,
      );
    });

    test('batch kedaluwarsa sehari setelah ED', () {
      expect(
        DistributionExpiryPolicy.isExpired(
          expiryDate: DateOnly.addDays(today, -1),
          nowUtc: nowUtc,
        ),
        isTrue,
      );
      expect(
        DistributionExpiryPolicy.remainingDays(
          expiryDate: DateOnly.addDays(today, -1),
          nowUtc: nowUtc,
        ),
        -1,
      );
    });

    test('batas 15:59 dan 16:00 UTC memindahkan hari operasional', () {
      // 2026-07-30 GMT+8 runs from 2026-07-29T16:00Z to 2026-07-30T15:59:59.999999Z.
      // A batch expiring on 2026-07-30 is therefore still valid at 15:59Z and expired
      // at 16:00Z — the same instant one minute apart, on either side of the boundary.
      final expiry = DateOnly.of(2026, 7, 30);

      expect(
        DistributionExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 30, 15, 59),
        ),
        isFalse,
      );
      expect(
        DistributionExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 30, 16),
        ),
        isTrue,
      );
    });

    test('tanggal ED tidak pernah dikonversi zona waktu', () {
      // T-9: `expiry_date` is a civil date printed on a package, and shifting it by a
      // timezone is exactly the bug `DateOnly` exists to prevent.
      final candidate = DistributionBatchCandidate(
        batchId: 'b',
        batchNo: 'B',
        expiryDate: DateOnly.of(2026, 7, 30),
        availableQty: Quantity.parse('1'),
      );
      expect(DateOnly.formatIso(candidate.expiryDate), '2026-07-30');
      expect(candidate.expiryDate.isUtc, isTrue);
      expect(candidate.expiryDate.hour, 0);
    });
  });

  group('pemblokiran total', () {
    test('batch kedaluwarsa tidak muncul sebagai kandidat', () async {
      final stock = await context.distributions.branchStockFor(
        branchStoreLocationId: fixture.branchStore.id,
        itemId: fixture.batchItem.id,
        nowUtc: nowUtc,
      );

      expect(stock!.candidates.map((candidate) => candidate.batchId), <String>[
        fixture.oldBatch.id,
        fixture.newBatch.id,
      ]);
      // The expired stock is reported separately so the form can explain it rather
      // than silently omitting it — and never offered as a choice.
      expect(
        stock.expiredCandidates.map((candidate) => candidate.batchId),
        <String>[fixture.expiredBatch.id],
      );
      expect(stock.hasExpiredStock, isTrue);
      // The usable total counts only the 6 valid units, never the 3 expired ones.
      expect(stock.availableQty, Quantity.parse('6'));
    });

    test('batch kedaluwarsa tidak dapat dipilih manual', () async {
      final id = await draft();

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.expiredBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<ExpiredBatchForDistributionFailure>()),
      );
      expect(await context.distributionLineCount(id), 0);
    });

    test('catatan tidak dapat meloloskan batch kedaluwarsa', () async {
      final id = await draft();

      // No reason, note or confirmation passes G-E4 — the difference from G-E3, where a
      // written reason is exactly what makes an override acceptable.
      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.expiredBatch.id,
          qty: '1',
          nowUtc: nowUtc,
          fefoOverrideReason: 'Disetujui oleh kepala klinik',
        ),
        throwsA(isA<ExpiredBatchForDistributionFailure>()),
      );
    });

    test('batch yang kedaluwarsa setelah draft dibuat menolak posting', () async {
      // The run that matters. `B-OLD` expires in 10 days, so a draft built today is
      // fine; posting it eleven days later is not, and the goods would otherwise land
      // in a treatment room unusable.
      final id = await draft();
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final later = nowUtc.add(const Duration(days: 11));
      expect(
        () => context
            .postDistribution(clock: () => later)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<ExpiredBatchForDistributionFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
      expect(await context.distributionMovementCount(id), 0);
    });

    test('batch masih valid pada hari ED-nya saat posting', () async {
      final id = await draft();
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      // Ten days out is `B-OLD`'s expiry day itself — still valid, all day.
      final onExpiryDay = nowUtc.add(const Duration(days: 10));
      final result = await context
          .postDistribution(clock: () => onExpiryDay)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);
      expect(result.distribution.isPosted, isTrue);
    });

    test('stok kedaluwarsa tetap berada di gudang cabang', () async {
      // G-E7: expired goods leave through disposal, not through a distribution. So the
      // balance is still there afterwards, waiting for a document this milestone does
      // not open.
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '6',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.batchItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('3'),
      );
      // And it never moved anywhere.
      final movements = await context.distributionMovements(id);
      expect(
        movements.map((movement) => movement['batch_id']),
        isNot(contains(fixture.expiredBatch.id)),
      );
    });

    test(
      'barang yang seluruh stoknya kedaluwarsa dilaporkan sebagai tanpa stok',
      () async {
        // Every valid unit gone, three expired ones left. The message has to say
        // "expired, dispose of it" rather than "out of stock, reorder it".
        final drain = await draft();
        await addDistributionItem(
          context,
          fixture,
          distributionId: drain,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          qty: '6',
          nowUtc: nowUtc,
        );
        await context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: drain);

        final id = await draft();
        await expectLater(
          addDistributionItem(
            context,
            fixture,
            distributionId: id,
            roomId: fixture.roomTwo.id,
            itemId: fixture.batchItem.id,
            qty: '1',
            nowUtc: nowUtc,
          ),
          throwsA(
            isA<DistributionItemHasNoStockFailure>().having(
              (failure) => failure.message,
              'message',
              contains('kedaluwarsa'),
            ),
          ),
        );
      },
    );
  });

  group('mendekati kedaluwarsa', () {
    test('near-expiry dilaporkan tetapi tidak memblokir', () async {
      // `B-OLD` has 10 days left against a 30-day threshold: inside the window, and
      // distributable. FEFO puts it first, which is exactly what should happen to
      // stock that is about to expire.
      expect(
        DistributionExpiryPolicy.isNearExpiry(
          expiryDate: DateOnly.addDays(today, 10),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        isTrue,
      );

      final id = await draft();
      final result = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      expect(result.allocations.single.batchId, fixture.oldBatch.id);

      final posted = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);
      expect(posted.distribution.isPosted, isTrue);
    });

    test('ambang near-expiry memakai perbandingan lebih kecil dari', () {
      // Worded *"sisa umur < expiry_alert_days"*, so 30 of 30 is outside the window and
      // 29 is inside it. An off-by-one here would badge every batch or none.
      expect(
        DistributionExpiryPolicy.isNearExpiry(
          expiryDate: DateOnly.addDays(today, 30),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        isFalse,
      );
      expect(
        DistributionExpiryPolicy.isNearExpiry(
          expiryDate: DateOnly.addDays(today, 29),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        isTrue,
      );
    });

    test('batch kedaluwarsa bukan near-expiry', () {
      // Two different verdicts, kept apart so a badge can say *kedaluwarsa* rather than
      // *segera kedaluwarsa*.
      expect(
        DistributionExpiryPolicy.isNearExpiry(
          expiryDate: DateOnly.addDays(today, -1),
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        isFalse,
      );
      expect(
        DistributionExpiryPolicy.isExpired(
          expiryDate: DateOnly.addDays(today, -1),
          nowUtc: nowUtc,
        ),
        isTrue,
      );
    });

    test('baris melaporkan near-expiry dan kedaluwarsa terpisah', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
        nowUtc: nowUtc,
      );

      final detail = await context.distributions.getDetail(id);
      final lines = {for (final line in detail!.lines) line.batchId: line};
      expect(lines[fixture.oldBatch.id]!.isNearExpiryOn(nowUtc), isTrue);
      expect(lines[fixture.oldBatch.id]!.isExpiredOn(nowUtc), isFalse);
      expect(lines[fixture.oldBatch.id]!.remainingDays(nowUtc), 10);
      expect(lines[fixture.newBatch.id]!.isNearExpiryOn(nowUtc), isFalse);

      final progress = detail.progressOn(nowUtc);
      expect(progress.nearExpiryCount, 1);
      expect(progress.expiredCount, 0);
    });
  });

  group('konsistensi batch (G-E2)', () {
    test('barang ber-ED wajib batch', () async {
      final id = await draft();

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<InvalidDistributionBatchFailure>()),
      );
    });

    test('barang tanpa ED tidak boleh punya batch', () async {
      final id = await draft();

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          batchId: fixture.oldBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<InvalidDistributionBatchFailure>()),
      );
    });

    test('batch milik barang lain ditolak', () async {
      final id = await draft();

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.tieItem.id,
          batchId: fixture.oldBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<InvalidDistributionBatchFailure>()),
      );
    });

    test('batch yang tidak ada adalah kegagalan referensi historis', () async {
      final id = await draft();

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: 'tidak-ada',
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<HistoricalDistributionReferenceMissingFailure>()),
      );
    });

    test('batch yang diarsipkan tetap dapat diposting', () async {
      // §32: an archived batch row is history, not absence — the stock it holds is
      // real, and a draft allocated against it must still be postable.
      final id = await draft();
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.archive('item_batches', fixture.oldBatch.id);

      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);
      expect(result.distribution.isPosted, isTrue);

      final detail = await context.distributions.getDetail(id);
      expect(detail!.lines.single.batchIsHistorical, isTrue);
      expect(detail.usesHistoricalMaster, isTrue);
    });

    test('batch yang hilang secara fisik adalah kegagalan eksplisit', () async {
      final id = await draft();
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.corruptByDeleting('item_batches', fixture.oldBatch.id);

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<HistoricalDistributionReferenceMissingFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
      expect(await context.distributionMovementCount(id), 0);
    });

    test('barang non-ED diposting dengan batch null', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      final movements = await context.distributionMovements(id);
      expect(movements.single['batch_id'], isNull);
    });
  });

  group('kebijakan kandidat', () {
    test('usableCandidates membuang kedaluwarsa dan saldo nol', () {
      final candidates = [
        DistributionBatchCandidate(
          batchId: 'expired',
          batchNo: 'X',
          expiryDate: DateOnly.addDays(today, -1),
          availableQty: Quantity.parse('5'),
        ),
        DistributionBatchCandidate(
          batchId: 'empty',
          batchNo: 'Y',
          expiryDate: DateOnly.addDays(today, 30),
          availableQty: Quantity.zero(),
        ),
        DistributionBatchCandidate(
          batchId: 'ok',
          batchNo: 'Z',
          expiryDate: DateOnly.addDays(today, 30),
          availableQty: Quantity.parse('1'),
        ),
      ];

      final usable = DistributionExpiryPolicy.usableCandidates(
        candidates: candidates,
        nowUtc: nowUtc,
      );
      expect(usable.map((candidate) => candidate.batchId), <String>['ok']);
      expect(
        DistributionExpiryPolicy.usableTotal(
          candidates: candidates,
          nowUtc: nowUtc,
        ),
        Quantity.parse('1'),
      );

      final expired = DistributionExpiryPolicy.expiredCandidates(
        candidates: candidates,
        nowUtc: nowUtc,
      );
      expect(expired.map((candidate) => candidate.batchId), <String>[
        'expired',
      ]);
    });

    test('batch yang diarsipkan tetap menjadi kandidat', () {
      // The row is hidden from pickers, not from stock: the balance behind it is real.
      final usable = DistributionExpiryPolicy.usableCandidates(
        candidates: [
          DistributionBatchCandidate(
            batchId: 'archived',
            batchNo: 'A',
            expiryDate: DateOnly.addDays(today, 30),
            availableQty: Quantity.parse('2'),
            isArchived: true,
          ),
        ],
        nowUtc: nowUtc,
      );
      expect(usable, hasLength(1));
      expect(usable.single.isArchived, isTrue);
    });

    test('sortForFefo memakai tiga kunci', () {
      final candidates = [
        DistributionBatchCandidate(
          batchId: 'z',
          batchNo: 'SAME',
          expiryDate: DateOnly.addDays(today, 10),
          availableQty: Quantity.parse('1'),
        ),
        DistributionBatchCandidate(
          batchId: 'a',
          batchNo: 'SAME',
          expiryDate: DateOnly.addDays(today, 10),
          availableQty: Quantity.parse('1'),
        ),
        DistributionBatchCandidate(
          batchId: 'm',
          batchNo: 'EARLIER',
          expiryDate: DateOnly.addDays(today, 5),
          availableQty: Quantity.parse('1'),
        ),
      ];
      DistributionExpiryPolicy.sortForFefo(candidates);

      expect(candidates.map((candidate) => candidate.batchId), <String>[
        'm',
        'a',
        'z',
      ]);
    });
  });

  group('kaitan dengan disposal', () {
    test('pemusnahan tetap jalur terpisah untuk stok kedaluwarsa', () async {
      // Asserted so the boundary is explicit: nothing in this milestone removes expired
      // stock, and the only path that does is `postDisposal` — a different movement
      // type, unreachable from any distribution use case (G-E7).
      final before = await branchStoreBalance(
        context,
        fixture,
        itemId: fixture.batchItem.id,
        batchId: fixture.expiredBatch.id,
      );
      expect(before, Quantity.parse('3'));

      await context.posting.postDisposal(
        locationId: fixture.branchStore.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.expiredBatch.id,
        qty: Quantity.parse('3'),
        actorUserId: fixture.branchHead.id,
        note: 'Pemusnahan stok kedaluwarsa',
      );

      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.batchItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.zero(),
      );
      // And that movement is a disposal, never a distribution.
      final rows = await context.database
          .customSelect(
            "SELECT movement_type FROM stock_movements "
            "WHERE movement_type = 'disposal';",
          )
          .get();
      expect(rows, hasLength(1));
      expect(
        StockMovementType.fromDbValue(
          rows.single.read<String>('movement_type'),
        ),
        StockMovementType.disposal,
      );
    });
  });
}
