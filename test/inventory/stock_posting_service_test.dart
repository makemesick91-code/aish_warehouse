import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

void main() {
  late TestContext context;
  late InventoryFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildFixture(context);
  });

  tearDown(() => context.dispose());

  Future<void> seedWarehouseStock(int qty) async {
    await context.posting.postInboundWarehouse(
      itemId: fixture.simpleItem.id,
      toLocationId: fixture.warehouse.id,
      qty: qty,
      actorUserId: fixture.actor.id,
    );
  }

  group('validasi input', () {
    test('qty nol ditolak', () async {
      await expectLater(
        context.posting.postInboundWarehouse(
          itemId: fixture.simpleItem.id,
          toLocationId: fixture.warehouse.id,
          qty: 0,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('qty negatif ditolak', () async {
      await expectLater(
        context.posting.postInboundWarehouse(
          itemId: fixture.simpleItem.id,
          toLocationId: fixture.warehouse.id,
          qty: -5,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('transfer ke lokasi yang sama ditolak', () async {
      await seedWarehouseStock(10);

      await expectLater(
        context.posting.postTransfer(
          itemId: fixture.simpleItem.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.warehouse.id,
          qty: 1,
          movementType: StockMovementType.shipment,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InvalidLocationFailure>()),
      );
    });

    test('barang masuk hanya diterima di warehouse pusat', () async {
      await expectLater(
        context.posting.postInboundWarehouse(
          itemId: fixture.simpleItem.id,
          toLocationId: fixture.branchStore.id,
          qty: 5,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InvalidLocationFailure>()),
      );
    });
  });

  group('transfer', () {
    test('mengurangi saldo sumber dan menambah saldo tujuan', () async {
      await seedWarehouseStock(30);

      await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: 12,
        movementType: StockMovementType.shipment,
        actorUserId: fixture.actor.id,
      );

      final source = await context.inventory.balanceQty(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
      );
      final target = await context.inventory.balanceQty(
        locationId: fixture.branchStore.id,
        itemId: fixture.simpleItem.id,
      );

      expect(source, 18);
      expect(target, 12);
    });

    test('stok sumber tidak boleh menjadi negatif', () async {
      await seedWarehouseStock(5);

      await expectLater(
        context.posting.postTransfer(
          itemId: fixture.simpleItem.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.branchStore.id,
          qty: 6,
          movementType: StockMovementType.shipment,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      final source = await context.inventory.balanceQty(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
      );
      expect(source, 5);
    });

    test('posting bersifat atomik: tidak ada movement saat gagal', () async {
      await seedWarehouseStock(5);
      final before = await context.inventory.stockCard(
        itemId: fixture.simpleItem.id,
      );

      await expectLater(
        context.posting.postTransfer(
          itemId: fixture.simpleItem.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.branchStore.id,
          qty: 999,
          movementType: StockMovementType.shipment,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      final after = await context.inventory.stockCard(
        itemId: fixture.simpleItem.id,
      );
      expect(after.length, before.length);

      final target = await context.inventory.balanceQty(
        locationId: fixture.branchStore.id,
        itemId: fixture.simpleItem.id,
      );
      expect(target, 0);
    });

    test('stream saldo memancarkan perubahan setelah posting', () async {
      final stream = context.inventory.watchBalancesAtLocation(
        fixture.warehouse.id,
      );

      expect(await stream.first, isEmpty);

      final afterPosting = stream.firstWhere((rows) => rows.isNotEmpty);
      await seedWarehouseStock(7);

      final rows = await afterPosting.timeout(const Duration(seconds: 10));
      expect(rows, hasLength(1));
      expect(rows.single.qtyOnHand, 7);
      expect(rows.single.sku, fixture.simpleItem.sku);
    });
  });

  group('batch dan kedaluwarsa', () {
    test('barang ber-ED wajib memiliki batch', () async {
      await expectLater(
        context.posting.postInboundWarehouse(
          itemId: fixture.expiryItem.id,
          toLocationId: fixture.warehouse.id,
          qty: 10,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<BatchRequiredFailure>()),
      );
    });

    test('barang tanpa ED tidak boleh memiliki batch', () async {
      // A batch can only be created for an expiry item, so borrow that batch
      // and try to attach it to the non-expiry item.
      final batch = await context.master.ensureBatch(
        itemId: fixture.expiryItem.id,
        batchNo: 'BATCH-X',
        expiryDate: utcDaysFromNow(90),
      );

      await expectLater(
        context.posting.postInboundWarehouse(
          itemId: fixture.simpleItem.id,
          batchId: batch.id,
          toLocationId: fixture.warehouse.id,
          qty: 10,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<BatchNotAllowedFailure>()),
      );
    });

    test('batch kedaluwarsa ditolak untuk transfer normal', () async {
      final batch = await context.master.ensureBatch(
        itemId: fixture.expiryItem.id,
        batchNo: 'EXP-OLD',
        expiryDate: utcDaysFromNow(5),
      );

      await context.posting.postInboundWarehouse(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        toLocationId: fixture.warehouse.id,
        qty: 10,
        actorUserId: fixture.actor.id,
      );

      // While the batch is still valid the transfer goes through.
      await context.posting.postTransfer(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: 1,
        movementType: StockMovementType.shipment,
        actorUserId: fixture.actor.id,
      );

      // Same database, but the service now believes we are past the expiry.
      final futurePosting = context.postingWithClock(
        () => DateTime.now().toUtc().add(const Duration(days: 30)),
      );

      await expectLater(
        futurePosting.postTransfer(
          itemId: fixture.expiryItem.id,
          batchId: batch.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.branchStore.id,
          qty: 1,
          movementType: StockMovementType.shipment,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<ExpiredBatchFailure>()),
      );

      // The rejected transfer changed nothing.
      expect(
        await context.inventory.balanceQty(
          locationId: fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: batch.id,
        ),
        9,
      );
    });

    test('pemusnahan tetap boleh memproses batch kedaluwarsa', () async {
      final batch = await context.master.ensureBatch(
        itemId: fixture.expiryItem.id,
        batchNo: 'EXP-DISPOSE',
        expiryDate: utcDaysFromNow(3),
      );
      await context.posting.postInboundWarehouse(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        toLocationId: fixture.warehouse.id,
        qty: 8,
        actorUserId: fixture.actor.id,
      );

      // The clock is past the expiry date, yet disposal must still work: it is
      // the only way expired stock leaves the system (G-E7).
      final futurePosting = context.postingWithClock(
        () => DateTime.now().toUtc().add(const Duration(days: 30)),
      );
      final movement = await futurePosting.postDisposal(
        locationId: fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        qty: 8,
        actorUserId: fixture.actor.id,
        note: 'Pemusnahan barang kedaluwarsa',
      );

      expect(movement.movementType, StockMovementType.disposal);
      expect(
        await context.inventory.balanceQty(
          locationId: fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: batch.id,
        ),
        0,
      );
    });

    test('pemusnahan wajib memiliki catatan', () async {
      await seedWarehouseStock(4);

      await expectLater(
        context.posting.postDisposal(
          locationId: fixture.warehouse.id,
          itemId: fixture.simpleItem.id,
          qty: 1,
          actorUserId: fixture.actor.id,
          note: '   ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('opname adjustment', () {
    test('menyesuaikan saldo ke hasil hitung fisik', () async {
      await seedWarehouseStock(10);

      final movement = await context.posting.postOpnameAdjustment(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        countedQty: 7,
        actorUserId: fixture.actor.id,
      );

      expect(movement, isNotNull);
      expect(movement!.movementType, StockMovementType.opnameAdjustment);
      expect(movement.qty, 3);
      expect(movement.fromLocationId, fixture.warehouse.id);
      expect(
        await context.inventory.balanceQty(
          locationId: fixture.warehouse.id,
          itemId: fixture.simpleItem.id,
        ),
        7,
      );
    });

    test('tidak membuat movement bila tidak ada selisih', () async {
      await seedWarehouseStock(10);

      final movement = await context.posting.postOpnameAdjustment(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        countedQty: 10,
        actorUserId: fixture.actor.id,
      );

      expect(movement, isNull);
    });
  });

  group('reversal', () {
    test('membuat movement baru dan tidak mengubah movement lama', () async {
      await seedWarehouseStock(20);
      final original = await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: 8,
        movementType: StockMovementType.shipment,
        actorUserId: fixture.actor.id,
      );

      final reversal = await context.posting.postReversal(
        movementId: original.id,
        actorUserId: fixture.actor.id,
        note: 'Salah kirim',
      );

      expect(reversal.id, isNot(original.id));
      expect(reversal.movementType, StockMovementType.reversal);
      expect(reversal.reversalOfMovementId, original.id);
      expect(reversal.fromLocationId, original.toLocationId);
      expect(reversal.toLocationId, original.fromLocationId);

      final stored = await context.inventory.movementById(original.id);
      expect(stored, isNotNull);
      expect(stored!.qty, original.qty);
      expect(stored.movementType, original.movementType);
      expect(stored.fromLocationId, original.fromLocationId);
      expect(stored.toLocationId, original.toLocationId);
      expect(stored.reversalOfMovementId, isNull);

      expect(
        await context.inventory.balanceQty(
          locationId: fixture.warehouse.id,
          itemId: fixture.simpleItem.id,
        ),
        20,
      );
      expect(
        await context.inventory.balanceQty(
          locationId: fixture.branchStore.id,
          itemId: fixture.simpleItem.id,
        ),
        0,
      );
    });

    test('movement tidak dapat dibalik dua kali', () async {
      await seedWarehouseStock(10);
      final original = await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: 4,
        movementType: StockMovementType.shipment,
        actorUserId: fixture.actor.id,
      );
      await context.posting.postReversal(
        movementId: original.id,
        actorUserId: fixture.actor.id,
        note: 'Koreksi',
      );

      await expectLater(
        context.posting.postReversal(
          movementId: original.id,
          actorUserId: fixture.actor.id,
          note: 'Koreksi ulang',
        ),
        throwsA(isA<MovementImmutableFailure>()),
      );
    });
  });
}
