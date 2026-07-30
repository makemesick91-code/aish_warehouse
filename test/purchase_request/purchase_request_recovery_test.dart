import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/purchase_request/domain/models/purchase_request_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Historical references: what happens to a Purchase Request when the master data it
/// points at goes out of service.
///
/// The distinction that runs through this file is the one Milestone 2.1 established
/// for Stok Opname, applied here:
///
/// * **Deactivated** (`is_active = false`, G-A4) and **soft-deleted**
///   (`deleted_at IS NOT NULL`, G-A5) rows are still *there*. A submitted request
///   still has to be readable and processable against them — it cannot go back to
///   draft to be re-pointed at something else, and an order must not become
///   unfulfillable because somebody tidied up master data on a Friday afternoon.
/// * A row that is **physically gone** is a broken reference. Nothing may be invented
///   to paper over it: the operation fails explicitly, names the row an administrator
///   has to repair, and leaves the document exactly as it was.
///
/// The one thing that is *not* forgiving is the actor performing the action right now:
/// a deactivated account may not process anything.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  /// A branch with one submitted request citing one count.
  Future<
    ({
      PurchaseRequestFixture fixture,
      String prId,
      String opnameId,
      String docNumber,
    })
  >
  submittedRequest() async {
    final fixture = await buildPurchaseRequestFixture(
      context,
      now: prWednesdayUtc(),
    );
    final opnameId = await fileOpnameForRoom(
      context,
      roomId: fixture.roomOne.id,
      nurseId: fixture.nurse.id,
      utcNow: prWednesdayUtc(),
    );
    final request = await context
        .createPurchaseRequest(clock: prWednesdayUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          selectedOpnameIds: [opnameId],
        );
    await context
        .submitPurchaseRequest(clock: prWednesdayUtc)
        .call(actorUserId: fixture.branchHead.id, prId: request.id);

    return (
      fixture: fixture,
      prId: request.id,
      opnameId: opnameId,
      docNumber: request.docNumber,
    );
  }

  group('master nonaktif tetap dapat dibaca dan diproses', () {
    test('PR submitted tetap terbaca setelah cabang nonaktif', () async {
      final setup = await submittedRequest();
      await context.deactivate('branches', setup.fixture.branch.id);

      final detail = await context.requests.getDetail(setup.prId);
      expect(detail, isNotNull);
      expect(detail!.summary.branchName, setup.fixture.branch.name);
      expect(detail.summary.branchIsHistorical, isTrue);
      expect(detail.usesHistoricalMaster, isTrue);
      expect(detail.lines, isNotEmpty);
    });

    test('PR tetap dapat diproses setelah cabang nonaktif', () async {
      final setup = await submittedRequest();
      await context.deactivate('branches', setup.fixture.branch.id);

      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);
      expect(await context.purchaseRequestStatusOf(setup.prId), 'processing');
    });

    test('PR processing tetap terbaca setelah barang nonaktif', () async {
      final setup = await submittedRequest();
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);
      final lineCount = await context.purchaseRequestLineCount(setup.prId);

      await context.deactivate('items', setup.fixture.simpleItem.id);

      final detail = await context.requests.getDetail(setup.prId);
      expect(
        detail!.lines,
        hasLength(lineCount),
        reason: 'Barang nonaktif tidak boleh menghilangkan baris.',
      );
      final line = detail.lines.firstWhere(
        (line) => line.itemId == setup.fixture.simpleItem.id,
      );
      expect(line.itemIsHistorical, isTrue);
      expect(line.itemName, setup.fixture.simpleItem.name);
    });

    test('PR tetap dapat ditolak setelah barang nonaktif', () async {
      final setup = await submittedRequest();
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);
      await context.deactivate('items', setup.fixture.simpleItem.id);

      await context
          .rejectPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.warehouseUser.id,
            prId: setup.prId,
            reason: 'Barang sudah tidak digunakan',
          );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'rejected');
    });

    test('pemohon nonaktif tidak menghilangkan dokumen', () async {
      final setup = await submittedRequest();
      await context.deactivate('users', setup.fixture.branchHead.id);

      final detail = await context.requests.getDetail(setup.prId);
      expect(detail, isNotNull);
      expect(
        detail!.summary.requestedByName,
        setup.fixture.branchHead.fullName,
      );
      expect(detail.summary.requestedByIsHistorical, isTrue);

      // And the warehouse queue still lists it — a request whose author left is
      // exactly the one somebody still has to act on.
      final queue = await context.requests.list(const PurchaseRequestFilter());
      expect(queue.map((summary) => summary.id), contains(setup.prId));
    });

    test('opname acuan historis tetap tampil dengan badge', () async {
      final setup = await submittedRequest();
      await context.deactivate('rooms', setup.fixture.roomOne.id);
      await context.deactivate('users', setup.fixture.nurse.id);

      final detail = await context.requests.getDetail(setup.prId);
      expect(detail!.opnames, hasLength(1));
      final reference = detail.opnames.single;
      expect(reference.roomIsHistorical, isTrue);
      expect(reference.countedByIsHistorical, isTrue);
      expect(reference.usesHistoricalMaster, isTrue);
      expect(reference.roomName, setup.fixture.roomOne.name);
    });

    test('ruangan yang di-archive tidak menghilangkan tautan opname', () async {
      final setup = await submittedRequest();
      await context.archive('rooms', setup.fixture.roomOne.id);

      final detail = await context.requests.getDetail(setup.prId);
      expect(detail!.opnames, hasLength(1));
      expect(detail.opnames.single.roomIsHistorical, isTrue);
    });

    test('Warehouse aktif tetap dapat memproses dokumen historis', () async {
      final setup = await submittedRequest();
      await context.deactivate('branches', setup.fixture.branch.id);
      await context.deactivate('rooms', setup.fixture.roomOne.id);
      await context.deactivate('items', setup.fixture.simpleItem.id);
      await context.deactivate('users', setup.fixture.branchHead.id);

      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);
      expect(await context.purchaseRequestStatusOf(setup.prId), 'processing');
    });
  });

  group('aktor tetap harus aktif', () {
    test('aktor Warehouse nonaktif ditolak dan status tidak berubah', () async {
      final setup = await submittedRequest();
      await context.deactivate('users', setup.fixture.warehouseUser.id);

      await expectLater(
        () => context
            .markPurchaseRequestProcessing(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.warehouseUser.id,
              prId: setup.prId,
            ),
        throwsA(isA<InactiveEntityFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'submitted');
      expect(
        await context.purchaseRequestColumn(setup.prId, 'processing_at'),
        isNull,
      );
    });

    test('aktor yang tidak ada ditolak', () async {
      final setup = await submittedRequest();

      await expectLater(
        () => context
            .markPurchaseRequestProcessing(clock: prWednesdayUtc)
            .call(actorUserId: 'user-tidak-ada', prId: setup.prId),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });
  });

  group('referensi rusak menghasilkan kegagalan eksplisit', () {
    test('barang baris yang hilang fisik menghentikan proses', () async {
      final setup = await submittedRequest();
      final storedItems = await context.requests.lineItemIds(setup.prId);

      // Corruption, not any supported operation: foreign keys are switched off so a
      // state the constraints normally prevent can be reproduced.
      await context.corruptByDeleting('items', setup.fixture.simpleItem.id);

      // The join behind `detail` silently drops the line…
      final detail = await context.requests.getDetail(setup.prId);
      expect(detail!.lines.length, lessThan(storedItems.length));

      // …so the set-integrity check is what refuses the transition, naming the row an
      // administrator has to repair.
      await expectLater(
        () => context
            .markPurchaseRequestProcessing(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.warehouseUser.id,
              prId: setup.prId,
            ),
        throwsA(
          isA<HistoricalPurchaseRequestReferenceMissingFailure>()
              .having((failure) => failure.entity, 'entity', 'items')
              .having(
                (failure) => failure.id,
                'id',
                setup.fixture.simpleItem.id,
              )
              .having((failure) => failure.prId, 'prId', setup.prId),
        ),
      );
      expect(
        await context.purchaseRequestStatusOf(setup.prId),
        'submitted',
        reason: 'Kegagalan harus mengembalikan seluruh transisi.',
      );
      expect(
        await context.purchaseRequestColumn(setup.prId, 'processing_at'),
        isNull,
      );
    });

    test('opname acuan yang hilang fisik menghentikan proses', () async {
      final setup = await submittedRequest();
      await context.corruptByDeleting('stock_opnames', setup.opnameId);

      await expectLater(
        () => context
            .markPurchaseRequestProcessing(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.warehouseUser.id,
              prId: setup.prId,
            ),
        throwsA(
          isA<HistoricalPurchaseRequestReferenceMissingFailure>()
              .having((failure) => failure.entity, 'entity', 'stock_opnames')
              .having((failure) => failure.id, 'id', setup.opnameId),
        ),
      );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'submitted');
    });

    test('baris yang hilang fisik menghentikan submit pada draft', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      await context.corruptByDeleting('items', fixture.simpleItem.id);

      // Caught while the document is still a draft, which leaves a way forward that
      // `submitted` would not have.
      await expectLater(
        () => context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: fixture.branchHead.id, prId: request.id),
        throwsA(isA<HistoricalPurchaseRequestReferenceMissingFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(request.id), 'draft');
    });

    test(
      'tidak ada baris atau tautan yang hilang diam-diam pada dokumen sehat',
      () async {
        final fixture = await buildPurchaseRequestFixture(
          context,
          now: prWednesdayUtc(),
        );
        final roomOne = await fileOpnameForRoom(
          context,
          roomId: fixture.roomOne.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );
        final roomTwo = await fileOpnameForRoom(
          context,
          roomId: fixture.roomTwo.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );
        final request = await context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [roomOne, roomTwo],
            );

        // Deactivating everything the joins touch must not reduce either set: the
        // queries filter neither `is_active` nor `deleted_at`.
        await context.deactivate('items', fixture.simpleItem.id);
        await context.deactivate('rooms', fixture.roomTwo.id);
        await context.deactivate('users', fixture.nurse.id);

        final detail = await context.requests.getDetail(request.id);
        expect(
          detail!.lines.map((line) => line.itemId).toSet(),
          (await context.requests.lineItemIds(request.id)).toSet(),
        );
        expect(
          detail.opnames.map((reference) => reference.opnameId).toSet(),
          (await context.requests.linkedOpnameIds(request.id)).toSet(),
        );
      },
    );
  });

  group('pembuatan baru tetap menuntut master aktif', () {
    test('barang nonaktif tidak dapat ditambahkan ke draft', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      await context.deactivate('items', fixture.unstockedItem.id);

      await expectLater(
        () => context.addPurchaseRequestLine.call(
          actorUserId: fixture.branchHead.id,
          prId: request.id,
          itemId: fixture.unstockedItem.id,
          requestedQty: Quantity.parse('1'),
          note: 'Butuh tambahan',
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test(
      'opname soft-deleted tidak dapat dijadikan acuan draft baru',
      () async {
        final fixture = await buildPurchaseRequestFixture(
          context,
          now: prWednesdayUtc(),
        );
        final opnameId = await fileOpnameForRoom(
          context,
          roomId: fixture.roomOne.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );
        await context.archive('stock_opnames', opnameId);

        await expectLater(
          () => context
              .createPurchaseRequest(clock: prWednesdayUtc)
              .call(
                actorUserId: fixture.branchHead.id,
                selectedOpnameIds: [opnameId],
              ),
          throwsA(
            isA<IneligibleStockOpnameFailure>().having(
              (failure) => failure.reason,
              'reason',
              StockOpnameEligibilityDenial.missing,
            ),
          ),
        );
      },
    );

    test(
      'barang nonaktif tetap terbaca pada dokumen yang sudah memintanya',
      () async {
        final setup = await submittedRequest();
        await context.deactivate('items', setup.fixture.simpleItem.id);

        // The item may no longer be *picked*, but the order that already asks for it is
        // untouched — that is the whole distinction.
        final detail = await context.requests.getDetail(setup.prId);
        final line = detail!.lines.firstWhere(
          (line) => line.itemId == setup.fixture.simpleItem.id,
        );
        expect(line.requestedQty.isPositive, isTrue);
        expect(line.itemIsHistorical, isTrue);
      },
    );
  });
}
