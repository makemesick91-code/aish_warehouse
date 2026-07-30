import 'package:aish_warehouse/features/delivery/presentation/pages/delivery_waybill_page.dart';
import 'package:aish_warehouse/features/delivery/presentation/providers/delivery_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Surat Jalan (§28, §44).
///
/// Generated entirely from the local database, so it works offline like everything
/// else (G-L3). The assertions that matter are about what a piece of paper says: a
/// draft must announce that it is one, quantities must read as quantities and never
/// as milli-units (Q-6), expiry dates must print exactly as stored (T-9), and the
/// audit behind a substituted batch or an accepted short shelf life must be on the
/// page rather than only in the database.
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

  Future<void> pumpWaybill(
    WidgetTester tester,
    String location, {
    bool asBranch = false,
  }) async {
    useTabletSurface(tester);
    await pumpAppAt(
      tester,
      context: context,
      actingAs: asBranch ? fixture.branchHead : fixture.warehouseUser,
      location: location,
      overrides: overrides,
    );
  }

  /// A document carrying one non-expiry line, one near-expiry batch with a
  /// confirmation, and one substituted batch with a FEFO reason — so every marker
  /// the page can print has something to print.
  Future<String> richOrder() => prepareDeliveryOrder(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [
      simpleAllocation(fixture, qty: '2.375'),
      batchAllocation(
        fixture,
        batchId: fixture.nearBatch.id,
        qty: '1.5',
        nearExpiryConfirmed: true,
        nearExpiryNote: 'Dipakai minggu ini',
      ),
      batchAllocation(
        fixture,
        batchId: fixture.safeBatch.id,
        qty: '0.5',
        fefoOverrideReason: 'Cabang minta masa simpan panjang',
      ),
    ],
  );

  group('draft', () {
    testWidgets('dokumen preparing dicetak dengan watermark draft', (
      tester,
    ) async {
      final doId = await richOrder();
      await pumpWaybill(tester, '/warehouse/delivery-orders/$doId/waybill');

      // A draft has taken nothing out of the warehouse, so a piece of paper that
      // looked like a Surat Jalan could travel with goods that were never posted.
      expect(find.byKey(DeliveryWaybillPage.draftBannerKey), findsOneWidget);
      expect(find.text('DRAFT — BELUM DIKIRIM'), findsWidgets);
      expect(find.text('SURAT JALAN'), findsNothing);
      // The shipper is unknown, and says so rather than showing a blank.
      expect(find.text('—'), findsWidgets);

      await disposeWidget(tester);
    });
  });

  group('final', () {
    testWidgets('dokumen shipped dicetak tanpa watermark', (tester) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await pumpWaybill(tester, '/warehouse/delivery-orders/$doId/waybill');

      expect(find.byKey(DeliveryWaybillPage.draftBannerKey), findsNothing);
      expect(find.byKey(DeliveryWaybillPage.titleKey), findsOneWidget);
      expect(find.text('SURAT JALAN'), findsOneWidget);
      expect(find.text('AISH WAREHOUSE'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('kepala dokumen memuat nomor, cabang dan alamat', (
      tester,
    ) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      final detail = await context.deliveries.getForWarehouse(doId);

      await pumpWaybill(tester, '/warehouse/delivery-orders/$doId/waybill');

      expect(find.text(detail!.summary.docNumber), findsOneWidget);
      expect(find.text(detail.summary.prDocNumber), findsOneWidget);
      expect(find.text('Warehouse Pusat'), findsOneWidget);
      expect(
        find.text('${fixture.branch.code} · ${fixture.branch.name}'),
        findsOneWidget,
      );
      expect(find.text('Jl. Uji No. 1'), findsOneWidget);
      expect(find.text(fixture.warehouseUser.fullName), findsWidgets);
      // Print time in operational GMT+8 (T-2).
      expect(
        find.textContaining('Dicetak 30 Jul 2026, 11:00 GMT+8'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('tabel barang memuat SKU, batch, ED, qty dan satuan', (
      tester,
    ) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await pumpWaybill(tester, '/warehouse/delivery-orders/$doId/waybill');

      for (final header in [
        'No',
        'SKU',
        'Barang',
        'Batch',
        'Expiry Date',
        'Qty',
        'Satuan',
        'Catatan',
      ]) {
        expect(find.text(header), findsOneWidget, reason: 'Kolom $header');
      }

      expect(find.text(fixture.simpleItem.sku), findsOneWidget);
      expect(find.text(fixture.simpleItem.name), findsOneWidget);
      expect(find.text(fixture.nearBatch.batchNo), findsOneWidget);
      // A civil date printed verbatim: 12 days from 2026-07-30 (T-9).
      expect(find.text('11 Agu 2026'), findsOneWidget);
      expect(find.text('box'), findsOneWidget);
      expect(find.text('ampul'), findsWidgets);
      // The non-expiry line has no batch and says so.
      expect(find.text('—'), findsWidgets);
      expect(find.text('Total 3 baris'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('kuantitas desimal diformat, bukan milli-unit', (tester) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await pumpWaybill(tester, '/warehouse/delivery-orders/$doId/waybill');

      expect(find.text('2.375'), findsOneWidget);
      expect(find.text('1.5'), findsOneWidget);
      expect(find.text('0.5'), findsOneWidget);
      // Q-6: a milli-unit value never reaches paper.
      for (final scaled in ['2375', '1500', '500']) {
        expect(
          find.text(scaled),
          findsNothing,
          reason: 'Milli-unit $scaled tidak boleh tercetak.',
        );
      }
      // Totals are grouped per unit, never added across them.
      expect(find.text('Total 2.375 box'), findsOneWidget);
      expect(find.text('Total 2 ampul'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('penanda near-expiry dan override FEFO tercetak', (
      tester,
    ) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await pumpWaybill(tester, '/warehouse/delivery-orders/$doId/waybill');

      // The audit that belongs on paper: why a batch was substituted, and that a
      // short shelf life was accepted (G-E3/G-E4).
      expect(find.textContaining('mendekati kedaluwarsa'), findsOneWidget);
      expect(
        find.textContaining('penggantian batch di luar saran FEFO'),
        findsOneWidget,
      );
      expect(find.text('Dekat ED: Dipakai minggu ini'), findsOneWidget);
      expect(
        find.text('FEFO: Cabang minta masa simpan panjang'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('placeholder tanda tangan tersedia', (tester) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await pumpWaybill(tester, '/warehouse/delivery-orders/$doId/waybill');

      expect(find.byKey(DeliveryWaybillPage.signaturesKey), findsOneWidget);
      expect(find.text('Petugas Warehouse'), findsOneWidget);
      expect(find.text('Pengantar'), findsOneWidget);
      expect(find.text('Penerima Cabang'), findsOneWidget);
      expect(find.text('(  nama & tanda tangan  )'), findsNWidgets(3));

      await disposeWidget(tester);
    });

    testWidgets('status sinkron tercetak', (tester) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await pumpWaybill(tester, '/warehouse/delivery-orders/$doId/waybill');

      // G-L3: a report header must make clear which data it reflects.
      expect(find.text('Menunggu sinkron'), findsOneWidget);

      await disposeWidget(tester);
    });
  });

  group('cabang', () {
    testWidgets('kepala cabang dapat mencetak Surat Jalan miliknya', (
      tester,
    ) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
      final detail = await context.deliveries.getForWarehouse(doId);

      await pumpWaybill(tester, '/deliveries/$doId/waybill', asBranch: true);

      expect(find.text('SURAT JALAN'), findsOneWidget);
      expect(find.text(detail!.summary.docNumber), findsOneWidget);
      expect(find.text(fixture.nearBatch.batchNo), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('tidak ada tombol aksi pada Surat Jalan', (tester) async {
      final doId = await richOrder();
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      await pumpWaybill(tester, '/deliveries/$doId/waybill', asBranch: true);

      // The page is a document, not a screen with affordances.
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Checkbox), findsNothing);

      await disposeWidget(tester);
    });
  });
}
