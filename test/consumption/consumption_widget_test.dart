import 'package:aish_warehouse/app/routes.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/widgets/quantity_field.dart';
import 'package:aish_warehouse/features/consumption/presentation/pages/branch_consumption_list_page.dart';
import 'package:aish_warehouse/features/consumption/presentation/pages/consumption_detail_page.dart';
import 'package:aish_warehouse/features/consumption/presentation/pages/consumption_form_page.dart';
import 'package:aish_warehouse/features/consumption/presentation/pages/consumption_list_page.dart';
import 'package:aish_warehouse/features/consumption/presentation/providers/consumption_providers.dart';
import 'package:aish_warehouse/features/consumption/presentation/widgets/consumption_badges.dart';
import 'package:aish_warehouse/features/consumption/presentation/widgets/consumption_candidate_picker.dart';
import 'package:aish_warehouse/features/consumption/presentation/widgets/consumption_filters.dart';
import 'package:aish_warehouse/features/inventory/presentation/widgets/stock_card_list.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The Pemakaian screens (§45).
///
/// Pumped through the **real router** wherever a document id is involved, because typing
/// the URL is the attack and pumping a page directly bypasses the layer under test. The
/// list and picker tests pump their widget with the acting user injected, which is what
/// exercises the provider scoping.
///
/// The absences get as much attention as the presences, and they are the interesting half:
/// an expired batch that is *absent* from the picker is a stronger guarantee than one that
/// is present and disabled, and a branch history with *no* write control is a stronger
/// guarantee than one whose buttons happen to be greyed out.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// Pins the feature clock, so every expiry badge is judged against the fixture's own
  /// instant rather than against the wall clock (T-7).
  final overrides = <Override>[
    consumptionClockProvider.overrideWithValue(() => nowUtc),
  ];

  Future<String> draft({String? roomId, MasterUser? actor}) =>
      createConsumptionDraft(
        context,
        fixture,
        roomId: roomId ?? fixture.roomOne.id,
        nowUtc: nowUtc,
        actorUserId: (actor ?? fixture.nurse).id,
      );

  Future<String> postedDocument({MasterUser? actor}) async {
    final nurse = actor ?? fixture.nurse;
    final id = await draft(actor: nurse);
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.expiryItem.id,
      batchId: fixture.validBatch.id,
      qty: '1.5',
      nowUtc: nowUtc,
      actorUserId: nurse.id,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.plainItem.id,
      qty: '2.25',
      nowUtc: nowUtc,
      actorUserId: nurse.id,
    );
    await context.postConsumption().call(
      actorUserId: nurse.id,
      consumptionId: id,
    );
    return id;
  }

  group('daftar Perawat', () {
    testWidgets('empty state dan tombol buat', (tester) async {
      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionListPage.emptyKey), findsOneWidget);
      expect(find.byKey(ConsumptionListPage.createKey), findsOneWidget);
      expect(find.text('Catat Pemakaian'), findsWidgets);
      // No approval wording anywhere (§7).
      expect(find.text('Ajukan'), findsNothing);
      expect(find.text('Setujui'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('draft dan posted milik sendiri tampil', (tester) async {
      final draftId = await draft();
      final postedId = await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      expect(
        find.byKey(ConsumptionListPage.rowKeyFor(draftId)),
        findsOneWidget,
      );
      expect(
        find.byKey(ConsumptionListPage.rowKeyFor(postedId)),
        findsOneWidget,
      );
      expect(find.text('Draft'), findsWidgets);
      expect(find.text('Sudah Diposting'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('draft perawat lain tidak tampil', (tester) async {
      final theirs = await draft(actor: fixture.otherNurse);
      final mine = await draft();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionListPage.rowKeyFor(mine)), findsOneWidget);
      expect(
        find.byKey(ConsumptionListPage.rowKeyFor(theirs)),
        findsNothing,
        reason: 'Draft perawat lain bukan milik akun ini (§14).',
      );
      await disposeWidget(tester);
    });

    testWidgets('filter ruangan hanya menampilkan ruangan cabang', (
      tester,
    ) async {
      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionRoomChips.chipsKey), findsOneWidget);
      expect(
        find.byKey(ConsumptionRoomChips.chipKeyFor(fixture.roomOne.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(ConsumptionRoomChips.chipKeyFor(fixture.roomTwo.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(ConsumptionRoomChips.chipKeyFor(fixture.otherBranchRoom.id)),
        findsNothing,
        reason: 'Ruangan cabang lain tidak boleh muncul (G-R1).',
      );
      await disposeWidget(tester);
    });

    testWidgets('filter ruangan menyaring daftar', (tester) async {
      final one = await draft(roomId: fixture.roomOne.id);
      final two = await draft(roomId: fixture.roomTwo.id);

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      await tester.tap(
        find.byKey(ConsumptionRoomChips.chipKeyFor(fixture.roomTwo.id)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ConsumptionListPage.rowKeyFor(two)), findsOneWidget);
      expect(find.byKey(ConsumptionListPage.rowKeyFor(one)), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('filter status menyaring daftar', (tester) async {
      final draftId = await draft();
      final postedId = await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      await tester.tap(
        find.byKey(ConsumptionStatusChips.chipKeyFor(ConsumptionStatus.posted)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ConsumptionListPage.rowKeyFor(postedId)),
        findsOneWidget,
      );
      expect(find.byKey(ConsumptionListPage.rowKeyFor(draftId)), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('pencarian menyaring daftar', (tester) async {
      final id = await draft();
      final other = await draft(roomId: fixture.roomTwo.id);
      final docNumber = (await context.consumptions.getById(id))!.docNumber;

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      await tester.enterText(
        find.byKey(ConsumptionListPage.searchKey),
        docNumber,
      );
      await tester.pump(ConsumptionListPage.searchDebounce);
      await tester.pumpAndSettle();

      expect(find.byKey(ConsumptionListPage.rowKeyFor(id)), findsOneWidget);
      expect(find.byKey(ConsumptionListPage.rowKeyFor(other)), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('kartu dashboard perawat tampil', (tester) async {
      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.nurse,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      // Both G-E6 counters, including the red one the picker can never offer.
      expect(find.text('Draft belum diposting'), findsOneWidget);
      expect(find.text('Pemakaian hari ini'), findsOneWidget);
      expect(find.text('Stok ruangan menipis'), findsOneWidget);
      expect(find.text('Segera kedaluwarsa'), findsOneWidget);
      expect(find.text('Kedaluwarsa'), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('peran tidak berwenang tidak melihat daftar', (tester) async {
      await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const ConsumptionListPage(),
        overrides: overrides,
      );

      // The provider yields nothing for a non-nurse, so the empty state is what shows.
      expect(find.byKey(ConsumptionListPage.emptyKey), findsOneWidget);
      expect(find.byKey(ConsumptionListPage.listKey), findsNothing);
      await disposeWidget(tester);
    });
  });

  group('form', () {
    Future<void> pumpForm(WidgetTester tester, String id) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$id/edit',
        overrides: overrides,
      );
    }

    testWidgets('header menampilkan ruangan, perawat dan waktu GMT+8', (
      tester,
    ) async {
      final id = await draft();
      await pumpForm(tester, id);

      expect(find.byKey(ConsumptionFormPage.headerKey), findsOneWidget);
      expect(find.textContaining(fixture.roomOne.code), findsWidgets);
      expect(find.textContaining(fixture.nurse.fullName), findsWidgets);
      expect(find.textContaining('GMT+8'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('empty state dan tombol tambah', (tester) async {
      final id = await draft();
      await pumpForm(tester, id);

      expect(find.byKey(ConsumptionFormPage.emptyKey), findsOneWidget);
      expect(find.byKey(ConsumptionFormPage.addKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('tidak ada field pasien di mana pun', (tester) async {
      final id = await draft();
      await pumpForm(tester, id);

      // Asserted against every input's **label**, not against the prose on the screen:
      // the note field's own helper text says *"Jangan mencantumkan data pasien"*, which is
      // the screen telling the nurse the rule rather than a field inviting a breach of it.
      // What §9 forbids is a place to *put* patient data.
      final labels = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.decoration?.labelText ?? '')
          .toList(growable: false);
      expect(labels, isNotEmpty, reason: 'Form seharusnya punya input.');
      for (final word in const [
        'asien',
        'Rekam',
        'rekam',
        'RM',
        'iagnos',
        'indakan',
        'atient',
      ]) {
        for (final label in labels) {
          expect(
            label,
            isNot(contains(word)),
            reason: 'Label "$label" bernuansa data pasien: $word (§9).',
          );
        }
      }
      // And the two labels that *are* there say what they are about: stock.
      expect(labels, contains('Catatan umum (opsional)'));
      await disposeWidget(tester);
    });

    testWidgets('tidak ada aksi persetujuan maupun tujuan', (tester) async {
      final id = await draft();
      await pumpForm(tester, id);

      expect(find.text('Ajukan'), findsNothing);
      expect(find.text('Setujui'), findsNothing);
      expect(find.text('Menunggu Persetujuan'), findsNothing);
      expect(find.textContaining('Lokasi tujuan'), findsNothing);
      expect(find.textContaining('Ruangan tujuan'), findsNothing);
      // The one action there is.
      expect(find.text('Posting Pemakaian'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('picker menawarkan stok ruangan, tanpa batch kedaluwarsa', (
      tester,
    ) async {
      final id = await draft();
      await pumpForm(tester, id);

      await tester.tap(find.byKey(ConsumptionFormPage.addKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ConsumptionCandidatePicker.sheetKey), findsOneWidget);
      // The valid, the near-expiry and the one expiring today are all offered.
      expect(
        find.byKey(
          ConsumptionCandidatePicker.tileKeyFor(
            '${fixture.expiryItem.id}|${fixture.validBatch.id}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ConsumptionCandidatePicker.tileKeyFor(
            '${fixture.expiryItem.id}|${fixture.nearBatch.id}',
          ),
        ),
        findsOneWidget,
      );
      // The expired one is **absent**, not disabled (G-E7).
      expect(
        find.byKey(
          ConsumptionCandidatePicker.tileKeyFor(
            '${fixture.expiryItem.id}|${fixture.expiredBatch.id}',
          ),
        ),
        findsNothing,
      );
      // And so is the batch with no room stock.
      expect(
        find.byKey(
          ConsumptionCandidatePicker.tileKeyFor(
            '${fixture.expiryItem.id}|${fixture.emptyBatch.id}',
          ),
        ),
        findsNothing,
      );
      await disposeWidget(tester);
    });

    testWidgets('picker menandai batch near-expiry dengan badge oranye', (
      tester,
    ) async {
      final id = await draft();
      await pumpForm(tester, id);

      await tester.tap(find.byKey(ConsumptionFormPage.addKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ConsumptionExpiryBadge.nearExpiryKey),
        findsWidgets,
        reason: 'G-E6 meminta badge "Segera kedaluwarsa".',
      );
      // …and the notice that says it should be used first, not avoided (§17).
      expect(find.byKey(ConsumptionNearExpiryNotice.noticeKey), findsWidgets);
      // Never a red badge here: the picker cannot return an expired position at all.
      expect(find.byKey(ConsumptionExpiryBadge.expiredKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('picker menampilkan barang tanpa ED tanpa pemilih batch', (
      tester,
    ) async {
      final id = await draft();
      await pumpForm(tester, id);

      await tester.tap(find.byKey(ConsumptionFormPage.addKey));
      await tester.pumpAndSettle();

      final tile = find.byKey(
        ConsumptionCandidatePicker.tileKeyFor('${fixture.plainItem.id}|'),
      );
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('tanpa batch')),
        findsNothing,
      );
      expect(
        find.descendant(of: tile, matching: find.textContaining('tanpa batch')),
        findsOneWidget,
      );
      await disposeWidget(tester);
    });

    testWidgets('menambah baris desimal dan menampilkan sisa', (tester) async {
      final id = await draft();
      await pumpForm(tester, id);

      await tester.tap(find.byKey(ConsumptionFormPage.addKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ConsumptionCandidatePicker.tileKeyFor(
            '${fixture.expiryItem.id}|${fixture.validBatch.id}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ConsumptionCandidatePicker.qtyKey),
        '2.375',
      );
      await tester.tap(find.byKey(ConsumptionCandidatePicker.addKey));
      await tester.pumpAndSettle();

      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId =
          lines['${fixture.expiryItem.id}|${fixture.validBatch.id}']!;
      expect(
        find.byKey(ConsumptionFormPage.qtyFieldKeyFor(lineId)),
        findsOneWidget,
      );
      // 5.5 − 2.375 = 3.125, exact (Q-2), and never in milli-units.
      expect(find.textContaining('3.125'), findsWidgets);
      expect(find.textContaining('3125'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets(
      'posisi yang sudah dipilih ditandai, tidak dapat dipilih lagi',
      (tester) async {
        final id = await draft();
        await addConsumptionPosition(
          context,
          fixture,
          consumptionId: id,
          itemId: fixture.plainItem.id,
          qty: '1',
          nowUtc: nowUtc,
        );
        await pumpForm(tester, id);

        await tester.tap(find.byKey(ConsumptionFormPage.addKey));
        await tester.pumpAndSettle();

        final tile = find.byKey(
          ConsumptionCandidatePicker.tileKeyFor('${fixture.plainItem.id}|'),
        );
        expect(
          find.descendant(of: tile, matching: find.text('Sudah dipilih')),
          findsOneWidget,
        );
        final listTile = tester.widget<ListTile>(tile);
        expect(listTile.enabled, isFalse);
        await disposeWidget(tester);
      },
    );

    testWidgets('sisa setelah pemakaian mengikuti ketikan', (tester) async {
      // §28 asks the screen to show what stays in the room. A remainder computed once per
      // parent rebuild would show the figure from before the nurse started typing, which is
      // the one number they are deciding against.
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId =
          lines['${fixture.expiryItem.id}|${fixture.validBatch.id}']!;

      await pumpForm(tester, id);
      // The room holds 5.5, and the line asks for 1.
      expect(
        find.textContaining('Sisa setelah pemakaian: 4.5'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(ConsumptionFormPage.qtyFieldKeyFor(lineId)),
        '2.375',
      );
      await tester.pump();
      // 5.5 − 2.375 = 3.125, exact and live (Q-2).
      expect(
        find.textContaining('Sisa setelah pemakaian: 3.125'),
        findsOneWidget,
      );

      // And a quantity beyond the shelf says so rather than clamping to a reassuring zero.
      await tester.enterText(
        find.byKey(ConsumptionFormPage.qtyFieldKeyFor(lineId)),
        '9',
      );
      await tester.pump();
      expect(find.textContaining('melebihi saldo ruangan'), findsOneWidget);
      expect(find.textContaining('Sisa setelah pemakaian'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('menghapus baris', (tester) async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId = lines['${fixture.plainItem.id}|']!;

      await pumpForm(tester, id);
      expect(
        find.byKey(ConsumptionFormPage.removeKeyFor(lineId)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ConsumptionFormPage.removeKeyFor(lineId)));
      await tester.pumpAndSettle();

      expect(await context.consumptionLineCount(id), 0);
      expect(find.byKey(ConsumptionFormPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('pending input di-flush sebelum konfirmasi', (tester) async {
      // §29's order: the dialog must describe what is *stored*, not what was handed to the
      // method. A quantity typed and not saved would otherwise be confirmed unseen.
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId = lines['${fixture.plainItem.id}|']!;

      await pumpForm(tester, id);
      await tester.enterText(
        find.byKey(ConsumptionFormPage.qtyFieldKeyFor(lineId)),
        '3.5',
      );
      await tester.tap(find.byKey(ConsumptionFormPage.postKey));
      await tester.pumpAndSettle();

      // Stored before the dialog opened.
      final rows = await context.consumptionLineRows(id);
      expect(rows[lineId]!['qty'], Quantity.parse('3.5').milliUnits);
      expect(find.byKey(ConsumptionFormPage.confirmKey), findsOneWidget);
      await tester.tap(find.byKey(ConsumptionFormPage.confirmCancelKey));
      await tester.pumpAndSettle();
      await disposeWidget(tester);
    });

    testWidgets('baris tidak valid difokuskan dan tidak diposting', (
      tester,
    ) async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId = lines['${fixture.plainItem.id}|']!;

      await pumpForm(tester, id);
      // Cleared: not a quantity at all, which is the user's to fix.
      await tester.enterText(
        find.byKey(ConsumptionFormPage.qtyFieldKeyFor(lineId)),
        '',
      );
      await tester.tap(find.byKey(ConsumptionFormPage.postKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ConsumptionFormPage.confirmKey), findsNothing);
      expect(find.textContaining('belum valid'), findsOneWidget);
      expect(await context.consumptionStatusOf(id), 'draft');
      expect(await context.consumptionMovementCount(id), 0);
      await disposeWidget(tester);
    });

    testWidgets('dialog konfirmasi menyebut ruangan, posisi dan finalitas', (
      tester,
    ) async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      await pumpForm(tester, id);
      await tester.tap(find.byKey(ConsumptionFormPage.postKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ConsumptionFormPage.confirmKey), findsOneWidget);
      expect(find.textContaining('1 posisi'), findsOneWidget);
      expect(find.textContaining(fixture.roomOne.code), findsWidgets);
      expect(find.textContaining('Tidak ada lokasi tujuan'), findsOneWidget);
      // §29's two sentences, verbatim.
      expect(find.text(ConsumptionFinalityNotice.stockMessage), findsOneWidget);
      expect(
        find.text(ConsumptionFinalityNotice.finalityMessage),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ConsumptionFormPage.confirmCancelKey));
      await tester.pumpAndSettle();
      await disposeWidget(tester);
    });

    testWidgets('membatalkan dialog tidak memposting', (tester) async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      await pumpForm(tester, id);
      await tester.tap(find.byKey(ConsumptionFormPage.postKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ConsumptionFormPage.confirmCancelKey));
      await tester.pumpAndSettle();

      expect(await context.consumptionStatusOf(id), 'draft');
      expect(await context.consumptionMovementCount(id), 0);
      await disposeWidget(tester);
    });

    testWidgets('posting sukses membuka detail read-only', (tester) async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1.25',
        nowUtc: nowUtc,
      );

      await pumpForm(tester, id);
      await tester.tap(find.byKey(ConsumptionFormPage.postKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ConsumptionFormPage.confirmAcceptKey));
      await tester.pumpAndSettle();

      expect(await context.consumptionStatusOf(id), 'posted');
      expect(await context.consumptionMovementCount(id), 1);
      // And the screen that follows is the read-only detail, with no post button on it.
      expect(find.byKey(ConsumptionDetailPage.detailKey), findsOneWidget);
      expect(find.byKey(ConsumptionFormPage.postKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('stok yang berubah memberi pesan §29', (tester) async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '10.5',
        nowUtc: nowUtc,
      );

      // A second document drains the position after this one was assembled.
      final rival = await draft(actor: fixture.otherNurse);
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: rival,
        itemId: fixture.plainItem.id,
        qty: '10.5',
        nowUtc: nowUtc,
        actorUserId: fixture.otherNurse.id,
      );
      await context.postConsumption().call(
        actorUserId: fixture.otherNurse.id,
        consumptionId: rival,
      );

      await pumpForm(tester, id);
      await tester.tap(find.byKey(ConsumptionFormPage.postKey));
      await tester.pumpAndSettle();

      // The stored quantity no longer fits the shelf, and the form says so **before** the
      // confirmation dialog: confirming a posting that is already doomed teaches people to
      // dismiss dialogs (§29).
      expect(find.byKey(ConsumptionFormPage.confirmKey), findsNothing);
      expect(
        find.textContaining(ConsumptionFinalityNotice.stockChangedMessage),
        findsOneWidget,
      );
      expect(await context.consumptionStatusOf(id), 'draft');
      expect(await context.consumptionMovementCount(id), 0);
      await disposeWidget(tester);
    });

    testWidgets('baris kedaluwarsa memblokir posting dengan penjelasan', (
      tester,
    ) async {
      final id = await draft();
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.nearBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      // Eleven days on, the near-expiry batch is past its date.
      final later = nowUtc.add(const Duration(days: 11));
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$id/edit',
        overrides: [consumptionClockProvider.overrideWithValue(() => later)],
      );

      expect(find.byKey(ConsumptionFormPage.expiredLineKey), findsOneWidget);
      expect(find.byKey(ConsumptionExpiryBadge.expiredKey), findsWidgets);
      expect(find.textContaining('pemusnahan'), findsWidgets);

      await tester.tap(find.byKey(ConsumptionFormPage.postKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ConsumptionFormPage.confirmKey), findsNothing);
      expect(await context.consumptionStatusOf(id), 'draft');
      await disposeWidget(tester);
    });
  });

  group('detail posted', () {
    testWidgets('menampilkan ruangan, aktor, batch, ED dan desimal', (
      tester,
    ) async {
      final id = await postedDocument();

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$id',
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionDetailPage.detailKey), findsOneWidget);
      expect(find.textContaining(fixture.roomOne.code), findsWidgets);
      expect(find.textContaining(fixture.nurse.fullName), findsWidgets);
      expect(find.textContaining(fixture.validBatch.batchNo), findsWidgets);
      expect(find.textContaining('1.5'), findsWidgets);
      expect(find.textContaining('2.25'), findsWidgets);
      // Never milli-units on a screen (Q-4).
      expect(find.textContaining('1500'), findsNothing);
      expect(find.textContaining('2250'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('menampilkan kartu stok pergerakan dokumen', (tester) async {
      // Until the Milestone 8 hardening this section printed the raw codes `consumption` and
      // `CONS`, which told a developer what to grep for and a nurse nothing. It now renders
      // the movements through the shared presenter.
      final id = await postedDocument();

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$id',
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionDetailPage.ledgerKey), findsOneWidget);
      expect(find.byKey(StockCardList.listKey), findsOneWidget);
      // Two lines were posted, so two ledger rows.
      final movements = await context.consumptionMovements(id);
      expect(movements, hasLength(2));
      expect(find.text('Pemakaian'), findsNWidgets(2));
      // The document reference reads as a document, not as a database code.
      final docNumber = await context.consumptionDocNumber(id);
      for (final movementId in await context.consumptionMovementIds(id)) {
        expect(
          tester
              .widget<Text>(
                find.byKey(StockCardList.documentKeyFor(movementId)),
              )
              .data,
          'dokumen Pemakaian · $docNumber',
          reason: 'Nomor dokumen, bukan UUID mentah, dan label bukan kode DB.',
        );
      }
      // The raw enum values must not reach the screen any more.
      expect(find.textContaining('movement_type'), findsNothing);
      expect(find.textContaining('ref_doc_type'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('total per unit tidak dijumlahkan lintas unit', (tester) async {
      final id = await postedDocument();

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$id',
        overrides: overrides,
      );

      // `1.5 ampul` and `2.25 box`, never `3.75` of anything.
      expect(find.textContaining('1.5 ampul'), findsWidgets);
      expect(find.textContaining('2.25 box'), findsWidgets);
      expect(find.textContaining('3.75'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('tidak ada kontrol edit, hapus maupun posting', (tester) async {
      final id = await postedDocument();

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$id',
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionFormPage.postKey), findsNothing);
      expect(find.byKey(ConsumptionFormPage.addKey), findsNothing);
      expect(
        find.byType(QuantityField),
        findsNothing,
        reason: 'Tidak ada kuantitas yang dapat diedit pada detail (§30).',
      );
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.text('Posting Pemakaian'), findsNothing);
      expect(find.text('Setujui'), findsNothing);
      // The one affordance the hardening adds is a *read* — opening a kartu stok — so it is
      // present, and it changes nothing.
      expect(find.text('Kartu stok posisi ini'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('ringkasan menyebut efek stok tanpa tujuan', (tester) async {
      final id = await postedDocument();

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$id',
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionDetailPage.summaryKey), findsOneWidget);
      expect(find.textContaining('tidak ada lokasi tujuan'), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('riwayat Kepala Cabang', () {
    testWidgets('menampilkan posted cabang dengan nama perawat', (
      tester,
    ) async {
      final id = await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const BranchConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionListPage.rowKeyFor(id)), findsOneWidget);
      expect(
        find.textContaining(fixture.nurse.fullName),
        findsWidgets,
        reason: '§31 meminta nama Perawat pada baris riwayat.',
      );
      await disposeWidget(tester);
    });

    testWidgets('draft tidak tampil', (tester) async {
      final draftId = await draft();
      final postedId = await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const BranchConsumptionListPage(),
        overrides: overrides,
      );

      expect(
        find.byKey(ConsumptionListPage.rowKeyFor(postedId)),
        findsOneWidget,
      );
      expect(
        find.byKey(ConsumptionListPage.rowKeyFor(draftId)),
        findsNothing,
        reason: 'Riwayat cabang hanya memuat dokumen posted (§14).',
      );
      await disposeWidget(tester);
    });

    testWidgets('dokumen cabang lain tidak tampil', (tester) async {
      final mine = await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        child: const BranchConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionListPage.rowKeyFor(mine)), findsNothing);
      expect(find.byKey(BranchConsumptionListPage.emptyKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('tidak ada kontrol tulis di mana pun', (tester) async {
      await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const BranchConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionListPage.createKey), findsNothing);
      expect(find.text('Catat Pemakaian'), findsNothing);
      expect(find.text('Posting Pemakaian'), findsNothing);
      expect(find.text('Setujui'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('filter ruangan dan perawat tersedia', (tester) async {
      await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const BranchConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(ConsumptionRoomChips.chipsKey), findsOneWidget);
      expect(find.byKey(ConsumptionNurseChips.chipsKey), findsOneWidget);
      expect(
        find.byKey(ConsumptionNurseChips.chipKeyFor(fixture.nurse.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ConsumptionNurseChips.chipKeyFor(fixture.otherBranchNurse.id),
        ),
        findsNothing,
      );
      // The status chips are deliberately absent: the list is `posted`-only by scope.
      expect(find.byKey(ConsumptionStatusChips.chipsKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('filter perawat menyaring daftar', (tester) async {
      final mine = await postedDocument();
      final theirs = await postedDocument(actor: fixture.otherNurse);

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const BranchConsumptionListPage(),
        overrides: overrides,
      );

      await tester.tap(
        find.byKey(ConsumptionNurseChips.chipKeyFor(fixture.otherNurse.id)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ConsumptionListPage.rowKeyFor(theirs)), findsOneWidget);
      expect(find.byKey(ConsumptionListPage.rowKeyFor(mine)), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('filter tanggal tersedia dan dapat dihapus', (tester) async {
      await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const BranchConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.byKey(BranchConsumptionListPage.dateKey), findsOneWidget);
      expect(find.text('Semua tanggal'), findsOneWidget);
      // Nothing is cleared until something is selected.
      expect(find.byKey(BranchConsumptionListPage.dateClearKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('kartu ringkas cabang tampil', (tester) async {
      await postedDocument();

      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const BranchConsumptionListPage(),
        overrides: overrides,
      );

      expect(find.text('Pemakaian hari ini'), findsOneWidget);
      expect(find.textContaining('Ruangan tertinggi'), findsOneWidget);
      await disposeWidget(tester);
    });
  });
}
