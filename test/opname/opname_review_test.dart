import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/inventory/domain/services/stock_posting_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_inventory_repository.dart';
import '../helpers/test_context.dart';

/// G-O5 — reviewing a Stok Opname aligns the room's stock with the count.
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  DateTime now = fixedWednesdayUtc();
  DateTime clock() => now;

  setUp(() async {
    now = fixedWednesdayUtc();
    context = TestContext.create(clock: clock);
    fixture = await buildOpnameFixture(context, now: now);
  });

  tearDown(() => context.dispose());

  /// Creates a document, applies [counts] by item/batch key, and submits it.
  Future<String> submittedOpname(
    Map<String, ({String qty, String? note})> counts,
  ) async {
    final opname = await context.createOpname().call(
      actorUserId: fixture.nurse.id,
      roomId: fixture.room.id,
    );
    final detail = await context.opnames.getDetail(opname.id);

    for (final line in detail!.lines) {
      final key = '${line.itemId}|${line.batchId ?? ''}';
      final count = counts[key];
      if (count == null) continue;
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: line.id,
        countedQty: Quantity.parse(count.qty),
        note: count.note,
      );
    }

    await context.submitOpname().call(
      actorUserId: fixture.nurse.id,
      opnameId: opname.id,
    );
    return opname.id;
  }

  String simpleKey() => '${fixture.simpleItem.id}|';

  String validBatchKey() => '${fixture.expiryItem.id}|${fixture.validBatch.id}';

  String expiredBatchKey() =>
      '${fixture.expiryItem.id}|${fixture.expiredBatch.id}';

  Future<Quantity> roomBalance({String? itemId, String? batchId}) =>
      context.inventory.balanceQty(
        locationId: fixture.roomLocation.id,
        itemId: itemId ?? fixture.simpleItem.id,
        batchId: batchId,
      );

  group('posting penyesuaian', () {
    test('selisih negatif mengurangi saldo ruangan', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '8', note: 'Dua box terpakai'),
      });

      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      expect(await roomBalance(), Quantity.parse('8'));
    });

    test('selisih positif menambah saldo ruangan', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '12.5', note: 'Ada kiriman belum tercatat'),
      });

      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      expect(await roomBalance(), Quantity.parse('12.5'));
    });

    test('selisih nol tidak membuat movement', () async {
      final opnameId = await submittedOpname(const {});

      final result = await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      expect(result.postedMovementCount, 0);
      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.stockOpname,
        refDocId: opnameId,
      );
      expect(movements, isEmpty);
    });

    test('saldo akhir setiap baris sama persis dengan hasil hitung', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '0.5', note: 'Tersisa setengah'),
        validBatchKey(): (qty: '3.125', note: 'Lebih dari catatan'),
        expiredBatchKey(): (qty: '0.25', note: 'Sisa kedaluwarsa'),
      });

      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      expect(await roomBalance(), Quantity.parse('0.5'));
      expect(
        await roomBalance(
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        ),
        Quantity.parse('3.125'),
      );
      expect(
        await roomBalance(
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('0.25'),
      );
    });

    test('movement memakai tipe, referensi dan aktor yang benar', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '8', note: 'Dua box terpakai'),
      });

      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.stockOpname,
        refDocId: opnameId,
      );
      expect(movements, hasLength(1));

      final movement = movements.single;
      expect(movement.movementType, StockMovementType.opnameAdjustment);
      expect(movement.refDocType, 'SO');
      expect(movement.refDocId, opnameId);
      // The reviewer is the actor: they are the one who authorised the change.
      expect(movement.actorUserId, fixture.branchHead.id);
      expect(movement.qty, Quantity.parse('2.5'));
      expect(movement.fromLocationId, fixture.roomLocation.id);
      expect(movement.toLocationId, isNull);
      expect(movement.note, contains('Dua box terpakai'));
    });

    test('batch dipertahankan pada movement', () async {
      final opnameId = await submittedOpname({
        validBatchKey(): (qty: '1', note: 'Berkurang'),
      });

      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.stockOpname,
        refDocId: opnameId,
      );
      expect(movements.single.batchId, fixture.validBatch.id);
    });

    test('batch kedaluwarsa tetap dapat disesuaikan lewat opname', () async {
      // Expired stock is blocked from transfers (G-E4) but must remain
      // countable and adjustable — that is how it is discovered before being
      // disposed of (G-E7).
      final opnameId = await submittedOpname({
        expiredBatchKey(): (qty: '0.25', note: 'Sisa batch kedaluwarsa'),
      });

      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      expect(
        await roomBalance(
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('0.25'),
      );
    });

    test(
      'penyesuaian dihitung terhadap saldo terkini, bukan snapshot',
      () async {
        final opnameId = await submittedOpname({
          simpleKey(): (qty: '10', note: 'Setengah box terpakai'),
        });

        // Stock moves between submitting and reviewing: 10.5 → 6.5. The counted
        // quantity is still 10, so the review must add 3.5, not subtract 0.5.
        await context.posting.postDisposal(
          locationId: fixture.roomLocation.id,
          itemId: fixture.simpleItem.id,
          qty: Quantity.parse('4'),
          actorUserId: fixture.warehouseUser.id,
          note: 'Pemusnahan di tengah proses',
        );
        expect(await roomBalance(), Quantity.parse('6.5'));

        await context.reviewOpname().call(
          actorUserId: fixture.branchHead.id,
          opnameId: opnameId,
        );

        expect(await roomBalance(), Quantity.parse('10'));

        final movements = await context.inventory.movementsByRef(
          refDocType: RefDocType.stockOpname,
          refDocId: opnameId,
        );
        expect(movements.single.qty, Quantity.parse('3.5'));
        expect(movements.single.toLocationId, fixture.roomLocation.id);
      },
    );

    test('dokumen menjadi reviewed dengan reviewer dan waktu UTC', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '8', note: 'Terpakai'),
      });

      now = fixedWednesdayUtc().add(const Duration(hours: 5));
      final result = await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      expect(result.opname.status, StockOpnameStatus.reviewed);
      expect(result.opname.reviewedBy, fixture.branchHead.id);
      expect(result.opname.reviewedAt, now);
      expect(result.opname.reviewedAt!.isUtc, isTrue);
      expect(result.opname.syncStatus, SyncStatus.pending);
    });
  });

  group('atomisitas', () {
    test('kegagalan satu baris membatalkan seluruh movement', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '8', note: 'Terpakai'),
        validBatchKey(): (qty: '1', note: 'Berkurang'),
        expiredBatchKey(): (qty: '0.25', note: 'Sisa'),
      });

      // Lines are posted in item-name order, so failing on "Masker Bedah"
      // guarantees the two "Anestesi Lokal" batches have already written
      // movements and balances by the time the failure lands. That is what
      // makes this a rollback test rather than a "nothing happened" test.
      final failing = FailingInventoryRepository(
        context.inventory,
        failOnItemId: fixture.simpleItem.id,
      );
      final posting = StockPostingService(
        inventory: failing,
        master: context.master,
        clock: clock,
      );

      await expectLater(
        context
            .reviewOpname(posting: posting)
            .call(actorUserId: fixture.branchHead.id, opnameId: opnameId),
        throwsA(isA<ValidationFailure>()),
      );

      expect(failing.appendedBeforeFailure, 2);

      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.stockOpname,
        refDocId: opnameId,
      );
      expect(movements, isEmpty);
    });

    test('kegagalan satu baris membatalkan seluruh perubahan saldo', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '8', note: 'Terpakai'),
        validBatchKey(): (qty: '1', note: 'Berkurang'),
      });

      final posting = StockPostingService(
        inventory: FailingInventoryRepository(
          context.inventory,
          failOnItemId: fixture.expiryItem.id,
        ),
        master: context.master,
        clock: clock,
      );

      await expectLater(
        context
            .reviewOpname(posting: posting)
            .call(actorUserId: fixture.branchHead.id, opnameId: opnameId),
        throwsA(isA<ValidationFailure>()),
      );

      expect(await roomBalance(), Quantity.parse('10.5'));
      expect(
        await roomBalance(
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        ),
        Quantity.parse('2.375'),
      );
    });

    test('kegagalan mempertahankan status submitted', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '8', note: 'Terpakai'),
        validBatchKey(): (qty: '1', note: 'Berkurang'),
      });

      final posting = StockPostingService(
        inventory: FailingInventoryRepository(
          context.inventory,
          failOnItemId: fixture.expiryItem.id,
        ),
        master: context.master,
        clock: clock,
      );

      await expectLater(
        context
            .reviewOpname(posting: posting)
            .call(actorUserId: fixture.branchHead.id, opnameId: opnameId),
        throwsA(isA<ValidationFailure>()),
      );

      final opname = await context.opnames.getById(opnameId);
      expect(opname!.status, StockOpnameStatus.submitted);
      expect(opname.reviewedAt, isNull);
      expect(opname.reviewedBy, isNull);
    });

    test(
      'dokumen tetap dapat direview setelah penyebab kegagalan hilang',
      () async {
        final opnameId = await submittedOpname({
          simpleKey(): (qty: '8', note: 'Terpakai'),
        });

        final posting = StockPostingService(
          inventory: FailingInventoryRepository(
            context.inventory,
            failOnItemId: fixture.simpleItem.id,
          ),
          master: context.master,
          clock: clock,
        );
        await expectLater(
          context
              .reviewOpname(posting: posting)
              .call(actorUserId: fixture.branchHead.id, opnameId: opnameId),
          throwsA(isA<ValidationFailure>()),
        );

        // Retrying with a healthy service must succeed — the rollback left the
        // document in a reviewable state, not a broken one.
        final result = await context.reviewOpname().call(
          actorUserId: fixture.branchHead.id,
          opnameId: opnameId,
        );
        expect(result.opname.status, StockOpnameStatus.reviewed);
        expect(await roomBalance(), Quantity.parse('8'));
      },
    );

    test('seluruh baris diposting dalam satu transaksi', () async {
      final opnameId = await submittedOpname({
        simpleKey(): (qty: '8', note: 'Terpakai'),
        validBatchKey(): (qty: '3', note: 'Bertambah'),
        expiredBatchKey(): (qty: '0.25', note: 'Sisa'),
      });

      final result = await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opnameId,
      );

      expect(result.adjustments, hasLength(3));
      expect(result.postedMovementCount, 3);

      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.stockOpname,
        refDocId: opnameId,
      );
      expect(movements, hasLength(3));
    });
  });

  group('finalitas', () {
    late String reviewedId;

    setUp(() async {
      reviewedId = await submittedOpname({
        simpleKey(): (qty: '8', note: 'Terpakai'),
      });
      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: reviewedId,
      );
    });

    test('review kedua ditolak', () async {
      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.branchHead.id,
          opnameId: reviewedId,
        ),
        throwsA(isA<InvalidStockOpnameStateFailure>()),
      );
    });

    test('review kedua tidak menambah movement', () async {
      try {
        await context.reviewOpname().call(
          actorUserId: fixture.branchHead.id,
          opnameId: reviewedId,
        );
      } on InvalidStockOpnameStateFailure {
        // expected
      }

      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.stockOpname,
        refDocId: reviewedId,
      );
      expect(movements, hasLength(1));
      expect(await roomBalance(), Quantity.parse('8'));
    });

    test('baris dokumen final tidak dapat diubah', () async {
      final detail = await context.opnames.getDetail(reviewedId);
      final line = detail!.lines.first;

      await expectLater(
        context.updateOpnameLine(
          actorUserId: fixture.nurse.id,
          lineId: line.id,
          countedQty: Quantity.parse('99'),
          note: 'Percobaan ubah',
        ),
        throwsA(isA<InvalidStockOpnameStateFailure>()),
      );

      final unchanged = await context.opnames.lineById(line.id);
      expect(unchanged!.countedQty, line.countedQty);
    });

    test('baris tidak dapat ditambahkan ke dokumen final', () async {
      await expectLater(
        context.addOpnameLine(
          actorUserId: fixture.nurse.id,
          opnameId: reviewedId,
          itemId: fixture.simpleItem.id,
          countedQty: Quantity.parse('1'),
        ),
        throwsA(isA<InvalidStockOpnameStateFailure>()),
      );
    });

    test('dokumen final tidak dapat dihapus lewat workflow', () async {
      final removed = await context.opnames.removeDraft(reviewedId);
      expect(removed, isFalse);

      final opname = await context.opnames.getById(reviewedId);
      expect(opname, isNotNull);
      expect(opname!.status, StockOpnameStatus.reviewed);
    });

    test('baris dokumen final tidak dapat dihapus', () async {
      final detail = await context.opnames.getDetail(reviewedId);
      final removed = await context.opnames.removeDraftLine(
        detail!.lines.first.id,
      );
      expect(removed, isFalse);

      final still = await context.opnames.getDetail(reviewedId);
      expect(still!.lines, hasLength(detail.lines.length));
    });
  });
}
