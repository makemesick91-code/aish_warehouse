import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:aish_warehouse/features/delivery/presentation/pages/delivery_order_create_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/pages/delivery_order_detail_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/pages/delivery_order_form_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/pages/warehouse_delivery_order_list_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/providers/delivery_providers.dart';
import 'package:aish_warehouse/features/delivery/presentation/widgets/delivery_allocation_card.dart';
import 'package:aish_warehouse/features/delivery/presentation/widgets/delivery_expiry_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The warehouse's Delivery Order screens (§27, §44).
///
/// Everything is pumped against the in-memory database with a pinned clock, so the
/// expiry badges and the near-expiry rules are deterministic (T-7). The interactions
/// worth testing are the ones a rule depends on: the FEFO button, the decimal input,
/// the near-expiry confirmation, the override reason, the pending-input flush before
/// *Kirim*, the confirmation dialog and the loading guard.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  // Overriding the one clock provider moves the candidate list, the near-expiry
  // badges, the ledger's expiry rejection and the print time together (T-7).
  final overrides = <Override>[
    deliveryClockProvider.overrideWithValue(() => nowUtc),
  ];

  Future<void> pumpAt(WidgetTester tester, String location) async {
    useTabletSurface(tester);
    await pumpAppAt(
      tester,
      context: context,
      actingAs: fixture.warehouseUser,
      location: location,
      overrides: overrides,
    );
  }

  /// A `preparing` document whose only allocation is the non-expiry item.
  Future<String> preparedSimple({String qty = '1'}) => prepareDeliveryOrder(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [simpleAllocation(fixture, qty: qty)],
  );

  group('daftar pengiriman', () {
    testWidgets('empty state saat belum ada Surat Jalan', (tester) async {
      await pumpAt(tester, '/warehouse/delivery-orders');

      expect(find.text('Pengiriman'), findsOneWidget);
      expect(
        find.byKey(WarehouseDeliveryOrderListPage.emptyKey),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('menampilkan nomor DO, PR, cabang dan status', (tester) async {
      final doId = await preparedSimple();
      final detail = await context.deliveries.getForWarehouse(doId);

      await pumpAt(tester, '/warehouse/delivery-orders');

      expect(find.text(detail!.summary.docNumber), findsOneWidget);
      expect(find.text('PR ${detail.summary.prDocNumber}'), findsOneWidget);
      expect(
        find.text('${fixture.branch.code} · ${fixture.branch.name}'),
        findsOneWidget,
      );
      expect(
        find.text('Disiapkan ${fixture.warehouseUser.fullName}'),
        findsOneWidget,
      );
      expect(find.text('1 baris'), findsOneWidget);
      // GMT+8 display (T-2): 03:00 UTC is 11:00 operational.
      expect(find.textContaining('30 Jul 2026, 11:00 GMT+8'), findsWidgets);
      expect(find.byKey(DeliveryOrderTile.tileKeyFor(doId)), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('filter status menyaring daftar', (tester) async {
      final preparing = await preparedSimple();
      await pumpAt(tester, '/warehouse/delivery-orders');
      expect(
        find.byKey(DeliveryOrderTile.tileKeyFor(preparing)),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('deliveryStatusFilter-shipped')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(DeliveryOrderTile.tileKeyFor(preparing)), findsNothing);
      expect(
        find.byKey(WarehouseDeliveryOrderListPage.emptyKey),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('pencarian barang menemukan Surat Jalan', (tester) async {
      final doId = await preparedSimple();
      await pumpAt(tester, '/warehouse/delivery-orders');

      await tester.enterText(
        find.byKey(WarehouseDeliveryOrderListPage.searchKey),
        'Masker',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byKey(DeliveryOrderTile.tileKeyFor(doId)), findsOneWidget);

      await tester.enterText(
        find.byKey(WarehouseDeliveryOrderListPage.searchKey),
        'Barang Yang Tidak Ada',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byKey(DeliveryOrderTile.tileKeyFor(doId)), findsNothing);

      await disposeWidget(tester);
    });
  });

  group('buat Surat Jalan dari PR', () {
    testWidgets('menampilkan sisa dan menawarkan tombol buat', (tester) async {
      await pumpAt(
        tester,
        '/warehouse/delivery-orders/new/${fixture.purchaseRequestId}',
      );

      expect(find.text('Buat Delivery Order'), findsWidgets);
      expect(find.text('Sisa yang belum dikirim'), findsOneWidget);
      // The outstanding figures come straight from the progress calculation.
      expect(find.textContaining('Diminta 3 box'), findsOneWidget);
      expect(find.textContaining('Sisa 3 box'), findsOneWidget);
      expect(
        find.byKey(DeliveryOrderCreatePage.createButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(DeliveryOrderCreatePage.completeNoticeKey),
        findsNothing,
      );

      await disposeWidget(tester);
    });

    testWidgets('PR yang sudah terkirim penuh tidak menawarkan tombol', (
      tester,
    ) async {
      // A request with one position, shipped in full: nothing left to send.
      final prId = await writeProcessingPurchaseRequest(
        context,
        branchId: fixture.otherBranch.id,
        requestedBy: fixture.otherBranchHead.id,
        processedBy: fixture.warehouseUser.id,
        nowUtc: nowUtc,
        lines: {fixture.simpleItem.id: '1'},
        prId: 'pr-complete',
      );
      final lineIds = await purchaseRequestLineIdsByItem(context, prId);
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: prId,
      );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [
          DeliveryAllocationFor(
            prLineId: lineIds[fixture.simpleItem.id]!,
            itemId: fixture.simpleItem.id,
            qty: '1',
          ).value,
        ],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
      );

      await pumpAt(tester, '/warehouse/delivery-orders/new/$prId');

      expect(
        find.byKey(DeliveryOrderCreatePage.completeNoticeKey),
        findsOneWidget,
      );
      expect(find.byKey(DeliveryOrderCreatePage.createButtonKey), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('menekan buat menghasilkan dokumen preparing', (tester) async {
      await pumpAt(
        tester,
        '/warehouse/delivery-orders/new/${fixture.purchaseRequestId}',
      );

      await tester.tap(find.byKey(DeliveryOrderCreatePage.createButtonKey));
      await tester.pumpAndSettle();

      final orders = await context.deliveries.listByPurchaseRequest(
        fixture.purchaseRequestId,
      );
      expect(orders, hasLength(1));
      expect(
        await context.deliveryOrderStatusOf(orders.single.id),
        'preparing',
      );
      // And it navigated to the allocation editor.
      expect(find.byKey(DeliveryOrderFormPage.allocateKey), findsOneWidget);

      await disposeWidget(tester);
    });
  });

  group('form alokasi', () {
    testWidgets('tanpa item picker bebas, hanya baris dari PR', (tester) async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await pumpAt(tester, '/warehouse/delivery-orders/${order.id}/edit');

      // One card per requested position, and nothing that could add another item —
      // G-D4 enforced by the absence of a control (§27.2).
      for (final prLineId in [
        fixture.simpleLineId,
        fixture.batchLineId,
        fixture.scarceLineId,
        fixture.tieLineId,
      ]) {
        expect(
          find.byKey(DeliveryAllocationCard.cardKeyFor(prLineId)),
          findsOneWidget,
        );
      }
      expect(find.text('Tambah barang'), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(
        find.byKey(DeliveryAllocationCard.emptyAllocationKey),
        findsWidgets,
      );

      await disposeWidget(tester);
    });

    testWidgets('Alokasikan FEFO mengisi alokasi dan menampilkan batch', (
      tester,
    ) async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await pumpAt(tester, '/warehouse/delivery-orders/${order.id}/edit');

      await tester.tap(find.byKey(DeliveryOrderFormPage.allocateKey));
      await tester.pumpAndSettle();

      final lines = await context.deliveries.lineReferences(order.id);
      expect(lines, isNotEmpty);
      // The nearest-expiry batch is allocated, and its badge says how long it has.
      expect(lines.map((line) => line.batchId), contains(fixture.nearBatch.id));
      expect(find.byKey(BatchExpiryBadge.nearExpiryKey), findsWidgets);
      // The expired batch is never offered, and the card explains why.
      expect(
        find.textContaining('batch kedaluwarsa tidak dapat dikirim'),
        findsWidgets,
      );

      await disposeWidget(tester);
    });

    testWidgets('input desimal 0.5 valid dan tersimpan', (tester) async {
      final doId = await preparedSimple();
      final lineIds = await deliveryLineIdsByAllocation(context, doId);
      final lineId = lineIds['${fixture.simpleLineId}|']!;

      await pumpAt(tester, '/warehouse/delivery-orders/$doId/edit');

      await tester.enterText(
        find.byKey(DeliveryAllocationCard.qtyFieldKeyFor(lineId)),
        '0.5',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DeliveryAllocationCard.saveKeyFor(lineId)));
      await tester.pumpAndSettle();

      final lines = await context.deliveries.lineReferences(doId);
      expect(lines.single.shippedQty, Quantity.parse('0.5'));

      await disposeWidget(tester);
    });

    testWidgets('sisa permintaan ditampilkan per baris', (tester) async {
      final doId = await preparedSimple(qty: '1');
      await pumpAt(tester, '/warehouse/delivery-orders/$doId/edit');

      // 3 requested, none shipped yet, 1 on this document.
      expect(find.textContaining('Diminta 3 box'), findsWidgets);
      expect(find.textContaining('Sudah dikirim 0 box'), findsWidgets);
      expect(find.textContaining('DO ini 1 box'), findsWidgets);
      // And the warehouse balance, which is the other ceiling (G-D3).
      expect(find.textContaining('Saldo Warehouse 2.5 box'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('batch kedaluwarsa tidak tersedia pada pemilih', (
      tester,
    ) async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
          ),
        ],
      );
      await pumpAt(tester, '/warehouse/delivery-orders/${order.id}/edit');

      final lines = await context.deliveries.lineReferences(order.id);
      await tester.tap(
        find.byKey(DeliveryAllocationCard.batchPickerKeyFor(lines.single.id)),
      );
      await tester.pumpAndSettle();

      // Three usable batches are offered; the expired one is not among them.
      expect(find.textContaining(fixture.nearBatch.batchNo), findsWidgets);
      expect(find.textContaining(fixture.soonBatch.batchNo), findsWidgets);
      expect(find.textContaining(fixture.safeBatch.batchNo), findsWidgets);
      expect(find.textContaining(fixture.expiredBatch.batchNo), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('konfirmasi near-expiry muncul dan wajib', (tester) async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [
          batchAllocation(fixture, batchId: fixture.nearBatch.id, qty: '1'),
        ],
      );
      final lines = await context.deliveries.lineReferences(order.id);

      await pumpAt(tester, '/warehouse/delivery-orders/${order.id}/edit');

      // 12 days left against a 30-day threshold: the checkbox is there, unticked.
      final checkbox = find.byKey(
        DeliveryAllocationCard.nearExpiryCheckKeyFor(lines.single.id),
      );
      expect(checkbox, findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(checkbox).value,
        isFalse,
        reason: 'Konfirmasi tidak boleh tercentang otomatis (G-E4).',
      );

      // Saving without it is refused, with the rule's own sentence.
      await tester.tap(
        find.byKey(DeliveryAllocationCard.saveKeyFor(lines.single.id)),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('memerlukan konfirmasi eksplisit'),
        findsOneWidget,
      );
      expect(
        (await context.deliveries.lineReferences(
          order.id,
        )).single.nearExpiryConfirmed,
        isFalse,
      );

      // Ticking it and saving goes through.
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(DeliveryAllocationCard.saveKeyFor(lines.single.id)),
      );
      await tester.pumpAndSettle();
      expect(
        (await context.deliveries.lineReferences(
          order.id,
        )).single.nearExpiryConfirmed,
        isTrue,
      );

      await disposeWidget(tester);
    });

    testWidgets('override FEFO memunculkan peringatan dan alasan wajib', (
      tester,
    ) async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [
          // The 300-day batch while two nearer ones still hold stock.
          batchAllocation(fixture, batchId: fixture.safeBatch.id, qty: '1'),
        ],
      );
      final lines = await context.deliveries.lineReferences(order.id);

      await pumpAt(tester, '/warehouse/delivery-orders/${order.id}/edit');

      // The warning names the batch that was passed over, which is what makes it
      // actionable.
      expect(
        find.textContaining('${fixture.nearBatch.batchNo} lebih dekat'),
        findsOneWidget,
      );
      final reasonField = find.byKey(
        DeliveryAllocationCard.fefoReasonKeyFor(lines.single.id),
      );
      expect(reasonField, findsOneWidget);

      // Saving without a reason is refused.
      await tester.tap(
        find.byKey(DeliveryAllocationCard.saveKeyFor(lines.single.id)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Isi alasan penggantian batch'), findsWidgets);

      await tester.enterText(reasonField, 'Cabang minta masa simpan panjang');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(DeliveryAllocationCard.saveKeyFor(lines.single.id)),
      );
      await tester.pumpAndSettle();
      expect(
        (await context.deliveries.lineReferences(
          order.id,
        )).single.fefoOverrideReason,
        'Cabang minta masa simpan panjang',
      );

      await disposeWidget(tester);
    });

    testWidgets('menghapus baris mengosongkan alokasi', (tester) async {
      final doId = await preparedSimple();
      final lineIds = await deliveryLineIdsByAllocation(context, doId);
      final lineId = lineIds['${fixture.simpleLineId}|']!;

      await pumpAt(tester, '/warehouse/delivery-orders/$doId/edit');
      await tester.tap(find.byKey(DeliveryAllocationCard.removeKeyFor(lineId)));
      await tester.pumpAndSettle();

      expect(await context.deliveryLineCount(doId), 0);

      await disposeWidget(tester);
    });
  });

  group('konfirmasi dan pengiriman', () {
    testWidgets('input tertunda di-flush sebelum kirim', (tester) async {
      // The behaviour worth spelling out: an officer who types `0.5` and goes
      // straight for *Kirim*, without pressing Simpan, must ship `0.5` — not the
      // quantity that happened to be stored (§27.4 step 1).
      final doId = await preparedSimple(qty: '2');
      final lineIds = await deliveryLineIdsByAllocation(context, doId);
      final lineId = lineIds['${fixture.simpleLineId}|']!;

      await pumpAt(tester, '/warehouse/delivery-orders/$doId/edit');
      await tester.enterText(
        find.byKey(DeliveryAllocationCard.qtyFieldKeyFor(lineId)),
        '0.5',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(DeliveryOrderFormPage.shipKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DeliveryOrderFormPage.confirmShipKey));
      await tester.pumpAndSettle();

      final lines = await context.deliveries.lineReferences(doId);
      expect(lines.single.shippedQty, Quantity.parse('0.5'));
      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
      final movements = await context.shipmentMovements(doId);
      expect(movements.single['qty'], 500);

      await disposeWidget(tester);
    });

    testWidgets('dialog konfirmasi menjelaskan efek stok dan finalitas', (
      tester,
    ) async {
      final doId = await preparedSimple();
      await pumpAt(tester, '/warehouse/delivery-orders/$doId/edit');

      await tester.tap(find.byKey(DeliveryOrderFormPage.shipKey));
      await tester.pumpAndSettle();

      expect(find.text('Kirim Surat Jalan?'), findsOneWidget);
      expect(
        find.textContaining('Stok Warehouse Pusat akan langsung berkurang'),
        findsOneWidget,
      );
      expect(find.textContaining('Aksi ini final'), findsOneWidget);

      // Cancelling changes nothing.
      await tester.tap(find.byKey(DeliveryOrderFormPage.cancelShipKey));
      await tester.pumpAndSettle();
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
      expect(await context.shipmentMovementCount(doId), 0);

      await disposeWidget(tester);
    });

    testWidgets('kirim berhasil menampilkan Surat Jalan dan mengurangi stok', (
      tester,
    ) async {
      final doId = await preparedSimple();
      await pumpAt(tester, '/warehouse/delivery-orders/$doId/edit');

      await tester.tap(find.byKey(DeliveryOrderFormPage.shipKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DeliveryOrderFormPage.confirmShipKey));
      await tester.pumpAndSettle();

      expect(await context.deliveryOrderStatusOf(doId), 'shipped');
      final balances = await context.balancesAt(fixture.warehouse.id);
      expect(balances['${fixture.simpleItem.id}|'], 1500);
      // Navigated to the waybill, which now prints as a real Surat Jalan.
      expect(find.text('SURAT JALAN'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('stok tidak mencukupi menampilkan pesan, bukan crash', (
      tester,
    ) async {
      final doId = await preparedSimple(qty: '2');
      await pumpAt(tester, '/warehouse/delivery-orders/$doId/edit');

      // Somebody else takes the stock while the form is open.
      await context.posting.postDisposal(
        locationId: fixture.warehouse.id,
        itemId: fixture.simpleItem.id,
        qty: Quantity.parse('2'),
        actorUserId: fixture.warehouseUser.id,
        note: 'Rusak',
      );

      await tester.tap(find.byKey(DeliveryOrderFormPage.shipKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DeliveryOrderFormPage.confirmShipKey));
      await tester.pumpAndSettle();

      // The failure's own Indonesian sentence, never a stack trace.
      expect(find.textContaining('Stok tidak mencukupi'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
      expect(await context.shipmentMovementCount(doId), 0);

      await disposeWidget(tester);
    });

    testWidgets('tombol kirim nonaktif saat dokumen kosong', (tester) async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
      await pumpAt(tester, '/warehouse/delivery-orders/${order.id}/edit');

      final button = tester.widget<FilledButton>(
        find.byKey(DeliveryOrderFormPage.shipKey),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'Dokumen tanpa alokasi tidak boleh dapat dikirim.',
      );

      await disposeWidget(tester);
    });
  });

  group('detail dan status akhir', () {
    testWidgets('dokumen shipped bersifat read-only', (tester) async {
      final doId = await preparedSimple();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await pumpAt(tester, '/warehouse/delivery-orders/$doId');

      // No edit affordance, and no receive button either — `shipped → received`
      // belongs to Good Receipt.
      expect(find.byKey(DeliveryOrderDetailPage.editKey), findsNothing);
      expect(find.text('Terima'), findsNothing);
      expect(find.byKey(DeliveryOrderFormPage.shipKey), findsNothing);
      expect(find.text('Menunggu pemeriksaan Good Receipt'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('dokumen preparing menawarkan ubah alokasi', (tester) async {
      final doId = await preparedSimple();
      await pumpAt(tester, '/warehouse/delivery-orders/$doId');

      expect(find.byKey(DeliveryOrderDetailPage.editKey), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('progres parsial dan penuh ditampilkan', (tester) async {
      // A one-position request shipped in full, so the completed state is visible.
      final prId = await writeProcessingPurchaseRequest(
        context,
        branchId: fixture.otherBranch.id,
        requestedBy: fixture.otherBranchHead.id,
        processedBy: fixture.warehouseUser.id,
        nowUtc: nowUtc,
        lines: {fixture.simpleItem.id: '1'},
        prId: 'pr-full',
      );
      final lineIds = await purchaseRequestLineIdsByItem(context, prId);
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: prId,
      );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [
          DeliveryAllocationFor(
            prLineId: lineIds[fixture.simpleItem.id]!,
            itemId: fixture.simpleItem.id,
            qty: '1',
          ).value,
        ],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: order.id,
      );

      await pumpAt(tester, '/warehouse/delivery-orders/${order.id}');
      expect(find.textContaining('Sisa 0 box'), findsWidgets);
      expect(await context.purchaseRequestStatusOf(prId), 'shipped');

      await disposeWidget(tester);
    });
  });
}

/// A one-off allocation for a request the fixture does not own.
///
/// The fixture's helpers are pinned to its own four positions; this exists for the
/// tests that build a smaller request to reach a state — a completed order — the
/// four-position fixture cannot.
class DeliveryAllocationFor {
  const DeliveryAllocationFor({
    required this.prLineId,
    required this.itemId,
    required this.qty,
  });

  final String prLineId;
  final String itemId;
  final String qty;

  DeliveryAllocation get value => DeliveryAllocation(
    prLineId: prLineId,
    itemId: itemId,
    qty: Quantity.parse(qty),
  );
}
