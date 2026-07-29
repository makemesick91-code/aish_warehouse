import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
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

  Future<MasterBatch> stockBatch({
    required String batchNo,
    required int daysUntilExpiry,
    required int qty,
  }) async {
    final batch = await context.master.ensureBatch(
      itemId: fixture.expiryItem.id,
      batchNo: batchNo,
      expiryDate: utcDaysFromNow(daysUntilExpiry),
    );
    await context.posting.postInboundWarehouse(
      itemId: fixture.expiryItem.id,
      batchId: batch.id,
      toLocationId: fixture.warehouse.id,
      qty: qty,
      actorUserId: fixture.actor.id,
    );
    return batch;
  }

  test('memilih batch dengan tanggal kedaluwarsa terdekat', () async {
    final near = await stockBatch(
      batchNo: 'B-NEAR',
      daysUntilExpiry: 15,
      qty: 20,
    );
    await stockBatch(batchNo: 'B-FAR', daysUntilExpiry: 200, qty: 50);

    final allocations = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: 5,
    );

    expect(allocations, hasLength(1));
    expect(allocations.single.batchId, near.id);
    expect(allocations.single.qty, 5);
  });

  test('dapat membagi alokasi ke beberapa batch', () async {
    final near = await stockBatch(
      batchNo: 'B-NEAR',
      daysUntilExpiry: 15,
      qty: 20,
    );
    final mid = await stockBatch(
      batchNo: 'B-MID',
      daysUntilExpiry: 60,
      qty: 30,
    );
    await stockBatch(batchNo: 'B-FAR', daysUntilExpiry: 400, qty: 10);

    final allocations = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: 35,
    );

    expect(allocations, hasLength(2));
    expect(allocations[0].batchId, near.id);
    expect(allocations[0].qty, 20);
    expect(allocations[1].batchId, mid.id);
    expect(allocations[1].qty, 15);
  });

  test('mengabaikan batch yang sudah kedaluwarsa', () async {
    final soon = await stockBatch(
      batchNo: 'B-SOON',
      daysUntilExpiry: 5,
      qty: 10,
    );
    final later = await stockBatch(
      batchNo: 'B-LATER',
      daysUntilExpiry: 300,
      qty: 10,
    );

    // 30 days later B-SOON is expired and must be skipped entirely.
    final futurePosting = context.postingWithClock(
      () => DateTime.now().toUtc().add(const Duration(days: 30)),
    );

    final allocations = await futurePosting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: 10,
    );

    expect(allocations, hasLength(1));
    expect(allocations.single.batchId, later.id);
    expect(allocations.map((a) => a.batchId), isNot(contains(soon.id)));
  });

  test('menolak bila total stok valid tidak mencukupi', () async {
    await stockBatch(batchNo: 'B-1', daysUntilExpiry: 20, qty: 4);
    await stockBatch(batchNo: 'B-2', daysUntilExpiry: 40, qty: 3);

    await expectLater(
      context.posting.allocateFefo(
        locationId: fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        qty: 10,
      ),
      throwsA(isA<InsufficientStockFailure>()),
    );
  });

  test('hasil alokasi deterministik untuk expiry yang sama', () async {
    await stockBatch(batchNo: 'B-002', daysUntilExpiry: 30, qty: 5);
    await stockBatch(batchNo: 'B-001', daysUntilExpiry: 30, qty: 5);

    final first = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: 7,
    );
    final second = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: 7,
    );

    expect(first.map((a) => a.batchNo).toList(), ['B-001', 'B-002']);
    expect(
      second.map((a) => a.batchNo).toList(),
      first.map((a) => a.batchNo).toList(),
    );
    expect(second.map((a) => a.qty).toList(), first.map((a) => a.qty).toList());
  });

  test('qty tidak valid ditolak', () async {
    await expectLater(
      context.posting.allocateFefo(
        locationId: fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        qty: 0,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('FEFO tidak berlaku untuk barang tanpa kedaluwarsa', () async {
    await expectLater(
      context.posting.allocateFefo(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        qty: 1,
      ),
      throwsA(isA<BatchNotAllowedFailure>()),
    );
  });
}
