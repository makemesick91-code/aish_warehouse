import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Repository behaviour and live streams (§48).
///
/// The stream assertions matter for one reason a `Future`-based test cannot cover: a
/// screen holds a subscription, and a decision written from anywhere has to reach it.
/// `expectLater(stream, emitsThrough(...))` is how that is checked without sleeping.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> shippedOrder({String qty = '2.5'}) => shipDeliveryOrderFor(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [
      simpleAllocation(fixture, qty: qty),
      safeBatchAllocation(fixture, qty: '4'),
    ],
  );

  Future<String> checkingReceipt() async => startGoodReceiptFor(
    context,
    fixture,
    deliveryOrderId: await shippedOrder(),
    nowUtc: nowUtc,
  );

  /// A second receipt on the same request, allocating a *different* position.
  ///
  /// G-D2 caps the cumulative shipped quantity per requested position, so a second
  /// shipment cannot repeat the first one's items — which is the delivery rule working,
  /// not an obstacle. The tie item is untouched by [shippedOrder], so it is what a second
  /// document ships.
  Future<String> secondCheckingReceipt() async => startGoodReceiptFor(
    context,
    fixture,
    deliveryOrderId: await shipDeliveryOrderFor(
      context,
      fixture,
      nowUtc: nowUtc,
      allocations: [tieAllocation(fixture, qty: '2')],
    ),
    nowUtc: nowUtc,
  );

  group('pembuatan dan pembacaan', () {
    test('GR baru muncul pada daftar cabang', () async {
      final grId = await checkingReceipt();

      final list = await context.receipts.listForBranch(
        branchId: fixture.branch.id,
      );

      expect(list.map((row) => row.id), [grId]);
      expect(list.single.status, GoodReceiptStatus.checking);
      expect(list.single.progress.total, 2);
      expect(list.single.progress.pending, 2);
    });

    test('ringkasan membawa nomor dokumen dan nama pelaku', () async {
      final grId = await checkingReceipt();
      final detail = await context.receipts.getForBranch(
        grId: grId,
        branchId: fixture.branch.id,
      );

      expect(detail!.summary.doDocNumber, startsWith('TMP-DO-'));
      expect(detail.summary.prDocNumber, startsWith('TMP-PR-'));
      expect(detail.summary.branchCode, fixture.branch.code);
      expect(detail.summary.receivedByName, fixture.branchHead.fullName);
      expect(detail.summary.shippedByName, fixture.warehouseUser.fullName);
      expect(detail.summary.doStatus, DeliveryOrderStatus.shipped);
      expect(detail.summary.doShippedAt, nowUtc);
    });

    test('findByDeliveryOrder menemukan GR satu pengiriman', () async {
      final doId = await shippedOrder();
      expect(await context.receipts.findByDeliveryOrder(doId), isNull);

      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );

      expect((await context.receipts.findByDeliveryOrder(doId))!.id, grId);
    });

    test('deliveryOrderLineIds membaca tanpa join', () async {
      final doId = await shippedOrder();
      final expected = await context.deliveries.lineReferences(doId);

      expect(
        (await context.receipts.deliveryOrderLineIds(doId)).toSet(),
        expected.map((line) => line.id).toSet(),
      );
    });

    test(
      'lineReferenceById mengembalikan identitas tanpa data master',
      () async {
        final grId = await checkingReceipt();
        final line = (await context.receipts.lineReferences(grId)).first;

        final reference = await context.receipts.lineReferenceById(line.id);

        expect(reference!.grId, grId);
        expect(reference.doLineId, line.doLineId);
        expect(reference.lineStatus, GoodReceiptLineStatus.pending);
        expect(await context.receipts.lineReferenceById('tidak-ada'), isNull);
      },
    );

    test(
      'kuantitas melewati batas sebagai Quantity, bukan milli-unit',
      () async {
        final grId = await checkingReceipt();
        final lines = await context.receipts.lineReferences(grId);

        // Q-4: the milli-unit integers stay behind the implementation.
        expect(
          lines.map((line) => line.shippedQty),
          containsAll([Quantity.parse('2.5'), Quantity.parse('4')]),
        );
      },
    );
  });

  group('stream detail', () {
    test('check baris memancarkan detail baru', () async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.first;

      final stream = context.receipts.watchForBranch(
        grId: grId,
        branchId: fixture.branch.id,
      );

      expectLater(
        stream,
        emitsThrough(
          predicate<GoodReceiptDetail?>(
            (detail) => detail != null && detail.progress.checked == 1,
            'detail dengan satu baris checked',
          ),
        ),
      );

      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        receivedQty: Quantity.parse('1'),
      );
    });

    test('reject baris memancarkan detail baru', () async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.first;

      expectLater(
        context.receipts.watchForBranch(
          grId: grId,
          branchId: fixture.branch.id,
        ),
        emitsThrough(
          predicate<GoodReceiptDetail?>(
            (detail) =>
                detail != null &&
                detail.hasRejectedLines &&
                detail.lines.any((row) => row.rejectReason == 'Rusak'),
            'detail dengan satu baris rejected beralasan',
          ),
        ),
      );

      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        reason: 'Rusak',
      );
    });

    test('progres berubah sampai semua diputuskan', () async {
      final grId = await checkingReceipt();

      expectLater(
        context.receipts.watchForBranch(
          grId: grId,
          branchId: fixture.branch.id,
        ),
        emitsThrough(
          predicate<GoodReceiptDetail?>(
            (detail) => detail != null && detail.canPost,
            'detail yang siap diposting',
          ),
        ),
      );

      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
    });

    test('posting memancarkan status posted', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      expectLater(
        context.receipts.watchForBranch(
          grId: grId,
          branchId: fixture.branch.id,
        ),
        emitsThrough(
          predicate<GoodReceiptDetail?>(
            (detail) => detail != null && detail.isPosted,
            'detail posted',
          ),
        ),
      );

      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
    });

    test('stream cabang lain tidak pernah memancarkan dokumen ini', () async {
      final grId = await checkingReceipt();

      expectLater(
        context.receipts.watchForBranch(
          grId: grId,
          branchId: fixture.otherBranch.id,
        ),
        emits(isNull),
      );

      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: (await context.receipts.getDetail(
          grId,
        ))!.lines.first.id,
        receivedQty: Quantity.parse('1'),
      );
    });

    test('stream warehouse memancarkan dokumen hanya setelah posted', () async {
      final grId = await checkingReceipt();

      expectLater(
        context.receipts.watchForWarehouse(grId),
        emitsInOrder([
          isNull,
          emitsThrough(
            predicate<GoodReceiptDetail?>(
              (detail) => detail != null && detail.isPosted,
              'detail posted',
            ),
          ),
        ]),
      );

      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
    });
  });

  group('stream daftar', () {
    test('daftar cabang memancarkan GR baru', () async {
      expectLater(
        context.receipts.watchListForBranch(branchId: fixture.branch.id),
        emitsThrough(hasLength(1)),
      );

      await checkingReceipt();
    });

    test('antrean menunggu kosong setelah GR diposting', () async {
      final grId = await checkingReceipt();

      expectLater(
        context.receipts.watchAwaitingDeliveryOrders(
          branchId: fixture.branch.id,
        ),
        emitsThrough(isEmpty),
      );

      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
    });

    test('antrean menunggu tetap memuat GR checking', () async {
      final doId = await shippedOrder();

      expectLater(
        context.receipts.watchAwaitingDeliveryOrders(
          branchId: fixture.branch.id,
        ),
        emitsThrough(
          predicate<List<GoodReceiptAwaitingDelivery>>(
            (rows) => rows.length == 1 && rows.single.hasReceipt,
            'antrean dengan GR yang sudah dimulai',
          ),
        ),
      );

      await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
    });

    test('antrean selisih warehouse muncul setelah posting', () async {
      final grId = await checkingReceipt();
      final byItem = await goodReceiptLinesByItem(context, grId);

      expectLater(
        context.receipts.watchWarehouseDiscrepancies(const GoodReceiptFilter()),
        emitsThrough(hasLength(2)),
      );

      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: byItem[fixture.simpleItem.id]!.id,
        receivedQty: Quantity.parse('1'),
      );
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: byItem[fixture.batchItem.id]!.id,
        reason: 'Rusak',
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
    });

    test('stream Surat Jalan menjadi received', () async {
      final doId = await shippedOrder();
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );

      expectLater(
        context.deliveries.watchForBranch(
          doId: doId,
          branchId: fixture.branch.id,
        ),
        emitsThrough(
          predicate<Object?>(
            (detail) =>
                detail != null &&
                (detail as dynamic).status == DeliveryOrderStatus.received,
            'Surat Jalan received',
          ),
        ),
      );

      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
    });
  });

  group('pencarian dan filter', () {
    /// A posted receipt with one shortage and one refusal, so both filters have
    /// something to select.
    Future<String> postedWithBoth() async {
      final grId = await checkingReceipt();
      final byItem = await goodReceiptLinesByItem(context, grId);
      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: byItem[fixture.simpleItem.id]!.id,
        receivedQty: Quantity.parse('1'),
      );
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: byItem[fixture.batchItem.id]!.id,
        reason: 'Rusak',
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
      return grId;
    }

    test(
      'pencarian daftar warehouse menemukan lewat nomor dan barang',
      () async {
        final grId = await postedWithBoth();
        final receipt = await context.receipts.getById(grId);
        final order = await context.deliveries.getById(receipt!.doId);

        for (final needle in [
          receipt.docNumber,
          order!.docNumber,
          fixture.branch.name,
          fixture.branch.code,
          fixture.simpleItem.name,
          fixture.simpleItem.sku,
        ]) {
          expect(
            await context.receipts.listForWarehouse(
              GoodReceiptFilter(searchQuery: needle),
            ),
            hasLength(1),
            reason: 'Pencarian "$needle" tidak menemukan GR.',
          );
        }
        expect(
          await context.receipts.listForWarehouse(
            const GoodReceiptFilter(searchQuery: 'tidak-ada'),
          ),
          isEmpty,
        );
      },
    );

    test('pencarian tidak peka huruf besar-kecil', () async {
      await postedWithBoth();

      expect(
        await context.receipts.listForWarehouse(
          GoodReceiptFilter(searchQuery: fixture.simpleItem.name.toUpperCase()),
        ),
        hasLength(1),
      );
    });

    test('filter cabang mempersempit antrean selisih', () async {
      await postedWithBoth();

      expect(
        await context.receipts.warehouseDiscrepancies(
          GoodReceiptFilter(branchId: fixture.branch.id),
        ),
        hasLength(2),
      );
      expect(
        await context.receipts.warehouseDiscrepancies(
          GoodReceiptFilter(branchId: fixture.otherBranch.id),
        ),
        isEmpty,
      );
    });

    test('filter tanggal posting mempersempit antrean selisih', () async {
      await postedWithBoth();

      expect(
        await context.receipts.warehouseDiscrepancies(
          GoodReceiptFilter(
            postedFromUtc: nowUtc.subtract(const Duration(hours: 1)),
            postedToUtc: nowUtc.add(const Duration(hours: 1)),
          ),
        ),
        hasLength(2),
      );
      expect(
        await context.receipts.warehouseDiscrepancies(
          GoodReceiptFilter(postedFromUtc: nowUtc.add(const Duration(days: 1))),
        ),
        isEmpty,
      );
    });

    test('filter status daftar cabang menyaring checking dan posted', () async {
      final posted = await postedWithBoth();
      final checking = await secondCheckingReceipt();

      expect(
        (await context.receipts.listForBranch(
          branchId: fixture.branch.id,
          statuses: const {GoodReceiptStatus.posted},
        )).map((row) => row.id),
        [posted],
      );
      expect(
        (await context.receipts.listForBranch(
          branchId: fixture.branch.id,
          statuses: const {GoodReceiptStatus.checking},
        )).map((row) => row.id),
        [checking],
      );
    });

    test('daftar warehouse mengabaikan permintaan status checking', () async {
      await checkingReceipt();

      // Intersecting rather than trusting the caller is what makes the restriction a
      // property of the method instead of a convention its callers follow.
      expect(
        await context.receipts.listForWarehouse(
          const GoodReceiptFilter(statuses: {GoodReceiptStatus.checking}),
        ),
        isEmpty,
      );
    });
  });

  group('penulisan terjaga', () {
    test('keputusan pada GR posted mengembalikan false, bukan menulis', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
      final line = (await context.receipts.lineReferences(grId)).first;
      final before = await context.goodReceiptLineRows(grId);

      // The guard is in the statement, so the repository reports "no rows" rather than
      // succeeding against a final document.
      expect(
        await context.receipts.decideChecked(
          grId: grId,
          lineId: line.id,
          receivedQty: Quantity.zero(),
        ),
        isFalse,
      );
      expect(
        await context.receipts.decideRejected(
          grId: grId,
          lineId: line.id,
          reason: 'Rusak',
        ),
        isFalse,
      );
      expect(
        await context.receipts.resetDecision(grId: grId, lineId: line.id),
        isFalse,
      );
      expect(await context.goodReceiptLineRows(grId), before);
    });

    test('baris dari GR lain mengembalikan false', () async {
      final first = await checkingReceipt();
      final second = await secondCheckingReceipt();
      final foreignLine = (await context.receipts.lineReferences(second)).first;

      expect(
        await context.receipts.decideChecked(
          grId: first,
          lineId: foreignLine.id,
          receivedQty: Quantity.zero(),
        ),
        isFalse,
      );
    });

    test('kuantitas di luar batas ditolak oleh statement', () async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.lineReferences(
        grId,
      )).firstWhere((row) => row.itemId == fixture.simpleItem.id);

      // `? <= shipped_qty` travels into the UPDATE, so a stale client cannot receive
      // more than was sent even if the domain check were somehow skipped.
      expect(
        await context.receipts.decideChecked(
          grId: grId,
          lineId: line.id,
          receivedQty: Quantity.parse('99'),
        ),
        isFalse,
      );
      expect(
        await context.receipts.decideChecked(
          grId: grId,
          lineId: line.id,
          receivedQty: Quantity.fromMilliUnits(-1),
        ),
        isFalse,
      );
    });

    test('alasan kosong ditolak oleh statement', () async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.lineReferences(grId)).first;

      expect(
        await context.receipts.decideRejected(
          grId: grId,
          lineId: line.id,
          reason: '   ',
        ),
        isFalse,
      );
    });

    test('postAtomically mengembalikan false ketika ada baris pending', () async {
      final grId = await checkingReceipt();
      final receipt = await context.receipts.getById(grId);
      final order = await context.deliveries.getById(receipt!.doId);

      // G-G2 is re-checked *inside* the UPDATE, which is what a second device deciding a
      // line between the read and the write would otherwise defeat.
      expect(
        await context.receipts.postAtomically(
          grId: grId,
          postedAtUtc: nowUtc,
          deliveryOrderId: order!.id,
          prId: order.prId,
          closeRequest: false,
        ),
        isFalse,
      );
      expect(await context.goodReceiptStatusOf(grId), 'checking');
    });

    test('createChecking menolak GR kedua dengan kegagalan bisnis', () async {
      final doId = await shippedOrder();
      await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );

      // The unique index fires, and the repository translates it rather than letting a
      // driver error surface.
      await expectLater(
        context.receipts.createChecking(
          docNumber: 'TMP-GR-manual',
          deliveryOrderId: doId,
          receivedBy: fixture.branchHead.id,
          lines: const [],
        ),
        throwsA(isA<GoodReceiptAlreadyExistsFailure>()),
      );
      expect(await context.goodReceiptCountFor(doId), 1);
    });

    test('transaksi yang gagal tidak meninggalkan apa pun', () async {
      final doId = await shippedOrder();

      await context.receipts
          .runInTransaction(() async {
            await context.receipts.createChecking(
              docNumber: 'TMP-GR-rollback',
              deliveryOrderId: doId,
              receivedBy: fixture.branchHead.id,
              lines: const [],
            );
            throw const ValidationFailure('Kegagalan buatan.');
          })
          .then<void>((_) {}, onError: (_, _) {});

      expect(await context.goodReceiptCountFor(doId), 0);
    });
  });

  group('status pengiriman untuk penutupan', () {
    test(
      'shipmentDeliveryOrdersOf memuat setiap DO hidup dengan statusnya',
      () async {
        final first = await shippedOrder(qty: '1');
        final draft = await prepareDeliveryOrder(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [simpleAllocation(fixture, qty: '0.5')],
        );

        final shipments = await context.receipts.shipmentDeliveryOrdersOf(
          fixture.purchaseRequestId,
        );

        expect(shipments.map((row) => row.doId), containsAll([first, draft]));
        expect(
          shipments.firstWhere((row) => row.doId == first).status,
          DeliveryOrderStatus.shipped,
        );
        expect(
          shipments.firstWhere((row) => row.doId == draft).status,
          DeliveryOrderStatus.preparing,
        );
      },
    );
  });

  group('data historis tetap terbaca', () {
    test('GR tetap muncul setelah cabang dinonaktifkan', () async {
      final grId = await checkingReceipt();
      await context.deactivate('branches', fixture.branch.id);

      final detail = await context.receipts.getForBranch(
        grId: grId,
        branchId: fixture.branch.id,
      );

      // A shipment whose branch was retired afterwards is exactly the receipt that still
      // has to be posted, so it is labelled rather than hidden.
      expect(detail, isNotNull);
      expect(detail!.summary.branchIsHistorical, isTrue);
      expect(detail.usesHistoricalMaster, isTrue);
    });

    test('GR tetap muncul setelah barang dinonaktifkan', () async {
      final grId = await checkingReceipt();
      await context.deactivate('items', fixture.simpleItem.id);

      final detail = await context.receipts.getForBranch(
        grId: grId,
        branchId: fixture.branch.id,
      );

      expect(detail!.lines, hasLength(2));
      expect(
        detail.lines
            .firstWhere((line) => line.itemId == fixture.simpleItem.id)
            .itemIsHistorical,
        isTrue,
      );
    });

    test('GR tetap muncul setelah petugas pengirim dinonaktifkan', () async {
      final grId = await checkingReceipt();
      await context.deactivate('users', fixture.warehouseUser.id);

      final detail = await context.receipts.getForBranch(
        grId: grId,
        branchId: fixture.branch.id,
      );

      expect(detail!.summary.shippedByName, fixture.warehouseUser.fullName);
    });
  });
}
