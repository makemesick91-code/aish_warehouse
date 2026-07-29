import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

void main() {
  late TestContext context;

  setUp(() {
    context = TestContext.create();
  });

  tearDown(() => context.dispose());

  test('seed membuat master data dan saldo awal', () async {
    expect(await context.seed.isSeeded(), isFalse);

    await context.seed.run();

    final summary = await context.master.summary();
    expect(summary.branches, 1);
    expect(summary.rooms, 3);
    expect(summary.categories, greaterThanOrEqualTo(4));
    expect(summary.items, greaterThanOrEqualTo(10));
    expect(summary.users, 4);
    // 1 warehouse + 1 branch store + 3 rooms.
    expect(summary.locations, 5);
    expect(await context.seed.isSeeded(), isTrue);

    final warehouse = await context.master.warehouseLocation();
    expect(warehouse, isNotNull);

    final balances = await context.inventory.balancesAtLocation(warehouse!.id);
    expect(balances, isNotEmpty);
    expect(balances.any((b) => b.hasExpiry && b.batchId != null), isTrue);
    expect(balances.any((b) => !b.hasExpiry && b.batchId == null), isTrue);
  });

  test('seed menyertakan saldo desimal yang tampil tanpa artefak', () async {
    await context.seed.run();

    final warehouse = (await context.master.warehouseLocation())!;
    final balances = await context.inventory.balancesAtLocation(warehouse.id);

    final gloves = balances.firstWhere((b) => b.sku == 'DEN-0004');
    expect(gloves.qtyOnHand, Quantity.parse('10.5'));
    expect(gloves.qtyOnHand.formatWithUnit(gloves.unit), '10.5 box');

    final antiseptic = balances.firstWhere((b) => b.sku == 'DEN-0008');
    expect(antiseptic.qtyOnHand, Quantity.parse('0.5'));
    expect(antiseptic.qtyOnHand.formatWithUnit(antiseptic.unit), '0.5 botol');

    final bonding = balances.firstWhere((b) => b.sku == 'DEN-0003');
    expect(bonding.qtyOnHand, Quantity.parse('2.375'));
    expect(bonding.qtyOnHand.format(), '2.375');

    // Whole balances must not gain a decimal tail.
    final mask = balances.firstWhere((b) => b.sku == 'DEN-0009');
    expect(mask.qtyOnHand.format(), '150');
    for (final balance in balances) {
      expect(balance.qtyOnHand.format(), isNot(endsWith('.0')));
    }
  });

  test('saldo desimal tetap idempoten setelah seed kedua', () async {
    await context.seed.run();
    await context.seed.run();

    final warehouse = (await context.master.warehouseLocation())!;
    final balances = await context.inventory.balancesAtLocation(warehouse.id);

    expect(
      balances.firstWhere((b) => b.sku == 'DEN-0004').qtyOnHand,
      Quantity.parse('10.5'),
    );
    expect(
      balances.firstWhere((b) => b.sku == 'DEN-0008').qtyOnHand,
      Quantity.parse('0.5'),
    );
    expect(
      balances.firstWhere((b) => b.sku == 'DEN-0003').qtyOnHand,
      Quantity.parse('2.375'),
    );
  });

  test('saldo awal selalu memiliki movement ledger', () async {
    await context.seed.run();

    final warehouse = (await context.master.warehouseLocation())!;
    final balances = await context.inventory.balancesAtLocation(warehouse.id);

    for (final balance in balances) {
      final movements = await context.inventory.stockCard(
        itemId: balance.itemId,
        locationId: warehouse.id,
      );
      expect(
        movements.where(
          (m) => m.movementType == StockMovementType.inboundWarehouse,
        ),
        isNotEmpty,
        reason: 'Saldo ${balance.sku} harus berasal dari ledger',
      );
    }
  });

  test('seed idempoten: dijalankan dua kali tanpa duplikasi', () async {
    await context.seed.run();

    final summaryAfterFirst = await context.master.summary();
    final warehouse = (await context.master.warehouseLocation())!;
    final balancesAfterFirst = await context.inventory.balancesAtLocation(
      warehouse.id,
    );
    final movementCountAfterFirst = await _countMovements(context);

    await context.seed.run();

    final summaryAfterSecond = await context.master.summary();
    final balancesAfterSecond = await context.inventory.balancesAtLocation(
      warehouse.id,
    );

    expect(summaryAfterSecond.branches, summaryAfterFirst.branches);
    expect(summaryAfterSecond.rooms, summaryAfterFirst.rooms);
    expect(summaryAfterSecond.items, summaryAfterFirst.items);
    expect(summaryAfterSecond.categories, summaryAfterFirst.categories);
    expect(summaryAfterSecond.users, summaryAfterFirst.users);
    expect(summaryAfterSecond.locations, summaryAfterFirst.locations);

    expect(balancesAfterSecond.length, balancesAfterFirst.length);
    for (var i = 0; i < balancesAfterFirst.length; i++) {
      expect(
        balancesAfterSecond[i].qtyOnHand,
        balancesAfterFirst[i].qtyOnHand,
        reason: 'Saldo ${balancesAfterFirst[i].sku} tidak boleh berubah',
      );
    }
    expect(await _countMovements(context), movementCountAfterFirst);
  });

  test('seed ditolak pada build produksi', () async {
    await expectLater(context.productionSeed.run(), throwsA(isA<StateError>()));

    final summary = await context.master.summary();
    expect(summary.isEmpty, isTrue);
  });
}

Future<int> _countMovements(TestContext context) async {
  final row = await context.database
      .customSelect('SELECT COUNT(*) AS total FROM stock_movements;')
      .getSingle();
  return row.read<int>('total');
}
