import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/pages/good_receipt_detail_page.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/pages/warehouse_good_receipt_discrepancy_page.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/pages/warehouse_good_receipt_list_page.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/providers/good_receipt_providers.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/widgets/good_receipt_badges.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/widgets/good_receipt_dashboard_cards.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/widgets/good_receipt_line_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The warehouse's read-only screens (§49).
///
/// The absences are the assertions here: no create control, no decide control, no post
/// control, and nothing that adds stock back to the warehouse or marks a return done.
/// Those are not omissions this test happens to notice — they are what §33 requires,
/// because the goods a branch refused are physically at the branch and nobody has counted
/// them back in.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();
  final fixtureUtc = nowUtc.subtract(const Duration(days: 10));

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: fixtureUtc);
  });

  tearDown(() => context.dispose());

  Future<void> pumpAsWarehouse(WidgetTester tester, String location) async {
    useTabletSurface(tester);
    await pumpAppAt(
      tester,
      context: context,
      actingAs: fixture.warehouseUser,
      location: location,
      overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
    );
  }

  /// A posted receipt with one shortage and one refusal — one row of each kind on the
  /// queue.
  Future<String> postedWithBoth({
    Duration age = const Duration(hours: 5),
  }) async {
    final shippedAt = nowUtc.subtract(age);
    final doId = await shipDeliveryOrderFor(
      context,
      fixture,
      nowUtc: shippedAt,
      shippedAtUtc: shippedAt,
      allocations: [
        simpleAllocation(fixture, qty: '2.5'),
        safeBatchAllocation(fixture, qty: '4'),
      ],
    );
    final grId = await startGoodReceiptFor(
      context,
      fixture,
      deliveryOrderId: doId,
      nowUtc: nowUtc,
    );
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
      reason: 'Rusak — kemasan pecah',
    );
    await context.postGoodReceipt().call(
      actorUserId: fixture.branchHead.id,
      goodReceiptId: grId,
    );
    return grId;
  }

  group('daftar Penerimaan Cabang', () {
    testWidgets('empty state ketika belum ada GR diposting', (tester) async {
      await pumpAsWarehouse(tester, '/warehouse/good-receipts');

      expect(find.byKey(WarehouseGoodReceiptListPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('GR posted muncul lintas cabang', (tester) async {
      final grId = await postedWithBoth();
      final receipt = await context.receipts.getById(grId);

      await pumpAsWarehouse(tester, '/warehouse/good-receipts');

      expect(find.text(receipt!.docNumber), findsOneWidget);
      expect(find.textContaining(fixture.branch.name), findsWidgets);
      expect(find.textContaining('1 ditolak'), findsOneWidget);
      expect(find.textContaining('1 kurang'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('GR yang masih checking tidak muncul', (tester) async {
      final shippedAt = nowUtc.subtract(const Duration(hours: 5));
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: shippedAt,
        shippedAtUtc: shippedAt,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final receipt = await context.receipts.getById(grId);

      await pumpAsWarehouse(tester, '/warehouse/good-receipts');

      // A branch head part way through a decision has not refused anything yet.
      expect(find.text(receipt!.docNumber), findsNothing);
      expect(find.byKey(WarehouseGoodReceiptListPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('pencarian menyaring daftar', (tester) async {
      await postedWithBoth();
      await pumpAsWarehouse(tester, '/warehouse/good-receipts');

      await tester.enterText(
        find.byKey(WarehouseGoodReceiptListPage.searchKey),
        'tidak-ada-nomor',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(WarehouseGoodReceiptListPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('peringatan overdue lintas cabang tampil', (tester) async {
      final shippedAt = nowUtc.subtract(const Duration(hours: 60));
      await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: shippedAt,
        shippedAtUtc: shippedAt,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );

      await pumpAsWarehouse(tester, '/warehouse/good-receipts');

      expect(
        find.textContaining('belum diposting cabang dalam batas 2×24 jam'),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('tautan ke antrean selisih tersedia', (tester) async {
      await postedWithBoth();
      await pumpAsWarehouse(tester, '/warehouse/good-receipts');

      await tester.tap(
        find.byKey(WarehouseGoodReceiptListPage.discrepancyLinkKey),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(WarehouseGoodReceiptDiscrepancyPage.listKey),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });
  });

  group('detail GR untuk Warehouse', () {
    testWidgets('detail posted read-only tanpa aksi apa pun', (tester) async {
      final grId = await postedWithBoth();

      await pumpAsWarehouse(tester, '/warehouse/good-receipts/$grId');

      expect(find.text('Ringkasan penerimaan'), findsOneWidget);
      // No post bar, and no line action of any kind.
      expect(find.byKey(GoodReceiptDetailPage.postButtonKey), findsNothing);
      for (final line in (await context.receipts.getDetail(grId))!.lines) {
        expect(
          find.byKey(GoodReceiptLineCard.checkKeyFor(line.id)),
          findsNothing,
        );
        expect(
          find.byKey(GoodReceiptLineCard.rejectKeyFor(line.id)),
          findsNothing,
        );
        expect(
          find.byKey(GoodReceiptLineCard.resetKeyFor(line.id)),
          findsNothing,
        );
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('alasan penolakan terbaca oleh Warehouse', (tester) async {
      final grId = await postedWithBoth();

      await pumpAsWarehouse(tester, '/warehouse/good-receipts/$grId');

      expect(find.text('Rusak — kemasan pecah'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('dikirim, diterima dan selisih ditampilkan per baris', (
      tester,
    ) async {
      final grId = await postedWithBoth();
      final line = (await context.receipts.getDetail(
        grId,
      ))!.lines.firstWhere((row) => row.itemId == fixture.simpleItem.id);

      await pumpAsWarehouse(tester, '/warehouse/good-receipts/$grId');

      expect(find.textContaining('Dikirim 2.5 box'), findsOneWidget);
      expect(find.textContaining('Diterima 1 box'), findsOneWidget);
      expect(
        find.byKey(GoodReceiptLineCard.discrepancyKeyFor(line.id)),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });
  });

  group('antrean selisih', () {
    testWidgets('empty state ketika belum ada selisih', (tester) async {
      await pumpAsWarehouse(tester, '/warehouse/good-receipt-discrepancies');

      expect(
        find.byKey(WarehouseGoodReceiptDiscrepancyPage.emptyKey),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('kedua jenis selisih muncul dengan badge masing-masing', (
      tester,
    ) async {
      await postedWithBoth();

      await pumpAsWarehouse(tester, '/warehouse/good-receipt-discrepancies');

      expect(
        find.byKey(
          GoodReceiptDiscrepancyBadge.keyFor(
            GoodReceiptDiscrepancyKind.shortage,
          ),
        ),
        findsWidgets,
      );
      expect(
        find.byKey(
          GoodReceiptDiscrepancyBadge.keyFor(
            GoodReceiptDiscrepancyKind.rejectedReturn,
          ),
        ),
        findsWidgets,
      );
      expect(find.textContaining('2 baris selisih'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('baris memuat nomor GR, SJ, PR, cabang, barang dan batch', (
      tester,
    ) async {
      final grId = await postedWithBoth();
      final receipt = await context.receipts.getById(grId);
      final order = await context.deliveries.getById(receipt!.doId);

      await pumpAsWarehouse(tester, '/warehouse/good-receipt-discrepancies');

      expect(find.textContaining(receipt.docNumber), findsWidgets);
      expect(find.textContaining(order!.docNumber), findsWidgets);
      expect(find.textContaining(fixture.branch.name), findsWidgets);
      expect(find.text(fixture.simpleItem.name), findsOneWidget);
      expect(
        find.textContaining('Batch ${fixture.safeBatch.batchNo}'),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('kuantitas dan alasan tampil per baris', (tester) async {
      await postedWithBoth();

      await pumpAsWarehouse(tester, '/warehouse/good-receipt-discrepancies');

      expect(find.textContaining('Dikirim 2.5 box'), findsOneWidget);
      expect(find.textContaining('Diterima 1 box'), findsOneWidget);
      expect(find.textContaining('Selisih 1.5 box'), findsOneWidget);
      expect(find.text('Rusak — kemasan pecah'), findsOneWidget);
      expect(find.textContaining('Diposting'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('filter jenis memisahkan kekurangan dan retur', (tester) async {
      await postedWithBoth();
      await pumpAsWarehouse(tester, '/warehouse/good-receipt-discrepancies');

      await tester.tap(
        find.byKey(
          ValueKey(
            'discrepancyKindFilter-'
            '${GoodReceiptDiscrepancyKind.rejectedReturn.name}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1 baris selisih'), findsOneWidget);
      expect(find.text(fixture.simpleItem.name), findsNothing);
      expect(find.text(fixture.batchItem.name), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('pencarian menyaring antrean', (tester) async {
      await postedWithBoth();
      await pumpAsWarehouse(tester, '/warehouse/good-receipt-discrepancies');

      await tester.enterText(
        find.byKey(WarehouseGoodReceiptDiscrepancyPage.searchKey),
        fixture.batchItem.name,
      );
      await tester.pumpAndSettle();

      // Two matches for the searched name: the row, and the text now sitting in the
      // search field itself.
      expect(find.text(fixture.batchItem.name), findsNWidgets(2));
      expect(find.text(fixture.simpleItem.name), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('tidak ada kontrol menambah saldo atau menyelesaikan retur', (
      tester,
    ) async {
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      await postedWithBoth();
      await pumpAsWarehouse(tester, '/warehouse/good-receipt-discrepancies');

      // Nothing here is actionable beyond navigating. A button that "resolved" a
      // discrepancy would be inventing stock nobody has counted back in.
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      for (final label in [
        'Tandai Selesai',
        'Terima Retur',
        'Kembalikan ke Warehouse',
        'Tambah Saldo',
      ]) {
        expect(find.textContaining(label), findsNothing);
      }
      expect(
        find.textContaining('belum kembali ke saldo Warehouse'),
        findsOneWidget,
      );

      // And the warehouse balance is untouched by the whole flow.
      final warehouseAfter = await context.balancesAt(fixture.warehouse.id);
      expect(
        warehouseAfter['${fixture.batchItem.id}|${fixture.safeBatch.id}'],
        (warehouseBefore['${fixture.batchItem.id}|${fixture.safeBatch.id}'] ??
                0) -
            Quantity.parse('4').milliUnits,
        reason:
            'Saldo warehouse hanya berkurang oleh pengiriman, tidak bertambah '
            'kembali oleh penolakan.',
      );
      await disposeWidget(tester);
    });
  });

  group('kartu dashboard Warehouse', () {
    testWidgets('kartu selisih muncul dan mengarah ke antrean', (tester) async {
      await postedWithBoth();
      await pumpAsWarehouse(tester, '/');

      expect(find.byKey(GoodReceiptDiscrepancyCard.cardKey), findsOneWidget);
      expect(find.textContaining('Selisih GR dari Cabang'), findsWidgets);
      expect(find.textContaining('perlu retur ke Warehouse'), findsOneWidget);

      await tester.tap(find.byKey(GoodReceiptDiscrepancyCard.cardKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(WarehouseGoodReceiptDiscrepancyPage.listKey),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('kartu tidak muncul ketika tidak ada selisih', (tester) async {
      await pumpAsWarehouse(tester, '/');

      expect(find.byKey(GoodReceiptDiscrepancyCard.cardKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('kartu pengingat cabang tidak muncul untuk Warehouse', (
      tester,
    ) async {
      final shippedAt = nowUtc.subtract(const Duration(hours: 60));
      await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: shippedAt,
        shippedAtUtc: shippedAt,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );

      await pumpAsWarehouse(tester, '/');

      expect(find.byKey(GoodReceiptReminderCard.cardKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('entry point Penerimaan Cabang tersedia untuk Warehouse', (
      tester,
    ) async {
      await pumpAsWarehouse(tester, '/');

      await tester.tap(find.byKey(const ValueKey('homeWarehouseGoodReceipts')));
      await tester.pumpAndSettle();

      expect(find.text('Penerimaan Cabang'), findsWidgets);
      await disposeWidget(tester);
    });
  });
}
