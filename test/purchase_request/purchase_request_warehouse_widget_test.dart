import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/widgets/historical_master_badge.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/pages/warehouse_purchase_request_detail_page.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/pages/warehouse_purchase_request_list_page.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/providers/purchase_request_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The warehouse screens: the cross-branch inbox and one request's detail.
///
/// The rule these tests exist to pin is G-R3 — *"Warehouse tidak bisa mengubah isi PR —
/// hanya memenuhi (fulfil) atau menolak dengan alasan"*. It is asserted as an absence:
/// no quantity input, no note field, no add-item picker, no remove button anywhere on
/// the screen. An absence is exactly the kind of property that decays silently, which is
/// why it is checked rather than assumed.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  final clockOverride = purchaseRequestClockProvider.overrideWithValue(
    prWednesdayUtc,
  );

  /// Two branches, each with a submitted request.
  Future<
    ({
      PurchaseRequestFixture fixture,
      String ourPrId,
      String theirPrId,
      String ourDocNumber,
      String theirDocNumber,
    })
  >
  queue() async {
    final fixture = await buildPurchaseRequestFixture(
      context,
      now: prWednesdayUtc(),
    );
    final ourCount = await fileOpnameForRoom(
      context,
      roomId: fixture.roomOne.id,
      nurseId: fixture.nurse.id,
      utcNow: prWednesdayUtc(),
    );
    final theirCount = await fileOpnameForRoom(
      context,
      roomId: fixture.otherBranchRoom.id,
      nurseId: fixture.otherBranchNurse.id,
      utcNow: prWednesdayUtc(),
    );

    final ours = await context
        .createPurchaseRequest(clock: prWednesdayUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          selectedOpnameIds: [ourCount],
        );
    await context
        .submitPurchaseRequest(clock: prWednesdayUtc)
        .call(actorUserId: fixture.branchHead.id, prId: ours.id);

    final theirs = await context
        .createPurchaseRequest(clock: prWednesdayUtc)
        .call(
          actorUserId: fixture.otherBranchHead.id,
          selectedOpnameIds: [theirCount],
        );
    await context
        .submitPurchaseRequest(clock: prWednesdayUtc)
        .call(actorUserId: fixture.otherBranchHead.id, prId: theirs.id);

    return (
      fixture: fixture,
      ourPrId: ours.id,
      theirPrId: theirs.id,
      ourDocNumber: ours.docNumber,
      theirDocNumber: theirs.docNumber,
    );
  }

  group('antrean PR masuk', () {
    testWidgets('menampilkan PR submitted dari semua cabang', (tester) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: const WarehousePurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      // Unscoped by branch on purpose: the central warehouse serves the whole clinic
      // group (spec §4.2).
      expect(find.text(setup.ourDocNumber), findsOneWidget);
      expect(find.text(setup.theirDocNumber), findsOneWidget);
      expect(
        find.text(
          '${setup.fixture.branch.code} · ${setup.fixture.branch.name}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '${setup.fixture.otherBranch.code} · '
          '${setup.fixture.otherBranch.name}',
        ),
        findsOneWidget,
      );
      // `findsAtLeastNWidgets`, because the status filter chip carries the same label
      // as the two chips on the rows.
      expect(find.text('Menunggu Diproses'), findsAtLeastNWidgets(2));

      await disposeWidget(tester);
    });

    testWidgets('draft cabang tidak pernah masuk antrean', (tester) async {
      useTabletSurface(tester);
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final draft = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        child: const WarehousePurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      expect(
        find.byKey(WarehousePurchaseRequestListPage.emptyKey),
        findsOneWidget,
      );
      expect(
        find.text(draft.docNumber),
        findsNothing,
        reason: 'Draft bersifat device-authoritative sampai dikirim (G-Y2).',
      );

      await disposeWidget(tester);
    });

    testWidgets('umur permintaan dan jumlah barang ditampilkan', (
      tester,
    ) async {
      final setup = await queue();
      final lineCount = await context.purchaseRequestLineCount(setup.ourPrId);
      useTabletSurface(tester);

      // Two days after the submission, read through the same injected clock the queue
      // uses — so the age column is deterministic (T-7).
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: const WarehousePurchaseRequestListPage(),
        overrides: [
          purchaseRequestClockProvider.overrideWithValue(
            () => prWednesdayUtc().add(const Duration(days: 2)),
          ),
        ],
      );

      expect(find.text('$lineCount barang'), findsWidgets);
      expect(find.text('Umur permintaan 2 hari'), findsWidgets);
      expect(
        find.text('Diminta ${setup.fixture.branchHead.fullName}'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('filter cabang mempersempit antrean', (tester) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: const WarehousePurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      await tester.tap(
        find.byKey(
          ValueKey('warehousePrBranchFilter-${setup.fixture.otherBranch.code}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('warehousePrTile-${setup.theirPrId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('warehousePrTile-${setup.ourPrId}')),
        findsNothing,
      );

      await disposeWidget(tester);
    });

    testWidgets('pencarian nomor dokumen mempersempit antrean', (tester) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: const WarehousePurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      await tester.enterText(
        find.byKey(const ValueKey('warehousePrSearch')),
        setup.theirDocNumber,
      );
      // Past the debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Asserted on the row rather than on the text, because the search field now
      // renders the same string.
      expect(
        find.byKey(ValueKey('warehousePrTile-${setup.theirPrId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('warehousePrTile-${setup.ourPrId}')),
        findsNothing,
      );

      await disposeWidget(tester);
    });

    testWidgets('peran cabang tidak melihat antrean', (tester) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.branchHead,
        child: const WarehousePurchaseRequestListPage(),
        overrides: [clockOverride],
      );

      expect(
        find.byKey(WarehousePurchaseRequestListPage.emptyKey),
        findsOneWidget,
      );
      expect(find.text(setup.theirDocNumber), findsNothing);

      await disposeWidget(tester);
    });
  });

  group('detail PR masuk', () {
    testWidgets('read-only: tidak ada kontrol edit isi PR (G-R3)', (
      tester,
    ) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      // Not one input, anywhere. The line cards are built with `editable: false`, so
      // there is nothing to disable.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Simpan baris'), findsNothing);
      expect(find.byTooltip('Hapus baris'), findsNothing);
      expect(find.textContaining('Tambah barang'), findsNothing);
      expect(find.text('Ubah'), findsNothing);

      // What it does show: what was asked for, and by whom.
      expect(find.text(setup.ourDocNumber), findsOneWidget);
      expect(find.text(setup.fixture.branchHead.fullName), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('submitted menawarkan Mulai Proses saja', (tester) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      expect(
        find.byKey(WarehousePurchaseRequestDetailPage.processButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(WarehousePurchaseRequestDetailPage.rejectButtonKey),
        findsNothing,
        reason:
            'Penolakan hanya dari processing: menolak berarti seseorang sudah '
            'melihatnya.',
      );

      await disposeWidget(tester);
    });

    testWidgets('Mulai Proses memindahkan status ke processing', (
      tester,
    ) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      await tester.tap(
        find.byKey(WarehousePurchaseRequestDetailPage.processButtonKey),
      );
      await tester.pumpAndSettle();

      expect(
        await context.purchaseRequestStatusOf(setup.ourPrId),
        'processing',
      );
      final request = (await context.requests.getById(setup.ourPrId))!;
      expect(request.processedBy, setup.fixture.warehouseUser.id);
      expect(request.processingAt, isNotNull);

      // The screen follows the stream: the reject action is now the one on offer.
      expect(
        find.byKey(WarehousePurchaseRequestDetailPage.rejectButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(WarehousePurchaseRequestDetailPage.processButtonKey),
        findsNothing,
      );

      await disposeWidget(tester);
    });

    testWidgets('dialog penolakan menuntut alasan', (tester) async {
      useTabletSurface(tester);
      final setup = await queue();
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.warehouseUser.id,
            prId: setup.ourPrId,
          );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      await tester.tap(
        find.byKey(WarehousePurchaseRequestDetailPage.rejectButtonKey),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('warehousePrRejectDialog')),
        findsOneWidget,
      );

      final confirm = find.byKey(const ValueKey('warehousePrRejectConfirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      // Whitespace is not a reason — the same rule the use case and the database's
      // `trim(reject_reason) <> ''` CHECK enforce.
      await tester.enterText(
        find.byKey(const ValueKey('warehousePrRejectReason')),
        '   ',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('warehousePrRejectReason')),
        'Stok warehouse habis',
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(await context.purchaseRequestStatusOf(setup.ourPrId), 'rejected');
      final request = (await context.requests.getById(setup.ourPrId))!;
      expect(request.rejectReason, 'Stok warehouse habis');
      expect(request.rejectedBy, setup.fixture.warehouseUser.id);

      await disposeWidget(tester);
    });

    testWidgets('rejected tidak menawarkan aksi apa pun', (tester) async {
      useTabletSurface(tester);
      final setup = await queue();
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.warehouseUser.id,
            prId: setup.ourPrId,
          );
      await context
          .rejectPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.warehouseUser.id,
            prId: setup.ourPrId,
            reason: 'Stok habis',
          );

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      expect(
        find.byKey(WarehousePurchaseRequestDetailPage.processButtonKey),
        findsNothing,
      );
      expect(
        find.byKey(WarehousePurchaseRequestDetailPage.rejectButtonKey),
        findsNothing,
      );
      expect(find.text('Ditolak'), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('detail menampilkan saran vs diminta tanpa milli-unit', (
      tester,
    ) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      final line = (await context.requests.getDetail(setup.ourPrId))!.lines
          .firstWhere((line) => line.itemId == setup.fixture.simpleItem.id);
      expect(line.suggestedQty, Quantity.parse('2.5'));

      expect(find.text('Saran sistem'), findsWidgets);
      expect(find.text('Jumlah diminta'), findsWidgets);
      expect(find.text('2.5 box'), findsWidgets);
      // Q-6: a milli-unit value is never shown to a user.
      expect(find.textContaining('2500'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('opname acuan ditampilkan dengan periode dan ruangan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      final reference = (await context.requests.getDetail(
        setup.ourPrId,
      ))!.opnames.single;
      expect(
        find.text(
          '${setup.fixture.roomOne.code} · ${setup.fixture.roomOne.name}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(reference.periodLabel), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('badge historis tampil setelah cabang dinonaktifkan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final setup = await queue();
      await context.deactivate('branches', setup.fixture.branch.id);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      expect(find.byKey(HistoricalMasterBadge.badgeKey), findsWidgets);
      // The document is still fully readable and still actionable.
      expect(find.text(setup.ourDocNumber), findsOneWidget);
      expect(
        find.byKey(WarehousePurchaseRequestDetailPage.processButtonKey),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('timeline menampilkan pelaku dan waktu GMT+8', (tester) async {
      useTabletSurface(tester);
      final setup = await queue();

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        child: WarehousePurchaseRequestDetailPage(prId: setup.ourPrId),
        overrides: [clockOverride],
      );

      await revealInList(
        tester,
        find.text('Dikirim ke Warehouse'),
        listKey: WarehousePurchaseRequestDetailPage.bodyKey,
      );

      expect(find.text('Dikirim ke Warehouse'), findsOneWidget);
      // 2026-07-29T03:00Z is 11:00 GMT+8, and the zone is spelled out (T-2).
      expect(find.textContaining('29 Jul 2026, 11:00 GMT+8'), findsWidgets);

      await disposeWidget(tester);
    });
  });
}
