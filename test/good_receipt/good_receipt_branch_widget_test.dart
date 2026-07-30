import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_line_decision_policy.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/pages/branch_good_receipt_list_page.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/pages/good_receipt_detail_page.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/providers/good_receipt_providers.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/widgets/good_receipt_badges.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/widgets/good_receipt_dashboard_cards.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/widgets/good_receipt_line_card.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/widgets/good_receipt_reject_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The Kepala Cabang's screens (§49).
///
/// Everything is pumped through the **real router**, so the route guards, the redirect and
/// the scoped providers are all in the path. Pumping a page directly with an id would
/// bypass exactly the layer several of these assertions are about.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  /// The fixture is built before "now" so a shipment can be aged for the deadline
  /// assertions without predating the request it belongs to (§36).
  final fixtureUtc = nowUtc.subtract(const Duration(days: 10));

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: fixtureUtc);
  });

  tearDown(() => context.dispose());

  Future<void> pumpAsBranch(WidgetTester tester, String location) async {
    useTabletSurface(tester);
    await pumpAppAt(
      tester,
      context: context,
      actingAs: fixture.branchHead,
      location: location,
      overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
    );
  }

  /// A shipment sent [age] before "now".
  Future<String> shipment({
    Duration age = const Duration(hours: 5),
    bool withBatch = true,
  }) {
    final shippedAt = nowUtc.subtract(age);
    return shipDeliveryOrderFor(
      context,
      fixture,
      nowUtc: shippedAt,
      shippedAtUtc: shippedAt,
      allocations: [
        simpleAllocation(fixture, qty: '2.5'),
        if (withBatch) safeBatchAllocation(fixture, qty: '4'),
      ],
    );
  }

  Future<String> checkingReceipt({
    Duration age = const Duration(hours: 5),
  }) async => startGoodReceiptFor(
    context,
    fixture,
    deliveryOrderId: await shipment(age: age),
    nowUtc: nowUtc,
  );

  group('daftar Penerimaan', () {
    testWidgets('empty state ketika tidak ada pengiriman', (tester) async {
      await pumpAsBranch(tester, '/receipts');

      expect(find.byKey(BranchGoodReceiptListPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('Surat Jalan shipped muncul dengan tombol mulai', (
      tester,
    ) async {
      final doId = await shipment();
      await pumpAsBranch(tester, '/receipts');

      expect(find.byKey(BranchGoodReceiptListPage.emptyKey), findsNothing);
      expect(find.text('Mulai Pemeriksaan'), findsOneWidget);
      expect(find.text('Lanjutkan Pemeriksaan'), findsNothing);
      final order = await context.deliveries.getById(doId);
      expect(find.textContaining(order!.docNumber), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('GR checking muncul dengan tombol lanjutkan dan progres', (
      tester,
    ) async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.first;
      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        receivedQty: line.shippedQty,
      );

      await pumpAsBranch(tester, '/receipts');

      expect(find.text('Lanjutkan Pemeriksaan'), findsOneWidget);
      expect(find.textContaining('1/2 diperiksa'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('badge overdue muncul untuk pengiriman lewat 48 jam', (
      tester,
    ) async {
      await shipment(age: const Duration(hours: 60));
      await pumpAsBranch(tester, '/receipts');

      expect(find.byKey(GoodReceiptDeadlineBadge.overdueKey), findsOneWidget);
      expect(find.textContaining('12 jam'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('badge dalam tenggat untuk pengiriman baru', (tester) async {
      await shipment(age: const Duration(hours: 2));
      await pumpAsBranch(tester, '/receipts');

      expect(find.byKey(GoodReceiptDeadlineBadge.overdueKey), findsNothing);
      expect(find.byKey(GoodReceiptDeadlineBadge.dueKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('overdue diurutkan lebih dulu', (tester) async {
      // Two shipments of *different* positions: G-D2 caps the cumulative shipped
      // quantity per requested position, so repeating the first one's items would fail
      // on the delivery side before this test got to its own subject.
      final recent = await shipment(age: const Duration(hours: 2));
      final late_ = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc.subtract(const Duration(hours: 70)),
        shippedAtUtc: nowUtc.subtract(const Duration(hours: 70)),
        allocations: [tieAllocation(fixture, qty: '2')],
      );

      await pumpAsBranch(tester, '/receipts');

      final recentTile = tester.getTopLeft(
        find.byKey(ValueKey('awaitingReceiptTile-$recent')),
      );
      final lateTile = tester.getTopLeft(
        find.byKey(ValueKey('awaitingReceiptTile-$late_')),
      );
      expect(lateTile.dy, lessThan(recentTile.dy));

      await disposeWidget(tester);
    });

    testWidgets('riwayat GR posted muncul di bagian tersendiri', (
      tester,
    ) async {
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

      await pumpAsBranch(tester, '/receipts');

      expect(
        find.byKey(BranchGoodReceiptListPage.historySectionKey),
        findsOneWidget,
      );
      expect(
        find.byKey(GoodReceiptSummaryTile.tileKeyFor(grId)),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });
  });

  group('layar pemeriksaan', () {
    testWidgets('header memuat nomor GR, SJ, PR dan tenggat', (tester) async {
      final grId = await checkingReceipt();
      final detail = await context.receipts.getDetail(grId);

      await pumpAsBranch(tester, '/receipts/$grId');

      expect(find.text(detail!.summary.docNumber), findsOneWidget);
      expect(find.textContaining(detail.summary.doDocNumber), findsWidgets);
      expect(find.textContaining(detail.summary.prDocNumber), findsWidgets);
      expect(find.textContaining('Tenggat'), findsWidgets);
      expect(find.textContaining('GMT+8'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('baris menampilkan batch, ED dan sisa hari', (tester) async {
      final grId = await checkingReceipt();
      await pumpAsBranch(tester, '/receipts/$grId');

      expect(
        find.textContaining('Batch ${fixture.safeBatch.batchNo}'),
        findsOneWidget,
      );
      // The date itself and the badge's own day count both mention ED.
      expect(find.textContaining('ED '), findsWidgets);
      expect(find.byKey(GoodReceiptExpiryBadge.badgeKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('progres 0/2 dan tombol posting nonaktif', (tester) async {
      final grId = await checkingReceipt();
      await pumpAsBranch(tester, '/receipts/$grId');

      expect(find.textContaining('0/2 diperiksa'), findsOneWidget);
      expect(
        find.byKey(GoodReceiptDetailPage.pendingNoticeKey),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(GoodReceiptDetailPage.postButtonKey),
      );
      expect(button.onPressed, isNull);
      await disposeWidget(tester);
    });

    testWidgets('input desimal diterima dan tersimpan sebagai checked', (
      tester,
    ) async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.itemId == fixture.simpleItem.id);

      await pumpAsBranch(tester, '/receipts/$grId');

      await tester.enterText(
        find.byKey(GoodReceiptLineCard.quantityKeyFor(line.id)),
        '1.25',
      );
      await tester.tap(find.byKey(GoodReceiptLineCard.checkKeyFor(line.id)));
      await tester.pumpAndSettle();

      final stored = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.id == line.id);
      expect(stored.isChecked, isTrue);
      expect(stored.receivedQty, Quantity.parse('1.25'));
      // Milli-units are never shown to a user (Q-6).
      expect(find.textContaining('1250'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('selisih tampil setelah menerima kurang', (tester) async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.itemId == fixture.simpleItem.id);

      await pumpAsBranch(tester, '/receipts/$grId');
      await tester.enterText(
        find.byKey(GoodReceiptLineCard.quantityKeyFor(line.id)),
        '1',
      );
      await tester.tap(find.byKey(GoodReceiptLineCard.checkKeyFor(line.id)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(GoodReceiptLineCard.discrepancyKeyFor(line.id)),
        findsOneWidget,
      );
      expect(find.textContaining('Selisih 1.5 box'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('sheet penolakan menuntut alasan Lainnya', (tester) async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.first;

      await pumpAsBranch(tester, '/receipts/$grId');
      await tester.tap(find.byKey(GoodReceiptLineCard.rejectKeyFor(line.id)));
      await tester.pumpAndSettle();

      expect(find.byKey(GoodReceiptRejectSheet.sheetKey), findsOneWidget);
      await tester.tap(
        find.byKey(
          GoodReceiptRejectSheet.presetKeyFor(
            GoodReceiptRejectReasonPresetForTest.other,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoodReceiptRejectSheet.submitKey));
      await tester.pumpAndSettle();

      // Still open, with the detail demanded: *Lainnya* on its own explains nothing.
      expect(find.byKey(GoodReceiptRejectSheet.sheetKey), findsOneWidget);
      expect(find.textContaining('wajib disertai detail'), findsOneWidget);

      final stored = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.id == line.id);
      expect(stored.isPending, isTrue);
      await disposeWidget(tester);
    });

    testWidgets('penolakan dengan preset tersimpan dan tampil', (tester) async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.first;

      await pumpAsBranch(tester, '/receipts/$grId');
      await tester.tap(find.byKey(GoodReceiptLineCard.rejectKeyFor(line.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoodReceiptRejectSheet.submitKey));
      await tester.pumpAndSettle();

      final stored = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.id == line.id);
      expect(stored.isRejected, isTrue);
      expect(stored.rejectReason, 'Rusak');
      expect(stored.receivedQty, Quantity.zero());
      expect(find.text('Rusak'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('membatalkan sheet tidak mengubah baris', (tester) async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.first;

      await pumpAsBranch(tester, '/receipts/$grId');
      await tester.tap(find.byKey(GoodReceiptLineCard.rejectKeyFor(line.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoodReceiptRejectSheet.cancelKey));
      await tester.pumpAndSettle();

      final stored = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.id == line.id);
      expect(stored.isPending, isTrue);
      await disposeWidget(tester);
    });
  });

  group('G-E5 pada layar', () {
    /// A shipment carrying a batch inside its alert window, which the warehouse
    /// confirmed (G-E4) and the branch must refuse (G-E5).
    Future<String> nearExpiryReceipt() async {
      final shippedAt = nowUtc.subtract(const Duration(hours: 5));
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: shippedAt,
        shippedAtUtc: shippedAt,
        allocations: [
          batchAllocation(
            fixture,
            batchId: fixture.nearBatch.id,
            qty: '1',
            nearExpiryConfirmed: true,
            nearExpiryNote: 'Disetujui warehouse',
          ),
        ],
      );
      return startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
    }

    testWidgets('batch dekat ED tidak dapat di-check dari layar', (
      tester,
    ) async {
      final grId = await nearExpiryReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.single;

      await pumpAsBranch(tester, '/receipts/$grId');

      final button = tester.widget<FilledButton>(
        find.byKey(GoodReceiptLineCard.checkKeyFor(line.id)),
      );
      // Disabled rather than hidden: the branch head has the goods in their hands and
      // needs telling *why* they cannot accept them.
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('harus ditolak dan tidak boleh masuk stok cabang'),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('sheet membuka dengan alasan kedaluwarsa terkunci', (
      tester,
    ) async {
      final grId = await nearExpiryReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.single;

      await pumpAsBranch(tester, '/receipts/$grId');
      await tester.tap(find.byKey(GoodReceiptLineCard.rejectKeyFor(line.id)));
      await tester.pumpAndSettle();

      expect(find.textContaining('wajib ditolak dengan'), findsOneWidget);
      // Every other preset is rendered but not selectable, so the reader can see the
      // whole vocabulary and why this one applies.
      final damaged = tester.widget<ChoiceChip>(
        find.byKey(
          GoodReceiptRejectSheet.presetKeyFor(
            GoodReceiptRejectReasonPresetForTest.damaged,
          ),
        ),
      );
      expect(damaged.onSelected, isNull);

      await tester.tap(find.byKey(GoodReceiptRejectSheet.submitKey));
      await tester.pumpAndSettle();

      final stored = (await context.receipts.getDetail(grId))!.lines.single;
      expect(stored.isRejected, isTrue);
      expect(stored.rejectReason, contains('Kedaluwarsa'));
      await disposeWidget(tester);
    });

    testWidgets('badge dekat ED tampil pada baris', (tester) async {
      final grId = await nearExpiryReceipt();
      await pumpAsBranch(tester, '/receipts/$grId');

      expect(find.byKey(GoodReceiptExpiryBadge.badgeKey), findsOneWidget);
      expect(find.textContaining('Dekat ED'), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('posting', () {
    Future<String> decidedReceipt(WidgetTester tester) async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      return grId;
    }

    testWidgets('tombol posting aktif setelah semua diputuskan', (
      tester,
    ) async {
      final grId = await decidedReceipt(tester);
      await pumpAsBranch(tester, '/receipts/$grId');

      expect(find.byKey(GoodReceiptDetailPage.pendingNoticeKey), findsNothing);
      final button = tester.widget<FilledButton>(
        find.byKey(GoodReceiptDetailPage.postButtonKey),
      );
      expect(button.onPressed, isNotNull);
      await disposeWidget(tester);
    });

    testWidgets('dialog konfirmasi menjelaskan efek stok dan finalitas', (
      tester,
    ) async {
      final grId = await decidedReceipt(tester);
      await pumpAsBranch(tester, '/receipts/$grId');

      await tester.tap(find.byKey(GoodReceiptDetailPage.postButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(GoodReceiptDetailPage.confirmDialogKey),
        findsOneWidget,
      );
      expect(
        find.textContaining('Stok Gudang Cabang akan bertambah'),
        findsOneWidget,
      );
      expect(find.textContaining('Tindakan ini final'), findsOneWidget);
      expect(
        find.textContaining('Surat Jalan akan ditandai diterima'),
        findsOneWidget,
      );

      // Cancelling writes nothing.
      await tester.tap(find.byKey(GoodReceiptDetailPage.confirmCancelKey));
      await tester.pumpAndSettle();
      expect(await context.goodReceiptStatusOf(grId), 'checking');
      await disposeWidget(tester);
    });

    testWidgets('posting berhasil menambah stok dan menjadi read-only', (
      tester,
    ) async {
      final grId = await decidedReceipt(tester);
      await pumpAsBranch(tester, '/receipts/$grId');

      await tester.tap(find.byKey(GoodReceiptDetailPage.postButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoodReceiptDetailPage.confirmSubmitKey));
      await tester.pumpAndSettle();

      expect(await context.goodReceiptStatusOf(grId), 'posted');
      expect(await context.balancesAt(fixture.branchStore.id), hasLength(2));
      // The bottom bar is gone, and so is every line action. Addressed by key rather
      // than by prose, because *Sesuai* is also the label of the decision chip a posted
      // line displays — the word survives, the button does not.
      expect(find.byKey(GoodReceiptDetailPage.postButtonKey), findsNothing);
      final lines = (await context.receipts.getDetail(grId))!.lines;
      for (final line in lines) {
        expect(
          find.byKey(GoodReceiptLineCard.checkKeyFor(line.id)),
          findsNothing,
        );
        expect(
          find.byKey(GoodReceiptLineCard.rejectKeyFor(line.id)),
          findsNothing,
        );
        expect(
          find.byKey(GoodReceiptLineCard.quantityKeyFor(line.id)),
          findsNothing,
        );
      }
      expect(find.byType(TextField), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('input tertunda di-flush sebelum posting', (tester) async {
      final grId = await decidedReceipt(tester);
      final line = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.itemId == fixture.simpleItem.id);

      await pumpAsBranch(tester, '/receipts/$grId');
      // Typed, never confirmed with ✔ — a controller living inside the lazily built list
      // would have lost this the moment the row scrolled away.
      await tester.enterText(
        find.byKey(GoodReceiptLineCard.quantityKeyFor(line.id)),
        '0.5',
      );
      await tester.tap(find.byKey(GoodReceiptDetailPage.postButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoodReceiptDetailPage.confirmSubmitKey));
      await tester.pumpAndSettle();

      final stored = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.id == line.id);
      expect(stored.receivedQty, Quantity.parse('0.5'));
      expect(stored.discrepancyQty, Quantity.parse('2'));
      await disposeWidget(tester);
    });

    testWidgets('posting menampilkan hasil dan ringkasan read-only', (
      tester,
    ) async {
      final grId = await decidedReceipt(tester);
      await pumpAsBranch(tester, '/receipts/$grId');

      await tester.tap(find.byKey(GoodReceiptDetailPage.postButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoodReceiptDetailPage.confirmSubmitKey));
      await tester.pumpAndSettle();

      expect(find.text('Ringkasan penerimaan'), findsOneWidget);
      expect(find.byKey(GoodReceiptDetailPage.postedNoticeKey), findsOneWidget);
      expect(find.textContaining('Diterima'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('kegagalan menampilkan pesan, bukan crash', (tester) async {
      final grId = await decidedReceipt(tester);
      // No branch store to credit: the posting refuses, and the screen has to say so in
      // Indonesian rather than surface an exception.
      await context.corruptByDeleting(
        'stock_locations',
        fixture.branchStore.id,
      );

      await pumpAsBranch(tester, '/receipts/$grId');
      await tester.tap(find.byKey(GoodReceiptDetailPage.postButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoodReceiptDetailPage.confirmSubmitKey));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Lokasi Gudang Cabang belum tersedia'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(await context.goodReceiptStatusOf(grId), 'checking');
      await disposeWidget(tester);
    });
  });

  group('memulai pemeriksaan dari daftar', () {
    testWidgets('mulai pemeriksaan membuat GR dan membuka checklist', (
      tester,
    ) async {
      final doId = await shipment();
      await pumpAsBranch(tester, '/receipts');

      await tester.tap(find.text('Mulai Pemeriksaan'));
      await tester.pumpAndSettle();

      expect(await context.goodReceiptCountFor(doId), 1);
      expect(find.textContaining('0/2 diperiksa'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('rute create langsung juga membuat GR', (tester) async {
      final doId = await shipment();
      await pumpAsBranch(tester, '/receipts/new/$doId');

      expect(await context.goodReceiptCountFor(doId), 1);
      expect(find.text('Pemeriksaan Barang'), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('kartu pengingat dashboard', () {
    testWidgets('kartu muncul untuk Kepala Cabang dengan pengiriman overdue', (
      tester,
    ) async {
      await shipment(age: const Duration(hours: 60));
      await pumpAsBranch(tester, '/');

      expect(find.byKey(GoodReceiptReminderCard.cardKey), findsOneWidget);
      expect(find.textContaining('melewati batas 2×24 jam'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('kartu tidak muncul ketika tidak ada yang mendesak', (
      tester,
    ) async {
      await shipment(age: const Duration(hours: 2));
      await pumpAsBranch(tester, '/');

      // A card that is always on screen is a card nobody reads.
      expect(find.byKey(GoodReceiptReminderCard.cardKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('kartu selisih warehouse tidak muncul untuk cabang', (
      tester,
    ) async {
      await shipment(age: const Duration(hours: 60));
      await pumpAsBranch(tester, '/');

      expect(find.byKey(GoodReceiptDiscrepancyCard.cardKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('kartu mengarah ke daftar Penerimaan', (tester) async {
      await shipment(age: const Duration(hours: 60));
      await pumpAsBranch(tester, '/');

      await tester.tap(find.byKey(GoodReceiptReminderCard.cardKey));
      await tester.pumpAndSettle();

      expect(find.byKey(BranchGoodReceiptListPage.listKey), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('entry point dari detail pengiriman', () {
    testWidgets('detail Surat Jalan menawarkan Terima Barang', (tester) async {
      final doId = await shipment();
      await pumpAsBranch(tester, '/deliveries/$doId');

      expect(find.text('Terima Barang'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('setelah GR dimulai berubah menjadi Lanjutkan Pemeriksaan', (
      tester,
    ) async {
      final doId = await shipment();
      await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );

      await pumpAsBranch(tester, '/deliveries/$doId');

      expect(find.text('Lanjutkan Pemeriksaan'), findsOneWidget);
      expect(find.text('Terima Barang'), findsNothing);
      await disposeWidget(tester);
    });
  });
}

/// The reject presets, re-exported so the widget test can name them without importing the
/// domain policy into a file about widgets.
///
/// A thin alias rather than a second enum: the values are the policy's, so a preset added
/// there appears here rather than being silently absent from the tests.
typedef GoodReceiptRejectReasonPresetForTest = GoodReceiptRejectReasonPreset;
