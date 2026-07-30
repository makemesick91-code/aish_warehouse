import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Historical recovery: a posted Pemakaian stays readable whatever happens to the master
/// data afterwards (§33).
///
/// The rule has two halves and they pull in opposite directions, which is exactly why they
/// need separate tests:
///
/// * **reading** a posted document never fails. Its branch may be closed, its room retired,
///   its item withdrawn, its batch archived and the nurse who posted it deactivated — and
///   the document still says what it said, with badges explaining which rows are history
///   (G-A4/G-A5). Nothing about it is hidden, because a consumption is the record of where
///   room stock went and losing it would leave the ledger unexplained.
/// * **posting** an existing draft is refused when the *operational* conditions no longer
///   hold: an inactive room, an archived room location, an expired batch, an inactive
///   actor. This is where the Pemakaian rule is stricter than the Pemusnahan's — taking
///   expired goods off a decommissioned shelf lowers risk, whereas recording usage in a
///   room the clinic has closed asserts activity in a place nobody is working (§15).
///
/// A reference that is *physically gone* is the third case, and it is neither: it is an
/// explicit failure naming the table and the id, never a skipped line and never a
/// substitution.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> postedDocument() async {
    final id = await createConsumptionDraft(
      context,
      fixture,
      roomId: fixture.roomOne.id,
      nowUtc: nowUtc,
      note: 'shift pagi',
    );
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
      itemId: fixture.plainItem.id,
      qty: '2.25',
      nowUtc: nowUtc,
    );
    await context.postConsumption().call(
      actorUserId: fixture.nurse.id,
      consumptionId: id,
    );
    return id;
  }

  Future<String> draftDocument() async {
    final id = await createConsumptionDraft(
      context,
      fixture,
      roomId: fixture.roomOne.id,
      nowUtc: nowUtc,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.expiryItem.id,
      batchId: fixture.validBatch.id,
      qty: '1',
      nowUtc: nowUtc,
    );
    return id;
  }

  group('dokumen posted tetap terbaca', () {
    test('cabang dinonaktifkan', () async {
      final id = await postedDocument();
      await context.deactivate('branches', fixture.branch.id);

      final own = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(own, isNotNull);
      expect(own!.lines, hasLength(2));
      expect(own.summary.branchIsHistorical, isTrue);
      expect(own.summary.branchName, fixture.branch.name);

      // …and the branch head can still read it.
      final branch = await context.consumptions.getPostedForBranch(
        consumptionId: id,
        branchId: fixture.branch.id,
      );
      expect(branch, isNotNull);
    });

    test('ruangan dinonaktifkan', () async {
      final id = await postedDocument();
      await context.deactivate('rooms', fixture.roomOne.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail, isNotNull);
      expect(detail!.room.name, fixture.roomOne.name);
      expect(detail.room.code, fixture.roomOne.code);
      expect(detail.room.isHistorical, isTrue);
      expect(detail.summary.roomIsHistorical, isTrue);
      expect(detail.usesHistoricalMaster, isTrue);
    });

    test('ruangan diarsipkan', () async {
      final id = await postedDocument();
      await context.archive('rooms', fixture.roomOne.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail, isNotNull);
      expect(detail!.room.isArchived, isTrue);
      expect(detail.room.isHistorical, isTrue);
    });

    test('lokasi ruangan diarsipkan', () async {
      final id = await postedDocument();
      await context.archive('stock_locations', fixture.locationOne.id);

      // The document names its *room*, not a location id, so an archived location does not
      // touch the read at all — which is the whole reason §8 stores the room.
      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail, isNotNull);
      expect(detail!.lines, hasLength(2));
    });

    test('barang dinonaktifkan', () async {
      final id = await postedDocument();
      await context.deactivate('items', fixture.expiryItem.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail!.lines, hasLength(2));
      final line = detail.lines.firstWhere(
        (line) => line.itemId == fixture.expiryItem.id,
      );
      expect(line.itemName, fixture.expiryItem.name);
      expect(line.sku, fixture.expiryItem.sku);
      expect(line.itemIsHistorical, isTrue);
    });

    test('kategori dinonaktifkan tidak menyembunyikan baris', () async {
      final id = await postedDocument();
      // Categories carry no `is_active`, so an administrator's way of retiring one is to
      // stop using it. What matters is that the detail read joins nothing on categories, so
      // a line keeps its own `categoryId` and its item name either way.
      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail!.lines.map((line) => line.categoryId).toSet(), {
        fixture.category.id,
      });
    });

    test('batch diarsipkan', () async {
      final id = await postedDocument();
      await context.archive('item_batches', fixture.validBatch.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      final line = detail!.lines.firstWhere((line) => line.isBatched);
      expect(line.batchNo, fixture.validBatch.batchNo);
      expect(line.expiryDate, isNotNull);
      expect(line.batchIsHistorical, isTrue);
    });

    test('perawat dinonaktifkan', () async {
      final id = await postedDocument();
      await context.deactivate('users', fixture.nurse.id);

      final detail = await context.consumptions.getPostedForBranch(
        consumptionId: id,
        branchId: fixture.branch.id,
      );
      expect(detail, isNotNull);
      expect(detail!.summary.createdByName, fixture.nurse.fullName);
      expect(detail.summary.postedByName, fixture.nurse.fullName);
      expect(detail.summary.createdByIsHistorical, isTrue);
      expect(detail.summary.postedByIsHistorical, isTrue);
    });

    test('semuanya sekaligus', () async {
      final id = await postedDocument();
      await context.deactivate('branches', fixture.branch.id);
      await context.deactivate('rooms', fixture.roomOne.id);
      await context.deactivate('items', fixture.expiryItem.id);
      await context.deactivate('items', fixture.plainItem.id);
      await context.archive('item_batches', fixture.validBatch.id);
      await context.deactivate('users', fixture.nurse.id);

      final detail = await context.consumptions.getPostedForBranch(
        consumptionId: id,
        branchId: fixture.branch.id,
      );
      expect(detail, isNotNull);
      expect(detail!.lines, hasLength(2));
      expect(detail.usesHistoricalMaster, isTrue);
      expect(detail.totalQuantityByUnit, {
        'ampul': Quantity.parse('1.5'),
        'box': Quantity.parse('2.25'),
      });
      // The ledger still names the document, whatever happened to the master data.
      expect(await context.consumptionMovementCount(id), 2);
    });

    test('daftar tetap memuat dokumen dengan master historis', () async {
      final id = await postedDocument();
      await context.deactivate('rooms', fixture.roomOne.id);
      await context.deactivate('users', fixture.nurse.id);

      final own = await context.consumptions.listOwn(
        actorUserId: fixture.nurse.id,
      );
      expect(own.map((row) => row.id), [id]);
      expect(own.single.usesHistoricalMaster, isTrue);

      final branch = await context.consumptions.listPostedForBranch(
        branchId: fixture.branch.id,
      );
      expect(branch.map((row) => row.id), [id]);
    });
  });

  group('draft existing: dapat dibaca, tidak selalu dapat diposting', () {
    test('barang nonaktif tetap terbaca dan tetap dapat diposting', () async {
      // The line already exists, so a product withdrawn from the catalogue afterwards must
      // not trap the nurse: the goods came off the room's shelf either way (§33).
      final id = await draftDocument();
      await context.deactivate('items', fixture.expiryItem.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail!.lines.single.itemIsHistorical, isTrue);

      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );
      expect(result.consumption.isPosted, isTrue);
    });

    test('batch diarsipkan tetap dapat diposting', () async {
      final id = await draftDocument();
      await context.archive('item_batches', fixture.validBatch.id);

      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );
      expect(result.consumption.isPosted, isTrue);
      expect(await context.consumptionMovementCount(id), 1);
    });

    test('ruangan nonaktif memblokir posting tetapi bukan bacaan', () async {
      final id = await draftDocument();
      await context.deactivate('rooms', fixture.roomOne.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail, isNotNull);
      expect(detail!.lines, hasLength(1));

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionRoomInactiveFailure>()),
      );
      expect(await context.consumptionStatusOf(id), 'draft');
      expect(await context.consumptionMovementCount(id), 0);
    });

    test('lokasi ruangan diarsipkan memblokir posting', () async {
      final id = await draftDocument();
      await context.archive('stock_locations', fixture.locationOne.id);

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionRoomLocationNotFoundFailure>()),
      );
      expect(await context.consumptionMovementCount(id), 0);
    });

    test('aktor nonaktif memblokir posting', () async {
      final id = await draftDocument();
      await context.deactivate('users', fixture.nurse.id);

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('aktor berubah peran memblokir posting', () async {
      final id = await draftDocument();
      await context.database.customStatement(
        'UPDATE users SET role = ? WHERE id = ?;',
        [UserRole.kepalaCabang.dbValue, fixture.nurse.id],
      );

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('batch kedaluwarsa memblokir posting', () async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
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

      final later = nowUtc.add(const Duration(days: 11));
      await expectLater(
        context
            .postConsumption(clock: () => later)
            .call(actorUserId: fixture.nurse.id, consumptionId: id),
        throwsA(isA<ExpiredBatchForConsumptionFailure>()),
      );
      // Still readable, and the badge on it now says why.
      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail!.lines.single.isExpiredOn(later), isTrue);
      expect(detail.progressOn(later).allUsable, isFalse);
    });

    test('saldo hilang memblokir posting dengan kekurangan yang jelas', () async {
      final id = await draftDocument();

      // Another document drains the position first.
      final rival = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
        actorUserId: fixture.otherNurse.id,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: rival,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '5.5',
        nowUtc: nowUtc,
        actorUserId: fixture.otherNurse.id,
      );
      await context.postConsumption().call(
        actorUserId: fixture.otherNurse.id,
        consumptionId: rival,
      );

      Object? caught;
      try {
        await context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        );
      } on Object catch (error) {
        caught = error;
      }

      expect(caught, isA<InsufficientRoomStockFailure>());
      final failure = caught as InsufficientRoomStockFailure;
      // The numbers are the point: a shortfall the nurse can act on rather than a bare
      // refusal (§18).
      expect(failure.available, Quantity.zero());
      expect(failure.requested, Quantity.parse('1'));
      expect(failure.batchId, fixture.validBatch.id);
    });
  });

  group('referensi hilang fisik', () {
    test('barang hilang: kegagalan eksplisit, bukan baris terlewat', () async {
      final id = await draftDocument();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.corruptByDeleting('items', fixture.plainItem.id);

      // The plain select still knows about both lines; the joined read has lost one.
      expect(await context.consumptions.lineReferences(id), hasLength(2));
      expect((await context.consumptions.getDetail(id))!.lines, hasLength(1));

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionLineIntegrityFailure>()),
      );

      expect(await context.consumptionMovementCount(id), 0);
      expect(await context.consumptionStatusOf(id), 'draft');
      expect(
        await context.consumptionLineCount(id),
        2,
        reason: 'Baris tidak boleh dihapus atau diganti (§33).',
      );
    });

    test('batch hilang: kegagalan menamai tabel dan id', () async {
      final id = await draftDocument();
      await context.corruptByDeleting('item_batches', fixture.validBatch.id);

      Object? caught;
      try {
        await context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        );
      } on Object catch (error) {
        caught = error;
      }

      expect(caught, isA<HistoricalConsumptionReferenceMissingFailure>());
      final failure = caught as HistoricalConsumptionReferenceMissingFailure;
      expect(failure.entity, 'item_batches');
      expect(failure.id, fixture.validBatch.id);
      expect(failure.consumptionId, id);
      expect(await context.consumptionMovementCount(id), 0);
    });

    test('ruangan hilang: kegagalan menamai rooms', () async {
      final id = await draftDocument();
      await context.corruptByDeleting('rooms', fixture.roomOne.id);

      Object? caught;
      try {
        await context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        );
      } on Object catch (error) {
        caught = error;
      }

      expect(caught, isA<HistoricalConsumptionReferenceMissingFailure>());
      expect(
        (caught as HistoricalConsumptionReferenceMissingFailure).entity,
        'rooms',
      );
      expect(await context.consumptionMovementCount(id), 0);
    });

    test('tidak ada substitusi item, batch atau ruangan', () async {
      final id = await draftDocument();
      final before = await context.consumptionLineRows(id);
      await context.corruptByDeleting('item_batches', fixture.validBatch.id);

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(anything),
      );

      // Byte-identical: nothing repaired, nothing guessed.
      expect(await context.consumptionLineRows(id), before);
      expect(
        await context.consumptionColumn(id, 'room_id'),
        fixture.roomOne.id,
      );
    });
  });
}
