import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/widgets/quantity_field.dart';
import 'package:aish_warehouse/features/disposal/presentation/pages/disposal_detail_page.dart';
import 'package:aish_warehouse/features/disposal/presentation/pages/disposal_form_page.dart';
import 'package:aish_warehouse/features/disposal/presentation/pages/disposal_list_page.dart';
import 'package:aish_warehouse/features/disposal/presentation/providers/disposal_providers.dart';
import 'package:aish_warehouse/features/disposal/presentation/widgets/disposal_badges.dart';
import 'package:aish_warehouse/features/disposal/presentation/widgets/disposal_candidate_picker.dart';
import 'package:aish_warehouse/features/disposal/presentation/widgets/disposal_dashboard_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The two Pemusnahan screens, driven the way a user drives them (§46).
///
/// Everything is pumped against the same in-memory database the domain tests use, so
/// nothing here is a stub: the scoped queries really run, the use cases really refuse,
/// and the numbers on screen are the numbers in `stock_balances`.
///
/// The assertions that matter most are the **absences**: no near-expiry batch in the
/// picker, no valid batch anywhere, no approval wording, no edit control on a posted
/// document, and no milli-units on any screen.
void main() {
  final nowUtc = DateTime.utc(2026, 7, 30, 4);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// Pumps the real router at [location], with the feature clock pinned so the
  /// eligibility rule is the one the test means.
  Future<void> open(
    WidgetTester tester, {
    required String location,
    required actingAs,
  }) async {
    useTabletSurface(tester);
    await pumpAppAt(
      tester,
      context: context,
      actingAs: actingAs,
      location: location,
      overrides: [disposalClockProvider.overrideWithValue(() => nowUtc)],
    );
  }

  Future<String> draftAt(
    String locationId, {
    required String actorUserId,
    String? reason,
  }) => createDisposalDraft(
    context,
    fixture,
    sourceLocationId: locationId,
    nowUtc: nowUtc,
    actorUserId: actorUserId,
    reason: reason,
  );

  group('Warehouse — daftar', () {
    testWidgets('menampilkan stok kedaluwarsa Warehouse Pusat', (tester) async {
      await open(
        tester,
        location: '/warehouse/disposals',
        actingAs: fixture.warehouseUser,
      );

      expect(find.text('Pemusnahan Stok'), findsWidgets);
      expect(find.byKey(DisposalListPage.sourceHeaderKey), findsOneWidget);
      expect(find.byKey(DisposalListPage.expiredListKey), findsOneWidget);
      // The expired batches, by name.
      expect(find.textContaining(fixture.expiredBatch.batchNo), findsWidgets);
      expect(find.textContaining(fixture.staleBatch.batchNo), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('tidak menampilkan batch yang belum kedaluwarsa', (
      tester,
    ) async {
      await open(
        tester,
        location: '/warehouse/disposals',
        actingAs: fixture.warehouseUser,
      );

      // Expiring today is not expired (T-10); near expiry is a badge, not a
      // candidate (§28); a valid batch appears nowhere at all.
      expect(find.textContaining(fixture.todayBatch.batchNo), findsNothing);
      expect(find.textContaining(fixture.nearBatch.batchNo), findsNothing);
      expect(find.textContaining(fixture.validBatch.batchNo), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('tidak ada selektor sumber di sisi warehouse', (tester) async {
      // One location, so a picker would be a choice with one option — and a control
      // a future change could widen by accident.
      await open(
        tester,
        location: '/warehouse/disposals',
        actingAs: fixture.warehouseUser,
      );

      expect(find.byKey(DisposalListPage.sourceSelectorKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('daftar draft kosong menjelaskan langkah berikutnya', (
      tester,
    ) async {
      await open(
        tester,
        location: '/warehouse/disposals',
        actingAs: fixture.warehouseUser,
      );
      await tester.tap(find.byKey(DisposalListPage.draftTabKey));
      await tester.pumpAndSettle();

      expect(find.byKey(DisposalListPage.draftEmptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('draft yang ada muncul di tab Draft', (tester) async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Kedaluwarsa',
      );
      await open(
        tester,
        location: '/warehouse/disposals',
        actingAs: fixture.warehouseUser,
      );
      await tester.tap(find.byKey(DisposalListPage.draftTabKey));
      await tester.pumpAndSettle();

      expect(find.byKey(DisposalSummaryTile.tileKeyFor(id)), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('tombol Buat Pemusnahan tersedia', (tester) async {
      await open(
        tester,
        location: '/warehouse/disposals',
        actingAs: fixture.warehouseUser,
      );

      expect(find.byKey(DisposalListPage.createKey), findsOneWidget);
      expect(find.text('Buat Pemusnahan'), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('Kepala Cabang — daftar', () {
    testWidgets('selektor sumber memuat gudang dan ruangan cabang', (
      tester,
    ) async {
      await open(tester, location: '/disposals', actingAs: fixture.branchHead);

      expect(find.byKey(DisposalListPage.sourceSelectorKey), findsOneWidget);
      for (final location in [
        fixture.branchStore,
        fixture.locationOne,
        fixture.locationTwo,
      ]) {
        expect(
          find.byKey(DisposalListPage.sourceChipKeyFor(location.id)),
          findsOneWidget,
          reason: '${location.name} tidak ada di selektor.',
        );
      }
      await disposeWidget(tester);
    });

    testWidgets('selektor tidak memuat Warehouse Pusat maupun cabang lain', (
      tester,
    ) async {
      await open(tester, location: '/disposals', actingAs: fixture.branchHead);

      expect(
        find.byKey(DisposalListPage.sourceChipKeyFor(fixture.warehouse.id)),
        findsNothing,
      );
      expect(
        find.byKey(
          DisposalListPage.sourceChipKeyFor(fixture.otherBranchStore.id),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          DisposalListPage.sourceChipKeyFor(fixture.otherBranchRoomLocation.id),
        ),
        findsNothing,
      );
      await disposeWidget(tester);
    });

    testWidgets('tidak ada pilihan "semua lokasi"', (tester) async {
      // The one-source invariant made visible: a document draws from exactly one
      // shelf, so a selector that could mean "all of them" would offer something the
      // document cannot express.
      await open(tester, location: '/disposals', actingAs: fixture.branchHead);

      final selector = find.byKey(DisposalListPage.sourceSelectorKey);
      expect(
        find.descendant(of: selector, matching: find.text('Semua')),
        findsNothing,
      );
      await disposeWidget(tester);
    });

    testWidgets('memilih ruangan mengganti daftar stok kedaluwarsa', (
      tester,
    ) async {
      await open(tester, location: '/disposals', actingAs: fixture.branchHead);

      // The branch store holds the other item too; room 1 holds only the one batch.
      await tester.tap(
        find.byKey(DisposalListPage.sourceChipKeyFor(fixture.locationOne.id)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(fixture.expiredBatch.batchNo), findsWidgets);
      expect(
        find.textContaining(fixture.otherExpiredBatch.batchNo),
        findsNothing,
      );
      await disposeWidget(tester);
    });
  });

  group('form draft', () {
    Future<String> openDraftForm(WidgetTester tester) async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );
      return id;
    }

    testWidgets('form kosong menjelaskan apa yang harus dipilih', (
      tester,
    ) async {
      await openDraftForm(tester);

      expect(find.byKey(DisposalFormPage.emptyKey), findsOneWidget);
      expect(find.byKey(DisposalFormPage.addKey), findsOneWidget);
      // The reason is missing, so the form says so rather than silently disabling
      // the button.
      expect(find.byKey(DisposalFormPage.reasonMissingKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('header menampilkan nomor sementara dan sumber', (
      tester,
    ) async {
      final id = await openDraftForm(tester);
      final disposal = await context.disposals.getById(id);

      expect(find.text(disposal!.docNumber), findsOneWidget);
      expect(find.textContaining('TMP-DSP-'), findsOneWidget);
      expect(find.textContaining('Warehouse Pusat'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('picker hanya menawarkan batch kedaluwarsa', (tester) async {
      await openDraftForm(tester);

      await tester.tap(find.byKey(DisposalFormPage.addKey));
      await tester.pumpAndSettle();

      expect(find.byKey(DisposalCandidatePicker.sheetKey), findsOneWidget);
      expect(find.textContaining(fixture.expiredBatch.batchNo), findsWidgets);
      // Every batch that must never be selectable — absent, not disabled.
      expect(find.textContaining(fixture.todayBatch.batchNo), findsNothing);
      expect(find.textContaining(fixture.nearBatch.batchNo), findsNothing);
      expect(find.textContaining(fixture.validBatch.batchNo), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('picker tidak menawarkan barang tanpa kedaluwarsa', (
      tester,
    ) async {
      await openDraftForm(tester);
      await tester.tap(find.byKey(DisposalFormPage.addKey));
      await tester.pumpAndSettle();

      // §9: nothing about an item with `has_expiry = false` can be past a date.
      expect(find.textContaining(fixture.plainItem.name), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('menambah posisi dengan jumlah desimal', (tester) async {
      final id = await openDraftForm(tester);

      await tester.tap(find.byKey(DisposalFormPage.addKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(
              DisposalCandidatePicker.tileKeyFor(
                '${fixture.expiryItem.id}|${fixture.expiredBatch.id}',
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(DisposalCandidatePicker.qtyKey),
        '2.375',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DisposalCandidatePicker.addKey));
      await tester.pumpAndSettle();

      final lines = await context.disposalLineRows(id);
      expect(lines, hasLength(1));
      expect(lines.values.single['qty'], Quantity.parse('2.375').milliUnits);
      await disposeWidget(tester);
    });

    testWidgets('jumlah default adalah seluruh posisi', (tester) async {
      await openDraftForm(tester);
      await tester.tap(find.byKey(DisposalFormPage.addKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(
              DisposalCandidatePicker.tileKeyFor(
                '${fixture.expiryItem.id}|${fixture.expiredBatch.id}',
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();

      // Destroying all of an expired batch is the ordinary case.
      final field = tester.widget<TextFormField>(
        find.descendant(
          of: find.byKey(DisposalCandidatePicker.qtyKey),
          matching: find.byType(TextFormField),
        ),
      );
      expect(field.controller?.text, '5.5');
      await disposeWidget(tester);
    });

    testWidgets('menghapus baris mengembalikan form ke keadaan kosong', (
      tester,
    ) async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Kedaluwarsa',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.tap(find.byKey(DisposalFormPage.removeKeyFor(lineId)));
      await tester.pumpAndSettle();

      expect(await context.disposalLineCount(id), 0);
      expect(find.byKey(DisposalFormPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('baris menampilkan saldo tersedia dan sisa setelah pemusnahan', (
      tester,
    ) async {
      // §30. The remaining figure is what a user checks before pressing a button
      // that cannot be undone, so it has to be there and it has to be exact.
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Kedaluwarsa',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '2.375',
        nowUtc: nowUtc,
      );
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );

      expect(
        find.byKey(DisposalFormPage.remainingKeyFor(lineId)),
        findsOneWidget,
      );
      // 5.5 − 2.375 = 3.125, exactly.
      expect(find.textContaining('Tersedia 5.5 ampul'), findsWidgets);
      expect(find.textContaining('sisa 3.125 ampul'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('sisa mengikuti jumlah yang diketik', (tester) async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Kedaluwarsa',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.enterText(
        find.byKey(DisposalFormPage.qtyFieldKeyFor(lineId)),
        '5.5',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('sisa 0 ampul'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('jumlah melebihi saldo dikatakan, bukan dipotong diam-diam', (
      tester,
    ) async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Kedaluwarsa',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.enterText(
        find.byKey(DisposalFormPage.qtyFieldKeyFor(lineId)),
        '99',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('melebihi saldo lokasi'), findsWidgets);
      // And the stored line is untouched until something is saved.
      expect(
        (await context.disposalLineRows(id)).values.single['qty'],
        Quantity.parse('1').milliUnits,
      );
      await disposeWidget(tester);
    });

    testWidgets('kunci baris stabil di antara build', (tester) async {
      // §31.5 depends on the key surviving a rebuild: one recreated each build would
      // attach to a different element every frame, and `ensureVisible` would scroll
      // to whatever was there last time — or to nothing.
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Kedaluwarsa',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );

      Key keyOfCard() => tester
          .widget(
            find
                .ancestor(
                  of: find.byKey(DisposalFormPage.qtyFieldKeyFor(lineId)),
                  matching: find.byWidgetPredicate(
                    (widget) => widget.key is GlobalKey,
                  ),
                )
                .last,
          )
          .key!;

      final before = keyOfCard();
      // Force a rebuild by typing into an unrelated field.
      await tester.enterText(
        find.byKey(DisposalFormPage.lineNoteKeyFor(lineId)),
        'Kemasan bocor',
      );
      await tester.pumpAndSettle();

      expect(identical(keyOfCard(), before), isTrue);
      await disposeWidget(tester);
    });

    testWidgets('chip alasan tersedia dan tanpa kata persetujuan', (
      tester,
    ) async {
      await openDraftForm(tester);

      expect(
        find.byKey(DisposalFormPage.reasonPresetKeyFor('expired')),
        findsOneWidget,
      );
      expect(
        find.byKey(DisposalFormPage.reasonPresetKeyFor('other')),
        findsOneWidget,
      );
      // §7/§31: posting is not approving, and the wording must not suggest it is.
      expect(find.textContaining('Setujui'), findsNothing);
      expect(find.textContaining('Approve'), findsNothing);
      expect(find.textContaining('Menunggu Persetujuan'), findsNothing);
      await disposeWidget(tester);
    });
  });

  group('baris invalid pertama (§31.5)', () {
    /// A document with five positions, so the last cards sit well below the fold on
    /// a tablet surface — which is the whole situation the scroll exists for.
    ///
    /// Returns the line ids in the order the form displays them (oldest expiry
    /// first), because "the first invalid line" is a claim about what the user sees.
    Future<({String id, List<String> lineIds})> tallDraft() async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Kedaluwarsa',
      );
      for (final position in <({String item, String batch, String qty})>[
        (
          item: fixture.expiryItem.id,
          batch: fixture.staleBatch.id,
          qty: '0.25',
        ),
        (item: fixture.expiryItem.id, batch: fixture.expiredBatch.id, qty: '1'),
        (
          item: fixture.otherExpiryItem.id,
          batch: fixture.otherExpiredBatch.id,
          qty: '0.5',
        ),
      ]) {
        await addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: position.item,
          batchId: position.batch,
          qty: position.qty,
          nowUtc: nowUtc,
        );
      }

      final detail = await context.disposals.getDetail(id);
      return (
        id: id,
        lineIds: detail!.orderedLines.map((line) => line.id).toList(),
      );
    }

    /// Pumps the form on a **narrow** surface.
    ///
    /// A tablet is tall enough to show a three-position document in one screen, and
    /// a scroll test needs something that genuinely does not fit. A phone-sized
    /// window is both realistic — the clinic's tablets are used in portrait, and a
    /// document can hold one line per expired position — and deterministic.
    Future<void> openNarrow(
      WidgetTester tester, {
      required String location,
      required actingAs,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 620);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: actingAs,
        location: location,
        overrides: [disposalClockProvider.overrideWithValue(() => nowUtc)],
      );
    }

    /// Whether the card carrying [lineId]'s quantity field is inside the viewport.
    bool isVisible(WidgetTester tester, String lineId) {
      final finder = find.byKey(DisposalFormPage.qtyFieldKeyFor(lineId));
      if (finder.evaluate().isEmpty) return false;
      final box = tester.renderObject<RenderBox>(finder);
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      return bottom > 0 && top < screen;
    }

    testWidgets('baris invalid di luar viewport discroll hingga terlihat', (
      tester,
    ) async {
      final draft = await tallDraft();
      final lastLineId = draft.lineIds.last;

      await openNarrow(
        tester,
        location: '/warehouse/disposals/${draft.id}/edit',
        actingAs: fixture.warehouseUser,
      );

      // Empty the *last* field, then scroll back to the top so it is genuinely off
      // screen when posting is pressed.
      await tester.enterText(
        find.byKey(DisposalFormPage.qtyFieldKeyFor(lastLineId)),
        '',
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(DisposalFormPage.linesKey),
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(
        isVisible(tester, lastLineId),
        isFalse,
        reason:
            'Prasyarat gagal: baris terakhir masih terlihat sebelum posting.',
      );

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();

      expect(isVisible(tester, lastLineId), isTrue);
      // The message the user already had is still shown alongside the scroll.
      expect(find.textContaining('belum valid'), findsWidgets);
      // And nothing was posted.
      expect(await context.disposalStatusOf(draft.id), 'draft');
      await disposeWidget(tester);
    });

    testWidgets('field invalid mendapat focus', (tester) async {
      final draft = await tallDraft();
      final lastLineId = draft.lineIds.last;

      await openNarrow(
        tester,
        location: '/warehouse/disposals/${draft.id}/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.enterText(
        find.byKey(DisposalFormPage.qtyFieldKeyFor(lastLineId)),
        '',
      );
      await tester.pumpAndSettle();
      // Take the focus away, so the assertion is about the form putting it back
      // rather than about it never having moved.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('disposalQty-$lastLineId'),
        reason:
            'Prasyarat gagal: focus sudah berada di field target sebelum posting.',
      );

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();

      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      expect(
        focused!.debugLabel,
        'disposalQty-$lastLineId',
        reason: 'Focus tidak mendarat pada field jumlah baris yang invalid.',
      );
      await disposeWidget(tester);
    });

    testWidgets('hanya baris invalid pertama yang menjadi target', (
      tester,
    ) async {
      final draft = await tallDraft();
      final firstLineId = draft.lineIds.first;
      final lastLineId = draft.lineIds.last;

      await openNarrow(
        tester,
        location: '/warehouse/disposals/${draft.id}/edit',
        actingAs: fixture.warehouseUser,
      );

      // Two invalid lines: the first in display order and the last. Only the first
      // may be targeted — otherwise the user is sent to the end of a document whose
      // earlier problem they have not seen yet.
      for (final lineId in [firstLineId, lastLineId]) {
        await tester.enterText(
          find.byKey(DisposalFormPage.qtyFieldKeyFor(lineId)),
          '',
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'disposalQty-$firstLineId',
      );
      await disposeWidget(tester);
    });

    testWidgets('jumlah nol diperlakukan sebagai baris invalid', (
      tester,
    ) async {
      // A zero parses fine, so nothing would catch it before the use case; §31.5 is
      // about pointing at the field, and a field holding `0` is exactly that case.
      final draft = await tallDraft();
      final targetLineId = draft.lineIds.first;

      await openNarrow(
        tester,
        location: '/warehouse/disposals/${draft.id}/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.enterText(
        find.byKey(DisposalFormPage.qtyFieldKeyFor(targetLineId)),
        '0',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'disposalQty-$targetLineId',
      );
      expect(await context.disposalStatusOf(draft.id), 'draft');
      // The zero was never written: the flush refused before sending it.
      expect(
        (await context.disposalLineRows(draft.id))[targetLineId]!['qty'],
        Quantity.parse('0.25').milliUnits,
      );
      await disposeWidget(tester);
    });

    testWidgets('tidak ada exception ketika baris invalid dihapus lebih dahulu', (
      tester,
    ) async {
      // The card the form would scroll to no longer exists. A null `currentContext`
      // and a detached focus node are ordinary outcomes here, not errors.
      final draft = await tallDraft();
      final targetLineId = draft.lineIds.first;

      await openNarrow(
        tester,
        location: '/warehouse/disposals/${draft.id}/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.enterText(
        find.byKey(DisposalFormPage.qtyFieldKeyFor(targetLineId)),
        '',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(DisposalFormPage.removeKeyFor(targetLineId)));
      await tester.pumpAndSettle();
      expect(await context.disposalLineCount(draft.id), 2);

      // Posting now walks the remaining lines, all of which are valid.
      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DisposalFormPage.confirmAcceptKey));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(await context.disposalStatusOf(draft.id), 'posted');
      await disposeWidget(tester);
    });

    testWidgets('tidak ada exception ketika halaman dispose setelah scroll', (
      tester,
    ) async {
      final draft = await tallDraft();
      final lastLineId = draft.lineIds.last;

      await openNarrow(
        tester,
        location: '/warehouse/disposals/${draft.id}/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.enterText(
        find.byKey(DisposalFormPage.qtyFieldKeyFor(lastLineId)),
        '',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();
      expect(isVisible(tester, lastLineId), isTrue);

      // Tearing the page down disposes every controller, focus node and key the page
      // created — including the ones the scroll had just touched, and the ones
      // belonging to lines removed earlier.
      await disposeWidget(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tidak ada exception ketika dispose setelah menghapus baris', (
      tester,
    ) async {
      final draft = await tallDraft();
      final targetLineId = draft.lineIds.first;

      await openNarrow(
        tester,
        location: '/warehouse/disposals/${draft.id}/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.tap(find.byKey(DisposalFormPage.removeKeyFor(targetLineId)));
      await tester.pumpAndSettle();

      await disposeWidget(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('posting', () {
    Future<String> readyDraft({String? reason}) async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: reason,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '2',
        nowUtc: nowUtc,
      );
      return id;
    }

    testWidgets(
      'menekan posting tanpa alasan menampilkan pesan, bukan dialog',
      (tester) async {
        final id = await readyDraft();
        await open(
          tester,
          location: '/warehouse/disposals/$id/edit',
          actingAs: fixture.warehouseUser,
        );

        await tester.tap(find.byKey(DisposalFormPage.postKey));
        await tester.pumpAndSettle();

        expect(find.byKey(DisposalFormPage.confirmKey), findsNothing);
        expect(
          find.textContaining('Catatan pemusnahan wajib diisi'),
          findsWidgets,
        );
        expect(await context.disposalStatusOf(id), 'draft');
        await disposeWidget(tester);
      },
    );

    testWidgets('dialog konfirmasi menyebut lokasi, jumlah posisi dan '
        'finalitas', (tester) async {
      final id = await readyDraft(reason: 'Kedaluwarsa');
      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();

      expect(find.byKey(DisposalFormPage.confirmKey), findsOneWidget);
      expect(find.textContaining('1 posisi'), findsWidgets);
      expect(find.textContaining('Warehouse Pusat'), findsWidgets);
      expect(find.textContaining('Tidak ada lokasi tujuan'), findsOneWidget);
      expect(find.text(DisposalFinalityNotice.message), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('membatalkan dialog tidak memposting apa pun', (tester) async {
      final id = await readyDraft(reason: 'Kedaluwarsa');
      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DisposalFormPage.confirmCancelKey));
      await tester.pumpAndSettle();

      expect(await context.disposalStatusOf(id), 'draft');
      expect(await context.disposalMovementCount(id), 0);
      await disposeWidget(tester);
    });

    testWidgets('posting mengurangi saldo dan membuka detail read-only', (
      tester,
    ) async {
      final id = await readyDraft(reason: 'Kedaluwarsa');
      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DisposalFormPage.confirmAcceptKey));
      await tester.pumpAndSettle();

      expect(await context.disposalStatusOf(id), 'posted');
      expect(await context.disposalMovementCount(id), 1);
      expect(
        await locationBalance(
          context,
          locationId: fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('3.5'),
      );
      // And the user lands on the document rather than a form they can no longer use.
      expect(find.byKey(DisposalDetailPage.detailKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('perubahan jumlah yang belum disimpan ikut ter-flush', (
      tester,
    ) async {
      // §31: the confirmation must describe the *stored* document, so the typed
      // quantity is written before the dialog opens rather than being lost.
      final id = await readyDraft(reason: 'Kedaluwarsa');
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );
      await tester.enterText(
        find.byKey(DisposalFormPage.qtyFieldKeyFor(lineId)),
        '3.125',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DisposalFormPage.confirmAcceptKey));
      await tester.pumpAndSettle();

      final movements = await context.disposalMovements(id);
      expect(movements.single['qty'], Quantity.parse('3.125').milliUnits);
      expect(
        await locationBalance(
          context,
          locationId: fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('2.375'),
      );
      await disposeWidget(tester);
    });

    testWidgets('alasan yang diketik ikut ter-flush sebelum posting', (
      tester,
    ) async {
      final id = await readyDraft();
      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );

      await tester.tap(
        find.byKey(DisposalFormPage.reasonPresetKeyFor('cleanup')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DisposalFormPage.reasonDetailKey),
        'Ditemukan saat audit bulanan',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(DisposalFormPage.postKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DisposalFormPage.confirmAcceptKey));
      await tester.pumpAndSettle();

      // The composed audit sentence, stored and carried onto the movement.
      expect(
        await context.disposalColumn(id, 'reason'),
        'Pembersihan stok lama — Ditemukan saat audit bulanan',
      );
      expect(
        (await context.disposalMovements(id)).single['note'],
        'Pembersihan stok lama — Ditemukan saat audit bulanan',
      );
      await disposeWidget(tester);
    });

    testWidgets(
      'stok yang berubah menghasilkan pesan, bukan penyesuaian diam',
      (tester) async {
        final id = await readyDraft(reason: 'Kedaluwarsa');
        await open(
          tester,
          location: '/warehouse/disposals/$id/edit',
          actingAs: fixture.warehouseUser,
        );

        // Something else drains the shelf while the form is open.
        await context.posting.postOpnameAdjustment(
          locationId: fixture.warehouse.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
          countedQty: Quantity.parse('0.5'),
          actorUserId: fixture.warehouseUser.id,
          note: 'Koreksi hitung fisik',
        );

        await tester.tap(find.byKey(DisposalFormPage.postKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(DisposalFormPage.confirmAcceptKey));
        await tester.pumpAndSettle();

        // Refused, and the quantity was never quietly reduced to fit.
        expect(await context.disposalStatusOf(id), 'draft');
        expect(await context.disposalMovementCount(id), 0);
        expect(
          (await context.disposalLineRows(id)).values.single['qty'],
          Quantity.parse('2').milliUnits,
        );
        expect(find.textContaining('tidak mencukupi'), findsWidgets);
        await disposeWidget(tester);
      },
    );

    testWidgets('tombol nonaktif ketika dokumen kosong', (tester) async {
      final id = await draftAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
        reason: 'Kedaluwarsa',
      );
      await open(
        tester,
        location: '/warehouse/disposals/$id/edit',
        actingAs: fixture.warehouseUser,
      );

      final button = tester.widget<FilledButton>(
        find.byKey(DisposalFormPage.postKey),
      );
      expect(button.onPressed, isNull);
      await disposeWidget(tester);
    });
  });

  group('detail read-only', () {
    Future<String> postedDisposal() async {
      final id = await draftAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
        reason: 'Kedaluwarsa — kemasan sudah rusak',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '2.375',
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
        note: 'Kemasan bocor',
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);
      return id;
    }

    testWidgets('menampilkan batch, ED, alasan dan sumber', (tester) async {
      final id = await postedDisposal();
      await open(
        tester,
        location: '/disposals/$id',
        actingAs: fixture.branchHead,
      );

      expect(find.byKey(DisposalDetailPage.detailKey), findsOneWidget);
      expect(find.textContaining(fixture.expiredBatch.batchNo), findsWidgets);
      expect(find.text('Kedaluwarsa — kemasan sudah rusak'), findsOneWidget);
      expect(find.textContaining(fixture.branchStore.name), findsWidgets);
      expect(find.textContaining('Kemasan bocor'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('menyatakan tidak ada lokasi tujuan', (tester) async {
      final id = await postedDisposal();
      await open(
        tester,
        location: '/disposals/$id',
        actingAs: fixture.branchHead,
      );

      expect(find.byKey(DisposalDetailPage.noDestinationKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('menampilkan badge kedaluwarsa dengan jumlah hari', (
      tester,
    ) async {
      final id = await postedDisposal();
      await open(
        tester,
        location: '/disposals/$id',
        actingAs: fixture.branchHead,
      );

      expect(find.byKey(DisposalExpiryBadge.expiredKey), findsWidgets);
      expect(find.textContaining('lewat 3 hari'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('menampilkan desimal, tidak pernah milli-unit', (tester) async {
      final id = await postedDisposal();
      await open(
        tester,
        location: '/disposals/$id',
        actingAs: fixture.branchHead,
      );

      expect(find.textContaining('2.375'), findsWidgets);
      // Q-6: the scale never reaches a screen.
      expect(find.textContaining('2375'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('tidak ada kontrol ubah, hapus, posting ulang atau '
        'persetujuan', (tester) async {
      final id = await postedDisposal();
      await open(
        tester,
        location: '/disposals/$id',
        actingAs: fixture.branchHead,
      );

      expect(find.byKey(DisposalFormPage.postKey), findsNothing);
      expect(find.byKey(DisposalFormPage.addKey), findsNothing);
      expect(find.byType(TextField), findsNothing);
      // The real editable-quantity control, asserted absent by its own type rather
      // than by hoping no text field happens to be on screen.
      expect(find.byType(QuantityField), findsNothing);
      expect(find.textContaining('Setujui'), findsNothing);
      expect(find.textContaining('Batalkan Posting'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('timeline menyebut pembuat dan pemosting', (tester) async {
      final id = await postedDisposal();
      await open(
        tester,
        location: '/disposals/$id',
        actingAs: fixture.branchHead,
      );

      expect(find.byKey(DisposalDetailPage.timelineKey), findsOneWidget);
      expect(find.text('Dibuat'), findsWidgets);
      expect(find.text('Diposting'), findsWidgets);
      expect(find.textContaining(fixture.branchHead.fullName), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('menyebut referensi ledger DSP', (tester) async {
      final id = await postedDisposal();
      await open(
        tester,
        location: '/disposals/$id',
        actingAs: fixture.branchHead,
      );

      expect(find.textContaining('DSP'), findsWidgets);
      await disposeWidget(tester);
    });
  });

  group('kartu dashboard', () {
    testWidgets('kartu warehouse menghitung posisi kedaluwarsa', (
      tester,
    ) async {
      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        child: const Scaffold(body: WarehouseDisposalCard()),
        // `pumpAppWidget` already injects the in-memory database; overriding it a
        // second time here would build two containers for one scope.
        overrides: [disposalClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byKey(WarehouseDisposalCard.cardKey), findsOneWidget);
      // `expiredBatch`, `staleBatch` and `otherExpiredBatch` are on the warehouse
      // shelf; nothing else there is past its date.
      expect(find.textContaining('3 batch kedaluwarsa'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('kartu cabang memisahkan gudang dan ruangan', (tester) async {
      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const Scaffold(body: BranchDisposalCard()),
        // `pumpAppWidget` already injects the in-memory database; overriding it a
        // second time here would build two containers for one scope.
        overrides: [disposalClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byKey(BranchDisposalCard.cardKey), findsOneWidget);
      expect(find.byKey(BranchDisposalCard.storeKey), findsOneWidget);
      expect(find.byKey(BranchDisposalCard.roomKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('entry point Pemusnahan muncul untuk peran yang berhak', (
      tester,
    ) async {
      useTabletSurface(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/',
        overrides: [disposalClockProvider.overrideWithValue(() => nowUtc)],
      );
      expect(
        find.byKey(const ValueKey('homeWarehouseDisposals')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('homeBranchDisposals')), findsNothing);
      await disposeWidget(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/',
        overrides: [disposalClockProvider.overrideWithValue(() => nowUtc)],
      );
      expect(find.byKey(const ValueKey('homeBranchDisposals')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('homeWarehouseDisposals')),
        findsNothing,
      );
      await disposeWidget(tester);
    });

    testWidgets('Perawat tidak melihat entry point Pemusnahan', (tester) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '/',
        overrides: [disposalClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byKey(const ValueKey('homeBranchDisposals')), findsNothing);
      expect(
        find.byKey(const ValueKey('homeWarehouseDisposals')),
        findsNothing,
      );
      await disposeWidget(tester);
    });
  });
}
