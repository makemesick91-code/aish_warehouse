import 'package:aish_warehouse/features/delivery/presentation/pages/branch_delivery_list_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/pages/delivery_order_detail_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/pages/delivery_order_form_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/pages/warehouse_delivery_order_list_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/providers/delivery_providers.dart';
import 'package:aish_warehouse/features/delivery/presentation/widgets/delivery_allocation_card.dart';
import 'package:aish_warehouse/features/delivery/presentation/widgets/delivery_expiry_badges.dart';
import 'package:aish_warehouse/features/delivery/presentation/widgets/delivery_order_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The Kepala Cabang's read-only delivery view (§29, §44).
///
/// Read-only in this milestone by design rather than by omission: the next step for a
/// shipped document is Good Receipt (G-G1), and that document does not exist yet. So
/// the screen must show the shipment in full — batches, expiry dates, quantities —
/// and offer **no** action at all, while saying what happens next.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  final overrides = <Override>[
    deliveryClockProvider.overrideWithValue(() => nowUtc),
  ];

  Future<void> pumpAsBranch(WidgetTester tester, String location) async {
    useTabletSurface(tester);
    await pumpAppAt(
      tester,
      context: context,
      actingAs: fixture.branchHead,
      location: location,
      overrides: overrides,
    );
  }

  /// A shipped document carrying one non-expiry line and one near-expiry batch.
  Future<String> shippedOrder() async {
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
          nearExpiryNote: 'Dipakai minggu ini',
        ),
      ],
    );
    await context.shipDeliveryOrder().call(
      actorUserId: fixture.warehouseUser.id,
      deliveryOrderId: doId,
    );
    return doId;
  }

  Future<String> preparingOrder() => prepareDeliveryOrder(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [simpleAllocation(fixture, qty: '1')],
  );

  group('daftar pengiriman masuk', () {
    testWidgets('empty state saat belum ada pengiriman', (tester) async {
      await pumpAsBranch(tester, '/deliveries');

      expect(find.text('Pengiriman Masuk'), findsOneWidget);
      expect(find.byKey(BranchDeliveryListPage.emptyKey), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('hanya shipped dan received yang tampil', (tester) async {
      final shipped = await shippedOrder();
      final preparing = await preparingOrder();

      await pumpAsBranch(tester, '/deliveries');

      expect(find.byKey(DeliveryOrderTile.tileKeyFor(shipped)), findsOneWidget);
      // Nothing has left the building for the draft, so the branch has not been
      // handed anything.
      expect(find.byKey(DeliveryOrderTile.tileKeyFor(preparing)), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('menampilkan nomor DO, PR, waktu kirim dan jumlah baris', (
      tester,
    ) async {
      final doId = await shippedOrder();
      final detail = await context.deliveries.getForWarehouse(doId);

      await pumpAsBranch(tester, '/deliveries');

      expect(find.text(detail!.summary.docNumber), findsOneWidget);
      expect(find.text('PR ${detail.summary.prDocNumber}'), findsOneWidget);
      expect(find.text('2 baris'), findsOneWidget);
      // Shipped time in operational GMT+8 (T-2).
      expect(
        find.textContaining('Dikirim 30 Jul 2026, 11:00 GMT+8'),
        findsOneWidget,
      );
      expect(find.text('Menunggu sinkron'), findsWidgets);
      expect(
        find.byKey(const ValueKey('deliveryStatusChip-shipped')),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('badge historis tampil setelah cabang dinonaktifkan', (
      tester,
    ) async {
      await shippedOrder();
      await context.deactivate('branches', fixture.branch.id);

      await pumpAsBranch(tester, '/deliveries');

      // The row stays — a shipment whose branch was retired is exactly the document
      // the branch still has to receive.
      expect(find.textContaining('Data historis'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('chip filter tidak menawarkan status preparing', (
      tester,
    ) async {
      await shippedOrder();
      await pumpAsBranch(tester, '/deliveries');

      // Offering a `preparing` chip would suggest there is something behind it.
      expect(
        find.byKey(const ValueKey('branchDeliveryStatusFilter-shipped')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('branchDeliveryStatusFilter-received')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('branchDeliveryStatusFilter-preparing')),
        findsNothing,
      );

      await disposeWidget(tester);
    });
  });

  group('detail read-only', () {
    testWidgets('menampilkan batch, expiry dan qty setiap baris', (
      tester,
    ) async {
      final doId = await shippedOrder();

      await pumpAsBranch(tester, '/deliveries/$doId');

      expect(find.text(fixture.simpleItem.name), findsOneWidget);
      expect(find.text(fixture.batchItem.name), findsOneWidget);
      expect(find.text('Dikirim 1 box'), findsOneWidget);
      expect(find.text('Dikirim 1.5 ampul'), findsOneWidget);
      // Batch number, expiry date as a civil date, and the remaining shelf life.
      expect(
        find.textContaining('${fixture.nearBatch.batchNo} · ED 11 Agu 2026'),
        findsOneWidget,
      );
      expect(find.textContaining('Sisa 12 hari'), findsOneWidget);
      // A non-expiry item says so rather than showing an empty batch cell.
      expect(find.text('Tanpa batch'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('peringatan near-expiry tampil', (tester) async {
      final doId = await shippedOrder();
      await pumpAsBranch(tester, '/deliveries/$doId');

      expect(find.byKey(BatchExpiryBadge.nearExpiryKey), findsOneWidget);
      expect(find.byKey(NearExpiryConfirmedBadge.badgeKey), findsOneWidget);
      expect(find.textContaining('Dipakai minggu ini'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('tidak ada kontrol edit, kirim atau terima', (tester) async {
      final doId = await shippedOrder();
      await pumpAsBranch(tester, '/deliveries/$doId');

      expect(find.byKey(DeliveryOrderDetailPage.editKey), findsNothing);
      expect(find.byKey(DeliveryOrderFormPage.shipKey), findsNothing);
      expect(find.byKey(DeliveryOrderFormPage.allocateKey), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(DeliveryAllocationCard), findsNothing);
      // And no receive affordance: `shipped → received` belongs to Good Receipt.
      expect(find.textContaining('Terima'), findsNothing);
      expect(find.textContaining('Good Receipt'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('pesan menunggu Good Receipt tampil untuk dokumen shipped', (
      tester,
    ) async {
      final doId = await shippedOrder();
      await pumpAsBranch(tester, '/deliveries/$doId');

      expect(
        find.text(DeliveryOrderStatusNote.awaitingGoodReceipt),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('progres Purchase Request tampil untuk cabang', (tester) async {
      final doId = await shippedOrder();
      await pumpAsBranch(tester, '/deliveries/$doId');

      expect(find.text('Progres Purchase Request'), findsOneWidget);
      // The cumulative reading, which is the honest one for a posted document.
      expect(find.textContaining('Terkirim 1 box'), findsOneWidget);
      expect(find.textContaining('Sisa 2 box'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('tombol Surat Jalan tersedia dan membuka dokumen', (
      tester,
    ) async {
      final doId = await shippedOrder();
      final detail = await context.deliveries.getForWarehouse(doId);

      await pumpAsBranch(tester, '/deliveries/$doId');
      await tester.tap(find.byKey(DeliveryOrderDetailPage.waybillKey));
      await tester.pumpAndSettle();

      expect(find.text('SURAT JALAN'), findsOneWidget);
      expect(find.text(detail!.summary.docNumber), findsOneWidget);

      await disposeWidget(tester);
    });
  });
}
