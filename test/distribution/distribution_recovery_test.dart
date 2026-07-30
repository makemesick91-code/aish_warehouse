import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Historical recovery for Distribusi (§32).
///
/// Two rules that look similar and are opposites:
///
/// * a **posted** document must stay readable however much master data is tidied away
///   afterwards. It is a record of stock that already moved, and hiding it would make the
///   ledger unexplainable. Deactivated and archived rows are labelled, never dropped.
/// * a **draft** must not post into a destination that is no longer operational. A room
///   that was switched off is not a place goods can go, and the branch head's way out is
///   to remove the line — not to have the system substitute a room for them.
///
/// And underneath both: a reference that is *physically gone* is always an explicit
/// failure. Nothing is guessed, substituted or invented to paper over it.
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

  Future<String> posted() async {
    final id = await draft();
    await add(
      id: id,
      roomId: fixture.roomOne.id,
      itemId: fixture.batchItem.id,
      qty: '2',
    );
    await add(
      id: id,
      roomId: fixture.roomTwo.id,
      itemId: fixture.simpleItem.id,
      qty: '1',
    );
    await context
        .postDistribution(clock: () => nowUtc)
        .call(actorUserId: fixture.branchHead.id, distributionId: id);
    return id;
  }

  group('dokumen posted tetap terbaca', () {
    test('cabang yang dinonaktifkan tidak menyembunyikan dokumen', () async {
      final id = await posted();
      await context.deactivate('branches', fixture.branch.id);

      final detail = await context.distributions.getForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      expect(detail, isNotNull);
      expect(detail!.summary.branchIsHistorical, isTrue);
      expect(detail.usesHistoricalMaster, isTrue);
      // The list keeps it too — an inner join filtering `is_active` would have dropped it.
      final rows = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows.map((summary) => summary.id), contains(id));
    });

    test('ruangan yang dinonaktifkan tetap tampil dengan badge', () async {
      final id = await posted();
      await context.deactivate('rooms', fixture.roomOne.id);

      final detail = await context.distributions.getForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      // Both rooms still there: two groups, not one.
      expect(detail!.roomGroups, hasLength(2));
      final group = detail.roomGroups.firstWhere(
        (group) => group.roomId == fixture.roomOne.id,
      );
      expect(group.roomIsHistorical, isTrue);
      expect(group.lines, isNotEmpty);
    });

    test('ruangan yang diarsipkan tetap tampil', () async {
      final id = await posted();
      await context.archive('rooms', fixture.roomTwo.id);

      final detail = await context.distributions.getForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      expect(detail!.roomGroups, hasLength(2));
      expect(
        detail.lines.any(
          (line) => line.roomId == fixture.roomTwo.id && line.roomIsHistorical,
        ),
        isTrue,
      );
    });

    test('barang yang dinonaktifkan tetap tampil dengan badge', () async {
      final id = await posted();
      await context.deactivate('items', fixture.simpleItem.id);

      final detail = await context.distributions.getForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      final line = detail!.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );
      expect(line.itemIsHistorical, isTrue);
      expect(line.itemName, 'Masker Bedah');
      expect(line.qty, Quantity.parse('1'));
    });

    test('batch yang diarsipkan tetap tampil dengan ED-nya', () async {
      final id = await posted();
      await context.archive('item_batches', fixture.oldBatch.id);

      final detail = await context.distributions.getForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      final line = detail!.lines.firstWhere(
        (line) => line.batchId == fixture.oldBatch.id,
      );
      expect(line.batchIsHistorical, isTrue);
      expect(line.batchNo, 'B-OLD');
      expect(line.expiryDate, isNotNull);
    });

    test('petugas yang dinonaktifkan tetap tercatat', () async {
      final id = await posted();
      await context.deactivate('users', fixture.branchHead.id);

      final detail = await context.distributions.getForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      expect(detail!.summary.distributedByIsHistorical, isTrue);
      expect(detail.summary.distributedByName, 'Kepala Cabang Uji');
    });

    test('kategori yang diarsipkan tidak menyembunyikan baris', () async {
      final id = await posted();
      await context.archive('item_categories', fixture.category.id);

      final detail = await context.distributions.getForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      // The detail query joins items, not categories, so a tidied category cannot make a
      // line disappear — asserted rather than assumed, because adding a category join
      // "for the label" is exactly how that regression would arrive.
      expect(detail!.lines, hasLength(2));
    });

    test('seluruh master historis sekaligus tetap terbaca', () async {
      final id = await posted();
      await context.deactivate('branches', fixture.branch.id);
      await context.deactivate('rooms', fixture.roomOne.id);
      await context.deactivate('rooms', fixture.roomTwo.id);
      await context.deactivate('items', fixture.simpleItem.id);
      await context.deactivate('items', fixture.batchItem.id);
      await context.deactivate('users', fixture.branchHead.id);
      await context.archive('item_batches', fixture.oldBatch.id);

      final detail = await context.distributions.getForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      expect(detail, isNotNull);
      expect(detail!.lines, hasLength(2));
      expect(detail.usesHistoricalMaster, isTrue);
      // And the ledger it explains is still there.
      expect(await context.distributionMovementCount(id), 2);
    });
  });

  group('draft tidak boleh memaksa masuk ruangan nonaktif', () {
    test('ruangan nonaktif memblokir posting', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await context.deactivate('rooms', fixture.roomOne.id);

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionRoomInactiveFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
      expect(await context.distributionMovementCount(id), 0);
    });

    test(
      'draft dengan ruangan nonaktif tetap dapat dibaca dan diperbaiki',
      () async {
        final id = await draft();
        await add(
          id: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
        );
        await context.deactivate('rooms', fixture.roomOne.id);

        // Readable: the branch head has to be able to see what is blocking them.
        final detail = await context.distributions.getForBranch(
          distributionId: id,
          branchId: fixture.branch.id,
        );
        expect(detail!.lines, hasLength(1));
        expect(detail.lines.single.roomIsHistorical, isTrue);

        // And removable — which is the way out. Removal deliberately does not re-verify the
        // room, or the document would be trapped with no exit.
        final lines = await distributionLineIdsByPosition(context, id);
        await context.removeDistributionLine.call(
          actorUserId: fixture.branchHead.id,
          distributionId: id,
          lineId: lines.values.single,
        );
        expect(await context.distributionLineCount(id), 0);
      },
    );

    test('lokasi ruangan yang diarsipkan memblokir posting', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await context.archive('stock_locations', fixture.locationOne.id);

      // An out-of-service location is not a place stock may be credited, and there is no
      // historical fallback on this path — unlike a Good Receipt, a distribution is new
      // work.
      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionRoomLocationNotFoundFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
    });

    test('gudang cabang yang diarsipkan memblokir posting', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await context.archive('stock_locations', fixture.branchStore.id);

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionBranchStoreNotFoundFailure>()),
      );
      expect(await context.distributionMovementCount(id), 0);
    });

    test(
      'barang yang dinonaktifkan setelah ditambahkan tetap dapat diposting',
      () async {
        // Unlike a room, a withdrawn *item* is still physically on the shelf: the goods
        // exist and the distribution can complete. What a deactivated item may not do is
        // appear on a new line.
        final id = await draft();
        await add(
          id: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
        );
        await context.deactivate('items', fixture.simpleItem.id);

        final result = await context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id);
        expect(result.distribution.isPosted, isTrue);

        // But a new line naming it is refused.
        final second = await draft();
        expect(
          () => add(
            id: second,
            roomId: fixture.roomTwo.id,
            itemId: fixture.simpleItem.id,
            qty: '1',
          ),
          throwsA(isA<InactiveEntityFailure>()),
        );
      },
    );

    test('qty baris barang nonaktif masih dapat dikoreksi', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '4',
      );
      await context.deactivate('items', fixture.simpleItem.id);

      final lines = await distributionLineIdsByPosition(context, id);
      await context
          .updateDistributionLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            distributionId: id,
            lineId: lines.values.single,
            qty: Quantity.parse('1'),
          );

      final rows = await context.distributionLineRows(id);
      expect(rows.values.single['qty'], 1000);
    });
  });

  group('referensi yang benar-benar hilang', () {
    test(
      'ruangan yang hilang secara fisik adalah kegagalan eksplisit',
      () async {
        final id = await draft();
        await add(
          id: id,
          roomId: fixture.roomThree.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
        );
        await context.corruptByDeleting('rooms', fixture.roomThree.id);

        expect(
          () => context
              .postDistribution(clock: () => nowUtc)
              .call(actorUserId: fixture.branchHead.id, distributionId: id),
          throwsA(
            anyOf(
              isA<HistoricalDistributionReferenceMissingFailure>(),
              isA<DistributionLineIntegrityFailure>(),
              isA<EntityNotFoundFailure>(),
            ),
          ),
        );
        expect(await context.distributionStatusOf(id), 'draft');
        expect(await context.distributionMovementCount(id), 0);
      },
    );

    test(
      'barang yang hilang secara fisik adalah kegagalan eksplisit',
      () async {
        final id = await draft();
        await add(
          id: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
        );
        await context.corruptByDeleting('items', fixture.simpleItem.id);

        expect(
          () => context
              .postDistribution(clock: () => nowUtc)
              .call(actorUserId: fixture.branchHead.id, distributionId: id),
          throwsA(
            anyOf(
              isA<HistoricalDistributionReferenceMissingFailure>(),
              isA<DistributionLineIntegrityFailure>(),
            ),
          ),
        );
        expect(await context.distributionMovementCount(id), 0);
      },
    );

    test('batch yang hilang secara fisik adalah kegagalan eksplisit', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '2',
      );
      await context.corruptByDeleting('item_batches', fixture.oldBatch.id);

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(
          anyOf(
            isA<HistoricalDistributionReferenceMissingFailure>(),
            isA<DistributionLineIntegrityFailure>(),
          ),
        ),
      );
      expect(await context.distributionMovementCount(id), 0);
    });

    test('dokumen tidak pernah menyusut melalui inner join', () async {
      // The failure mode this whole family of checks exists for: a joined read that
      // silently returns one fewer line, and a posting that moves less stock than the
      // document says while every per-line check still passes (§22).
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
        qty: '1',
      );
      expect(await context.distributionLineCount(id), 2);

      await context.corruptByDeleting('items', fixture.batchItem.id);

      // The plain select still sees two lines; the joined read sees one. The mismatch is
      // reported rather than posted.
      expect(await context.distributions.lineIds(id), hasLength(2));
      final detail = await context.distributions.getDetail(id);
      expect(detail!.lines, hasLength(1));

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionLineIntegrityFailure>()),
      );
      expect(await context.distributionMovementCount(id), 0);
    });

    test('kegagalan integritas menyebut baris yang hilang', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      final lines = await distributionLineIdsByPosition(context, id);
      final lineId = lines.values.single;
      await context.corruptByDeleting('items', fixture.simpleItem.id);

      await expectLater(
        context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(
          isA<DistributionLineIntegrityFailure>().having(
            (failure) => failure.missingLineIds,
            'missingLineIds',
            contains(lineId),
          ),
        ),
      );
    });

    test('tidak ada substitusi ruangan atau batch', () async {
      // Named as its own test because it is the one thing a "helpful" recovery path would
      // do: pick another room, or another batch, and post anyway. Nothing here does.
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '2',
      );
      await context.deactivate('rooms', fixture.roomOne.id);

      await expectLater(
        context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionRoomInactiveFailure>()),
      );

      // The line still names exactly what it named, and nothing moved anywhere.
      final rows = await context.distributionLineRows(id);
      expect(rows.values.single['room_id'], fixture.roomOne.id);
      expect(rows.values.single['batch_id'], fixture.oldBatch.id);
      for (final room in [fixture.roomTwo, fixture.roomThree]) {
        expect(
          await roomBalance(
            context,
            fixture,
            roomId: room.id,
            itemId: fixture.batchItem.id,
            batchId: fixture.oldBatch.id,
          ),
          Quantity.zero(),
        );
      }
    });
  });
}
