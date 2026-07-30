import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The Distribusi development seed (§35).
///
/// Two properties matter more than the demo data itself:
///
/// * **idempotence.** A second run must be a no-op rather than the start of a second
///   chain, because the seed button is on the development home page and gets pressed
///   twice.
/// * **it obeys the same rules the screens do.** Every balance it produces arrives
///   through the ledger, the posted document goes through `PostDistributionUseCase`, and
///   nothing it writes could not have been written by a branch head. A seed that took a
///   shortcut would be a fixture that proves the wrong thing on every fresh install.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  Future<int> distributionCount() async {
    final row = await context.database
        .customSelect('SELECT COUNT(*) AS c FROM distributions;')
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> distributionLineTotal() async {
    final row = await context.database
        .customSelect(
          'SELECT COUNT(*) AS c FROM distribution_lines '
          'WHERE deleted_at IS NULL;',
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<String?> branchStoreId() async {
    final branches = await context.master.activeBranches();
    if (branches.isEmpty) return null;
    final stores = await context.master.activeBranchStoreLocations(
      branches.first.id,
    );
    return stores.length == 1 ? stores.single.id : null;
  }

  group('draft', () {
    test('menghasilkan draft multi-ruangan', () async {
      await context.seed.run();
      final id = await context.seed.seedDraftDistribution();

      expect(id, isNotNull);
      expect(await context.distributionStatusOf(id!), 'draft');

      final detail = await context.distributions.getDetail(id);
      expect(detail, isNotNull);
      expect(detail!.isEmpty, isFalse);
      // G-T3 has to be visible on a fresh install, not merely supported.
      expect(detail.roomCount, greaterThanOrEqualTo(2));
      expect(detail.lineCount, greaterThanOrEqualTo(2));
    });

    test('tidak memindahkan stok', () async {
      await context.seed.run();
      await context.seed.seedPostedGoodReceipt();
      final store = await branchStoreId();
      final before = await context.balancesAt(store!);

      final id = await context.seed.seedDraftDistribution();
      expect(id, isNotNull);

      // A draft is an intention; the balances move when it is posted (§18).
      expect(await context.balancesAt(store), before);
      expect(await context.distributionMovementCount(id!), 0);
    });

    test('menyisakan stok di gudang cabang', () async {
      // §35: an emptied store makes every other screen look broken, so the demo takes a
      // share rather than everything.
      await context.seed.run();
      await context.seed.seedPostedDistribution();

      final store = await branchStoreId();
      final balances = await context.balancesAt(store!);
      expect(balances, isNotEmpty);
      expect(
        balances.values.any((qty) => qty > 0),
        isTrue,
        reason: 'Seed menghabiskan seluruh stok gudang cabang.',
      );
    });

    test('idempoten: dua kali menghasilkan satu dokumen', () async {
      await context.seed.run();
      final first = await context.seed.seedDraftDistribution();
      final second = await context.seed.seedDraftDistribution();

      expect(first, isNotNull);
      expect(second, first);
      expect(await distributionCount(), 1);
    });

    test('idempoten setelah dokumen diposting', () async {
      // The status-agnostic lookup is what makes this a no-op rather than the start of a
      // second chain: a *posted* document still counts as "already seeded".
      await context.seed.run();
      final posted = await context.seed.seedPostedDistribution();
      expect(posted, isNotNull);

      final again = await context.seed.seedDraftDistribution();
      expect(again, posted);
      expect(await distributionCount(), 1);
    });

    test('tanpa master data tidak menghasilkan apa pun', () async {
      // A seed must never be the reason a fresh install fails to open.
      expect(await context.seed.seedDraftDistribution(), isNull);
      expect(await distributionCount(), 0);
    });
  });

  group('posted', () {
    test('memposting melalui use case dan menulis ledger', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedDistribution();

      expect(id, isNotNull);
      expect(await context.distributionStatusOf(id!), 'posted');
      expect(await context.distributionColumn(id, 'posted_at'), isNotNull);

      // Real `distribution` movements, one per line — never a direct balance write
      // (G-A1).
      final movements = await context.distributionMovements(id);
      expect(movements, hasLength(await distributionLineTotal()));
      for (final movement in movements) {
        expect(movement['movement_type'], 'distribution');
        expect(movement['ref_doc_type'], 'DIST');
        expect(movement['ref_doc_id'], id);
        expect(movement['from_location_id'], isNotNull);
        expect(movement['to_location_id'], isNotNull);
      }
    });

    test('saldo ruangan bertambah sesuai dokumen', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedDistribution();
      final detail = await context.distributions.getDetail(id!);

      for (final group in detail!.roomGroups) {
        final locations = await context.master.activeRoomLocations(
          group.roomId,
        );
        expect(locations, hasLength(1));
        for (final line in group.lines) {
          final onHand = await context.inventory.balanceQty(
            locationId: locations.single.id,
            itemId: line.itemId,
            batchId: line.batchId,
          );
          expect(
            onHand >= line.qty,
            isTrue,
            reason:
                'Ruangan ${group.roomCode} tidak menerima ${line.sku} '
                'sebanyak ${line.qty.format()}.',
          );
        }
      }
    });

    test('total keluar sama dengan total masuk', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedDistribution();

      final movements = await context.distributionMovements(id!);
      final out = movements.fold<int>(
        0,
        (sum, movement) => sum + (movement['qty'] as int),
      );
      // Every movement is two-sided, so what left the store is exactly what arrived.
      expect(out, greaterThan(0));
      final detail = await context.distributions.getDetail(id);
      expect(
        out,
        detail!.lines.fold<int>(0, (sum, line) => sum + line.qty.milliUnits),
      );
    });

    test('idempoten: dua kali tidak memposting dua kali', () async {
      await context.seed.run();
      final first = await context.seed.seedPostedDistribution();
      final movements = await context.distributionMovementCount(first!);

      final second = await context.seed.seedPostedDistribution();
      expect(second, first);
      expect(await context.distributionMovementCount(first), movements);
      expect(await distributionCount(), 1);
    });

    test('tidak mendistribusikan batch kedaluwarsa', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedDistribution();
      final detail = await context.distributions.getDetail(id!);
      final nowUtc = DateTime.now().toUtc();

      // G-E4 applies to the seed too: it is not exempt from a rule the screens enforce.
      for (final line in detail!.lines) {
        expect(
          line.isExpiredOn(nowUtc),
          isFalse,
          reason: '${line.sku} batch ${line.batchNo} sudah kedaluwarsa.',
        );
      }
    });

    test('seluruh baris mengikuti FEFO atau menyimpan alasan', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedDistribution();
      final detail = await context.distributions.getDetail(id!);

      // The seed uses the automatic path, so nothing it writes should need a reason —
      // and if a future change makes one necessary, the use case would have refused
      // rather than stored a line without one.
      for (final line in detail!.lines) {
        if (line.hasFefoOverride) {
          expect(line.fefoOverrideReason!.trim(), isNotEmpty);
        }
      }
    });

    test('tidak dijalankan oleh run() sehingga draft tetap ada', () async {
      // A fresh install should show both shapes: a draft to continue *and* a posted
      // document to read. Posting the only draft would leave the form with nothing to
      // open, which is why the two are separate opt-in steps.
      await context.seed.run();
      expect(await distributionCount(), 0);
    });

    test('build produksi menolak seed', () async {
      expect(
        () => context.productionSeed.seedDraftDistribution(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => context.productionSeed.seedPostedDistribution(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('prasyarat', () {
    test('gudang cabang distok melalui Good Receipt', () async {
      await context.seed.run();
      final store = await branchStoreId();
      expect(await context.balancesAt(store!), isEmpty);

      // The store's only legitimate source (spec §2.5): the distribution seed posts the
      // receipt itself rather than writing balances.
      await context.seed.seedDraftDistribution();
      expect(await context.balancesAt(store), isNotEmpty);

      final receipts = await context.database
          .customSelect(
            "SELECT COUNT(*) AS c FROM stock_movements "
            "WHERE movement_type = 'good_receipt';",
          )
          .getSingle();
      expect(receipts.read<int>('c'), greaterThan(0));
    });

    test('dokumen milik cabang dan Kepala Cabang yang tersedia', () async {
      await context.seed.run();
      final id = await context.seed.seedDraftDistribution();

      final distribution = await context.distributions.getById(id!);
      final branches = await context.master.activeBranches();
      final users = await context.master.activeUsers();
      final head = users.firstWhere(
        (user) => user.role == UserRole.kepalaCabang,
      );

      expect(distribution!.branchId, branches.first.id);
      expect(distribution.distributedBy, head.id);
      expect(distribution.docNumber, startsWith('TMP-DIST-'));
      expect(distribution.note, isNotNull);
    });

    test('setiap baris menyasar ruangan cabang yang sama (G-T1)', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedDistribution();
      final distribution = await context.distributions.getById(id!);
      final rooms = await context.master.activeRooms(
        branchId: distribution!.branchId,
      );
      final allowed = rooms.map((room) => room.id).toSet();

      final rows = await context.distributionLineRows(id);
      for (final row in rows.values) {
        expect(allowed, contains(row['room_id']));
      }
    });

    test('qty setiap baris positif dan desimal eksak', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedDistribution();

      final rows = await context.distributionLineRows(id!);
      expect(rows, isNotEmpty);
      for (final row in rows.values) {
        final qty = row['qty'] as int;
        expect(qty, greaterThan(0));
        // A quarter of a fixed-point value is still a fixed-point value (Q-2).
        expect(Quantity.fromMilliUnits(qty).isPositive, isTrue);
      }
    });

    test('foreign_key_check bersih setelah seed', () async {
      await context.seed.run();
      await context.seed.seedPostedDistribution();

      final violations = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });
  });
}
