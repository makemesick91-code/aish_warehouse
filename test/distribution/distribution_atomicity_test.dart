import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/distribution/domain/services/distribution_state_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_inventory_repository.dart';
import '../helpers/test_context.dart';

/// G-T4 — *"Posting bersifat atomik: semua baris berhasil atau semua batal"* (§40).
///
/// The assertion every test here makes is the same one, from a different angle: after a
/// failed posting the database looks exactly as it did before. That means **zero**
/// movements, the store balance unchanged, every room balance unchanged, the status
/// still `draft` and `posted_at` still null — and it has to hold whichever line the
/// failure lands on, which is why the failures below are placed on the first line, the
/// middle one and the last one in turn.
///
/// The failure is injected through [FailingInventoryRepository] rather than by stubbing
/// the posting service, so the real posting logic stays in the path and the failure
/// lands where a real one would.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A three-room document, one line each, six units in total.
  Future<String> threeRoomDraft() async {
    final id = await createDistributionDraft(context, fixture, nowUtc: nowUtc);
    for (final entry in [
      (room: fixture.roomOne, qty: '1'),
      (room: fixture.roomTwo, qty: '2'),
      (room: fixture.roomThree, qty: '3'),
    ]) {
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: entry.room.id,
        itemId: fixture.simpleItem.id,
        qty: entry.qty,
        nowUtc: nowUtc,
      );
    }
    return id;
  }

  /// Asserts the database is untouched by a failed posting.
  Future<void> expectNothingWritten(String id) async {
    expect(await context.distributionStatusOf(id), 'draft');
    expect(await context.distributionColumn(id, 'posted_at'), isNull);
    expect(await context.distributionMovementCount(id), 0);
    expect(
      await branchStoreBalance(context, fixture, itemId: fixture.simpleItem.id),
      Quantity.parse('10.5'),
    );
    for (final room in [fixture.roomOne, fixture.roomTwo, fixture.roomThree]) {
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: room.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
        reason: '${room.code} menerima stok dari posting yang gagal.',
      );
    }
  }

  group('sukses', () {
    test('dokumen multi-baris satu ruangan berhasil', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
        nowUtc: nowUtc,
      );

      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(result.lineCount, 2);
      expect(result.movements, hasLength(2));
      expect(await context.distributionStatusOf(id), 'posted');
      expect(await context.distributionColumn(id, 'posted_at'), isNotNull);
    });

    test('dokumen multi-ruangan berhasil', () async {
      final id = await threeRoomDraft();

      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(result.roomCount, 3);
      expect(await context.distributionMovementCount(id), 3);
    });
  });

  group('rollback', () {
    test('kegagalan pada baris pertama tidak menulis apa pun', () async {
      final id = await threeRoomDraft();
      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 0,
      );

      await expectLater(
        context
            .postDistribution(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(failing.appendedBeforeFailure, 0);
      await expectNothingWritten(id);
    });

    test('kegagalan pada baris kedua membatalkan baris pertama', () async {
      final id = await threeRoomDraft();
      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 1,
      );

      await expectLater(
        context
            .postDistribution(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      // One movement *was* appended before the failure — and it is gone anyway, which
      // is the whole point: the transaction, not the loop, decides what survives.
      expect(failing.appendedBeforeFailure, 1);
      await expectNothingWritten(id);
    });

    test('kegagalan pada baris terakhir membatalkan semuanya', () async {
      final id = await threeRoomDraft();
      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 2,
      );

      await expectLater(
        context
            .postDistribution(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(failing.appendedBeforeFailure, 2);
      await expectNothingWritten(id);
    });

    test('kegagalan pada ruangan tertentu membatalkan ruangan lain', () async {
      // Failing by destination is the distribution-shaped version of the assertion:
      // every room receives the same product, so failing by item could not express
      // "the last room broke and the earlier ones must not keep their stock".
      //
      // Which room the plan posts last is decided by `(room_id, item_id, batch_id)` —
      // deterministic for a given database, but the ids are UUIDs, so the test works
      // out the last one rather than assuming it is R3.
      final id = await threeRoomDraft();
      final lastRoomId = ([
        fixture.roomOne.id,
        fixture.roomTwo.id,
        fixture.roomThree.id,
      ]..sort()).last;
      final failing = FailingInventoryRepository(
        context.inventory,
        failOnToLocationId: fixture.locationForRoom(lastRoomId).id,
      );

      await expectLater(
        context
            .postDistribution(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(failing.appendedBeforeFailure, 2);
      await expectNothingWritten(id);
    });

    test('tidak ada pergerakan sisa di seluruh ledger', () async {
      // Not merely "none under this document's reference": a rolled-back posting must
      // leave the ledger byte-identical, whatever `ref_doc_type` a stray row carried.
      final before = await context.totalMovementCount();
      final id = await threeRoomDraft();
      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 1,
      );

      await expectLater(
        context
            .postDistribution(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(await context.totalMovementCount(), before);
    });

    test('baris draft tetap dapat diperbaiki setelah kegagalan', () async {
      final id = await threeRoomDraft();
      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 1,
      );

      await expectLater(
        context
            .postDistribution(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      // Still a draft, so the branch head can adjust and try again — with the real
      // posting service this time.
      final lines = await distributionLineIdsByPosition(context, id);
      await context
          .updateDistributionLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            distributionId: id,
            lineId: lines['${fixture.roomOne.id}|${fixture.simpleItem.id}|']!,
            qty: Quantity.parse('5'),
          );

      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);
      expect(result.totalQty, Quantity.parse('10'));
      expect(await context.distributionStatusOf(id), 'posted');
    });
  });

  group('posting ganda', () {
    test(
      'memposting dua kali ditolak dan tidak menduplikasi pergerakan',
      () async {
        final id = await threeRoomDraft();
        await context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id);

        expect(await context.distributionMovementCount(id), 3);

        expect(
          () => context
              .postDistribution(clock: () => nowUtc)
              .call(actorUserId: fixture.branchHead.id, distributionId: id),
          throwsA(isA<DistributionAlreadyPostedFailure>()),
        );
        expect(await context.distributionMovementCount(id), 3);
        expect(
          await branchStoreBalance(
            context,
            fixture,
            itemId: fixture.simpleItem.id,
          ),
          Quantity.parse('4.5'),
        );
      },
    );

    test(
      'posting bersamaan atas dokumen yang sama hanya berhasil sekali',
      () async {
        final id = await threeRoomDraft();

        final results = await Future.wait([
          context
              .postDistribution(clock: () => nowUtc)
              .call(actorUserId: fixture.branchHead.id, distributionId: id)
              .then((_) => true)
              .catchError((_) => false),
          context
              .postDistribution(clock: () => nowUtc)
              .call(actorUserId: fixture.branchHead.id, distributionId: id)
              .then((_) => true)
              .catchError((_) => false),
        ]);

        expect(results.where((ok) => ok), hasLength(1));
        expect(await context.distributionStatusOf(id), 'posted');
        // The guarded UPDATE is what makes this exact: three lines, three movements,
        // whichever attempt lost.
        expect(await context.distributionMovementCount(id), 3);
        expect(
          await branchStoreBalance(
            context,
            fixture,
            itemId: fixture.simpleItem.id,
          ),
          Quantity.parse('4.5'),
        );
      },
    );
  });

  group('dokumen final bersifat read-only', () {
    test('dokumen kosong tidak dapat diposting', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionLineRequiredFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
    });

    test('baris dokumen posted tidak dapat diubah', () async {
      final id = await threeRoomDraft();
      final lines = await distributionLineIdsByPosition(context, id);
      final lineId = lines['${fixture.roomOne.id}|${fixture.simpleItem.id}|']!;
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(
        () => context
            .updateDistributionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              distributionId: id,
              lineId: lineId,
              qty: Quantity.parse('9'),
            ),
        throwsA(isA<DistributionAlreadyPostedFailure>()),
      );

      final rows = await context.distributionLineRows(id);
      expect(rows[lineId]!['qty'], 1000);
    });

    test('baris dokumen posted tidak dapat dihapus', () async {
      final id = await threeRoomDraft();
      final lines = await distributionLineIdsByPosition(context, id);
      final lineId = lines['${fixture.roomOne.id}|${fixture.simpleItem.id}|']!;
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(
        () => context.removeDistributionLine.call(
          actorUserId: fixture.branchHead.id,
          distributionId: id,
          lineId: lineId,
        ),
        throwsA(isA<DistributionAlreadyPostedFailure>()),
      );
      expect(await context.distributionLineCount(id), 3);
    });

    test('baris tidak dapat ditambahkan ke dokumen posted', () async {
      final id = await threeRoomDraft();
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionAlreadyPostedFailure>()),
      );
      expect(await context.distributionLineCount(id), 3);
    });
  });

  group('mesin status', () {
    test('draft → posted adalah satu-satunya transisi', () {
      expect(DistributionStatePolicy.nextStatesOf(DistributionStatus.draft), {
        DistributionStatus.posted,
      });
      expect(
        DistributionStatePolicy.nextStatesOf(DistributionStatus.posted),
        isEmpty,
      );
    });

    test('posted tidak punya transisi keluar', () {
      expect(
        DistributionStatePolicy.isAllowed(
          DistributionStatus.posted,
          DistributionStatus.draft,
        ),
        isFalse,
      );
      expect(
        DistributionStatePolicy.isAllowed(
          DistributionStatus.posted,
          DistributionStatus.posted,
        ),
        isFalse,
      );
      expect(
        DistributionStatePolicy.isAllowed(
          DistributionStatus.draft,
          DistributionStatus.draft,
        ),
        isFalse,
      );
    });

    test('hanya Kepala Cabang boleh menjalankan transisi', () {
      for (final role in UserRole.values) {
        expect(
          DistributionStatePolicy.isAllowedFor(
            role: role,
            from: DistributionStatus.draft,
            to: DistributionStatus.posted,
          ),
          role == UserRole.kepalaCabang,
          reason: 'Peran ${role.dbValue} salah dinilai.',
        );
      }
    });

    test('enum menyetujui tabel kebijakan', () {
      expect(
        DistributionStatus.draft.canTransitionTo(DistributionStatus.posted),
        isTrue,
      );
      expect(
        DistributionStatus.posted.canTransitionTo(DistributionStatus.draft),
        isFalse,
      );
      expect(DistributionStatus.draft.isEditable, isTrue);
      expect(DistributionStatus.posted.isEditable, isFalse);
      expect(DistributionStatus.posted.isFinal, isTrue);
      expect(DistributionStatus.draft.canPost, isTrue);
      expect(DistributionStatus.posted.canPost, isFalse);
    });
  });
}
