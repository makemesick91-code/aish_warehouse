import 'package:aish_warehouse/app/routes.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/features/goods_return/presentation/pages/branch_goods_return_list_page.dart';
import 'package:aish_warehouse/features/goods_return/presentation/pages/goods_return_detail_page.dart';
import 'package:aish_warehouse/features/goods_return/presentation/pages/warehouse_goods_return_pages.dart';
import 'package:aish_warehouse/features/goods_return/presentation/providers/goods_return_providers.dart';
import 'package:aish_warehouse/features/goods_return/presentation/widgets/goods_return_badges.dart';
import 'package:aish_warehouse/features/goods_return/presentation/widgets/goods_return_link_chip.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/pages/warehouse_good_receipt_discrepancy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The two Retur sections as a user meets them (§29 … §33/§49).
///
/// The assertions that matter most are the **absences**: no quantity field, no item
/// picker, no add or remove control, no partial checkbox. Those are not simplifications
/// that a later milestone fills in — they are what makes the document a faithful copy of
/// the Good Receipt's rejections (§18), and a screen that grew one would be a screen
/// that lets somebody rewrite what the branch refused.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  final clockOverride = <Override>[
    goodsReturnClockProvider.overrideWithValue(() => nowUtc),
  ];

  group('Kepala Cabang — antrean Perlu Dibuat', () {
    testWidgets('GR dengan barang ditolak tampil beserta tombol Buat Retur', (
      tester,
    ) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: AppRoutes.returns,
        overrides: clockOverride,
      );

      expect(
        find.byKey(
          BranchGoodsReturnListPage.createButtonKey(fixture.goodReceiptId),
        ),
        findsOneWidget,
      );
      // The reject reasons and the near-expiry warning are on the card, so a branch
      // head knows what they are about to raise (§29).
      expect(find.textContaining('Kemasan rusak saat diterima'), findsWidgets);
      expect(find.textContaining('segera kedaluwarsa'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('baris kekurangan tidak muncul dan tidak punya tombol', (
      tester,
    ) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: AppRoutes.returns,
        overrides: clockOverride,
      );

      // §16.10, on the screen that would most easily blur it. The shortage line's item
      // is `tieItem`, and it must not be offered as returnable anywhere.
      expect(find.textContaining(fixture.tieItem.sku), findsNothing);
      expect(find.textContaining('Kekurangan'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('GR yang sudah punya retur tidak lagi bisa dibuat', (
      tester,
    ) async {
      useTabletSurface(tester);
      await createGoodsReturnFor(context, fixture);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: AppRoutes.returns,
        overrides: clockOverride,
      );

      expect(
        find.byKey(
          BranchGoodsReturnListPage.createButtonKey(fixture.goodReceiptId),
        ),
        findsNothing,
      );
      expect(
        find.byKey(BranchGoodsReturnListPage.pendingEmptyKey),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('satu tap membuat snapshot dan membuka detail draft', (
      tester,
    ) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: AppRoutes.returns,
        overrides: clockOverride,
      );

      await tester.tap(
        find.byKey(
          BranchGoodsReturnListPage.createButtonKey(fixture.goodReceiptId),
        ),
      );
      await tester.pumpAndSettle();

      expect(await context.goodsReturnCountFor(fixture.goodReceiptId), 1);
      // Pushed *replacing* the queue, so Back does not return to a dead button (§30).
      expect(find.byKey(GoodsReturnDetailPage.linesKey), findsOneWidget);
      expect(find.byKey(GoodsReturnDetailPage.shipButtonKey), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('Kepala Cabang — detail draft', () {
    Future<String> openDraft(WidgetTester tester) async {
      final created = await createGoodsReturnFor(context, fixture);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/returns/${created.id}',
        overrides: clockOverride,
      );
      return created.id;
    }

    testWidgets('seluruh baris rejected tampil dengan qty dan alasan', (
      tester,
    ) async {
      useTabletSurface(tester);
      await openDraft(tester);

      expect(find.byType(GoodsReturnLineTile), findsNWidgets(2));
      expect(
        find.text(
          '${fixture.rejectedSimpleQty.format()} ${fixture.simpleItem.unit}',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Alasan ditolak: Kemasan rusak saat diterima'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Alasan ditolak: Sisa umur simpan terlalu pendek'),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('tidak ada editor kuantitas, picker atau kontrol baris', (
      tester,
    ) async {
      useTabletSurface(tester);
      await openDraft(tester);

      // Exactly one text field on the whole screen: the branch note.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(GoodsReturnDetailPage.noteFieldKey), findsOneWidget);

      for (final label in const [
        'Tambah Baris',
        'Hapus Baris',
        'Ubah Kuantitas',
        'Pilih Barang',
        'Pilih Batch',
        'Terima Sebagian',
      ]) {
        expect(
          find.text(label),
          findsNothing,
          reason: '"$label" tidak boleh ada pada dokumen Retur.',
        );
      }
      await disposeWidget(tester);
    });

    testWidgets('dialog kirim menjelaskan bahwa saldo belum bertambah', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await openDraft(tester);

      await tester.tap(find.byKey(GoodsReturnDetailPage.shipButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Saldo Gudang Cabang tidak berubah'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Saldo Warehouse baru bertambah setelah Warehouse mengonfirmasi',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(GoodsReturnDetailPage.shipConfirmKey));
      await tester.pumpAndSettle();

      expect(await context.goodsReturnStatusOf(id), 'shipped');
      expect(
        await context.goodsReturnMovementCount(id),
        0,
        reason: 'Pengiriman tidak menulis ledger (§20).',
      );
      await disposeWidget(tester);
    });

    testWidgets('detail shipped read-only, tanpa tombol kirim', (tester) async {
      useTabletSurface(tester);
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/returns/${shipped.id}',
        overrides: clockOverride,
      );

      expect(find.byKey(GoodsReturnDetailPage.shipButtonKey), findsNothing);
      expect(find.byKey(GoodsReturnDetailPage.readOnlyKey), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('catatan draft tersimpan', (tester) async {
      useTabletSurface(tester);
      final id = await openDraft(tester);

      await tester.enterText(
        find.byKey(GoodsReturnDetailPage.noteFieldKey),
        'Dikirim via kurir internal',
      );
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();

      expect(
        await context.goodsReturnColumn(id, 'note'),
        'Dikirim via kurir internal',
      );
      await disposeWidget(tester);
    });
  });

  group('Warehouse — antrean', () {
    testWidgets('antrean kosong sebelum ada yang dikirim', (tester) async {
      useTabletSurface(tester);
      await createGoodsReturnFor(context, fixture);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: AppRoutes.warehouseReturns,
        overrides: clockOverride,
      );

      expect(
        find.byKey(WarehouseGoodsReturnListPage.queueEmptyKey),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('retur yang dikirim muncul dengan cabang dan umur perjalanan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: AppRoutes.warehouseReturns,
        overrides: clockOverride,
      );

      expect(
        find.byKey(GoodsReturnSummaryCard.keyFor(shipped.id)),
        findsOneWidget,
      );
      expect(find.textContaining(fixture.branch.code), findsWidgets);
      expect(find.textContaining('di jalan'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('draft cabang tidak pernah muncul di antrean Warehouse', (
      tester,
    ) async {
      useTabletSurface(tester);
      final draft = await createGoodsReturnFor(context, fixture);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: AppRoutes.warehouseReturns,
        overrides: clockOverride,
      );

      expect(find.byKey(GoodsReturnSummaryCard.keyFor(draft.id)), findsNothing);
      expect(find.text(draft.docNumber), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('filter cabang menyempitkan antrean', (tester) async {
      useTabletSurface(tester);
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: AppRoutes.warehouseReturns,
        overrides: clockOverride,
      );
      expect(
        find.byKey(GoodsReturnSummaryCard.keyFor(shipped.id)),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          WarehouseGoodsReturnListPage.branchChipKey(fixture.otherBranch.id),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(GoodsReturnSummaryCard.keyFor(shipped.id)),
        findsNothing,
      );
      await disposeWidget(tester);
    });
  });

  group('Warehouse — detail penerimaan', () {
    testWidgets('dialog menyebut tujuan, jumlah dan batch kedaluwarsa', (
      tester,
    ) async {
      useTabletSurface(tester);
      // Run at the instant `nearBatch` has expired, so the dialog has an expired count
      // to state — an expired batch is information here, never a refusal (§36).
      final at = fixture.expiredInstant;
      final shipped = await shippedGoodsReturnFor(context, fixture, nowUtc: at);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/returns/${shipped.id}',
        overrides: [goodsReturnClockProvider.overrideWithValue(() => at)],
      );

      await tester.tap(
        find.byKey(WarehouseGoodsReturnDetailPage.receiveButtonKey),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Tujuan: Warehouse Pusat'), findsOneWidget);
      expect(find.textContaining('2 posisi'), findsOneWidget);
      expect(
        find.textContaining('1 posisi memuat batch kedaluwarsa'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Movement return akan dibuat untuk setiap baris'),
        findsOneWidget,
      );
      expect(find.textContaining('Tindakan ini final'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('konfirmasi menambah saldo dan mengunci dokumen', (
      tester,
    ) async {
      useTabletSurface(tester);
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final before = await context.balancesAt(fixture.warehouse.id);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/returns/${shipped.id}',
        overrides: clockOverride,
      );

      await tester.enterText(
        find.byKey(WarehouseGoodsReturnDetailPage.noteFieldKey),
        'Kardus penyok, isi lengkap',
      );
      await tester.tap(
        find.byKey(WarehouseGoodsReturnDetailPage.receiveButtonKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(WarehouseGoodsReturnDetailPage.receiveConfirmKey),
      );
      await tester.pumpAndSettle();

      expect(await context.goodsReturnStatusOf(shipped.id), 'received');
      expect(await context.goodsReturnMovementCount(shipped.id), 2);
      expect(
        await context.goodsReturnColumn(shipped.id, 'warehouse_note'),
        'Kardus penyok, isi lengkap',
      );
      expect(
        await context.balancesAt(fixture.warehouse.id),
        isNot(before),
        reason: 'Saldo Warehouse harus bertambah.',
      );

      // And the screen is now read-only.
      expect(
        find.byKey(WarehouseGoodsReturnDetailPage.readOnlyKey),
        findsOneWidget,
      );
      expect(
        find.byKey(WarehouseGoodsReturnDetailPage.receiveButtonKey),
        findsNothing,
      );
      await disposeWidget(tester);
    });

    testWidgets('tidak ada checkbox parsial atau editor kuantitas', (
      tester,
    ) async {
      useTabletSurface(tester);
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/returns/${shipped.id}',
        overrides: clockOverride,
      );

      // §16.16: a Warehouse user who finds a mismatch must not be able to quietly
      // write down what they actually found.
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Slider), findsNothing);
      // One field only: the Warehouse note.
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.byKey(WarehouseGoodsReturnDetailPage.noteFieldKey),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });
  });

  group('integrasi antrean selisih GR', () {
    Future<void> openDiscrepancies(WidgetTester tester) => pumpAppAt(
      tester,
      context: context,
      actingAs: fixture.warehouseUser,
      location: AppRoutes.warehouseGoodReceiptDiscrepancies,
      overrides: clockOverride,
    );

    testWidgets('rejected tanpa retur berbunyi Belum dibuat', (tester) async {
      useTabletSurface(tester);
      await openDiscrepancies(tester);

      expect(
        find.byKey(GoodsReturnLinkChip.keyFor(fixture.rejectedSimpleLineId)),
        findsOneWidget,
      );
      expect(
        find.textContaining(GoodsReturnLinkChip.notCreatedLabel),
        findsWidgets,
      );
      await disposeWidget(tester);
    });

    testWidgets('status chip mengikuti dokumen: draft, dikirim, diterima', (
      tester,
    ) async {
      useTabletSurface(tester);

      await createGoodsReturnFor(context, fixture);
      await openDiscrepancies(tester);
      expect(find.textContaining('Retur: Draft'), findsWidgets);
      await disposeWidget(tester);

      final draft = await context.goodsReturns.findByGoodReceipt(
        fixture.goodReceiptId,
      );
      await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: draft!.id);
      await openDiscrepancies(tester);
      expect(find.textContaining('Retur: Dikirim'), findsWidgets);
      await disposeWidget(tester);

      await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, goodsReturnId: draft.id);
      await openDiscrepancies(tester);
      expect(find.textContaining('Retur: Diterima'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('baris kekurangan tetap Kekurangan, tanpa chip retur', (
      tester,
    ) async {
      useTabletSurface(tester);
      await openDiscrepancies(tester);

      // The line that arrived short carries the discrepancy badge and **no** return
      // chip — there is no box coming back, so there is no document to show (§33).
      expect(
        find.byKey(GoodsReturnLinkChip.keyFor(fixture.shortageLineId)),
        findsNothing,
      );
      expect(find.textContaining('Kekurangan'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('tidak ada tombol Buat Retur di layar Warehouse', (
      tester,
    ) async {
      useTabletSurface(tester);
      await openDiscrepancies(tester);

      // Raising a return is the branch's act: the goods are at *their* building (§15).
      expect(find.text('Buat Retur'), findsNothing);
      expect(find.byType(WarehouseGoodReceiptDiscrepancyPage), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('layar sempit', () {
    testWidgets('detail cabang tidak overflow pada layar ponsel', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 690);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final shipped = await shippedGoodsReturnFor(context, fixture);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/returns/${shipped.id}',
        overrides: clockOverride,
      );

      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });

    testWidgets('antrean Warehouse tidak overflow pada layar ponsel', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 690);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await shippedGoodsReturnFor(context, fixture);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: AppRoutes.warehouseReturns,
        overrides: clockOverride,
      );

      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });
  });

  group('label status', () {
    testWidgets('kata yang dipakai bukan kata persetujuan', (tester) async {
      useTabletSurface(tester);
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/returns/${shipped.id}',
        overrides: clockOverride,
      );

      expect(find.text(GoodsReturnStatus.shipped.label), findsWidgets);
      for (final forbidden in const [
        'Setujui',
        'Disetujui',
        'Menunggu Persetujuan',
        'Ajukan',
        'Approval',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'Retur tidak punya tahap persetujuan (§8).',
        );
      }
      await disposeWidget(tester);
    });
  });
}
