import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/document_timestamp_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The ledger a posted Distribusi writes (§43, spec §2.5).
///
/// *"Distribusi `posted` — `distribution`: Gudang Cabang − qty, Ruangan + qty."*
///
/// One movement per line, both locations set. That is the shape that distinguishes a
/// distribution from a shipment: a Delivery Order writes one leg out with
/// `to_location_id = NULL` because the goods are in transit, and a Good Receipt writes
/// the matching leg in. A distribution has no transit — the store and the room are both
/// inside one branch and both exist at the moment of the posting — so each line is a
/// single two-sided movement.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draft() =>
      createDistributionDraft(context, fixture, nowUtc: nowUtc);

  group('bentuk pergerakan', () {
    test('satu baris menghasilkan satu pergerakan dua sisi', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2.5',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      final movements = await context.distributionMovements(id);
      expect(movements, hasLength(1));
      final movement = movements.single;
      expect(movement['movement_type'], 'distribution');
      expect(movement['from_location_id'], fixture.branchStore.id);
      expect(movement['to_location_id'], fixture.locationOne.id);
      expect(movement['item_id'], fixture.simpleItem.id);
      expect(movement['batch_id'], isNull);
      expect(movement['qty'], 2500);
      expect(movement['ref_doc_type'], 'DIST');
      expect(movement['ref_doc_id'], id);
      expect(movement['actor_user_id'], fixture.branchHead.id);
    });

    test('kedua lokasi terisi, tidak seperti pengiriman', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      final movement = (await context.distributionMovements(id)).single;
      expect(movement['from_location_id'], isNotNull);
      expect(movement['to_location_id'], isNotNull);
    });

    test('jumlah pergerakan sama dengan jumlah baris aktif', () async {
      final id = await draft();
      // Three rooms, and one of them splits across two batches: four lines.
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
        nowUtc: nowUtc,
      );
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomThree.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final lineCount = await context.distributionLineCount(id);
      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(lineCount, 4);
      expect(result.movements, hasLength(4));
      expect(await context.distributionMovementCount(id), 4);
    });

    test('baris yang dihapus tidak menghasilkan pergerakan', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );

      final lines = await distributionLineIdsByPosition(context, id);
      await context.removeDistributionLine.call(
        actorUserId: fixture.branchHead.id,
        distributionId: id,
        lineId: lines['${fixture.roomTwo.id}|${fixture.simpleItem.id}|']!,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(await context.distributionMovementCount(id), 1);
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomTwo.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
    });

    test('batch dipertahankan pada pergerakan', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      final movements = await context.distributionMovements(id);
      final byBatch = {
        for (final movement in movements) movement['batch_id']: movement['qty'],
      };
      expect(byBatch[fixture.oldBatch.id], 2000);
      expect(byBatch[fixture.newBatch.id], 1000);
    });
  });

  group('efek saldo', () {
    test('gudang cabang berkurang, ruangan bertambah', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '4',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('6.5'),
      );
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('4'),
      );
    });

    test(
      'total pengurangan sumber sama dengan total penambahan tujuan',
      () async {
        final id = await draft();
        for (final entry in [
          (room: fixture.roomOne, qty: '1.25'),
          (room: fixture.roomTwo, qty: '2.5'),
          (room: fixture.roomThree, qty: '0.375'),
        ]) {
          await addDistributionItem(
            context,
            fixture,
            distributionId: id,
            roomId: entry.room.id,
            itemId: fixture.simpleItem.id,
            qty: entry.qty,
            nowUtc: nowUtc,
          );
        }

        final before = await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        );
        final result = await context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id);
        final after = await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        );

        final arrived = Quantity.sum([
          for (final room in [
            fixture.roomOne,
            fixture.roomTwo,
            fixture.roomThree,
          ])
            await roomBalance(
              context,
              fixture,
              roomId: room.id,
              itemId: fixture.simpleItem.id,
            ),
        ]);

        // Exact fixed point, so this is an equality rather than a tolerance (Q-2).
        expect(before - after, arrived);
        expect(arrived, result.totalQty);
        expect(arrived, Quantity.parse('4.125'));
      },
    );

    test('batch dipertahankan pada saldo ruangan', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      // The room's stock is split per batch, exactly as the store's was (G-E2).
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.oldBatch.id,
        ),
        Quantity.parse('2'),
      );
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.newBatch.id,
        ),
        Quantity.parse('1'),
      );
      // And the room has no batch-less balance for a batch-tracked item.
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
        ),
        Quantity.zero(),
      );
    });

    test('warehouse pusat tidak terpengaruh', () async {
      final before = await context.balancesAt(fixture.warehouse.id);

      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(await context.balancesAt(fixture.warehouse.id), before);
    });

    test('gudang cabang lain tidak terpengaruh', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(await context.balancesAt(fixture.otherBranchStore.id), isEmpty);
      expect(
        await context.balancesAt(fixture.otherBranchRoomLocation.id),
        isEmpty,
      );
    });

    test('dokumen PR, DO dan GR tidak tersentuh', () async {
      // A distribution is branch-internal: nothing about it belongs to the request that
      // brought the goods in, and inventing a transition on one would be asserting a
      // business event that never happened.
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      for (final table in [
        'purchase_requests',
        'delivery_orders',
        'good_receipts',
      ]) {
        final row = await context.database
            .customSelect('SELECT COUNT(*) AS c FROM $table;')
            .getSingle();
        expect(row.read<int>('c'), 0, reason: '$table tidak boleh disentuh.');
      }
    });
  });

  group('ledger append-only', () {
    test('tidak ada pergerakan yang diubah atau dihapus', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final before = await context.totalMovementCount();
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      // Exactly one row added, and the earlier fixture rows are all still there
      // (G-A1). The repository contract offers no update and no delete at all.
      expect(await context.totalMovementCount(), before + 1);
    });

    test('koreksi tetap lewat pembalik, bukan edit', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.distribution,
        refDocId: id,
      );
      expect(movements, hasLength(1));

      // A reversal is a *new* row pointing back at the original — the only correction
      // path the ledger has, and one this milestone does not expose to any screen.
      final reversal = await context.posting.postReversal(
        movementId: movements.single.id,
        actorUserId: fixture.branchHead.id,
        note: 'Koreksi distribusi',
      );
      expect(reversal.movementType, StockMovementType.reversal);
      expect(reversal.reversalOfMovementId, movements.single.id);
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('10.5'),
      );
      // The original row is untouched.
      final original = await context.inventory.movementById(
        movements.single.id,
      );
      expect(original!.qty, Quantity.parse('2'));
      expect(original.movementType, StockMovementType.distribution);
    });

    test('dokumen yang sudah diposting tidak dapat diposting ulang', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<DistributionAlreadyPostedFailure>()),
      );
      expect(await context.distributionMovementCount(id), 1);
    });
  });

  group('timestamp', () {
    test('posted_at disimpan sebagai instan UTC', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      expect(result.distribution.postedAt, nowUtc);
      expect(result.distribution.postedAt!.isUtc, isTrue);
      // Stored with the `Z` suffix, so the instant survives the round trip.
      final raw = await context.distributionColumn(id, 'posted_at');
      expect(raw, endsWith('Z'));
    });

    test('posted_at sama dengan created_at diperbolehkan', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      // Two transitions really can land on the same microsecond on a fast device, and
      // there is nothing wrong with that document.
      final result = await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);
      expect(result.distribution.postedAt, result.distribution.createdAt);
    });

    test('posted_at satu mikrodetik lebih awal ditolak', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final behind = nowUtc.subtract(const Duration(microseconds: 1));
      expect(
        () => context
            .postDistribution(clock: () => behind)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
      expect(await context.distributionColumn(id, 'posted_at'), isNull);
      expect(await context.distributionMovementCount(id), 0);
    });

    test('pesan jam perangkat dipakai untuk kemunduran waktu', () async {
      final id = await draft();
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      await expectLater(
        context
            .postDistribution(
              clock: () => nowUtc.subtract(const Duration(hours: 2)),
            )
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(
          isA<InvalidDocumentTimestampFailure>().having(
            (failure) => failure.message,
            'message',
            DocumentTimestampPolicy.deviceClockBehindMessage,
          ),
        ),
      );
    });

    test('urutan tidak dibandingkan sebagai teks di SQL', () async {
      // The trap schema v4 removed from `stock_opnames`: ISO-8601 TEXT compares by
      // characters. `distributions` therefore carries no CHECK relating its two
      // timestamps, and ordering is `DocumentTimestampPolicy`'s on UTC instants.
      final sql = await context.database
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'distributions';",
          )
          .getSingle();
      final ddl = sql.read<String>('sql');
      expect(ddl, isNot(contains('posted_at >= created_at')));
      expect(ddl, isNot(contains('posted_at > created_at')));
    });
  });
}
