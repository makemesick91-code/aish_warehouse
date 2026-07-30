import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The repository contract and its live streams (§23, §43).
///
/// Two things are checked. **Mapping**, because the boundary is where milli-units
/// become `Quantity`, TEXT becomes an enum and a UTC string becomes an instant — and
/// a mistake there is invisible to every rule test above it. And **reactivity**,
/// because these screens are streams: a write that does not reach the list is a
/// write the officer cannot see happened.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> preparedSimple({String qty = '1'}) => prepareDeliveryOrder(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [simpleAllocation(fixture, qty: qty)],
  );

  group('pemetaan', () {
    test(
      'kuantitas melewati batas sebagai Quantity, bukan milli-unit',
      () async {
        final doId = await preparedSimple(qty: '2.375');
        final detail = await context.deliveries.getForWarehouse(doId);

        expect(detail!.lines.single.shippedQty, Quantity.parse('2.375'));
        expect(detail.lines.single.shippedQty.format(), '2.375');
        // Nothing above the repository ever sees the scale.
        expect(detail.lines.single.requestedQty, Quantity.parse('3'));
      },
    );

    test('status, sync dan timestamp dipetakan sebagai tipe domain', () async {
      final doId = await preparedSimple();
      var detail = await context.deliveries.getForWarehouse(doId);

      expect(detail!.status, DeliveryOrderStatus.preparing);
      expect(detail.order.syncStatus, SyncStatus.pending);
      expect(detail.order.createdAt.isUtc, isTrue);
      expect(detail.order.shippedAt, isNull);

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      detail = await context.deliveries.getForWarehouse(doId);
      expect(detail!.status, DeliveryOrderStatus.shipped);
      expect(detail.order.shippedAt!.isUtc, isTrue);
      expect(detail.summary.shippedByName, fixture.warehouseUser.fullName);
    });

    test('expiry date dibaca apa adanya sebagai civil date', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      final detail = await context.deliveries.getForWarehouse(doId);

      // T-9: no timezone conversion on the way out either — 12 days from
      // 2026-07-30 is 2026-08-11 and stays that date.
      final expiry = detail!.lines.single.expiryDate!;
      expect(expiry.year, 2026);
      expect(expiry.month, 8);
      expect(expiry.day, 11);
      expect(detail.lines.single.remainingDays(nowUtc), 12);
      expect(detail.lines.single.isNearExpiryOn(nowUtc), isTrue);
      expect(detail.lines.single.isExpiredOn(nowUtc), isFalse);
    });

    test('label historis terbaca meski master ditarik', () async {
      final doId = await preparedSimple();
      await context.deactivate('items', fixture.simpleItem.id);
      await context.deactivate('branches', fixture.branch.id);

      final detail = await context.deliveries.getForWarehouse(doId);
      expect(detail!.summary.branchName, fixture.branch.name);
      expect(detail.summary.branchCode, fixture.branch.code);
      expect(detail.summary.branchAddress, 'Jl. Uji No. 1');
      expect(detail.lines.single.sku, fixture.simpleItem.sku);
      expect(detail.usesHistoricalMaster, isTrue);
    });

    test('total per satuan tidak mencampur satuan berbeda', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '1'),
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1.5',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      final detail = await context.deliveries.getForWarehouse(doId);

      // `2 box` and `3 ampul` are not `5` of anything.
      expect(detail!.shippedByUnit, {
        'box': Quantity.parse('1'),
        'ampul': Quantity.parse('1.5'),
      });
    });

    test(
      'jumlah baris pada ringkasan tidak dipengaruhi baris terhapus',
      () async {
        final doId = await prepareDeliveryOrder(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [
            simpleAllocation(fixture, qty: '1'),
            batchAllocation(
              fixture,
              batchId: fixture.nearBatch.id,
              qty: '1',
              nearExpiryConfirmed: true,
            ),
          ],
        );
        final lineIds = await deliveryLineIdsByAllocation(context, doId);
        await context.removeDeliveryLine.call(
          actorUserId: fixture.warehouseUser.id,
          lineId: lineIds['${fixture.simpleLineId}|']!,
        );

        final summaries = await context.deliveries.listByPurchaseRequest(
          fixture.purchaseRequestId,
        );
        expect(
          summaries.firstWhere((summary) => summary.id == doId).lineCount,
          1,
        );
      },
    );

    test(
      'progres pengiriman dihitung untuk dokumen dan untuk PR saja',
      () async {
        final doId = await preparedSimple(qty: '1');

        // With the document named, its own allocations are counted separately.
        final withDoc = await context.deliveries.shipmentProgress(
          prId: fixture.purchaseRequestId,
          doId: doId,
        );
        final simple = withDoc.firstWhere(
          (entry) => entry.prLineId == fixture.simpleLineId,
        );
        expect(simple.currentDoQty, Quantity.parse('1'));
        expect(simple.previouslyShippedQty, Quantity.zero());
        expect(simple.remainingAfterCurrentDo, Quantity.parse('2'));

        // Without it — how the "create a shipment" screen asks — nothing is
        // allocated yet.
        final withoutDoc = await context.deliveries.shipmentProgress(
          prId: fixture.purchaseRequestId,
        );
        expect(
          withoutDoc
              .firstWhere((entry) => entry.prLineId == fixture.simpleLineId)
              .currentDoQty,
          Quantity.zero(),
        );
      },
    );

    test(
      'Surat Jalan memakai nama warehouse yang diberikan pemanggil',
      () async {
        final doId = await preparedSimple();
        final waybill = await context.deliveries.waybill(
          doId: doId,
          warehouseName: 'Warehouse Pusat',
          printedAtUtc: nowUtc,
        );

        expect(waybill!.warehouseName, 'Warehouse Pusat');
        expect(waybill.printedAtUtc, nowUtc);
        expect(waybill.isDraft, isTrue);
        expect(waybill.title, 'DRAFT — BELUM DIKIRIM');

        await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        );
        final shipped = await context.deliveries.waybill(
          doId: doId,
          warehouseName: 'Warehouse Pusat',
          printedAtUtc: nowUtc,
        );
        expect(shipped!.isDraft, isFalse);
        expect(shipped.title, 'SURAT JALAN');
      },
    );
  });

  group('stream', () {
    test('Surat Jalan baru muncul pada daftar warehouse', () async {
      final stream = context.deliveries.watchListForWarehouse(
        const DeliveryOrderFilter(),
      );
      expect(await stream.first, isEmpty);

      final doId = await preparedSimple();
      expect((await stream.first).map((summary) => summary.id), contains(doId));
    });

    test('edit baris memancarkan detail baru', () async {
      final doId = await preparedSimple();
      final lineIds = await deliveryLineIdsByAllocation(context, doId);
      final stream = context.deliveries.watchForWarehouse(doId);

      expect(
        (await stream.first)!.lines.single.shippedQty,
        Quantity.parse('1'),
      );

      await context.updateDeliveryLine().call(
        actorUserId: fixture.warehouseUser.id,
        lineId: lineIds['${fixture.simpleLineId}|']!,
        shippedQty: Quantity.parse('2'),
      );
      expect(
        (await stream.first)!.lines.single.shippedQty,
        Quantity.parse('2'),
      );
    });

    test('pengiriman mengubah status pada stream', () async {
      final doId = await preparedSimple();
      final stream = context.deliveries.watchForWarehouse(doId);
      expect((await stream.first)!.status, DeliveryOrderStatus.preparing);

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      expect((await stream.first)!.status, DeliveryOrderStatus.shipped);
    });

    test(
      'daftar cabang menerima dokumen setelah dikirim, bukan sebelumnya',
      () async {
        final stream = context.deliveries.watchListForBranch(
          branchId: fixture.branch.id,
        );
        final doId = await preparedSimple();
        expect(await stream.first, isEmpty);

        await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        );
        expect(
          (await stream.first).map((summary) => summary.id),
          contains(doId),
        );
      },
    );

    test('beberapa Surat Jalan satu PR semuanya muncul', () async {
      final first = await preparedSimple(qty: '1');
      final second = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );

      final rows = await context.deliveries
          .watchByPurchaseRequest(fixture.purchaseRequestId)
          .first;
      expect(rows.map((summary) => summary.id).toSet(), {first, second});
    });

    test('dokumen preparing yang di-soft-delete hilang dari daftar', () async {
      final doId = await preparedSimple();
      expect(
        (await context.deliveries
                .watchListForWarehouse(const DeliveryOrderFilter())
                .first)
            .map((summary) => summary.id),
        contains(doId),
      );

      expect(await context.deliveries.removePreparing(doId), isTrue);
      expect(
        await context.deliveries
            .watchListForWarehouse(const DeliveryOrderFilter())
            .first,
        isEmpty,
      );
    });

    test('dokumen shipped tidak dapat di-soft-delete', () async {
      final doId = await preparedSimple();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      // The ledger movements point at it; removing it would leave them describing a
      // shipment nothing claims to have made (G-A5/G-S2).
      expect(await context.deliveries.removePreparing(doId), isFalse);
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });
  });

  group('filter dan pencarian', () {
    test('filter status', () async {
      final preparing = await preparedSimple();
      final shipped = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: shipped,
      );

      final onlyPreparing = await context.deliveries.listForWarehouse(
        const DeliveryOrderFilter(statuses: {DeliveryOrderStatus.preparing}),
      );
      expect(onlyPreparing.map((summary) => summary.id), [preparing]);

      final onlyShipped = await context.deliveries.listForWarehouse(
        const DeliveryOrderFilter(statuses: {DeliveryOrderStatus.shipped}),
      );
      expect(onlyShipped.map((summary) => summary.id), [shipped]);
    });

    test('filter cabang', () async {
      final ours = await preparedSimple();

      final otherPrId = await writeProcessingPurchaseRequest(
        context,
        branchId: fixture.otherBranch.id,
        requestedBy: fixture.otherBranchHead.id,
        processedBy: fixture.warehouseUser.id,
        nowUtc: nowUtc,
        lines: {fixture.simpleItem.id: '1'},
        prId: 'pr-other',
      );
      final theirs = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: otherPrId,
      );

      expect(
        (await context.deliveries.listForWarehouse(
          DeliveryOrderFilter(branchId: fixture.branch.id),
        )).map((summary) => summary.id),
        [ours],
      );
      expect(
        (await context.deliveries.listForWarehouse(
          DeliveryOrderFilter(branchId: fixture.otherBranch.id),
        )).map((summary) => summary.id),
        [theirs.id],
      );
    });

    test('pencarian nomor DO, nomor PR, cabang dan barang', () async {
      final doId = await preparedSimple();
      final detail = await context.deliveries.getForWarehouse(doId);

      Future<List<String>> search(String query) async =>
          (await context.deliveries.listForWarehouse(
            DeliveryOrderFilter(searchQuery: query),
          )).map((summary) => summary.id).toList();

      // Document number, in part and case-insensitively.
      expect(await search(detail!.summary.docNumber), [doId]);
      expect(await search('tmp-do'), [doId]);
      // Purchase Request number.
      expect(await search(detail.summary.prDocNumber), [doId]);
      // Branch name and code.
      expect(await search('Cabang Uji'), [doId]);
      expect(await search('cab-01'), [doId]);
      // Item name and SKU of something the shipment carries.
      expect(await search('Masker'), [doId]);
      expect(await search('DO-0001'), [doId]);
      // And something it does not.
      expect(await search('Tidak Ada Barang Ini'), isEmpty);
    });

    test('pencarian barang tidak memotong jumlah baris', () async {
      // The item search is a subquery rather than a join, precisely so a document
      // found by one of its items still reports all of them.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '1'),
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );

      final rows = await context.deliveries.listForWarehouse(
        const DeliveryOrderFilter(searchQuery: 'Masker'),
      );
      expect(rows.single.id, doId);
      expect(rows.single.lineCount, 2);
    });
  });

  group('penulisan terjaga', () {
    test('edit basi ditolak setelah dokumen dikirim', () async {
      final doId = await preparedSimple();
      final lineIds = await deliveryLineIdsByAllocation(context, doId);
      final lineId = lineIds['${fixture.simpleLineId}|']!;

      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      // Straight at the repository, bypassing the use case guards: the predicate is
      // inside the statement, so it still refuses.
      expect(
        await context.deliveries.updatePreparingLine(
          lineId: lineId,
          shippedQty: Quantity.parse('2'),
        ),
        isFalse,
      );
      expect(
        await context.deliveries.replacePreparingLines(
          doId: doId,
          allocations: [simpleAllocation(fixture, qty: '2')],
        ),
        isFalse,
      );
      expect(await context.deliveries.removePreparingLine(lineId), isFalse);
      expect(
        await context.deliveries.updatePreparingNote(
          doId: doId,
          note: 'Diubah setelah kirim',
        ),
        isFalse,
      );
      expect(
        await context.deliveries.addPreparingLine(
          doId: doId,
          allocation: simpleAllocation(fixture, qty: '1'),
        ),
        isNull,
      );

      // The posted allocation is untouched.
      final lines = await context.deliveries.lineReferences(doId);
      expect(lines.single.shippedQty, Quantity.parse('1'));
      expect(await context.deliveryLineCount(doId), 1);
    });

    test(
      'markShipped kedua kali melaporkan gagal, bukan menulis ulang',
      () async {
        final doId = await preparedSimple();
        await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        );
        final firstShippedAt = await context.deliveryOrderColumn(
          doId,
          'shipped_at',
        );

        expect(
          await context.deliveries.markShipped(
            doId: doId,
            shippedBy: fixture.secondWarehouseUser.id,
            shippedAtUtc: nowUtc.add(const Duration(hours: 1)),
            prId: fixture.purchaseRequestId,
            completesRequest: false,
          ),
          isFalse,
        );
        // Neither the actor nor the instant was overwritten.
        expect(
          await context.deliveryOrderColumn(doId, 'shipped_at'),
          firstShippedAt,
        );
        expect(
          await context.deliveryOrderColumn(doId, 'shipped_by'),
          fixture.warehouseUser.id,
        );
      },
    );

    test('transaksi yang gagal tidak meninggalkan apa pun', () async {
      final before = await context.balancesAt(fixture.warehouse.id);

      await expectLater(
        () => context.deliveries.runInTransaction(() async {
          await context.deliveries.createPreparing(
            docNumber: 'TMP-DO-rollback',
            prId: fixture.purchaseRequestId,
            preparedBy: fixture.warehouseUser.id,
            allocations: [simpleAllocation(fixture, qty: '1')],
            createdAtUtc: nowUtc,
          );
          throw const ValidationFailure('Batalkan transaksi.');
        }),
        throwsA(isA<ValidationFailure>()),
      );

      expect(
        await context.deliveries.listByPurchaseRequest(
          fixture.purchaseRequestId,
        ),
        isEmpty,
      );
      expect(await context.balancesAt(fixture.warehouse.id), before);
    });

    test('audit expiry dinormalisasi agar CHECK tidak pernah dilanggar', () async {
      // A form legitimately reaches all three of these states while it is being
      // filled in: a note typed before the box is ticked, whitespace in a reason, an
      // audit left over from a batch that was then cleared. None of them is an error
      // the officer needs told about — they are just not facts yet — so the mapping
      // drops them rather than letting a CHECK fire and surface as
      // "Terjadi kesalahan tak terduga".
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          // A note without a confirmation.
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryNote: 'Ditulis sebelum dicentang',
          ),
          // An expiry audit on an item that has no batch at all.
          DeliveryAllocation(
            prLineId: fixture.simpleLineId,
            itemId: fixture.simpleItem.id,
            qty: Quantity.parse('1'),
            fefoOverrideReason: 'Tidak berlaku untuk barang tanpa batch',
            nearExpiryConfirmed: true,
            nearExpiryNote: 'Juga tidak berlaku',
          ),
          // Whitespace in both.
          DeliveryAllocation(
            prLineId: fixture.tieLineId,
            itemId: fixture.tieItem.id,
            batchId: fixture.tieBatchA.id,
            qty: Quantity.parse('1'),
            fefoOverrideReason: '   ',
            nearExpiryConfirmed: true,
            nearExpiryNote: '  ',
          ),
        ],
      );

      final lines = {
        for (final line in await context.deliveries.lineReferences(doId))
          line.prLineId: line,
      };

      final withoutConfirmation = lines[fixture.batchLineId]!;
      expect(withoutConfirmation.nearExpiryConfirmed, isFalse);
      expect(withoutConfirmation.nearExpiryNote, isNull);

      final withoutBatch = lines[fixture.simpleLineId]!;
      expect(withoutBatch.batchId, isNull);
      expect(withoutBatch.fefoOverrideReason, isNull);
      expect(withoutBatch.nearExpiryConfirmed, isFalse);
      expect(withoutBatch.nearExpiryNote, isNull);

      final blank = lines[fixture.tieLineId]!;
      expect(blank.fefoOverrideReason, isNull);
      expect(blank.nearExpiryConfirmed, isTrue);
      expect(blank.nearExpiryNote, isNull);
    });

    test('edit baris menormalisasi audit yang sama', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
            nearExpiryNote: 'Awal',
          ),
        ],
      );
      final lineIds = await deliveryLineIdsByAllocation(context, doId);

      // Un-ticking the confirmation must take its note with it.
      expect(
        await context.deliveries.updatePreparingLine(
          lineId: lineIds['${fixture.batchLineId}|${fixture.nearBatch.id}']!,
          shippedQty: Quantity.parse('1'),
          batchId: fixture.nearBatch.id,
          nearExpiryNote: 'Masih tertinggal',
        ),
        isTrue,
      );

      final line = (await context.deliveries.lineReferences(doId)).single;
      expect(line.nearExpiryConfirmed, isFalse);
      expect(line.nearExpiryNote, isNull);
    });

    test(
      'doc_number unik ditolak sebagai kegagalan, bukan diam-diam',
      () async {
        await context.deliveries.createPreparing(
          docNumber: 'TMP-DO-fixed',
          prId: fixture.purchaseRequestId,
          preparedBy: fixture.warehouseUser.id,
          allocations: const <DeliveryAllocation>[],
          createdAtUtc: nowUtc,
        );

        await expectLater(
          () => context.deliveries.createPreparing(
            docNumber: 'TMP-DO-fixed',
            prId: fixture.purchaseRequestId,
            preparedBy: fixture.warehouseUser.id,
            allocations: const <DeliveryAllocation>[],
            createdAtUtc: nowUtc,
          ),
          throwsA(anything),
        );
        expect(
          (await context.deliveries.listByPurchaseRequest(
            fixture.purchaseRequestId,
          )).length,
          1,
        );
      },
    );
  });
}
