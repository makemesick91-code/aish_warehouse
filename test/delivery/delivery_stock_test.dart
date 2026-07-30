import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:aish_warehouse/features/inventory/domain/models/inventory_models.dart';
import 'package:aish_warehouse/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:aish_warehouse/features/inventory/domain/services/stock_posting_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// **G-D3** — *"`shipped_qty` tidak boleh melebihi saldo Warehouse Pusat; posting DO
/// mengurangi stok warehouse saat itu juga (stok tidak boleh negatif — transaksi
/// ditolak)."*
///
/// And the half of the rule the wording implies rather than states: the branch gains
/// nothing. Spec §2.5 gives Good Receipt the `good_receipt` movement into Gudang
/// Cabang, so a shipment is one leg out and nothing in — `to_location_id` is NULL on
/// every row. A test that only checked the warehouse side would pass with a shipment
/// that had already credited the branch.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<Quantity> warehouseBalance({String? batchId, String? itemId}) =>
      context.inventory.balanceQty(
        locationId: fixture.warehouse.id,
        itemId: itemId ?? fixture.simpleItem.id,
        batchId: batchId,
      );

  group('kecukupan saldo', () {
    test('qty di bawah saldo berhasil', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      expect(await warehouseBalance(), Quantity.parse('1.5'));
    });

    test('qty tepat sama dengan saldo berhasil dan menyisakan nol', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      expect(await warehouseBalance(), Quantity.zero());
    });

    test('qty di atas saldo ditolak', () async {
      // 2.5 on the shelf, 3 requested — the order allows 3 but the warehouse does
      // not, and G-D3 is the binding limit.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '3')],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );
      expect(await warehouseBalance(), Quantity.parse('2.5'));
      expect(await context.shipmentMovementCount(doId), 0);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
    });

    test('barang tanpa saldo sama sekali ditolak', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [DeliveryAllocationForScarce(fixture).allocation],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );
      expect(await context.shipmentMovementCount(doId), 0);
    });

    test('dua alokasi dari batch yang sama diperiksa sebagai total', () async {
      // Checking them one at a time would let two allocations of 1.5 both pass
      // against a 2-unit batch. The sufficiency check sums per position first.
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      // The unique index forbids two allocations of the same `(PR line, batch)`, so
      // the collision has to come from two *different* PR lines drawing on one
      // batch — which the schema permits and the posting must still catch.
      await context.database.customStatement(
        'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
        'sync_status, do_id, pr_line_id, item_id, batch_id, shipped_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'dol-a',
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'pending',
          order.id,
          fixture.batchLineId,
          fixture.batchItem.id,
          fixture.soonBatch.id,
          1500,
        ],
      );
      await context.database.customStatement(
        'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
        'sync_status, do_id, pr_line_id, item_id, batch_id, shipped_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'dol-b',
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'pending',
          order.id,
          fixture.tieLineId,
          fixture.batchItem.id,
          fixture.soonBatch.id,
          1500,
        ],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(await context.shipmentMovementCount(order.id), 0);
    });

    test('satu baris kurang membatalkan seluruh dokumen', () async {
      // The first allocation is perfectly shippable; the second is not. Atomicity
      // means the first one's movement must not survive.
      //
      // The short line is `tieItem`: 3 requested — so G-D2 is satisfied — sourced
      // entirely from `tieBatchA`, which holds only 2. Its sibling batch shares the
      // same expiry date, so passing it over is no FEFO violation either (G-E3).
      // That leaves the balance as the one rule left to fire, which is the point.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '1'),
          DeliveryAllocation(
            prLineId: fixture.tieLineId,
            itemId: fixture.tieItem.id,
            batchId: fixture.tieBatchA.id,
            qty: Quantity.parse('3'),
          ),
        ],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(await context.shipmentMovementCount(doId), 0);
      expect(await warehouseBalance(), Quantity.parse('2.5'));
      expect(
        await warehouseBalance(
          itemId: fixture.tieItem.id,
          batchId: fixture.tieBatchA.id,
        ),
        Quantity.parse('2'),
      );
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
      expect(await context.deliveryOrderColumn(doId, 'shipped_at'), isNull);
      expect(await context.deliveryOrderColumn(doId, 'shipped_by'), isNull);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'processing',
      );
    });

    test('perubahan saldo antara penyiapan dan pengiriman terdeteksi', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2')],
      );

      // Somebody else disposes of the stock while the form sat open. The form's
      // snapshot said 2.5 was there; the transaction reads 0.5 and refuses.
      await context.posting.postDisposal(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        qty: Quantity.parse('2'),
        actorUserId: fixture.warehouseUser.id,
        note: 'Rusak saat penyimpanan',
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );
      expect(await warehouseBalance(), Quantity.parse('0.5'));
      expect(await context.shipmentMovementCount(doId), 0);
    });
  });

  group('ledger shipment', () {
    test('movement shipment tercatat dengan referensi yang benar', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '1'),
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1.5',
            nearExpiryConfirmed: true,
          ),
        ],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final movements = await context.shipmentMovements(doId);
      expect(movements, hasLength(2));
      for (final movement in movements) {
        expect(movement['movement_type'], StockMovementType.shipment.dbValue);
        expect(movement['ref_doc_type'], RefDocType.deliveryOrder);
        expect(movement['ref_doc_id'], doId);
        expect(movement['from_location_id'], fixture.warehouse.id);
        // The goods are in transit: the branch gains nothing until Good Receipt
        // posts (spec §2.5).
        expect(movement['to_location_id'], isNull);
        expect(movement['actor_user_id'], fixture.warehouseUser.id);
      }

      final byItem = {
        for (final movement in movements)
          '${movement['item_id']}|${movement['batch_id'] ?? ''}':
              movement['qty'],
      };
      expect(byItem['${fixture.simpleItem.id}|'], 1000);
      expect(byItem['${fixture.batchItem.id}|${fixture.nearBatch.id}'], 1500);
    });

    test('gudang cabang tidak bertambah', () async {
      final before = await context.balancesAt(fixture.branchStore.id);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      expect(await context.balancesAt(fixture.branchStore.id), before);
      expect(before, isEmpty);
    });

    test('saldo warehouse berkurang tepat per batch', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1.5',
            nearExpiryConfirmed: true,
          ),
          batchAllocation(
            fixture,
            batchId: fixture.soonBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final balances = await context.balancesAt(fixture.warehouse.id);
      expect(balances['${fixture.batchItem.id}|${fixture.nearBatch.id}'], 0);
      expect(balances['${fixture.batchItem.id}|${fixture.soonBatch.id}'], 1000);
      // Untouched batches keep their quantity.
      expect(balances['${fixture.batchItem.id}|${fixture.safeBatch.id}'], 6000);
    });

    test('movement lama tidak diubah, hanya ditambah', () async {
      final before = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM stock_movements;')
          .getSingle();

      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final after = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM stock_movements;')
          .getSingle();
      // Append-only (G-A1): exactly one new row, none replaced.
      expect(after.read<int>('c'), before.read<int>('c') + 1);
    });

    test('Surat Jalan tanpa baris tidak dapat dikirim', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        ),
        throwsA(isA<DeliveryOrderLineRequiredFailure>()),
      );
      expect(await context.shipmentMovementCount(order.id), 0);
    });
  });

  group('rollback atomik', () {
    test('kegagalan ledger membatalkan movement, saldo, DO dan PR', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '1'),
          // FEFO's own answer — nearest expiry first — with the confirmation its
          // 12-day shelf life demands, so nothing rejects the document before the
          // ledger is reached and the rollback has something to undo.
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1.5',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      final before = await context.balancesAt(fixture.warehouse.id);

      // A posting service that writes the first movement and then throws — the
      // shape of a mid-document failure that atomicity has to survive.
      final failing = _FailAfterFirstMovementPostingService(
        inventory: context.inventory,
        master: context.master,
        clock: () => nowUtc,
      );

      await expectLater(
        () => context
            .shipDeliveryOrder(clock: () => nowUtc, posting: failing)
            .call(actorUserId: fixture.warehouseUser.id, deliveryOrderId: doId),
        throwsA(isA<ValidationFailure>()),
      );

      expect(await context.shipmentMovementCount(doId), 0);
      expect(await context.balancesAt(fixture.warehouse.id), before);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
      expect(await context.deliveryOrderColumn(doId, 'shipped_at'), isNull);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'processing',
      );
    });

    test('kegagalan setelah movement membatalkan status DO juga', () async {
      // The whole `tieItem` position ships, which would complete nothing on its
      // own — but the second allocation refers to a batch of another item, so the
      // consistency check fires *after* the quantities were validated.
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.database.customStatement(
        'INSERT INTO delivery_order_lines (id, created_at, updated_at, '
        'sync_status, do_id, pr_line_id, item_id, batch_id, shipped_qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'dol-wrong-batch',
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'pending',
          order.id,
          fixture.tieLineId,
          fixture.tieItem.id,
          // A batch of `batchItem`, not of `tieItem`.
          fixture.safeBatch.id,
          1000,
        ],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: order.id,
        ),
        throwsA(isA<InvalidDeliveryBatchFailure>()),
      );
      expect(await context.shipmentMovementCount(order.id), 0);
      expect(await context.deliveryOrderStatusOf(order.id), 'preparing');
    });
  });
}

