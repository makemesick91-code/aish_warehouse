import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Historical recovery (§21, §7.2/§7.3 of the opname hardening applied to
/// shipments).
///
/// A Delivery Order fulfils a Purchase Request that was raised days earlier, so
/// master data can legitimately change underneath it. The rule has two halves and
/// they pull in opposite directions:
///
/// * **Deactivated or archived is still there.** A branch, item, batch or account
///   withdrawn *after* the order was raised is still exactly what was ordered, and
///   the shipment must remain readable and postable. Losing it would strand the
///   branch, because a `processing` request has no way back.
/// * **Missing is missing.** A row that cannot be found at all means the reference
///   is broken. Nothing may be guessed, substituted or silently dropped, and the
///   refusal must leave no movement, no balance change and no status behind.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> preparedSimple({String qty = '1'}) => prepareDeliveryOrder(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [simpleAllocation(fixture, qty: qty)],
  );

  group('master nonaktif tetap dapat dipenuhi', () {
    test('cabang nonaktif tetap menerima pengiriman', () async {
      final doId = await preparedSimple();
      await context.deactivate('branches', fixture.branch.id);

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
      final detail = await context.deliveries.getForWarehouse(doId);
      // Readable, and labelled — not hidden.
      expect(detail!.summary.branchIsHistorical, isTrue);
      expect(detail.usesHistoricalMaster, isTrue);
      expect(detail.summary.branchName, fixture.branch.name);
    });

    test('barang nonaktif tetap dapat dikirim', () async {
      final doId = await preparedSimple();
      await context.deactivate('items', fixture.simpleItem.id);

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final detail = await context.deliveries.getForWarehouse(doId);
      expect(detail!.lines.single.itemIsHistorical, isTrue);
      expect(detail.lines.single.itemName, fixture.simpleItem.name);
      expect(await context.shipmentMovementCount(doId), 1);
    });

    test('pemohon nonaktif tidak menghilangkan Surat Jalan', () async {
      final doId = await preparedSimple();
      await context.deactivate('users', fixture.branchHead.id);

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final detail = await context.deliveries.getForWarehouse(doId);
      expect(detail, isNotNull);
      expect(detail!.summary.requestedByName, fixture.branchHead.fullName);
    });

    test('petugas penyiap nonaktif tidak menghilangkan dokumen', () async {
      final doId = await preparedSimple();
      await context.deactivate('users', fixture.warehouseUser.id);

      final detail = await context.deliveries.getForWarehouse(doId);
      expect(detail!.summary.preparedByIsHistorical, isTrue);
      expect(detail.summary.preparedByName, fixture.warehouseUser.fullName);

      // The document is not stranded: another active officer ships it.
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.secondWarehouseUser.id,
        deliveryOrderId: doId,
      );
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });

    test('Surat Jalan shipped tetap terbaca setelah master nonaktif', () async {
      final doId = await preparedSimple();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await context.deactivate('branches', fixture.branch.id);
      await context.deactivate('items', fixture.simpleItem.id);
      await context.archive('users', fixture.warehouseUser.id);

      final warehouseView = await context.deliveries.getForWarehouse(doId);
      expect(warehouseView, isNotNull);
      expect(warehouseView!.usesHistoricalMaster, isTrue);

      // And the branch can still receive it, which is the whole point.
      final branchView = await context.deliveries.getForBranch(
        doId: doId,
        branchId: fixture.branch.id,
      );
      expect(branchView, isNotNull);
      expect(branchView!.lines.single.shippedQty, Quantity.parse('1'));
    });

    test('kategori barang nonaktif tidak memengaruhi pengiriman', () async {
      // Categories carry no `is_active` semantics for a shipment, but archiving one
      // must not make its items unreadable either.
      final doId = await preparedSimple();
      await context.archive(
        'item_categories',
        (await context.master.categories()).first.id,
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });

    test('batch diarsipkan setelah penyiapan tetap dapat dikirim', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      await context.archive('item_batches', fixture.nearBatch.id);

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final movements = await context.shipmentMovements(doId);
      expect(movements.single['batch_id'], fixture.nearBatch.id);
      final detail = await context.deliveries.getForWarehouse(doId);
      expect(detail!.lines.single.batchIsHistorical, isTrue);
    });
  });

  group('referensi yang benar-benar hilang', () {
    /// Everything a broken reference must leave untouched.
    Future<void> expectNothingHappened(String doId) async {
      expect(await context.shipmentMovementCount(doId), 0);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
      expect(await context.deliveryOrderColumn(doId, 'shipped_at'), isNull);
      expect(await context.deliveryOrderColumn(doId, 'shipped_by'), isNull);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'processing',
      );
    }

    test('barang hilang menghasilkan kegagalan eksplisit', () async {
      final doId = await preparedSimple();
      final before = await context.balancesAt(fixture.warehouse.id);
      await context.corruptByDeleting('items', fixture.simpleItem.id);

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<HistoricalDeliveryReferenceMissingFailure>()
              .having((failure) => failure.entity, 'entity', 'items')
              .having((failure) => failure.doId, 'doId', doId),
        ),
      );
      await expectNothingHappened(doId);
      expect(await context.balancesAt(fixture.warehouse.id), before);
    });

    test('batch hilang menghasilkan kegagalan eksplisit', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      await context.corruptByDeleting('item_batches', fixture.nearBatch.id);

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<HistoricalDeliveryReferenceMissingFailure>().having(
            (failure) => failure.entity,
            'entity',
            'item_batches',
          ),
        ),
      );
      await expectNothingHappened(doId);
    });

    test('Purchase Request hilang menghasilkan kegagalan eksplisit', () async {
      final doId = await preparedSimple();
      await context.corruptByDeleting(
        'purchase_requests',
        fixture.purchaseRequestId,
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<HistoricalDeliveryReferenceMissingFailure>().having(
            (failure) => failure.entity,
            'entity',
            'purchase_requests',
          ),
        ),
      );
      expect(await context.shipmentMovementCount(doId), 0);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
    });

    test('inner join tidak boleh menghilangkan baris', () async {
      // Two allocations; one item's row disappears. The joined read returns one
      // line, the plain select returns two, and the difference is what refuses the
      // shipment rather than sending a document that is quietly short.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '1'),
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      await context.corruptByDeleting('items', fixture.simpleItem.id);

      final stored = await context.deliveries.lineReferences(doId);
      final loaded = await context.deliveries.getForWarehouse(doId);
      expect(stored, hasLength(2));
      expect(loaded!.lines, hasLength(1));

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<HistoricalDeliveryReferenceMissingFailure>()),
      );
      await expectNothingHappened(doId);
    });

    test('lokasi warehouse hilang menolak pengiriman', () async {
      final doId = await preparedSimple();
      await context.corruptByDeleting('stock_locations', fixture.warehouse.id);

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<WarehouseLocationNotFoundFailure>()),
      );
      await expectNothingHappened(doId);
    });

    test('lokasi warehouse ganda menolak pengiriman', () async {
      final doId = await preparedSimple();
      await context.database.customStatement(
        'INSERT INTO stock_locations (id, created_at, updated_at, sync_status, '
        'type, name) VALUES (?, ?, ?, ?, ?, ?);',
        [
          'wh-2',
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'pending',
          'warehouse',
          'Warehouse Pusat Kedua',
        ],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(
          isA<AmbiguousWarehouseLocationFailure>().having(
            (failure) => failure.locationIds.length,
            'jumlah lokasi',
            2,
          ),
        ),
      );
      await expectNothingHappened(doId);
    });

    test(
      'lokasi warehouse yang diarsipkan dianggap tidak ada untuk pengiriman baru',
      () async {
        // Archiving is not deletion, but a *new* posting must not go to a location an
        // administrator has retired: the balances it holds are history.
        final doId = await preparedSimple();
        await context.archive('stock_locations', fixture.warehouse.id);

        await expectLater(
          () => context.shipDeliveryOrder().call(
            actorUserId: fixture.warehouseUser.id,
            deliveryOrderId: doId,
          ),
          throwsA(isA<WarehouseLocationNotFoundFailure>()),
        );
        await expectNothingHappened(doId);
      },
    );

    test('aktor warehouse yang hilang menolak pengiriman', () async {
      final doId = await preparedSimple();
      await context.corruptByDeleting('users', fixture.secondWarehouseUser.id);

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.secondWarehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
      await expectNothingHappened(doId);
    });
  });

  group('penyiapan baru tetap ketat', () {
    test(
      'alokasi baru menolak batch kedaluwarsa meski dokumen historis',
      () async {
        // Historic tolerance is about *completing* work, not about starting it: an
        // expired batch is never a legitimate new allocation.
        final order = await context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: fixture.purchaseRequestId,
        );
        await context.deactivate('items', fixture.batchItem.id);

        await expectLater(
          () => context.updateDeliveryLine().add(
            actorUserId: fixture.warehouseUser.id,
            deliveryOrderId: order.id,
            prLineId: fixture.batchLineId,
            shippedQty: Quantity.parse('1'),
            batchId: fixture.expiredBatch.id,
            fefoOverrideReason: 'Diminta cabang',
          ),
          throwsA(isA<ExpiredBatchForDeliveryFailure>()),
        );
        expect(await context.deliveryLineCount(order.id), 0);
      },
    );

    test('alokasi FEFO tetap berjalan untuk barang nonaktif pada PR', () async {
      // The item was withdrawn after the request was raised. It is still what the
      // branch asked for, so FEFO must still allocate it.
      await context.deactivate('items', fixture.batchItem.id);

      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      final outcomes = await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
      );

      final batched = outcomes.firstWhere(
        (outcome) => outcome.prLineId == fixture.batchLineId,
      );
      expect(batched.allocatedQty, Quantity.parse('4'));
    });
  });
}
