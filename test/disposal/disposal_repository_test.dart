import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/disposal/domain/models/disposal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// What the repository reads back, and when its streams re-emit (§45).
///
/// The streams are the interesting half. A screen renders from them, so a write that
/// does not reach one is a screen that shows stale numbers until it is reopened —
/// and on this document a stale number is a quantity somebody is about to destroy.
void main() {
  final nowUtc = DateTime.utc(2026, 7, 30, 4);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> warehouseDraft({String reason = 'Kedaluwarsa'}) =>
      createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
        reason: reason,
      );

  Future<void> addExpired(String id, String qty, {String? batchId}) =>
      addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: batchId ?? fixture.expiredBatch.id,
        qty: qty,
        nowUtc: nowUtc,
      );

  group('pemetaan', () {
    test('milli-unit dipetakan ke Quantity dan tidak pernah bocor', () async {
      final id = await warehouseDraft();
      await addExpired(id, '2.375');

      final detail = await context.disposals.getDetail(id);
      expect(detail!.lines.single.qty, Quantity.parse('2.375'));
      // Q-6: the scale never reaches anything above the repository.
      expect(detail.lines.single.qty.format(), '2.375');
    });

    test('tanggal kedaluwarsa dibaca verbatim sebagai tanggal sipil', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');

      final line = (await context.disposals.getDetail(id))!.lines.single;
      final batch = await context.master.batchById(fixture.expiredBatch.id);
      // T-8/T-9: never timezone converted on the way out.
      expect(line.expiryDate, batch!.expiryDate);
      expect(line.expiryDate.hour, 0);
      expect(line.expiryDate.isUtc, isTrue);
    });

    test('status teks dipetakan ke enum', () async {
      final id = await warehouseDraft();
      expect(
        (await context.disposals.getById(id))!.status,
        DisposalStatus.draft,
      );

      await addExpired(id, '1');
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);
      expect(
        (await context.disposals.getById(id))!.status,
        DisposalStatus.posted,
      );
    });

    test('ringkasan memuat nama lokasi, pembuat dan pemosting', () async {
      final id = await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
        reason: 'Kedaluwarsa',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
      );

      var detail = (await context.disposals.getForBranch(
        disposalId: id,
        branchId: fixture.branch.id,
      ))!;
      expect(detail.summary.source.name, fixture.locationOne.name);
      expect(detail.summary.source.kindLabel, 'Ruangan');
      expect(detail.summary.branchName, fixture.branch.name);
      expect(detail.summary.roomCode, fixture.roomOne.code);
      expect(detail.summary.createdByName, fixture.branchHead.fullName);
      // Null while it is a draft — there is no poster yet.
      expect(detail.summary.postedByName, isNull);

      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);

      detail = (await context.disposals.getForBranch(
        disposalId: id,
        branchId: fixture.branch.id,
      ))!;
      expect(detail.summary.postedByName, fixture.branchHead.fullName);
    });

    test('ringkasan warehouse tidak memiliki cabang maupun ruangan', () async {
      // The left joins are what keep the warehouse's own documents visible: an inner
      // join on `branches` would make every one of them vanish from the list.
      final id = await warehouseDraft();
      final detail = await context.disposals.getForWarehouse(id);

      expect(detail, isNotNull);
      expect(detail!.summary.branchName, isNull);
      expect(detail.summary.roomName, isNull);
      expect(detail.summary.source.kindLabel, 'Warehouse Pusat');
    });

    test('hitungan ringkasan dihitung SQL, bukan dari baris', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      await addExpired(id, '0.25', batchId: fixture.staleBatch.id);

      final rows = await context.disposals.listForWarehouse();
      final summary = rows.single;
      expect(summary.lineCount, 2);
      expect(summary.itemCount, 1);
      expect(summary.batchCount, 2);
      expect(summary.label, '2 posisi · 1 barang');
    });

    test('baris yang dihapus lunak tidak menggelembungkan hitungan', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      await addExpired(id, '0.25', batchId: fixture.staleBatch.id);
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      ))['${fixture.expiryItem.id}|${fixture.staleBatch.id}']!;

      await context.removeDisposalLine.call(
        actorUserId: fixture.warehouseUser.id,
        disposalId: id,
        lineId: lineId,
      );

      expect((await context.disposals.listForWarehouse()).single.lineCount, 1);
    });
  });

  group('stream', () {
    test('draft baru muncul di daftar yang di-scope', () async {
      final emissions = <List<DisposalSummary>>[];
      final subscription = context.disposals.watchListForWarehouse().listen(
        emissions.add,
      );
      await pumpEventQueue();

      await warehouseDraft();
      await pumpEventQueue();

      expect(emissions.last, hasLength(1));
      await subscription.cancel();
    });

    test('menambah baris memancarkan detail baru', () async {
      final id = await warehouseDraft();
      final emissions = <DisposalDetail?>[];
      final subscription = context.disposals
          .watchForWarehouse(id)
          .listen(emissions.add);
      await pumpEventQueue();

      await addExpired(id, '1');
      await pumpEventQueue();

      expect(emissions.last!.lineCount, 1);
      await subscription.cancel();
    });

    test('mengubah jumlah memancarkan detail baru', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      final emissions = <DisposalDetail?>[];
      final subscription = context.disposals
          .watchForWarehouse(id)
          .listen(emissions.add);
      await pumpEventQueue();

      await context
          .updateDisposalLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            disposalId: id,
            lineId: lineId,
            qty: Quantity.parse('2.5'),
          );
      await pumpEventQueue();

      expect(emissions.last!.lines.single.qty, Quantity.parse('2.5'));
      await subscription.cancel();
    });

    test('menghapus baris memancarkan detail baru', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      final emissions = <DisposalDetail?>[];
      final subscription = context.disposals
          .watchForWarehouse(id)
          .listen(emissions.add);
      await pumpEventQueue();

      await context.removeDisposalLine.call(
        actorUserId: fixture.warehouseUser.id,
        disposalId: id,
        lineId: lineId,
      );
      await pumpEventQueue();

      expect(emissions.last!.isEmpty, isTrue);
      await subscription.cancel();
    });

    test('mengubah alasan memancarkan detail baru', () async {
      final id = await warehouseDraft();
      final emissions = <DisposalDetail?>[];
      final subscription = context.disposals
          .watchForWarehouse(id)
          .listen(emissions.add);
      await pumpEventQueue();

      await context.updateDisposalHeader.call(
        actorUserId: fixture.warehouseUser.id,
        disposalId: id,
        reason: 'Pembersihan stok lama',
      );
      await pumpEventQueue();

      expect(emissions.last!.disposal.reason, 'Pembersihan stok lama');
      await subscription.cancel();
    });

    test('posting mengubah status pada stream', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');

      final emissions = <DisposalDetail?>[];
      final subscription = context.disposals
          .watchForWarehouse(id)
          .listen(emissions.add);
      await pumpEventQueue();

      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);
      await pumpEventQueue();

      expect(emissions.last!.isPosted, isTrue);
      expect(emissions.last!.summary.postedByName, isNotNull);
      await subscription.cancel();
    });

    test(
      'stream cabang tidak pernah memancarkan dokumen cabang lain',
      () async {
        final emissions = <List<DisposalSummary>>[];
        final subscription = context.disposals
            .watchListForBranch(branchId: fixture.otherBranch.id)
            .listen(emissions.add);
        await pumpEventQueue();

        await createDisposalDraft(
          context,
          fixture,
          sourceLocationId: fixture.branchStore.id,
          nowUtc: nowUtc,
          actorUserId: fixture.branchHead.id,
          reason: 'Kedaluwarsa',
        );
        await pumpEventQueue();

        for (final emission in emissions) {
          expect(emission, isEmpty);
        }
        await subscription.cancel();
      },
    );

    test('stok kedaluwarsa berkurang setelah pemusnahan penuh', () async {
      final emissions = <List<ExpiredStockPosition>>[];
      final subscription = context.disposals
          .watchExpiredPositions(
            sourceLocationId: fixture.warehouse.id,
            nowUtc: nowUtc,
          )
          .listen(emissions.add);
      await pumpEventQueue();
      final before = emissions.last.length;

      final id = await warehouseDraft();
      await addExpired(id, '1.25', batchId: fixture.staleBatch.id);
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);
      await pumpEventQueue();

      expect(emissions.last, hasLength(before - 1));
      expect(
        emissions.last.map((position) => position.batchId),
        isNot(contains(fixture.staleBatch.id)),
      );
      await subscription.cancel();
    });

    test(
      'pemusnahan sebagian memperbarui saldo tersedia pada stream',
      () async {
        final emissions = <List<ExpiredStockPosition>>[];
        final subscription = context.disposals
            .watchExpiredPositions(
              sourceLocationId: fixture.warehouse.id,
              nowUtc: nowUtc,
            )
            .listen(emissions.add);
        await pumpEventQueue();

        final id = await warehouseDraft();
        await addExpired(id, '0.375', batchId: fixture.staleBatch.id);
        await context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id);
        await pumpEventQueue();

        final remaining = emissions.last.firstWhere(
          (position) => position.batchId == fixture.staleBatch.id,
        );
        expect(remaining.qtyOnHand, Quantity.parse('0.875'));
        await subscription.cancel();
      },
    );
  });

  group('penyaringan', () {
    test('filter status memisahkan draft dan riwayat', () async {
      final draft = await warehouseDraft();
      final posted = await warehouseDraft();
      await addExpired(posted, '1');
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: posted);

      expect(
        (await context.disposals.listForWarehouse(
          statuses: {DisposalStatus.draft},
        )).map((row) => row.id),
        [draft],
      );
      expect(
        (await context.disposals.listForWarehouse(
          statuses: {DisposalStatus.posted},
        )).map((row) => row.id),
        [posted],
      );
    });

    test('pencarian menemukan nomor dokumen, lokasi dan barang', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      final docNumber = (await context.disposals.getById(id))!.docNumber;

      for (final needle in [
        docNumber,
        'warehouse',
        'anestesi',
        'dsp-0001',
        'b-expired',
      ]) {
        expect(
          await context.disposals.listForWarehouse(searchQuery: needle),
          hasLength(1),
          reason: 'pencarian "$needle" tidak menemukan dokumen.',
        );
      }
    });

    test('pencarian yang tidak cocok mengembalikan kosong', () async {
      final id = await warehouseDraft();
      await addExpired(id, '1');
      expect(
        await context.disposals.listForWarehouse(searchQuery: 'tidak-ada-ini'),
        isEmpty,
      );
    });

    test('filter lokasi mempersempit di dalam cakupan cabang', () async {
      final storeDoc = await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.branchStore.id,
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
        reason: 'Kedaluwarsa',
      );
      await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
        reason: 'Kedaluwarsa',
      );

      final storeOnly = await context.disposals.listForBranch(
        branchId: fixture.branch.id,
        sourceLocationId: fixture.branchStore.id,
      );
      expect(storeOnly.map((row) => row.id), [storeDoc]);

      // And it only ever narrows: a location outside the branch matches nothing
      // rather than widening the scope.
      expect(
        await context.disposals.listForBranch(
          branchId: fixture.branch.id,
          sourceLocationId: fixture.warehouse.id,
        ),
        isEmpty,
      );
    });
  });

  group('transaksi', () {
    test('rollback membersihkan seluruh tulisan dalam transaksi', () async {
      final id = await warehouseDraft();

      await expectLater(
        context.disposals.runInTransaction<void>(() async {
          await context.disposals.addLine(
            disposalId: id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.expiredBatch.id,
            qty: Quantity.parse('1'),
          );
          throw StateError('batalkan');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await context.disposalLineCount(id), 0);
    });
  });

  group('lokasi sumber', () {
    test('warehouse mengembalikan lokasi warehouse saja', () async {
      final locations = await context.disposals.warehouseSourceLocations();
      expect(locations.map((location) => location.id), [fixture.warehouse.id]);
    });

    test(
      'cabang mengembalikan gudang dan ruangannya, gudang lebih dahulu',
      () async {
        final locations = await context.disposals.branchSourceLocations(
          fixture.branch.id,
        );
        expect(locations.first.type, StockLocationType.branchStore);
        expect(locations.map((location) => location.id).toSet(), {
          fixture.branchStore.id,
          fixture.locationOne.id,
          fixture.locationTwo.id,
        });
      },
    );

    test(
      'lokasi historis dapat dibaca kembali termasuk yang diarsipkan',
      () async {
        await context.archive('stock_locations', fixture.locationTwo.id);

        // Absent from the "may I use it" list…
        expect(
          (await context.disposals.branchSourceLocations(
            fixture.branch.id,
          )).map((location) => location.id),
          isNot(contains(fixture.locationTwo.id)),
        );
        // …and still readable by id, which is what keeps a posted document's source
        // nameable (§34).
        final historical = await context.disposals.historicalLocationById(
          fixture.locationTwo.id,
        );
        expect(historical, isNotNull);
        expect(historical!.isArchived, isTrue);
      },
    );
  });
}
