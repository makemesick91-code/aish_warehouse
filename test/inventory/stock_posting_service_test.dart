import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
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

  /// Quantities are written the way a user types them and parsed, so the tests
  /// read like the business rules they check.
  Quantity qty(String value) => Quantity.parse(value);

  Future<void> seedWarehouseStock(String amount) async {
    await context.posting.postInboundWarehouse(
      itemId: fixture.simpleItem.id,
      toLocationId: fixture.warehouse.id,
      qty: qty(amount),
      actorUserId: fixture.actor.id,
    );
  }

  Future<Quantity> warehouseBalance() => context.inventory.balanceQty(
    locationId: fixture.warehouse.id,
    itemId: fixture.simpleItem.id,
  );

  Future<Quantity> branchStoreBalance() => context.inventory.balanceQty(
    locationId: fixture.branchStore.id,
    itemId: fixture.simpleItem.id,
  );

  group('validasi input', () {
    test('qty nol ditolak', () async {
      await expectLater(
        context.posting.postInboundWarehouse(
          itemId: fixture.simpleItem.id,
          toLocationId: fixture.warehouse.id,
          qty: Quantity.zero(),
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
          qty: Quantity.fromWhole(-5),
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('transfer ke lokasi yang sama ditolak', () async {
      await seedWarehouseStock('10');

      await expectLater(
        context.posting.postTransfer(
          itemId: fixture.simpleItem.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.warehouse.id,
          qty: Quantity.fromWhole(1),
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
          qty: Quantity.fromWhole(5),
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InvalidLocationFailure>()),
      );
    });
  });

  group('transfer', () {
    test('mengurangi saldo sumber dan menambah saldo tujuan', () async {
      await seedWarehouseStock('30');

      await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: qty('12'),
        movementType: StockMovementType.shipment,
        actorUserId: fixture.actor.id,
      );

      expect(await warehouseBalance(), qty('18'));
      expect(await branchStoreBalance(), qty('12'));
    });

    test('stok sumber tidak boleh menjadi negatif', () async {
      await seedWarehouseStock('5');

      await expectLater(
        context.posting.postTransfer(
          itemId: fixture.simpleItem.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.branchStore.id,
          qty: qty('6'),
          movementType: StockMovementType.shipment,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(await warehouseBalance(), qty('5'));
    });

    test('posting bersifat atomik: tidak ada movement saat gagal', () async {
      await seedWarehouseStock('5');
      final before = await context.inventory.stockCard(
        itemId: fixture.simpleItem.id,
      );

      await expectLater(
        context.posting.postTransfer(
          itemId: fixture.simpleItem.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.branchStore.id,
          qty: qty('999'),
          movementType: StockMovementType.shipment,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      final after = await context.inventory.stockCard(
        itemId: fixture.simpleItem.id,
      );
      expect(after.length, before.length);
      expect(await branchStoreBalance(), Quantity.zero());
    });

    test('stream saldo memancarkan perubahan setelah posting', () async {
      final stream = context.inventory.watchBalancesAtLocation(
        fixture.warehouse.id,
      );

      expect(await stream.first, isEmpty);

      final afterPosting = stream.firstWhere((rows) => rows.isNotEmpty);
      await seedWarehouseStock('7');

      final rows = await afterPosting.timeout(const Duration(seconds: 10));
      expect(rows, hasLength(1));
      expect(rows.single.qtyOnHand, qty('7'));
      expect(rows.single.sku, fixture.simpleItem.sku);
    });
  });

  group('kuantitas desimal', () {
    test('inbound 0.5 berhasil dan tersimpan tepat', () async {
      await seedWarehouseStock('0.5');

      final balance = await warehouseBalance();
      expect(balance, qty('0.5'));
      expect(balance.format(), '0.5');
      expect(balance.milliUnits, 500);
    });

    test('transfer 0.25 memindahkan kuantitas desimal', () async {
      await seedWarehouseStock('1');

      await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: qty('0.25'),
        movementType: StockMovementType.shipment,
        actorUserId: fixture.actor.id,
      );

      expect(await warehouseBalance(), qty('0.75'));
      expect(await branchStoreBalance(), qty('0.25'));
    });

    test('inbound 1.5 lalu transfer 0.5 menyisakan tepat 1', () async {
      await seedWarehouseStock('1.5');

      await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: qty('0.5'),
        movementType: StockMovementType.shipment,
        actorUserId: fixture.actor.id,
      );

      final remaining = await warehouseBalance();
      expect(remaining, Quantity.fromWhole(1));
      expect(remaining.format(), '1');
    });

    test('inbound 0.1 dan 0.2 menghasilkan saldo tepat 0.3', () async {
      await seedWarehouseStock('0.1');
      await seedWarehouseStock('0.2');

      final balance = await warehouseBalance();
      expect(balance, qty('0.3'));
      // The floating-point answer would be 0.30000000000000004.
      expect(balance.format(), '0.3');
      expect(balance.milliUnits, 300);
    });

    test('transfer melebihi saldo desimal ditolak', () async {
      await seedWarehouseStock('0.5');

      await expectLater(
        context.posting.postTransfer(
          itemId: fixture.simpleItem.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.branchStore.id,
          qty: qty('0.501'),
          movementType: StockMovementType.shipment,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(await warehouseBalance(), qty('0.5'));
      expect(await branchStoreBalance(), Quantity.zero());
    });

    test('rollback atomik tetap bekerja dengan kuantitas desimal', () async {
      await seedWarehouseStock('1.25');
      final before = await context.inventory.stockCard(
        itemId: fixture.simpleItem.id,
      );

      await expectLater(
        context.posting.postTransfer(
          itemId: fixture.simpleItem.id,
          fromLocationId: fixture.warehouse.id,
          toLocationId: fixture.branchStore.id,
          qty: qty('2.5'),
          movementType: StockMovementType.shipment,
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      final after = await context.inventory.stockCard(
        itemId: fixture.simpleItem.id,
      );
      expect(after.length, before.length);
      expect(await warehouseBalance(), qty('1.25'));
    });

    test('saldo tidak pernah menjadi negatif', () async {
      await seedWarehouseStock('0.5');

      await expectLater(
        context.posting.postDisposal(
          locationId: fixture.warehouse.id,
          itemId: fixture.simpleItem.id,
          qty: qty('0.75'),
          actorUserId: fixture.actor.id,
          note: 'Pemusnahan berlebih',
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      final balance = await warehouseBalance();
      expect(balance.isNegative, isFalse);
      expect(balance, qty('0.5'));
    });

    test('pemusnahan kuantitas desimal berhasil', () async {
      await seedWarehouseStock('2.375');

      final movement = await context.posting.postDisposal(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        qty: qty('0.375'),
        actorUserId: fixture.actor.id,
        note: 'Rusak saat penyimpanan',
      );

      expect(movement.qty, qty('0.375'));
      expect(await warehouseBalance(), qty('2'));
    });

    test('stream saldo memancarkan nilai desimal', () async {
      final stream = context.inventory.watchBalancesAtLocation(
        fixture.warehouse.id,
      );
      expect(await stream.first, isEmpty);

      final afterPosting = stream.firstWhere((rows) => rows.isNotEmpty);
      await seedWarehouseStock('0.5');

      final rows = await afterPosting.timeout(const Duration(seconds: 10));
      expect(rows.single.qtyOnHand, qty('0.5'));
      expect(rows.single.qtyOnHand.format(), '0.5');
      expect(rows.single.qtyOnHand.formatWithUnit(rows.single.unit), '0.5 box');
    });
  });

  group('batch dan kedaluwarsa', () {
    test('barang ber-ED wajib memiliki batch', () async {
      await expectLater(
        context.posting.postInboundWarehouse(
          itemId: fixture.expiryItem.id,
          toLocationId: fixture.warehouse.id,
          qty: qty('10'),
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
        expiryDate: expiryDateInDays(90),
      );

      await expectLater(
        context.posting.postInboundWarehouse(
          itemId: fixture.simpleItem.id,
          batchId: batch.id,
          toLocationId: fixture.warehouse.id,
          qty: qty('10'),
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<BatchNotAllowedFailure>()),
      );
    });

    test('batch kedaluwarsa ditolak untuk transfer normal', () async {
      final batch = await context.master.ensureBatch(
        itemId: fixture.expiryItem.id,
        batchNo: 'EXP-OLD',
        expiryDate: expiryDateInDays(5),
      );

      await context.posting.postInboundWarehouse(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        toLocationId: fixture.warehouse.id,
        qty: qty('10'),
        actorUserId: fixture.actor.id,
      );

      // While the batch is still valid the transfer goes through.
      await context.posting.postTransfer(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: qty('1'),
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
          qty: qty('1'),
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
        qty('9'),
      );
    });

    test('batch berlaku sampai akhir tanggal ED menurut GMT+8', () async {
      final batch = await context.master.ensureBatch(
        itemId: fixture.expiryItem.id,
        batchNo: 'EXP-TODAY',
        // Civil date; must not shift when compared or formatted.
        expiryDate: DateTime.utc(2026, 7, 29),
      );

      // 2026-07-29 23:30 GMT+8 — the last half hour of the expiry day.
      final onExpiryDay = context.postingWithClock(
        () => DateTime.utc(2026, 7, 29, 15, 30),
      );
      await onExpiryDay.postInboundWarehouse(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        toLocationId: fixture.warehouse.id,
        qty: qty('4'),
        actorUserId: fixture.actor.id,
      );

      expect(
        await context.inventory.balanceQty(
          locationId: fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: batch.id,
        ),
        qty('4'),
      );
    });

    test('batch ditolak pada hari berikutnya menurut GMT+8', () async {
      final batch = await context.master.ensureBatch(
        itemId: fixture.expiryItem.id,
        batchNo: 'EXP-TOMORROW',
        expiryDate: DateTime.utc(2026, 7, 29),
      );

      // 2026-07-29 16:30 UTC is already 2026-07-30 00:30 in GMT+8, so the
      // batch is expired even though the UTC date still reads 29 July.
      final afterMidnight = context.postingWithClock(
        () => DateTime.utc(2026, 7, 29, 16, 30),
      );

      await expectLater(
        afterMidnight.postInboundWarehouse(
          itemId: fixture.expiryItem.id,
          batchId: batch.id,
          toLocationId: fixture.warehouse.id,
          qty: qty('4'),
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<ExpiredBatchFailure>()),
      );
    });

    test('pemusnahan tetap boleh memproses batch kedaluwarsa', () async {
      final batch = await context.master.ensureBatch(
        itemId: fixture.expiryItem.id,
        batchNo: 'EXP-DISPOSE',
        expiryDate: expiryDateInDays(3),
      );
      await context.posting.postInboundWarehouse(
        itemId: fixture.expiryItem.id,
        batchId: batch.id,
        toLocationId: fixture.warehouse.id,
        qty: qty('8'),
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
        qty: qty('8'),
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
        Quantity.zero(),
      );
    });

    test('pemusnahan wajib memiliki catatan', () async {
      await seedWarehouseStock('4');

      await expectLater(
        context.posting.postDisposal(
          locationId: fixture.warehouse.id,
          itemId: fixture.simpleItem.id,
          qty: qty('1'),
          actorUserId: fixture.actor.id,
          note: '   ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('opname adjustment', () {
    test('menyesuaikan saldo ke hasil hitung fisik', () async {
      await seedWarehouseStock('10');

      final movement = await context.posting.postOpnameAdjustment(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        countedQty: qty('7'),
        actorUserId: fixture.actor.id,
      );

      expect(movement, isNotNull);
      expect(movement!.movementType, StockMovementType.opnameAdjustment);
      expect(movement.qty, qty('3'));
      expect(movement.fromLocationId, fixture.warehouse.id);
      expect(await warehouseBalance(), qty('7'));
    });

    test('menerima hasil hitung fisik desimal', () async {
      await seedWarehouseStock('2');

      final movement = await context.posting.postOpnameAdjustment(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        countedQty: qty('1.5'),
        actorUserId: fixture.actor.id,
      );

      // The difference is -0.5; the movement carries its magnitude and encodes
      // the direction through `from_location_id`.
      expect(movement!.qty, qty('0.5'));
      expect(movement.fromLocationId, fixture.warehouse.id);
      expect(movement.toLocationId, isNull);
      expect(await warehouseBalance(), qty('1.5'));
    });

    test('selisih positif desimal menambah saldo', () async {
      await seedWarehouseStock('1');

      final movement = await context.posting.postOpnameAdjustment(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        countedQty: qty('1.25'),
        actorUserId: fixture.actor.id,
      );

      expect(movement!.qty, qty('0.25'));
      expect(movement.toLocationId, fixture.warehouse.id);
      expect(await warehouseBalance(), qty('1.25'));
    });

    test('tidak membuat movement bila tidak ada selisih', () async {
      await seedWarehouseStock('10');

      final movement = await context.posting.postOpnameAdjustment(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        countedQty: qty('10'),
        actorUserId: fixture.actor.id,
      );

      expect(movement, isNull);
    });

    test('hasil hitung fisik negatif ditolak', () async {
      await seedWarehouseStock('10');

      await expectLater(
        context.posting.postOpnameAdjustment(
          locationId: fixture.warehouse.id,
          itemId: fixture.simpleItem.id,
          countedQty: Quantity.fromMilliUnits(-500),
          actorUserId: fixture.actor.id,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('reversal', () {
    test('membuat movement baru dan tidak mengubah movement lama', () async {
      await seedWarehouseStock('20');
      final original = await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: qty('8'),
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

      expect(await warehouseBalance(), qty('20'));
      expect(await branchStoreBalance(), Quantity.zero());
    });

    test('reversal mempertahankan kuantitas desimal persis', () async {
      await seedWarehouseStock('3');
      final original = await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: qty('1.375'),
        movementType: StockMovementType.shipment,
        actorUserId: fixture.actor.id,
      );

      final reversal = await context.posting.postReversal(
        movementId: original.id,
        actorUserId: fixture.actor.id,
        note: 'Koreksi jumlah',
      );

      expect(reversal.qty, qty('1.375'));
      expect(reversal.qty, original.qty);
      expect(await warehouseBalance(), qty('3'));
      expect(await branchStoreBalance(), Quantity.zero());
    });

    test('movement tidak dapat dibalik dua kali', () async {
      await seedWarehouseStock('10');
      final original = await context.posting.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.branchStore.id,
        qty: qty('4'),
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
