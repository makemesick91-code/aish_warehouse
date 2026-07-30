import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// **G-D1** — *"DO hanya bisa dibuat dari PR berstatus `submitted`/`processing`."*
///
/// Plus the two things creation must **not** do, which are as much part of the rule
/// as the eligibility check: it writes no ledger movement and changes no balance. A
/// `preparing` document is an intention; stock leaves when it is shipped (spec
/// §2.5). Every test here therefore ends by asserting that the warehouse balance is
/// exactly what it was.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<int> movementCount() async {
    final row = await context.database
        .customSelect(
          "SELECT COUNT(*) AS c FROM stock_movements WHERE ref_doc_type = 'DO';",
        )
        .getSingle();
    return row.read<int>('c');
  }

  group('kelayakan Purchase Request', () {
    test('PR processing dapat dibuatkan Surat Jalan', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      expect(order.status, DeliveryOrderStatus.preparing);
      expect(order.prId, fixture.purchaseRequestId);
      expect(order.preparedBy, fixture.warehouseUser.id);
      // G-Y4: a temporary number until the backend issues the real one.
      expect(order.docNumber, startsWith('TMP-DO-'));
      expect(order.shippedAt, isNull);
      expect(order.shippedBy, isNull);
      expect(order.syncStatus, SyncStatus.pending);
    });

    test('PR submitted menjadi processing dalam satu transaksi', () async {
      // Filed under the *other* branch: G-P4's partial unique index allows one
      // live `submitted`/`processing` request per branch, and the fixture's own
      // request already occupies that slot for `branch`.
      final prId = await writeProcessingPurchaseRequest(
        context,
        branchId: fixture.otherBranch.id,
        requestedBy: fixture.otherBranchHead.id,
        processedBy: fixture.warehouseUser.id,
        nowUtc: nowUtc,
        lines: {fixture.simpleItem.id: '1'},
        status: 'submitted',
        prId: 'pr-submitted',
      );
      expect(await context.purchaseRequestStatusOf(prId), 'submitted');

      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: prId,
      );

      // The transition and the document are one unit of work: neither is
      // observable without the other.
      expect(await context.purchaseRequestStatusOf(prId), 'processing');
      expect(
        await context.purchaseRequestColumn(prId, 'processed_by'),
        fixture.warehouseUser.id,
      );
      expect(
        await context.purchaseRequestColumn(prId, 'processing_at'),
        isNotNull,
      );
      expect(order.status, DeliveryOrderStatus.preparing);
    });

    test('PR yang sudah processing tidak ditulis ulang', () async {
      final before = await context.purchaseRequestColumn(
        fixture.purchaseRequestId,
        'processing_at',
      );
      await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      expect(
        await context.purchaseRequestColumn(
          fixture.purchaseRequestId,
          'processing_at',
        ),
        before,
      );
    });

    /// Every status G-D1 excludes, each with the audit columns its CHECK demands.
    for (final scenario in <({String status, String label})>[
      (status: 'draft', label: 'draft'),
      (status: 'shipped', label: 'shipped'),
      (status: 'closed', label: 'closed'),
      (status: 'rejected', label: 'rejected'),
      (status: 'cancelled', label: 'cancelled'),
    ]) {
      test('PR ${scenario.label} ditolak', () async {
        final prId = await _writeRequestInStatus(
          context,
          fixture,
          status: scenario.status,
          nowUtc: nowUtc,
        );

        await expectLater(
          () => context.createDeliveryOrder().call(
            actorUserId: fixture.warehouseUser.id,
            purchaseRequestId: prId,
          ),
          throwsA(isA<InvalidPurchaseRequestForDeliveryFailure>()),
        );
        // Nothing was created, and the request was not moved.
        expect(await context.purchaseRequestStatusOf(prId), scenario.status);
        expect(await context.deliveries.listByPurchaseRequest(prId), isEmpty);
      });
    }

    test('PR yang tidak ada ditolak', () async {
      await expectLater(
        () => context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: 'tidak-ada',
        ),
        throwsA(isA<PurchaseRequestNotFoundFailure>()),
      );
    });

    test('PR tanpa baris barang ditolak', () async {
      final prId = await writeProcessingPurchaseRequest(
        context,
        branchId: fixture.otherBranch.id,
        requestedBy: fixture.otherBranchHead.id,
        processedBy: fixture.warehouseUser.id,
        nowUtc: nowUtc,
        lines: const <String, String>{},
        prId: 'pr-empty',
      );

      await expectLater(
        () => context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: prId,
        ),
        throwsA(isA<PurchaseRequestLineNotFoundFailure>()),
      );
    });

    test('baris PR dengan barang hilang ditolak, bukan dilewati', () async {
      // The joined read behind `purchaseRequestPositions` inner-joins `items`, so a
      // line whose item row is gone would simply be absent — and a shipment
      // prepared against an order that is quietly one line short would look
      // complete when it is not (G-D5).
      await context.corruptByDeleting('items', fixture.scarceItem.id);

      await expectLater(
        () => context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: fixture.purchaseRequestId,
        ),
        throwsA(isA<HistoricalDeliveryReferenceMissingFailure>()),
      );
      expect(
        await context.deliveries.listByPurchaseRequest(
          fixture.purchaseRequestId,
        ),
        isEmpty,
      );
    });
  });

  group('aktor', () {
    test('hanya peran warehouse yang dapat membuat Surat Jalan', () async {
      for (final actor in [fixture.branchHead, fixture.nurse]) {
        await expectLater(
          () => context.createDeliveryOrder().call(
            actorUserId: actor.id,
            purchaseRequestId: fixture.purchaseRequestId,
          ),
          throwsA(isA<InvalidReviewerFailure>()),
          reason: '${actor.role.dbValue} tidak boleh membuat Surat Jalan.',
        );
      }
    });

    test('petugas warehouse nonaktif ditolak', () async {
      await context.deactivate('users', fixture.warehouseUser.id);

      await expectLater(
        () => context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: fixture.purchaseRequestId,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('aktor yang tidak ada ditolak', () async {
      await expectLater(
        () => context.createDeliveryOrder().call(
          actorUserId: 'tidak-ada',
          purchaseRequestId: fixture.purchaseRequestId,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });
  });

  group('lokasi warehouse', () {
    test('tanpa lokasi Warehouse Pusat pembuatan ditolak', () async {
      await context.corruptByDeleting('stock_locations', fixture.warehouse.id);

      await expectLater(
        () => context.createDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          purchaseRequestId: fixture.purchaseRequestId,
        ),
        throwsA(isA<WarehouseLocationNotFoundFailure>()),
      );
    });

    test(
      'lokasi Warehouse Pusat ganda ditolak, bukan dipilih salah satu',
      () async {
        // Which of two warehouses the goods left is a business fact. Picking the
        // first would post the ledger against a location nobody chose.
        await context.database.customStatement(
          'INSERT INTO stock_locations (id, created_at, updated_at, sync_status, '
          'type, name) VALUES (?, ?, ?, ?, ?, ?);',
          [
            'wh-2',
            nowUtc.toIso8601String(),
            nowUtc.toIso8601String(),
            'pending',
            'warehouse',
            'Warehouse Pusat Kedua',
          ],
        );

        await expectLater(
          () => context.createDeliveryOrder().call(
            actorUserId: fixture.warehouseUser.id,
            purchaseRequestId: fixture.purchaseRequestId,
          ),
          throwsA(isA<AmbiguousWarehouseLocationFailure>()),
        );
      },
    );
  });

  group('pembuatan tidak menyentuh stok', () {
    test('tidak ada movement dan saldo tidak berubah saat create', () async {
      final before = await context.balancesAt(fixture.warehouse.id);
      expect(await movementCount(), 0);

      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      expect(await movementCount(), 0);
      expect(await context.shipmentMovementCount(order.id), 0);
      expect(await context.balancesAt(fixture.warehouse.id), before);
    });

    test('alokasi FEFO juga tidak menyentuh stok', () async {
      final before = await context.balancesAt(fixture.warehouse.id);

      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.allocateFefo().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
      );

      expect(await context.deliveryLineCount(order.id), greaterThan(0));
      expect(await movementCount(), 0);
      expect(await context.balancesAt(fixture.warehouse.id), before);
    });

    test('satu PR boleh memiliki beberapa Surat Jalan preparing', () async {
      // Spec §2.3 allows it, and partial shipment depends on it. Nothing here
      // reserves stock, so several drafts can legitimately coexist — only one of
      // them will pass the revalidation at ship time.
      final first = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      final second = await context.createDeliveryOrder().call(
        actorUserId: fixture.secondWarehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      expect(first.id, isNot(second.id));
      expect(first.docNumber, isNot(second.docNumber));
      final all = await context.deliveries.listByPurchaseRequest(
        fixture.purchaseRequestId,
      );
      expect(all.map((summary) => summary.id).toSet(), {first.id, second.id});
    });

    test('catatan header dinormalisasi, spasi menjadi null', () async {
      final blank = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
        note: '   ',
      );
      expect(blank.note, isNull);

      final filled = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
        note: '  Kurir internal  ',
      );
      expect(filled.note, 'Kurir internal');
    });
  });
}

/// Writes one Purchase Request in [status], with the audit columns its CHECK
/// constraints demand for that status.
///
/// `rejected` and `cancelled` each require an actor, an instant and a non-blank
/// reason; `shipped` and `closed` require the processing pair. Writing them by hand
/// is what lets G-D1 be tested against statuses no use case in this milestone can
/// produce.
Future<String> _writeRequestInStatus(
  TestContext context,
  DeliveryFixture fixture, {
  required String status,
  required DateTime nowUtc,
}) async {
  final id = 'pr-$status';
  final submittedAt = status == 'draft'
      ? null
      : nowUtc.subtract(const Duration(hours: 4)).toIso8601String();
  final processingAt =
      const {'processing', 'shipped', 'closed', 'rejected'}.contains(status)
      ? nowUtc.subtract(const Duration(hours: 3)).toIso8601String()
      : null;

  await context.database.customStatement(
    'INSERT INTO purchase_requests (id, created_at, updated_at, sync_status, '
    'doc_number, branch_id, requested_by, status, submitted_at, processing_at, '
    'processed_by, rejected_at, rejected_by, reject_reason, cancelled_at, '
    'cancelled_by, cancel_reason) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
    [
      id,
      nowUtc.subtract(const Duration(hours: 5)).toIso8601String(),
      nowUtc.toIso8601String(),
      'pending',
      'TMP-PR-$id',
      fixture.branch.id,
      fixture.branchHead.id,
      status,
      submittedAt,
      processingAt,
      processingAt == null ? null : fixture.warehouseUser.id,
      status == 'rejected'
          ? nowUtc.subtract(const Duration(hours: 2)).toIso8601String()
          : null,
      status == 'rejected' ? fixture.warehouseUser.id : null,
      status == 'rejected' ? 'Stok tidak tersedia' : null,
      status == 'cancelled'
          ? nowUtc.subtract(const Duration(hours: 2)).toIso8601String()
          : null,
      status == 'cancelled' ? fixture.branchHead.id : null,
      status == 'cancelled' ? 'Tidak dibutuhkan lagi' : null,
    ],
  );
  await context.database.customStatement(
    'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
    'sync_status, pr_id, item_id, suggested_qty, requested_qty) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
    [
      '$id-line-1',
      nowUtc.toIso8601String(),
      nowUtc.toIso8601String(),
      'pending',
      id,
      fixture.simpleItem.id,
      0,
      1000,
    ],
  );
  return id;
}
