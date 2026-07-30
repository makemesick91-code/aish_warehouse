import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/distribution/domain/models/distribution_models.dart';
import 'package:aish_warehouse/features/distribution/domain/services/distribution_access_policy.dart';
import 'package:aish_warehouse/features/distribution/presentation/pages/distribution_detail_page.dart';
import 'package:aish_warehouse/features/distribution/presentation/pages/distribution_list_page.dart';
import 'package:aish_warehouse/features/distribution/presentation/providers/distribution_providers.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderListenable`, `Refreshable` and `Override` live here rather than in the main
// barrel file in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Read authorization for Distribusi (§44).
///
/// The assertions come in three layers, because each catches something the others
/// cannot: the **policy** is exercised as a pure function, the **providers** are built
/// against a real database with a real session, and the **routes** are reached by typing
/// the URL — which is the attack, so the test has to type it.
///
/// The route guard is deliberately never the only defence asserted. §25 lists five, and
/// every one of them gets a test here: the scoped SQL read, the branch-scoped provider,
/// the guard, the use case's own re-read of the actor, and the session cache being
/// invalidated when the acting user changes.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draftWithLine({String? actorUserId}) async {
    final id = await createDistributionDraft(
      context,
      fixture,
      nowUtc: nowUtc,
      actorUserId: actorUserId,
    );
    await addDistributionItem(
      context,
      fixture,
      distributionId: id,
      roomId: fixture.roomOne.id,
      itemId: fixture.simpleItem.id,
      qty: '2',
      nowUtc: nowUtc,
      actorUserId: actorUserId,
    );
    return id;
  }

  Future<String> postedDistribution() async {
    final id = await draftWithLine();
    await context
        .postDistribution(clock: () => nowUtc)
        .call(actorUserId: fixture.branchHead.id, distributionId: id);
    return id;
  }

  /// A distribution owned by the *other* branch, built by its own branch head so nothing
  /// about it depends on a rule being broken to create it.
  Future<String> foreignDistribution() async {
    // The other branch needs a room location before its head can add a line.
    final id = await createDistributionDraft(
      context,
      fixture,
      nowUtc: nowUtc,
      actorUserId: fixture.otherBranchHead.id,
    );
    return id;
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
        distributionClockProvider.overrideWithValue(() => nowUtc),
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

    test('hanya Kepala Cabang mencapai layar Distribusi', () {
      for (final kind in DistributionRouteKind.values) {
        for (final role in UserRole.values) {
          final granted = DistributionAccessPolicy.forSection(
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

    test('setiap layar berbatas cabang, tanpa pengecualian', () {
      // Unlike Good Receipt there is no warehouse side to this document (spec §3.1), so
      // `requiresBranchScope` has no way to answer anything else — and that is the
      // property worth pinning, because a single `false` here is how an IDOR appears.
      for (final kind in DistributionRouteKind.values) {
        expect(
          DistributionAccessPolicy.requiresBranchScope(kind),
          isTrue,
          reason: '$kind tidak berbatas cabang.',
        );
      }
    });

    test('Kepala Cabang tanpa cabang ditolak', () {
      final access = DistributionAccessPolicy.forSection(
        user: userWith(UserRole.kepalaCabang),
        kind: DistributionRouteKind.branchList,
      );
      expect(access.reason, DistributionAccessDenialReason.noBranch);
    });

    test('akun nonaktif ditolak', () {
      final access = DistributionAccessPolicy.forSection(
        user: const MasterUser(
          id: 'u-1',
          fullName: 'Kepala Cabang',
          email: 'k@test.local',
          role: UserRole.kepalaCabang,
          branchId: 'b-1',
          isActive: false,
        ),
        kind: DistributionRouteKind.branchList,
      );
      expect(access.reason, DistributionAccessDenialReason.role);
    });

    test('tanpa sesi ditolak', () {
      final access = DistributionAccessPolicy.forSection(
        user: null,
        kind: DistributionRouteKind.branchList,
      );
      expect(access.reason, DistributionAccessDenialReason.noSession);
    });

    test('dokumen cabang lain dan dokumen tak ada dijawab sama', () {
      final actor = userWith(UserRole.kepalaCabang, branchId: 'b-1');

      final foreign = DistributionAccessPolicy.forDocument(
        user: actor,
        kind: DistributionRouteKind.branchDocument,
        scope: const DistributionAccessScope(
          distributionId: 'd-1',
          branchId: 'b-2',
          distributedBy: 'u-2',
          status: DistributionStatus.draft,
        ),
      );
      final missing = DistributionAccessPolicy.forDocument(
        user: actor,
        kind: DistributionRouteKind.branchDocument,
        scope: null,
      );

      // Telling them apart would let anyone with the app work out which document ids are
      // real across the clinic group.
      expect(foreign.reason, DistributionAccessDenialReason.documentOutOfScope);
      expect(missing.reason, DistributionAccessDenialReason.documentOutOfScope);
    });

    test('editor menolak dokumen yang sudah diposting', () {
      final actor = userWith(UserRole.kepalaCabang, branchId: 'b-1');
      const posted = DistributionAccessScope(
        distributionId: 'd-1',
        branchId: 'b-1',
        distributedBy: 'u-1',
        status: DistributionStatus.posted,
      );

      expect(
        DistributionAccessPolicy.forDocument(
          user: actor,
          kind: DistributionRouteKind.branchDraft,
          scope: posted,
        ).reason,
        DistributionAccessDenialReason.documentStatus,
      );
      // The read-only detail shows it perfectly well.
      expect(
        DistributionAccessPolicy.forDocument(
          user: actor,
          kind: DistributionRouteKind.branchDocument,
          scope: posted,
        ).isGranted,
        isTrue,
      );
    });

    test('layar tulis dinyatakan eksplisit', () {
      expect(
        DistributionAccessPolicy.isWriteScreen(
          DistributionRouteKind.branchDraft,
        ),
        isTrue,
      );
      expect(
        DistributionAccessPolicy.isWriteScreen(
          DistributionRouteKind.branchCreate,
        ),
        isTrue,
      );
      expect(
        DistributionAccessPolicy.isWriteScreen(
          DistributionRouteKind.branchDocument,
        ),
        isFalse,
      );
      expect(
        DistributionAccessPolicy.isWriteScreen(
          DistributionRouteKind.branchList,
        ),
        isFalse,
      );
    });

    test('canWrite hanya benar untuk Kepala Cabang', () {
      for (final role in UserRole.values) {
        expect(
          DistributionAccessPolicy.canWrite(role),
          role == UserRole.kepalaCabang,
          reason: '${role.dbValue} salah dinilai.',
        );
      }
      expect(DistributionAccessPolicy.canWrite(null), isFalse);
    });
  });

  group('provider berbatas cabang', () {
    test('daftar hanya memuat dokumen cabang sendiri', () async {
      final own = await draftWithLine();
      final foreign = await foreignDistribution();

      final container = await containerFor(fixture.branchHead);
      final rows = await readStream(
        container,
        branchDistributionListProvider(null),
        branchDistributionListProvider(null).future,
      );

      expect(rows.map((summary) => summary.id), contains(own));
      expect(rows.map((summary) => summary.id), isNot(contains(foreign)));
    });

    test('detail cabang lain memancarkan null', () async {
      final foreign = await foreignDistribution();

      final container = await containerFor(fixture.branchHead);
      final detail = await readStream(
        container,
        branchDistributionDetailProvider(foreign),
        branchDistributionDetailProvider(foreign).future,
      );

      expect(detail, isNull);
    });

    test('Warehouse mendapat daftar kosong, bukan lintas cabang', () async {
      await draftWithLine();

      final container = await containerFor(fixture.warehouseUser);
      final rows = await readStream(
        container,
        branchDistributionListProvider(null),
        branchDistributionListProvider(null).future,
      );

      // The role check inside the provider is what makes the route guard *not* the only
      // thing standing between a warehouse session and every branch's documents.
      expect(rows, isEmpty);
    });

    test('Perawat mendapat daftar kosong', () async {
      await draftWithLine();

      final container = await containerFor(fixture.nurse);
      final rows = await readStream(
        container,
        branchDistributionListProvider(null),
        branchDistributionListProvider(null).future,
      );

      expect(rows, isEmpty);
    });

    test('Super Admin mendapat daftar kosong', () async {
      await draftWithLine();

      final container = await containerFor(fixture.superAdmin);
      final rows = await readStream(
        container,
        branchDistributionListProvider(null),
        branchDistributionListProvider(null).future,
      );

      expect(rows, isEmpty);
    });

    test('Warehouse tidak melihat detail dokumen apa pun', () async {
      final id = await draftWithLine();

      final container = await containerFor(fixture.warehouseUser);
      final detail = await readStream(
        container,
        branchDistributionDetailProvider(id),
        branchDistributionDetailProvider(id).future,
      );

      expect(detail, isNull);
    });

    test('daftar ruangan Warehouse kosong', () async {
      final container = await containerFor(fixture.warehouseUser);
      final rooms = await readStream(
        container,
        branchDistributionRoomsProvider(null),
        branchDistributionRoomsProvider(null).future,
      );

      expect(rooms, isEmpty);
    });

    test('gudang cabang tidak resolve untuk Warehouse', () async {
      final container = await containerFor(fixture.warehouseUser);
      expect(await container.read(branchStoreLocationProvider.future), isNull);
    });

    test('pencarian stok kosong tanpa gudang cabang yang resolve', () async {
      final container = await containerFor(fixture.warehouseUser);
      final rows = await container.read(
        distributionStockSearchProvider((
          query: 'Masker',
          categoryId: null,
        )).future,
      );

      // No store resolves for a warehouse session, so there is nothing to search — and
      // certainly not another branch's shelf.
      expect(rows, isEmpty);
    });

    test('pencarian stok Kepala Cabang membaca gudangnya sendiri', () async {
      final container = await containerFor(fixture.branchHead);
      final rows = await container.read(
        distributionStockSearchProvider((
          query: 'Masker',
          categoryId: null,
        )).future,
      );

      expect(rows, hasLength(1));
      expect(rows.single.itemId, fixture.simpleItem.id);
    });

    test('pergantian sesi membangun ulang, tidak menyajikan cache', () async {
      final own = await draftWithLine();

      // One container, two sessions — which is what the app does when the development
      // role picker switches user. A stale cache entry is the one way a branch scope can
      // be correct everywhere and still leak.
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(context.database),
          distributionClockProvider.overrideWithValue(() => nowUtc),
        ],
      );
      addTearDown(container.dispose);

      await container.read(currentSessionProvider.future);
      await container
          .read(currentSessionProvider.notifier)
          .switchTo(fixture.branchHead.id);
      final asHead = await readStream(
        container,
        branchDistributionListProvider(null),
        branchDistributionListProvider(null).future,
      );
      expect(asHead.map((summary) => summary.id), contains(own));

      await container
          .read(currentSessionProvider.notifier)
          .switchTo(fixture.otherBranchHead.id);
      final asOtherHead = await readStream(
        container,
        branchDistributionListProvider(null),
        branchDistributionListProvider(null).future,
      );
      expect(asOtherHead.map((summary) => summary.id), isNot(contains(own)));

      await container
          .read(currentSessionProvider.notifier)
          .switchTo(fixture.warehouseUser.id);
      final asWarehouse = await readStream(
        container,
        branchDistributionListProvider(null),
        branchDistributionListProvider(null).future,
      );
      expect(asWarehouse, isEmpty);
    });
  });

  group('rute langsung', () {
    testWidgets('Kepala Cabang membuka daftarnya sendiri', (tester) async {
      useTabletSurface(tester);
      await draftWithLine();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/distributions',
        overrides: [distributionClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byKey(DistributionListPage.createKey), findsOneWidget);
      expect(find.byType(AccessDeniedPage), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('Warehouse dialihkan dari daftar Distribusi', (tester) async {
      useTabletSurface(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/distributions',
        overrides: [distributionClockProvider.overrideWithValue(() => nowUtc)],
      );

      // The synchronous redirect sends them home; either way the list is not on screen.
      expect(find.byKey(DistributionListPage.createKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('Perawat dialihkan dari daftar Distribusi', (tester) async {
      useTabletSurface(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '/distributions',
        overrides: [distributionClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byKey(DistributionListPage.createKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('dokumen cabang lain menampilkan akses ditolak', (
      tester,
    ) async {
      useTabletSurface(tester);
      final foreign = await foreignDistribution();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/distributions/$foreign',
        overrides: [distributionClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('id yang tidak ada menampilkan respons yang sama', (
      tester,
    ) async {
      useTabletSurface(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/distributions/tidak-ada',
        overrides: [distributionClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('editor menolak dokumen yang sudah diposting', (tester) async {
      useTabletSurface(tester);
      final id = await postedDistribution();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/distributions/$id/edit',
        overrides: [distributionClockProvider.overrideWithValue(() => nowUtc)],
      );

      // G-S2: the editor's route kind accepts `draft` only, so the guard refuses before
      // the form is built at all.
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('detail dokumen posted terbuka untuk pemiliknya', (
      tester,
    ) async {
      useTabletSurface(tester);
      final id = await postedDistribution();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/distributions/$id',
        overrides: [distributionClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsNothing);
      expect(find.byKey(DistributionDetailPage.headerKey), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('pohon widget yang ditolak tidak memuat nomor, barang atau qty', (
      tester,
    ) async {
      useTabletSurface(tester);
      // Give the foreign document something worth leaking. Its store has to be stocked
      // first — the fixture deliberately leaves the second branch empty — and it is
      // stocked through the ledger, so the foreign document is entirely legitimate
      // rather than something only a broken rule could have produced.
      final early = context.postingWithClock(
        () => nowUtc.subtract(const Duration(days: 30)),
      );
      await early.postInboundWarehouse(
        itemId: fixture.simpleItem.id,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.parse('5'),
        actorUserId: fixture.warehouseUser.id,
      );
      await early.postTransfer(
        itemId: fixture.simpleItem.id,
        fromLocationId: fixture.warehouse.id,
        toLocationId: fixture.otherBranchStore.id,
        qty: Quantity.parse('5'),
        movementType: StockMovementType.goodReceipt,
        actorUserId: fixture.warehouseUser.id,
      );

      final foreign = await foreignDistribution();
      await addDistributionItem(
        context,
        fixture,
        distributionId: foreign,
        roomId: fixture.otherBranchRoom.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
        actorUserId: fixture.otherBranchHead.id,
      );
      final detail = await context.distributions.getDetail(foreign);
      final docNumber = detail!.distribution.docNumber;

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/distributions/$foreign',
        overrides: [distributionClockProvider.overrideWithValue(() => nowUtc)],
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      // Nothing about the document is anywhere in the tree — not the number, not the
      // room, not the item, not the quantity. The guard did not hide them; it never
      // fetched them.
      for (final leak in [
        docNumber,
        fixture.otherBranchRoom.name,
        fixture.simpleItem.name,
        fixture.simpleItem.sku,
        'Ruang Dental 1 Cabang Lain',
      ]) {
        expect(
          find.textContaining(leak, findRichText: true),
          findsNothing,
          reason: '"$leak" bocor pada layar yang ditolak.',
        );
      }
      await disposeWidget(tester);
    });
  });

  group('use case adalah otoritas', () {
    test('use case membaca ulang aktor dari database', () async {
      // O-8. The session claims a role; the stored row decides. Deactivating the account
      // after the session was built must refuse the write, and only a re-read can notice.
      final id = await draftWithLine();
      await context.deactivate('users', fixture.branchHead.id);

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<InactiveEntityFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
    });

    test('mengubah peran akun menolak penulisan berikutnya', () async {
      final id = await draftWithLine();
      // What a back-office role change looks like from the app's point of view.
      await context.database.customStatement(
        "UPDATE users SET role = 'warehouse', branch_id = NULL WHERE id = ?;",
        [fixture.branchHead.id],
      );

      expect(
        () => context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(await context.distributionStatusOf(id), 'draft');
    });

    test('dokumen posted tetap tidak dapat diubah oleh siapa pun', () async {
      final id = await postedDistribution();
      final lines = await distributionLineIdsByPosition(context, id);
      final lineId = lines.values.first;

      for (final actor in [
        fixture.branchHead,
        fixture.otherBranchHead,
        fixture.warehouseUser,
        fixture.superAdmin,
        fixture.nurse,
      ]) {
        await expectLater(
          context.removeDistributionLine.call(
            actorUserId: actor.id,
            distributionId: id,
            lineId: lineId,
          ),
          throwsA(isA<AppFailure>()),
          reason: '${actor.role.dbValue} berhasil mengubah dokumen final.',
        );
      }
      expect(await context.distributionLineCount(id), 1);
    });
  });

  group('permukaan yang sengaja tidak ada', () {
    const repository =
        'lib/features/distribution/domain/repositories/distribution_repository.dart';
    const dao = 'lib/core/db/daos/distribution_dao.dart';
    const presentationRoot = 'lib/features/distribution/presentation';

    test('tidak ada un-post, reopen atau cancel', () {
      for (final file in [repository, dao]) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'unpost',
          'unPost',
          'reopen',
          'markDraft',
          'setStatus',
          'cancel',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menyediakan $forbidden.',
          );
        }
      }
    });

    test('tidak ada hard delete', () {
      for (final file in [repository, dao]) {
        final code = readCodeOnly(file);
        expect(code.contains('delete('), isFalse, reason: file);
        expect(code.contains('hardDelete'), isFalse, reason: file);
      }
    });

    test('presentasi tidak dapat menominasikan lokasi', () {
      // §14/G-T1's structural half: the store and the room location are resolved by
      // type, so there is no parameter a screen could pass and no column it could set.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'fromLocationId',
          'toLocationId',
          'sourceLocationId',
          'destinationLocationId',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menyebut $forbidden.',
          );
        }
      }
    });

    test('kontrak repository tidak menerima lokasi sumber atau tujuan', () {
      final code = readCodeOnly(repository);
      expect(code.contains('fromLocationId'), isFalse);
      expect(code.contains('toLocationId'), isFalse);
      // The one location the contract does mention is the branch store the *reads* are
      // scoped to, and the caller resolves it through `MasterDataRepository`.
      expect(code.contains('branchStoreLocationId'), isTrue);
    });

    test('DAO tidak menulis saldo', () {
      final code = readCodeOnly(dao);
      expect(code.contains('setBalanceQty'), isFalse);
      expect(code.contains('qtyOnHand: Value'), isFalse);
      expect(code.contains('into(stockBalances)'), isFalse);
    });
  });
}
