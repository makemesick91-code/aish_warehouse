import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/disposal/domain/services/disposal_quantity_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// How much may be destroyed, and what happens when two documents want the same
/// batch (§41).
///
/// Every number here is exact fixed-point integer arithmetic on milli-units (Q-2).
/// `5.5 − 2.375` is exactly `3.125`, and a test that passed with `double` arithmetic
/// would be testing the wrong thing — which is why the quantities in this fixture
/// have three decimal places rather than being whole.
///
/// The concurrency half is the interesting one. A draft **does not reserve stock**:
/// two documents may both name the same expired batch, both look fine on screen, and
/// the transaction that commits first wins. What the second must not do is commit a
/// negative balance, write half its movements, or leave the document in a state
/// nobody can recover from.
void main() {
  final nowUtc = DateTime.utc(2026, 7, 30, 4);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> warehouseDraft() => createDisposalDraft(
    context,
    fixture,
    sourceLocationId: fixture.warehouse.id,
    nowUtc: nowUtc,
    reason: 'Kedaluwarsa',
  );

  Future<void> addExpired(String disposalId, String qty, {String? batchId}) =>
      addDisposalPosition(
        context,
        fixture,
        disposalId: disposalId,
        itemId: fixture.expiryItem.id,
        batchId: batchId ?? fixture.expiredBatch.id,
        qty: qty,
        nowUtc: nowUtc,
      );

  Future<Quantity> warehouseBalance({String? batchId}) => locationBalance(
    context,
    locationId: fixture.warehouse.id,
    itemId: fixture.expiryItem.id,
    batchId: batchId ?? fixture.expiredBatch.id,
  );

  group('validasi jumlah', () {
    test('jumlah nol ditolak', () async {
      final id = await warehouseDraft();
      await expectLater(
        addExpired(id, '0'),
        throwsA(isA<InvalidDisposalQuantityFailure>()),
      );
    });

    test('jumlah negatif ditolak sebelum mencapai domain', () {
      // `Quantity.parse` refuses it outright, which is the earliest possible refusal
      // and the reason no negative ever reaches a use case.
      expect(
        () => Quantity.parse('-1'),
        throwsA(isA<QuantityFormatException>()),
      );
    });

    test('jumlah 0.001 diterima', () async {
      final id = await warehouseDraft();
      await addExpired(id, '0.001');
      final lines = await context.disposalLineRows(id);
      expect(lines.values.single['qty'], 1);
    });

    test('jumlah sama dengan saldo diterima', () async {
      // Destroying the whole of an expired batch is the ordinary case, not the edge
      // one: it leaves a balance of exactly zero, which `CHECK (qty_on_hand >= 0)`
      // accepts.
      final id = await warehouseDraft();
      await addExpired(id, '5.5');
      final lines = await context.disposalLineRows(id);
      expect(lines.values.single['qty'], Quantity.parse('5.5').milliUnits);
    });

    test('jumlah di bawah saldo diterima', () async {
      final id = await warehouseDraft();
      await addExpired(id, '2.375');
      expect(
        (await context.disposalLineRows(id)).values.single['qty'],
        Quantity.parse('2.375').milliUnits,
      );
    });

    test('jumlah di atas saldo ditolak', () async {
      final id = await warehouseDraft();
      await expectLater(
        addExpired(id, '5.501'),
        throwsA(isA<InsufficientDisposalStockFailure>()),
      );
      expect(await context.disposalLineCount(id), 0);
    });

    test('empat desimal ditolak oleh parser', () {
      expect(
        () => Quantity.parse('1.2345'),
        throwsA(isA<QuantityFormatException>()),
      );
    });
  });

  group('aritmetika fixed-point', () {
    test('pemusnahan sebagian menyisakan sisa yang eksak', () async {
      final id = await warehouseDraft();
      await addExpired(id, '2.375');
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      // 5.5 − 2.375 = 3.125, with no residue. A `double` would produce
      // 3.1249999999999996.
      expect(await warehouseBalance(), Quantity.parse('3.125'));
    });

    test('dua pemusnahan berurutan menjumlah kembali dengan tepat', () async {
      for (final qty in const ['1.125', '0.875']) {
        final id = await warehouseDraft();
        await addExpired(id, qty);
        await context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id);
      }
      expect(await warehouseBalance(), Quantity.parse('3.5'));
    });

    test('agregasi posisi memakai kunci item|batch', () {
      expect(
        DisposalQuantityPolicy.sourceKey('item-1', 'batch-1'),
        'item-1|batch-1',
      );
      expect(
        DisposalQuantityPolicy.exceedsAvailable(
          requested: Quantity.parse('5.5'),
          available: Quantity.parse('5.5'),
        ),
        isFalse,
        reason: 'Kesetaraan lolos: memusnahkan seluruh batch itu sah.',
      );
      expect(
        DisposalQuantityPolicy.exceedsAvailable(
          requested: Quantity.parse('5.501'),
          available: Quantity.parse('5.5'),
        ),
        isTrue,
      );
      expect(
        DisposalQuantityPolicy.isPartial(
          requested: Quantity.parse('2'),
          available: Quantity.parse('5.5'),
        ),
        isTrue,
      );
      expect(
        DisposalQuantityPolicy.isPartial(
          requested: Quantity.parse('5.5'),
          available: Quantity.parse('5.5'),
        ),
        isFalse,
      );
    });
  });

  group('posisi pada satu dokumen', () {
    test('dua batch berbeda dari barang yang sama valid', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      await addExpired(id, '0.25', batchId: fixture.staleBatch.id);

      expect(await context.disposalLineCount(id), 2);
    });

    test('posisi item+batch ganda ditolak', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');

      await expectLater(
        addExpired(id, '1'),
        throwsA(isA<DuplicateDisposalLineFailure>()),
      );
      expect(await context.disposalLineCount(id), 1);
    });

    test('baris yang dihapus lunak membebaskan posisinya', () async {
      // The partial unique index is qualified `WHERE deleted_at IS NULL`, which is
      // what makes remove-then-add the supported way to change a position.
      final id = await warehouseDraft();
      await addExpired(id, '1');
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await context.removeDisposalLine.call(
        actorUserId: fixture.warehouseUser.id,
        disposalId: id,
        lineId: lineId,
      );
      expect(await context.disposalLineCount(id), 0);

      await addExpired(id, '2');
      expect(await context.disposalLineCount(id), 1);
    });

    test('mengubah baris memperbarui jumlah dan catatan', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await context
          .updateDisposalLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            disposalId: id,
            lineId: lineId,
            qty: Quantity.parse('2.5'),
            note: 'Kemasan bocor',
          );

      final row = (await context.disposalLineRows(id))[lineId]!;
      expect(row['qty'], Quantity.parse('2.5').milliUnits);
      expect(row['note'], 'Kemasan bocor');
    });

    test('mengubah baris melebihi saldo ditolak', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await expectLater(
        context
            .updateDisposalLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              disposalId: id,
              lineId: lineId,
              qty: Quantity.parse('99'),
            ),
        throwsA(isA<InsufficientDisposalStockFailure>()),
      );
      expect(
        (await context.disposalLineRows(id))[lineId]!['qty'],
        Quantity.parse('1').milliUnits,
      );
    });
  });

  group('draft tidak mereservasi stok', () {
    test('dua draft boleh melebihi saldo bersama-sama', () async {
      // Both look fine while they are drafts. Nothing has moved, so nothing is
      // reserved — §18 states this directly.
      final first = await warehouseDraft();
      final second = await warehouseDraft();
      await addExpired(first, '3');
      await addExpired(second, '3');

      expect(await context.disposalLineCount(first), 1);
      expect(await context.disposalLineCount(second), 1);
      expect(await warehouseBalance(), Quantity.parse('5.5'));
    });

    test('yang pertama diposting menang, yang kedua ditolak', () async {
      final first = await warehouseDraft();
      final second = await warehouseDraft();
      await addExpired(first, '3');
      await addExpired(second, '3');

      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: first);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: second),
        throwsA(isA<InsufficientDisposalStockFailure>()),
      );

      // The winner committed in full; the loser left nothing behind.
      expect(await context.disposalStatusOf(first), 'posted');
      expect(await context.disposalStatusOf(second), 'draft');
      expect(await context.disposalMovementCount(first), 1);
      expect(await context.disposalMovementCount(second), 0);
      // 5.5 − 3, and never negative.
      expect(await warehouseBalance(), Quantity.parse('2.5'));
    });

    test('yang gagal tetap dapat diperbaiki dan diposting', () async {
      // The loser is refused, not broken: its lines survive, so the user reduces the
      // quantity and posts what is actually there.
      final first = await warehouseDraft();
      final second = await warehouseDraft();
      await addExpired(first, '3');
      await addExpired(second, '3');

      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: first);
      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: second),
        throwsA(isA<InsufficientDisposalStockFailure>()),
      );

      final lineId = (await disposalLineIdsByPosition(
        context,
        second,
      )).values.single;
      await context
          .updateDisposalLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            disposalId: second,
            lineId: lineId,
            qty: Quantity.parse('2.5'),
          );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: second);

      expect(await context.disposalStatusOf(second), 'posted');
      expect(await warehouseBalance(), Quantity.zero());
    });

    test('posting ganda pada dokumen yang sama ditolak', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<DisposalAlreadyPostedFailure>()),
      );
      // And no second set of movements.
      expect(await context.disposalMovementCount(id), 1);
      expect(await warehouseBalance(), Quantity.parse('4.5'));
    });

    test('posting bersamaan hanya menghasilkan satu pemenang', () async {
      // Both futures start before either commits. Whichever the scheduler runs first
      // takes the guarded UPDATE; the other finds `status <> 'draft'` and rolls its
      // movements back.
      final id = await warehouseDraft();
      await addExpired(id, '2');

      final post = context.postDisposal(clock: () => nowUtc);
      final results = await Future.wait<Object?>([
        post
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
        post
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
      ]);

      final failures = results.whereType<AppFailure>();
      expect(failures, hasLength(1));
      expect(await context.disposalStatusOf(id), 'posted');
      expect(await context.disposalMovementCount(id), 1);
      expect(await warehouseBalance(), Quantity.parse('3.5'));
    });
  });

  group('saldo tidak pernah negatif', () {
    test('memusnahkan seluruh saldo meninggalkan nol, bukan negatif', () async {
      final id = await warehouseDraft();
      await addExpired(id, '5.5');
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      expect(await warehouseBalance(), Quantity.zero());
      final negatives = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM stock_balances WHERE qty_on_hand < 0;',
          )
          .getSingle();
      expect(negatives.read<int>('c'), 0);
    });

    test('saldo yang habis di antara add dan post membatalkan posting', () async {
      final id = await warehouseDraft();
      await addExpired(id, '2');

      // Something else drains the shelf in the meantime — an opname adjustment, say.
      await context.posting.postOpnameAdjustment(
        locationId: fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        countedQty: Quantity.parse('1'),
        actorUserId: fixture.warehouseUser.id,
        note: 'Koreksi hitung fisik',
      );

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<InsufficientDisposalStockFailure>()),
      );
      expect(await context.disposalStatusOf(id), 'draft');
      expect(await context.disposalMovementCount(id), 0);
      expect(await warehouseBalance(), Quantity.parse('1'));
    });
  });
}
