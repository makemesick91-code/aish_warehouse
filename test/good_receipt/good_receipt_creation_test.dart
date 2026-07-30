import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-G1 — *"GR hanya bisa dibuat oleh Kepala Cabang dari cabang tujuan, dari DO
/// berstatus `shipped`; 1 DO = 1 GR"* (§39).
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A shipment with one non-batch and one safely dated batch position.
  Future<String> shippedOrder() => shipDeliveryOrderFor(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [
      simpleAllocation(fixture, qty: '2.5'),
      safeBatchAllocation(fixture, qty: '4'),
    ],
  );

  group('kelayakan Surat Jalan', () {
    test(
      'Kepala Cabang cabang tujuan dapat membuat GR dari DO shipped',
      () async {
        final doId = await shippedOrder();

        final receipt = await context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        );

        expect(receipt.status, GoodReceiptStatus.checking);
        expect(receipt.doId, doId);
        expect(receipt.receivedBy, fixture.branchHead.id);
        expect(receipt.postedAt, isNull);
        // Local numbering only: a server-shaped `GR-{cabang}-{date}-{seq}` would
        // collide across devices (G-Y4).
        expect(receipt.docNumber, startsWith('TMP-GR-'));
        expect(receipt.syncStatus, SyncStatus.pending);
      },
    );

    test('DO preparing ditolak', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2')],
      );

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InvalidDeliveryOrderForReceiptFailure>()),
      );
      expect(await context.goodReceiptCountFor(doId), 0);
    });

    test('DO received ditolak', () async {
      final doId = await shippedOrder();
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
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
      expect(await context.deliveryOrderStatusOf(doId), 'received');

      // The shipment is final now, and its receipt already exists — both reasons this
      // must be refused, and either alone is enough.
      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(await context.goodReceiptCountFor(doId), 1);
    });

    test('DO yang tidak ada ditolak', () async {
      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: 'tidak-ada',
        ),
        throwsA(isA<DeliveryOrderNotFoundFailure>()),
      );
    });

    test('Surat Jalan tanpa barang ditolak', () async {
      // A shipment with no allocations cannot be shipped at all, so the only way to
      // reach this guard is a document whose lines went away underneath it. Asserted
      // through the empty `preparing` document, which fails on its status first —
      // the point is that neither path produces a receipt.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: const [],
      );

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(await context.goodReceiptCountFor(doId), 0);
    });
  });

  group('RBAC', () {
    test('Kepala Cabang cabang lain ditolak', () async {
      final doId = await shippedOrder();

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.otherBranchHead.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<GoodReceiptBranchMismatchFailure>()),
      );
      expect(await context.goodReceiptCountFor(doId), 0);
    });

    test('Petugas Warehouse ditolak', () async {
      final doId = await shippedOrder();

      // G-R4: the officer who prepared and shipped the goods must not also declare
      // them received.
      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(await context.goodReceiptCountFor(doId), 0);
    });

    test('Perawat ditolak', () async {
      final doId = await shippedOrder();

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.nurse.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('Super Admin ditolak', () async {
      final doId = await shippedOrder();
      final superAdmin = await context.master.ensureUser(
        email: 'admin@test.local',
        fullName: 'Super Admin Uji',
        role: UserRole.superAdmin,
      );

      // Widening a workflow permission because an account is powerful is exactly the
      // quiet grant G-R4 exists to prevent.
      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: superAdmin.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(await context.goodReceiptCountFor(doId), 0);
    });

    test('Kepala Cabang nonaktif ditolak', () async {
      final doId = await shippedOrder();
      await context.deactivate('users', fixture.branchHead.id);

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('Kepala Cabang tanpa cabang ditolak', () async {
      final doId = await shippedOrder();
      // A branch-scoped role without a branch is a data fault, not a permission that
      // happens to be wide.
      await context.database.customStatement(
        'UPDATE users SET branch_id = NULL WHERE id = ?;',
        [fixture.branchHead.id],
      );

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<UnauthorizedBranchFailure>()),
      );
    });

    test('pengguna yang tidak ada ditolak', () async {
      final doId = await shippedOrder();

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: 'tidak-ada',
          deliveryOrderId: doId,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });
  });

  group('satu DO satu GR', () {
    test('GR kedua untuk DO yang sama ditolak', () async {
      final doId = await shippedOrder();
      await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<GoodReceiptAlreadyExistsFailure>()),
      );
      expect(await context.goodReceiptCountFor(doId), 1);
    });

    test('dua pembuatan bersamaan menghasilkan tepat satu GR', () async {
      final doId = await shippedOrder();

      // Both attempts read "no receipt yet" and both insert. The unique index on
      // `good_receipts.do_id` is the final guard; the check-then-act pair above it
      // never is.
      final outcomes = await Future.wait<String?>(
        [context.createGoodReceipt(), context.createGoodReceipt()].map(
          (useCase) => useCase
              .call(actorUserId: fixture.branchHead.id, deliveryOrderId: doId)
              .then<String?>((receipt) => receipt.id)
              .onError<AppFailure>((_, _) => null),
        ),
      );

      expect(outcomes.whereType<String>(), hasLength(1));
      expect(outcomes.where((id) => id == null), hasLength(1));
      expect(await context.goodReceiptCountFor(doId), 1);
    });

    test('percobaan yang kalah tidak meninggalkan baris orphan', () async {
      final doId = await shippedOrder();
      await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );
      final linesBefore = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM good_receipt_lines;')
          .getSingle();

      await context
          .createGoodReceipt()
          .call(actorUserId: fixture.branchHead.id, deliveryOrderId: doId)
          .then<void>((_) {}, onError: (_, _) {});

      // The whole create is one transaction, so a refused header rolls its snapshot
      // back with it.
      final linesAfter = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM good_receipt_lines;')
          .getSingle();
      expect(linesAfter.read<int>('c'), linesBefore.read<int>('c'));
    });
  });

  group('snapshot', () {
    test('seluruh baris Surat Jalan tersnapshot satu banding satu', () async {
      final doId = await shippedOrder();
      final receipt = await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );

      final expected = await context.deliveries.lineReferences(doId);
      final snapshot = await context.receipts.lineReferences(receipt.id);

      expect(snapshot, hasLength(expected.length));
      expect(
        snapshot.map((line) => line.doLineId).toSet(),
        expected.map((line) => line.id).toSet(),
      );
    });

    test('item, batch dan shipped_qty disalin dari Surat Jalan', () async {
      final doId = await shippedOrder();
      final receipt = await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );

      final allocations = {
        for (final line in await context.deliveries.lineReferences(doId))
          line.id: line,
      };
      final rows = await context.goodReceiptLineRows(receipt.id);

      for (final row in rows.values) {
        final allocation = allocations[row['do_line_id']]!;
        expect(row['item_id'], allocation.itemId);
        expect(row['batch_id'], allocation.batchId);
        expect(row['shipped_qty'], allocation.shippedQty.milliUnits);
      }
    });

    test(
      'setiap baris mulai pending dengan received_qty = shipped_qty',
      () async {
        final doId = await shippedOrder();
        final receipt = await context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        );

        final rows = await context.goodReceiptLineRows(receipt.id);
        expect(rows, isNotEmpty);
        for (final row in rows.values) {
          expect(row['line_status'], 'pending');
          expect(row['reject_reason'], isNull);
          // The branch head is confirming a delivery, not entering it from scratch.
          expect(row['received_qty'], row['shipped_qty']);
        }
      },
    );

    test('kuantitas desimal tersnapshot tepat', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.375')],
      );
      final receipt = await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );

      final lines = await context.receipts.lineReferences(receipt.id);
      expect(lines.single.shippedQty, Quantity.parse('2.375'));
      expect(lines.single.receivedQty, Quantity.parse('2.375'));
    });

    test('snapshot tidak berubah ketika master berubah setelahnya', () async {
      final doId = await shippedOrder();
      final receipt = await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );
      final before = await context.goodReceiptLineRows(receipt.id);

      await context.deactivate('items', fixture.simpleItem.id);
      await context.archive('item_batches', fixture.safeBatch.id);

      // Deactivating and archiving are not deletion: the snapshot is exactly what
      // shipped, and it stays that way.
      expect(await context.goodReceiptLineRows(receipt.id), before);
    });

    test('header dan baris dibuat atomik', () async {
      final doId = await shippedOrder();
      final receipt = await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );

      // Not "the header exists" and separately "some lines exist": a receipt with a
      // header and no snapshot could be posted as an empty document.
      expect(await context.goodReceiptCountFor(doId), 1);
      expect(await context.goodReceiptLineCount(receipt.id), 2);
    });
  });

  group('tanpa efek stok', () {
    test('pembuatan GR tidak menulis movement', () async {
      final doId = await shippedOrder();
      final receipt = await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );

      // Spec §2.5 credits the branch when the receipt is *posted*.
      expect(await context.goodReceiptMovementCount(receipt.id), 0);
    });

    test('pembuatan GR tidak mengubah saldo mana pun', () async {
      final doId = await shippedOrder();
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      final branchBefore = await context.balancesAt(fixture.branchStore.id);

      await context.createGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        deliveryOrderId: doId,
      );

      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
      expect(await context.balancesAt(fixture.branchStore.id), branchBefore);
    });

    test(
      'Surat Jalan tetap shipped dan Purchase Request tetap seperti semula',
      () async {
        final doId = await shippedOrder();
        final prStatusBefore = await context.purchaseRequestStatusOf(
          fixture.purchaseRequestId,
        );

        await context.createGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          deliveryOrderId: doId,
        );

        expect(await context.deliveryOrderStatusOf(doId), 'shipped');
        expect(
          await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
          prStatusBefore,
        );
      },
    );
  });
}
