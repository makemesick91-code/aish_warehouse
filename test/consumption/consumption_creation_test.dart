import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Creating a Pemakaian, and who may (§38).
///
/// The interesting half of this file is the refusals. §14 gives the write path to
/// `perawat` alone, and to *one* nurse per document — so the tests below exercise not
/// only "the wrong role" but the case no earlier milestone had: **the right role, wrong
/// person**. A second nurse in the same branch passes every check an earlier document
/// would have applied, and must still be refused.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  /// A fixed instant so every expiry boundary in the fixture is deterministic.
  /// `2026-07-30T08:00:00Z` is `2026-07-30 16:00 GMT+8` — comfortably inside one
  /// operational day, so a test that does not care about the boundary never trips over
  /// it.
  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('pembuatan', () {
    test('perawat aktif dapat membuat draft untuk ruangan cabangnya', () async {
      final consumption = await context.createConsumption().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.roomOne.id,
      );

      expect(consumption.status, ConsumptionStatus.draft);
      expect(consumption.roomId, fixture.roomOne.id);
      expect(consumption.branchId, fixture.branch.id);
      expect(consumption.createdBy, fixture.nurse.id);
      expect(consumption.postedAt, isNull);
      expect(consumption.postedBy, isNull);
      expect(consumption.syncStatus, SyncStatus.pending);
    });

    test('nomor sementara berawalan TMP-CNS', () async {
      final consumption = await context.createConsumption().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.roomOne.id,
      );
      expect(consumption.docNumber, startsWith('TMP-CNS-'));
    });

    test('createdAt memakai clock yang disuntikkan', () async {
      final consumption = await context.createConsumption().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.roomOne.id,
      );
      expect(consumption.createdAt, nowUtc);
      expect(consumption.createdAt.isUtc, isTrue);
    });

    test('catatan opsional dinormalisasi; spasi menjadi null', () async {
      final withNote = await context.createConsumption().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.roomOne.id,
        note: '  Pemakaian shift pagi  ',
      );
      expect(withNote.note, 'Pemakaian shift pagi');

      final blank = await context.createConsumption().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.roomTwo.id,
        note: '  \n\t ',
      );
      expect(blank.note, isNull);
      expect(blank.hasNote, isFalse);
    });

    test('dokumen tanpa catatan tetap sah — catatan tidak wajib', () async {
      // The difference from a Pemusnahan, asserted rather than assumed: G-E7 makes a
      // disposal reason mandatory and nothing asks a nurse to justify ordinary usage.
      final consumption = await context.createConsumption().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.roomOne.id,
      );
      expect(consumption.note, isNull);

      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: consumption.id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: consumption.id,
      );
      expect(result.consumption.isPosted, isTrue);
    });

    test(
      'membuat draft tidak menulis movement dan tidak mengubah saldo',
      () async {
        final before = await locationBalance(
          context,
          locationId: fixture.locationOne.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        );
        final movementsBefore = await context.totalMovementCount();

        final consumption = await context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.roomOne.id,
        );

        expect(await context.totalMovementCount(), movementsBefore);
        expect(
          await locationBalance(
            context,
            locationId: fixture.locationOne.id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.validBatch.id,
          ),
          before,
        );
        expect(await context.consumptionMovementCount(consumption.id), 0);
      },
    );

    test('draft kosong tidak dapat diposting', () async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
      );

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionLineRequiredFailure>()),
      );
      expect(await context.consumptionStatusOf(id), 'draft');
    });
  });

  group('ruangan', () {
    test('ruangan cabang lain ditolak', () async {
      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.otherBranchRoom.id,
        ),
        throwsA(isA<ConsumptionRoomBranchMismatchFailure>()),
      );
    });

    test('ruangan tidak aktif ditolak', () async {
      await context.deactivate('rooms', fixture.roomTwo.id);

      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.roomTwo.id,
        ),
        throwsA(isA<ConsumptionRoomInactiveFailure>()),
      );
    });

    test('ruangan diarsipkan ditolak', () async {
      await context.archive('rooms', fixture.roomTwo.id);

      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.roomTwo.id,
        ),
        throwsA(isA<ConsumptionRoomInactiveFailure>()),
      );
    });

    test('ruangan tidak ada ditolak', () async {
      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: 'tidak-ada',
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });

    test('cabang tidak aktif ditolak', () async {
      await context.deactivate('branches', fixture.branch.id);

      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.roomOne.id,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('lokasi stok ruangan hilang ditolak', () async {
      await context.archive('stock_locations', fixture.locationTwo.id);

      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.roomTwo.id,
        ),
        throwsA(isA<ConsumptionRoomLocationNotFoundFailure>()),
      );
    });

    test('lokasi stok ruangan ganda ditolak', () async {
      // The state `ensureLocation` cannot produce, and §15 says a consumption must
      // refuse rather than guess which shelf the goods left.
      await context.insertDuplicateLocation(
        id: 'dup-room-loc',
        type: StockLocationType.room.dbValue,
        name: 'Ruang Dental 2 (duplikat)',
        branchId: fixture.branch.id,
        roomId: fixture.roomTwo.id,
      );

      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.roomTwo.id,
        ),
        throwsA(isA<ConsumptionRoomLocationAmbiguousFailure>()),
      );
    });

    test('gudang cabang dan warehouse bukan sumber yang dapat dinamai', () async {
      // Structural rather than checked: the create use case takes a **room id**, so a
      // location of any other type simply has no parameter to arrive through. Asserting
      // it through the room lookup is the closest a runtime test can get, and the
      // architecture test asserts the absence of a location parameter directly.
      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.branchStore.id,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.warehouse.id,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });
  });

  group('peran', () {
    test('kepala cabang tidak dapat membuat', () async {
      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.branchHead.id,
          roomId: fixture.roomOne.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('petugas warehouse tidak dapat membuat', () async {
      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.warehouseUser.id,
          roomId: fixture.roomOne.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('super admin tidak dapat membuat', () async {
      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.superAdmin.id,
          roomId: fixture.roomOne.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('perawat nonaktif ditolak', () async {
      await context.deactivate('users', fixture.nurse.id);

      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.roomOne.id,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('pengguna tidak ada ditolak', () async {
      await expectLater(
        context.createConsumption().call(
          actorUserId: 'tidak-ada',
          roomId: fixture.roomOne.id,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });

    test('perawat tanpa cabang ditolak', () async {
      // Raw SQL, because `ensureUser` refuses to *create* a branchless nurse — the
      // repository already enforces that half. What this exercises is the state a
      // back-office edit or a bad sync payload can still produce, and §14 says the
      // guards must refuse it rather than treat "no branch" as "every branch".
      await context.database.customStatement(
        'UPDATE users SET branch_id = NULL WHERE id = ?;',
        [fixture.nurse.id],
      );

      await expectLater(
        context.createConsumption().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.roomOne.id,
        ),
        throwsA(isA<UnauthorizedBranchFailure>()),
      );
    });

    test(
      'perawat cabang lain tidak dapat memakai ruangan cabang ini',
      () async {
        await expectLater(
          context.createConsumption().call(
            actorUserId: fixture.otherBranchNurse.id,
            roomId: fixture.roomOne.id,
          ),
          throwsA(isA<ConsumptionRoomBranchMismatchFailure>()),
        );
      },
    );
  });

  group('kepemilikan draft (§14)', () {
    late String consumptionId;

    setUp(() async {
      consumptionId = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
      );
    });

    test(
      'perawat kedua di cabang yang sama tidak dapat menambah baris',
      () async {
        // The case no earlier milestone's guards could have caught: same role, same
        // branch, same room — a different person.
        await expectLater(
          context
              .addConsumptionLine(clock: () => nowUtc)
              .call(
                actorUserId: fixture.otherNurse.id,
                consumptionId: consumptionId,
                itemId: fixture.plainItem.id,
                qty: Quantity.parse('1'),
              ),
          throwsA(isA<ConsumptionNotOwnedFailure>()),
        );
        expect(await context.consumptionLineCount(consumptionId), 0);
      },
    );

    test('perawat kedua tidak dapat mengubah catatan', () async {
      await expectLater(
        context.updateConsumptionHeader.call(
          actorUserId: fixture.otherNurse.id,
          consumptionId: consumptionId,
          note: 'diubah orang lain',
        ),
        throwsA(isA<ConsumptionNotOwnedFailure>()),
      );
      expect(await context.consumptionColumn(consumptionId, 'note'), isNull);
    });

    test('perawat kedua tidak dapat menghapus baris', () async {
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: consumptionId,
        itemId: fixture.plainItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, consumptionId);
      final lineId = lines['${fixture.plainItem.id}|']!;

      await expectLater(
        context.removeConsumptionLine.call(
          actorUserId: fixture.otherNurse.id,
          consumptionId: consumptionId,
          lineId: lineId,
        ),
        throwsA(isA<ConsumptionNotOwnedFailure>()),
      );
      expect(await context.consumptionLineCount(consumptionId), 1);
    });

    test('perawat kedua tidak dapat memposting', () async {
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: consumptionId,
        itemId: fixture.plainItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.otherNurse.id,
          consumptionId: consumptionId,
        ),
        throwsA(isA<ConsumptionNotOwnedFailure>()),
      );
      expect(await context.consumptionStatusOf(consumptionId), 'draft');
      expect(await context.consumptionMovementCount(consumptionId), 0);
    });

    test('pembuat draft dapat melakukan semuanya', () async {
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: consumptionId,
        itemId: fixture.plainItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await context.updateConsumptionHeader.call(
        actorUserId: fixture.nurse.id,
        consumptionId: consumptionId,
        note: 'shift pagi',
      );
      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: consumptionId,
      );

      expect(result.consumption.isPosted, isTrue);
      expect(result.consumption.postedBy, fixture.nurse.id);
    });

    test('draft tidak terlihat oleh kepala cabang', () async {
      final rows = await context.consumptions.listPostedForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows, isEmpty);
    });

    test('draft tidak terlihat oleh perawat lain', () async {
      final rows = await context.consumptions.listOwn(
        actorUserId: fixture.otherNurse.id,
      );
      expect(rows, isEmpty);

      final detail = await context.consumptions.getOwn(
        consumptionId: consumptionId,
        actorUserId: fixture.otherNurse.id,
      );
      expect(detail, isNull);
    });

    test('perubahan peran sesi menolak tulis', () async {
      // The actor is re-read from the database on every write (O-8), so demoting the
      // account mid-session refuses the next write rather than the one after a restart.
      await context.database.customStatement(
        'UPDATE users SET role = ? WHERE id = ?;',
        [UserRole.kepalaCabang.dbValue, fixture.nurse.id],
      );

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: consumptionId,
              itemId: fixture.plainItem.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });
  });

  group('header immutable', () {
    test('hanya catatan yang dapat diubah', () async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
        note: 'awal',
      );

      await context.updateConsumptionHeader.call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
        note: 'diubah',
      );

      final after = await context.consumptions.getById(id);
      expect(after!.note, 'diubah');
      // Everything else is exactly as it was created: there is no writer that reaches
      // any of these columns.
      expect(after.roomId, fixture.roomOne.id);
      expect(after.branchId, fixture.branch.id);
      expect(after.createdBy, fixture.nurse.id);
      expect(after.status, ConsumptionStatus.draft);
      expect(after.postedAt, isNull);
      expect(after.postedBy, isNull);
    });

    test('catatan dapat dikosongkan kembali', () async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
        note: 'awal',
      );

      await context.updateConsumptionHeader.call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
        note: null,
      );
      expect((await context.consumptions.getById(id))!.note, isNull);
    });

    test('catatan dokumen posted tidak dapat diubah', () async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
        note: 'sebelum posting',
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      await expectLater(
        context.updateConsumptionHeader.call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
          note: 'sesudah posting',
        ),
        throwsA(isA<ConsumptionAlreadyPostedFailure>()),
      );
      expect(await context.consumptionColumn(id, 'note'), 'sebelum posting');
    });
  });
}
