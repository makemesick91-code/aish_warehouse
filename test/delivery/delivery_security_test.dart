import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/delivery/domain/services/delivery_order_access_policy.dart';
import 'package:aish_warehouse/features/delivery/presentation/providers/delivery_providers.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
//  and  live here rather than in the main barrel
// file in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// RBAC and IDOR for Delivery Order (§24, spec §3.1, G-R2, G-R3).
///
/// The rules are checked at three levels, because each catches what the others
/// cannot:
///
/// * the **pure policy**, which is what the router, the guard and the providers all
///   ask, so they cannot disagree;
/// * the **providers**, which is where an unscoped read would actually happen — a
///   route guard is not the only defence, and a screen that reached a provider by
///   another path must still see nothing;
/// * the **real router**, navigated by typing the URL, because pumping a page
///   directly with an id bypasses exactly the layer under test.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A shipped document addressed to the fixture's branch.
  Future<String> shippedOrder() async {
    final doId = await prepareDeliveryOrder(
      context,
      fixture,
      nowUtc: nowUtc,
      allocations: [simpleAllocation(fixture, qty: '1')],
    );
    await context.shipDeliveryOrder().call(
      actorUserId: fixture.warehouseUser.id,
      deliveryOrderId: doId,
    );
    return doId;
  }

  /// A `preparing` document — the warehouse's working draft.
  Future<String> preparingOrder() => prepareDeliveryOrder(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [simpleAllocation(fixture, qty: '1')],
  );

  /// Reads an `autoDispose` async provider to completion.
  ///
  /// A bare `read(provider.future)` disposes the provider the moment the future is
  /// awaited — there is no listener keeping it alive — and Riverpod then reports it
  /// was "disposed during loading state". Holding a subscription for the duration is
  /// what a screen does, and it is what these assertions have to do too.
  Future<T> readAsync<T>(
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

  Future<ProviderContainer> containerFor(MasterUser actor) async {
    final container = ProviderContainer(
      overrides: [
        // The whole graph hangs off the database provider, exactly as in the app.
        appDatabaseProvider.overrideWithValue(context.database),
        currentSessionProvider.overrideWith(
          () => FixedSessionController(actor),
        ),
        deliveryClockProvider.overrideWithValue(() => nowUtc),
      ],
    );
    addTearDown(container.dispose);
    // Let the session resolve before anything reads it. Until it does,
    // `actingBranchIdProvider` is null and every branch-scoped provider correctly
    // emits nothing — which would make these assertions pass for the wrong reason.
    await container.read(currentSessionProvider.future);
    return container;
  }

  group('kebijakan akses murni', () {
    test('warehouse mencapai layar warehouse, bukan layar cabang', () {
      final officer = fixture.warehouseUser;

      for (final kind in [
        DeliveryRouteKind.warehouseList,
        DeliveryRouteKind.warehouseCreate,
        DeliveryRouteKind.warehouseDocument,
        DeliveryRouteKind.warehouseDraft,
        DeliveryRouteKind.warehouseWaybill,
      ]) {
        expect(
          DeliveryOrderAccessPolicy.forSection(
            user: officer,
            kind: kind,
          ).isGranted,
          isTrue,
          reason: '$kind seharusnya terbuka untuk Warehouse.',
        );
      }
      for (final kind in [
        DeliveryRouteKind.branchList,
        DeliveryRouteKind.branchDocument,
        DeliveryRouteKind.branchWaybill,
      ]) {
        expect(
          DeliveryOrderAccessPolicy.forSection(
            user: officer,
            kind: kind,
          ).reason,
          DeliveryAccessDenialReason.role,
        );
      }
    });

    test('perawat ditolak dari setiap layar Delivery Order', () {
      // Spec §3.1 gives a nurse no delivery row at all.
      for (final kind in DeliveryRouteKind.values) {
        expect(
          DeliveryOrderAccessPolicy.forSection(
            user: fixture.nurse,
            kind: kind,
          ).isDenied,
          isTrue,
          reason: 'Perawat tidak boleh mencapai $kind.',
        );
      }
    });

    test('super admin tidak mendapat akses tulis maupun baca DO', () async {
      final admin = await context.master.ensureUser(
        email: 'admin@test.local',
        fullName: 'Super Admin Uji',
        role: UserRole.superAdmin,
      );

      // Widening a workflow permission because an account is powerful is exactly
      // the quiet grant G-R4 is about.
      for (final kind in DeliveryRouteKind.values) {
        expect(
          DeliveryOrderAccessPolicy.forSection(
            user: admin,
            kind: kind,
          ).isDenied,
          isTrue,
        );
      }
      // And no write path either.
      await expectLater(
        () => context.createDeliveryOrder().call(
          actorUserId: admin.id,
          purchaseRequestId: fixture.purchaseRequestId,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('akun nonaktif ditolak meski peran benar', () {
      const inactive = MasterUser(
        id: 'u-inactive',
        fullName: 'Petugas Nonaktif',
        email: 'off@test.local',
        role: UserRole.warehouse,
        isActive: false,
      );
      expect(
        DeliveryOrderAccessPolicy.forSection(
          user: inactive,
          kind: DeliveryRouteKind.warehouseList,
        ).reason,
        DeliveryAccessDenialReason.role,
      );
    });

    test('kepala cabang tanpa cabang ditolak', () {
      const noBranch = MasterUser(
        id: 'u-nobranch',
        fullName: 'Kepala Tanpa Cabang',
        email: 'nb@test.local',
        role: UserRole.kepalaCabang,
        isActive: true,
      );
      expect(
        DeliveryOrderAccessPolicy.forSection(
          user: noBranch,
          kind: DeliveryRouteKind.branchList,
        ).reason,
        DeliveryAccessDenialReason.noBranch,
      );
    });

    test('hanya layar cabang yang di-scope, dan hanya status terkirim', () {
      for (final kind in DeliveryRouteKind.values) {
        final isBranch = const {
          DeliveryRouteKind.branchList,
          DeliveryRouteKind.branchDocument,
          DeliveryRouteKind.branchWaybill,
        }.contains(kind);
        expect(DeliveryOrderAccessPolicy.requiresBranchScope(kind), isBranch);
        expect(
          DeliveryOrderAccessPolicy.visibleStatuses(kind),
          isBranch ? DeliveryOrderAccessPolicy.branchVisibleStatuses : isEmpty,
        );
      }
      expect(DeliveryOrderAccessPolicy.branchVisibleStatuses, {
        DeliveryOrderStatus.shipped,
        DeliveryOrderStatus.received,
      });
    });

    test('hanya layar warehouse yang menulis', () {
      expect(
        DeliveryRouteKind.values
            .where(DeliveryOrderAccessPolicy.isWriteScreen)
            .toSet(),
        {DeliveryRouteKind.warehouseCreate, DeliveryRouteKind.warehouseDraft},
      );
    });
  });

  group('scope kueri repository', () {
    test('warehouse membaca Surat Jalan setiap cabang', () async {
      final doId = await shippedOrder();
      expect(await context.deliveries.getForWarehouse(doId), isNotNull);
    });

    test('cabang membaca miliknya sendiri saja', () async {
      final doId = await shippedOrder();

      expect(
        await context.deliveries.getForBranch(
          doId: doId,
          branchId: fixture.branch.id,
        ),
        isNotNull,
      );
      // Another branch's id resolves to nothing — the predicate is in the SQL, so
      // the document is not fetched and then withheld.
      expect(
        await context.deliveries.getForBranch(
          doId: doId,
          branchId: fixture.otherBranch.id,
        ),
        isNull,
      );
    });

    test('cabang tidak dapat membaca dokumen preparing', () async {
      final doId = await preparingOrder();

      // Nothing has left the building, so the branch has not been handed anything.
      expect(
        await context.deliveries.getForBranch(
          doId: doId,
          branchId: fixture.branch.id,
        ),
        isNull,
      );
      // And the warehouse, whose draft it is, sees it.
      expect(await context.deliveries.getForWarehouse(doId), isNotNull);
    });

    test('daftar cabang hanya memuat shipped dan received', () async {
      final shipped = await shippedOrder();
      final preparing = await preparingOrder();

      final rows = await context.deliveries
          .watchListForBranch(branchId: fixture.branch.id)
          .first;
      expect(rows.map((summary) => summary.id), [shipped]);
      expect(rows.map((summary) => summary.id), isNot(contains(preparing)));
    });

    test('daftar cabang menolak permintaan status preparing', () async {
      await preparingOrder();

      // Intersecting inside the method is what makes the restriction a property of
      // the API rather than a convention its callers follow.
      final rows = await context.deliveries
          .watchListForBranch(
            branchId: fixture.branch.id,
            statuses: {DeliveryOrderStatus.preparing},
          )
          .first;
      expect(rows, isEmpty);
    });

    test(
      'access scope tidak dapat membedakan tidak ada dan bukan milikmu',
      () async {
        final doId = await shippedOrder();

        // Both answers are `null`, and that ambiguity is the design: telling them
        // apart would turn the address bar into a way to enumerate documents.
        expect(
          await context.deliveries.findAccessScope(
            doId: doId,
            branchId: fixture.otherBranch.id,
            statuses: DeliveryOrderAccessPolicy.branchVisibleStatuses,
          ),
          isNull,
        );
        expect(
          await context.deliveries.findAccessScope(
            doId: 'tidak-ada',
            branchId: fixture.otherBranch.id,
            statuses: DeliveryOrderAccessPolicy.branchVisibleStatuses,
          ),
          isNull,
        );
      },
    );
  });

  group('scope provider', () {
    test('provider detail warehouse menolak aktor bukan warehouse', () async {
      final doId = await shippedOrder();
      final container = await containerFor(fixture.branchHead);

      // The unscoped read: a branch session reaching it must see nothing, because
      // the route guard is not the only defence.
      expect(
        await readAsync(
          container,
          warehouseDeliveryDetailProvider(doId),
          warehouseDeliveryDetailProvider(doId).future,
        ),
        isNull,
      );
    });

    test('provider detail cabang menolak cabang lain', () async {
      final doId = await shippedOrder();
      final container = await containerFor(fixture.otherBranchHead);

      expect(
        await readAsync(
          container,
          branchDeliveryDetailProvider(doId),
          branchDeliveryDetailProvider(doId).future,
        ),
        isNull,
      );
    });

    test('provider detail cabang menolak dokumen preparing', () async {
      final doId = await preparingOrder();
      final container = await containerFor(fixture.branchHead);

      expect(
        await readAsync(
          container,
          branchDeliveryDetailProvider(doId),
          branchDeliveryDetailProvider(doId).future,
        ),
        isNull,
      );
    });

    test('daftar warehouse kosong untuk aktor cabang', () async {
      await shippedOrder();
      final container = await containerFor(fixture.branchHead);

      expect(
        await readAsync(
          container,
          warehouseDeliveryListProvider(null),
          warehouseDeliveryListProvider(null).future,
        ),
        isEmpty,
      );
    });

    test('daftar cabang kosong untuk aktor warehouse', () async {
      await shippedOrder();
      final container = await containerFor(fixture.warehouseUser);

      // The warehouse has no branch, and a branch-scoped provider must treat that
      // as "no branch to scope to" rather than as "every branch".
      expect(
        await readAsync(
          container,
          branchDeliveryListProvider(null),
          branchDeliveryListProvider(null).future,
        ),
        isEmpty,
      );
    });

    test(
      'Surat Jalan cabang menolak cabang lain dan dokumen preparing',
      () async {
        final shipped = await shippedOrder();
        final preparing = await preparingOrder();

        final foreign = await containerFor(fixture.otherBranchHead);
        expect(
          await foreign.read(
            deliveryWaybillProvider((doId: shipped, branchScoped: true)).future,
          ),
          isNull,
        );

        final own = await containerFor(fixture.branchHead);
        expect(
          await own.read(
            deliveryWaybillProvider((
              doId: preparing,
              branchScoped: true,
            )).future,
          ),
          isNull,
        );
        expect(
          await own.read(
            deliveryWaybillProvider((doId: shipped, branchScoped: true)).future,
          ),
          isNotNull,
        );
      },
    );

    test('ganti sesi tidak menyajikan dokumen sesi sebelumnya', () async {
      final doId = await shippedOrder();

      // Two containers stand in for two sessions. The branch-scoped provider is
      // `autoDispose` and reads the acting branch on every build, so the second
      // session cannot resolve the first one's cache entry.
      final first = await containerFor(fixture.branchHead);
      expect(
        await readAsync(
          first,
          branchDeliveryDetailProvider(doId),
          branchDeliveryDetailProvider(doId).future,
        ),
        isNotNull,
      );

      final second = await containerFor(fixture.otherBranchHead);
      expect(
        await readAsync(
          second,
          branchDeliveryDetailProvider(doId),
          branchDeliveryDetailProvider(doId).future,
        ),
        isNull,
      );
    });
  });

  group('route guard dan URL langsung', () {
    testWidgets('cabang lain tidak membocorkan apa pun dari URL', (
      tester,
    ) async {
      useTabletSurface(tester);
      final doId = await shippedOrder();
      final detail = await context.deliveries.getForWarehouse(doId);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '/deliveries/$doId',
        overrides: [deliveryClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      // Not one fact about the document reaches the tree: not its number, not the
      // request it fulfils, not the branch, the item, the batch or the quantity.
      expect(find.textContaining(detail!.summary.docNumber), findsNothing);
      expect(find.textContaining(detail.summary.prDocNumber), findsNothing);
      expect(find.textContaining(fixture.branch.name), findsNothing);
      expect(find.textContaining(fixture.simpleItem.name), findsNothing);
      expect(find.textContaining(fixture.simpleItem.sku), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('dokumen preparing tidak dapat dibuka cabang tujuan', (
      tester,
    ) async {
      useTabletSurface(tester);
      final doId = await preparingOrder();
      final detail = await context.deliveries.getForWarehouse(doId);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/deliveries/$doId',
        overrides: [deliveryClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(find.textContaining(detail!.summary.docNumber), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('perawat tidak dapat membuka daftar pengiriman', (
      tester,
    ) async {
      useTabletSurface(tester);
      await shippedOrder();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '/deliveries',
        overrides: [deliveryClockProvider.overrideWithValue(() => nowUtc)],
      );

      // The synchronous redirect sends a nurse home rather than rendering the
      // section at all.
      expect(find.text('Pengiriman Masuk'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('cabang tidak dapat membuka daftar warehouse', (tester) async {
      useTabletSurface(tester);
      await shippedOrder();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/warehouse/delivery-orders',
        overrides: [deliveryClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.text('Pengiriman'), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('editor menolak dokumen yang sudah dikirim', (tester) async {
      useTabletSurface(tester);
      final doId = await shippedOrder();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/delivery-orders/$doId/edit',
        overrides: [deliveryClockProvider.overrideWithValue(() => nowUtc)],
      );

      // A shipped document's allocations are what the ledger was posted from, so
      // the editor route is refused rather than rendered read-only (G-S2).
      expect(find.byType(AccessDeniedPage), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('warehouse dapat membuka Surat Jalan lintas cabang', (
      tester,
    ) async {
      useTabletSurface(tester);
      final doId = await shippedOrder();
      final detail = await context.deliveries.getForWarehouse(doId);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/delivery-orders/$doId/waybill',
        overrides: [deliveryClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsNothing);
      expect(find.text(detail!.summary.docNumber), findsOneWidget);

      await disposeWidget(tester);
    });
  });

  group('use case membaca aktor dari database', () {
    test(
      'sesi tidak dapat memberi wewenang yang tidak dimiliki pengguna',
      () async {
        // O-8: the session provides only an actor id. Every use case re-reads the
        // stored user, so a tampered session cannot widen anyone's authority.
        final doId = await preparingOrder();
        final lineIds = await deliveryLineIdsByAllocation(context, doId);

        for (final actor in [fixture.branchHead, fixture.nurse]) {
          await expectLater(
            () => context.shipDeliveryOrder().call(
              actorUserId: actor.id,
              deliveryOrderId: doId,
            ),
            throwsA(isA<InvalidReviewerFailure>()),
          );
          await expectLater(
            () => context.updateDeliveryLine().call(
              actorUserId: actor.id,
              lineId: lineIds['${fixture.simpleLineId}|']!,
              shippedQty: Quantity.parse('1'),
            ),
            throwsA(isA<InvalidReviewerFailure>()),
          );
          await expectLater(
            () => context.removeDeliveryLine.call(
              actorUserId: actor.id,
              lineId: lineIds['${fixture.simpleLineId}|']!,
            ),
            throwsA(isA<InvalidReviewerFailure>()),
          );
          await expectLater(
            () => context.allocateFefo().call(
              actorUserId: actor.id,
              deliveryOrderId: doId,
            ),
            throwsA(isA<InvalidReviewerFailure>()),
          );
        }

        expect(await context.deliveryOrderStatusOf(doId), 'preparing');
        expect(await context.shipmentMovementCount(doId), 0);
      },
    );

    test(
      'petugas yang dinonaktifkan setelah penyiapan tidak dapat mengirim',
      () async {
        final doId = await preparingOrder();
        await context.deactivate('users', fixture.warehouseUser.id);

        // Unlike the branch or item data a historic document points at, the person
        // shipping goods right now has to be a currently valid account.
        await expectLater(
          () => context.shipDeliveryOrder().call(
            actorUserId: fixture.warehouseUser.id,
            deliveryOrderId: doId,
          ),
          throwsA(isA<InactiveEntityFailure>()),
        );
        // Another active officer can still ship it — the document is not stranded.
        await context.shipDeliveryOrder().call(
          actorUserId: fixture.secondWarehouseUser.id,
          deliveryOrderId: doId,
        );
        expect(
          await context.deliveryOrderColumn(doId, 'shipped_by'),
          fixture.secondWarehouseUser.id,
        );
      },
    );
  });
}
