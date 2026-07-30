import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:aish_warehouse/features/delivery/domain/services/delivery_order_state_policy.dart';
import 'package:aish_warehouse/features/purchase_request/domain/services/purchase_request_state_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/source_inspection.dart';

/// **G-D5** — *"PR otomatis `shipped` bila semua baris terkirim penuh; `closed`
/// setelah semua DO diterima (GR posted)."*
///
/// Milestone 4 implements the first half and must not implement the second. Both
/// halves are asserted: the automatic `processing → shipped` transition, and the
/// **absence** of any path to `closed` or to a `received` Delivery Order. A milestone
/// that quietly reached either would leave the next one with a state machine it did
/// not write.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A request with exactly the positions [lines] names, so completeness can be
  /// reached without wrestling the four-position fixture into place.
  Future<({String prId, Map<String, String> lineIds})> smallRequest(
    Map<String, String> lines, {
    String prId = 'pr-small',
  }) async {
    final id = await writeProcessingPurchaseRequest(
      context,
      branchId: fixture.otherBranch.id,
      requestedBy: fixture.otherBranchHead.id,
      processedBy: fixture.warehouseUser.id,
      nowUtc: nowUtc,
      lines: lines,
      prId: prId,
    );
    return (prId: id, lineIds: await purchaseRequestLineIdsByItem(context, id));
  }

  Future<String> prepareFor({
    required String prId,
    required List<DeliveryAllocation> allocations,
  }) async {
    final order = await context
        .createDeliveryOrder(clock: () => nowUtc)
        .call(actorUserId: fixture.warehouseUser.id, purchaseRequestId: prId);
    await context.deliveries.replacePreparingLines(
      doId: order.id,
      allocations: allocations,
    );
    return order.id;
  }

  group('transisi otomatis PR', () {
    test('pengiriman parsial mempertahankan PR processing', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );

      final result = await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      expect(result.purchaseRequestCompleted, isFalse);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'processing',
      );
    });

    test(
      'pengiriman penuh satu Surat Jalan mengubah PR menjadi shipped',
      () async {
        final request = await smallRequest({fixture.simpleItem.id: '2'});
        final doId = await prepareFor(
          prId: request.prId,
          allocations: [
            DeliveryAllocation(
              prLineId: request.lineIds[fixture.simpleItem.id]!,
              itemId: fixture.simpleItem.id,
              qty: Quantity.parse('2'),
            ),
          ],
        );

        final result = await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        );

        expect(result.purchaseRequestCompleted, isTrue);
        expect(result.isPartialShipment, isFalse);
        expect(await context.purchaseRequestStatusOf(request.prId), 'shipped');
        // Atomic with the shipment: the document and the request moved together.
        expect(await context.deliveryOrderStatusOf(doId), 'shipped');
      },
    );

    test(
      'pengiriman penuh multi-DO mengubah PR pada Surat Jalan terakhir',
      () async {
        final request = await smallRequest({fixture.simpleItem.id: '2.5'});
        final prLineId = request.lineIds[fixture.simpleItem.id]!;

        final first = await prepareFor(
          prId: request.prId,
          allocations: [
            DeliveryAllocation(
              prLineId: prLineId,
              itemId: fixture.simpleItem.id,
              qty: Quantity.parse('1'),
            ),
          ],
        );
        await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: first,
        );
        expect(
          await context.purchaseRequestStatusOf(request.prId),
          'processing',
        );

        final second = await prepareFor(
          prId: request.prId,
          allocations: [
            DeliveryAllocation(
              prLineId: prLineId,
              itemId: fixture.simpleItem.id,
              qty: Quantity.parse('1.5'),
            ),
          ],
        );
        final result = await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: second,
        );

        expect(result.purchaseRequestCompleted, isTrue);
        expect(await context.purchaseRequestStatusOf(request.prId), 'shipped');
        // Both documents stay `shipped`; the transition belongs to the request, not
        // to the last document.
        expect(await context.deliveryOrderStatusOf(first), 'shipped');
        expect(await context.deliveryOrderStatusOf(second), 'shipped');
      },
    );

    test('satu baris belum penuh mempertahankan processing', () async {
      final request = await smallRequest({
        fixture.simpleItem.id: '1',
        fixture.tieItem.id: '3',
      });
      final doId = await prepareFor(
        prId: request.prId,
        allocations: [
          // The first position completes; the second is one short.
          DeliveryAllocation(
            prLineId: request.lineIds[fixture.simpleItem.id]!,
            itemId: fixture.simpleItem.id,
            qty: Quantity.parse('1'),
          ),
          DeliveryAllocation(
            prLineId: request.lineIds[fixture.tieItem.id]!,
            itemId: fixture.tieItem.id,
            batchId: fixture.tieBatchA.id,
            qty: Quantity.parse('2'),
          ),
        ],
      );

      final result = await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      expect(result.purchaseRequestCompleted, isFalse);
      expect(await context.purchaseRequestStatusOf(request.prId), 'processing');
      // And the completeness is per position, not per document.
      final complete = result.progress.where((entry) => entry.isFullyShipped);
      expect(complete, hasLength(1));
    });

    test('kegagalan ledger membuat PR tetap processing', () async {
      final request = await smallRequest({fixture.simpleItem.id: '2'});
      final doId = await prepareFor(
        prId: request.prId,
        allocations: [
          DeliveryAllocation(
            prLineId: request.lineIds[fixture.simpleItem.id]!,
            itemId: fixture.simpleItem.id,
            // The whole order, but more than the shelf holds — so the shipment
            // fails at the very step that would otherwise complete the request.
            qty: Quantity.parse('2'),
          ),
        ],
      );
      await context.posting.postDisposal(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        qty: Quantity.parse('2'),
        actorUserId: fixture.warehouseUser.id,
        note: 'Rusak',
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(await context.purchaseRequestStatusOf(request.prId), 'processing');
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
      expect(await context.shipmentMovementCount(doId), 0);
    });

    test('PR yang tidak lagi processing menolak pengiriman', () async {
      // A `preparing` document may have been prepared days ago against an order
      // that has since been rejected. Stock must not leave the warehouse for it.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      await context.database.customStatement(
        "UPDATE purchase_requests SET status = 'rejected', rejected_at = ?, "
        'rejected_by = ?, reject_reason = ? WHERE id = ?;',
        [
          nowUtc.toIso8601String(),
          fixture.warehouseUser.id,
          'Dibatalkan pusat',
          fixture.purchaseRequestId,
        ],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InvalidPurchaseRequestForDeliveryFailure>()),
      );
      expect(await context.shipmentMovementCount(doId), 0);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
    });

    test('kelebihan kirim tidak pernah membuat PR shipped', () async {
      final request = await smallRequest({fixture.simpleItem.id: '1'});
      final doId = await prepareFor(
        prId: request.prId,
        allocations: [
          DeliveryAllocation(
            prLineId: request.lineIds[fixture.simpleItem.id]!,
            itemId: fixture.simpleItem.id,
            qty: Quantity.parse('2'),
          ),
        ],
      );

      await expectLater(
        () => context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<DeliveryQuantityExceedsRequestedFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(request.prId), 'processing');
    });
  });

  group('batas milestone', () {
    test('PR tidak pernah menjadi closed', () async {
      final request = await smallRequest({fixture.simpleItem.id: '2'});
      final doId = await prepareFor(
        prId: request.prId,
        allocations: [
          DeliveryAllocation(
            prLineId: request.lineIds[fixture.simpleItem.id]!,
            itemId: fixture.simpleItem.id,
            qty: Quantity.parse('2'),
          ),
        ],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      // `shipped`, and nothing in this milestone can take it further: `closed`
      // happens when every shipment has been received through Good Receipt.
      expect(await context.purchaseRequestStatusOf(request.prId), 'shipped');
    });

    test('Surat Jalan tidak pernah menjadi received', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
    });

    test('tidak ada penulis received pada DAO, repository atau use case', () {
      // The transition exists in the state machine and belongs to Good Receipt.
      // Offering a writer for it now would be a button waiting to be wired up
      // before the document that justifies it exists.
      for (final file in [
        'lib/core/db/daos/delivery_order_dao.dart',
        'lib/features/delivery/domain/repositories/delivery_order_repository.dart',
        'lib/features/delivery/data/repositories/drift_delivery_order_repository.dart',
        ...dartFilesUnder('lib/features/delivery/domain/use_cases'),
        ...dartFilesUnder('lib/features/delivery/presentation'),
      ]) {
        final code = readCodeOnly(file);
        expect(
          RegExp(r'markReceived|MarkDeliveryOrderReceived').hasMatch(code),
          isFalse,
          reason: '$file menawarkan penulis status received.',
        );
        expect(
          RegExp(
            r'(status:\s*(const\s+)?Value\(DeliveryOrderStatus\.received|'
            r'to:\s*DeliveryOrderStatus\.received)',
          ).hasMatch(code),
          isFalse,
          reason: '$file menulis atau meminta transisi menuju received.',
        );
      }
    });

    test('tidak ada penulis closed pada jalur Delivery Order', () {
      // A guard may *mention* `closed` — it renders a sentence for a request that
      // is already in that state, which is exactly the message an officer needs.
      // What none of them may do is ask for a transition into it, or write the
      // column: `closed` happens when every shipment has been received, and the
      // document that decides that is Good Receipt's.
      for (final file in [
        'lib/core/db/daos/delivery_order_dao.dart',
        ...dartFilesUnder('lib/features/delivery'),
      ]) {
        final code = readCodeOnly(file);
        expect(
          RegExp(
            r'(to:\s*PurchaseRequestStatus\.closed|'
            r'status:\s*(const\s+)?Value\(PurchaseRequestStatus\.closed|'
            r'markPurchaseRequestClosed)',
          ).hasMatch(code),
          isFalse,
          reason: '$file menulis atau meminta transisi menuju closed.',
        );
      }

      // And the one place that *does* write a Purchase Request status writes
      // exactly one, guarded by the status it moves from.
      final dao = readCodeOnly('lib/core/db/daos/delivery_order_dao.dart');
      expect(dao, contains('markPurchaseRequestShipped'));
      expect(
        dao,
        contains('t.status.equalsValue(PurchaseRequestStatus.processing)'),
      );
      expect(dao, isNot(contains('Future<int> setPurchaseRequestStatus')));
    });
  });

  group('kebijakan status', () {
    test('mesin status DO hanya maju', () {
      expect(
        DeliveryOrderStatePolicy.isAllowed(
          DeliveryOrderStatus.preparing,
          DeliveryOrderStatus.shipped,
        ),
        isTrue,
      );
      expect(
        DeliveryOrderStatePolicy.isAllowed(
          DeliveryOrderStatus.shipped,
          DeliveryOrderStatus.received,
        ),
        isTrue,
      );
      for (final transition in <(DeliveryOrderStatus, DeliveryOrderStatus)>[
        (DeliveryOrderStatus.shipped, DeliveryOrderStatus.preparing),
        (DeliveryOrderStatus.received, DeliveryOrderStatus.shipped),
        (DeliveryOrderStatus.received, DeliveryOrderStatus.preparing),
        (DeliveryOrderStatus.preparing, DeliveryOrderStatus.received),
        (DeliveryOrderStatus.preparing, DeliveryOrderStatus.preparing),
        (DeliveryOrderStatus.shipped, DeliveryOrderStatus.shipped),
      ]) {
        expect(
          DeliveryOrderStatePolicy.isAllowed(transition.$1, transition.$2),
          isFalse,
          reason:
              '${transition.$1.dbValue} → ${transition.$2.dbValue} '
              'seharusnya ditolak.',
        );
      }
    });

    test('received bukan transisi pengguna untuk peran mana pun', () {
      expect(
        DeliveryOrderStatePolicy.isUserTransition(
          DeliveryOrderStatus.shipped,
          DeliveryOrderStatus.received,
        ),
        isFalse,
      );
      expect(
        DeliveryOrderStatePolicy.isGoodReceiptTransition(
          DeliveryOrderStatus.shipped,
          DeliveryOrderStatus.received,
        ),
        isTrue,
      );
      for (final role in UserRole.values) {
        expect(
          DeliveryOrderStatePolicy.isAllowedFor(
            role: role,
            from: DeliveryOrderStatus.shipped,
            to: DeliveryOrderStatus.received,
          ),
          isFalse,
          reason: '${role.dbValue} tidak boleh menandai DO received.',
        );
      }
      expect(
        DeliveryOrderStatePolicy.userNextStatesOf(DeliveryOrderStatus.shipped),
        isEmpty,
      );
    });

    test('hanya warehouse yang boleh preparing → shipped', () {
      for (final role in UserRole.values) {
        expect(
          DeliveryOrderStatePolicy.isAllowedFor(
            role: role,
            from: DeliveryOrderStatus.preparing,
            to: DeliveryOrderStatus.shipped,
          ),
          role == UserRole.warehouse,
          reason: '${role.dbValue} salah dinilai untuk transisi pengiriman.',
        );
      }
    });

    test('kelayakan PR mengikuti G-D1 dan lebih sempit saat kirim', () {
      for (final status in PurchaseRequestStatus.values) {
        expect(
          DeliveryOrderStatePolicy.canCreateFrom(status),
          status == PurchaseRequestStatus.submitted ||
              status == PurchaseRequestStatus.processing,
        );
        // Creating from `submitted` works only because creation moves it first, so
        // by the time anything ships the request must already be `processing`.
        expect(
          DeliveryOrderStatePolicy.canShipAgainst(status),
          status == PurchaseRequestStatus.processing,
        );
      }
    });

    test('PR processing → shipped tetap transisi sistem', () {
      // The Delivery Order drives it, which is why no second Purchase Request state
      // machine was written. If this ever stops being a `system` transition, the
      // shipment fails loudly instead of writing a status nothing sanctions.
      expect(
        PurchaseRequestStatePolicy.isSystemTransition(
          PurchaseRequestStatus.processing,
          PurchaseRequestStatus.shipped,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isUserTransition(
          PurchaseRequestStatus.processing,
          PurchaseRequestStatus.shipped,
        ),
        isFalse,
      );
    });
  });
}
