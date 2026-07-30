import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/widgets/historical_master_badge.dart';
import 'package:aish_warehouse/features/distribution/presentation/pages/distribution_detail_page.dart';
import 'package:aish_warehouse/features/distribution/presentation/pages/distribution_form_page.dart';
import 'package:aish_warehouse/features/distribution/presentation/pages/distribution_list_page.dart';
import 'package:aish_warehouse/features/distribution/presentation/providers/distribution_providers.dart';
import 'package:aish_warehouse/features/distribution/presentation/widgets/distribution_badges.dart';
import 'package:aish_warehouse/features/distribution/presentation/widgets/distribution_item_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The Distribusi screens (§46).
///
/// Every test pumps the real widget against the real in-memory database, with the feature
/// clock pinned so an expiry badge and the number beside it are judged against the same
/// instant (T-7). Nothing here stubs a provider that touches data: the point of a widget
/// test on these screens is that the query, the policy and the rendering agree.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// The feature clock, pinned so every badge, count and `posted_at` on screen is judged
  /// against one instant (T-7).
  final overrides = <Override>[
    distributionClockProvider.overrideWithValue(() => nowUtc),
  ];

  Future<String> draft() =>
      createDistributionDraft(context, fixture, nowUtc: nowUtc);

  Future<void> add({
    required String id,
    required String roomId,
    required String itemId,
    required String qty,
  }) => addDistributionItem(
    context,
    fixture,
    distributionId: id,
    roomId: roomId,
    itemId: itemId,
    qty: qty,
    nowUtc: nowUtc,
  );

  Future<String> postedDistribution() async {
    final id = await draft();
    await add(
      id: id,
      roomId: fixture.roomOne.id,
      itemId: fixture.simpleItem.id,
      qty: '2',
    );
    await add(
      id: id,
      roomId: fixture.roomTwo.id,
      itemId: fixture.batchItem.id,
      qty: '3',
    );
    await context
        .postDistribution(clock: () => nowUtc)
        .call(actorUserId: fixture.branchHead.id, distributionId: id);
    return id;
  }

  group('daftar', () {
    testWidgets('empty state dan tombol buat', (tester) async {
      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(DistributionListPage.emptyKey), findsOneWidget);
      expect(find.byKey(DistributionListPage.createKey), findsOneWidget);
      expect(find.text('Buat Distribusi'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('baris draft muncul dengan chip status', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
      );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      expect(
        find.byKey(DistributionSummaryTile.tileKeyFor(id)),
        findsOneWidget,
      );
      expect(find.text('Draft'), findsWidgets);
      expect(find.textContaining('1 ruangan · 1 baris'), findsOneWidget);
      expect(find.byKey(DistributionListPage.emptyKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('baris posted muncul dengan waktu posting GMT+8', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await postedDistribution();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      expect(
        find.byKey(DistributionSummaryTile.tileKeyFor(id)),
        findsOneWidget,
      );
      expect(find.text('Selesai Diposting'), findsWidgets);
      // 03:00 UTC is 11:00 GMT+8 (T-2), and the zone is spelled out.
      expect(
        find.textContaining('Diposting 30 Jul 2026, 11:00 GMT+8'),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('cabang aktor ditampilkan', (tester) async {
      useTabletSurface(tester);
      await draft();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(DistributionListPage.branchKey), findsOneWidget);
      expect(find.textContaining('CAB-01 · Cabang Uji'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('cabang tetap tampil meski filter tidak cocok', (tester) async {
      // The header comes from master data, not from the first row: a status filter that
      // matches nothing must not make the branch name disappear (§28).
      useTabletSurface(tester);
      await draft();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      await tester.tap(
        find.byKey(const ValueKey('distributionStatusFilter-posted')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(DistributionListPage.emptyKey), findsOneWidget);
      expect(find.byKey(DistributionListPage.branchKey), findsOneWidget);
      expect(find.textContaining('CAB-01 · Cabang Uji'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('daftar kosong sejak awal tetap menampilkan cabang', (
      tester,
    ) async {
      useTabletSurface(tester);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(DistributionListPage.branchKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('filter status menyaring daftar', (tester) async {
      useTabletSurface(tester);
      final drafted = await draft();
      final posted = await postedDistribution();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      expect(
        find.byKey(DistributionSummaryTile.tileKeyFor(drafted)),
        findsOneWidget,
      );
      expect(
        find.byKey(DistributionSummaryTile.tileKeyFor(posted)),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('distributionStatusFilter-posted')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(DistributionSummaryTile.tileKeyFor(drafted)),
        findsNothing,
      );
      expect(
        find.byKey(DistributionSummaryTile.tileKeyFor(posted)),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('pencarian menyaring daftar', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      await tester.enterText(
        find.byKey(DistributionListPage.searchKey),
        'Ruang Dental 2',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(DistributionSummaryTile.tileKeyFor(id)),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(DistributionListPage.searchKey),
        'tidak ada apa pun',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(DistributionSummaryTile.tileKeyFor(id)), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('sesi tanpa hak tulis melihat daftar kosong', (tester) async {
      useTabletSurface(tester);
      await draft();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        child: const DistributionListPage(),
        overrides: overrides,
      );

      // The provider emits empty for a role that may not distribute, so the screen has
      // nothing to render even when it is somehow reached directly.
      expect(find.byKey(DistributionListPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('form multi-ruangan', () {
    Future<void> pumpForm(WidgetTester tester, String id) => pumpAppWidget(
      tester,
      context: context,
      actingAs: fixture.branchHead,
      child: DistributionFormPage(distributionId: id),
      overrides: overrides,
    );

    testWidgets('chip ruangan dinamis dari database', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);

      // Three rooms, from the database — never a hard-coded `R1 / R2 / R3`.
      expect(find.byKey(DistributionRoomChips.rowKey), findsOneWidget);
      for (final room in [
        fixture.roomOne,
        fixture.roomTwo,
        fixture.roomThree,
      ]) {
        expect(
          find.byKey(DistributionRoomChips.keyFor(room.id)),
          findsOneWidget,
        );
      }
      // Another branch's room is never offered (G-T1).
      expect(
        find.byKey(DistributionRoomChips.keyFor(fixture.otherBranchRoom.id)),
        findsNothing,
      );
      await disposeWidget(tester);
    });

    testWidgets('ruangan keempat muncul tanpa reload', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);

      final fourth = await context.master.ensureRoom(
        branchId: fixture.branch.id,
        code: 'R4',
        name: 'Ruang Dental 4',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(DistributionRoomChips.keyFor(fourth.id)),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('chip kategori dinamis', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);

      expect(
        find.byKey(DistributionCategoryFilterChips.allKey),
        findsOneWidget,
      );
      expect(
        find.byKey(DistributionCategoryFilterChips.keyFor(fixture.category.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(
          DistributionCategoryFilterChips.keyFor(fixture.otherCategory.id),
        ),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('pencarian barang butuh ruangan terpilih lebih dahulu', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);

      expect(
        find.text('Pilih ruangan tujuan terlebih dahulu.'),
        findsOneWidget,
      );
      expect(find.byKey(DistributionItemPicker.fieldKey), findsNothing);

      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(DistributionItemPicker.fieldKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('pencarian hanya menampilkan barang bersaldo', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);
      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'DIST-000',
      );
      // The picker debounces ±200 ms (spec §4.3).
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();

      expect(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.simpleItem.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.batchItem.id)),
        findsOneWidget,
      );
      // `emptyItem` has no branch-store balance, so it is not distributable (§15).
      expect(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.emptyItem.id)),
        findsNothing,
      );
      await disposeWidget(tester);
    });

    testWidgets('pencarian tanpa hasil menampilkan "Tidak ditemukan"', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);
      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'barang yang tidak ada',
      );
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();

      expect(find.byKey(DistributionItemPicker.emptyKey), findsOneWidget);
      expect(find.text('Tidak ditemukan'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('memilih barang membuka kartu qty dengan saldo', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);
      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'Masker',
      );
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.simpleItem.id)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(DistributionFormPage.qtyKey), findsOneWidget);
      expect(find.textContaining('tersedia 10.5 box'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('menambah qty desimal menyimpan baris', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);
      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'Masker',
      );
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.simpleItem.id)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(DistributionFormPage.qtyKey), '2.375');
      await tester.tap(find.byKey(DistributionFormPage.addKey));
      await tester.pumpAndSettle();

      final rows = await context.distributionLineRows(id);
      expect(rows.values.single['qty'], 2375);
      // The stored line is rendered, grouped under its room.
      expect(find.textContaining('2.375 box'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('alokasi FEFO terpecah ditampilkan per batch', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
      );
      await pumpForm(tester, id);

      // Two lines, nearest expiry first.
      expect(find.textContaining('B-OLD'), findsWidgets);
      expect(find.textContaining('A-NEW'), findsWidgets);
      expect(find.textContaining('2 ampul'), findsWidgets);
      expect(find.textContaining('1 ampul'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('batch kedaluwarsa tidak pernah muncul', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);
      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'Anestesi',
      );
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.batchItem.id)),
      );
      await tester.pumpAndSettle();

      // The candidate pills list `B-OLD` and `A-NEW`; `C-EXPIRED` is not offered at all
      // (G-E4).
      expect(find.textContaining('B-OLD'), findsWidgets);
      expect(find.textContaining('C-EXPIRED'), findsNothing);
      // The usable total excludes it too: 6, not 9.
      expect(find.textContaining('tersedia 6 ampul'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('badge near-expiry oranye tampil tanpa memblokir', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '2',
      );
      await pumpForm(tester, id);

      // `B-OLD` has 10 days left against a 30-day threshold (G-E6). It is a badge, not a
      // gate: the *Posting* button stays enabled.
      expect(find.byKey(DistributionExpiryBadge.nearExpiryKey), findsWidgets);
      final button = tester.widget<FilledButton>(
        find.byKey(DistributionFormPage.postKey),
      );
      expect(button.onPressed, isNotNull);
      await disposeWidget(tester);
    });

    testWidgets('baris multi-ruangan dikelompokkan', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
      );
      await pumpForm(tester, id);

      expect(find.textContaining('R1 · Ruang Dental 1'), findsWidgets);
      expect(find.textContaining('R2 · Ruang Dental 2'), findsWidgets);
      expect(find.textContaining('1 ruangan'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('barang yang sudah ada ditandai pada pencarian', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await pumpForm(tester, id);
      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'Masker',
      );
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();

      // Still listed, but marked — so the branch head can see *why* picking it will not
      // add a second row, rather than tapping it and getting a refusal.
      expect(find.text('Sudah ada'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('menghapus baris memperbarui daftar', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      final lines = await distributionLineIdsByPosition(context, id);
      await pumpForm(tester, id);

      await tester.tap(find.byKey(_removeKeyFor(lines.values.single)));
      await tester.pumpAndSettle();

      expect(await context.distributionLineCount(id), 0);
      expect(find.byKey(DistributionFormPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('stok tidak cukup menampilkan pesan Bahasa Indonesia', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);
      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'Masker',
      );
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.simpleItem.id)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(DistributionFormPage.qtyKey), '99');
      await tester.tap(find.byKey(DistributionFormPage.addKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('Saldo Gudang Cabang'), findsOneWidget);
      expect(find.textContaining('tidak mencukupi'), findsOneWidget);
      // No raw exception text and no stack trace.
      expect(find.textContaining('Exception'), findsNothing);
      expect(await context.distributionLineCount(id), 0);
      await disposeWidget(tester);
    });

    testWidgets('tombol posting mati pada dokumen kosong', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);

      final button = tester.widget<FilledButton>(
        find.byKey(DistributionFormPage.postKey),
      );
      expect(button.onPressed, isNull);
      await disposeWidget(tester);
    });

    testWidgets('posting meminta konfirmasi dan menjelaskan efeknya', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await pumpForm(tester, id);

      await tester.tap(find.byKey(DistributionFormPage.postKey));
      await tester.pumpAndSettle();

      expect(find.byKey(DistributionFormPage.confirmKey), findsOneWidget);
      expect(
        find.textContaining('Stok Gudang Cabang akan berkurang'),
        findsOneWidget,
      );
      expect(find.textContaining('2 ruangan akan bertambah'), findsOneWidget);
      expect(find.textContaining('bersifat final'), findsOneWidget);

      // Cancelling changes nothing.
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(await context.distributionStatusOf(id), 'draft');
      await disposeWidget(tester);
    });

    testWidgets('konfirmasi memposting dan memindahkan stok', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
      );
      // The real router, not a bare `MaterialApp`: a successful posting navigates to the
      // read-only detail, and asserting that it does means the navigation has to be
      // available. Reaching the form by URL also puts the route guard in the path, which
      // is what a branch head actually goes through.
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/distributions/$id/edit',
        overrides: overrides,
      );

      await tester.tap(find.byKey(DistributionFormPage.postKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DistributionFormPage.confirmAcceptKey));
      await tester.pumpAndSettle();

      expect(await context.distributionStatusOf(id), 'posted');
      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('8.5'),
      );
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('2'),
      );
      await disposeWidget(tester);
    });

    testWidgets('input qty yang belum ditambah di-flush saat posting', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await pumpForm(tester, id);

      // Pick a second item and type a quantity, then press *Posting* without tapping
      // *Tambah*. §29 requires the pending input to be flushed: a number the branch head
      // typed is work they believe is on the document.
      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomTwo.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'Masker',
      );
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.simpleItem.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(DistributionFormPage.qtyKey), '3');

      await tester.tap(find.byKey(DistributionFormPage.postKey));
      await tester.pumpAndSettle();

      // The pending line landed *before* the confirmation appeared.
      expect(await context.distributionLineCount(id), 2);
      expect(find.byKey(DistributionFormPage.confirmKey), findsOneWidget);
      expect(find.textContaining('2 ruangan'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('input pertama pada dokumen kosong di-flush lalu dikonfirmasi', (
      tester,
    ) async {
      // The stale-snapshot case: the document was empty when the build closed over it,
      // so confirming against that snapshot would tell the branch head "belum memuat
      // barang" about the very line they just added.
      useTabletSurface(tester);
      final id = await draft();
      await pumpForm(tester, id);

      await tester.tap(
        find.byKey(DistributionRoomChips.keyFor(fixture.roomOne.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DistributionItemPicker.fieldKey),
        'Masker',
      );
      await tester.pump(DistributionItemPicker.debounce);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(DistributionItemPicker.optionKeyFor(fixture.simpleItem.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(DistributionFormPage.qtyKey), '2');

      // Post without tapping *Tambah*: the line lands and the confirmation appears,
      // rather than a "document is empty" complaint.
      await tester.tap(find.byKey(DistributionFormPage.postKey));
      await tester.pumpAndSettle();

      expect(await context.distributionLineCount(id), 1);
      expect(find.byKey(DistributionFormPage.confirmKey), findsOneWidget);
      expect(find.textContaining('belum memuat barang'), findsNothing);
      // And the counts quoted are the ones after the flush, not one short.
      expect(find.textContaining('1 ruangan akan bertambah'), findsOneWidget);
      expect(find.textContaining('1 baris'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('form menolak membuka dokumen yang sudah diposting', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await postedDistribution();
      await pumpForm(tester, id);

      expect(find.byKey(DistributionFormPage.readOnlyKey), findsOneWidget);
      expect(find.byKey(DistributionFormPage.postKey), findsNothing);
      expect(find.byKey(DistributionItemPicker.fieldKey), findsNothing);
      await disposeWidget(tester);
    });
  });

  group('detail read-only', () {
    Future<void> pumpDetail(WidgetTester tester, String id) => pumpAppWidget(
      tester,
      context: context,
      actingAs: fixture.branchHead,
      child: DistributionDetailPage(distributionId: id),
      overrides: overrides,
    );

    testWidgets('header, timeline dan ringkasan tampil', (tester) async {
      useTabletSurface(tester);
      final id = await postedDistribution();
      await pumpDetail(tester, id);

      expect(find.byKey(DistributionDetailPage.headerKey), findsOneWidget);
      expect(find.byKey(DistributionDetailPage.timelineKey), findsOneWidget);
      expect(find.byKey(DistributionDetailPage.summaryKey), findsOneWidget);
      expect(find.text('Selesai Diposting'), findsWidgets);
      expect(find.textContaining('Kepala Cabang Uji'), findsWidgets);
      expect(find.textContaining('30 Jul 2026, 11:00 GMT+8'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('dikelompokkan per ruangan dengan sumber dan tujuan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await postedDistribution();
      await pumpDetail(tester, id);

      expect(
        find.byKey(DistributionDetailPage.roomKeyFor(fixture.roomOne.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(DistributionDetailPage.roomKeyFor(fixture.roomTwo.id)),
        findsOneWidget,
      );
      // §30 asks for both sides in words.
      expect(
        find.textContaining('Gudang Cabang → Ruang Dental 1'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Gudang Cabang → Ruang Dental 2'),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('batch, ED dan desimal ditampilkan', (tester) async {
      useTabletSurface(tester);
      final id = await postedDistribution();
      await pumpDetail(tester, id);

      expect(find.textContaining('B-OLD'), findsWidgets);
      expect(find.textContaining('A-NEW'), findsWidgets);
      expect(find.textContaining('tanpa batch'), findsWidgets);
      expect(find.textContaining('2 box'), findsWidgets);
      // Milli-units are never shown (Q-6).
      expect(find.textContaining('2000'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('alasan override FEFO ditampilkan', (tester) async {
      useTabletSurface(tester);
      final id = await draft();
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.newBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        fefoOverrideReason: 'Diminta dokter untuk ED panjang',
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);
      await pumpDetail(tester, id);

      expect(
        find.byKey(DistributionFefoOverrideBadge.badgeKey),
        findsOneWidget,
      );
      expect(
        find.textContaining('Diminta dokter untuk ED panjang'),
        findsOneWidget,
      );
      expect(find.textContaining('1 di luar FEFO'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('tidak ada kontrol edit, hapus atau posting', (tester) async {
      useTabletSurface(tester);
      final id = await postedDistribution();
      await pumpDetail(tester, id);

      // Absent, not disabled: G-S2 makes a posted document read-only permanently, and a
      // screen that renders an action the use case would refuse has to be kept in step
      // with the refusal by hand.
      expect(find.byKey(DistributionFormPage.postKey), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.text('Posting Distribusi'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('badge historis tampil untuk ruangan yang dinonaktifkan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await postedDistribution();
      await context.deactivate('rooms', fixture.roomOne.id);
      await pumpDetail(tester, id);

      // §32: the document stays fully readable, and the badge explains why the room no
      // longer appears in the pickers.
      expect(find.byKey(HistoricalMasterBadge.badgeKey), findsWidgets);
      expect(
        find.byKey(DistributionDetailPage.roomKeyFor(fixture.roomOne.id)),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('dokumen cabang lain menampilkan pesan netral', (tester) async {
      useTabletSurface(tester);
      final foreign = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
        actorUserId: fixture.otherBranchHead.id,
      );
      await pumpDetail(tester, foreign);

      expect(find.byKey(DistributionDetailPage.notFoundKey), findsOneWidget);
      await disposeWidget(tester);
    });
  });
}

/// The remove button of one line on the form.
Key _removeKeyFor(String lineId) => ValueKey('distributionLineRemove-$lineId');
