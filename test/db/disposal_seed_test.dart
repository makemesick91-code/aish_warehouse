import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The Pemusnahan demo seed (§37).
///
/// Three properties are asserted, and each is a promise a fresh install depends on:
///
/// * **Idempotent.** Running the seed twice adds nothing. Every write goes through a
///   stable `ref_doc_id` that is checked first, or through an "already seeded" lookup.
/// * **Ledger-backed.** Nothing writes `stock_balances` directly — not even the
///   expired positions, which cannot arrive through a Good Receipt because a receipt
///   refuses an expired batch (G-E4). They arrive through an opname adjustment, which
///   is the path O-7 leaves open and which still writes a real movement.
/// * **Safe when incomplete.** Every opt-in step returns `null` rather than throwing
///   when a prerequisite is missing. A seed must never be the reason a fresh install
///   fails to open.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  Future<int> disposalCount() async {
    final row = await context.database
        .customSelect('SELECT COUNT(*) AS c FROM disposals;')
        .getSingle();
    return row.read<int>('c');
  }

  Future<String?> branchStoreId() async {
    final branches = await context.master.activeBranches();
    if (branches.isEmpty) return null;
    final stores = await context.master.activeBranchStoreLocations(
      branches.first.id,
    );
    return stores.isEmpty ? null : stores.single.id;
  }

  group('stok kedaluwarsa dasar', () {
    test('run() menempatkan stok kedaluwarsa di warehouse dan ruangan', () async {
      // Both Pemusnahan screens must have something to show on a fresh install,
      // *without* any opt-in step.
      await context.seed.run();

      final warehouses = await context.master.activeWarehouseLocations();
      final warehouseExpired = await context.disposals.expiredPositions(
        sourceLocationId: warehouses.single.id,
        nowUtc: DateTime.now().toUtc(),
      );
      expect(warehouseExpired, isNotEmpty);

      final rooms = await context.master.activeRooms();
      var roomExpiredTotal = 0;
      for (final room in rooms) {
        final location = await context.master.activeRoomLocation(room.id);
        if (location == null) continue;
        roomExpiredTotal += (await context.disposals.expiredPositions(
          sourceLocationId: location.id,
          nowUtc: DateTime.now().toUtc(),
        )).length;
      }
      expect(roomExpiredTotal, greaterThan(0));
    });

    test('run() membiarkan Gudang Cabang kosong', () async {
      // Milestone 6 relies on this: the branch store's first stock arrives through a
      // posted Good Receipt (spec §2.5), and stocking it in `run()` would quietly
      // make that assertion about a shelf somebody else had already filled.
      await context.seed.run();
      final store = await branchStoreId();
      expect(await context.balancesAt(store!), isEmpty);
    });

    test('stok kedaluwarsa Gudang Cabang bersifat opt-in', () async {
      await context.seed.run();
      final store = await branchStoreId();

      await context.seed.seedExpiredBranchStoreStock();

      final expired = await context.disposals.expiredPositions(
        sourceLocationId: store!,
        nowUtc: DateTime.now().toUtc(),
      );
      expect(expired, isNotEmpty);
    });

    test(
      'stok Gudang Cabang mencakup kedaluwarsa, segera dan masih berlaku',
      () async {
        // Between them a fresh install shows the whole eligibility rule without anybody
        // having to construct it by hand.
        await context.seed.run();
        await context.seed.seedExpiredBranchStoreStock();
        final store = await branchStoreId();

        final balances = await context.balancesAt(store!);
        expect(balances.length, greaterThanOrEqualTo(3));

        final expired = await context.disposals.expiredPositions(
          sourceLocationId: store,
          nowUtc: DateTime.now().toUtc(),
        );
        // Strictly fewer than the shelf holds: the near-expiry and valid batches must
        // not be candidates.
        expect(expired.length, lessThan(balances.length));
      },
    );

    test('setiap saldo didukung movement ledger', () async {
      await context.seed.run();
      await context.seed.seedExpiredBranchStoreStock();

      final orphans = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM stock_balances b '
            'WHERE NOT EXISTS ('
            '  SELECT 1 FROM stock_movements m '
            '  WHERE m.item_id = b.item_id '
            '    AND (m.batch_id IS b.batch_id) '
            '    AND (m.from_location_id = b.location_id '
            '         OR m.to_location_id = b.location_id)'
            ');',
          )
          .getSingle();
      expect(
        orphans.read<int>('c'),
        0,
        reason:
            'Ada saldo tanpa movement — seed menulis stock_balances langsung.',
      );
    });

    test('menjalankan dua kali tidak menggandakan saldo', () async {
      await context.seed.run();
      await context.seed.seedExpiredBranchStoreStock();
      final store = await branchStoreId();
      final first = await context.balancesAt(store!);

      await context.seed.seedExpiredBranchStoreStock();
      expect(await context.balancesAt(store), first);
    });
  });

  group('draft', () {
    test('membuat draft cabang dengan alasan yang dapat dibaca', () async {
      await context.seed.run();
      final id = await context.seed.seedDraftDisposal();
      expect(id, isNotNull);

      final disposal = await context.disposals.getById(id!);
      expect(disposal!.isDraft, isTrue);
      // §19: what goes in the column is a sentence, never a preset code.
      expect(disposal.reason, 'Pembersihan stok lama — seed pengembangan');
      expect(disposal.reason, isNot(contains('cleanup')));
      expect(disposal.docNumber, startsWith('TMP-DSP-'));
    });

    test('draft memakai Gudang Cabang sebagai sumber', () async {
      await context.seed.run();
      final id = await context.seed.seedDraftDisposal();
      final store = await branchStoreId();

      expect((await context.disposals.getById(id!))!.sourceLocationId, store);
    });

    test(
      'setiap baris draft menunjuk batch yang benar-benar kedaluwarsa',
      () async {
        await context.seed.run();
        final id = await context.seed.seedDraftDisposal();

        final detail = await context.disposals.getDetail(id!);
        expect(detail!.lines, isNotEmpty);
        final nowUtc = DateTime.now().toUtc();
        for (final line in detail.lines) {
          expect(
            line.isExpiredOn(nowUtc),
            isTrue,
            reason: 'Baris seed menunjuk batch yang belum kedaluwarsa.',
          );
          expect(line.qty.isPositive, isTrue);
        }
      },
    );

    test('draft tidak menghabiskan seluruh stok demo', () async {
      // The *Stok Kedaluwarsa* tab must still have rows after the demo document is
      // posted, or the screen it is demonstrating looks broken.
      await context.seed.run();
      await context.seed.seedPostedDisposal();
      final store = await branchStoreId();

      final remaining = await context.disposals.expiredPositions(
        sourceLocationId: store!,
        nowUtc: DateTime.now().toUtc(),
      );
      expect(remaining, isNotEmpty);
    });

    test('menjalankan dua kali tidak membuat dokumen kedua', () async {
      await context.seed.run();
      final first = await context.seed.seedDraftDisposal();
      final second = await context.seed.seedDraftDisposal();

      expect(second, first);
      expect(await disposalCount(), 1);
    });

    test('draft warehouse memakai Warehouse Pusat', () async {
      await context.seed.run();
      final id = await context.seed.seedWarehouseDraftDisposal();
      expect(id, isNotNull);

      final warehouses = await context.master.activeWarehouseLocations();
      final disposal = await context.disposals.getById(id!);
      expect(disposal!.sourceLocationId, warehouses.single.id);
      expect(disposal.createdBy, isNotEmpty);
    });

    test('draft warehouse idempoten', () async {
      await context.seed.run();
      final first = await context.seed.seedWarehouseDraftDisposal();
      expect(await context.seed.seedWarehouseDraftDisposal(), first);
    });

    test('run() sendiri tidak membuat dokumen apa pun', () async {
      // A developer exercising the empty state needs one that stays empty.
      await context.seed.run();
      expect(await disposalCount(), 0);
    });
  });

  group('posted', () {
    test('memposting lewat use case, bukan mutasi saldo', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedDisposal();
      expect(id, isNotNull);

      final disposal = await context.disposals.getById(id!);
      expect(disposal!.isPosted, isTrue);
      expect(disposal.postedBy, isNotNull);
      expect(disposal.postedAt, isNotNull);

      // Real movements carrying the reason and the actor G-E7 demands.
      final movements = await context.disposalMovements(id);
      expect(movements, isNotEmpty);
      for (final movement in movements) {
        expect(movement['movement_type'], 'disposal');
        expect(movement['to_location_id'], isNull);
        expect(movement['ref_doc_type'], 'DSP');
        expect((movement['note'] as String?)?.trim(), isNotEmpty);
      }
    });

    test('saldo sumber berkurang tepat sejumlah baris', () async {
      await context.seed.run();
      await context.seed.seedExpiredBranchStoreStock();
      final store = await branchStoreId();
      final before = await context.balancesAt(store!);

      final id = await context.seed.seedPostedDisposal();
      final lines = await context.disposalLineRows(id!);
      final after = await context.balancesAt(store);

      var totalDestroyed = 0;
      for (final line in lines.values) {
        totalDestroyed += line['qty']! as int;
      }
      final beforeTotal = before.values.fold<int>(0, (sum, qty) => sum + qty);
      final afterTotal = after.values.fold<int>(0, (sum, qty) => sum + qty);
      expect(beforeTotal - afterTotal, totalDestroyed);
    });

    test('menjalankan dua kali tidak memposting ulang', () async {
      await context.seed.run();
      final first = await context.seed.seedPostedDisposal();
      final movementsBefore = await context.disposalMovementCount(first!);

      expect(await context.seed.seedPostedDisposal(), first);
      expect(await context.disposalMovementCount(first), movementsBefore);
    });
  });

  group('prasyarat dan build', () {
    test('mengembalikan null tanpa master data', () async {
      // No branch, no users, no shelf. Nothing throws.
      expect(await context.seed.seedDraftDisposal(), isNull);
      expect(await context.seed.seedPostedDisposal(), isNull);
      expect(await context.seed.seedWarehouseDraftDisposal(), isNull);
    });

    test('stok Gudang Cabang aman dipanggil tanpa master data', () async {
      await context.seed.seedExpiredBranchStoreStock();
      expect(await disposalCount(), 0);
    });

    test('build produksi menolak seed', () async {
      expect(
        () => context.productionSeed.seedDraftDisposal(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => context.productionSeed.seedPostedDisposal(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => context.productionSeed.seedWarehouseDraftDisposal(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => context.productionSeed.seedExpiredBranchStoreStock(),
        throwsA(isA<StateError>()),
      );
    });

    test('foreign_key_check bersih setelah seluruh seed', () async {
      await context.seed.run();
      await context.seed.seedPostedDisposal();
      await context.seed.seedWarehouseDraftDisposal();

      final violations = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });

    test('tidak ada saldo negatif setelah seluruh seed', () async {
      await context.seed.run();
      await context.seed.seedPostedDisposal();

      final negatives = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM stock_balances WHERE qty_on_hand < 0;',
          )
          .getSingle();
      expect(negatives.read<int>('c'), 0);
    });

    test('kuantitas desimal tersimpan sebagai milli-unit yang eksak', () async {
      await context.seed.run();
      await context.seed.seedExpiredBranchStoreStock();
      final store = await branchStoreId();

      final balances = await context.balancesAt(store!);
      // `1.25` and `0.75` are in the seed precisely so the fixed-point path is
      // exercised rather than integer arithmetic that would work either way.
      expect(balances.values, contains(Quantity.parse('1.25').milliUnits));
      expect(balances.values, contains(Quantity.parse('0.75').milliUnits));
    });

    test(
      'tidak ada movement disposal sebelum seed opt-in dijalankan',
      () async {
        await context.seed.run();
        expect(
          await context.movementCountOfType(StockMovementType.disposal),
          0,
        );
      },
    );
  });
}
