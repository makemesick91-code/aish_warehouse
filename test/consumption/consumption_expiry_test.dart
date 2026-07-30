import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/consumption/domain/services/consumption_expiry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Batch and expiry rules for a Pemakaian (§39).
///
/// Two rules, and they pull in opposite directions:
///
/// * **Expired is blocked, absolutely.** G-E7 puts expired stock out through a
///   Pemusnahan and nothing else, so consuming it is refused at add, at update and again
///   inside the posting transaction — with no confirmation, no note and no override that
///   passes.
/// * **Near-expiry is a badge, never a block.** G-E6 asks for the *"Segera
///   kedaluwarsa"* warning; a nurse reaching for the batch that expires soonest is doing
///   exactly the right thing, so §17 asks for no FEFO override reason and none is
///   demanded anywhere.
///
/// The boundary between them is the operational day in GMT+8 (T-10), and the two
/// timezone tests below pin it at the two UTC instants either side of a GMT+8 midnight:
/// `15:59Z` is still the old operational day and `16:00Z` is already the new one.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draft({String? actorUserId, String? roomId}) =>
      createConsumptionDraft(
        context,
        fixture,
        roomId: roomId ?? fixture.roomOne.id,
        nowUtc: nowUtc,
        actorUserId: actorUserId,
      );

  group('aturan batch (G-E2)', () {
    test('barang ber-ED wajib memilih batch', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<ConsumptionBatchRequiredFailure>()),
      );
      expect(await context.consumptionLineCount(id), 0);
    });

    test('barang tanpa ED tidak boleh membawa batch', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.plainItem.id,
              batchId: fixture.validBatch.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<ConsumptionBatchNotAllowedFailure>()),
      );
    });

    test('barang tanpa ED tercatat dengan batch null', () async {
      final id = await draft();
      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '2.5',
        nowUtc: nowUtc,
      );

      expect(line.batchId, isNull);
      expect(line.isBatched, isFalse);
      expect(line.positionKey, '${fixture.plainItem.id}|');
    });

    test('batch milik barang lain ditolak', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: fixture.otherItemBatch.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<InvalidConsumptionBatchFailure>()),
      );
    });

    test('batch tidak ada memberi kegagalan historis eksplisit', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: 'tidak-ada',
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<HistoricalConsumptionReferenceMissingFailure>()),
      );
    });
  });

  group('batch kedaluwarsa diblokir (§17/G-E7)', () {
    test('batch valid dapat digunakan', () async {
      final id = await draft();
      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      expect(line.batchId, fixture.validBatch.id);
    });

    test('batch yang kedaluwarsa hari ini masih dapat digunakan (T-10)', () async {
      // A batch is usable for the whole of its expiry day. This is the boundary the
      // Pemusnahan refuses on the same day, and the two must stay complementary.
      final id = await draft();
      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.todayBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      expect(line.batchId, fixture.todayBatch.id);
    });

    test('batch kedaluwarsa H+1 ditolak saat add', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: fixture.expiredBatch.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<ExpiredBatchForConsumptionFailure>()),
      );
      expect(await context.consumptionLineCount(id), 0);
    });

    test('catatan tidak dapat meloloskan batch kedaluwarsa', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: fixture.expiredBatch.id,
              qty: Quantity.parse('1'),
              note: 'sudah dikonfirmasi kepala cabang',
            ),
        throwsA(isA<ExpiredBatchForConsumptionFailure>()),
      );
    });

    test(
      'batch yang kedaluwarsa setelah draft dibuka ditolak saat posting',
      () async {
        // The run that matters. The line was legal when it was added; the operational day
        // rolled over while the draft sat open, and the posting is what notices.
        final id = await draft();
        await addConsumptionPosition(
          context,
          fixture,
          consumptionId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.todayBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        );

        final tomorrow = nowUtc.add(const Duration(days: 1));
        await expectLater(
          context
              .postConsumption(clock: () => tomorrow)
              .call(actorUserId: fixture.nurse.id, consumptionId: id),
          throwsA(isA<ExpiredBatchForConsumptionFailure>()),
        );

        expect(await context.consumptionStatusOf(id), 'draft');
        expect(await context.consumptionMovementCount(id), 0);
        expect(await context.consumptionLineCount(id), 1);
      },
    );

    test('batch kedaluwarsa ditolak saat update baris', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.todayBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId =
          lines['${fixture.expiryItem.id}|${fixture.todayBatch.id}']!;

      final tomorrow = nowUtc.add(const Duration(days: 1));
      await expectLater(
        context
            .updateConsumptionLine(clock: () => tomorrow)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              lineId: lineId,
              qty: Quantity.parse('2'),
            ),
        throwsA(isA<ExpiredBatchForConsumptionFailure>()),
      );
      // The stored quantity is untouched.
      final rows = await context.consumptionLineRows(id);
      expect(rows[lineId]!['qty'], Quantity.parse('1').milliUnits);
    });

    test('batch kedaluwarsa tidak muncul pada daftar kandidat', () async {
      final positions = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );

      final batchIds = positions
          .map((position) => position.batchId)
          .whereType<String>()
          .toSet();
      expect(batchIds, contains(fixture.validBatch.id));
      expect(batchIds, contains(fixture.nearBatch.id));
      expect(batchIds, contains(fixture.todayBatch.id));
      expect(
        batchIds,
        isNot(contains(fixture.expiredBatch.id)),
        reason: 'Batch kedaluwarsa hanya keluar melalui pemusnahan (G-E7).',
      );
    });

    test(
      'pemusnahan tetap satu-satunya jalur untuk batch kedaluwarsa',
      () async {
        // The complement, asserted against the *other* feature: the batch this
        // consumption refuses is exactly the one a Pemusnahan offers.
        final disposable = await context.disposals.expiredPositions(
          sourceLocationId: fixture.locationOne.id,
          nowUtc: nowUtc,
        );
        expect(
          disposable.map((position) => position.batchId),
          contains(fixture.expiredBatch.id),
        );
        // …and the room still physically holds it.
        expect(
          await locationBalance(
            context,
            locationId: fixture.locationOne.id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.expiredBatch.id,
          ),
          Quantity.parse('1.25'),
        );
      },
    );
  });

  group('batas hari operasional GMT+8 (T-10)', () {
    /// A batch expiring on `2026-07-30` in operational time.
    late String boundaryBatchId;

    setUp(() async {
      final batch = await context.master.ensureBatch(
        itemId: fixture.expiryItem.id,
        batchNo: 'G-BOUNDARY',
        expiryDate: DateOnly.of(2026, 7, 30),
      );
      boundaryBatchId = batch.id;

      // Stock it while it is comfortably in date, so the transfer is not refused.
      final early = context.postingWithClock(() => DateTime.utc(2026, 1, 1));
      await early.postInboundWarehouse(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.parse('5'),
        actorUserId: fixture.warehouseUser.id,
      );
      await early.postTransfer(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.locationOne.id,
        qty: Quantity.parse('5'),
        movementType: StockMovementType.distribution,
        actorUserId: fixture.warehouseUser.id,
      );
    });

    test(
      '15:59Z pada 30 Juli masih hari operasional 30 Juli — boleh dipakai',
      () async {
        // `2026-07-30T15:59:59.999999Z` is `2026-07-30 23:59:59 GMT+8`.
        final lastInstant = DateTime.utc(2026, 7, 30, 15, 59, 59, 999, 999);
        final id = await draft();

        final line = await context
            .addConsumptionLine(clock: () => lastInstant)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: boundaryBatchId,
              qty: Quantity.parse('1'),
            );
        expect(line.batchId, boundaryBatchId);
      },
    );

    test(
      '16:00Z pada 30 Juli sudah hari operasional 31 Juli — ditolak',
      () async {
        // `2026-07-30T16:00:00Z` is `2026-07-31 00:00 GMT+8`.
        final firstInstant = DateTime.utc(2026, 7, 30, 16);
        final id = await draft();

        await expectLater(
          context
              .addConsumptionLine(clock: () => firstInstant)
              .call(
                actorUserId: fixture.nurse.id,
                consumptionId: id,
                itemId: fixture.expiryItem.id,
                batchId: boundaryBatchId,
                qty: Quantity.parse('1'),
              ),
          throwsA(isA<ExpiredBatchForConsumptionFailure>()),
        );
      },
    );
  });

  group('near-expiry hanya peringatan (§17/G-E6)', () {
    test('batch near-expiry dapat digunakan tanpa alasan override', () async {
      final id = await draft();

      // No `fefoOverrideReason` parameter exists on this path at all — the call below is
      // the whole API — and the line is stored without one.
      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.nearBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      expect(line.batchId, fixture.nearBatch.id);
      expect(line.note, isNull);
    });

    test('memilih batch bukan-terdekat tidak memerlukan alasan', () async {
      // `validBatch` expires in 200 days and `nearBatch` in 10. A Distribusi would
      // demand a written reason for skipping the nearer one (G-E3); §17 says a
      // consumption does not, because the nurse records what they physically took.
      final id = await draft();
      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      expect(line.batchId, fixture.validBatch.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail!.lines.single.note, isNull);
    });

    test('flag near-expiry tampil pada kandidat', () async {
      final positions = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );

      final near = positions.firstWhere(
        (position) => position.batchId == fixture.nearBatch.id,
      );
      expect(near.isNearExpiryOn(nowUtc), isTrue);
      expect(near.isExpiredOn(nowUtc), isFalse);
      expect(near.remainingDaysOn(nowUtc), 10);

      final valid = positions.firstWhere(
        (position) => position.batchId == fixture.validBatch.id,
      );
      expect(valid.isNearExpiryOn(nowUtc), isFalse);
      expect(valid.remainingDaysOn(nowUtc), 200);
    });

    test(
      'barang tanpa ED tidak pernah near-expiry maupun kedaluwarsa',
      () async {
        final positions = await context.consumptions.roomPositions(
          roomId: fixture.roomOne.id,
          roomLocationId: fixture.locationOne.id,
          nowUtc: nowUtc,
        );
        final plain = positions.firstWhere(
          (position) => position.itemId == fixture.plainItem.id,
        );

        expect(plain.isBatched, isFalse);
        expect(plain.expiryDate, isNull);
        expect(plain.isExpiredOn(nowUtc), isFalse);
        expect(plain.isNearExpiryOn(nowUtc), isFalse);
        expect(plain.remainingDaysOn(nowUtc), isNull);
      },
    );
  });

  group('ConsumptionExpiryPolicy', () {
    test('kanonik: expired = operationalDate > expiryDate', () async {
      final expiry = DateOnly.of(2026, 7, 30);

      // The whole of the expiry day, in operational time.
      expect(
        ConsumptionExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 29, 16),
        ),
        isFalse,
      );
      expect(
        ConsumptionExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 30, 15, 59),
        ),
        isFalse,
      );
      // The first instant of the next operational day.
      expect(
        ConsumptionExpiryPolicy.isExpired(
          expiryDate: expiry,
          nowUtc: DateTime.utc(2026, 7, 30, 16),
        ),
        isTrue,
      );
    });

    test('null expiry tidak pernah kedaluwarsa dan tidak pernah near', () {
      expect(
        ConsumptionExpiryPolicy.isExpired(expiryDate: null, nowUtc: nowUtc),
        isFalse,
      );
      expect(
        ConsumptionExpiryPolicy.isConsumable(expiryDate: null, nowUtc: nowUtc),
        isTrue,
      );
      expect(
        ConsumptionExpiryPolicy.isNearExpiry(
          expiryDate: null,
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        isFalse,
      );
      expect(
        ConsumptionExpiryPolicy.remainingDays(expiryDate: null, nowUtc: nowUtc),
        isNull,
      );
    });

    test('near-expiry memakai <= sesuai kata G-E6', () {
      final today = DateOnly.of(2026, 7, 30);
      final atBoundary = DateOnly.addDays(today, 30);
      final justOutside = DateOnly.addDays(today, 31);
      final reference = DateTime.utc(2026, 7, 30, 8);

      expect(
        ConsumptionExpiryPolicy.isNearExpiry(
          expiryDate: atBoundary,
          expiryAlertDays: 30,
          nowUtc: reference,
        ),
        isTrue,
        reason: 'G-E6: sisa umur ≤ expiry_alert_days.',
      );
      expect(
        ConsumptionExpiryPolicy.isNearExpiry(
          expiryDate: justOutside,
          expiryAlertDays: 30,
          nowUtc: reference,
        ),
        isFalse,
      );
    });

    test('batch kedaluwarsa bukan near-expiry — kasus yang lebih tegas', () {
      final expired = DateOnly.of(2026, 7, 1);
      final reference = DateTime.utc(2026, 7, 30, 8);

      expect(
        ConsumptionExpiryPolicy.isExpired(
          expiryDate: expired,
          nowUtc: reference,
        ),
        isTrue,
      );
      expect(
        ConsumptionExpiryPolicy.isNearExpiry(
          expiryDate: expired,
          expiryAlertDays: 30,
          nowUtc: reference,
        ),
        isFalse,
        reason:
            'Badge harus berkata "Kedaluwarsa", bukan "Segera kedaluwarsa".',
      );
      expect(
        ConsumptionExpiryPolicy.daysExpired(
          expiryDate: expired,
          nowUtc: reference,
        ),
        29,
      );
    });

    test('urutan kandidat deterministik: nama, ED, batch, id', () async {
      final positions = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );

      // Within one item the nearest expiry comes first — operational help, not a FEFO
      // requirement (§17).
      final anaesthetic = positions
          .where((position) => position.itemId == fixture.expiryItem.id)
          .toList(growable: false);
      expect(anaesthetic.length, 3);
      expect(anaesthetic[0].batchId, fixture.todayBatch.id);
      expect(anaesthetic[1].batchId, fixture.nearBatch.id);
      expect(anaesthetic[2].batchId, fixture.validBatch.id);

      // And items are ordered by name across the whole list.
      final names = positions
          .map((position) => position.itemName)
          .toList(growable: false);
      final sorted = [...names]..sort();
      expect(names, sorted);
    });
  });

  group('batch historis', () {
    test('batch yang diarsipkan tetap terbaca pada dokumen posted', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      await context.archive('item_batches', fixture.validBatch.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail, isNotNull);
      expect(detail!.lines.single.batchNo, 'A-VALID');
      expect(detail.lines.single.batchIsHistorical, isTrue);
      expect(detail.usesHistoricalMaster, isTrue);
    });
  });
}
