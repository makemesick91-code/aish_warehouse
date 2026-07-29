import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
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

  Quantity qty(String value) => Quantity.parse(value);

  Future<MasterBatch> stockBatch({
    required String batchNo,
    required int daysUntilExpiry,
    required String qty,
  }) async {
    final batch = await context.master.ensureBatch(
      itemId: fixture.expiryItem.id,
      batchNo: batchNo,
      expiryDate: expiryDateInDays(daysUntilExpiry),
    );
    await context.posting.postInboundWarehouse(
      itemId: fixture.expiryItem.id,
      batchId: batch.id,
      toLocationId: fixture.warehouse.id,
      qty: Quantity.parse(qty),
      actorUserId: fixture.actor.id,
    );
    return batch;
  }

  test('memilih batch dengan tanggal kedaluwarsa terdekat', () async {
    final near = await stockBatch(
      batchNo: 'B-NEAR',
      daysUntilExpiry: 15,
      qty: '20',
    );
    await stockBatch(batchNo: 'B-FAR', daysUntilExpiry: 200, qty: '50');

    final allocations = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: qty('5'),
    );

    expect(allocations, hasLength(1));
    expect(allocations.single.batchId, near.id);
    expect(allocations.single.qty, qty('5'));
  });

  test('dapat membagi alokasi ke beberapa batch', () async {
    final near = await stockBatch(
      batchNo: 'B-NEAR',
      daysUntilExpiry: 15,
      qty: '20',
    );
    final mid = await stockBatch(
      batchNo: 'B-MID',
      daysUntilExpiry: 60,
      qty: '30',
    );
    await stockBatch(batchNo: 'B-FAR', daysUntilExpiry: 400, qty: '10');

    final allocations = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: qty('35'),
    );

    expect(allocations, hasLength(2));
    expect(allocations[0].batchId, near.id);
    expect(allocations[0].qty, qty('20'));
    expect(allocations[1].batchId, mid.id);
    expect(allocations[1].qty, qty('15'));
  });

  test('mengalokasikan kuantitas desimal dari satu batch', () async {
    final near = await stockBatch(
      batchNo: 'B-DEC',
      daysUntilExpiry: 20,
      qty: '2.5',
    );

    final allocations = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: qty('0.75'),
    );

    expect(allocations, hasLength(1));
    expect(allocations.single.batchId, near.id);
    expect(allocations.single.qty, qty('0.75'));
    expect(allocations.single.qty.format(), '0.75');
  });

  test('membagi 1.5 ke beberapa batch tanpa selisih', () async {
    final near = await stockBatch(
      batchNo: 'B-A',
      daysUntilExpiry: 10,
      qty: '0.5',
    );
    final mid = await stockBatch(
      batchNo: 'B-B',
      daysUntilExpiry: 20,
      qty: '0.25',
    );
    final far = await stockBatch(batchNo: 'B-C', daysUntilExpiry: 30, qty: '5');

    final requested = qty('1.5');
    final allocations = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: requested,
    );

    expect(allocations, hasLength(3));
    expect(allocations[0].batchId, near.id);
    expect(allocations[0].qty, qty('0.5'));
    expect(allocations[1].batchId, mid.id);
    expect(allocations[1].qty, qty('0.25'));
    expect(allocations[2].batchId, far.id);
    expect(allocations[2].qty, qty('0.75'));

    // The whole point: the parts add back up to exactly what was asked for.
    final total = Quantity.sum(allocations.map((a) => a.qty));
    expect(total, requested);
    expect(total.format(), '1.5');
  });

  test('alokasi desimal lintas batch tidak menyisakan pecahan', () async {
    await stockBatch(batchNo: 'B-1', daysUntilExpiry: 10, qty: '0.1');
    await stockBatch(batchNo: 'B-2', daysUntilExpiry: 20, qty: '0.1');
    await stockBatch(batchNo: 'B-3', daysUntilExpiry: 30, qty: '0.1');

    final allocations = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: qty('0.3'),
    );

    expect(Quantity.sum(allocations.map((a) => a.qty)), qty('0.3'));
    expect(Quantity.sum(allocations.map((a) => a.qty)).format(), '0.3');
  });

  test('mengabaikan batch yang sudah kedaluwarsa', () async {
    final soon = await stockBatch(
      batchNo: 'B-SOON',
      daysUntilExpiry: 5,
      qty: '10',
    );
    final later = await stockBatch(
      batchNo: 'B-LATER',
      daysUntilExpiry: 300,
      qty: '10',
    );

    // 30 days later B-SOON is expired and must be skipped entirely.
    final futurePosting = context.postingWithClock(
      () => DateTime.now().toUtc().add(const Duration(days: 30)),
    );

    final allocations = await futurePosting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: qty('10'),
    );

    expect(allocations, hasLength(1));
    expect(allocations.single.batchId, later.id);
    expect(allocations.map((a) => a.batchId), isNot(contains(soon.id)));
  });

  test('menolak bila total stok valid tidak mencukupi', () async {
    await stockBatch(batchNo: 'B-1', daysUntilExpiry: 20, qty: '4');
    await stockBatch(batchNo: 'B-2', daysUntilExpiry: 40, qty: '3');

    await expectLater(
      context.posting.allocateFefo(
        locationId: fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        qty: qty('10'),
      ),
      throwsA(
        isA<InsufficientStockFailure>()
            .having((f) => f.available, 'available', qty('7'))
            .having((f) => f.requested, 'requested', qty('10')),
      ),
    );
  });

  test('menolak permintaan desimal yang melebihi stok', () async {
    await stockBatch(batchNo: 'B-1', daysUntilExpiry: 20, qty: '0.5');

    await expectLater(
      context.posting.allocateFefo(
        locationId: fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        qty: qty('0.501'),
      ),
      throwsA(isA<InsufficientStockFailure>()),
    );
  });

  test('hasil alokasi deterministik untuk expiry yang sama', () async {
    await stockBatch(batchNo: 'B-002', daysUntilExpiry: 30, qty: '5');
    await stockBatch(batchNo: 'B-001', daysUntilExpiry: 30, qty: '5');

    final first = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: qty('7'),
    );
    final second = await context.posting.allocateFefo(
      locationId: fixture.warehouse.id,
      itemId: fixture.expiryItem.id,
      qty: qty('7'),
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
        qty: Quantity.zero(),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('FEFO tidak berlaku untuk barang tanpa kedaluwarsa', () async {
    await expectLater(
      context.posting.allocateFefo(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        qty: qty('1'),
      ),
      throwsA(isA<BatchNotAllowedFailure>()),
    );
  });
}
