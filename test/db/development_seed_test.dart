import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/operational_iso_week.dart';
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

  group('saldo ruangan untuk Stok Opname', () {
    test('ruang dental 1 memiliki saldo awal siap dihitung', () async {
      await context.seed.run();

      final room = (await context.master.activeRooms()).firstWhere(
        (room) => room.code == 'R1',
      );
      final location = await context.master.activeRoomLocation(room.id);
      expect(location, isNotNull);

      final balances = await context.inventory.balancesAtLocation(location!.id);
      expect(balances, isNotEmpty);
      // Both kinds of position, which is what makes the snapshot interesting.
      expect(balances.any((b) => b.batchId == null), isTrue);
      expect(balances.any((b) => b.batchId != null), isTrue);
    });

    test('saldo ruangan menyertakan kuantitas desimal', () async {
      await context.seed.run();

      final room = (await context.master.activeRooms()).firstWhere(
        (room) => room.code == 'R1',
      );
      final location = await context.master.activeRoomLocation(room.id);
      final balances = await context.inventory.balancesAtLocation(location!.id);

      final gloves = balances.firstWhere((b) => b.sku == 'DEN-0004');
      expect(gloves.qtyOnHand, Quantity.parse('4.5'));
      expect(gloves.qtyOnHand.format(), '4.5');

      // R1 holds the anaesthetic across **two** batches since Milestone 8 seeded a
      // near-expiry one beside the valid one (§36), so the assertion names the batch
      // rather than taking whichever row came back first — `firstWhere` on the SKU alone
      // would pass or fail on query order.
      final anaesthetic = balances.where((b) => b.sku == 'DEN-0007');
      expect(anaesthetic, hasLength(2));
      expect(
        anaesthetic.firstWhere((b) => b.batchNo == 'LID-2407').qtyOnHand,
        Quantity.parse('12.5'),
      );
      expect(
        anaesthetic.firstWhere((b) => b.batchNo == 'LID-2403').qtyOnHand,
        Quantity.parse('4.5'),
      );
    });

    test('terdapat batch kedaluwarsa yang tetap dapat dihitung', () async {
      await context.seed.run();

      final room = (await context.master.activeRooms()).firstWhere(
        (room) => room.code == 'R1',
      );
      final location = await context.master.activeRoomLocation(room.id);
      final balances = await context.inventory.balancesAtLocation(location!.id);

      final now = DateTime.now().toUtc();
      final expired = balances.where((b) => b.isExpiredOn(now));
      expect(
        expired,
        isNotEmpty,
        reason:
            'Stok opname harus bisa melaporkan barang kedaluwarsa yang masih '
            'ada di ruangan (G-E7).',
      );
      expect(expired.first.batchNo, 'CHX-2301');
      expect(expired.first.qtyOnHand, Quantity.parse('0.5'));
    });

    test('saldo ruangan idempoten pada seed kedua', () async {
      await context.seed.run();
      final first = await _countMovements(context);

      await context.seed.run();

      expect(await _countMovements(context), first);
    });

    test('saldo ruangan selalu berasal dari ledger', () async {
      await context.seed.run();

      final room = (await context.master.activeRooms()).firstWhere(
        (room) => room.code == 'R1',
      );
      final location = await context.master.activeRoomLocation(room.id);
      final balances = await context.inventory.balancesAtLocation(location!.id);

      for (final balance in balances) {
        final movements = await context.inventory.stockCard(
          itemId: balance.itemId,
          locationId: location.id,
        );
        expect(
          movements,
          isNotEmpty,
          reason: 'stock_balances tidak boleh ditulis tanpa movement (G-A1).',
        );
      }
    });
  });

  group('data demo Purchase Request', () {
    test('seed memfile opname acuan untuk jendela G-P1', () async {
      await context.seed.run();

      final rows = await context.database
          .customSelect(
            'SELECT o.status, o.period_year, o.period_week, r.code AS room '
            'FROM stock_opnames o JOIN rooms r ON r.id = o.room_id '
            'WHERE o.deleted_at IS NULL;',
          )
          .get();

      // Two current-week counts from different rooms, one from the previous week, and
      // one deliberately outside the window (§28).
      expect(rows, hasLength(4));
      expect(
        rows.map((row) => row.read<String>('status')).toSet(),
        {'submitted'},
        reason: 'Acuan harus sudah diserahkan agar dapat dikutip (G-O4).',
      );

      final current = OperationalIsoWeek.ofUtcInstant(DateTime.now().toUtc());
      final periods = rows
          .map(
            (row) => OperationalIsoWeek(
              year: row.read<int>('period_year'),
              week: row.read<int>('period_week'),
            ),
          )
          .toList(growable: false);

      final distances = periods.map(current.weeksAfter).toList(growable: false)
        ..sort();
      expect(
        distances,
        [0, 0, 1, 3],
        reason:
            'Dua minggu berjalan, satu minggu sebelumnya, satu terlalu tua '
            'untuk mendemonstrasikan batas G-P1.',
      );

      // The two current-week counts come from different rooms, so a Purchase Request
      // can demonstrate the multi-room aggregate.
      final currentRooms = <String>{
        for (final row in rows)
          if (current.weeksAfter(
                OperationalIsoWeek(
                  year: row.read<int>('period_year'),
                  week: row.read<int>('period_week'),
                ),
              ) ==
              0)
            row.read<String>('room'),
      };
      expect(currentRooms, hasLength(2));
    });

    test('acuan seed menghasilkan saran desimal dan kandidat manual', () async {
      await context.seed.run();

      final head = (await context.master.activeUsers()).firstWhere(
        (user) => user.role == UserRole.kepalaCabang,
      );
      final eligible = await context.eligibleOpnamesFor(
        branchId: head.branchId!,
        utcNow: DateTime.now().toUtc(),
      );
      expect(eligible, hasLength(3), reason: 'Tiga acuan berada di jendela.');

      final request = await context.createPurchaseRequest().call(
        actorUserId: head.id,
        selectedOpnameIds: eligible
            .map((reference) => reference.opnameId)
            .toList(growable: false),
      );
      final detail = await context.requests.getDetail(request.id);
      final bySku = {for (final line in detail!.lines) line.sku: line};

      // DEN-0004: par 5/room, R1 holds 4.5 and R2 holds 3 → 0.5 + 2 = 2.5 box.
      expect(bySku['DEN-0004']!.suggestedQty, Quantity.parse('2.5'));
      // DEN-0007: par 10/room, R2 holds two batches of 2 → summed to 4 before the par
      // comparison, so 6 ampul rather than 8 + 8.
      expect(bySku['DEN-0007']!.suggestedQty, Quantity.parse('6'));
      // DEN-0005: R1 holds 120 against a par of 50, so nothing is suggested — which is
      // what makes it the position a manual request is demonstrated against.
      expect(bySku.containsKey('DEN-0005'), isFalse);
    });

    test(
      'seed utama tidak mengirim PR, agar demo membuat bisa dijalankan',
      () async {
        await context.seed.run();

        final rows = await context.database
            .customSelect('SELECT COUNT(*) AS c FROM purchase_requests;')
            .getSingle();
        expect(
          rows.read<int>('c'),
          0,
          reason:
              'PR submitted akan menempati slot aktif cabang (G-P4) dan menolak '
              'hal pertama yang dicoba pengembang.',
        );
      },
    );

    test('demo PR submitted tersedia sebagai langkah terpisah', () async {
      await context.seed.run();

      final prId = await context.seed.seedSubmittedPurchaseRequest();
      expect(prId, isNotNull);
      expect(await context.purchaseRequestStatusOf(prId!), 'submitted');

      final head = (await context.master.activeUsers()).firstWhere(
        (user) => user.role == UserRole.kepalaCabang,
      );
      // Idempotent: the branch now holds its one active order, so a second call is a
      // no-op rather than a constraint violation.
      expect(await context.seed.seedSubmittedPurchaseRequest(), isNull);
      expect(await context.activePurchaseRequestCount(head.branchId!), 1);
    });

    test('seed kedua tidak menduplikasi opname acuan', () async {
      await context.seed.run();
      await context.seed.run();

      final rows = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM stock_opnames WHERE deleted_at IS NULL;',
          )
          .getSingle();
      expect(
        rows.read<int>('c'),
        4,
        reason:
            'G-O1 menolak opname kedua per ruangan per minggu; seed melewatinya.',
      );
    });

    test('seed menyediakan Kepala Cabang dan Warehouse aktif', () async {
      await context.seed.run();

      final users = await context.master.activeUsers();
      expect(
        users.where((user) => user.role == UserRole.kepalaCabang),
        isNotEmpty,
      );
      expect(
        users.where((user) => user.role == UserRole.warehouse),
        isNotEmpty,
      );
      // The branch head must actually be attached to a branch, or nothing in the
      // Purchase Request workflow is reachable.
      expect(
        users.firstWhere((user) => user.role == UserRole.kepalaCabang).branchId,
        isNotNull,
      );
    });
  });
}

Future<int> _countMovements(TestContext context) async {
  final row = await context.database
      .customSelect('SELECT COUNT(*) AS total FROM stock_movements;')
      .getSingle();
  return row.read<int>('total');
}
