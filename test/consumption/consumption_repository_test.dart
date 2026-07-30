import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/consumption/domain/models/consumption_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The repository and its live streams (§44).
///
/// Every screen in this feature renders from a Drift stream, so the assertions here are
/// about *emission* rather than about a single read: a form that stored a line and did not
/// re-emit would look like a form that lost it.
///
/// The candidate reads get the most attention, because they are where three rules meet —
/// only this room, only positive balances, only unexpired batches — and any one of them
/// missing produces a picker that offers something the use case then refuses.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draft({String? roomId, String? actorUserId}) =>
      createConsumptionDraft(
        context,
        fixture,
        roomId: roomId ?? fixture.roomOne.id,
        nowUtc: nowUtc,
        actorUserId: actorUserId,
      );

  group('daftar milik sendiri', () {
    test('draft baru langsung muncul di daftar', () async {
      expect(
        await context.consumptions.listOwn(actorUserId: fixture.nurse.id),
        isEmpty,
      );

      final id = await draft();
      final rows = await context.consumptions.listOwn(
        actorUserId: fixture.nurse.id,
      );
      expect(rows, hasLength(1));
      expect(rows.single.id, id);
      expect(rows.single.status, ConsumptionStatus.draft);
      expect(rows.single.lineCount, 0);
    });

    test('stream daftar memancarkan setiap perubahan', () async {
      final emissions = <List<ConsumptionSummary>>[];
      final subscription = context.consumptions
          .watchOwnList(actorUserId: fixture.nurse.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      final id = await draft();
      await pumpEventQueue();
      expect(emissions.last, hasLength(1));
      expect(emissions.last.single.lineCount, 0);

      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await pumpEventQueue();
      expect(emissions.last.single.lineCount, 1);

      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );
      await pumpEventQueue();
      expect(emissions.last.single.status, ConsumptionStatus.posted);
    });

    test('filter status menyaring daftar', () async {
      final draftId = await draft();
      final postedId = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: postedId,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: postedId,
      );

      final drafts = await context.consumptions.listOwn(
        actorUserId: fixture.nurse.id,
        statuses: const {ConsumptionStatus.draft},
      );
      expect(drafts.map((row) => row.id), [draftId]);

      final posted = await context.consumptions.listOwn(
        actorUserId: fixture.nurse.id,
        statuses: const {ConsumptionStatus.posted},
      );
      expect(posted.map((row) => row.id), [postedId]);
    });

    test('filter ruangan menyaring daftar', () async {
      final one = await draft(roomId: fixture.roomOne.id);
      final two = await draft(roomId: fixture.roomTwo.id);

      final roomOne = await context.consumptions.listOwn(
        actorUserId: fixture.nurse.id,
        roomId: fixture.roomOne.id,
      );
      expect(roomOne.map((row) => row.id), [one]);

      final roomTwo = await context.consumptions.listOwn(
        actorUserId: fixture.nurse.id,
        roomId: fixture.roomTwo.id,
      );
      expect(roomTwo.map((row) => row.id), [two]);
    });

    test(
      'pencarian menemukan nomor, ruangan, nama barang, SKU dan batch',
      () async {
        final id = await draft();
        await addConsumptionPosition(
          context,
          fixture,
          consumptionId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        );
        final docNumber = (await context.consumptions.getById(id))!.docNumber;

        Future<List<String>> search(String query) async =>
            (await context.consumptions.listOwn(
              actorUserId: fixture.nurse.id,
              searchQuery: query,
            )).map((row) => row.id).toList();

        expect(await search(docNumber), [id]);
        // Case-insensitive throughout (G-Y1: entirely local).
        expect(await search('RUANG dental 1'), [id]);
        expect(await search('r1'), [id]);
        expect(await search('anestesi'), [id]);
        expect(await search('CNS-0001'), [id]);
        expect(await search('a-valid'), [id]);
        expect(await search('tidak ada apa pun'), isEmpty);
      },
    );

    test('pencarian tidak bocor lintas perawat', () async {
      final theirs = await draft(actorUserId: fixture.otherNurse.id);
      final docNumber = (await context.consumptions.getById(theirs))!.docNumber;

      expect(
        await context.consumptions.listOwn(
          actorUserId: fixture.nurse.id,
          searchQuery: docNumber,
        ),
        isEmpty,
      );
    });
  });

  group('detail stream', () {
    test('menambah, mengubah dan menghapus baris memancarkan detail', () async {
      final id = await draft();
      final emissions = <ConsumptionDetail?>[];
      final subscription = context.consumptions
          .watchOwn(consumptionId: id, actorUserId: fixture.nurse.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions.last!.isEmpty, isTrue);

      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await pumpEventQueue();
      expect(emissions.last!.lines, hasLength(1));
      expect(emissions.last!.lines.single.qty, Quantity.parse('2'));

      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId =
          lines['${fixture.expiryItem.id}|${fixture.validBatch.id}']!;

      await context
          .updateConsumptionLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.nurse.id,
            consumptionId: id,
            lineId: lineId,
            qty: Quantity.parse('3.5'),
            note: 'satu ampul pecah',
          );
      await pumpEventQueue();
      expect(emissions.last!.lines.single.qty, Quantity.parse('3.5'));
      expect(emissions.last!.lines.single.note, 'satu ampul pecah');

      await context.removeConsumptionLine.call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
        lineId: lineId,
      );
      await pumpEventQueue();
      expect(emissions.last!.lines, isEmpty);
    });

    test('mengubah catatan header memancarkan detail', () async {
      final id = await draft();
      final emissions = <ConsumptionDetail?>[];
      final subscription = context.consumptions
          .watchOwn(consumptionId: id, actorUserId: fixture.nurse.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions.last!.consumption.note, isNull);

      await context.updateConsumptionHeader.call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
        note: 'shift pagi',
      );
      await pumpEventQueue();
      expect(emissions.last!.consumption.note, 'shift pagi');
    });

    test('posting mengubah status pada stream', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final emissions = <ConsumptionDetail?>[];
      final subscription = context.consumptions
          .watchOwn(consumptionId: id, actorUserId: fixture.nurse.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions.last!.isDraft, isTrue);

      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );
      await pumpEventQueue();
      expect(emissions.last!.isPosted, isTrue);
      expect(emissions.last!.summary.postedByName, fixture.nurse.fullName);
    });

    test('stream perawat lain tidak pernah memancarkan dokumen ini', () async {
      final id = await draft();
      final emissions = <ConsumptionDetail?>[];
      final subscription = context.consumptions
          .watchOwn(consumptionId: id, actorUserId: fixture.otherNurse.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions.last, isNull);

      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await pumpEventQueue();
      expect(emissions.every((detail) => detail == null), isTrue);
    });

    test(
      'stream cabang tidak memancarkan draft, lalu memancarkan posted',
      () async {
        final id = await draft();
        await addConsumptionPosition(
          context,
          fixture,
          consumptionId: id,
          itemId: fixture.plainItem.id,
          qty: '1',
          nowUtc: nowUtc,
        );

        final emissions = <ConsumptionDetail?>[];
        final subscription = context.consumptions
            .watchPostedForBranch(
              consumptionId: id,
              branchId: fixture.branch.id,
            )
            .listen(emissions.add);
        addTearDown(subscription.cancel);

        await pumpEventQueue();
        expect(emissions.last, isNull);

        await context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        );
        await pumpEventQueue();
        expect(emissions.last, isNotNull);
        expect(emissions.last!.isPosted, isTrue);
      },
    );
  });

  group('kandidat ruangan', () {
    test('hanya posisi bersaldo positif dan belum kedaluwarsa', () async {
      final positions = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );

      final keys = positions.map((position) => position.positionKey).toSet();
      expect(
        keys,
        contains('${fixture.expiryItem.id}|${fixture.validBatch.id}'),
      );
      expect(
        keys,
        contains('${fixture.expiryItem.id}|${fixture.nearBatch.id}'),
      );
      expect(
        keys,
        contains('${fixture.expiryItem.id}|${fixture.todayBatch.id}'),
      );
      expect(keys, contains('${fixture.plainItem.id}|'));
      expect(keys, contains('${fixture.otherPlainItem.id}|'));
      expect(
        keys,
        contains('${fixture.otherExpiryItem.id}|${fixture.otherItemBatch.id}'),
      );

      // Expired: absent, not greyed out (G-E7).
      expect(
        keys,
        isNot(contains('${fixture.expiryItem.id}|${fixture.expiredBatch.id}')),
      );
      // Zero balance: never a candidate.
      expect(
        keys,
        isNot(contains('${fixture.expiryItem.id}|${fixture.emptyBatch.id}')),
      );
      expect(
        positions.every((position) => position.qtyOnHand.isPositive),
        isTrue,
      );
    });

    test('near-expiry tetap kandidat dengan flag', () async {
      final positions = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );
      final near = positions.firstWhere(
        (position) => position.batchId == fixture.nearBatch.id,
      );
      expect(near.isNearExpiryOn(nowUtc), isTrue);
      expect(near.isExpiredOn(nowUtc), isFalse);
    });

    test('filter kategori menyaring kandidat', () async {
      final obat = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
        categoryId: fixture.category.id,
      );
      expect(obat.map((position) => position.categoryId).toSet(), {
        fixture.category.id,
      });
      expect(obat.map((position) => position.itemId).toSet(), {
        fixture.expiryItem.id,
        fixture.plainItem.id,
      });

      final alat = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
        categoryId: fixture.otherCategory.id,
      );
      expect(alat.map((position) => position.itemId).toSet(), {
        fixture.otherExpiryItem.id,
        fixture.otherPlainItem.id,
      });
    });

    test('pencarian kandidat cocok nama, SKU dan batch', () async {
      final id = await draft();

      Future<Set<String>> search(String query) async =>
          (await context.consumptions.searchRoomCandidates(
            roomId: fixture.roomOne.id,
            roomLocationId: fixture.locationOne.id,
            nowUtc: nowUtc,
            searchQuery: query,
          )).map((position) => position.itemId).toSet();
      expect(id, isNotEmpty);

      expect(await search('anestesi'), {fixture.expiryItem.id});
      expect(await search('CNS-0003'), {fixture.plainItem.id});
      expect(await search('B-NEAR'), {fixture.expiryItem.id});
      expect(await search('MASKER'), {fixture.plainItem.id});
      expect(await search('tidak ada'), isEmpty);
    });

    test('kandidat dibatasi limit', () async {
      final capped = await context.consumptions.searchRoomCandidates(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
        limit: 2,
      );
      expect(capped, hasLength(2));

      final uncapped = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );
      expect(uncapped.length, greaterThan(2));
    });

    test('barang nonaktif tidak ditawarkan untuk baris baru', () async {
      await context.deactivate('items', fixture.plainItem.id);

      final forNewLine = await context.consumptions.searchRoomCandidates(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );
      expect(
        forNewLine.map((position) => position.itemId),
        isNot(contains(fixture.plainItem.id)),
      );

      // …but the document's own availability read keeps it, so an existing line can still
      // show what the room holds (§33).
      final forExistingLines = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );
      final match = forExistingLines.where(
        (position) => position.itemId == fixture.plainItem.id,
      );
      expect(match, hasLength(1));
      expect(match.single.itemIsHistorical, isTrue);
    });

    test('saldo kandidat berubah setelah posting', () async {
      final before = await context.consumptions.roomPositionFor(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        nowUtc: nowUtc,
      );
      expect(before!.qtyOnHand, Quantity.parse('5.5'));

      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1.5',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      final after = await context.consumptions.roomPositionFor(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        nowUtc: nowUtc,
      );
      expect(after!.qtyOnHand, Quantity.parse('4'));
    });

    test('stream kandidat memancarkan setelah posting', () async {
      final emissions = <List<RoomStockPosition>>[];
      final subscription = context.consumptions
          .watchRoomPositions(
            roomId: fixture.roomOne.id,
            roomLocationId: fixture.locationOne.id,
            nowUtc: nowUtc,
          )
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      Quantity plainQty(List<RoomStockPosition> rows) => rows
          .firstWhere((position) => position.itemId == fixture.plainItem.id)
          .qtyOnHand;
      expect(plainQty(emissions.last), Quantity.parse('10.5'));

      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '0.5',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );
      await pumpEventQueue();

      expect(plainQty(emissions.last), Quantity.parse('10'));
    });

    test('posisi yang habis hilang dari kandidat', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '5.5',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      final positions = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );
      expect(
        positions.map((position) => position.batchId),
        isNot(contains(fixture.validBatch.id)),
      );
    });

    test('roomPositionFor membedakan batch NULL dari batch tertentu', () async {
      // `batchId == null` cannot be a SQL equality, so a query that only pinned the item
      // would return the batched rows too. The distinction is what makes an item without
      // expiry readable at all.
      final unbatched = await context.consumptions.roomPositionFor(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.locationOne.id,
        itemId: fixture.plainItem.id,
        nowUtc: nowUtc,
      );
      expect(unbatched, isNotNull);
      expect(unbatched!.batchId, isNull);
      expect(unbatched.qtyOnHand, Quantity.parse('10.5'));

      // Asking for the *unbatched* row of a batch-tracked item finds nothing: that
      // position does not exist.
      expect(
        await context.consumptions.roomPositionFor(
          roomId: fixture.roomOne.id,
          roomLocationId: fixture.locationOne.id,
          itemId: fixture.expiryItem.id,
          nowUtc: nowUtc,
        ),
        isNull,
      );
    });
  });

  group('ruangan dan lokasi', () {
    test('daftar ruangan aktif per cabang', () async {
      final rooms = await context.consumptions.activeRoomsOfBranch(
        fixture.branch.id,
      );
      expect(rooms.map((room) => room.roomId).toSet(), {
        fixture.roomOne.id,
        fixture.roomTwo.id,
      });
      expect(rooms.every((room) => room.isActive), isTrue);
      expect(rooms.every((room) => !room.isHistorical), isTrue);
    });

    test(
      'ruangan nonaktif hilang dari daftar tetapi terbaca historis',
      () async {
        await context.deactivate('rooms', fixture.roomTwo.id);

        final rooms = await context.consumptions.activeRoomsOfBranch(
          fixture.branch.id,
        );
        expect(rooms.map((room) => room.roomId), [fixture.roomOne.id]);

        final historical = await context.consumptions.historicalRoomById(
          fixture.roomTwo.id,
        );
        expect(historical, isNotNull);
        expect(historical!.isHistorical, isTrue);
        expect(historical.name, fixture.roomTwo.name);
      },
    );

    test('stream ruangan memancarkan daftar aktif cabang', () async {
      // The emission is asserted rather than a single read, because the selector renders
      // from this stream — a room list that never emitted would show an empty selector.
      //
      // What this test deliberately does **not** do is deactivate a room and wait for a
      // second emission. `TestContext.deactivate` writes through `customStatement`, which
      // drift does not track for stream invalidation, so no emission would arrive — and
      // that is a property of the helper rather than of the query. Deactivating a room is
      // a back-office act in production, and the *content* of the predicate is asserted by
      // the re-read test above.
      final emissions = <List<ConsumptionRoom>>[];
      final subscription = context.consumptions
          .watchActiveRoomsOfBranch(fixture.branch.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions, isNotEmpty);
      expect(emissions.last.map((room) => room.roomId).toSet(), {
        fixture.roomOne.id,
        fixture.roomTwo.id,
      });
      expect(
        emissions.last.map((room) => room.roomId),
        isNot(contains(fixture.otherBranchRoom.id)),
      );
    });

    test('lokasi ruangan dikembalikan sebagai daftar', () async {
      final locations = await context.consumptions.roomLocations(
        fixture.roomOne.id,
      );
      expect(locations, hasLength(1));
      expect(locations.single.id, fixture.locationOne.id);
      expect(locations.single.type, StockLocationType.room);

      await context.insertDuplicateLocation(
        id: 'dup-loc',
        type: StockLocationType.room.dbValue,
        name: 'Duplikat',
        branchId: fixture.branch.id,
        roomId: fixture.roomOne.id,
      );
      // Two rows, and the caller has to be able to *see* that rather than get one of them
      // (§15).
      expect(
        await context.consumptions.roomLocations(fixture.roomOne.id),
        hasLength(2),
      );
    });

    test('lokasi diarsipkan hanya terlihat dengan activeOnly false', () async {
      await context.archive('stock_locations', fixture.locationTwo.id);

      expect(
        await context.consumptions.roomLocations(fixture.roomTwo.id),
        isEmpty,
      );
      expect(
        await context.consumptions.roomLocations(
          fixture.roomTwo.id,
          activeOnly: false,
        ),
        hasLength(1),
      );
    });
  });

  group('transaksi', () {
    test('rollback membersihkan seluruh tulisan di dalamnya', () async {
      final id = await draft();

      await expectLater(
        context.consumptions.runInTransaction(() async {
          await context.consumptions.addDraftLine(
            consumptionId: id,
            actorUserId: fixture.nurse.id,
            itemId: fixture.plainItem.id,
            qty: Quantity.parse('1'),
          );
          await context.consumptions.updateOwnDraftNote(
            consumptionId: id,
            actorUserId: fixture.nurse.id,
            note: 'akan dibatalkan',
          );
          throw StateError('batal');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await context.consumptionLineCount(id), 0);
      expect(await context.consumptionColumn(id, 'note'), isNull);
    });

    test('posting dua kali aman melalui repository', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      expect(
        await context.consumptions.markPosted(
          consumptionId: id,
          actorUserId: fixture.nurse.id,
          postedAtUtc: nowUtc,
          postedBy: fixture.nurse.id,
        ),
        isTrue,
      );
      expect(
        await context.consumptions.markPosted(
          consumptionId: id,
          actorUserId: fixture.nurse.id,
          postedAtUtc: nowUtc,
          postedBy: fixture.nurse.id,
        ),
        isFalse,
        reason: 'Guarded update menyertakan status draft.',
      );
    });

    test('guarded line writers menolak dokumen posted', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId = lines['${fixture.plainItem.id}|']!;
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(
        await context.consumptions.updateDraftLine(
          consumptionId: id,
          actorUserId: fixture.nurse.id,
          lineId: lineId,
          qty: Quantity.parse('2'),
        ),
        isFalse,
      );
      expect(
        await context.consumptions.removeDraftLine(
          consumptionId: id,
          actorUserId: fixture.nurse.id,
          lineId: lineId,
        ),
        isFalse,
      );
      expect(
        await context.consumptions.updateOwnDraftNote(
          consumptionId: id,
          actorUserId: fixture.nurse.id,
          note: 'sesudah',
        ),
        isFalse,
      );
    });

    test('guarded line writers menolak qty nol di SQL', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);

      expect(
        await context.consumptions.updateDraftLine(
          consumptionId: id,
          actorUserId: fixture.nurse.id,
          lineId: lines['${fixture.plainItem.id}|']!,
          qty: Quantity.zero(),
        ),
        isFalse,
        reason: '`? > 0` ikut ke dalam statement, bukan hanya ke domain.',
      );
    });
  });

  group('id set untuk integritas', () {
    test('lineIds, lineItemIds dan lineBatchIds konsisten', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      expect(await context.consumptions.lineIds(id), hasLength(2));
      expect((await context.consumptions.lineItemIds(id)).toSet(), {
        fixture.expiryItem.id,
        fixture.plainItem.id,
      });
      // Only the batched line contributes, which is what makes an item without expiry
      // pass the reference check rather than look like a broken reference.
      expect(await context.consumptions.lineBatchIds(id), [
        fixture.validBatch.id,
      ]);
    });

    test('baris soft-deleted tidak muncul di id set', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);
      await context.removeConsumptionLine.call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
        lineId: lines['${fixture.plainItem.id}|']!,
      );

      expect(await context.consumptions.lineIds(id), isEmpty);
      expect(await context.consumptions.lineItemIds(id), isEmpty);
      expect(await context.consumptions.lineReferences(id), isEmpty);
    });
  });
}
