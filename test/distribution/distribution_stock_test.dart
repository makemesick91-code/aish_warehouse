import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/distribution/domain/models/distribution_models.dart';
import 'package:aish_warehouse/features/distribution/domain/services/distribution_quantity_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-T2 — *"Total qty per item pada satu distribusi ≤ saldo Gudang Cabang saat
/// posting (stok tidak boleh negatif)"* (§38).
///
/// Two things make this rule non-trivial, and both get their own group below:
///
/// * the total is **aggregated across every room** (G-T3), so two rooms taking `3`
///   each from a balance of `5` must fail even though neither line exceeds it;
/// * the balance that decides it is the one live **at posting**, not the one a form
///   saw. Everything a draft holds is a photograph of a shelf somebody else can also
///   reach.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draft() =>
      createDistributionDraft(context, fixture, nowUtc: nowUtc);

  Future<void> add({
    required String id,
    required String roomId,
    required String itemId,
    required String qty,
  }) => addDistributionItem(
    context,
    fixture,
    distributionId: id,
    roomId: roomId,
    itemId: itemId,
    qty: qty,
    nowUtc: nowUtc,
  );

  Future<void> post(String id) => context
      .postDistribution(clock: () => nowUtc)
      .call(actorUserId: fixture.branchHead.id, distributionId: id);

  group('batas satu baris', () {
    test('qty di bawah saldo diterima', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '4',
      );
      await post(id);

      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('6.5'),
      );
    });

    test('qty sama dengan saldo diterima dan menyisakan nol', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '10.5',
      );
      await post(id);

      // Distributing a store's entire holding is legitimate: `CHECK (qty_on_hand >= 0)`
      // accepts exactly zero.
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('10.5'),
      );
    });

    test('qty melebihi saldo ditolak saat ditambahkan', () async {
      final id = await draft();

      expect(
        () => add(
          id: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '10.501',
        ),
        throwsA(isA<InsufficientBranchStockFailure>()),
      );
      expect(await context.distributionLineCount(id), 0);
    });

    test('desimal dihitung eksak tanpa residu', () async {
      final id = await draft();
      // 10.5 split as 3.5 + 3.5 + 3.5 leaves exactly nothing — the property fixed-point
      // arithmetic buys and binary floating point does not (Q-2).
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '3.5',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '3.5',
      );
      await add(
        id: id,
        roomId: fixture.roomThree.id,
        itemId: fixture.simpleItem.id,
        qty: '3.5',
      );
      await post(id);

      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
      // Read raw as well, so a "close enough" float cannot hide behind a `Quantity`
      // comparison: the stored value is an integer count of milli-units.
      final balances = await context.balancesAt(fixture.branchStore.id);
      expect(balances['${fixture.simpleItem.id}|'], 0);
      final rooms = <int>[
        for (final room in [
          fixture.roomOne,
          fixture.roomTwo,
          fixture.roomThree,
        ])
          (await context.balancesAt(
            fixture.locationForRoom(room.id).id,
          ))['${fixture.simpleItem.id}|']!,
      ];
      expect(rooms, [3500, 3500, 3500]);
    });
  });

  group('agregasi lintas ruangan', () {
    test('total tiga ruangan dijumlahkan terhadap satu saldo', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '4',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '4',
      );

      // 4 + 4 = 8 of 10.5 is fine; a third 4 would be 12 and is not.
      expect(
        () => add(
          id: id,
          roomId: fixture.roomThree.id,
          itemId: fixture.simpleItem.id,
          qty: '4',
        ),
        throwsA(isA<InsufficientBranchStockFailure>()),
      );
      expect(await context.distributionLineCount(id), 2);
    });

    test('total per batch diperiksa terpisah dari total per item', () async {
      final id = await draft();
      // `B-OLD` holds 2 and `A-NEW` holds 4, so the item total is 6 — but a request for
      // 3 from one batch is impossible even though 3 ≤ 6. FEFO splits it across both.
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
      );

      final rows = await context.distributionLineRows(id);
      final byBatch = {
        for (final row in rows.values) row['batch_id']: row['qty'],
      };
      expect(byBatch[fixture.oldBatch.id], 2000);
      expect(byBatch[fixture.newBatch.id], 1000);
    });

    test(
      'ruangan kedua hanya dapat mengambil sisa batch setelah ruangan pertama',
      () async {
        final id = await draft();
        // R1 empties `B-OLD` (2) and takes 1 of `A-NEW`. R2 may then only draw the 3
        // that remain of `A-NEW`; asking for 4 is refused.
        await add(
          id: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          qty: '3',
        );
        await add(
          id: id,
          roomId: fixture.roomTwo.id,
          itemId: fixture.batchItem.id,
          qty: '3',
        );

        expect(
          () => add(
            id: id,
            roomId: fixture.roomThree.id,
            itemId: fixture.batchItem.id,
            qty: '1',
          ),
          throwsA(isA<InsufficientBranchStockFailure>()),
        );

        final rows = await context.distributionLineRows(id);
        final total = rows.values.fold<int>(
          0,
          (sum, row) => sum + (row['qty'] as int),
        );
        // Exactly the 6 usable units, never the 3 expired ones.
        expect(total, 6000);
      },
    );

    test('barang tanpa ED dijumlahkan pada satu posisi non-batch', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '5',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '5',
      );

      expect(
        () => add(
          id: id,
          roomId: fixture.roomThree.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
        ),
        throwsA(isA<InsufficientBranchStockFailure>()),
      );
    });
  });

  group('revalidasi saat posting', () {
    test('saldo yang menyusut setelah draft dibuat menolak posting', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '8',
      );

      // Another document empties most of the store in the meantime — the situation a
      // form's snapshot cannot see.
      final other = await draft();
      await add(
        id: other,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '5',
      );
      await post(other);

      expect(() => post(id), throwsA(isA<InsufficientBranchStockFailure>()));
      expect(await context.distributionStatusOf(id), 'draft');
      expect(await context.distributionMovementCount(id), 0);
      // The document that did commit is untouched by the one that failed.
      expect(await context.distributionStatusOf(other), 'posted');
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('5.5'),
      );
    });

    test(
      'dua distribusi yang bersama-sama melebihi saldo: hanya yang valid commit',
      () async {
        // §18's worked example, scaled up: 6 + 6 against 10.5. Whichever posts first
        // wins; the second is refused with a shortfall it can act on, and the store
        // never goes negative.
        final first = await draft();
        final second = await draft();
        await add(
          id: first,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '6',
        );
        await add(
          id: second,
          roomId: fixture.roomTwo.id,
          itemId: fixture.simpleItem.id,
          qty: '6',
        );

        await post(first);
        expect(
          () => post(second),
          throwsA(isA<InsufficientBranchStockFailure>()),
        );

        expect(await context.distributionStatusOf(first), 'posted');
        expect(await context.distributionStatusOf(second), 'draft');
        final remaining = await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        );
        expect(remaining, Quantity.parse('4.5'));
        expect(remaining.isNegative, isFalse);
      },
    );

    test('dua distribusi yang bersama-sama pas: keduanya commit', () async {
      // The valid half of the same situation (§18): 3 + 2 out of a batch holding 5
      // is fine, and both documents post.
      final first = await draft();
      final second = await draft();
      await add(
        id: first,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '6',
      );
      await add(
        id: second,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '4.5',
      );

      await post(first);
      await post(second);

      expect(await context.distributionStatusOf(first), 'posted');
      expect(await context.distributionStatusOf(second), 'posted');
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
    });

    test('posting bersamaan dari dua sisi aman', () async {
      // Both futures start before either finishes. Drift serialises the transactions,
      // so one commits and the other finds the store short — never both.
      final first = await draft();
      final second = await draft();
      await add(
        id: first,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '6',
      );
      await add(
        id: second,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '6',
      );

      final results = await Future.wait([
        post(first).then((_) => true).catchError((_) => false),
        post(second).then((_) => true).catchError((_) => false),
      ]);

      expect(results.where((ok) => ok), hasLength(1));
      final remaining = await branchStoreBalance(
        context,
        fixture,
        itemId: fixture.simpleItem.id,
      );
      expect(remaining, Quantity.parse('4.5'));
      expect(remaining.isNegative, isFalse);
    });

    test('saldo gudang cabang tidak pernah negatif', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '6',
      );

      // Drain the batches from another document first.
      final other = await draft();
      await add(
        id: other,
        roomId: fixture.roomTwo.id,
        itemId: fixture.batchItem.id,
        qty: '6',
      );
      await post(other);

      expect(() => post(id), throwsA(isA<InsufficientBranchStockFailure>()));

      for (final batch in [fixture.oldBatch, fixture.newBatch]) {
        final balance = await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.batchItem.id,
          batchId: batch.id,
        );
        expect(balance, Quantity.zero());
        expect(balance.isNegative, isFalse);
      }
    });
  });

  group('kebijakan kuantitas', () {
    test('total per posisi sumber menjumlahkan seluruh ruangan', () {
      final lines = [
        DistributionLineReference(
          id: 'l1',
          distributionId: 'd',
          roomId: 'r1',
          itemId: 'i1',
          batchId: 'b1',
          qty: Quantity.parse('3'),
        ),
        DistributionLineReference(
          id: 'l2',
          distributionId: 'd',
          roomId: 'r2',
          itemId: 'i1',
          batchId: 'b1',
          qty: Quantity.parse('2'),
        ),
        DistributionLineReference(
          id: 'l3',
          distributionId: 'd',
          roomId: 'r2',
          itemId: 'i1',
          qty: Quantity.parse('1'),
        ),
      ];

      final bySource = DistributionQuantityPolicy.totalsBySourcePosition(lines);
      expect(bySource['i1|b1'], Quantity.parse('5'));
      // `batch_id IS NULL` is a position of its own, exactly as the partial unique
      // index on `stock_balances` treats it.
      expect(bySource['i1|'], Quantity.parse('1'));

      expect(
        DistributionQuantityPolicy.totalsByItem(lines)['i1'],
        Quantity.parse('6'),
      );
      expect(
        DistributionQuantityPolicy.totalsByRoom(lines)['r2'],
        Quantity.parse('3'),
      );
    });

    test('kesamaan tidak melebihi, kelebihan satu milli-unit melebihi', () {
      final five = Quantity.parse('5');
      expect(
        DistributionQuantityPolicy.exceedsAvailable(
          requested: five,
          available: five,
        ),
        isFalse,
      );
      expect(
        DistributionQuantityPolicy.exceedsAvailable(
          requested: Quantity.fromMilliUnits(5001),
          available: five,
        ),
        isTrue,
      );
    });

    test('qty nol dan negatif bukan qty baris yang sah', () {
      expect(
        DistributionQuantityPolicy.isValidLineQty(Quantity.zero()),
        isFalse,
      );
      expect(
        DistributionQuantityPolicy.isValidLineQty(Quantity.fromMilliUnits(-1)),
        isFalse,
      );
      expect(
        DistributionQuantityPolicy.isValidLineQty(Quantity.fromMilliUnits(1)),
        isTrue,
      );
    });
  });
}
