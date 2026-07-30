import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-T3 — *"Satu dokumen distribusi boleh menyasar beberapa ruangan sekaligus
/// (baris per ruangan-item)"* (§39).
///
/// The grain that makes this work is `(room, item, batch)`: the same item may go to
/// three rooms, the same batch may be split between two, and one item in one room may
/// draw on two batches — but the *same* position twice is refused, because posting it
/// would take double the quantity out of the store while every per-line check still
/// passed. Two partial unique indexes enforce it in SQLite and the guards enforce it in
/// the domain, so a branch head gets a sentence rather than a driver error.
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

  group('jumlah ruangan', () {
    test('satu ruangan valid', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      final detail = await context.distributions.getDetail(id);
      expect(detail!.roomCount, 1);
      expect(detail.roomGroups, hasLength(1));
    });

    test('dua ruangan valid', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      final detail = await context.distributions.getDetail(id);
      expect(detail!.roomCount, 2);
    });

    test('tiga ruangan valid dan diposting bersama', () async {
      final id = await draft();
      for (final room in [
        fixture.roomOne,
        fixture.roomTwo,
        fixture.roomThree,
      ]) {
        await add(
          id: id,
          roomId: room.id,
          itemId: fixture.simpleItem.id,
          qty: '2',
        );
      }

      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(result.roomCount, 3);
      expect(result.lineCount, 3);
      expect(result.movements, hasLength(3));
      for (final room in [
        fixture.roomOne,
        fixture.roomTwo,
        fixture.roomThree,
      ]) {
        expect(
          await roomBalance(
            context,
            fixture,
            roomId: room.id,
            itemId: fixture.simpleItem.id,
          ),
          Quantity.parse('2'),
        );
      }
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('4.5'),
      );
    });
  });

  group('kombinasi barang dan ruangan', () {
    test('barang yang sama ke beberapa ruangan', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
      );

      final detail = await context.distributions.getDetail(id);
      expect(detail!.linesForItem(fixture.simpleItem.id), hasLength(2));
      expect(detail.totalForItem(fixture.simpleItem.id), Quantity.parse('3'));
    });

    test('barang berbeda ke ruangan berbeda', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.batchItem.id,
        qty: '2',
      );

      final detail = await context.distributions.getDetail(id);
      final groups = detail!.roomGroups;
      expect(groups, hasLength(2));
      expect(groups.first.roomCode, 'R1');
      expect(groups.first.lines.single.itemId, fixture.simpleItem.id);
      expect(groups.last.roomCode, 'R2');
      expect(groups.last.lines.single.itemId, fixture.batchItem.id);
    });

    test('batch yang sama ke dua ruangan berbeda valid', () async {
      final id = await draft();
      // `B-OLD` holds 2. One unit to each of two rooms is two *different* positions
      // sharing one source batch — legitimate, and exactly why G-T2 has to aggregate.
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
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.oldBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      await post(id);

      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.batchItem.id,
          batchId: fixture.oldBatch.id,
        ),
        Quantity.zero(),
      );
      for (final room in [fixture.roomOne, fixture.roomTwo]) {
        expect(
          await roomBalance(
            context,
            fixture,
            roomId: room.id,
            itemId: fixture.batchItem.id,
            batchId: fixture.oldBatch.id,
          ),
          Quantity.parse('1'),
        );
      }
    });

    test('satu barang satu ruangan terbagi ke dua batch', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
      );

      final detail = await context.distributions.getDetail(id);
      final position = detail!.linesForPosition(
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
      );
      expect(position, hasLength(2));
      // Ordered nearest expiry first, so the reader sees FEFO's own order.
      expect(position.first.batchId, fixture.oldBatch.id);
      expect(position.last.batchId, fixture.newBatch.id);
      // One room, one item, two lines.
      expect(detail.roomCount, 1);
      expect(detail.lineCount, 2);
    });
  });

  group('posisi ganda ditolak', () {
    test('posisi batch yang sama dua kali ditolak', () async {
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

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.oldBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DuplicateDistributionLineFailure>()),
      );
      expect(await context.distributionLineCount(id), 1);
    });

    test('posisi non-batch yang sama dua kali ditolak', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      expect(
        () => addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DuplicateDistributionLineFailure>()),
      );
      expect(await context.distributionLineCount(id), 1);
    });

    test(
      'batch kedua untuk item yang sama di ruangan yang sama diterima manual',
      () async {
        // A *manual* split is legitimate: two batches of one product for one room are
        // two positions. Only the automatic path refuses a second add, because FEFO
        // already allocated the whole position.
        final id = await draft();
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
        await addManualDistributionAllocation(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.newBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        );

        expect(await context.distributionLineCount(id), 2);
      },
    );

    test('baris yang dihapus membebaskan posisinya kembali', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      final lines = await distributionLineIdsByPosition(context, id);
      await context.removeDistributionLine.call(
        actorUserId: fixture.branchHead.id,
        distributionId: id,
        lineId: lines['${fixture.roomOne.id}|${fixture.simpleItem.id}|']!,
      );

      // The partial `WHERE deleted_at IS NULL` is what makes this possible.
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '3',
      );
      expect(await context.distributionLineCount(id), 1);
      final detail = await context.distributions.getDetail(id);
      expect(detail!.lines.single.qty, Quantity.parse('3'));
    });
  });

  group('pengelompokan per ruangan', () {
    test('detail dikelompokkan per ruangan urut kode', () async {
      final id = await draft();
      // Added out of order on purpose: the grouping sorts, the insertion order does not
      // decide it.
      await add(
        id: id,
        roomId: fixture.roomThree.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '3',
      );

      final detail = await context.distributions.getDetail(id);
      expect(detail!.roomGroups.map((group) => group.roomCode), <String>[
        'R1',
        'R2',
        'R3',
      ]);
      expect(
        detail.roomGroups.map((group) => group.totalsByUnit['box']),
        <Quantity>[
          Quantity.parse('2'),
          Quantity.parse('3'),
          Quantity.parse('1'),
        ],
      );
    });

    test('grup ruangan melaporkan jumlah item dan baris terpisah', () async {
      final id = await draft();
      // One room, one item, two batches: two lines but one item.
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
      );
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      final detail = await context.distributions.getDetail(id);
      final group = detail!.roomGroups.single;
      expect(group.lineCount, 3);
      expect(group.itemCount, 2);
      expect(group.totalsByUnit['ampul'], Quantity.parse('3'));
      expect(group.totalsByUnit['box'], Quantity.parse('1'));
    });

    test('total per unit tidak mencampur satuan', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.batchItem.id,
        qty: '2',
      );

      final detail = await context.distributions.getDetail(id);
      expect(detail!.totalsByUnit, hasLength(2));
      expect(detail.totalsByUnit['box'], Quantity.parse('2'));
      expect(detail.totalsByUnit['ampul'], Quantity.parse('2'));
    });

    test('progress menghitung ruangan, baris dan item', () async {
      final id = await draft();
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
        qty: '2',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      final detail = await context.distributions.getDetail(id);
      final progress = detail!.progressOn(nowUtc);
      expect(progress.roomCount, 2);
      expect(progress.itemCount, 2);
      expect(progress.lineCount, 4);
      expect(progress.label, '2 ruangan · 4 baris');
      // `B-OLD` expires in 10 days against a 30-day threshold, so the lines drawing on
      // it are near expiry — a badge, never a block (G-E6).
      expect(progress.nearExpiryCount, greaterThan(0));
      expect(progress.expiredCount, 0);
    });
  });

  group('posting multi-ruangan', () {
    test('setiap ruangan menerima saldonya masing-masing', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
      );
      await add(
        id: id,
        roomId: fixture.roomThree.id,
        itemId: fixture.simpleItem.id,
        qty: '3',
      );

      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(result.totalQty, Quantity.parse('6'));
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('1'),
      );
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomTwo.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('2'),
      );
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomThree.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('3'),
      );
      // What left the store equals what arrived.
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('4.5'),
      );
    });

    test('ruangan yang tidak disasar tidak berubah', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await post(id);

      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomTwo.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomThree.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
      // And no other branch is touched.
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.otherBranchRoom.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
    });
  });
}
