import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The ledger a posted Pemakaian writes (§41).
///
/// Every assertion here is about one shape:
///
/// ```
/// movement_type   = consumption
/// from_location_id = <room location>
/// to_location_id   = NULL
/// ref_doc_type     = CONS
/// ref_doc_id       = <consumption id>
/// actor_user_id    = <the nurse who posted>
/// ```
///
/// `to_location_id IS NULL` is what §2.2 states directly — *"NULL jika barang keluar
/// sistem (pemakaian/buang)"* — and it is the fact that makes every other test in this
/// file necessary: a movement with nothing on the other side has no counter-entry to
/// reconcile against, so if it were written wrongly nothing downstream would notice.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draft({String? roomId, String? note}) =>
      createConsumptionDraft(
        context,
        fixture,
        roomId: roomId ?? fixture.roomOne.id,
        nowUtc: nowUtc,
        note: note,
      );

  Future<Quantity> balanceAt(
    String locationId, {
    required String itemId,
    String? batchId,
  }) => locationBalance(
    context,
    locationId: locationId,
    itemId: itemId,
    batchId: batchId,
  );

  group('bentuk movement', () {
    late String consumptionId;

    setUp(() async {
      consumptionId = await draft(note: 'shift pagi');
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: consumptionId,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '2.5',
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: consumptionId,
        itemId: fixture.plainItem.id,
        qty: '1.25',
        nowUtc: nowUtc,
        note: 'satu box rusak saat dibuka',
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: consumptionId,
      );
    });

    test('satu movement per baris aktif', () async {
      expect(await context.consumptionMovementCount(consumptionId), 2);
      expect(await context.consumptionLineCount(consumptionId), 2);
    });

    test('movement_type adalah consumption', () async {
      final movements = await context.consumptionMovements(consumptionId);
      for (final movement in movements) {
        expect(movement['movement_type'], 'consumption');
      }
    });

    test(
      'from_location_id adalah lokasi ruangan, to_location_id NULL',
      () async {
        final movements = await context.consumptionMovements(consumptionId);
        for (final movement in movements) {
          expect(movement['from_location_id'], fixture.locationOne.id);
          expect(
            movement['to_location_id'],
            isNull,
            reason: 'Pemakaian mengeluarkan barang dari sistem (§2.2/§19).',
          );
        }
      },
    );

    test('ref_doc_type adalah CONS dan ref_doc_id dokumennya', () async {
      final movements = await context.consumptionMovements(consumptionId);
      for (final movement in movements) {
        expect(movement['ref_doc_type'], 'CONS');
        expect(movement['ref_doc_id'], consumptionId);
      }
      expect(RefDocType.consumption, 'CONS');
    });

    test('ref_doc_type bukan DIST, DSP maupun SO', () async {
      // A shared `ref_doc_type` would make the stock card unable to say which document a
      // movement came from, and `movementsByRef` would return both.
      expect(RefDocType.consumption, isNot(RefDocType.distribution));
      expect(RefDocType.consumption, isNot(RefDocType.disposal));
      expect(RefDocType.consumption, isNot(RefDocType.stockOpname));

      final byDist = await context.inventory.movementsByRef(
        refDocType: RefDocType.distribution,
        refDocId: consumptionId,
      );
      expect(byDist, isEmpty);
      final byDisposal = await context.inventory.movementsByRef(
        refDocType: RefDocType.disposal,
        refDocId: consumptionId,
      );
      expect(byDisposal, isEmpty);
    });

    test('actor adalah perawat yang memposting', () async {
      final movements = await context.consumptionMovements(consumptionId);
      for (final movement in movements) {
        expect(movement['actor_user_id'], fixture.nurse.id);
      }
    });

    test('batch dipertahankan; barang tanpa ED membawa batch NULL', () async {
      final movements = await context.consumptionMovements(consumptionId);
      final byItem = {
        for (final movement in movements)
          movement['item_id'] as String: movement,
      };

      expect(byItem[fixture.expiryItem.id]!['batch_id'], fixture.validBatch.id);
      expect(byItem[fixture.plainItem.id]!['batch_id'], isNull);
    });

    test('qty movement adalah milli-unit eksak', () async {
      final movements = await context.consumptionMovements(consumptionId);
      final byItem = {
        for (final movement in movements)
          movement['item_id'] as String: movement,
      };

      expect(byItem[fixture.expiryItem.id]!['qty'], 2500);
      expect(byItem[fixture.plainItem.id]!['qty'], 1250);
    });

    test('catatan movement menggabungkan catatan header dan baris', () async {
      final movements = await context.consumptionMovements(consumptionId);
      final byItem = {
        for (final movement in movements)
          movement['item_id'] as String: movement,
      };

      // Header only.
      expect(byItem[fixture.expiryItem.id]!['note'], 'shift pagi');
      // Header plus the line's own detail, joined the same way for every row.
      expect(
        byItem[fixture.plainItem.id]!['note'],
        'shift pagi · satu box rusak saat dibuka',
      );
    });

    test('catatan movement boleh NULL bila keduanya kosong', () async {
      // The difference from a Pemusnahan: G-E7 makes a disposal note mandatory, and
      // nothing makes a consumption note mandatory (§19).
      final bare = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: bare,
        itemId: fixture.otherPlainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: bare,
      );

      final movements = await context.consumptionMovements(bare);
      expect(movements.single['note'], isNull);
    });
  });

  group('efek saldo', () {
    test('saldo ruangan berkurang tepat sejumlah pemakaian', () async {
      final before = await balanceAt(
        fixture.locationOne.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
      );

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

      expect(
        await balanceAt(
          fixture.locationOne.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        ),
        before - Quantity.parse('1.5'),
      );
    });

    test('tidak ada lokasi tujuan yang bertambah', () async {
      final storeBefore = await balanceAt(
        fixture.branchStore.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
      );
      final warehouseBefore = await balanceAt(
        fixture.warehouse.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
      );
      final otherRoomBefore = await balanceAt(
        fixture.locationTwo.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
      );

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
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(
        await balanceAt(
          fixture.branchStore.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        ),
        storeBefore,
        reason: 'Gudang Cabang tidak boleh berubah.',
      );
      expect(
        await balanceAt(
          fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        ),
        warehouseBefore,
        reason: 'Warehouse Pusat tidak boleh berubah.',
      );
      expect(
        await balanceAt(
          fixture.locationTwo.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        ),
        otherRoomBefore,
        reason: 'Ruangan lain tidak boleh berubah.',
      );
    });

    test('saldo ruangan lain cabang tidak berubah', () async {
      final before = await balanceAt(
        fixture.otherBranchRoomLocation.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
      );

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
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(
        await balanceAt(
          fixture.otherBranchRoomLocation.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
        ),
        before,
      );
    });

    test('batch lain dari barang yang sama tidak berubah', () async {
      final nearBefore = await balanceAt(
        fixture.locationOne.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.nearBatch.id,
      );

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
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(
        await balanceAt(
          fixture.locationOne.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.nearBatch.id,
        ),
        nearBefore,
      );
    });

    test('saldo dapat mencapai nol tetapi tidak negatif', () async {
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

      final after = await balanceAt(
        fixture.locationOne.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
      );
      expect(after, Quantity.zero());
      expect(after.isNegative, isFalse);
    });
  });

  group('dokumen lain tidak tersentuh', () {
    test(
      'opname, PR, DO, GR, distribusi dan pemusnahan tidak berubah',
      () async {
        final before = <String, int>{
          'stock_opnames': await _countOf(context, 'stock_opnames'),
          'purchase_requests': await _countOf(context, 'purchase_requests'),
          'delivery_orders': await _countOf(context, 'delivery_orders'),
          'good_receipts': await _countOf(context, 'good_receipts'),
          'distributions': await _countOf(context, 'distributions'),
          'disposals': await _countOf(context, 'disposals'),
        };

        final id = await draft();
        await addConsumptionPosition(
          context,
          fixture,
          consumptionId: id,
          itemId: fixture.plainItem.id,
          qty: '1',
          nowUtc: nowUtc,
        );
        await context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        );

        for (final entry in before.entries) {
          expect(
            await _countOf(context, entry.key),
            entry.value,
            reason: '${entry.key} berubah saat posting Pemakaian.',
          );
        }
      },
    );

    test('movement jenis lain tidak bertambah', () async {
      final before = {
        for (final type in StockMovementType.values)
          type: await context.movementCountOfType(type),
      };

      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      for (final type in StockMovementType.values) {
        final expected = type == StockMovementType.consumption
            ? before[type]! + 1
            : before[type]!;
        expect(
          await context.movementCountOfType(type),
          expected,
          reason: 'Jumlah movement ${type.dbValue} berubah tak terduga.',
        );
      }
    });
  });

  group('append-only (G-A1)', () {
    test('movement asli tidak diubah oleh posting kedua yang gagal', () async {
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
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      final first = await context.consumptionMovements(id);
      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(anything),
      );
      expect(await context.consumptionMovements(id), first);
    });

    test('dokumen posted bersifat read-only', () async {
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

      // Every write path refuses, and none of them writes a movement.
      await expectLater(
        context.updateConsumptionHeader.call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
          note: 'sesudah',
        ),
        throwsA(anything),
      );
      await expectLater(
        context
            .updateConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              lineId: lineId,
              qty: Quantity.parse('2'),
            ),
        throwsA(anything),
      );
      await expectLater(
        context.removeConsumptionLine.call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
          lineId: lineId,
        ),
        throwsA(anything),
      );
      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.otherPlainItem.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(anything),
      );

      expect(await context.consumptionMovementCount(id), 1);
      expect(await context.consumptionLineCount(id), 1);
      final rows = await context.consumptionLineRows(id);
      expect(rows[lineId]!['qty'], Quantity.parse('1').milliUnits);
    });

    test('pembalikan tetap movement baru, bukan edit', () async {
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
      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );
      final original = result.movements.single;

      final reversal = await context.posting.postReversal(
        movementId: original.id,
        actorUserId: fixture.nurse.id,
        note: 'salah catat',
      );

      expect(reversal.id, isNot(original.id));
      expect(reversal.movementType, StockMovementType.reversal);
      expect(reversal.reversalOfMovementId, original.id);
      // The mirror image: what left the room comes back into it.
      expect(reversal.fromLocationId, isNull);
      expect(reversal.toLocationId, fixture.locationOne.id);
      // And the original row is untouched.
      final refetched = await context.inventory.movementById(original.id);
      expect(refetched!.qty, original.qty);
      expect(refetched.note, original.note);
      expect(refetched.movementType, StockMovementType.consumption);
    });
  });

  group('audit dokumen', () {
    test('status, postedAt dan postedBy terisi', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(result.consumption.status, ConsumptionStatus.posted);
      expect(result.consumption.postedAt, nowUtc);
      expect(result.consumption.postedAt!.isUtc, isTrue);
      expect(result.consumption.postedBy, fixture.nurse.id);
      expect(result.consumption.syncStatus, SyncStatus.pending);
      expect(await context.consumptionStatusOf(id), 'posted');
    });

    test('hasil posting menamai ruangan dan lokasinya, tanpa tujuan', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(result.room.id, fixture.roomOne.id);
      expect(result.roomLocation.id, fixture.locationOne.id);
      expect(result.roomLocation.type, StockLocationType.room);
      expect(result.plan.roomId, fixture.roomOne.id);
      expect(result.plan.roomLocationId, fixture.locationOne.id);
      expect(result.lineCount, 1);
      expect(result.totalQty, Quantity.parse('1'));
    });

    test('postedAt lebih awal dari createdAt ditolak', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final behind = nowUtc.subtract(const Duration(microseconds: 1));
      await expectLater(
        context
            .postConsumption(clock: () => behind)
            .call(actorUserId: fixture.nurse.id, consumptionId: id),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );

      expect(await context.consumptionStatusOf(id), 'draft');
      expect(await context.consumptionMovementCount(id), 0);
    });

    test('postedAt sama dengan createdAt diterima', () async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final result = await context
          .postConsumption(clock: () => nowUtc)
          .call(actorUserId: fixture.nurse.id, consumptionId: id);
      expect(result.consumption.postedAt, nowUtc);
    });
  });

  group('kartu stok', () {
    test('movement pemakaian tampil pada kartu stok ruangan', () async {
      final id = await draft(note: 'shift pagi');
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      final card = await context.inventory.stockCard(
        itemId: fixture.expiryItem.id,
        locationId: fixture.locationOne.id,
      );

      final consumption = card.where(
        (movement) => movement.movementType == StockMovementType.consumption,
      );
      expect(consumption, hasLength(1));
      final movement = consumption.single;
      expect(movement.refDocType, RefDocType.consumption);
      expect(movement.refDocId, id);
      expect(movement.actorUserId, fixture.nurse.id);
      expect(movement.fromLocationId, fixture.locationOne.id);
      expect(movement.toLocationId, isNull);
      expect(movement.qty, Quantity.parse('2'));
      expect(movement.note, 'shift pagi');
    });

    test('movementsByRef menemukan seluruh baris dokumen', () async {
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
        qty: '2',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.consumption,
        refDocId: id,
      );
      expect(movements, hasLength(2));
      expect(movements.map((movement) => movement.itemId).toSet(), {
        fixture.expiryItem.id,
        fixture.plainItem.id,
      });
    });
  });

  group('urutan movement deterministik', () {
    test('rencana diurutkan item, batch, lalu baris', () async {
      final id = await draft();
      // Added in an order that is *not* the plan's, so a stable plan is doing the work
      // rather than insertion order.
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.nearBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      final batchIds = result.plan.entries
          .map((entry) => entry.batchId)
          .toList(growable: false);
      final sorted = [...batchIds]..sort();
      expect(batchIds, sorted);
    });

    test('posisi tanpa batch diurutkan sebelum posisi berbatch', () async {
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

      final result = await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      // Ordered by item id first, so the pairing below is what the plan guarantees:
      // within one item, `''` (no batch) precedes every batch id.
      final keys = result.plan.entries
          .map((entry) => entry.sourceKey)
          .toList(growable: false);
      final sorted = [...keys]..sort();
      expect(keys, sorted);
      expect(result.plan.sourcePositions, hasLength(2));
    });
  });
}

Future<int> _countOf(TestContext context, String table) async {
  final row = await context.database
      .customSelect('SELECT COUNT(*) AS c FROM $table;')
      .getSingle();
  return row.read<int>('c');
}
