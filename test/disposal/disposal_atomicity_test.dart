import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_inventory_repository.dart';
import '../helpers/test_context.dart';

/// All lines commit, or none does (§43, §21).
///
/// Every other posting in this application has a counter-entry: a shipment's outbound
/// leg is matched by a receipt's inbound one, a distribution debits a store and
/// credits a room. A `disposal` movement has **none** — stock leaves and nothing
/// gains it — so a partially committed disposal would be quantities that simply
/// vanished, with nothing in the ledger to reconcile them against. The transaction
/// boundary is the only thing standing between that and the database.
///
/// Each test forces a failure at a different point and then asserts the same five
/// things, which together are what "rolled back" actually means:
///
/// ```
/// 0 movements under this document          (and 0 disposal movements anywhere)
/// every source balance unchanged
/// status still 'draft'
/// posted_at and posted_by still NULL
/// every line still there, so the user can fix what was wrong
/// ```
void main() {
  final nowUtc = DateTime.utc(2026, 7, 30, 4);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A three-position warehouse draft: two batches of one item and one of another,
  /// so a failure can be landed on the first, the middle or the last.
  Future<String> threeLineDraft() async {
    final id = await createDisposalDraft(
      context,
      fixture,
      sourceLocationId: fixture.warehouse.id,
      nowUtc: nowUtc,
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
    return id;
  }

  /// The five assertions that together mean "nothing happened".
  Future<void> expectFullyRolledBack(
    String disposalId, {
    required int lineCount,
    required Map<String, Quantity> balances,
  }) async {
    expect(
      await context.disposalMovementCount(disposalId),
      0,
      reason: 'Ada movement yang tertinggal setelah rollback.',
    );
    expect(
      await context.movementCountOfType(StockMovementType.disposal),
      0,
      reason: 'Ada movement disposal di luar dokumen ini.',
    );
    expect(await context.disposalStatusOf(disposalId), 'draft');
    expect(await context.disposalColumn(disposalId, 'posted_at'), isNull);
    expect(await context.disposalColumn(disposalId, 'posted_by'), isNull);
    expect(await context.disposalLineCount(disposalId), lineCount);

    for (final entry in balances.entries) {
      final parts = entry.key.split('|');
      expect(
        await locationBalance(
          context,
          locationId: fixture.warehouse.id,
          itemId: parts[0],
          batchId: parts[1],
        ),
        entry.value,
        reason: 'Saldo ${entry.key} berubah meski posting gagal.',
      );
    }
  }

  /// The three warehouse positions the fixture opens with — what "unchanged" means.
  Map<String, Quantity> openingBalances() => {
    '${fixture.expiryItem.id}|${fixture.expiredBatch.id}': Quantity.parse(
      '5.5',
    ),
    '${fixture.expiryItem.id}|${fixture.staleBatch.id}': Quantity.parse('1.25'),
    '${fixture.otherExpiryItem.id}|${fixture.otherExpiredBatch.id}':
        Quantity.parse('2'),
  };

  group('kegagalan ledger', () {
    for (final scenario in const [
      ('baris pertama', 0),
      ('baris tengah', 1),
      ('baris terakhir', 2),
    ]) {
      test('kegagalan pada ${scenario.$1} membatalkan seluruh dokumen', () async {
        final id = await threeLineDraft();
        final failing = FailingInventoryRepository(
          context.inventory,
          failAfterAppends: scenario.$2,
        );

        await expectLater(
          context
              .postDisposal(
                clock: () => nowUtc,
                posting: context.postingWith(
                  inventory: failing,
                  clock: () => nowUtc,
                ),
              )
              .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
          throwsA(isA<ValidationFailure>()),
        );

        // The failure really did land where the test intended: earlier movements
        // *were* written inside the transaction and then rolled back.
        expect(failing.appendedBeforeFailure, scenario.$2);
        await expectFullyRolledBack(
          id,
          lineCount: 3,
          balances: openingBalances(),
        );
      });
    }
  });

  group('kegagalan validasi', () {
    test('barang yang hilang membatalkan dokumen', () async {
      // The joined detail inner-joins `items`, so a physically missing row makes the
      // read one line shorter — and §23's set-integrity check is what notices, before
      // the per-line reference check ever runs. That ordering is the point: the
      // *silent shrinking* is the dangerous failure, because every per-line check
      // would still pass on the two lines that survived.
      final id = await threeLineDraft();
      await context.corruptByDeleting('items', fixture.otherExpiryItem.id);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<DisposalLineIntegrityFailure>()),
      );
      await expectFullyRolledBack(
        id,
        lineCount: 3,
        balances: openingBalances(),
      );
    });

    test('batch yang hilang membatalkan dokumen', () async {
      // Same shape as the item case: `disposal_lines.batch_id` is NOT NULL and the
      // detail inner-joins `item_batches`, so a missing batch drops the line from the
      // joined read and the set comparison refuses the document.
      final id = await threeLineDraft();
      await context.corruptByDeleting('item_batches', fixture.staleBatch.id);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<DisposalLineIntegrityFailure>()),
      );
      await expectFullyRolledBack(
        id,
        lineCount: 3,
        balances: openingBalances(),
      );
    });

    test('lokasi sumber yang hilang membatalkan dokumen', () async {
      // Explicit failure, never a substitution: posting against a replacement shelf
      // would reduce a balance nobody chose (§15/§34). The document itself becomes
      // unreadable — its summary inner-joins the location — which is the honest
      // answer for a row whose source no longer exists at all.
      //
      // An *archived* source is a different case entirely and is deliberately still
      // postable; `disposal_recovery_test` covers it.
      final id = await threeLineDraft();
      await context.corruptByDeleting('stock_locations', fixture.warehouse.id);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<AppFailure>()),
      );
      expect(await context.disposalStatusOf(id), 'draft');
      expect(await context.disposalMovementCount(id), 0);
      expect(await context.movementCountOfType(StockMovementType.disposal), 0);
      expect(await context.disposalLineCount(id), 3);
    });

    test('batch yang tidak lagi kedaluwarsa membatalkan dokumen', () async {
      // The clock is wound back to before the batches expired, which is what a device
      // whose clock went backwards looks like.
      final id = await threeLineDraft();
      final earlier = nowUtc.subtract(const Duration(days: 60));

      await expectLater(
        context
            .postDisposal(clock: () => earlier)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<BatchNotExpiredForDisposalFailure>()),
      );
      await expectFullyRolledBack(
        id,
        lineCount: 3,
        balances: openingBalances(),
      );
    });

    test('saldo yang berubah membatalkan dokumen', () async {
      final id = await threeLineDraft();
      await context.posting.postOpnameAdjustment(
        locationId: fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        countedQty: Quantity.parse('0.5'),
        actorUserId: fixture.warehouseUser.id,
        note: 'Koreksi hitung fisik',
      );

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<InsufficientDisposalStockFailure>()),
      );

      expect(await context.disposalMovementCount(id), 0);
      expect(await context.movementCountOfType(StockMovementType.disposal), 0);
      expect(await context.disposalStatusOf(id), 'draft');
      expect(await context.disposalLineCount(id), 3);
      // The adjustment stands; the disposal changed nothing on top of it.
      expect(
        await locationBalance(
          context,
          locationId: fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('0.5'),
      );
    });

    test('alasan yang dikosongkan membatalkan posting', () async {
      final id = await threeLineDraft();
      await context.updateDisposalHeader.call(
        actorUserId: fixture.warehouseUser.id,
        disposalId: id,
        reason: null,
      );

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<DisposalReasonRequiredFailure>()),
      );
      await expectFullyRolledBack(
        id,
        lineCount: 3,
        balances: openingBalances(),
      );
    });

    test('alasan yang hanya berisi whitespace ditolak domain', () async {
      // `String.trim()` strips tabs and newlines; SQLite's `trim()` strips spaces
      // only. A reason of "\n\t" therefore satisfies the CHECK and is refused here —
      // the domain is the authority, the CHECK is the floor (§19).
      final id = await threeLineDraft();
      await context.updateDisposalHeader.call(
        actorUserId: fixture.warehouseUser.id,
        disposalId: id,
        reason: '\n\t  ',
      );
      // Normalised to NULL on the way in rather than stored as blank.
      expect(await context.disposalColumn(id, 'reason'), isNull);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<DisposalReasonRequiredFailure>()),
      );
      await expectFullyRolledBack(
        id,
        lineCount: 3,
        balances: openingBalances(),
      );
    });

    test('dokumen kosong ditolak', () async {
      final id = await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
        reason: 'Kedaluwarsa',
      );

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<DisposalLineRequiredFailure>()),
      );
      expect(await context.disposalStatusOf(id), 'draft');
      expect(await context.movementCountOfType(StockMovementType.disposal), 0);
    });

    test('timestamp perangkat yang mundur ditolak', () async {
      // §36: `posted_at` may not land before `created_at`. Compared on UTC instants,
      // never as text.
      final id = await threeLineDraft();
      final behind = nowUtc.subtract(const Duration(microseconds: 1));

      await expectLater(
        context
            .postDisposal(clock: () => behind)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );
      await expectFullyRolledBack(
        id,
        lineCount: 3,
        balances: openingBalances(),
      );
    });

    test('timestamp yang sama persis diterima', () async {
      // Two events really can land on the same microsecond on a fast device.
      final id = await threeLineDraft();
      final result = await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);
      expect(result.disposal.isPosted, isTrue);
    });
  });

  group('integritas himpunan baris (§23)', () {
    test('baris yang hilang dari joined read membatalkan posting', () async {
      // An inner join on an item row that is physically gone makes the detail one
      // line shorter, silently. Posting on that basis would destroy less stock than
      // the document says it did, and every per-line check would still pass.
      final id = await threeLineDraft();

      // Break the join without breaking the plain select: the line still names the
      // item, but the item row is gone.
      await context.corruptByDeleting('items', fixture.otherExpiryItem.id);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<AppFailure>()),
      );

      // Whichever guard fired first, the outcome is the same: nothing moved and the
      // document still holds all three lines.
      expect(await context.disposalLineCount(id), 3);
      expect(await context.movementCountOfType(StockMovementType.disposal), 0);
    });

    test('guarded update menolak dokumen yang tidak lagi draft', () async {
      // The last line of defence: the `markPosted` statement carries
      // `status = 'draft'`, so a second device that posted in between yields zero
      // rows and the movements written above it roll back.
      final id = await threeLineDraft();
      final disposal = await context.disposals.getById(id);

      // Simulate the other device by flipping the status underneath.
      await context.database.customStatement(
        "UPDATE disposals SET status = 'posted', posted_at = ?, posted_by = ? "
        'WHERE id = ?;',
        [DateOnly.formatIso(nowUtc), fixture.warehouseUser.id, disposal!.id],
      );

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<DisposalAlreadyPostedFailure>()),
      );
      expect(await context.movementCountOfType(StockMovementType.disposal), 0);
    });
  });

  group('rollback tidak menyentuh apa pun di luar dokumen', () {
    test('total movement seluruh database tidak berubah', () async {
      final id = await threeLineDraft();
      final before = await context.totalMovementCount();

      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 2,
      );
      await expectLater(
        context
            .postDisposal(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(await context.totalMovementCount(), before);
    });

    test('saldo lokasi lain tidak berubah saat posting cabang gagal', () async {
      final id = await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.branchStore.id,
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
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
        actorUserId: fixture.branchHead.id,
      );

      final warehouseBefore = await locationBalance(
        context,
        locationId: fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
      );
      final roomBefore = await locationBalance(
        context,
        locationId: fixture.locationOne.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
      );

      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 0,
      );
      await expectLater(
        context
            .postDisposal(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.branchHead.id, disposalId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(
        await locationBalance(
          context,
          locationId: fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        warehouseBefore,
      );
      expect(
        await locationBalance(
          context,
          locationId: fixture.locationOne.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        roomBefore,
      );
      expect(
        await locationBalance(
          context,
          locationId: fixture.branchStore.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('4'),
      );
    });

    test('dokumen lain tidak berubah statusnya', () async {
      final other = await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
        reason: 'Kedaluwarsa',
      );
      final id = await threeLineDraft();

      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 1,
      );
      await expectLater(
        context
            .postDisposal(
              clock: () => nowUtc,
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(await context.disposalStatusOf(other), 'draft');
      final rows = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM disposals;',
            variables: const <Variable<Object>>[],
          )
          .getSingle();
      expect(rows.read<int>('c'), 2);
    });
  });
}
