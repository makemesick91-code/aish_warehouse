import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/purchase_request/domain/services/suggested_purchase_request_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// `suggested_qty` — the deficiency arithmetic of §14.
///
/// ```
/// per room, per item : counted    = Σ counted_qty over that item's batches
/// per room, per item : deficiency = max(0, item.min_stock_room − counted)
/// per item           : suggested  = Σ deficiency over the cited rooms
/// ```
///
/// The order of those steps is the thing most worth pinning. A batch-tracked item is
/// counted once per batch, so comparing each line to the par level separately would
/// demand the par level several times over — three batches of 2 against a par of 5
/// would come out as a deficiency of 9 instead of 0. Half of this file exists to make
/// that mistake fail the build.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  const calculator = SuggestedPurchaseRequestCalculator();

  MasterItem item({
    String id = 'item-1',
    String sku = 'SKU-1',
    String name = 'Barang Uji',
    String unit = 'box',
    required int minStockRoom,
    bool isActive = true,
  }) => MasterItem(
    id: id,
    sku: sku,
    name: name,
    categoryId: 'cat-1',
    unit: unit,
    minStockRoom: minStockRoom,
    minStockBranch: minStockRoom * 4,
    hasExpiry: false,
    expiryAlertDays: 30,
    isActive: isActive,
  );

  OpnameCountSnapshot snapshot({
    String opnameId = 'so-1',
    String roomId = 'room-1',
    String roomName = 'Ruang Dental 1',
    int year = 2026,
    int week = 31,
    required List<OpnameCountedPosition> lines,
  }) => (
    opnameId: opnameId,
    roomId: roomId,
    roomName: roomName,
    periodYear: year,
    periodWeek: week,
    lines: lines,
  );

  OpnameCountedPosition position(String itemId, String qty) =>
      (itemId: itemId, countedQty: Quantity.parse(qty));

  group('formula max(0, min − counted)', () {
    test('hitungan di bawah par menghasilkan kekurangan', () {
      final lines = calculator(
        snapshots: [
          snapshot(lines: [position('item-1', '2')]),
        ],
        items: {'item-1': item(minStockRoom: 5)},
      );

      expect(lines, hasLength(1));
      expect(lines.single.suggestedQty, Quantity.parse('3'));
      expect(lines.single.parLevelPerRoom, Quantity.parse('5'));
      expect(lines.single.countedTotal, Quantity.parse('2'));
    });

    test('hitungan sama dengan par tidak menyarankan apa pun', () {
      final lines = calculator(
        snapshots: [
          snapshot(lines: [position('item-1', '5')]),
        ],
        items: {'item-1': item(minStockRoom: 5)},
      );
      expect(lines, isEmpty);
    });

    test('hitungan di atas par tidak menghasilkan nilai negatif', () {
      final lines = calculator(
        snapshots: [
          snapshot(lines: [position('item-1', '9')]),
        ],
        items: {'item-1': item(minStockRoom: 5)},
        includeZeroSuggestions: true,
      );

      expect(lines.single.suggestedQty, Quantity.zero());
      expect(
        lines.single.suggestedQty.isNegative,
        isFalse,
        reason: 'Kelebihan stok tidak boleh menjadi saran negatif.',
      );
    });

    test('kekurangan desimal dihitung eksak', () {
      final lines = calculator(
        snapshots: [
          snapshot(lines: [position('item-1', '2.375')]),
        ],
        items: {'item-1': item(minStockRoom: 5)},
      );

      // 5 − 2.375 = 2.625 exactly. On `double` this is the kind of subtraction that
      // produces 2.6249999999999996.
      expect(lines.single.suggestedQty, Quantity.parse('2.625'));
      expect(lines.single.suggestedQty.milliUnits, 2625);
    });
  });

  group('agregasi', () {
    test('kekurangan dijumlahkan antar-ruangan', () {
      final lines = calculator(
        snapshots: [
          snapshot(
            opnameId: 'so-1',
            roomId: 'room-1',
            roomName: 'Ruang Dental 1',
            lines: [position('item-1', '2.5')],
          ),
          snapshot(
            opnameId: 'so-2',
            roomId: 'room-2',
            roomName: 'Ruang Dental 2',
            lines: [position('item-1', '1')],
          ),
        ],
        items: {'item-1': item(minStockRoom: 5)},
      );

      // (5 − 2.5) + (5 − 1) = 2.5 + 4 = 6.5
      expect(lines.single.suggestedQty, Quantity.parse('6.5'));
      expect(lines.single.countedTotal, Quantity.parse('3.5'));
      expect(lines.single.sourceRoomNames, [
        'Ruang Dental 1',
        'Ruang Dental 2',
      ]);
    });

    test('batch dijumlahkan per ruangan SEBELUM dibandingkan dengan par', () {
      final lines = calculator(
        snapshots: [
          snapshot(
            lines: [
              position('item-1', '2'),
              position('item-1', '2'),
              position('item-1', '2'),
            ],
          ),
        ],
        items: {'item-1': item(minStockRoom: 5)},
        includeZeroSuggestions: true,
      );

      // 2 + 2 + 2 = 6, which is above the par of 5, so the deficiency is nothing.
      // Comparing each batch to par separately would give (5−2) × 3 = 9.
      expect(lines.single.countedTotal, Quantity.parse('6'));
      expect(lines.single.suggestedQty, Quantity.zero());
    });

    test('batch dijumlahkan lalu kekurangan dihitung sekali', () {
      final lines = calculator(
        snapshots: [
          snapshot(lines: [position('item-1', '2'), position('item-1', '2')]),
        ],
        items: {'item-1': item(minStockRoom: 10)},
      );

      // 10 − (2 + 2) = 6, not (10 − 2) + (10 − 2) = 16.
      expect(lines.single.suggestedQty, Quantity.parse('6'));
    });

    test('item yang sama pada dua opname menjadi satu baris PR', () {
      final lines = calculator(
        snapshots: [
          snapshot(
            opnameId: 'so-1',
            roomId: 'room-1',
            lines: [position('item-1', '1')],
          ),
          snapshot(
            opnameId: 'so-2',
            roomId: 'room-2',
            roomName: 'Ruang Dental 2',
            lines: [position('item-1', '1')],
          ),
        ],
        items: {'item-1': item(minStockRoom: 5)},
      );

      expect(
        lines,
        hasLength(1),
        reason: 'Deduplikasi per item, bukan per opname.',
      );
      expect(lines.single.suggestedQty, Quantity.parse('8'));
    });

    test('dua opname ruangan yang sama tidak dihitung ganda', () {
      // G-P1 admits the current *and* the previous week, so a branch head can
      // legitimately cite two counts of one room. Summing both would double-count the
      // same shelf: a par of 5 counted at 2 last week and 4 this week is a deficiency
      // of 1, not of 3 + 1. The newest count per room wins.
      final lines = calculator(
        snapshots: [
          snapshot(
            opnameId: 'so-lastweek',
            roomId: 'room-1',
            week: 30,
            lines: [position('item-1', '2')],
          ),
          snapshot(
            opnameId: 'so-thisweek',
            roomId: 'room-1',
            week: 31,
            lines: [position('item-1', '4')],
          ),
        ],
        items: {'item-1': item(minStockRoom: 5)},
      );

      expect(lines.single.suggestedQty, Quantity.parse('1'));
      expect(lines.single.countedTotal, Quantity.parse('4'));
    });

    test('pemilihan opname terbaru per ruangan lintas tahun ISO', () {
      final lines = calculator(
        snapshots: [
          snapshot(
            opnameId: 'so-2025',
            roomId: 'room-1',
            year: 2025,
            week: 52,
            lines: [position('item-1', '1')],
          ),
          snapshot(
            opnameId: 'so-2026',
            roomId: 'room-1',
            year: 2026,
            week: 1,
            lines: [position('item-1', '4')],
          ),
        ],
        items: {'item-1': item(minStockRoom: 5)},
      );

      expect(
        lines.single.suggestedQty,
        Quantity.parse('1'),
        reason: '2026-W01 lebih baru dari 2025-W52.',
      );
    });

    test('ruangan yang sudah di atas par tidak dicatat sebagai sumber', () {
      final lines = calculator(
        snapshots: [
          snapshot(
            opnameId: 'so-1',
            roomId: 'room-1',
            roomName: 'Ruang Dental 1',
            lines: [position('item-1', '1')],
          ),
          snapshot(
            opnameId: 'so-2',
            roomId: 'room-2',
            roomName: 'Ruang Dental 2',
            lines: [position('item-1', '5')],
          ),
        ],
        items: {'item-1': item(minStockRoom: 5)},
      );

      expect(lines.single.suggestedQty, Quantity.parse('4'));
      expect(
        lines.single.sourceRoomNames,
        ['Ruang Dental 1'],
        reason:
            'Ruangan yang tidak kekurangan bukan sumber saran; mencantumkannya '
            'akan salah menjelaskan angkanya.',
      );
    });

    test('baris diurutkan menurut nama barang', () {
      final lines = calculator(
        snapshots: [
          snapshot(lines: [position('item-z', '0'), position('item-a', '0')]),
        ],
        items: {
          'item-z': item(
            id: 'item-z',
            sku: 'SKU-Z',
            name: 'Zinc Oxide',
            minStockRoom: 2,
          ),
          'item-a': item(
            id: 'item-a',
            sku: 'SKU-A',
            name: 'Alkohol',
            minStockRoom: 2,
          ),
        },
      );

      expect(lines.map((line) => line.itemName), ['Alkohol', 'Zinc Oxide']);
    });
  });

  group('barang nonaktif dan tidak dikenal', () {
    test('barang nonaktif tidak disarankan', () {
      final lines = calculator(
        snapshots: [
          snapshot(lines: [position('item-1', '0')]),
        ],
        items: {'item-1': item(minStockRoom: 5, isActive: false)},
      );

      expect(
        lines,
        isEmpty,
        reason:
            'Barang yang sudah dinonaktifkan tidak boleh diminta pada dokumen '
            'baru (G-A4).',
      );
    });

    test('barang yang tidak ada pada katalog dilewati kalkulator', () {
      // Deciding what a missing master row *means* is the calling use case's job —
      // it raises a broken-reference failure, which a pure calculator cannot do
      // honestly.
      final lines = calculator(
        snapshots: [
          snapshot(lines: [position('item-hilang', '0')]),
        ],
        items: const <String, MasterItem>{},
      );
      expect(lines, isEmpty);
    });
  });

  group('terhadap database', () {
    test(
      'draft dibuat dengan saran agregat multi-ruangan dan multi-batch',
      () async {
        final fixture = await buildPurchaseRequestFixture(
          context,
          now: prWednesdayUtc(),
        );
        final roomOne = await fileOpnameForRoom(
          context,
          roomId: fixture.roomOne.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );
        final roomTwo = await fileOpnameForRoom(
          context,
          roomId: fixture.roomTwo.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );

        final request = await context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [roomOne, roomTwo],
            );

        final detail = await context.requests.getDetail(request.id);
        final byItem = {for (final line in detail!.lines) line.itemId: line};

        // simpleItem: par 5, R1 holds 2.5 and R2 holds 1 → 2.5 + 4 = 6.5 box.
        expect(
          byItem[fixture.simpleItem.id]!.suggestedQty,
          Quantity.parse('6.5'),
        );
        // batchItem: par 10, R2 holds 2 + 2 across two batches → 10 − 4 = 6 ampul.
        expect(byItem[fixture.batchItem.id]!.suggestedQty, Quantity.parse('6'));
        // abundantItem: par 0, so never short. Not a line at all.
        expect(byItem.containsKey(fixture.abundantItem.id), isFalse);
        // unstockedItem: on no count, so nothing to suggest.
        expect(byItem.containsKey(fixture.unstockedItem.id), isFalse);
      },
    );

    test('requested_qty draft dimulai dari saran sistem', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      final detail = await context.requests.getDetail(request.id);
      for (final line in detail!.lines) {
        expect(line.requestedQty, line.suggestedQty);
        expect(line.requestedQty.isPositive, isTrue);
      }
    });

    test('barang nonaktif tidak muncul pada draft baru', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      // R1 holds 1 of spareItem against a par of 4, so it would otherwise be
      // suggested at 3 pcs.
      await context.deactivate('items', fixture.spareItem.id);

      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      final detail = await context.requests.getDetail(request.id);
      expect(
        detail!.lines.map((line) => line.itemId),
        isNot(contains(fixture.spareItem.id)),
      );
    });

    test('saran tidak memakai saldo terkini, hanya snapshot opname', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );

      // Stock arrives in the room *after* the count. The suggestion must not notice:
      // the whole point of ordering against an opname is that the numbers are the
      // ones somebody physically wrote down.
      await context
          .postingWithClock(prWednesdayUtc)
          .postOpnameAdjustment(
            locationId: fixture.locationOne.id,
            itemId: fixture.simpleItem.id,
            countedQty: Quantity.parse('99'),
            actorUserId: fixture.warehouseUser.id,
            refDocType: RefDocType.seed,
            refDocId: 'after-the-count',
          );

      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      final detail = await context.requests.getDetail(request.id);
      final line = detail!.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );
      // 5 − 2.5 = 2.5, computed from the counted snapshot rather than from the 99
      // now sitting on the shelf.
      expect(line.suggestedQty, Quantity.parse('2.5'));
    });

    test('snapshot saran tidak berubah setelah PR dibuat', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      final before = (await context.requests.getDetail(request.id))!.lines
          .firstWhere((line) => line.itemId == fixture.simpleItem.id)
          .suggestedQty;

      // Both a par-level change and a stock movement leave the snapshot alone.
      await context.database.customStatement(
        'UPDATE items SET min_stock_room = 99 WHERE id = ?;',
        [fixture.simpleItem.id],
      );
      await context
          .postingWithClock(prWednesdayUtc)
          .postOpnameAdjustment(
            locationId: fixture.locationOne.id,
            itemId: fixture.simpleItem.id,
            countedQty: Quantity.zero(),
            actorUserId: fixture.warehouseUser.id,
            refDocType: RefDocType.seed,
            refDocId: 'emptied',
          );

      final after = (await context.requests.getDetail(request.id))!.lines
          .firstWhere((line) => line.itemId == fixture.simpleItem.id)
          .suggestedQty;
      expect(after, before);
    });
  });

  group('mengubah daftar opname pada draft', () {
    test('menambah ruangan menghitung ulang saran', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final roomOne = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final roomTwo = await fileOpnameForRoom(
        context,
        roomId: fixture.roomTwo.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );

      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [roomOne],
          );
      expect(
        (await context.requests.getDetail(request.id))!.lines
            .firstWhere((line) => line.itemId == fixture.simpleItem.id)
            .suggestedQty,
        Quantity.parse('2.5'),
      );

      final updated = await context
          .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            prId: request.id,
            selectedOpnameIds: [roomOne, roomTwo],
          );

      expect(
        updated.lines
            .firstWhere((line) => line.itemId == fixture.simpleItem.id)
            .suggestedQty,
        Quantity.parse('6.5'),
      );
      // The second room's batch item is now proposed as well.
      expect(
        updated.lines.map((line) => line.itemId),
        contains(fixture.batchItem.id),
      );
      expect(await context.purchaseRequestOpnameLinkCount(request.id), 2);
    });

    test(
      'jumlah yang sudah diedit pengguna dipertahankan saat recompute',
      () async {
        final fixture = await buildPurchaseRequestFixture(
          context,
          now: prWednesdayUtc(),
        );
        final roomOne = await fileOpnameForRoom(
          context,
          roomId: fixture.roomOne.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );
        final roomTwo = await fileOpnameForRoom(
          context,
          roomId: fixture.roomTwo.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );

        final request = await context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [roomOne],
            );
        final line = (await context.requests.getDetail(
          request.id,
        ))!.lines.firstWhere((line) => line.itemId == fixture.simpleItem.id);

        // The branch head asks for 3 rather than the suggested 2.5 — below the 150 %
        // threshold, so no note is needed.
        await context.updatePurchaseRequest.line(
          actorUserId: fixture.branchHead.id,
          lineId: line.id,
          requestedQty: Quantity.parse('3'),
        );

        final updated = await context
            .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              prId: request.id,
              selectedOpnameIds: [roomOne, roomTwo],
            );

        final after = updated.lines.firstWhere(
          (line) => line.itemId == fixture.simpleItem.id,
        );
        expect(
          after.requestedQty,
          Quantity.parse('3'),
          reason: 'Angka yang sudah ditulis Kepala Cabang tidak boleh ditimpa.',
        );
        expect(after.suggestedQty, Quantity.parse('6.5'));
        expect(
          after.id,
          line.id,
          reason: 'Baris di-update, bukan dibuat ulang.',
        );
      },
    );

    test(
      'baris yang hilang dari saran menjadi permintaan manual, bukan dihapus',
      () async {
        final fixture = await buildPurchaseRequestFixture(
          context,
          now: prWednesdayUtc(),
        );
        final roomOne = await fileOpnameForRoom(
          context,
          roomId: fixture.roomOne.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );
        final roomTwo = await fileOpnameForRoom(
          context,
          roomId: fixture.roomTwo.id,
          nurseId: fixture.nurse.id,
          utcNow: prWednesdayUtc(),
        );

        // Start from both rooms, so the batch item is proposed…
        final request = await context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [roomOne, roomTwo],
            );
        final batchLine = (await context.requests.getDetail(
          request.id,
        ))!.lines.firstWhere((line) => line.itemId == fixture.batchItem.id);
        await context.updatePurchaseRequest.line(
          actorUserId: fixture.branchHead.id,
          lineId: batchLine.id,
          requestedQty: Quantity.parse('7'),
          note: 'Stok cadangan tindakan',
        );

        // …then drop the room that justified it.
        final updated = await context
            .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              prId: request.id,
              selectedOpnameIds: [roomOne],
            );

        final after = updated.lines.firstWhere(
          (line) => line.itemId == fixture.batchItem.id,
        );
        expect(
          after.requestedQty,
          Quantity.parse('7'),
          reason: 'Menghapus baris diam-diam akan membuang keputusan pengguna.',
        );
        expect(after.suggestedQty, Quantity.zero());
        expect(
          after.isManualRequest,
          isTrue,
          reason:
              'Tanpa saran, baris menjadi permintaan manual dan catatan menjadi '
              'wajib (G-P3).',
        );
        expect(after.note, 'Stok cadangan tindakan');
      },
    );

    test('recompute tidak dapat dijalankan pada PR submitted', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final roomOne = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final roomTwo = await fileOpnameForRoom(
        context,
        roomId: fixture.roomTwo.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [roomOne],
          );
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: fixture.branchHead.id, prId: request.id);

      await expectLater(
        () => context
            .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              prId: request.id,
              selectedOpnameIds: [roomOne, roomTwo],
            ),
        throwsA(isA<Object>()),
      );
      expect(await context.purchaseRequestOpnameLinkCount(request.id), 1);
    });
  });
}
