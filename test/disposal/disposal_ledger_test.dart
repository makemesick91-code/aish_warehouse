import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/disposal/domain/services/disposal_reason_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// What a posted Pemusnahan writes to the ledger (§42, G-E7/G-A1).
///
/// Every assertion here is about the shape of one `disposal` movement, and the shape
/// is what makes this document different from every other one in the application:
///
/// ```
/// movement_type    = disposal
/// from_location_id = the document's source
/// to_location_id   = NULL          ← nothing receives the stock
/// ref_doc_type     = DSP
/// ref_doc_id       = disposal.id
/// actor_user_id    = whoever posted
/// note             = non-empty     ← G-E7's catatan
/// ```
///
/// The `to_location_id IS NULL` is not an omission. A shipment writes one leg out and
/// a Good Receipt the matching leg in, because goods are in transit between them; a
/// distribution debits a store and credits a room. A disposal has **no second leg at
/// all** — which is exactly why the note and the actor are mandatory, and why the
/// tests below check that nothing anywhere else moved.
void main() {
  final nowUtc = DateTime.utc(2026, 7, 30, 4);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draftAt(
    String locationId, {
    required String actorUserId,
    String reason = 'Kedaluwarsa',
  }) => createDisposalDraft(
    context,
    fixture,
    sourceLocationId: locationId,
    nowUtc: nowUtc,
    actorUserId: actorUserId,
    reason: reason,
  );

  Future<Quantity> balanceAt(
    String locationId, {
    String? batchId,
    String? itemId,
  }) => locationBalance(
    context,
    locationId: locationId,
    itemId: itemId ?? fixture.expiryItem.id,
    batchId: batchId ?? fixture.expiredBatch.id,
  );

  group('bentuk movement', () {
    test('setiap kolom sesuai §20', () async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '2.375',
        nowUtc: nowUtc,
      );

      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      final movements = await context.disposalMovements(id);
      expect(movements, hasLength(1));
      final movement = movements.single;

      expect(movement['movement_type'], 'disposal');
      expect(movement['from_location_id'], fixture.warehouse.id);
      // The whole shape of the document, in one assertion.
      expect(movement['to_location_id'], isNull);
      expect(movement['ref_doc_type'], 'DSP');
      expect(movement['ref_doc_id'], id);
      expect(movement['actor_user_id'], fixture.warehouseUser.id);
      expect(movement['item_id'], fixture.expiryItem.id);
      expect(movement['batch_id'], fixture.expiredBatch.id);
      expect(movement['qty'], Quantity.parse('2.375').milliUnits);
      expect((movement['note'] as String?)?.trim(), isNotEmpty);
    });

    test('ref_doc_type DSP tidak bertabrakan dengan DIST', () async {
      // Sharing a value with the Distribusi would make `movementsByRef` return both
      // and the stock card unable to say which document a movement came from.
      expect(RefDocType.disposal, 'DSP');
      expect(RefDocType.disposal, isNot(RefDocType.distribution));

      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      final byRef = await context.inventory.movementsByRef(
        refDocType: RefDocType.disposal,
        refDocId: id,
      );
      expect(byRef, hasLength(1));
      expect(
        await context.inventory.movementsByRef(
          refDocType: RefDocType.distribution,
          refDocId: id,
        ),
        isEmpty,
      );
    });

    test('catatan movement memuat alasan header', () async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Pembersihan stok lama — Ditemukan saat audit bulanan',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      expect(
        (await context.disposalMovements(id)).single['note'],
        'Pembersihan stok lama — Ditemukan saat audit bulanan',
      );
    });

    test(
      'catatan baris digabung ke catatan movement secara deterministik',
      () async {
        final id = await draftAt(
          fixture.warehouse.id,
          actorUserId: fixture.warehouseUser.id,
          reason: 'Kedaluwarsa',
        );
        await addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
          qty: '1',
          nowUtc: nowUtc,
          note: 'Kemasan bocor',
        );
        await context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

        expect(
          (await context.disposalMovements(id)).single['note'],
          'Kedaluwarsa${DisposalReasonPolicy.separator}Kemasan bocor',
        );
      },
    );

    test('satu movement per baris hidup', () async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.staleBatch.id,
        qty: '0.25',
        nowUtc: nowUtc,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.otherExpiryItem.id,
        batchId: fixture.otherExpiredBatch.id,
        qty: '0.5',
        nowUtc: nowUtc,
      );

      final result = await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      expect(result.movements, hasLength(3));
      expect(await context.disposalMovementCount(id), 3);
      expect(await context.disposalLineCount(id), 3);
    });
  });

  group('efek saldo', () {
    test('saldo sumber berkurang tepat sejumlah baris', () async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '2',
        nowUtc: nowUtc,
      );

      expect(await balanceAt(fixture.warehouse.id), Quantity.parse('5.5'));
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);
      expect(await balanceAt(fixture.warehouse.id), Quantity.parse('3.5'));
    });

    test('tidak ada saldo tujuan yang dibuat', () async {
      final before = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM stock_balances;')
          .getSingle();

      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      final after = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM stock_balances;')
          .getSingle();
      // A disposal reduces one row and creates none: no quarantine bin, no write-off
      // account, nothing.
      expect(after.read<int>('c'), before.read<int>('c'));
    });

    test('lokasi lain tidak berubah', () async {
      final beforeStore = await balanceAt(fixture.branchStore.id);
      final beforeRoom = await balanceAt(fixture.locationOne.id);
      final beforeOther = await balanceAt(fixture.otherBranchStore.id);

      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      expect(await balanceAt(fixture.branchStore.id), beforeStore);
      expect(await balanceAt(fixture.locationOne.id), beforeRoom);
      expect(await balanceAt(fixture.otherBranchStore.id), beforeOther);
    });

    test('batch tetap ada setelah stoknya habis', () async {
      // A batch is master data, not a balance. Destroying the last of it empties the
      // shelf; it does not delete the row, and the posted document must still be able
      // to name it.
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.staleBatch.id,
        qty: '1.25',
        nowUtc: nowUtc,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      expect(await context.master.batchById(fixture.staleBatch.id), isNotNull);
      expect(await context.master.itemById(fixture.expiryItem.id), isNotNull);
    });

    test('dokumen milestone lain tidak tersentuh', () async {
      final before = await context.database
          .customSelect(
            "SELECT (SELECT COUNT(*) FROM stock_movements "
            "WHERE movement_type <> 'disposal') AS others;",
          )
          .getSingle();

      final id = await draftAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);

      final after = await context.database
          .customSelect(
            "SELECT (SELECT COUNT(*) FROM stock_movements "
            "WHERE movement_type <> 'disposal') AS others;",
          )
          .getSingle();
      expect(after.read<int>('others'), before.read<int>('others'));
    });
  });

  group('append-only (G-A1)', () {
    test('movement asal tidak diubah oleh apa pun setelahnya', () async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final result = await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);
      final original = result.movements.single;

      // A second, unrelated disposal of the same batch.
      final second = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: second,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: second);

      final reread = await context.inventory.movementById(original.id);
      expect(reread!.qty, original.qty);
      expect(reread.note, original.note);
      expect(reread.refDocId, id);
    });

    test('pembalikan menjadi movement baru, dokumen tetap posted', () async {
      // Reversal is the ledger's own workflow (G-A1) and this milestone builds no UI
      // for it. What matters is the shape when it *is* used: the original stays, the
      // document stays posted, and the correction is a new row.
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final result = await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      final reversal = await context.posting.postReversal(
        movementId: result.movements.single.id,
        actorUserId: fixture.warehouseUser.id,
        note: 'Salah batch',
      );

      expect(reversal.movementType, StockMovementType.reversal);
      expect(reversal.reversalOfMovementId, result.movements.single.id);
      // The disposal's outbound leg reversed puts the stock back.
      expect(await balanceAt(fixture.warehouse.id), Quantity.parse('5.5'));
      // And the document is untouched: it still says what it said.
      expect(await context.disposalStatusOf(id), 'posted');
      expect(await context.disposalMovementCount(id), 2);
    });
  });

  group('audit', () {
    test('posted_at dan posted_by terisi aktor yang memposting', () async {
      final id = await draftAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);

      expect(
        await context.disposalColumn(id, 'posted_by'),
        fixture.branchHead.id,
      );
      expect(
        await context.disposalColumn(id, 'created_by'),
        fixture.branchHead.id,
      );
      final postedAt = await context.disposalColumn(id, 'posted_at');
      expect(postedAt, isNotNull);
      // Stored as a UTC instant (T-1), never as an operational wall clock.
      expect(postedAt, endsWith('Z'));
    });

    test('nomor dokumen sementara berbentuk TMP-DSP', () async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      expect(
        (await context.disposals.getById(id))!.docNumber,
        startsWith('TMP-DSP-'),
      );
    });

    test('sync_status kembali pending setelah posting', () async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      expect(await context.disposalColumn(id, 'sync_status'), 'pending');
    });
  });
}
