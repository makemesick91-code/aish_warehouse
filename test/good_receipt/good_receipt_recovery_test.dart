import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Historical recovery (§34).
///
/// A Good Receipt completes work that already exists: the goods have shipped and are
/// physically on the branch's counter. It must therefore stay readable *and postable*
/// after an administrator tidies master data away — a receipt that became unpostable
/// because somebody deactivated an item would strand real stock with no way to record
/// it.
///
/// The line the tests draw is between **deactivated or archived** (the row is there, and
/// history is exactly what it is) and **physically gone** (the reference is broken, and
/// nothing may be invented, substituted or guessed to paper over it).
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> shippedOrder() => shipDeliveryOrderFor(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [
      simpleAllocation(fixture, qty: '2.5'),
      safeBatchAllocation(fixture, qty: '4'),
    ],
  );

  /// A receipt with every position accepted, ready to post.
  Future<String> readyReceipt() async {
    final grId = await startGoodReceiptFor(
      context,
      fixture,
      deliveryOrderId: await shippedOrder(),
      nowUtc: nowUtc,
    );
    await checkEveryGoodReceiptLine(
      context,
      fixture,
      grId: grId,
      nowUtc: nowUtc,
    );
    return grId;
  }

  Future<void> post(String grId) => context.postGoodReceipt().call(
    actorUserId: fixture.branchHead.id,
    goodReceiptId: grId,
  );

  group('master nonaktif tetap dapat diposting', () {
    test('cabang nonaktif tidak menghalangi posting', () async {
      final grId = await readyReceipt();
      await context.deactivate('branches', fixture.branch.id);

      await post(grId);

      expect(await context.goodReceiptStatusOf(grId), 'posted');
      expect(await context.goodReceiptMovementCount(grId), 2);
    });

    test('barang nonaktif tidak menghalangi posting', () async {
      final grId = await readyReceipt();
      await context.deactivate('items', fixture.simpleItem.id);

      await post(grId);

      final detail = await context.receipts.getDetail(grId);
      expect(
        detail!.lines
            .firstWhere((line) => line.itemId == fixture.simpleItem.id)
            .itemIsHistorical,
        isTrue,
      );
      expect(await context.goodReceiptStatusOf(grId), 'posted');
    });

    test('kategori nonaktif tidak menghalangi posting', () async {
      final grId = await readyReceipt();
      final categoryId = fixture.simpleItem.categoryId;
      await context.database.customStatement(
        'UPDATE item_categories SET deleted_at = ? WHERE id = ?;',
        [nowUtc.toIso8601String(), categoryId],
      );

      await post(grId);

      expect(await context.goodReceiptStatusOf(grId), 'posted');
    });

    test('batch diarsipkan tidak menghalangi posting', () async {
      final grId = await readyReceipt();
      await context.archive('item_batches', fixture.safeBatch.id);

      await post(grId);

      final movements = await context.goodReceiptMovements(grId);
      // The archived batch is still the batch the goods carry, so the movement names it.
      expect(
        movements.map((movement) => movement['batch_id']),
        contains(fixture.safeBatch.id),
      );
    });

    test('petugas pengirim nonaktif tidak menghalangi posting', () async {
      final grId = await readyReceipt();
      await context.deactivate('users', fixture.warehouseUser.id);

      await post(grId);

      expect(await context.goodReceiptStatusOf(grId), 'posted');
    });

    test('pemohon PR nonaktif tidak menghalangi posting', () async {
      final grId = await readyReceipt();
      // The branch head who raised the request is the same account receiving here, so a
      // second head stands in for "the requester left".
      final requester = await context.master.ensureUser(
        email: 'kacab-lama@test.local',
        fullName: 'Kepala Cabang Lama',
        role: UserRole.kepalaCabang,
        branchId: fixture.branch.id,
      );
      await context.database.customStatement(
        'UPDATE purchase_requests SET requested_by = ? WHERE id = ?;',
        [requester.id, fixture.purchaseRequestId],
      );
      await context.deactivate('users', requester.id);

      await post(grId);

      expect(await context.goodReceiptStatusOf(grId), 'posted');
    });

    test('Gudang Cabang diarsipkan tetap dipakai apa adanya', () async {
      final grId = await readyReceipt();
      // Archived after the receipt was raised. The exact row is used — never another
      // branch's store, and never a guess.
      await context.archive('stock_locations', fixture.branchStore.id);

      final result = await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );

      expect(result.branchStore.id, fixture.branchStore.id);
      expect(result.branchStore.isArchived, isTrue);
      final balances = await context.balancesAt(fixture.branchStore.id);
      expect(balances, hasLength(2));
    });

    test('Gudang Cabang hidup menang atas yang diarsipkan', () async {
      // A store archived and re-created has two rows, and the balances a posting must
      // credit are the ones on the live location.
      await context.archive('stock_locations', fixture.branchStore.id);
      await context.database.customStatement(
        'INSERT INTO stock_locations (id, created_at, updated_at, sync_status, '
        'type, branch_id, name) VALUES (?, ?, ?, ?, ?, ?, ?);',
        [
          'loc-branch-store-new',
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'pending',
          StockLocationType.branchStore.dbValue,
          fixture.branch.id,
          'Gudang Cabang Uji (Baru)',
        ],
      );
      final grId = await readyReceipt();

      final result = await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );

      expect(result.branchStore.id, 'loc-branch-store-new');
      expect(await context.balancesAt(fixture.branchStore.id), isEmpty);
      expect(await context.balancesAt('loc-branch-store-new'), hasLength(2));
    });

    test('aktor tetap harus aktif meski dokumennya historis', () async {
      final grId = await readyReceipt();
      await context.deactivate('branches', fixture.branch.id);
      // Unlike the branch or item data the receipt points at, the person accepting goods
      // right now has to be a currently valid account (§7.2).
      await context.deactivate('users', fixture.branchHead.id);

      await expectLater(post(grId), throwsA(isA<InactiveEntityFailure>()));
      expect(await context.goodReceiptStatusOf(grId), 'checking');
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test('aktor harus tetap milik cabang tujuan', () async {
      final grId = await readyReceipt();
      await context.database.customStatement(
        'UPDATE users SET branch_id = ? WHERE id = ?;',
        [fixture.otherBranch.id, fixture.branchHead.id],
      );

      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptBranchMismatchFailure>()),
      );
      expect(await context.goodReceiptMovementCount(grId), 0);
    });
  });

  group('referensi hilang gagal eksplisit', () {
    test(
      'barang yang hilang secara fisik gagal dan tidak menulis apa pun',
      () async {
        final grId = await readyReceipt();
        await context.corruptByDeleting('items', fixture.simpleItem.id);

        await expectLater(
          post(grId),
          throwsA(isA<GoodReceiptHistoricalReferenceMissingFailure>()),
        );
        expect(await context.goodReceiptStatusOf(grId), 'checking');
        expect(await context.goodReceiptMovementCount(grId), 0);
        expect(await context.balancesAt(fixture.branchStore.id), isEmpty);
      },
    );

    test('batch yang hilang secara fisik gagal eksplisit', () async {
      final grId = await readyReceipt();
      await context.corruptByDeleting('item_batches', fixture.safeBatch.id);

      final failure = await post(
        grId,
      ).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(failure, isA<GoodReceiptHistoricalReferenceMissingFailure>());
      expect(
        (failure as GoodReceiptHistoricalReferenceMissingFailure).entity,
        'item_batches',
      );
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test('Surat Jalan yang hilang gagal eksplisit', () async {
      final grId = await readyReceipt();
      final receipt = await context.receipts.getById(grId);
      await context.corruptByDeleting('delivery_orders', receipt!.doId);

      final failure = await post(
        grId,
      ).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(failure, isA<GoodReceiptHistoricalReferenceMissingFailure>());
      expect(
        (failure as GoodReceiptHistoricalReferenceMissingFailure).entity,
        'delivery_orders',
      );
    });

    test('Purchase Request yang hilang gagal eksplisit', () async {
      final grId = await readyReceipt();
      await context.corruptByDeleting(
        'purchase_requests',
        fixture.purchaseRequestId,
      );

      final failure = await post(
        grId,
      ).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(failure, isA<GoodReceiptHistoricalReferenceMissingFailure>());
      expect(
        (failure as GoodReceiptHistoricalReferenceMissingFailure).entity,
        'purchase_requests',
      );
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test(
      'Gudang Cabang yang hilang gagal eksplisit tanpa menebak lokasi',
      () async {
        final grId = await readyReceipt();
        // A second branch's store exists and must never be borrowed.
        final otherStore = await context.master.ensureLocation(
          type: StockLocationType.branchStore,
          name: 'Gudang Cabang Lain',
          branchId: fixture.otherBranch.id,
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
      },
    );

    test('baris Surat Jalan yang hilang terdeteksi sebagai integritas', () async {
      final grId = await readyReceipt();
      final receipt = await context.receipts.getById(grId);
      final allocation = (await context.deliveries.lineReferences(
        receipt!.doId,
      )).first;

      // The receipt still has its snapshot; the shipment no longer has the allocation it
      // answers. Posting on that basis would credit stock no document accounts for.
      await context.corruptByDeleting('delivery_order_lines', allocation.id);

      final failure = await post(
        grId,
      ).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(failure, isA<GoodReceiptLineIntegrityFailure>());
      expect(
        (failure as GoodReceiptLineIntegrityFailure).extraDoLineIds,
        contains(allocation.id),
      );
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test('baris GR yang hilang terdeteksi sebagai integritas', () async {
      final grId = await readyReceipt();
      final lineId = (await context.receipts.lineReferences(grId)).first.id;

      await context.corruptByDeleting('good_receipt_lines', lineId);

      final failure = await post(
        grId,
      ).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(failure, isA<GoodReceiptLineIntegrityFailure>());
      expect(
        (failure as GoodReceiptLineIntegrityFailure).missingDoLineIds,
        isNotEmpty,
      );
      expect(await context.goodReceiptMovementCount(grId), 0);
    });
  });

  group('pembacaan historis', () {
    test('detail tetap memuat seluruh baris meski master nonaktif', () async {
      final grId = await readyReceipt();
      await context.deactivate('items', fixture.simpleItem.id);
      await context.archive('item_batches', fixture.safeBatch.id);
      await context.deactivate('branches', fixture.branch.id);

      final detail = await context.receipts.getForBranch(
        grId: grId,
        branchId: fixture.branch.id,
      );

      // Labelled, not hidden: the queries behind these screens filter neither
      // `is_active` nor `deleted_at` (§7.6).
      expect(detail!.lines, hasLength(2));
      expect(detail.usesHistoricalMaster, isTrue);
      expect(detail.summary.branchIsHistorical, isTrue);
    });

    test('inner join yang menelan baris terdeteksi, bukan disembunyikan', () async {
      final grId = await readyReceipt();
      await context.corruptByDeleting('items', fixture.simpleItem.id);

      final loaded = await context.receipts.getDetail(grId);
      final stored = await context.receipts.lineReferences(grId);

      // The joined read is one line short. Posting from the half we can see would credit
      // the branch short with nobody told, which is why the plain select is the
      // authority.
      expect(loaded!.lines, hasLength(1));
      expect(stored, hasLength(2));
      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptHistoricalReferenceMissingFailure>()),
      );
    });

    test('GR posted tetap terbaca setelah master dinonaktifkan', () async {
      final grId = await readyReceipt();
      await post(grId);

      await context.deactivate('items', fixture.simpleItem.id);
      await context.deactivate('branches', fixture.branch.id);
      await context.deactivate('users', fixture.branchHead.id);

      final detail = await context.receipts.getForWarehouse(grId);

      expect(detail, isNotNull);
      expect(detail!.lines, hasLength(2));
      expect(detail.summary.receivedByIsHistorical, isTrue);
    });

    test('antrean selisih warehouse menandai master historis', () async {
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: await shippedOrder(),
        nowUtc: nowUtc,
      );
      final byItem = await goodReceiptLinesByItem(context, grId);
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: byItem[fixture.simpleItem.id]!.id,
        reason: 'Rusak',
      );
      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: byItem[fixture.batchItem.id]!.id,
        receivedQty: Quantity.parse('4'),
      );
      await post(grId);

      await context.deactivate('items', fixture.simpleItem.id);
      await context.deactivate('branches', fixture.branch.id);

      final rows = await context.receipts.warehouseDiscrepancies(
        const GoodReceiptFilter(),
      );

      expect(rows, hasLength(1));
      expect(rows.single.itemIsHistorical, isTrue);
      expect(rows.single.branchIsHistorical, isTrue);
      expect(rows.single.usesHistoricalMaster, isTrue);
    });
  });
}
