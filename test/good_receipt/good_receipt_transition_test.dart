import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/delivery/domain/services/delivery_order_state_policy.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:aish_warehouse/features/good_receipt/domain/repositories/good_receipt_repository.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_closure_policy.dart';
import 'package:aish_warehouse/features/good_receipt/domain/use_cases/post_good_receipt_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/services/purchase_request_state_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_inventory_repository.dart';
import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';

/// `DO shipped → received` and `PR shipped → closed` — the two foreign transitions a
/// posted Good Receipt drives (§44, §22/§23).
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
    // Every closure test needs the whole request shippable, and the fixture is built
    // for the delivery tests, where two positions are deliberately short.
    await stockForFullShipment(context, fixture, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<GoodReceiptPostingResult> post(String grId) => context
      .postGoodReceipt()
      .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId);

  /// Ships [allocations], starts a receipt, accepts everything and posts it.
  Future<({String doId, String grId, GoodReceiptPostingResult result})>
  receiveInFull(List<Object> allocations) async {
    final doId = await shipDeliveryOrderFor(
      context,
      fixture,
      nowUtc: nowUtc,
      allocations: allocations.cast(),
    );
    final grId = await startGoodReceiptFor(
      context,
      fixture,
      deliveryOrderId: doId,
      nowUtc: nowUtc,
    );
    await checkEveryGoodReceiptLine(
      context,
      fixture,
      grId: grId,
      nowUtc: nowUtc,
    );
    return (doId: doId, grId: grId, result: await post(grId));
  }

  group('Surat Jalan menjadi received', () {
    test('posting GR menandai Surat Jalan diterima', () async {
      final outcome = await receiveInFull([
        simpleAllocation(fixture, qty: '2.5'),
      ]);

      expect(await context.deliveryOrderStatusOf(outcome.doId), 'received');
      expect(outcome.result.deliveryOrderReceived, isTrue);
    });

    test('penerimaan parsial tetap menandai Surat Jalan diterima', () async {
      // What makes a shipment `received` is that every position was *decided*, not
      // that everything arrived. The shortfall is the discrepancy the warehouse
      // follows up (G-G3); the shipment itself is done travelling.
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final line = (await context.receipts.getDetail(grId))!.lines.single;
      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        receivedQty: Quantity.parse('1'),
      );

      await post(grId);

      expect(await context.deliveryOrderStatusOf(doId), 'received');
    });

    test(
      'penolakan seluruh baris tetap menandai Surat Jalan diterima',
      () async {
        final doId = await shipDeliveryOrderFor(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [simpleAllocation(fixture, qty: '2.5')],
        );
        final grId = await startGoodReceiptFor(
          context,
          fixture,
          deliveryOrderId: doId,
          nowUtc: nowUtc,
        );
        final line = (await context.receipts.getDetail(grId))!.lines.single;
        await context.rejectGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          reason: 'Rusak',
        );

        await post(grId);

        expect(await context.deliveryOrderStatusOf(doId), 'received');
      },
    );

    test('Surat Jalan tetap shipped sebelum GR diposting', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      // Every decision is in, and the shipment is *still* `shipped`: what moves it is
      // posting, not checking.
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });

    test('transisi dinilai lewat DeliveryOrderStatePolicy', () {
      // Asserted rather than assumed, so this milestone cannot grow a second Delivery
      // Order state machine by accident.
      expect(
        DeliveryOrderStatePolicy.isGoodReceiptTransition(
          DeliveryOrderStatus.shipped,
          DeliveryOrderStatus.received,
        ),
        isTrue,
      );
      // And no role may drive it directly — it is a document's consequence.
      for (final role in UserRole.values) {
        expect(
          DeliveryOrderStatePolicy.isAllowedFor(
            role: role,
            from: DeliveryOrderStatus.shipped,
            to: DeliveryOrderStatus.received,
          ),
          isFalse,
        );
      }
    });
  });

  group('Purchase Request menjadi closed', () {
    test('satu-satunya Surat Jalan diterima menutup Purchase Request', () async {
      // One shipment covering every requested position moves the request to `shipped`
      // (G-D5); receiving it is then the last thing outstanding.
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: fullRequestAllocations(fixture),
      );
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'shipped',
      );

      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      final result = await post(grId);

      expect(result.purchaseRequestClosed, isTrue);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'closed',
      );
    });

    test(
      'Purchase Request processing tidak ditutup oleh penerimaan parsial',
      () async {
        // A partial shipment leaves the request `processing`, and `processing → closed`
        // is not a transition the state machine lists at all.
        final outcome = await receiveInFull([
          simpleAllocation(fixture, qty: '1'),
        ]);

        expect(
          await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
          'processing',
        );
        expect(outcome.result.purchaseRequestClosed, isFalse);
      },
    );

    test('masih ada Surat Jalan shipped menjaga PR tetap shipped', () async {
      // Two shipments that together cover the request exactly, which is what makes it
      // `shipped` and therefore closable.
      final firstDo = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '3'),
          safeBatchAllocation(fixture, qty: '4'),
        ],
      );
      final secondDo = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          tieAllocation(fixture, qty: '2'),
          tieAllocation(fixture, qty: '1', batchId: fixture.tieBatchB.id),
          scarceAllocation(fixture, qty: '2'),
        ],
      );
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'shipped',
      );

      final firstGr = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: firstDo,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: firstGr,
        nowUtc: nowUtc,
      );
      final firstResult = await post(firstGr);

      expect(firstResult.purchaseRequestClosed, isFalse);
      expect(firstResult.outstandingShipments, 1);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'shipped',
      );
      expect(await context.deliveryOrderStatusOf(firstDo), 'received');
      expect(await context.deliveryOrderStatusOf(secondDo), 'shipped');
    });

    test('Surat Jalan terakhir diterima menutup Purchase Request', () async {
      final firstDo = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '3'),
          safeBatchAllocation(fixture, qty: '4'),
        ],
      );
      final secondDo = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          tieAllocation(fixture, qty: '2'),
          tieAllocation(fixture, qty: '1', batchId: fixture.tieBatchB.id),
          scarceAllocation(fixture, qty: '2'),
        ],
      );

      for (final doId in [firstDo, secondDo]) {
        final grId = await startGoodReceiptFor(
          context,
          fixture,
          deliveryOrderId: doId,
          nowUtc: nowUtc,
        );
        await checkEveryGoodReceiptLine(
          context,
          fixture,
          grId: grId,
          nowUtc: nowUtc,
        );
        await post(grId);
      }

      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'closed',
      );
    });

    test('baris rejected tidak mencegah penutupan', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: fullRequestAllocations(fixture),
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final byItem = await goodReceiptLinesByItem(context, grId);
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: byItem[fixture.simpleItem.id]!.id,
        reason: 'Rusak',
      );
      final check = context.checkGoodReceiptLine();
      for (final line in (await context.receipts.getDetail(grId))!.lines) {
        if (line.itemId == fixture.simpleItem.id) continue;
        await check.call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: line.shippedQty,
        );
      }

      final result = await post(grId);

      // `closed` means the send-and-receive cycle finished, not that everything
      // arrived: the discrepancies stay on the warehouse's queue as their own
      // follow-up.
      expect(result.purchaseRequestClosed, isTrue);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'closed',
      );
      expect(
        await context.receipts.warehouseDiscrepancies(
          const GoodReceiptFilter(),
        ),
        isNotEmpty,
      );
    });

    test('kekurangan tidak mencegah penutupan', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: fullRequestAllocations(fixture),
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final check = context.checkGoodReceiptLine();
      for (final line in (await context.receipts.getDetail(grId))!.lines) {
        await check.call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          // Half of everything, in exact fixed point.
          receivedQty: line.shippedQty.scaledBy(numerator: 1, denominator: 2),
        );
      }

      final result = await post(grId);

      expect(result.purchaseRequestClosed, isTrue);
      expect(result.progress.shortage, greaterThan(0));
    });

    test('PR tidak ditutup sebelum GR diposting', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: fullRequestAllocations(fixture),
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'shipped',
      );
    });

    test('transisi dinilai lewat PurchaseRequestStatePolicy', () {
      expect(
        PurchaseRequestStatePolicy.isSystemTransition(
          PurchaseRequestStatus.shipped,
          PurchaseRequestStatus.closed,
        ),
        isTrue,
      );
      // `processing → closed` is not a transition at all, which is why a partial
      // shipment can never close a request.
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.processing,
          PurchaseRequestStatus.closed,
        ),
        isFalse,
      );
      for (final role in UserRole.values) {
        expect(
          PurchaseRequestStatePolicy.isAllowedFor(
            role: role,
            from: PurchaseRequestStatus.shipped,
            to: PurchaseRequestStatus.closed,
          ),
          isFalse,
        );
      }
    });
  });

  group('kebijakan penutupan', () {
    const doA = GoodReceiptShipmentStatus(
      doId: 'a',
      status: DeliveryOrderStatus.received,
    );
    const doB = GoodReceiptShipmentStatus(
      doId: 'b',
      status: DeliveryOrderStatus.shipped,
    );
    const doDraft = GoodReceiptShipmentStatus(
      doId: 'c',
      status: DeliveryOrderStatus.preparing,
    );

    test('menutup ketika hanya dokumen ini yang tersisa', () {
      expect(
        GoodReceiptClosurePolicy.closesRequest(
          shipments: const [doA, doB],
          currentDoId: 'b',
        ),
        isTrue,
      );
    });

    test('tidak menutup ketika ada dokumen shipped lain', () {
      expect(
        GoodReceiptClosurePolicy.closesRequest(
          shipments: const [
            doB,
            GoodReceiptShipmentStatus(
              doId: 'd',
              status: DeliveryOrderStatus.shipped,
            ),
          ],
          currentDoId: 'b',
        ),
        isFalse,
      );
    });

    test('Surat Jalan preparing tidak dihitung sebagai pengiriman', () {
      // A draft allocation has no shipment ledger behind it, so nobody is waiting to
      // receive it. Counting it would leave a request with a forgotten draft open for
      // ever.
      expect(
        GoodReceiptClosurePolicy.closesRequest(
          shipments: const [doB, doDraft],
          currentDoId: 'b',
        ),
        isTrue,
      );
      expect(
        GoodReceiptClosurePolicy.shipmentsOf(const [doA, doB, doDraft]),
        hasLength(2),
      );
    });

    test('daftar kosong tidak menutup apa pun', () {
      expect(
        GoodReceiptClosurePolicy.closesRequest(
          shipments: const [],
          currentDoId: 'b',
        ),
        isFalse,
      );
    });

    test('dokumen di luar daftar tidak menutup apa pun', () {
      expect(
        GoodReceiptClosurePolicy.closesRequest(
          shipments: const [doA],
          currentDoId: 'tidak-terkait',
        ),
        isFalse,
      );
    });

    test('hanya PR shipped yang dapat ditutup', () {
      for (final status in PurchaseRequestStatus.values) {
        expect(
          GoodReceiptClosurePolicy.isClosable(status),
          status == PurchaseRequestStatus.shipped,
        );
      }
    });

    test('sisa pengiriman dihitung tanpa dokumen ini', () {
      expect(
        GoodReceiptClosurePolicy.outstandingAfter(
          shipments: const [doA, doB, doDraft],
          currentDoId: 'b',
        ),
        0,
      );
      expect(
        GoodReceiptClosurePolicy.outstandingAfter(
          shipments: const [
            doB,
            GoodReceiptShipmentStatus(
              doId: 'd',
              status: DeliveryOrderStatus.shipped,
            ),
          ],
          currentDoId: 'b',
        ),
        1,
      );
    });
  });

  group('atomisitas transisi', () {
    test('kegagalan ledger menjaga Surat Jalan dan PR tetap semula', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: fullRequestAllocations(fixture),
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      await context
          .postGoodReceipt(
            posting: context.postingWith(
              inventory: FailingInventoryRepository(
                context.inventory,
                failOnItemId: fixture.tieItem.id,
              ),
            ),
          )
          .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId)
          .then<void>((_) {}, onError: (_, _) {});

      // All four writes share one transaction: ledger, receipt, shipment, request.
      expect(await context.goodReceiptMovementCount(grId), 0);
      expect(await context.goodReceiptStatusOf(grId), 'checking');
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'shipped',
      );
      expect(await context.balancesAt(fixture.branchStore.id), isEmpty);
    });
  });

  group('tidak ada penulis lain', () {
    test('hanya jalur posting GR yang menulis DO received', () {
      // Anywhere else, this would be a "Mark Received" button waiting to be wired up.
      final allowed = <String>{
        'lib/core/db/daos/good_receipt_dao.dart',
        'lib/features/good_receipt/data/repositories/drift_good_receipt_repository.dart',
      };
      for (final file in [
        ...dartFilesUnder('lib/features'),
        ...dartFilesUnder('lib/core/db/daos'),
        ...dartFilesUnder('lib/app'),
      ]) {
        if (allowed.contains(file.replaceAll(r'\', '/'))) continue;
        final code = readCodeOnly(file);
        expect(
          RegExp(
            r'(status:\s*(const\s+)?Value\(DeliveryOrderStatus\.received|'
            // Narrowed in Milestone 9. The bare `markReceived` this used to also match
            // was a guess at what a future method might be called, and Milestone 9
            // shipped one with exactly that name on an unrelated table —
            // `goods_returns.markReceived`, which moves a Retur to `received` and never
            // touches a Delivery Order. Matching it would have been a false positive,
            // and adding those files to `allowed` would have asserted the opposite of
            // the truth: they may *not* mark a shipment received. What this rule is
            // about is the Delivery Order, so that is what it now names.
            r'markDeliveryOrderReceived)',
          ).hasMatch(code),
          isFalse,
          reason: '$file dapat menulis status received.',
        );
      }
    });

    test('hanya jalur posting GR yang menulis PR closed', () {
      final allowed = <String>{
        'lib/core/db/daos/good_receipt_dao.dart',
        'lib/features/good_receipt/data/repositories/drift_good_receipt_repository.dart',
      };
      for (final file in [
        ...dartFilesUnder('lib/features'),
        ...dartFilesUnder('lib/core/db/daos'),
        ...dartFilesUnder('lib/app'),
      ]) {
        if (allowed.contains(file.replaceAll(r'\', '/'))) continue;
        final code = readCodeOnly(file);
        expect(
          RegExp(
            r'(status:\s*(const\s+)?Value\(PurchaseRequestStatus\.closed|'
            r'markPurchaseRequestClosed|markClosed)',
          ).hasMatch(code),
          isFalse,
          reason: '$file dapat menulis status closed.',
        );
      }
    });

    test('tidak ada use case publik untuk received atau closed', () {
      for (final file in dartFilesUnder('lib/features')) {
        final source = readLibrarySource(file);
        for (final forbidden in [
          'MarkDeliveryOrderReceivedUseCase',
          'ClosePurchaseRequestUseCase',
          'MarkPurchaseRequestClosedUseCase',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '$file mendeklarasikan $forbidden.',
          );
        }
      }
    });

    test('provider dan halaman GR tidak menyentuh penulis transisi', () {
      for (final file in [
        ...dartFilesUnder('lib/features/good_receipt/presentation'),
        ...dartFilesUnder('lib/features/delivery/presentation'),
      ]) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'markDeliveryOrderReceived',
          'markPurchaseRequestClosed',
          'postAtomically',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file memanggil $forbidden langsung.',
          );
        }
      }
    });
  });

  group('Surat Jalan preparing yang tertinggal', () {
    test('tidak dapat dikirim lagi setelah PR shipped, dan tidak menghalangi '
        'penutupan', () async {
      // Raised while the request was still `processing`, then left behind.
      final leftover = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: const [],
      );

      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: fullRequestAllocations(fixture),
      );
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'shipped',
      );

      // The leftover draft can no longer ship: its request is no longer `processing`.
      await expectLater(
        context
            .shipDeliveryOrder(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              deliveryOrderId: leftover,
            ),
        throwsA(isA<InvalidPurchaseRequestForDeliveryFailure>()),
      );

      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      final result = await post(grId);

      // And it does not hold the request open either — it is not a shipment.
      expect(result.purchaseRequestClosed, isTrue);
      expect(await context.deliveryOrderStatusOf(leftover), 'preparing');
    });
  });
}
