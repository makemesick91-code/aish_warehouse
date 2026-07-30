import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_access_policy.dart';
import 'package:aish_warehouse/features/good_receipt/presentation/providers/good_receipt_providers.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderListenable`, `Refreshable` and `Override` live here rather than in the main
// barrel file in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Read authorization for Good Receipt (§47).
///
/// The assertions come in three layers, because each catches something the others
/// cannot: the **policy** is exercised as a pure function, the **providers** are built
/// against a real database with a real session, and the **routes** are reached by typing
/// the URL — which is the attack, so the test has to type it.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> shippedOrder({String qty = '0.5'}) => shipDeliveryOrderFor(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [simpleAllocation(fixture, qty: qty)],
  );

  Future<String> checkingReceipt() async => startGoodReceiptFor(
    context,
    fixture,
    deliveryOrderId: await shippedOrder(),
    nowUtc: nowUtc,
  );

  Future<String> postedReceipt() async {
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
    return grId;
  }

  /// Reads a stream provider while holding it open.
  ///
  /// `container.read(p.future)` alone opens and immediately closes its own subscription,
  /// so an `autoDispose` provider is torn down before its first emission ever arrives. A
  /// screen holds the provider for as long as it is on screen; this reproduces that
  /// rather than racing it.
  Future<T> readStream<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
    Refreshable<Future<T>> future,
  ) async {
    final subscription = container.listen(provider, (_, _) {});
    try {
      return await container.read(future);
    } finally {
      subscription.close();
    }
  }

  /// A provider graph hanging off the in-memory database, acting as [actor].
  ///
  /// The whole graph hangs off `appDatabaseProvider`, exactly as in the app, so nothing
  /// here is a stub: the scoped queries really run, against real rows.
  Future<ProviderContainer> containerFor(MasterUser actor) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(context.database),
        currentSessionProvider.overrideWith(
          () => FixedSessionController(actor),
        ),
        goodReceiptClockProvider.overrideWithValue(() => nowUtc),
      ],
    );
    addTearDown(container.dispose);
    // Let the session resolve before anything reads it.
    await container.read(currentSessionProvider.future);
    return container;
  }

  group('kebijakan akses', () {
    MasterUser userWith(UserRole role, {String? branchId}) => MasterUser(
      id: 'u-${role.dbValue}',
      fullName: role.label,
      email: '${role.dbValue}@test.local',
      role: role,
      branchId: branchId,
      isActive: true,
    );

    test('hanya Kepala Cabang mencapai layar cabang', () {
      for (final kind in [
        GoodReceiptRouteKind.branchList,
        GoodReceiptRouteKind.branchCreate,
        GoodReceiptRouteKind.branchDocument,
      ]) {
        for (final role in UserRole.values) {
          final granted = GoodReceiptAccessPolicy.forSection(
            user: userWith(role, branchId: 'b-1'),
            kind: kind,
          ).isGranted;
          expect(
            granted,
            role == UserRole.kepalaCabang,
            reason: '${role.dbValue} pada $kind salah dinilai.',
          );
        }
      }
    });

    test('hanya Warehouse mencapai layar warehouse', () {
      for (final kind in [
        GoodReceiptRouteKind.warehouseList,
        GoodReceiptRouteKind.warehouseDocument,
        GoodReceiptRouteKind.warehouseDiscrepancies,
      ]) {
        for (final role in UserRole.values) {
          final granted = GoodReceiptAccessPolicy.forSection(
            user: userWith(role),
            kind: kind,
          ).isGranted;
          expect(
            granted,
            role == UserRole.warehouse,
            reason: '${role.dbValue} pada $kind salah dinilai.',
          );
        }
      }
    });

    test('Kepala Cabang tanpa cabang ditolak', () {
      final access = GoodReceiptAccessPolicy.forSection(
        user: userWith(UserRole.kepalaCabang),
        kind: GoodReceiptRouteKind.branchList,
      );
      expect(access.reason, GoodReceiptAccessDenialReason.noBranch);
    });

    test('akun nonaktif ditolak', () {
      final access = GoodReceiptAccessPolicy.forSection(
        user: const MasterUser(
          id: 'u-1',
          fullName: 'Kepala Cabang',
          email: 'k@test.local',
          role: UserRole.kepalaCabang,
          branchId: 'b-1',
          isActive: false,
        ),
        kind: GoodReceiptRouteKind.branchList,
      );
      expect(access.reason, GoodReceiptAccessDenialReason.role);
    });

    test('tanpa sesi ditolak', () {
      expect(
        GoodReceiptAccessPolicy.forSection(
          user: null,
          kind: GoodReceiptRouteKind.branchList,
        ).reason,
        GoodReceiptAccessDenialReason.noSession,
      );
    });

    test('layar cabang ber-scope cabang, layar warehouse tidak', () {
      expect(
        GoodReceiptAccessPolicy.requiresBranchScope(
          GoodReceiptRouteKind.branchDocument,
        ),
        isTrue,
      );
      expect(
        GoodReceiptAccessPolicy.requiresBranchScope(
          GoodReceiptRouteKind.warehouseDocument,
        ),
        isFalse,
      );
    });

    test('Warehouse hanya boleh melihat GR posted', () {
      expect(
        GoodReceiptAccessPolicy.visibleStatuses(
          GoodReceiptRouteKind.warehouseDocument,
        ),
        {GoodReceiptStatus.posted},
      );
      // A `checking` receipt is a branch head part way through a decision.
      final access = GoodReceiptAccessPolicy.forDocument(
        user: userWith(UserRole.warehouse),
        kind: GoodReceiptRouteKind.warehouseDocument,
        scope: const GoodReceiptAccessScope(
          grId: 'gr-1',
          doId: 'do-1',
          prId: 'pr-1',
          branchId: 'b-1',
          status: GoodReceiptStatus.checking,
        ),
      );
      expect(access.reason, GoodReceiptAccessDenialReason.documentStatus);
    });

    test('cabang melihat checking dan posted', () {
      expect(
        GoodReceiptAccessPolicy.visibleStatuses(
          GoodReceiptRouteKind.branchDocument,
        ),
        {GoodReceiptStatus.checking, GoodReceiptStatus.posted},
      );
    });

    test('dokumen cabang lain menjawab out-of-scope', () {
      final access = GoodReceiptAccessPolicy.forDocument(
        user: userWith(UserRole.kepalaCabang, branchId: 'b-1'),
        kind: GoodReceiptRouteKind.branchDocument,
        scope: const GoodReceiptAccessScope(
          grId: 'gr-1',
          doId: 'do-1',
          prId: 'pr-1',
          branchId: 'b-2',
          status: GoodReceiptStatus.checking,
        ),
      );
      expect(access.reason, GoodReceiptAccessDenialReason.documentOutOfScope);
    });

    test('rute create hanya untuk Surat Jalan shipped cabang sendiri', () {
      GoodReceiptAccess accessFor(
        String branchId,
        DeliveryOrderStatus status,
      ) => GoodReceiptAccessPolicy.forDeliveryOrder(
        user: userWith(UserRole.kepalaCabang, branchId: 'b-1'),
        kind: GoodReceiptRouteKind.branchCreate,
        scope: DeliveryOrderAccessScopeFor(branchId, status).scope,
      );

      expect(accessFor('b-1', DeliveryOrderStatus.shipped).isGranted, isTrue);
      expect(
        accessFor('b-1', DeliveryOrderStatus.preparing).reason,
        GoodReceiptAccessDenialReason.documentStatus,
      );
      expect(
        accessFor('b-1', DeliveryOrderStatus.received).reason,
        GoodReceiptAccessDenialReason.documentStatus,
      );
      expect(
        accessFor('b-2', DeliveryOrderStatus.shipped).reason,
        GoodReceiptAccessDenialReason.documentOutOfScope,
      );
    });

    test('tidak ada layar warehouse yang bersifat tulis', () {
      for (final kind in [
        GoodReceiptRouteKind.warehouseList,
        GoodReceiptRouteKind.warehouseDocument,
        GoodReceiptRouteKind.warehouseDiscrepancies,
      ]) {
        expect(GoodReceiptAccessPolicy.isWriteScreen(kind), isFalse);
      }
    });
  });

  group('scope repository', () {
    test('Kepala Cabang A tidak membaca GR cabang B', () async {
      final grId = await checkingReceipt();

      expect(
        await context.receipts.getForBranch(
          grId: grId,
          branchId: fixture.otherBranch.id,
        ),
        isNull,
      );
      // And the access lookup answers the same way for both "no such receipt" and
      // "somebody else's", so the id cannot be probed.
      expect(
        await context.receipts.findAccessScope(
          grId: grId,
          branchId: fixture.otherBranch.id,
        ),
        isNull,
      );
    });

    test('daftar cabang hanya memuat GR cabang itu', () async {
      await checkingReceipt();

      expect(
        await context.receipts.listForBranch(branchId: fixture.branch.id),
        hasLength(1),
      );
      expect(
        await context.receipts.listForBranch(branchId: fixture.otherBranch.id),
        isEmpty,
      );
    });

    test('pembacaan warehouse menolak GR yang masih checking', () async {
      final grId = await checkingReceipt();

      expect(await context.receipts.getForWarehouse(grId), isNull);
      expect(
        await context.receipts.listForWarehouse(const GoodReceiptFilter()),
        isEmpty,
      );

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

      expect(await context.receipts.getForWarehouse(grId), isNotNull);
    });

    test('warehouse membaca selisih lintas cabang', () async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.single;
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        reason: 'Rusak',
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );

      // Not branch-scoped by design: the central warehouse ships to every branch and its
      // selisih report spans all of them (spec §4.2).
      expect(
        await context.receipts.warehouseDiscrepancies(
          const GoodReceiptFilter(),
        ),
        hasLength(1),
      );
      // And the same query pinned to a branch narrows correctly.
      expect(
        await context.receipts.warehouseDiscrepancies(
          GoodReceiptFilter(branchId: fixture.otherBranch.id),
        ),
        isEmpty,
      );
    });

    test('query cabang membawa predikat SQL, bukan filter Dart', () {
      // Filtering in Dart would look equivalent and would not be: the row would have
      // been read, mapped and possibly cached before being discarded.
      final dao = readCodeOnly('lib/core/db/daos/good_receipt_dao.dart');
      expect(dao, contains('purchaseRequests.branchId.equals(branchId)'));
      expect(dao, contains('goodReceipts.status.isIn('));
    });
  });

  group('penulisan lintas cabang', () {
    test('Kepala Cabang B tidak dapat membuat GR untuk DO cabang A', () async {
      final doId = await shippedOrder();

      await expectLater(
        context.createGoodReceipt().call(
          actorUserId: fixture.otherBranchHead.id,
          deliveryOrderId: doId,
        ),
        throwsA(isA<GoodReceiptBranchMismatchFailure>()),
      );
    });

    test('Kepala Cabang B tidak dapat memutuskan baris GR cabang A', () async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.single;

      await expectLater(
        context.checkGoodReceiptLine().call(
          actorUserId: fixture.otherBranchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: Quantity.parse('0.5'),
        ),
        throwsA(isA<GoodReceiptBranchMismatchFailure>()),
      );
      await expectLater(
        context.rejectGoodReceiptLine().call(
          actorUserId: fixture.otherBranchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          reason: 'Rusak',
        ),
        throwsA(isA<GoodReceiptBranchMismatchFailure>()),
      );
    });

    test('Kepala Cabang B tidak dapat memposting GR cabang A', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      await expectLater(
        context.postGoodReceipt().call(
          actorUserId: fixture.otherBranchHead.id,
          goodReceiptId: grId,
        ),
        throwsA(isA<GoodReceiptBranchMismatchFailure>()),
      );
      expect(await context.goodReceiptStatusOf(grId), 'checking');
    });

    test('Warehouse tidak dapat memutuskan atau memposting', () async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.single;

      for (final attempt in [
        () => context.checkGoodReceiptLine().call(
          actorUserId: fixture.warehouseUser.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: Quantity.parse('0.5'),
        ),
        () => context.rejectGoodReceiptLine().call(
          actorUserId: fixture.warehouseUser.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          reason: 'Rusak',
        ),
        () => context.resetGoodReceiptLine().call(
          actorUserId: fixture.warehouseUser.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
        ),
        () => context.postGoodReceipt().call(
          actorUserId: fixture.warehouseUser.id,
          goodReceiptId: grId,
        ),
      ]) {
        await expectLater(attempt(), throwsA(isA<InvalidReviewerFailure>()));
      }
      expect(await context.goodReceiptStatusOf(grId), 'checking');
    });

    test('use case membaca ulang aktor dari database', () async {
      final grId = await checkingReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.single;
      // The session may still claim the branch head is active; the stored row does not.
      await context.deactivate('users', fixture.branchHead.id);

      await expectLater(
        context.checkGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: Quantity.parse('0.5'),
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test(
      'baris GR cabang lain tidak dapat dialamatkan lewat GR sendiri',
      () async {
        final foreignGr = await checkingReceipt();
        final foreignLine = (await context.receipts.getDetail(
          foreignGr,
        ))!.lines.single;
        final ownGr = await checkingReceipt();

        // A line id from another receipt, aimed at one this actor may touch.
        await expectLater(
          context.checkGoodReceiptLine().call(
            actorUserId: fixture.branchHead.id,
            goodReceiptId: ownGr,
            goodReceiptLineId: foreignLine.id,
            receivedQty: Quantity.parse('0.5'),
          ),
          throwsA(isA<GoodReceiptLineNotFoundFailure>()),
        );
      },
    );
  });

  group('provider ber-scope', () {
    test('provider detail cabang menolak sesi cabang lain', () async {
      final grId = await checkingReceipt();

      final own = await containerFor(fixture.branchHead);
      final other = await containerFor(fixture.otherBranchHead);

      expect(
        await readStream(
          own,
          branchGoodReceiptDetailProvider(grId),
          branchGoodReceiptDetailProvider(grId).future,
        ),
        isNotNull,
      );
      expect(
        await readStream(
          other,
          branchGoodReceiptDetailProvider(grId),
          branchGoodReceiptDetailProvider(grId).future,
        ),
        isNull,
      );
    });

    test('provider detail cabang menolak sesi warehouse', () async {
      final grId = await checkingReceipt();
      final warehouse = await containerFor(fixture.warehouseUser);

      expect(
        await readStream(
          warehouse,
          branchGoodReceiptDetailProvider(grId),
          branchGoodReceiptDetailProvider(grId).future,
        ),
        isNull,
      );
    });

    test('provider warehouse menolak sesi cabang', () async {
      final grId = await postedReceipt();
      final branch = await containerFor(fixture.branchHead);

      expect(
        await readStream(
          branch,
          warehouseGoodReceiptDetailProvider(grId),
          warehouseGoodReceiptDetailProvider(grId).future,
        ),
        isNull,
      );
      expect(
        await readStream(
          branch,
          warehouseGoodReceiptListProvider(null),
          warehouseGoodReceiptListProvider(null).future,
        ),
        isEmpty,
      );
      expect(
        await readStream(
          branch,
          warehouseDiscrepancyQueueProvider(null),
          warehouseDiscrepancyQueueProvider(null).future,
        ),
        isEmpty,
      );
    });

    test('provider antrean cabang kosong untuk peran tanpa cabang', () async {
      await shippedOrder();
      final warehouse = await containerFor(fixture.warehouseUser);

      expect(
        await readStream(
          warehouse,
          branchAwaitingDeliveriesProvider(null),
          branchAwaitingDeliveriesProvider(null).future,
        ),
        isEmpty,
      );
    });

    test('provider perawat kosong pada setiap daftar', () async {
      await postedReceipt();
      final nurse = await containerFor(fixture.nurse);

      expect(
        await readStream(
          nurse,
          branchGoodReceiptListProvider(null),
          branchGoodReceiptListProvider(null).future,
        ),
        isEmpty,
      );
      expect(
        await readStream(
          nurse,
          branchAwaitingDeliveriesProvider(null),
          branchAwaitingDeliveriesProvider(null).future,
        ),
        isEmpty,
      );
      expect(
        await readStream(
          nurse,
          warehouseGoodReceiptListProvider(null),
          warehouseGoodReceiptListProvider(null).future,
        ),
        isEmpty,
      );
      expect(
        await readStream(
          nurse,
          warehouseDiscrepancyQueueProvider(null),
          warehouseDiscrepancyQueueProvider(null).future,
        ),
        isEmpty,
      );
    });

    test('pergantian sesi tidak menyajikan cache sesi sebelumnya', () async {
      final grId = await checkingReceipt();

      // Two containers rather than one mutated session: `autoDispose` plus the acting
      // providers is what makes the second read re-run, and building them separately is
      // how a stale cache entry would show up.
      final first = await containerFor(fixture.branchHead);
      expect(
        await readStream(
          first,
          branchGoodReceiptDetailProvider(grId),
          branchGoodReceiptDetailProvider(grId).future,
        ),
        isNotNull,
      );

      final second = await containerFor(fixture.otherBranchHead);
      expect(
        await readStream(
          second,
          branchGoodReceiptDetailProvider(grId),
          branchGoodReceiptDetailProvider(grId).future,
        ),
        isNull,
      );
    });
  });

  group('URL langsung', () {
    testWidgets('perawat tidak dapat membuka daftar Penerimaan', (
      tester,
    ) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '/receipts',
        overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
      );

      // The synchronous redirect sends a nurse home rather than rendering the section at
      // all, so the title never appears.
      expect(find.text('Penerimaan'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('Warehouse tidak dapat membuka daftar Penerimaan cabang', (
      tester,
    ) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/receipts',
        overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.text('Penerimaan'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('Kepala Cabang lain tidak membocorkan data GR', (tester) async {
      useTabletSurface(tester);
      final grId = await checkingReceipt();
      final receipt = await context.receipts.getById(grId);
      final order = await context.deliveries.getById(receipt!.doId);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '/receipts/$grId',
        overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      // Nothing about the document reaches the tree: not its number, not the shipment's,
      // not the branch, not the item, not a quantity.
      expect(find.textContaining(receipt.docNumber), findsNothing);
      expect(find.textContaining(order!.docNumber), findsNothing);
      expect(find.textContaining(fixture.branch.name), findsNothing);
      expect(find.textContaining(fixture.simpleItem.name), findsNothing);
      expect(find.textContaining(fixture.simpleItem.sku), findsNothing);
      expect(find.textContaining('0.5'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('Warehouse tidak dapat membuka GR yang masih checking', (
      tester,
    ) async {
      useTabletSurface(tester);
      final grId = await checkingReceipt();
      final receipt = await context.receipts.getById(grId);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/good-receipts/$grId',
        overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(find.textContaining(receipt!.docNumber), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('rute create menolak Surat Jalan cabang lain', (tester) async {
      useTabletSurface(tester);
      final doId = await shippedOrder();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '/receipts/new/$doId',
        overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      // And no receipt was created for it either — a refused route writes nothing.
      expect(await context.goodReceiptCountFor(doId), 0);

      await disposeWidget(tester);
    });

    testWidgets('rute create menolak Surat Jalan preparing', (tester) async {
      useTabletSurface(tester);
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '0.5')],
      );

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/receipts/new/$doId',
        overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(await context.goodReceiptCountFor(doId), 0);

      await disposeWidget(tester);
    });

    testWidgets('Kepala Cabang tidak dapat membuka antrean selisih warehouse', (
      tester,
    ) async {
      useTabletSurface(tester);
      await postedReceipt();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/warehouse/good-receipt-discrepancies',
        overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.text('Selisih GR dari Cabang'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('id yang tidak ada ditolak seperti dokumen cabang lain', (
      tester,
    ) async {
      useTabletSurface(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/receipts/tidak-ada',
        overrides: [goodReceiptClockProvider.overrideWithValue(() => nowUtc)],
      );

      // One answer for "no such receipt" and for "somebody else's": telling them apart
      // would let anyone with the app enumerate which ids are real.
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      await disposeWidget(tester);
    });
  });

  group('immutabilitas dokumen final', () {
    test('GR posted tidak dapat diubah lewat jalur mana pun', () async {
      final grId = await postedReceipt();
      final line = (await context.receipts.getDetail(grId))!.lines.single;
      final before = await context.goodReceiptLineRows(grId);

      for (final attempt in [
        () => context.checkGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: Quantity.zero(),
        ),
        () => context.rejectGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          reason: 'Rusak',
        ),
        () => context.resetGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
        ),
        () => context.postGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
        ),
      ]) {
        await expectLater(attempt(), throwsA(isA<AppFailure>()));
      }

      expect(await context.goodReceiptLineRows(grId), before);
      expect(await context.goodReceiptStatusOf(grId), 'posted');
    });

    test('baris rejected tidak dapat dihapus lewat repository', () {
      // Asserted against the source, because a method that exists will eventually be
      // called: there is no delete on this document at all.
      final repository = readCodeOnly(
        'lib/features/good_receipt/domain/repositories/'
        'good_receipt_repository.dart',
      );
      final dao = readCodeOnly('lib/core/db/daos/good_receipt_dao.dart');

      for (final forbidden in ['delete', 'softDelete', 'remove']) {
        expect(
          repository.toLowerCase().contains(forbidden.toLowerCase()),
          isFalse,
          reason: 'Repository menawarkan operasi $forbidden.',
        );
      }
      expect(dao.contains('DELETE FROM'), isFalse);
    });
  });

  group('penjaga rute bukan satu-satunya pertahanan', () {
    test('provider dan repository memeriksa peran serta cabang sendiri', () {
      final providers = readCodeOnly(
        'lib/features/good_receipt/presentation/providers/'
        'good_receipt_providers.dart',
      );

      // Every scoped provider asks the acting user afresh, so a screen reached by any
      // other means still reads nothing it should not.
      expect(providers, contains('actingBranchIdProvider'));
      expect(providers, contains('actingRoleProvider'));
      expect(
        'UserRole.kepalaCabang'.allMatches(providers).length,
        greaterThanOrEqualTo(3),
      );
      expect(
        'UserRole.warehouse'.allMatches(providers).length,
        greaterThanOrEqualTo(3),
      );
    });

    test('halaman tidak memakai baca tanpa scope', () {
      for (final file in dartFilesUnder(
        'lib/features/good_receipt/presentation',
      )) {
        final code = readCodeOnly(file);
        for (final unscoped in [
          '.getDetail(',
          '.summaryById(',
          '.listReceipts(',
          '.lineReferences(',
        ]) {
          expect(
            code.contains(unscoped),
            isFalse,
            reason: '$file memakai baca tanpa scope ($unscoped).',
          );
        }
      }
    });
  });
}

/// A Delivery Order access scope, built without a database.
///
/// The create route's policy takes the *shipment's* scope rather than a receipt's, and
/// exercising that as a pure function needs a value rather than a query.
class DeliveryOrderAccessScopeFor {
  const DeliveryOrderAccessScopeFor(this.branchId, this.status);

  final String branchId;
  final DeliveryOrderStatus status;

  DeliveryOrderAccessScope get scope => DeliveryOrderAccessScope(
    doId: 'do-1',
    prId: 'pr-1',
    branchId: branchId,
    status: status,
  );
}