/// The fixture's zero-stock position, as an allocation.
///
/// A tiny wrapper class rather than a helper function, so the intent reads at the
/// call site: this is the item that has nothing on the shelf.
class DeliveryAllocationForScarce {
  DeliveryAllocationForScarce(this.fixture);

  final DeliveryFixture fixture;

  DeliveryAllocation get allocation => DeliveryAllocation(
    prLineId: fixture.scarceLineId,
    itemId: fixture.scarceItem.id,
    qty: Quantity.parse('1'),
  );
}

/// A posting service that appends one movement and then fails.
///
/// Subclassing the real service rather than faking it, so everything up to the
/// failure point is genuine: real validation, a real ledger row, a real balance
/// write. That is what makes the rollback assertion meaningful — the transaction has
/// something to roll *back*.
class _FailAfterFirstMovementPostingService extends StockPostingService {
  _FailAfterFirstMovementPostingService({
    required super.inventory,
    required super.master,
    super.clock,
  }) : _inventory = inventory;

  final InventoryRepository _inventory;

  @override
  Future<List<InventoryMovement>> postShipmentInTransaction({
    required String fromLocationId,
    required List<ShipmentPostingLine> lines,
    required String actorUserId,
    required String deliveryOrderId,
  }) async {
    final first = lines.first;
    await _inventory.appendMovement(
      MovementDraft(
        id: 'partial-movement-$deliveryOrderId',
        itemId: first.itemId,
        batchId: first.batchId,
        fromLocationId: fromLocationId,
        qty: first.qty,
        movementType: StockMovementType.shipment,
        actorUserId: actorUserId,
        refDocType: RefDocType.deliveryOrder,
        refDocId: deliveryOrderId,
      ),
    );
    await _inventory.setBalanceQty(
      locationId: fromLocationId,
      itemId: first.itemId,
      batchId: first.batchId,
      qtyOnHand:
          await _inventory.balanceQty(
            locationId: fromLocationId,
            itemId: first.itemId,
            batchId: first.batchId,
          ) -
          first.qty,
    );
    throw const ValidationFailure('Kegagalan simulasi setelah baris pertama.');
  }
}
