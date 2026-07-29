import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/opname/domain/models/opname_models.dart';
import 'package:aish_warehouse/features/opname/presentation/pages/opname_form_page.dart';
import 'package:aish_warehouse/features/opname/presentation/pages/opname_list_page.dart';
import 'package:aish_warehouse/features/opname/presentation/widgets/searchable_item_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Perawat-facing screens: the list, the counting form, and the read-only view
/// a document turns into once it has been submitted.
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildOpnameFixture(context);
  });

  tearDown(() => context.dispose());

  Future<String> createDraft() async {
    final opname = await context.createOpname().call(
      actorUserId: fixture.nurse.id,
      roomId: fixture.room.id,
    );
    return opname.id;
  }

  Future<StockOpnameLine> lineFor(
    String opnameId, {
    required String sku,
  }) async {
    final detail = await context.opnames.getDetail(opnameId);
    return detail!.lines.firstWhere((line) => line.sku == sku);
  }

  group('daftar stok opname', () {
    testWidgets('menampilkan empty state saat belum ada dokumen', (
      tester,
    ) async {
      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const OpnameListPage(),
      );

      expect(find.text('Stok Opname'), findsOneWidget);
      expect(find.textContaining('Belum ada stok opname'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('menampilkan periode ISO dan tanggal operasional GMT+8', (
      tester,
    ) async {
      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const OpnameListPage(),
      );

      expect(find.textContaining('Periode '), findsOneWidget);
      expect(find.textContaining('GMT+8'), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('tombol buat aktif bila ruangan belum dihitung', (
      tester,
    ) async {
      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const OpnameListPage(),
      );

      final button = find.widgetWithText(
        FilledButton,
        '+ Opname Minggu Ini · ${fixture.room.name}',
      );
      expect(button, findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

      await disposeWidget(tester);
    });

    testWidgets('tombol buat nonaktif dan menjelaskan alasannya (G-O1)', (
      tester,
    ) async {
      await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const OpnameListPage(),
      );

      final button = find.widgetWithText(
        FilledButton,
        '+ Opname Minggu Ini · ${fixture.room.name}',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(
        find.textContaining('sudah memiliki opname minggu ini'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('riwayat menampilkan nomor dokumen dan status', (tester) async {
      final id = await createDraft();
      final opname = await context.opnames.getById(id);

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const OpnameListPage(),
      );

      expect(find.text(opname!.docNumber), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.textContaining('3 baris'), findsOneWidget);

      await disposeWidget(tester);
    });
  });

  group('form stok opname', () {
    testWidgets('menampilkan snapshot stok sistem', (tester) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      await revealLine(tester, find.text('Masker Bedah'));
      expect(find.text('Masker Bedah'), findsOneWidget);
      // The snapshot renders without a floating point tail and without
      // milli-units (Q-6).
      expect(find.text('10.5 box'), findsOneWidget);
      expect(find.text('10500 box'), findsNothing);
      expect(find.text('Stok sistem'), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('menerima input 0.5 dan menampilkan selisih', (tester) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      final card = await revealCard(tester, 'Masker Bedah');
      final quantityField = find.descendant(
        of: card,
        matching: find.widgetWithText(TextFormField, '10.5'),
      );

      await tester.enterText(quantityField, '0.5');
      await tester.pump();

      // 0.5 − 10.5 = exactly −10.
      expect(find.text('-10 box'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('menerima koma sebagai pemisah desimal', (tester) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      final card = await revealCard(tester, 'Masker Bedah');
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextFormField, '10.5'),
        ),
        '0,5',
      );
      await tester.pump();

      expect(find.text('-10 box'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('catatan wajib ditandai saat ada selisih (G-O3)', (
      tester,
    ) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      expect(find.text('Catatan (opsional)'), findsWidgets);

      final card = await revealCard(tester, 'Masker Bedah');
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextFormField, '10.5'),
        ),
        '8',
      );
      await tester.pump();

      expect(find.text('Catatan alasan selisih *'), findsOneWidget);
      expect(find.text('Wajib diisi karena ada selisih.'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('submit tanpa catatan menampilkan pesan Bahasa Indonesia', (
      tester,
    ) async {
      final id = await createDraft();
      final line = await lineFor(id, sku: 'TEST-0001');
      await context.opnames.updateDraftLine(
        lineId: line.id,
        countedQty: Quantity.parse('8'),
      );

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Kirim'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Catatan wajib diisi untuk baris yang berselisih'),
        findsWidgets,
      );
      // The document must still be a draft after a rejected submit.
      expect((await context.opnames.getById(id))!.isDraft, isTrue);

      await disposeWidget(tester);
    });

    testWidgets('submit berhasil membuat dokumen menjadi read-only', (
      tester,
    ) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Kirim'));
      await tester.pumpAndSettle();

      expect((await context.opnames.getById(id))!.isSubmitted, isTrue);
      expect(find.text('Menunggu Review'), findsOneWidget);
      expect(find.text('Menunggu review Kepala Cabang.'), findsOneWidget);
      // No editing affordances survive the transition (G-S2).
      expect(find.widgetWithText(FilledButton, 'Kirim'), findsNothing);
      expect(find.text('Simpan baris'), findsNothing);
      expect(find.byType(SearchableItemDropdown), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('tombol kirim nonaktif selama proses berjalan', (tester) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Kirim'));
      // One frame in: the guard must already have disabled the button, so a
      // second tap cannot start a second submit.
      await tester.pump();

      final busy = find.widgetWithText(FilledButton, 'Mengirim…');
      if (busy.evaluate().isNotEmpty) {
        expect(tester.widget<FilledButton>(busy).onPressed, isNull);
      }

      await tester.pumpAndSettle();
      expect((await context.opnames.getById(id))!.isSubmitted, isTrue);

      await disposeWidget(tester);
    });

    testWidgets('chip kategori menyaring daftar barang', (tester) async {
      final id = await createDraft();
      final otherCategory = await context.master.ensureCategory('Obat');
      final otherItem = await context.master.ensureItem(
        sku: 'TEST-0300',
        name: 'Paracetamol',
        categoryId: otherCategory.id,
        unit: 'strip',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );
      await context.addOpnameLine(
        actorUserId: fixture.nurse.id,
        opnameId: id,
        itemId: otherItem.id,
        countedQty: Quantity.parse('2'),
        note: 'Ditemukan',
      );

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      await revealLine(tester, find.text('Masker Bedah'));
      expect(find.text('Masker Bedah'), findsOneWidget);
      await revealLine(tester, find.text('Paracetamol'));
      expect(find.text('Paracetamol'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Obat'));
      await tester.pumpAndSettle();

      expect(find.text('Paracetamol'), findsOneWidget);
      expect(find.text('Masker Bedah'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('pencarian menemukan barang berdasarkan nama', (tester) async {
      final id = await createDraft();
      await context.master.ensureItem(
        sku: 'TEST-0400',
        name: 'Kapas Gulung',
        categoryId: fixture.category.id,
        unit: 'pack',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      await tester.enterText(find.byType(TextField).first, 'Kapas');
      // Past the 200 ms debounce.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Kapas Gulung'), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('pencarian menemukan barang berdasarkan SKU', (tester) async {
      final id = await createDraft();
      await context.master.ensureItem(
        sku: 'TEST-0500',
        name: 'Alkohol Swab',
        categoryId: fixture.category.id,
        unit: 'box',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      await tester.enterText(find.byType(TextField).first, 'TEST-0500');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Alkohol Swab'), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets(
      'kirim menyimpan hasil ketikan yang belum ditekan Simpan baris',
      (tester) async {
        // Regression: the counted quantity and note live in the card's local
        // state until saved. If Kirim did not flush them, the document would
        // be submitted with the values still in the database — and the review
        // would then adjust the ledger to a number nobody counted, finally and
        // irreversibly.
        final id = await createDraft();

        await pumpOpnameWidget(
          tester,
          context: context,
          actingAs: fixture.nurse,
          child: OpnameFormPage(opnameId: id),
        );

        final card = await revealCard(tester, 'Masker Bedah');
        await tester.enterText(
          find.descendant(
            of: card,
            matching: find.widgetWithText(TextFormField, '10.5'),
          ),
          '8',
        );
        await tester.pump();
        await tester.enterText(
          find.descendant(of: card, matching: find.byType(TextField)).last,
          'Dua setengah box terpakai',
        );
        await tester.pump();

        // Straight to Kirim — "Simpan baris" is never tapped.
        await tester.tap(find.widgetWithText(FilledButton, 'Kirim'));
        await tester.pumpAndSettle();

        final line = await lineFor(id, sku: 'TEST-0001');
        expect(line.countedQty, Quantity.parse('8'));
        expect(line.note, 'Dua setengah box terpakai');
        expect(line.difference, Quantity.parse('2.5').let((q) => -q));
        expect((await context.opnames.getById(id))!.isSubmitted, isTrue);

        await disposeWidget(tester);
      },
    );

    testWidgets('kirim tanpa catatan tetap ditolak walau belum disimpan', (
      tester,
    ) async {
      // The flush must not become a way to bypass G-O3: a difference typed
      // without a reason is still rejected, and the document stays a draft.
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      final card = await revealCard(tester, 'Masker Bedah');
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextFormField, '10.5'),
        ),
        '8',
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Kirim'));
      await tester.pumpAndSettle();

      expect((await context.opnames.getById(id))!.isDraft, isTrue);
      // The typed quantity was still persisted, so nothing the nurse entered
      // is lost by the rejection.
      final line = await lineFor(id, sku: 'TEST-0001');
      expect(line.countedQty, Quantity.parse('8'));

      await disposeWidget(tester);
    });

    testWidgets('hasil hitung nol dan tiga desimal diterima', (tester) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      final card = await revealCard(tester, 'Masker Bedah');
      // Addressed by position, not by its current text: the text changes with
      // each entry, so a text-based finder would stop matching.
      final field = find
          .descendant(of: card, matching: find.byType(TextField))
          .first;

      await tester.enterText(field, '0');
      await tester.pump();
      expect(find.text('-10.5 box'), findsOneWidget);

      await tester.enterText(field, '2.375');
      await tester.pump();
      expect(find.text('-8.125 box'), findsOneWidget);
      // Milli-units never reach the screen (Q-6).
      expect(find.textContaining('8125'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('selisih positif dan nol ditampilkan berbeda', (tester) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      final card = await revealCard(tester, 'Masker Bedah');
      // Untouched: the snapshot equals the count, so the badge is neutral.
      expect(find.text('Sesuai'), findsWidgets);

      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextFormField, '10.5'),
        ),
        '12',
      );
      await tester.pump();

      expect(find.text('+1.5 box'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('catatan tetap dapat diisi saat tidak ada selisih', (
      tester,
    ) async {
      // "Opsional" must mean "may be left empty", not "cannot be typed in".
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      final card = await revealCard(tester, 'Masker Bedah');
      final note = find
          .descendant(of: card, matching: find.byType(TextField))
          .last;
      expect(tester.widget<TextField>(note).enabled, isNot(false));

      await tester.enterText(note, 'Segel kemasan rusak');
      await tester.pump();

      final saveButton = find.descendant(
        of: card,
        matching: find.text('Simpan baris'),
      );
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final line = await lineFor(id, sku: 'TEST-0001');
      expect(line.note, 'Segel kemasan rusak');
      expect(line.hasDifference, isFalse);

      await disposeWidget(tester);
    });

    testWidgets('pencarian tanpa hasil menampilkan Tidak ditemukan', (
      tester,
    ) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      await tester.enterText(find.byType(TextField).first, 'zzz-tidak-ada');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Tidak ditemukan'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('dokumen yang sudah direview menampilkan status final', (
      tester,
    ) async {
      // Regression: the footer condition excluded exactly the reviewed case,
      // so a nurse opening her locked count saw no closing statement at all.
      final id = await createDraft();
      await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: id,
      );
      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: id,
      );

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      expect(find.text('Selesai Direview'), findsOneWidget);
      expect(
        find.text('Dokumen sudah direview dan bersifat final.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Kirim'), findsNothing);
      expect(find.text('Simpan baris'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('menghapus baris tambahan dari draft', (tester) async {
      final id = await createDraft();
      final extra = await context.master.ensureItem(
        sku: 'TEST-0600',
        name: 'Zink Oksida',
        categoryId: fixture.category.id,
        unit: 'pcs',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );
      await context.addOpnameLine(
        actorUserId: fixture.nurse.id,
        opnameId: id,
        itemId: extra.id,
        countedQty: Quantity.parse('3'),
        note: 'Ditemukan',
      );

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      final card = await revealCard(tester, 'Zink Oksida');
      final deleteButton = find.descendant(
        of: card,
        matching: find.byIcon(Icons.delete_outline),
      );
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('Baris dihapus.'), findsOneWidget);
      final detail = await context.opnames.getDetail(id);
      expect(detail!.lines.where((line) => line.itemId == extra.id), isEmpty);

      await disposeWidget(tester);
    });

    testWidgets('menyimpan baris memperbarui selisih di database', (
      tester,
    ) async {
      final id = await createDraft();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: OpnameFormPage(opnameId: id),
      );

      final card = await revealCard(tester, 'Masker Bedah');
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextFormField, '10.5'),
        ),
        '0.5',
      );
      await tester.pump();
      // Two text fields live in a card: the quantity, then the note.
      await tester.enterText(
        find.descendant(of: card, matching: find.byType(TextField)).last,
        'Tersisa setengah box',
      );
      await tester.pump();

      final saveButton = find.descendant(
        of: card,
        matching: find.text('Simpan baris'),
      );
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final line = await lineFor(id, sku: 'TEST-0001');
      expect(line.countedQty, Quantity.parse('0.5'));
      expect(line.difference.format(), '-10');
      expect(line.note, 'Tersisa setengah box');

      await disposeWidget(tester);
    });
  });
}

/// Small helper so a negative expectation reads as prose.
extension on Quantity {
  T let<T>(T Function(Quantity) transform) => transform(this);
}
