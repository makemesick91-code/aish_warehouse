import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/widgets/historical_master_badge.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/pages/purchase_request_detail_page.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/pages/purchase_request_form_page.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/pages/purchase_request_list_page.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/pages/purchase_request_wizard_page.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/providers/purchase_request_providers.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/widgets/eligible_opname_tile.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/widgets/purchase_request_line_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The Kepala Cabang screens: list, wizard, draft editor, read-only detail.
///
/// Everything is pumped against the same in-memory database the domain tests use, so a
/// widget assertion is about what the real stack renders rather than about a stub.
///
/// The most valuable test in this file is the flush one. A branch head who types a
/// quantity and taps *Kirim ke Warehouse* without first tapping *Simpan baris* must
/// send the number they are looking at — not the one still sitting in the database.
/// That was a real bug in the Stok Opname form, and it is the reason every line card
/// reports its keystrokes upward.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  final clockOverride = purchaseRequestClockProvider.overrideWithValue(
    prWednesdayUtc,
  );

  Future<PurchaseRequestFixture> fixtureWithCounts({
    bool secondRoom = false,
    bool previousWeek = false,
    bool tooOld = false,
  }) async {
    final fixture = await buildPurchaseRequestFixture(
      context,
      now: prWednesdayUtc(),
    );
    await fileOpnameForRoom(
      context,
      roomId: fixture.roomOne.id,
      nurseId: fixture.nurse.id,
      utcNow: prWednesdayUtc(),
    );
    if (secondRoom) {
      await fileOpnameForRoom(
        context,
        roomId: fixture.roomTwo.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
    }
    if (previousWeek) {
      await fileOpnameForRoom(
        context,
        roomId: fixture.roomThree.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(1),
      );
    }
    if (tooOld) {
      await fileOpnameForRoom(
        context,
        roomId: fixture.roomTwo.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(3),
      );
    }
    return fixture;
  }

  /// Scrolls the line whose quantity field is [lineId] into view and returns its card.
  ///
  /// The form is a lazy `ListView`, so a card below the fold has not been built and a
  /// finder for it matches nothing. Addressing the field *inside its own card* also
  /// keeps a two-line document from having its second card's button tapped by accident.
  Future<Finder> revealLineCard(WidgetTester tester, String lineId) async {
    final field = find.byKey(ValueKey('prRequestedQty-$lineId'));
    await revealInList(
      tester,
      field,
      listKey: PurchaseRequestFormPage.lineListKey,
    );
    return find.ancestor(of: field, matching: find.byType(Card)).first;
  }

  Future<String> draftFor(
    PurchaseRequestFixture fixture, {
    List<String>? opnameIds,
  }) async {
    final eligible = await context.eligibleOpnamesFor(
      branchId: fixture.branch.id,
      utcNow: prWednesdayUtc(),
    );
    final request = await context
        .createPurchaseRequest(clock: prWednesdayUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          selectedOpnameIds: opnameIds ?? [eligible.first.opnameId],
        );
    return request.id;
  }

  group('daftar', () {
    testWidgets('empty state ditampilkan saat belum ada PR', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const PurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      expect(find.byKey(purchaseRequestEmptyStateKey), findsOneWidget);
      expect(find.text('Purchase Request'), findsWidgets);
      expect(
        find.text('Buat Purchase Request'),
        findsOneWidget,
        reason: 'Tombol buat harus tersedia dari empty state.',
      );

      await disposeWidget(tester);
    });

    testWidgets('riwayat menampilkan nomor, status dan jumlah barang', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      final request = (await context.requests.getById(prId))!;
      final lineCount = await context.purchaseRequestLineCount(prId);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const PurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      expect(find.text(request.docNumber), findsOneWidget);
      expect(find.text('Draft'), findsWidgets);
      expect(find.text('$lineCount barang'), findsOneWidget);
      expect(find.text('1 opname acuan'), findsOneWidget);
      // Offline work is normal, so the sync marker is informational.
      expect(find.text('Menunggu sinkron'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('PR aktif ditandai pada daftar (G-P4)', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: fixture.branchHead.id, prId: prId);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const PurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      expect(find.byKey(activePurchaseRequestNoticeKey), findsOneWidget);
      expect(find.textContaining('Ada permintaan aktif'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('peran tanpa cabang melihat daftar kosong', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      await draftFor(fixture);

      // The warehouse has no branch, so the branch-scoped list must emit nothing
      // rather than everything.
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        child: const PurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      expect(find.byKey(purchaseRequestEmptyStateKey), findsOneWidget);

      await disposeWidget(tester);
    });
  });

  group('wizard pilih opname', () {
    testWidgets('hanya opname eligible ditawarkan', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts(previousWeek: true, tooOld: true);
      final eligible = await context.eligibleOpnamesFor(
        branchId: fixture.branch.id,
        utcNow: prWednesdayUtc(),
      );
      final all = await context.database
          .customSelect('SELECT id FROM stock_opnames;')
          .get();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const PurchaseRequestWizardPage(),
        overrides: [clockOverride],
      );

      expect(eligible, hasLength(2));
      expect(all, hasLength(3), reason: 'Satu di antaranya terlalu tua.');

      for (final reference in eligible) {
        expect(
          find.byKey(EligibleOpnameTile.keyFor(reference.opnameId)),
          findsOneWidget,
        );
      }
      final ineligible = all
          .map((row) => row.read<String>('id'))
          .where(
            (id) => !eligible.any((reference) => reference.opnameId == id),
          );
      for (final id in ineligible) {
        expect(
          find.byKey(EligibleOpnameTile.keyFor(id)),
          findsNothing,
          reason: 'Opname di luar jendela G-P1 tidak boleh ditawarkan.',
        );
      }

      await disposeWidget(tester);
    });

    testWidgets('lanjut tanpa memilih opname ditolak di tempat', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const PurchaseRequestWizardPage(),
        overrides: [clockOverride],
      );

      await tester.tap(find.byKey(PurchaseRequestWizardPage.continueButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('opnameSelectionRequired')),
        findsOneWidget,
      );
      // Nothing was created.
      final rows = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM purchase_requests;')
          .getSingle();
      expect(rows.read<int>('c'), 0);

      await disposeWidget(tester);
    });

    testWidgets('memilih opname membuat draft lalu membuka editor', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final eligible = await context.eligibleOpnamesFor(
        branchId: fixture.branch.id,
        utcNow: prWednesdayUtc(),
      );

      // The real router, because the wizard replaces itself with the editor on
      // success and that navigation is part of what is being tested.
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/purchase-requests/new',
        overrides: [clockOverride],
      );

      await tester.tap(
        find.byKey(EligibleOpnameTile.keyFor(eligible.single.opnameId)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PurchaseRequestWizardPage.continueButtonKey));
      await tester.pumpAndSettle();

      final rows = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM purchase_requests;')
          .getSingle();
      expect(rows.read<int>('c'), 1);
      // Step 2 is now on screen.
      expect(find.text('Tinjau & Sesuaikan Permintaan'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('empty state saat tidak ada opname eligible', (tester) async {
      useTabletSurface(tester);
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      // Only a count that is too old exists.
      await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(3),
      );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const PurchaseRequestWizardPage(),
        overrides: [clockOverride],
      );

      expect(
        find.byKey(const ValueKey('eligibleOpnameEmptyState')),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });
  });

  group('editor draft', () {
    testWidgets('baris saran ditampilkan dengan rincian par level', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts(secondRoom: true);
      final eligible = await context.eligibleOpnamesFor(
        branchId: fixture.branch.id,
        utcNow: prWednesdayUtc(),
      );
      final prId = await draftFor(
        fixture,
        opnameIds: eligible
            .map((reference) => reference.opnameId)
            .toList(growable: false),
      );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestFormPage(prId: prId),
        overrides: [clockOverride],
      );

      final line = (await context.requests.getDetail(
        prId,
      ))!.lines.firstWhere((line) => line.itemId == fixture.simpleItem.id);
      final card = await revealLineCard(tester, line.id);

      // The multi-room aggregate: 2.5 + 4 = 6.5 box, shown in units and never in
      // milli-units (Q-6).
      expect(
        find.descendant(of: card, matching: find.text(fixture.simpleItem.name)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('6.5 box')),
        findsWidgets,
      );
      expect(find.textContaining('6500'), findsNothing);
      // The working behind the number.
      expect(
        find.descendant(of: card, matching: find.text('Par level per ruangan')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Ruangan sumber')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(fixture.roomOne.name),
        ),
        findsWidgets,
        reason: 'Ruangan sumber saran harus terlihat.',
      );

      await disposeWidget(tester);
    });

    testWidgets('input desimal 0.5 diterima', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      final line = (await context.requests.getDetail(
        prId,
      ))!.lines.firstWhere((line) => line.itemId == fixture.simpleItem.id);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestFormPage(prId: prId),
        overrides: [clockOverride],
      );

      final card = await revealLineCard(tester, line.id);
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.byKey(ValueKey('prRequestedQty-${line.id}')),
        ),
        '0.5',
      );
      await tester.pumpAndSettle();

      // `tap` dispatches at the widget's centre whether or not that point is inside
      // the viewport, so a button below the fold would send the gesture to whatever
      // happens to be there instead. `ensureVisible` is what makes the tap land.
      final save = find.descendant(
        of: card,
        matching: find.text('Simpan baris'),
      );
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
        (await context.requests.lineById(line.id))!.requestedQty,
        Quantity.parse('0.5'),
      );

      await disposeWidget(tester);
    });

    testWidgets('peringatan 150% muncul saat jumlah dinaikkan', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      final line = (await context.requests.getDetail(
        prId,
      ))!.lines.firstWhere((line) => line.itemId == fixture.simpleItem.id);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestFormPage(prId: prId),
        overrides: [clockOverride],
      );

      final card = await revealLineCard(tester, line.id);
      final field = find.descendant(
        of: card,
        matching: find.byKey(ValueKey('prRequestedQty-${line.id}')),
      );
      final warning = find.descendant(
        of: card,
        matching: find.byKey(purchaseRequestThresholdWarningKey),
      );
      expect(warning, findsNothing);

      // Suggested 2.5, so 3.75 is exactly 150 % — still no warning.
      await tester.enterText(field, '3.75');
      await tester.pumpAndSettle();
      expect(
        warning,
        findsNothing,
        reason: 'Aturan berbunyi > 150%, jadi tepat 150% tidak memperingatkan.',
      );

      // One milli-unit more, and it does.
      await tester.enterText(field, '3.751');
      await tester.pumpAndSettle();
      expect(warning, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('lebih dari 150% saran sistem'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('Catatan alasan (wajib)'),
        ),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('submit ditolak selama baris di atas 150% tanpa catatan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      final line = (await context.requests.getDetail(
        prId,
      ))!.lines.firstWhere((line) => line.itemId == fixture.simpleItem.id);

      // The real router, because the second, successful submit navigates away.
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/purchase-requests/$prId/edit',
        overrides: [clockOverride],
      );

      final card = await revealLineCard(tester, line.id);
      final field = find.descendant(
        of: card,
        matching: find.byKey(ValueKey('prRequestedQty-${line.id}')),
      );

      // 20 against a suggestion of 2.5 is far above the threshold, so the warning
      // and the mandatory-note label appear the moment it is typed.
      await tester.enterText(field, '20');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(purchaseRequestThresholdWarningKey),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(PurchaseRequestFormPage.submitButtonKey));
      await tester.pumpAndSettle();

      // Refused — and refused by the *flush*, because saving a single line enforces
      // G-P3 on its own. Either way nothing is sent, and the message is a sentence
      // rather than a stack trace.
      expect(await context.purchaseRequestStatusOf(prId), 'draft');
      expect(find.textContaining('Catatan alasan wajib diisi'), findsWidgets);

      // Let the snack bar go before touching the form again: `enterText` focuses the
      // field by tapping it, and a tap can be swallowed by the overlay sitting on top.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // With a reason, the same document goes through.
      final note = find.descendant(
        of: card,
        matching: find.byKey(ValueKey('prNote-${line.id}')),
      );
      await tester.ensureVisible(note);
      await tester.pumpAndSettle();
      await tester.enterText(note, 'Kegiatan bakti sosial');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PurchaseRequestFormPage.submitButtonKey));
      await tester.pumpAndSettle();

      expect(await context.purchaseRequestStatusOf(prId), 'submitted');
      final saved = await context.requests.lineById(line.id);
      expect(saved!.requestedQty, Quantity.parse('20'));
      expect(saved.note, 'Kegiatan bakti sosial');

      await disposeWidget(tester);
    });

    testWidgets('input yang belum disimpan di-flush sebelum submit', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      final detail = (await context.requests.getDetail(prId))!;
      final line = detail.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );

      // The real router, because a successful submit navigates to the detail screen.
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/purchase-requests/$prId/edit',
        overrides: [clockOverride],
      );

      // Type a quantity and go straight for the submit button — no "Simpan baris".
      final card = await revealLineCard(tester, line.id);
      await tester.enterText(
        find.descendant(
          of: card,
          matching: find.byKey(ValueKey('prRequestedQty-${line.id}')),
        ),
        '3',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PurchaseRequestFormPage.submitButtonKey));
      await tester.pumpAndSettle();

      expect(await context.purchaseRequestStatusOf(prId), 'submitted');
      expect(
        (await context.requests.lineById(line.id))!.requestedQty,
        Quantity.parse('3'),
        reason:
            'Tanpa flush, dokumen yang terkirim akan memuat angka lama — '
            'jumlah yang tidak pernah diminta siapa pun.',
      );

      await disposeWidget(tester);
    });

    testWidgets('menghapus baris mengurangi daftar', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      final before = await context.purchaseRequestLineCount(prId);
      final line = (await context.requests.getDetail(
        prId,
      ))!.lines.firstWhere((line) => line.itemId == fixture.simpleItem.id);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestFormPage(prId: prId),
        overrides: [clockOverride],
      );

      final card = await revealLineCard(tester, line.id);
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('Hapus baris')),
      );
      await tester.pumpAndSettle();

      expect(await context.purchaseRequestLineCount(prId), before - 1);

      await disposeWidget(tester);
    });

    testWidgets('menambah barang manual menuntut jumlah dan catatan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      final before = await context.purchaseRequestLineCount(prId);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestFormPage(prId: prId),
        overrides: [clockOverride],
      );

      // Type into the item picker and wait past its debounce.
      await tester.enterText(
        find.widgetWithText(TextField, 'Tambah barang (nama atau SKU)'),
        fixture.unstockedItem.name,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ValueKey('prItemOption-${fixture.unstockedItem.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('prAddManualLineDialog')),
        findsOneWidget,
      );

      // The confirm button stays disabled until both a quantity and a reason exist.
      final confirm = find.byKey(const ValueKey('prManualConfirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('prManualQty')), '2');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(confirm).onPressed,
        isNull,
        reason: 'Permintaan manual wajib catatan (G-P3).',
      );

      await tester.enterText(
        find.byKey(const ValueKey('prManualNote')),
        'Persediaan baru',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(await context.purchaseRequestLineCount(prId), before + 1);
      final added = await context.requests.findLineByItem(
        prId: prId,
        itemId: fixture.unstockedItem.id,
      );
      expect(added!.isManualRequest, isTrue);
      expect(added.note, 'Persediaan baru');

      await disposeWidget(tester);
    });

    testWidgets('badge permintaan manual tampil pada baris tanpa saran', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      await context.addPurchaseRequestLine.call(
        actorUserId: fixture.branchHead.id,
        prId: prId,
        itemId: fixture.unstockedItem.id,
        requestedQty: Quantity.parse('2'),
        note: 'Persediaan baru',
      );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestFormPage(prId: prId),
        overrides: [clockOverride],
      );

      expect(find.text('Permintaan manual'), findsOneWidget);
      expect(
        find.textContaining('Permintaan manual tanpa saran stok opname'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });
  });

  group('detail read-only', () {
    testWidgets('PR submitted tidak memiliki kontrol edit', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: fixture.branchHead.id, prId: prId);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestDetailPage(prId: prId),
        overrides: [clockOverride],
      );

      // No inputs at all: the line cards are built with `editable: false`, so there is
      // nothing to disable.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Simpan baris'), findsNothing);
      expect(find.byTooltip('Hapus baris'), findsNothing);
      expect(find.byKey(PurchaseRequestDetailPage.editButtonKey), findsNothing);

      // What it does show is the status and where the ball is.
      expect(find.text('Menunggu Diproses'), findsWidgets);
      expect(find.text('Menunggu diproses Warehouse.'), findsOneWidget);
      // Cancellation is still open before the warehouse starts (G-S3).
      expect(
        find.byKey(PurchaseRequestDetailPage.cancelButtonKey),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('draft menawarkan lanjutkan dan batalkan', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestDetailPage(prId: prId),
        overrides: [clockOverride],
      );

      expect(
        find.byKey(PurchaseRequestDetailPage.editButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(PurchaseRequestDetailPage.cancelButtonKey),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('dialog pembatalan menuntut alasan', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestDetailPage(prId: prId),
        overrides: [clockOverride],
      );

      await tester.tap(find.byKey(PurchaseRequestDetailPage.cancelButtonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('prCancelDialog')), findsOneWidget);

      final confirm = find.byKey(const ValueKey('prCancelConfirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      // Whitespace is not a reason.
      await tester.enterText(
        find.byKey(const ValueKey('prCancelReason')),
        '   ',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('prCancelReason')),
        'Sudah tersedia di cabang',
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(await context.purchaseRequestStatusOf(prId), 'cancelled');
      expect(
        (await context.requests.getById(prId))!.cancelReason,
        'Sudah tersedia di cabang',
      );

      await disposeWidget(tester);
    });

    testWidgets('PR processing tidak menawarkan pembatalan', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: fixture.branchHead.id, prId: prId);
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: fixture.warehouseUser.id, prId: prId);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestDetailPage(prId: prId),
        overrides: [clockOverride],
      );

      expect(
        find.byKey(PurchaseRequestDetailPage.cancelButtonKey),
        findsNothing,
        reason: 'G-S3: pembatalan tertutup begitu Warehouse mulai bekerja.',
      );
      expect(find.text('Sedang Diproses'), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('PR ditolak menampilkan alasan penolakan', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: fixture.branchHead.id, prId: prId);
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: fixture.warehouseUser.id, prId: prId);
      await context
          .rejectPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            prId: prId,
            reason: 'Stok warehouse habis',
          );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestDetailPage(prId: prId),
        overrides: [clockOverride],
      );

      expect(find.text('Ditolak'), findsWidgets);
      expect(find.text('Stok warehouse habis'), findsOneWidget);
      expect(find.text('Ditolak Warehouse'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('PR dibatalkan menampilkan pelaku, waktu dan alasan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      await context
          .cancelPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            prId: prId,
            reason: 'Salah pilih acuan',
          );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestDetailPage(prId: prId),
        overrides: [clockOverride],
      );

      expect(find.text('Dibatalkan'), findsWidgets);
      expect(find.text('Salah pilih acuan'), findsOneWidget);
      // Actor and the instant, in GMT+8 with the zone spelled out (T-2).
      expect(find.textContaining(fixture.branchHead.fullName), findsWidgets);
      expect(find.textContaining('GMT+8'), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('badge historis tampil setelah barang dinonaktifkan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: fixture.branchHead.id, prId: prId);
      await context.deactivate('items', fixture.simpleItem.id);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestDetailPage(prId: prId),
        overrides: [clockOverride],
      );

      expect(find.byKey(HistoricalMasterBadge.badgeKey), findsWidgets);
      expect(
        find.text(fixture.simpleItem.name),
        findsOneWidget,
        reason: 'Barang nonaktif tetap tampil, hanya ditandai.',
      );

      await disposeWidget(tester);
    });

    testWidgets('detail tidak menampilkan milli-unit', (tester) async {
      useTabletSurface(tester);
      final fixture = await fixtureWithCounts();
      final prId = await draftFor(fixture);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: PurchaseRequestDetailPage(prId: prId),
        overrides: [clockOverride],
      );

      // 2.5 box is 2500 milli-units, and a user must never see that (Q-6).
      expect(find.text('2.5 box'), findsWidgets);
      expect(find.textContaining('2500'), findsNothing);

      await disposeWidget(tester);
    });
  });
}
