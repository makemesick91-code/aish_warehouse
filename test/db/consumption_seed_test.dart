import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The development seed's Pemakaian demo data (§36).
///
/// Three properties matter, and each has failed on an earlier milestone at least once:
///
/// * **idempotent.** Running the seed twice must not file two documents, and the check is
///   owner-scoped rather than branch-scoped because that is the scope this document lives
///   in (§14).
/// * **through the use cases.** The demo consumption is created, filled and posted by the
///   real use cases, so every rule the screens enforce applies to it too and the balances
///   it reduces are backed by real ledger rows. A seed that wrote `stock_balances` directly
///   would demonstrate a state the application cannot reach.
/// * **it does not exhaust the demo stock.** Half of each position, truncated in exact
///   fixed point — so the picker, the room-stock screen and the branch history all still
///   have rows after the demo document is posted.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  group('prasyarat data ruangan', () {
    test('ruangan R1 memuat setiap bentuk posisi (§36)', () async {
      await context.seed.run();

      final room = (await context.master.activeRooms()).firstWhere(
        (room) => room.code == 'R1',
      );
      final location = await context.master.activeRoomLocation(room.id);
      final balances = await context.inventory.balancesAtLocation(location!.id);
      final nowUtc = DateTime.now().toUtc();

      // An item without expiry.
      expect(
        balances.any((row) => row.batchId == null && row.qtyOnHand.isPositive),
        isTrue,
        reason: 'Barang tanpa ED wajib ada agar G-E2 terdemonstrasi.',
      );
      // A batch-tracked item across more than one batch.
      final anaesthetic = balances.where((row) => row.sku == 'DEN-0007');
      expect(
        anaesthetic.length,
        greaterThanOrEqualTo(2),
        reason: 'Barang ber-ED multi-batch wajib ada.',
      );
      // A comfortably valid batch.
      expect(
        balances.any(
          (row) =>
              row.expiryDate != null &&
              !row.isExpiredOn(nowUtc) &&
              (row.daysUntilExpiry(nowUtc) ?? 0) > 30,
        ),
        isTrue,
        reason: 'Batch valid wajib ada.',
      );
      // A near-expiry batch — the orange badge (G-E6).
      expect(
        balances.any((row) {
          final remaining = row.daysUntilExpiry(nowUtc);
          return remaining != null &&
              !row.isExpiredOn(nowUtc) &&
              remaining <= row.expiryAlertDays;
        }),
        isTrue,
        reason: 'Batch near-expiry wajib ada agar badge oranye terlihat.',
      );
      // An expired batch — which cannot be consumed at all (G-E7).
      expect(
        balances.any((row) => row.isExpiredOn(nowUtc)),
        isTrue,
        reason: 'Batch kedaluwarsa wajib ada agar penolakan §17 terlihat.',
      );
      // Decimal quantities throughout.
      expect(
        balances.any((row) => row.qtyOnHand.milliUnits % Quantity.scale != 0),
        isTrue,
        reason: 'Saldo desimal wajib ada.',
      );
    });

    test('perawat dan kepala cabang aktif tersedia', () async {
      await context.seed.run();

      final users = await context.master.activeUsers();
      final nurses = users.where((user) => user.role == UserRole.perawat);
      final heads = users.where((user) => user.role == UserRole.kepalaCabang);

      expect(nurses, isNotEmpty);
      expect(heads, isNotEmpty);
      expect(nurses.first.branchId, isNotNull);
      expect(heads.first.branchId, isNotNull);
    });

    test('batch kedaluwarsa di ruangan bukan kandidat pemakaian', () async {
      await context.seed.run();

      final room = (await context.master.activeRooms()).firstWhere(
        (room) => room.code == 'R1',
      );
      final location = await context.master.activeRoomLocation(room.id);
      final nowUtc = DateTime.now().toUtc();

      final consumable = await context.consumptions.roomPositions(
        roomId: room.id,
        roomLocationId: location!.id,
        nowUtc: nowUtc,
      );
      expect(
        consumable.every((position) => !position.isExpiredOn(nowUtc)),
        isTrue,
        reason: 'Kandidat pemakaian tidak boleh memuat batch kedaluwarsa.',
      );

      // …and it is exactly the position the Pemusnahan screen *does* offer.
      final disposable = await context.disposals.expiredPositions(
        sourceLocationId: location.id,
        nowUtc: nowUtc,
      );
      expect(
        disposable,
        isNotEmpty,
        reason: 'Batch kedaluwarsa harus keluar melalui pemusnahan (G-E7).',
      );
    });
  });

  group('demo dokumen', () {
    test(
      'run() tidak membuat Pemakaian, agar empty state dapat diuji',
      () async {
        await context.seed.run();

        final row = await context.database
            .customSelect('SELECT COUNT(*) AS c FROM consumptions;')
            .getSingle();
        expect(row.read<int>('c'), 0);
      },
    );

    test('seedDraftConsumption membuat satu draft milik perawat', () async {
      await context.seed.run();
      final id = await context.seed.seedDraftConsumption();

      expect(id, isNotNull);
      expect(await context.consumptionStatusOf(id!), 'draft');

      final nurses = (await context.master.activeUsers()).where(
        (user) => user.role == UserRole.perawat,
      );
      expect(
        await context.consumptionColumn(id, 'created_by'),
        nurses.first.id,
      );
      expect(
        await context.consumptionColumn(id, 'doc_number'),
        startsWith('TMP-CNS-'),
      );
      expect(await context.consumptionLineCount(id), greaterThan(0));
    });

    test('draft demo memuat posisi berbatch dan tanpa batch', () async {
      await context.seed.run();
      final id = (await context.seed.seedDraftConsumption())!;

      final rows = await context.consumptionLineRows(id);
      expect(rows, hasLength(2));
      expect(
        rows.values.any((row) => row['batch_id'] == null),
        isTrue,
        reason: 'Satu posisi tanpa batch, agar G-E2 terdemonstrasi.',
      );
      expect(
        rows.values.any((row) => row['batch_id'] != null),
        isTrue,
        reason: 'Satu posisi berbatch.',
      );
    });

    test('draft demo tidak memuat batch kedaluwarsa', () async {
      await context.seed.run();
      final id = (await context.seed.seedDraftConsumption())!;

      final detail = await context.consumptions.getDetail(id);
      final nowUtc = DateTime.now().toUtc();
      expect(detail!.lines.every((line) => !line.isExpiredOn(nowUtc)), isTrue);
      expect(detail.progressOn(nowUtc).allUsable, isTrue);
    });

    test('draft demo tidak menulis movement', () async {
      await context.seed.run();
      final before = await context.movementCountOfType(
        StockMovementType.consumption,
      );
      final id = (await context.seed.seedDraftConsumption())!;

      expect(await context.consumptionMovementCount(id), 0);
      expect(
        await context.movementCountOfType(StockMovementType.consumption),
        before,
      );
    });

    test('seedDraftConsumption idempoten', () async {
      await context.seed.run();
      final first = await context.seed.seedDraftConsumption();
      final second = await context.seed.seedDraftConsumption();

      expect(second, first);
      final row = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM consumptions;')
          .getSingle();
      expect(row.read<int>('c'), 1);
    });

    test('seedPostedConsumption memposting melalui use case', () async {
      await context.seed.run();
      final id = await context.seed.seedPostedConsumption();

      expect(id, isNotNull);
      expect(await context.consumptionStatusOf(id!), 'posted');
      expect(await context.consumptionColumn(id, 'posted_at'), isNotNull);
      expect(await context.consumptionColumn(id, 'posted_by'), isNotNull);

      // Real ledger rows, one per line, with the right shape.
      final lineCount = await context.consumptionLineCount(id);
      final movements = await context.consumptionMovements(id);
      expect(movements, hasLength(lineCount));
      for (final movement in movements) {
        expect(movement['movement_type'], 'consumption');
        expect(movement['ref_doc_type'], 'CONS');
        expect(movement['to_location_id'], isNull);
        expect(movement['from_location_id'], isNotNull);
      }
    });

    test('seedPostedConsumption idempoten', () async {
      await context.seed.run();
      final first = await context.seed.seedPostedConsumption();
      final second = await context.seed.seedPostedConsumption();

      expect(second, first);
      final row = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM consumptions;')
          .getSingle();
      expect(row.read<int>('c'), 1);
      expect(await context.consumptionMovementCount(first!), lessThan(3));
    });

    test('posting demo tidak menghabiskan stok ruangan', () async {
      await context.seed.run();
      final room = (await context.master.activeRooms()).firstWhere(
        (room) => room.code == 'R1',
      );
      final location = await context.master.activeRoomLocation(room.id);
      final nowUtc = DateTime.now().toUtc();

      final before = await context.consumptions.roomPositions(
        roomId: room.id,
        roomLocationId: location!.id,
        nowUtc: nowUtc,
      );
      await context.seed.seedPostedConsumption();
      final after = await context.consumptions.roomPositions(
        roomId: room.id,
        roomLocationId: location.id,
        nowUtc: nowUtc,
      );

      expect(
        after,
        hasLength(before.length),
        reason:
            'Setiap posisi harus menyisakan saldo, agar layar yang '
            'didemonstrasikan tidak tampak kosong (§36).',
      );
      expect(after.every((position) => position.qtyOnHand.isPositive), isTrue);
      // And each touched position really did fall.
      final beforeByKey = {
        for (final position in before) position.positionKey: position.qtyOnHand,
      };
      final afterByKey = {
        for (final position in after) position.positionKey: position.qtyOnHand,
      };
      expect(
        afterByKey.entries.any(
          (entry) => entry.value < beforeByKey[entry.key]!,
        ),
        isTrue,
      );
    });

    test('dokumen demo terbaca oleh kepala cabang setelah diposting', () async {
      await context.seed.run();
      final id = (await context.seed.seedPostedConsumption())!;

      final heads = (await context.master.activeUsers()).where(
        (user) => user.role == UserRole.kepalaCabang,
      );
      final branchId = heads.first.branchId!;

      final rows = await context.consumptions.listPostedForBranch(
        branchId: branchId,
      );
      expect(rows.map((row) => row.id), contains(id));
    });

    test('draft demo tidak terbaca oleh kepala cabang', () async {
      await context.seed.run();
      final id = (await context.seed.seedDraftConsumption())!;

      final heads = (await context.master.activeUsers()).where(
        (user) => user.role == UserRole.kepalaCabang,
      );
      final rows = await context.consumptions.listPostedForBranch(
        branchId: heads.first.branchId!,
      );
      expect(rows.map((row) => row.id), isNot(contains(id)));
    });

    test('dokumen demo diposting pada hari operasional yang sama', () async {
      await context.seed.run();
      final id = (await context.seed.seedPostedConsumption())!;

      final postedAt = DateTime.parse(
        (await context.consumptionColumn(id, 'posted_at'))!,
      );
      expect(
        AppTimeZone.operationalDate(postedAt),
        AppTimeZone.operationalDate(DateTime.now().toUtc()),
        reason: 'Dashboard "Pemakaian hari ini" harus memuat dokumen demo.',
      );
    });

    test('tidak ada data pasien pada dokumen demo', () async {
      await context.seed.run();
      final id = (await context.seed.seedPostedConsumption())!;

      final note = await context.consumptionColumn(id, 'note');
      expect(note, isNotNull);
      for (final word in const ['pasien', 'Pasien', 'rekam', 'diagnos']) {
        expect(note, isNot(contains(word)));
      }
      final movements = await context.consumptionMovements(id);
      for (final movement in movements) {
        final text = movement['note'] as String?;
        if (text == null) continue;
        for (final word in const ['pasien', 'rekam', 'diagnos']) {
          expect(text, isNot(contains(word)));
        }
      }
    });
  });

  group('penjaga build produksi', () {
    test('seed pemakaian menolak build rilis', () async {
      await context.seed.run();

      await expectLater(
        context.productionSeed.seedDraftConsumption(),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        context.productionSeed.seedPostedConsumption(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
