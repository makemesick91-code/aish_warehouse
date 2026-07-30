import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/good_receipt/domain/use_cases/post_good_receipt_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_inventory_repository.dart';
import '../helpers/test_context.dart';

/// G-G5 — *"Posting GR: hanya baris `checked` yang menambah stok Gudang Cabang.
/// Barang `rejected` masuk daftar retur ke warehouse"* (§43).
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  String balanceKey(String itemId, [String? batchId]) =>
      '$itemId|${batchId ?? ''}';

  /// A two-position shipment: one item without expiry, one batch-tracked.
  Future<String> shippedOrder() => shipDeliveryOrderFor(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [
      simpleAllocation(fixture, qty: '2.5'),
      safeBatchAllocation(fixture, qty: '4'),
    ],
  );

  Future<String> checkingReceipt() async => startGoodReceiptFor(
    context,
    fixture,
    deliveryOrderId: await shippedOrder(),
    nowUtc: nowUtc,
  );

  Future<void> check(String grId, String lineId, String qty) =>
      context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: lineId,
        receivedQty: Quantity.parse(qty),
      );

  Future<void> reject(String grId, String lineId, String reason) =>
      context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: lineId,
        reason: reason,
      );

  Future<GoodReceiptPostingResult> post(String grId) => context
      .postGoodReceipt()
      .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId);

  group('stok Gudang Cabang', () {
    test('checked penuh menambah stok sebesar yang dikirim', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      await post(grId);

      final balances = await context.balancesAt(fixture.branchStore.id);
      expect(
        balances[balanceKey(fixture.simpleItem.id)],
        Quantity.parse('2.5').milliUnits,
      );
      expect(
        balances[balanceKey(fixture.batchItem.id, fixture.safeBatch.id)],
        Quantity.parse('4').milliUnits,
      );
    });

    test('checked parsial hanya menambah yang diterima', () async {
      final grId = await checkingReceipt();
      final byItem = await goodReceiptLinesByItem(context, grId);

      await check(grId, byItem[fixture.simpleItem.id]!.id, '1.5');
      await check(grId, byItem[fixture.batchItem.id]!.id, '2.375');
      await post(grId);

      final balances = await context.balancesAt(fixture.branchStore.id);
      expect(
        balances[balanceKey(fixture.simpleItem.id)],
        Quantity.parse('1.5').milliUnits,
      );
      expect(
        balances[balanceKey(fixture.batchItem.id, fixture.safeBatch.id)],
        Quantity.parse('2.375').milliUnits,
      );
    });

    test(
      'checked nol tidak membuat movement dan tidak membuat saldo',
      () async {
        final grId = await checkingReceipt();
        final byItem = await goodReceiptLinesByItem(context, grId);

        await check(grId, byItem[fixture.simpleItem.id]!.id, '0');
        await check(grId, byItem[fixture.batchItem.id]!.id, '4');
        final result = await post(grId);

        // The ledger records changes, not confirmations (G-A1).
        expect(result.movements, hasLength(1));
        expect(await context.goodReceiptMovementCount(grId), 1);
        final balances = await context.balancesAt(fixture.branchStore.id);
        expect(
          balances.containsKey(balanceKey(fixture.simpleItem.id)),
          isFalse,
        );
      },
    );

    test('rejected tidak menambah stok cabang', () async {
      final grId = await checkingReceipt();
      final byItem = await goodReceiptLinesByItem(context, grId);

      await reject(grId, byItem[fixture.simpleItem.id]!.id, 'Rusak');
      await check(grId, byItem[fixture.batchItem.id]!.id, '4');
      await post(grId);

      final balances = await context.balancesAt(fixture.branchStore.id);
      expect(balances.containsKey(balanceKey(fixture.simpleItem.id)), isFalse);
      expect(
        balances[balanceKey(fixture.batchItem.id, fixture.safeBatch.id)],
        Quantity.parse('4').milliUnits,
      );
    });

    test(
      'campuran checked, parsial dan rejected menghasilkan saldo tepat',
      () async {
        final doId = await shipDeliveryOrderFor(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [
            simpleAllocation(fixture, qty: '2.5'),
            safeBatchAllocation(fixture, qty: '4'),
            tieAllocation(fixture, qty: '2'),
          ],
        );
        final grId = await startGoodReceiptFor(
          context,
          fixture,
          deliveryOrderId: doId,
          nowUtc: nowUtc,
        );
        final byItem = await goodReceiptLinesByItem(context, grId);

        await check(grId, byItem[fixture.simpleItem.id]!.id, '2.5');
        await check(grId, byItem[fixture.batchItem.id]!.id, '1.25');
        await reject(grId, byItem[fixture.tieItem.id]!.id, 'Salah barang');
        final result = await post(grId);

        expect(result.movements, hasLength(2));
        final balances = await context.balancesAt(fixture.branchStore.id);
        expect(balances, {
          balanceKey(fixture.simpleItem.id): Quantity.parse('2.5').milliUnits,
          balanceKey(fixture.batchItem.id, fixture.safeBatch.id):
              Quantity.parse('1.25').milliUnits,
        });
      },
    );
  });

  group('bentuk movement ledger', () {
    test(
      'movement good_receipt masuk ke Gudang Cabang tanpa lokasi asal',
      () async {
        final grId = await checkingReceipt();
        await checkEveryGoodReceiptLine(
          context,
          fixture,
          grId: grId,
          nowUtc: nowUtc,
        );
        await post(grId);

        final movements = await context.goodReceiptMovements(grId);
        expect(movements, hasLength(2));
        for (final movement in movements) {
          expect(movement['movement_type'], 'good_receipt');
          // The shipment already recorded the outbound leg; this is the arrival.
          expect(movement['from_location_id'], isNull);
          expect(movement['to_location_id'], fixture.branchStore.id);
          expect(movement['ref_doc_type'], 'GR');
          expect(movement['ref_doc_id'], grId);
          expect(movement['actor_user_id'], fixture.branchHead.id);
        }
      },
    );

    test('batch dipertahankan dan item non-expiry tanpa batch', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await post(grId);

      final movements = await context.goodReceiptMovements(grId);
      final simple = movements.firstWhere(
        (movement) => movement['item_id'] == fixture.simpleItem.id,
      );
      final batched = movements.firstWhere(
        (movement) => movement['item_id'] == fixture.batchItem.id,
      );

      expect(simple['batch_id'], isNull);
      expect(batched['batch_id'], fixture.safeBatch.id);
    });

    test('kuantitas movement adalah received_qty, bukan shipped_qty', () async {
      final grId = await checkingReceipt();
      final byItem = await goodReceiptLinesByItem(context, grId);
      await check(grId, byItem[fixture.simpleItem.id]!.id, '1.125');
      await check(grId, byItem[fixture.batchItem.id]!.id, '4');
      await post(grId);

      final movements = await context.goodReceiptMovements(grId);
      final simple = movements.firstWhere(
        (movement) => movement['item_id'] == fixture.simpleItem.id,
      );
      expect(simple['qty'], Quantity.parse('1.125').milliUnits);
    });

    test('posting tidak menyentuh saldo Warehouse', () async {
      final doId = await shippedOrder();
      // The shipment already took the stock out; a receipt must not reduce it again.
      final warehouseAfterShipping = await context.balancesAt(
        fixture.warehouse.id,
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      await post(grId);

      expect(
        await context.balancesAt(fixture.warehouse.id),
        warehouseAfterShipping,
      );
    });

    test('rejected tidak mengembalikan stok ke Warehouse', () async {
      final doId = await shippedOrder();
      final warehouseAfterShipping = await context.balancesAt(
        fixture.warehouse.id,
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final byItem = await goodReceiptLinesByItem(context, grId);
      await reject(grId, byItem[fixture.simpleItem.id]!.id, 'Rusak');
      await reject(grId, byItem[fixture.batchItem.id]!.id, 'Rusak');

      await post(grId);

      // The refused goods are physically at the branch, and nobody has counted them
      // back in. Crediting the warehouse here would invent stock it does not have —
      // the physical return is a later milestone's document.
      expect(
        await context.balancesAt(fixture.warehouse.id),
        warehouseAfterShipping,
      );
      expect(await context.goodReceiptMovementCount(grId), 0);
      // And no `return` movement was written anywhere.
      final returns = await context.database
          .customSelect(
            "SELECT COUNT(*) AS c FROM stock_movements "
            "WHERE movement_type = 'return';",
          )
          .getSingle();
      expect(returns.read<int>('c'), 0);
    });

    test('posting tidak menyentuh saldo ruangan', () async {
      final room = (await context.master.activeRooms(
        branchId: fixture.branch.id,
      )).single;
      final roomLocation = await context.master.activeRoomLocation(room.id);
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      await post(grId);

      // Distribution is what moves stock from the branch store to a room, and it is
      // not this milestone's document.
      expect(await context.balancesAt(roomLocation!.id), isEmpty);
    });
  });

  group('lokasi Gudang Cabang', () {
    test(
      'tanpa Gudang Cabang posting ditolak dan tidak ada movement',
      () async {
        final grId = await checkingReceipt();
        await checkEveryGoodReceiptLine(
          context,
          fixture,
          grId: grId,
          nowUtc: nowUtc,
        );
        await context.corruptByDeleting(
          'stock_locations',
          fixture.branchStore.id,
        );

        await expectLater(
          post(grId),
          throwsA(isA<GoodReceiptBranchStoreNotFoundFailure>()),
        );
        expect(await context.goodReceiptStatusOf(grId), 'checking');
        expect(await context.goodReceiptMovementCount(grId), 0);
      },
    );

    test('lebih dari satu Gudang Cabang ditolak, bukan ditebak', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      // Written directly: `ensureLocation` is idempotent on `(type, branch, room)` and
      // would hand back the existing store, which is precisely the state this test
      // needs to *not* be in. An administrator's back office, or a future sync
      // payload, can produce the duplicate; the app cannot.
      await context.database.customStatement(
        'INSERT INTO stock_locations (id, created_at, updated_at, sync_status, '
        'type, branch_id, name) VALUES (?, ?, ?, ?, ?, ?, ?);',
        [
          'loc-branch-store-2',
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'pending',
          StockLocationType.branchStore.dbValue,
          fixture.branch.id,
          'Gudang Cabang Kedua',
        ],
      );

      final failure = await post(
        grId,
      ).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(failure, isA<GoodReceiptBranchStoreAmbiguousFailure>());
      expect(
        (failure as GoodReceiptBranchStoreAmbiguousFailure).locationIds,
        containsAll([fixture.branchStore.id, 'loc-branch-store-2']),
      );
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test('Gudang Cabang cabang lain tidak dipakai', () async {
      // A branch with no store of its own must fail rather than borrow another's.
      final otherStore = await context.master.ensureLocation(
        type: StockLocationType.branchStore,
        name: 'Gudang Cabang Lain',
        branchId: fixture.otherBranch.id,
      );
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await context.corruptByDeleting(
        'stock_locations',
        fixture.branchStore.id,
      );

      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptBranchStoreNotFoundFailure>()),
      );
      expect(await context.balancesAt(otherStore.id), isEmpty);
    });

    test('lokasi tidak di-hard-code: perubahan nama tetap terpakai', () async {
      // Looked up by type and branch every time, so renaming the row changes nothing
      // about where the stock lands.
      await context.database.customStatement(
        'UPDATE stock_locations SET name = ? WHERE id = ?;',
        ['Gudang Cabang Uji (Baru)', fixture.branchStore.id],
      );
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      final result = await post(grId);

      expect(result.branchStore.id, fixture.branchStore.id);
      expect(result.branchStore.name, 'Gudang Cabang Uji (Baru)');
    });
  });

  group('atomisitas', () {
    /// A posting service whose ledger write fails on the second movement.
    Future<String> receiptWithFailingPosting() async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      return grId;
    }

    test('kegagalan pada satu baris membatalkan seluruh movement', () async {
      final grId = await receiptWithFailingPosting();
      // Fails on the batch-tracked position, which the posting reaches *after* the
      // non-batch one has already written its movement and raised its balance. If the
      // posting were not one unit of work, that earlier write would survive.
      final failing = FailingInventoryRepository(
        context.inventory,
        failOnItemId: fixture.batchItem.id,
      );

      await expectLater(
        context
            .postGoodReceipt(posting: context.postingWith(inventory: failing))
            .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId),
        throwsA(anything),
      );

      // Not "one movement was written": zero. A failure on the second position must
      // roll the first one's movement back, which is why they share a transaction.
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test('kegagalan membatalkan saldo cabang', () async {
      final grId = await receiptWithFailingPosting();
      // Fails on the batch-tracked position, which the posting reaches *after* the
      // non-batch one has already written its movement and raised its balance. If the
      // posting were not one unit of work, that earlier write would survive.
      final failing = FailingInventoryRepository(
        context.inventory,
        failOnItemId: fixture.batchItem.id,
      );

      await context
          .postGoodReceipt(posting: context.postingWith(inventory: failing))
          .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId)
          .then<void>((_) {}, onError: (_, _) {});

      expect(await context.balancesAt(fixture.branchStore.id), isEmpty);
    });

    test('kegagalan menjaga GR tetap checking tanpa posted_at', () async {
      final grId = await receiptWithFailingPosting();
      final failing = FailingInventoryRepository(
        context.inventory,
        failOnItemId: fixture.batchItem.id,
      );

      await context
          .postGoodReceipt(posting: context.postingWith(inventory: failing))
          .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId)
          .then<void>((_) {}, onError: (_, _) {});

      expect(await context.goodReceiptStatusOf(grId), 'checking');
      expect(await context.goodReceiptColumn(grId, 'posted_at'), isNull);
    });

    test('kegagalan menjaga Surat Jalan tetap shipped', () async {
      final doId = await shippedOrder();
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      final failing = FailingInventoryRepository(
        context.inventory,
        failOnItemId: fixture.batchItem.id,
      );

      await context
          .postGoodReceipt(posting: context.postingWith(inventory: failing))
          .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId)
          .then<void>((_) {}, onError: (_, _) {});

      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });

    test('kegagalan menjaga Purchase Request tetap seperti semula', () async {
      final grId = await receiptWithFailingPosting();
      final before = await context.purchaseRequestStatusOf(
        fixture.purchaseRequestId,
      );
      final failing = FailingInventoryRepository(
        context.inventory,
        failOnItemId: fixture.batchItem.id,
      );

      await context
          .postGoodReceipt(posting: context.postingWith(inventory: failing))
          .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId)
          .then<void>((_) {}, onError: (_, _) {});

      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        before,
      );
    });

    test('kegagalan menjaga keputusan baris tetap dapat diperbaiki', () async {
      final grId = await receiptWithFailingPosting();
      final before = await context.goodReceiptLineRows(grId);
      final failing = FailingInventoryRepository(
        context.inventory,
        failOnItemId: fixture.batchItem.id,
      );

      await context
          .postGoodReceipt(posting: context.postingWith(inventory: failing))
          .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId)
          .then<void>((_) {}, onError: (_, _) {});

      // The document is still `checking`, so the branch head can revise and try again.
      expect(await context.goodReceiptLineRows(grId), before);
      final result = await post(grId);
      expect(result.receipt.isPosted, isTrue);
    });
  });
}
