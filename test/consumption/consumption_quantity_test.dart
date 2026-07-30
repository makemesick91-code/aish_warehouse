import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/consumption/domain/services/consumption_quantity_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Quantity and concurrency rules for a Pemakaian (§40).
///
/// The arithmetic is exact fixed point throughout (Q-2): `2.375` from `5.5` leaves
/// exactly `3.125`, and nothing on this path converts to `double`.
///
/// The concurrency half is the interesting one, and §18 states the rule that makes it
/// tractable: **a draft reserves nothing.** Two drafts may name the same position, and the
/// second to post is refused with a shortfall it can act on. The alternative — reserving
/// stock on a draft — would need something to release it, and nothing in this milestone
/// can: a draft has no expiry, no cancel and an owner who may simply never come back to
/// it.
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

  Future<Quantity> roomBalance({String? batchId, String? itemId}) =>
      locationBalance(
        context,
        locationId: fixture.locationOne.id,
        itemId: itemId ?? fixture.expiryItem.id,
        batchId: batchId,
      );

  group('kuantitas baris', () {
    test('qty nol ditolak', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.plainItem.id,
              qty: Quantity.zero(),
            ),
        throwsA(isA<InvalidConsumptionQuantityFailure>()),
      );
      expect(await context.consumptionLineCount(id), 0);
    });

    test('qty negatif ditolak', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.plainItem.id,
              qty: -Quantity.parse('1'),
            ),
        throwsA(isA<InvalidConsumptionQuantityFailure>()),
      );
    });

    test('qty 0.001 diterima', () async {
      final id = await draft();
      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '0.001',
        nowUtc: nowUtc,
      );
      expect(line.qty, Quantity.parse('0.001'));
      expect(line.qty.milliUnits, 1);
    });

    test('qty tepat sama dengan saldo diterima', () async {
      final id = await draft();
      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        // The room holds exactly 5.5 of this position.
        qty: '5.5',
        nowUtc: nowUtc,
      );
      expect(line.qty, Quantity.parse('5.5'));
    });

    test('qty di bawah saldo diterima dan sisanya eksak', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '2.375',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(
        await roomBalance(batchId: fixture.validBatch.id),
        Quantity.parse('3.125'),
        reason: '5.5 − 2.375 = 3.125, eksak tanpa residu (Q-2).',
      );
    });

    test('qty di atas saldo ditolak', () async {
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: fixture.validBatch.id,
              qty: Quantity.parse('5.501'),
            ),
        throwsA(isA<InsufficientRoomStockFailure>()),
      );
      expect(await context.consumptionLineCount(id), 0);
    });

    test('tiga desimal disimpan eksak sebagai milli-unit', () async {
      final id = await draft();
      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '2.375',
        nowUtc: nowUtc,
      );

      final rows = await context.consumptionLineRows(id);
      expect(rows[line.id]!['qty'], 2375);
    });

    test('posisi tanpa saldo di ruangan ditolak', () async {
      // `emptyBatch` exists, is in date, and no room holds any of it.
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: fixture.emptyBatch.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<ConsumptionItemHasNoStockFailure>()),
      );
    });

    test('saldo diperiksa per batch, bukan per barang', () async {
      // The room holds 5.5 of `validBatch` and 2.375 of `nearBatch`. Asking for 6 of the
      // near batch must fail even though the item's total across batches is 10.875.
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: fixture.nearBatch.id,
              qty: Quantity.parse('6'),
            ),
        throwsA(isA<InsufficientRoomStockFailure>()),
      );
    });

    test('saldo barang tanpa batch dibaca dari baris batch NULL', () async {
      // A distinct balance row from any batch of the same item, and the one that must be
      // read for an item without expiry.
      final id = await draft();

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.plainItem.id,
              qty: Quantity.parse('10.501'),
            ),
        throwsA(isA<InsufficientRoomStockFailure>()),
      );

      final line = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '10.5',
        nowUtc: nowUtc,
      );
      expect(line.qty, Quantity.parse('10.5'));
    });

    test('update baris memvalidasi ulang saldo', () async {
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
      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId =
          lines['${fixture.expiryItem.id}|${fixture.validBatch.id}']!;

      await expectLater(
        context
            .updateConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              lineId: lineId,
              qty: Quantity.parse('99'),
            ),
        throwsA(isA<InsufficientRoomStockFailure>()),
      );

      // And a legal change goes through.
      await context
          .updateConsumptionLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.nurse.id,
            consumptionId: id,
            lineId: lineId,
            qty: Quantity.parse('3.25'),
          );
      final rows = await context.consumptionLineRows(id);
      expect(rows[lineId]!['qty'], Quantity.parse('3.25').milliUnits);
    });

    test('update baris menolak qty nol', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);

      await expectLater(
        context
            .updateConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              lineId: lines['${fixture.plainItem.id}|']!,
              qty: Quantity.zero(),
            ),
        throwsA(isA<InvalidConsumptionQuantityFailure>()),
      );
    });
  });

  group('posisi ganda', () {
    test('batch yang sama dua kali ditolak', () async {
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

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.expiryItem.id,
              batchId: fixture.validBatch.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<DuplicateConsumptionLineFailure>()),
      );
      expect(await context.consumptionLineCount(id), 1);
    });

    test('barang tanpa batch dua kali ditolak', () async {
      // The `unbatched` partial index's job: SQLite treats every NULL as distinct, so one
      // index over `(…, batch_id)` would let this through.
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.plainItem.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<DuplicateConsumptionLineFailure>()),
      );
      expect(await context.consumptionLineCount(id), 1);
    });

    test('dua batch berbeda dari satu barang diterima', () async {
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
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.nearBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      expect(await context.consumptionLineCount(id), 2);
    });

    test('baris yang dihapus membebaskan posisi', () async {
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
      final lines = await consumptionLineIdsByPosition(context, id);
      await context.removeConsumptionLine.call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
        lineId: lines['${fixture.expiryItem.id}|${fixture.validBatch.id}']!,
      );
      expect(await context.consumptionLineCount(id), 0);

      // The same position may be added back — the partial indexes are qualified
      // `WHERE deleted_at IS NULL` (G-A5).
      final again = await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      expect(again.qty, Quantity.parse('2'));
      expect(await context.consumptionLineCount(id), 1);
    });

    test('posisi yang sama pada dua dokumen berbeda diterima', () async {
      // The unique indexes are per document, not per position. Two nurses' documents —
      // and two of one nurse's — may name the same batch; §18 says whichever posts first
      // wins.
      final first = await draft();
      final second = await draft();

      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: first,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '3',
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: second,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '3',
        nowUtc: nowUtc,
      );

      expect(await context.consumptionLineCount(first), 1);
      expect(await context.consumptionLineCount(second), 1);
    });
  });

  group('draft tidak mereservasi stok (§18)', () {
    test('menambah baris tidak mengubah saldo', () async {
      final before = await roomBalance(batchId: fixture.validBatch.id);
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '3',
        nowUtc: nowUtc,
      );

      expect(await roomBalance(batchId: fixture.validBatch.id), before);
      expect(await context.consumptionMovementCount(id), 0);
    });

    test(
      'dua draft dapat melebihi saldo bersama; yang pertama post menang',
      () async {
        // The canonical §18 example, with the fixture's own numbers: the room holds `5.5`,
        // and two drafts each ask for `3`.
        final first = await draft();
        final second = await draft();
        for (final id in [first, second]) {
          await addConsumptionPosition(
            context,
            fixture,
            consumptionId: id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.validBatch.id,
            qty: '3',
            nowUtc: nowUtc,
          );
        }

        // The first posts against a balance of 5.5 and leaves 2.5.
        await context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: first,
        );
        expect(
          await roomBalance(batchId: fixture.validBatch.id),
          Quantity.parse('2.5'),
        );

        // The second re-reads the balance inside its transaction and is refused.
        await expectLater(
          context.postConsumption().call(
            actorUserId: fixture.nurse.id,
            consumptionId: second,
          ),
          throwsA(isA<InsufficientRoomStockFailure>()),
        );

        // And it left nothing behind: no movement, no status change, no balance change.
        expect(await context.consumptionStatusOf(second), 'draft');
        expect(await context.consumptionColumn(second, 'posted_at'), isNull);
        expect(await context.consumptionColumn(second, 'posted_by'), isNull);
        expect(await context.consumptionMovementCount(second), 0);
        expect(await context.consumptionLineCount(second), 1);
        expect(
          await roomBalance(batchId: fixture.validBatch.id),
          Quantity.parse('2.5'),
        );
      },
    );

    test(
      'dua perawat berbeda: yang kedua ditolak, saldo tidak negatif',
      () async {
        final mine = await draft();
        final theirs = await draft(actorUserId: fixture.otherNurse.id);
        await addConsumptionPosition(
          context,
          fixture,
          consumptionId: mine,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
          qty: '5.5',
          nowUtc: nowUtc,
        );
        await addConsumptionPosition(
          context,
          fixture,
          consumptionId: theirs,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
          qty: '5.5',
          nowUtc: nowUtc,
          actorUserId: fixture.otherNurse.id,
        );

        await context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: mine,
        );
        expect(
          await roomBalance(batchId: fixture.validBatch.id),
          Quantity.zero(),
        );

        await expectLater(
          context.postConsumption().call(
            actorUserId: fixture.otherNurse.id,
            consumptionId: theirs,
          ),
          throwsA(isA<InsufficientRoomStockFailure>()),
        );
        final after = await roomBalance(batchId: fixture.validBatch.id);
        expect(after, Quantity.zero());
        expect(after.isNegative, isFalse);
      },
    );

    test('posting dua kali dokumen yang sama ditolak tanpa duplikat', () async {
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
      expect(await context.consumptionMovementCount(id), 1);

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionAlreadyPostedFailure>()),
      );
      expect(
        await context.consumptionMovementCount(id),
        1,
        reason: 'Posting kedua tidak boleh menambah movement.',
      );
      expect(
        await roomBalance(batchId: fixture.validBatch.id),
        Quantity.parse('4.5'),
      );
    });
  });

  group('agregasi per posisi', () {
    test('total per posisi dijumlahkan sebelum dibandingkan', () async {
      // The partial indexes already stop one document holding a position twice, but the
      // aggregation is what makes the check correct on a document two devices assembled.
      // Constructed here through the *plan builder*, which is the layer the posting
      // trusts.
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final lines = await context.consumptions.lineReferences(id);
      final totals = ConsumptionQuantityPolicy.totalsBySourcePosition(lines);
      expect(totals.length, 2);
      expect(
        totals['${fixture.expiryItem.id}|${fixture.validBatch.id}'],
        Quantity.parse('2'),
      );
      expect(totals['${fixture.plainItem.id}|'], Quantity.parse('1'));
    });

    test('ConsumptionQuantityPolicy: kunci posisi konsisten', () {
      expect(ConsumptionQuantityPolicy.sourceKey('i1', 'b1'), 'i1|b1');
      expect(
        ConsumptionQuantityPolicy.sourceKey('i1', null),
        'i1|',
        reason: 'Segmen batch kosong, bukan "null", agar cocok stock_balances.',
      );
    });

    test('ConsumptionQuantityPolicy: kesetaraan lolos, kelebihan ditolak', () {
      final five = Quantity.parse('5');
      expect(
        ConsumptionQuantityPolicy.exceedsAvailable(
          requested: five,
          available: five,
        ),
        isFalse,
      );
      expect(
        ConsumptionQuantityPolicy.exceedsAvailable(
          requested: Quantity.parse('5.001'),
          available: five,
        ),
        isTrue,
      );
      // `Quantity.parse` refuses a negative literal, so the expected shortfall is built
      // by negating a positive one — which is also how the production code arrives at it.
      expect(
        ConsumptionQuantityPolicy.shortfall(
          requested: Quantity.parse('7'),
          available: five,
        ),
        -Quantity.parse('2'),
      );
      expect(
        ConsumptionQuantityPolicy.isPartial(
          requested: Quantity.parse('2'),
          available: five,
        ),
        isTrue,
      );
      expect(
        ConsumptionQuantityPolicy.isPartial(requested: five, available: five),
        isFalse,
      );
    });

    test('dua posisi berbeda dari satu barang berkurang terpisah', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1.5',
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.nearBatch.id,
        qty: '0.375',
        nowUtc: nowUtc,
      );

      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(
        await roomBalance(batchId: fixture.validBatch.id),
        Quantity.parse('4'),
      );
      expect(
        await roomBalance(batchId: fixture.nearBatch.id),
        Quantity.parse('2'),
      );
    });
  });
}
