import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/disposal/domain/services/disposal_access_policy.dart';
import 'package:aish_warehouse/features/disposal/presentation/providers/disposal_providers.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderListenable` and `Refreshable` live here rather than in the main barrel
// file in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The four layers that keep one scope's documents out of the other's hands (§44).
///
/// A single check is never the answer, and each layer here fails differently:
///
/// 1. **SQL** — the scope predicate is inside the query, so a foreign document is
///    never fetched. This is the only layer that makes "cannot leak" a property of
///    the data rather than of the code above it.
/// 2. **Providers** — every stream re-checks the acting role on each build and emits
///    empty rather than reading across the boundary, so the route guard is never the
///    only thing standing between a session and somebody else's shelf.
/// 3. **Route guard** — the page does not exist until the decision says yes, so a
///    refused route has no subscription to any document stream.
/// 4. **Use cases** — the last word, and the only one that decides a *write*.
///
/// The widget assertions are the interesting ones: they type the URL, which is the
/// attack, and then assert that the rendered tree contains no document number, no
/// item name, no batch number, no quantity and no reason.
void main() {
  final nowUtc = DateTime.utc(2026, 7, 30, 4);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> postedDisposalAt(
    String locationId, {
    required String actorUserId,
  }) async {
    final id = await createDisposalDraft(
      context,
      fixture,
      sourceLocationId: locationId,
      nowUtc: nowUtc,
      actorUserId: actorUserId,
      reason: 'Kedaluwarsa — rahasia cabang',
    );
    await addDisposalPosition(
      context,
      fixture,
      disposalId: id,
      itemId: fixture.expiryItem.id,
      batchId: fixture.expiredBatch.id,
      qty: '1.5',
      nowUtc: nowUtc,
      actorUserId: actorUserId,
    );
    await context
        .postDisposal(clock: () => nowUtc)
        .call(actorUserId: actorUserId, disposalId: id);
    return id;
  }

  /// Every string a leak would consist of.
  Future<List<String>> secretsOf(String disposalId) async {
    final detail = await context.disposals.getDetail(disposalId);
    return [
      detail!.disposal.docNumber,
      detail.disposal.reason!,
      detail.source.name,
      for (final line in detail.lines) ...[
        line.itemName,
        line.sku,
        line.batchNo,
        line.qty.format(),
      ],
    ];
  }

  void expectNothingLeaked(List<String> secrets) {
    for (final secret in secrets) {
      expect(
        find.textContaining(secret, findRichText: true),
        findsNothing,
        reason: '"$secret" bocor ke widget tree yang seharusnya ditolak.',
      );
    }
  }

  group('cakupan SQL', () {
    test('daftar warehouse hanya memuat dokumen Warehouse Pusat', () async {
      await postedDisposalAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );

      final warehouseRows = await context.disposals.listForWarehouse();
      expect(warehouseRows, hasLength(1));
      expect(warehouseRows.single.sourceLocationId, fixture.warehouse.id);
    });

    test('daftar cabang memakai predikat cabang aktor', () async {
      await postedDisposalAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      final branchDoc = await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );

      final rows = await context.disposals.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows.map((row) => row.id), [branchDoc]);
    });

    test('Kepala Cabang A tidak dapat membaca dokumen cabang B', () async {
      final id = await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );

      expect(
        await context.disposals.getForBranch(
          disposalId: id,
          branchId: fixture.otherBranch.id,
        ),
        isNull,
      );
      expect(
        await context.disposals.listForBranch(branchId: fixture.otherBranch.id),
        isEmpty,
      );
    });

    test('dokumen cabang tidak terbaca lewat cakupan warehouse', () async {
      final id = await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      expect(await context.disposals.getForWarehouse(id), isNull);
    });

    test('dokumen warehouse tidak terbaca lewat cakupan cabang', () async {
      final id = await postedDisposalAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      expect(
        await context.disposals.getForBranch(
          disposalId: id,
          branchId: fixture.branch.id,
        ),
        isNull,
      );
    });

    test(
      'findAccessScope mengembalikan null untuk id asing maupun tidak ada',
      () async {
        final id = await postedDisposalAt(
          fixture.branchStore.id,
          actorUserId: fixture.branchHead.id,
        );

        // The two answers are deliberately identical: telling them apart would let the
        // id space be enumerated from the address bar.
        expect(
          await context.disposals.findAccessScope(
            disposalId: id,
            scope: DisposalLocationScope.branch,
            branchId: fixture.otherBranch.id,
          ),
          isNull,
        );
        expect(
          await context.disposals.findAccessScope(
            disposalId: 'id-yang-tidak-ada',
            scope: DisposalLocationScope.branch,
            branchId: fixture.otherBranch.id,
          ),
          isNull,
        );
      },
    );

    test('editor tidak menerima dokumen yang sudah diposting', () async {
      final id = await postedDisposalAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      expect(
        await context.disposals.findAccessScope(
          disposalId: id,
          scope: DisposalLocationScope.warehouse,
          statuses: DisposalAccessPolicy.editableStatuses,
        ),
        isNull,
      );
    });

    test('cakupan cabang tanpa branch id tidak melebar menjadi semua', () async {
      // A role that has lost its branch must see *no* documents, not all of them.
      await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      expect(
        await context.disposals.findAccessScope(
          disposalId: 'apa pun',
          scope: DisposalLocationScope.branch,
        ),
        isNull,
      );
    });
  });

  group('provider', () {
    /// Reads a stream provider while holding it open.
    ///
    /// `container.read(p.future)` alone opens and immediately closes its own
    /// subscription, so an `autoDispose` provider is torn down before its first
    /// emission ever arrives. A screen holds the provider for as long as it is on
    /// screen; this reproduces that rather than racing it.
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

    /// A provider graph hanging off the in-memory database, acting as [user].
    ///
    /// The whole graph hangs off `appDatabaseProvider`, exactly as in the app, so
    /// nothing here is a stub: the scoped queries really run, against real rows.
    Future<ProviderContainer> containerFor(MasterUser user) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(context.database),
          currentSessionProvider.overrideWith(
            () => FixedSessionController(user),
          ),
          disposalClockProvider.overrideWithValue(() => nowUtc),
        ],
      );
      addTearDown(container.dispose);
      // Let the session resolve before anything reads it.
      await container.read(currentSessionProvider.future);
      return container;
    }

    test('daftar warehouse kosong untuk Kepala Cabang', () async {
      await postedDisposalAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      final container = await containerFor(fixture.branchHead);

      final rows = await readStream(
        container,
        warehouseDisposalListProvider,
        warehouseDisposalListProvider.future,
      );
      expect(rows, isEmpty);
    });

    test('daftar cabang kosong untuk Warehouse', () async {
      await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      final container = await containerFor(fixture.warehouseUser);

      expect(
        await readStream(
          container,
          branchDisposalListProvider,
          branchDisposalListProvider.future,
        ),
        isEmpty,
      );
    });

    test('daftar cabang kosong untuk Perawat', () async {
      await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      final container = await containerFor(fixture.nurse);

      expect(
        await readStream(
          container,
          branchDisposalListProvider,
          branchDisposalListProvider.future,
        ),
        isEmpty,
      );
      expect(
        await readStream(
          container,
          warehouseDisposalListProvider,
          warehouseDisposalListProvider.future,
        ),
        isEmpty,
      );
    });

    test('detail cabang null untuk cabang lain', () async {
      final id = await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      final container = await containerFor(fixture.otherBranchHead);

      expect(
        await readStream(
          container,
          branchDisposalDetailProvider(id),
          branchDisposalDetailProvider(id).future,
        ),
        isNull,
      );
    });

    test('lokasi sumber Perawat kosong', () async {
      // Not a filtered-down list — an empty one. There is no source a nurse may name.
      final container = await containerFor(fixture.nurse);
      expect(
        await container.read(disposalSourceLocationsProvider.future),
        isEmpty,
      );
      expect(
        await container.read(effectiveDisposalSourceProvider.future),
        isNull,
      );
    });

    test('lokasi sumber Super Admin kosong', () async {
      final container = await containerFor(fixture.superAdmin);
      expect(
        await container.read(disposalSourceLocationsProvider.future),
        isEmpty,
      );
    });

    test('lokasi sumber Warehouse hanya Warehouse Pusat', () async {
      final container = await containerFor(fixture.warehouseUser);
      final locations = await container.read(
        disposalSourceLocationsProvider.future,
      );
      expect(locations.map((location) => location.id), [fixture.warehouse.id]);
    });

    test('lokasi sumber Kepala Cabang hanya cabangnya sendiri', () async {
      final container = await containerFor(fixture.branchHead);
      final locations = await container.read(
        disposalSourceLocationsProvider.future,
      );

      expect(locations.map((location) => location.id).toSet(), {
        fixture.branchStore.id,
        fixture.locationOne.id,
        fixture.locationTwo.id,
      });
      expect(
        locations.map((location) => location.id),
        isNot(contains(fixture.warehouse.id)),
      );
      expect(
        locations.map((location) => location.id),
        isNot(contains(fixture.otherBranchStore.id)),
      );
    });

    test('pilihan sumber di luar cakupan diabaikan', () async {
      // The leak this closes: a selection surviving a session switch must not point a
      // branch head at their previous branch's shelf.
      final container = await containerFor(fixture.branchHead);
      container
          .read(selectedDisposalSourceProvider.notifier)
          .select(fixture.otherBranchStore.id);

      final effective = await container.read(
        effectiveDisposalSourceProvider.future,
      );
      expect(effective, isNotNull);
      expect(effective!.id, isNot(fixture.otherBranchStore.id));
      expect(effective.branchId, fixture.branch.id);
    });

    test('kandidat kedaluwarsa hanya dari lokasi dalam cakupan', () async {
      final container = await containerFor(fixture.branchHead);
      final positions = await readStream(
        container,
        disposalExpiredPositionsProvider,
        disposalExpiredPositionsProvider.future,
      );
      for (final position in positions) {
        expect(position.locationId, fixture.branchStore.id);
      }
    });
  });

  group('URL langsung', () {
    testWidgets('Kepala Cabang lain melihat halaman ditolak, bukan dokumen', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      final secrets = await secretsOf(id);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '/disposals/$id',
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(find.text(accessDeniedMessage), findsOneWidget);
      expectNothingLeaked(secrets);
      await disposeWidget(tester);
    });

    testWidgets('Warehouse tidak dapat membuka dokumen cabang lewat rute '
        'warehouse', (tester) async {
      useTabletSurface(tester);
      final id = await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      final secrets = await secretsOf(id);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/disposals/$id',
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expectNothingLeaked(secrets);
      await disposeWidget(tester);
    });

    testWidgets('Kepala Cabang tidak dapat membuka dokumen warehouse', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await postedDisposalAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      final secrets = await secretsOf(id);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/disposals/$id',
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expectNothingLeaked(secrets);
      await disposeWidget(tester);
    });

    testWidgets('id yang tidak ada dan id asing memberi jawaban yang sama', (
      tester,
    ) async {
      useTabletSurface(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/disposals/id-yang-tidak-ada',
      );
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('editor menolak dokumen yang sudah diposting', (tester) async {
      useTabletSurface(tester);
      final id = await postedDisposalAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/disposals/$id/edit',
      );

      // `posted` is read-only permanently (G-S2), and the editor route says so before
      // anything is fetched.
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('Perawat dialihkan dari seluruh bagian Pemusnahan', (
      tester,
    ) async {
      useTabletSurface(tester);

      for (final location in const ['/disposals', '/warehouse/disposals']) {
        await pumpAppAt(
          tester,
          context: context,
          actingAs: fixture.nurse,
          location: location,
        );
        expect(
          find.text('Pemusnahan Stok'),
          findsNothing,
          reason: 'Perawat mencapai $location.',
        );
        await disposeWidget(tester);
      }
    });

    testWidgets('Super Admin dialihkan dari seluruh bagian Pemusnahan', (
      tester,
    ) async {
      useTabletSurface(tester);

      for (final location in const ['/disposals', '/warehouse/disposals']) {
        await pumpAppAt(
          tester,
          context: context,
          actingAs: fixture.superAdmin,
          location: location,
        );
        expect(find.text('Pemusnahan Stok'), findsNothing);
        await disposeWidget(tester);
      }
    });
  });

  group('pergantian sesi', () {
    testWidgets('dokumen cabang tidak bertahan di cache setelah ganti sesi', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await postedDisposalAt(
        fixture.branchStore.id,
        actorUserId: fixture.branchHead.id,
      );
      final secrets = await secretsOf(id);

      // Open it legitimately first, so anything cacheable is cached.
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/disposals/$id',
      );
      expect(find.textContaining(secrets.first), findsWidgets);
      await disposeWidget(tester);

      // Then the same URL under a different session.
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '/disposals/$id',
      );
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expectNothingLeaked(secrets);
      await disposeWidget(tester);
    });
  });

  group('finalitas', () {
    test(
      'dokumen yang diposting tidak dapat diubah lewat use case mana pun',
      () async {
        final id = await postedDisposalAt(
          fixture.warehouse.id,
          actorUserId: fixture.warehouseUser.id,
        );
        final lineId = (await disposalLineIdsByPosition(
          context,
          id,
        )).values.single;

        await expectLater(
          context.updateDisposalHeader.call(
            actorUserId: fixture.warehouseUser.id,
            disposalId: id,
            reason: 'Alasan baru',
          ),
          throwsA(isA<DisposalAlreadyPostedFailure>()),
        );
        await expectLater(
          context.removeDisposalLine.call(
            actorUserId: fixture.warehouseUser.id,
            disposalId: id,
            lineId: lineId,
          ),
          throwsA(isA<DisposalAlreadyPostedFailure>()),
        );
        await expectLater(
          addDisposalPosition(
            context,
            fixture,
            disposalId: id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.staleBatch.id,
            qty: '0.25',
            nowUtc: nowUtc,
          ),
          throwsA(isA<DisposalAlreadyPostedFailure>()),
        );

        // The audit record is exactly what it was.
        expect(
          await context.disposalColumn(id, 'reason'),
          'Kedaluwarsa — rahasia cabang',
        );
        expect(await context.disposalLineCount(id), 1);
        expect(await context.disposalMovementCount(id), 1);
      },
    );

    test('SQL bertahan meski use case dilewati', () async {
      // The guarded statements carry `status = 'draft'` themselves, so even a caller
      // that skipped every domain check writes nothing.
      final id = await postedDisposalAt(
        fixture.warehouse.id,
        actorUserId: fixture.warehouseUser.id,
      );
      final lineId = (await disposalLineIdsByPosition(
        context,
        id,
      )).values.single;

      expect(
        await context.disposals.updateDraftReason(
          disposalId: id,
          reason: 'Diubah diam-diam',
        ),
        isFalse,
      );
      expect(
        await context.disposals.removeDraftLine(disposalId: id, lineId: lineId),
        isFalse,
      );
      expect(
        await context.disposals.markPosted(
          disposalId: id,
          postedAtUtc: nowUtc,
          postedBy: fixture.warehouseUser.id,
        ),
        isFalse,
      );

      expect(
        await context.disposalColumn(id, 'reason'),
        'Kedaluwarsa — rahasia cabang',
      );
      expect(await context.disposalLineCount(id), 1);
    });
  });
}
