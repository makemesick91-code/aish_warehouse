import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/distribution/domain/services/distribution_room_policy.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-T1 — *"Distribusi hanya dari Gudang Cabang ke ruangan dalam cabang yang
/// sama"* (§37).
///
/// The rule SQLite cannot enforce. `rooms.branch_id = distributions.branch_id` is a
/// cross-table equality, and a foreign key ties a column to a row rather than two rows
/// to each other — the schema test asserts that a hand-written INSERT gets away with
/// it, precisely so nobody mistakes the gap for coverage. So the rule lives in four
/// places, and this file exercises all of them: the add path, the read predicates, the
/// posting revalidation, and the policy they all share.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draftWithOneLine({String? roomId}) async {
    final id = await createDistributionDraft(context, fixture, nowUtc: nowUtc);
    await addDistributionItem(
      context,
      fixture,
      distributionId: id,
      roomId: roomId ?? fixture.roomOne.id,
      itemId: fixture.simpleItem.id,
      qty: '2',
      nowUtc: nowUtc,
    );
    return id;
  }

  group('ruangan tujuan', () {
    test('ruangan cabang sendiri diterima', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      for (final room in [
        fixture.roomOne,
        fixture.roomTwo,
        fixture.roomThree,
      ]) {
        await addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: room.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        );
      }

      final detail = await context.distributions.getDetail(id);
      expect(detail!.roomCount, 3);
    });

    test('ruangan cabang lain ditolak', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.otherBranchRoom.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionRoomBranchMismatchFailure>()),
      );
      expect(await context.distributionLineCount(id), 0);
    });

    test('ruangan yang tidak ada ditolak', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: 'tidak-ada',
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });

    test('ruangan nonaktif ditolak untuk baris baru', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      await context.deactivate('rooms', fixture.roomTwo.id);

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomTwo.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionRoomInactiveFailure>()),
      );
    });

    test('ruangan yang dinonaktifkan sebelum posting memblokir posting', () async {
      // §32: a draft line pointing at a deactivated room may not post — the physical
      // destination is not operational, and recording an arrival nobody can act on
      // would be worse than refusing. The way out is to remove the line.
      final id = await draftWithOneLine(roomId: fixture.roomTwo.id);
      await context.deactivate('rooms', fixture.roomTwo.id);

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
      'menghapus baris ruangan nonaktif membuat dokumen dapat diposting lagi',
      () async {
        final id = await draftWithOneLine(roomId: fixture.roomTwo.id);
        await addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        );
        await context.deactivate('rooms', fixture.roomTwo.id);

        final lines = await distributionLineIdsByPosition(context, id);
        final stuck = lines['${fixture.roomTwo.id}|${fixture.simpleItem.id}|']!;
        await context.removeDistributionLine.call(
          actorUserId: fixture.branchHead.id,
          distributionId: id,
          lineId: stuck,
        );

        final result = await context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id);
        expect(result.distribution.isPosted, isTrue);
        expect(result.roomCount, 1);
      },
    );

    test('satu ruangan tidak valid membatalkan seluruh dokumen', () async {
      // Three rooms, one of them switched off after the fact. There is no partial
      // posting: G-T4 makes the whole document fail, and the other two rooms receive
      // nothing.
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      for (final room in [
        fixture.roomOne,
        fixture.roomTwo,
        fixture.roomThree,
      ]) {
        await addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: room.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        );
      }
      await context.deactivate('rooms', fixture.roomThree.id);

      await expectLater(
        context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionRoomInactiveFailure>()),
      );

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
          Quantity.zero(),
        );
      }
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('10.5'),
      );
    });
  });

  group('lokasi ruangan', () {
    test('ruangan tanpa lokasi stok ditolak', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      await context.archive('stock_locations', fixture.locationTwo.id);

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomTwo.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionRoomLocationNotFoundFailure>()),
      );
    });

    test('dua lokasi untuk satu ruangan ditolak sebagai ambigu', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      await context.insertDuplicateLocation(
        id: 'room-one-duplicate',
        type: 'room',
        name: 'Ruang Dental 1 (duplikat)',
        branchId: fixture.branch.id,
        roomId: fixture.roomOne.id,
      );

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionRoomLocationAmbiguousFailure>()),
      );
    });

    test('lokasi ruangan yang salah cabang ditolak', () async {
      // A misfiled location row: the type and the room are right, the branch is not.
      // The policy re-checks all three on the resolved row rather than trusting the
      // query that found it.
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      await context.database.customStatement(
        'UPDATE stock_locations SET branch_id = ? WHERE id = ?;',
        [fixture.otherBranch.id, fixture.locationOne.id],
      );

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionRoomLocationNotFoundFailure>()),
      );
    });
  });

  group('gudang cabang sumber', () {
    test('sumber selalu gudang cabang dokumen, bukan warehouse', () async {
      final id = await draftWithOneLine();
      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(result.branchStore.id, fixture.branchStore.id);
      final movements = await context.distributionMovements(id);
      expect(movements, hasLength(1));
      expect(movements.single['from_location_id'], fixture.branchStore.id);
      expect(movements.single['from_location_id'], isNot(fixture.warehouse.id));
      // Warehouse Pusat is untouched by a distribution.
      final warehouseMovements = await context.database
          .customSelect(
            "SELECT COUNT(*) AS c FROM stock_movements "
            "WHERE ref_doc_type = 'DIST' AND (from_location_id = ? "
            'OR to_location_id = ?);',
            variables: [
              Variable<String>(fixture.warehouse.id),
              Variable<String>(fixture.warehouse.id),
            ],
          )
          .getSingle();
      expect(warehouseMovements.read<int>('c'), 0);
    });

    test('gudang cabang lain tidak pernah menjadi sumber', () async {
      final id = await draftWithOneLine();
      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(result.branchStore.id, isNot(fixture.otherBranchStore.id));
      final movements = await context.distributionMovements(id);
      expect(
        movements.single['from_location_id'],
        isNot(fixture.otherBranchStore.id),
      );
    });

    test('gudang cabang yang diarsipkan memblokir posting', () async {
      // §32: an out-of-service store cannot supply goods, so — unlike a Good Receipt,
      // which falls back to the archived row it was raised against — a distribution
      // refuses. It is new work, not the completion of old work.
      final id = await draftWithOneLine();
      await context.archive('stock_locations', fixture.branchStore.id);

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionBranchStoreNotFoundFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
      expect(await context.distributionMovementCount(id), 0);
    });

    test('dua gudang cabang memblokir posting sebagai ambigu', () async {
      final id = await draftWithOneLine();
      await context.insertDuplicateLocation(
        id: 'branch-store-duplicate',
        type: 'branch_store',
        name: 'Gudang Cabang Uji Kedua',
        branchId: fixture.branch.id,
      );

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionBranchStoreAmbiguousFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
    });
  });

  group('RBAC', () {
    test('Kepala Cabang cabang lain tidak dapat menambah baris', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
          actorUserId: fixture.otherBranchHead.id,
        ),
        throwsA(isA<DistributionBranchMismatchFailure>()),
      );
    });

    test('Kepala Cabang cabang lain tidak dapat memposting', () async {
      final id = await draftWithOneLine();

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.otherBranchHead.id, distributionId: id),
        throwsA(isA<DistributionBranchMismatchFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
    });

    test('Warehouse tidak dapat membuat, menambah atau memposting', () async {
      expect(
        () => context
            .createDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id),
        throwsA(isA<InvalidReviewerFailure>()),
      );

      final id = await draftWithOneLine();
      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomTwo.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
          actorUserId: fixture.warehouseUser.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, distributionId: id),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('Perawat tidak dapat membuat, menambah atau memposting', () async {
      expect(
        () => context
            .createDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.nurse.id),
        throwsA(isA<InvalidReviewerFailure>()),
      );

      final id = await draftWithOneLine();
      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.nurse.id, distributionId: id),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('Super Admin tidak diberi akses tulis', () async {
      // G-R4: an account being powerful is not a reason to hand it somebody else's
      // job. Spec §3.1 gives Distribusi to `kepala_cabang` alone.
      expect(
        () => context
            .createDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.superAdmin.id),
        throwsA(isA<InvalidReviewerFailure>()),
      );

      final id = await draftWithOneLine();
      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.superAdmin.id, distributionId: id),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('Kepala Cabang nonaktif ditolak', () async {
      final id = await draftWithOneLine();
      await context.deactivate('users', fixture.branchHead.id);

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('pengguna yang tidak ada ditolak', () async {
      expect(
        () => context
            .createDistribution(clock: () => nowUtc)
            .call(actorUserId: 'tidak-ada'),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });
  });

  group('pembacaan SQL berbatas cabang', () {
    test('daftar cabang lain tidak memuat dokumen cabang ini', () async {
      final id = await draftWithOneLine();

      final own = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(own.map((summary) => summary.id), contains(id));

      final foreign = await context.distributions.listForBranch(
        branchId: fixture.otherBranch.id,
      );
      expect(foreign, isEmpty);
    });

    test('getForBranch cabang lain mengembalikan null', () async {
      final id = await draftWithOneLine();

      expect(
        await context.distributions.getForBranch(
          distributionId: id,
          branchId: fixture.otherBranch.id,
        ),
        isNull,
      );
      expect(
        await context.distributions.getForBranch(
          distributionId: id,
          branchId: fixture.branch.id,
        ),
        isNotNull,
      );
    });

    test('findAccessScope cabang lain mengembalikan null', () async {
      final id = await draftWithOneLine();

      expect(
        await context.distributions.findAccessScope(
          distributionId: id,
          branchId: fixture.otherBranch.id,
        ),
        isNull,
      );
      // And an id that does not exist answers the same way, so the two cannot be told
      // apart from outside.
      expect(
        await context.distributions.findAccessScope(
          distributionId: 'tidak-ada',
          branchId: fixture.branch.id,
        ),
        isNull,
      );

      final scope = await context.distributions.findAccessScope(
        distributionId: id,
        branchId: fixture.branch.id,
      );
      expect(scope!.branchId, fixture.branch.id);
    });

    test(
      'watchForBranch cabang lain tidak pernah memancarkan dokumen',
      () async {
        final id = await draftWithOneLine();

        final emitted = await context.distributions
            .watchForBranch(
              distributionId: id,
              branchId: fixture.otherBranch.id,
            )
            .first;
        expect(emitted, isNull);
      },
    );

    test('daftar ruangan hanya memuat ruangan cabang sendiri', () async {
      final rooms = await context.distributions.branchRooms(fixture.branch.id);
      expect(rooms.map((room) => room.id), <String>[
        fixture.roomOne.id,
        fixture.roomTwo.id,
        fixture.roomThree.id,
      ]);
      expect(
        rooms.map((room) => room.id),
        isNot(contains(fixture.otherBranchRoom.id)),
      );
    });
  });

  group('kebijakan murni', () {
    test('verifyRoom menolak cabang lain sebelum menolak nonaktif', () async {
      // Order matters: "this room is not yours" must not be distinguishable from
      // "this room is switched off", or a message would tell a branch head something
      // true about another branch's room.
      final foreignRoom = await context.master.historicalRoomById(
        fixture.otherBranchRoom.id,
      );
      await context.deactivate('rooms', fixture.otherBranchRoom.id);

      final verdict = DistributionRoomPolicy.verifyRoom(
        room: foreignRoom,
        branchId: fixture.branch.id,
      );
      expect(verdict.rejection, DistributionRoomRejection.branchMismatch);
    });

    test('verifyRoom menolak ruangan yang tidak ada', () {
      final verdict = DistributionRoomPolicy.verifyRoom(
        room: null,
        branchId: fixture.branch.id,
      );
      expect(verdict.rejection, DistributionRoomRejection.missing);
    });

    test('isDistinctLeg menolak sumber sama dengan tujuan', () {
      expect(
        DistributionRoomPolicy.isDistinctLeg(
          sourceLocationId: 'a',
          destinationLocationId: 'a',
        ),
        isFalse,
      );
      expect(
        DistributionRoomPolicy.isDistinctLeg(
          sourceLocationId: 'a',
          destinationLocationId: 'b',
        ),
        isTrue,
      );
    });
  });
}
