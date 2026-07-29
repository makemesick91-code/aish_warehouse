import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/inventory/domain/services/stock_posting_service.dart';
import 'package:aish_warehouse/features/inventory/presentation/providers/inventory_providers.dart';
import 'package:aish_warehouse/features/opname/presentation/pages/opname_review_detail_page.dart';
import 'package:aish_warehouse/features/opname/presentation/pages/opname_review_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_inventory_repository.dart';
import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Kepala Cabang review screens: the inbox, the detail, and the final lock.
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildOpnameFixture(context);
  });

  tearDown(() => context.dispose());

  /// A submitted document where the plain item was counted 2.5 box short.
  Future<String> submittedWithShortage() async {
    final opname = await context.createOpname().call(
      actorUserId: fixture.nurse.id,
      roomId: fixture.room.id,
    );
    final detail = await context.opnames.getDetail(opname.id);
    final line = detail!.lines.firstWhere(
      (line) => line.itemId == fixture.simpleItem.id,
    );
    await context.updateOpnameLine(
      actorUserId: fixture.nurse.id,
      lineId: line.id,
      countedQty: Quantity.parse('8'),
      note: 'Dua setengah box terpakai',
    );
    await context.submitOpname().call(
      actorUserId: fixture.nurse.id,
      opnameId: opname.id,
    );
    return opname.id;
  }

  Future<Quantity> roomBalance() => context.inventory.balanceQty(
    locationId: fixture.roomLocation.id,
    itemId: fixture.simpleItem.id,
  );

  group('daftar review', () {
    testWidgets('menampilkan empty state saat tidak ada yang menunggu', (
      tester,
    ) async {
      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const OpnameReviewListPage(),
      );

      expect(find.text('Review Stok Opname'), findsOneWidget);
      expect(
        find.textContaining('Tidak ada stok opname yang menunggu review'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('menampilkan dokumen submitted dengan ringkasan selisih', (
      tester,
    ) async {
      final id = await submittedWithShortage();
      final opname = await context.opnames.getById(id);

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const OpnameReviewListPage(),
      );

      expect(find.text(opname!.docNumber), findsOneWidget);
      expect(find.textContaining('Ruang Dental 1'), findsOneWidget);
      expect(find.textContaining('Perawat Uji'), findsOneWidget);
      expect(find.text('3 baris'), findsOneWidget);
      expect(find.text('1 berselisih'), findsOneWidget);
      expect(find.text('Menunggu Review'), findsOneWidget);
      // Grouped by ISO period.
      expect(
        find.textContaining('Periode ${opname.periodLabel}'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('perawat tidak melihat daftar review', (tester) async {
      await submittedWithShortage();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const OpnameReviewListPage(),
      );

      expect(
        find.textContaining(
          'Hanya Kepala Cabang yang dapat mereview stok opname',
        ),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });
  });

  group('detail review', () {
    testWidgets('menampilkan selisih, catatan dan ringkasan per satuan', (
      tester,
    ) async {
      final id = await submittedWithShortage();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      expect(find.text('Ringkasan'), findsOneWidget);
      expect(find.text('Jumlah barang'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Baris berselisih'), findsOneWidget);
      expect(find.text('Total kekurangan'), findsOneWidget);
      // Reported per unit, never summed across units.
      expect(find.text('2.5 box'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('detail bersifat read-only', (tester) async {
      final id = await submittedWithShortage();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      expect(find.text('Simpan baris'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Review & Kunci'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('menampilkan dialog konfirmasi sebelum mengunci', (
      tester,
    ) async {
      final id = await submittedWithShortage();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Review & Kunci'));
      await tester.pumpAndSettle();

      expect(find.text('Review & Kunci?'), findsOneWidget);
      expect(
        find.textContaining('final dan tidak dapat dibatalkan'),
        findsOneWidget,
      );

      // Cancelling must change nothing at all.
      await tester.tap(find.widgetWithText(TextButton, 'Batal'));
      await tester.pumpAndSettle();

      expect((await context.opnames.getById(id))!.isSubmitted, isTrue);
      expect(await roomBalance(), Quantity.parse('10.5'));

      await disposeWidget(tester);
    });

    testWidgets('review berhasil mengunci dokumen dan menyesuaikan saldo', (
      tester,
    ) async {
      final id = await submittedWithShortage();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Review & Kunci'));
      await tester.pumpAndSettle();
      // The dialog's confirm button carries the same label as the one that
      // opened it, so the tap has to be scoped to the dialog.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Review & Kunci'),
        ),
      );
      await tester.pumpAndSettle();

      final opname = await context.opnames.getById(id);
      expect(opname!.isReviewed, isTrue);
      expect(opname.reviewedBy, fixture.branchHead.id);
      expect(await roomBalance(), Quantity.parse('8'));

      // The screen re-renders as a locked document.
      expect(find.text('Selesai Direview'), findsOneWidget);
      expect(find.textContaining('Sudah direview'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Review & Kunci'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('kegagalan posting mempertahankan status submitted', (
      tester,
    ) async {
      final id = await submittedWithShortage();

      // A posting service that refuses the movement for the counted item.
      final posting = StockPostingService(
        inventory: FailingInventoryRepository(
          context.inventory,
          failOnItemId: fixture.simpleItem.id,
        ),
        master: context.master,
      );

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
        overrides: [stockPostingServiceProvider.overrideWithValue(posting)],
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Review & Kunci'));
      await tester.pumpAndSettle();
      // The dialog's confirm button carries the same label as the one that
      // opened it, so the tap has to be scoped to the dialog.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Review & Kunci'),
        ),
      );
      await tester.pumpAndSettle();

      // The error is reported in Indonesian, not as a stack trace.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Kegagalan buatan'), findsOneWidget);

      final opname = await context.opnames.getById(id);
      expect(opname!.status, StockOpnameStatus.submitted);
      expect(opname.reviewedAt, isNull);
      expect(opname.reviewedBy, isNull);
      // No stock moved.
      expect(await roomBalance(), Quantity.parse('10.5'));
      expect(
        await context.inventory.movementsByRef(
          refDocType: RefDocType.stockOpname,
          refDocId: id,
        ),
        isEmpty,
      );
      // The action stays available for a retry.
      expect(
        find.widgetWithText(FilledButton, 'Review & Kunci'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('tombol review nonaktif selama proses berjalan', (
      tester,
    ) async {
      final id = await submittedWithShortage();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Review & Kunci'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Review & Kunci'),
        ),
      );
      // One frame in: the guard must already hold, so a second tap cannot
      // start a second posting against the same document.
      await tester.pump();

      final busy = find.widgetWithText(FilledButton, 'Memproses…');
      if (busy.evaluate().isNotEmpty) {
        expect(tester.widget<FilledButton>(busy).onPressed, isNull);
      }

      await tester.pumpAndSettle();

      // Whatever the frame timing, the ledger was adjusted exactly once.
      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.stockOpname,
        refDocId: id,
      );
      expect(movements, hasLength(1));
      expect(await roomBalance(), Quantity.parse('8'));

      await disposeWidget(tester);
    });

    testWidgets('dokumen yang sudah direview tampil final', (tester) async {
      final id = await submittedWithShortage();
      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: id,
      );

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      expect(find.text('Selesai Direview'), findsOneWidget);
      expect(find.textContaining('Sudah direview'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Review & Kunci'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('perawat tidak melihat aksi review pada detail', (
      tester,
    ) async {
      final id = await submittedWithShortage();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      expect(find.widgetWithText(FilledButton, 'Review & Kunci'), findsNothing);
      expect(
        find.text('Anda tidak dapat mereview dokumen ini.'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('kepala cabang lain tidak melihat aksi review', (tester) async {
      final id = await submittedWithShortage();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      expect(find.widgetWithText(FilledButton, 'Review & Kunci'), findsNothing);

      await disposeWidget(tester);
    });
  });
}
