import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/goods_return/domain/models/goods_return_models.dart';
import 'package:aish_warehouse/features/goods_return/domain/services/goods_return_access_policy.dart';
import 'package:aish_warehouse/features/goods_return/presentation/providers/goods_return_providers.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Who can read and write what (§15/§27/§47).
///
/// The Retur is the first document in this application whose two audiences are scoped
/// *differently*: a Kepala Cabang by **branch**, a Petugas Warehouse by **status**. That
/// asymmetry is deliberate — the goods from every branch arrive at one building, so a
/// cross-branch queue is the feature — and it means the usual "is it in your branch?"
/// test only covers half the surface. The other half is: **can a Warehouse user reach a
/// draft?**, asked at the SQL layer, the provider layer and the route.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A container acting as [user], wired to the in-memory database.
  Future<ProviderContainer> containerFor(MasterUser user) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(context.database),
        currentSessionProvider.overrideWith(() => FixedSessionController(user)),
        goodsReturnClockProvider.overrideWithValue(() => nowUtc),
      ],
    );
    addTearDown(container.dispose);
    // Let the session resolve before anything reads it.
    await container.read(currentSessionProvider.future);
    return container;
  }

  /// Reads a stream provider while holding it open.
  ///
  /// `container.read(p.future)` alone opens and immediately closes its own
  /// subscription, so an `autoDispose` provider is torn down before its first emission
  /// ever arrives. A screen holds the provider for as long as it is on screen; this
  /// reproduces that rather than racing it.
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

  group('scope SQL', () {
    test('daftar cabang hanya memuat dokumen cabang itu', () async {
      final mine = await createGoodsReturnFor(context, fixture);
      // The other branch raises its own, so there is genuinely something to leak.
      final theirs = await context
          .createGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.otherBranchHead.id,
            goodReceiptId: fixture.otherBranchGoodReceiptId,
          );

      final rows = await context.goodsReturns.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows.map((row) => row.id), contains(mine.id));
      expect(rows.map((row) => row.id), isNot(contains(theirs.id)));
    });

    test('antrean Warehouse tidak pernah memuat draft', () async {
      final draft = await createGoodsReturnFor(context, fixture);
      final shipped = await context
          .createGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.otherBranchHead.id,
            goodReceiptId: fixture.otherBranchGoodReceiptId,
          );
      await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.otherBranchHead.id,
            goodsReturnId: shipped.id,
          );

      final rows = await context.goodsReturns.listForWarehouse();
      expect(
        rows.map((row) => row.id),
        contains(shipped.id),
        reason: 'Warehouse bekerja lintas cabang.',
      );
      expect(
        rows.map((row) => row.id),
        isNot(contains(draft.id)),
        reason: 'Draft cabang bukan urusan Warehouse.',
      );
    });

    test(
      'status draft dipaksa keluar walau caller meminta seluruh status',
      () async {
        final draft = await createGoodsReturnFor(context, fixture);

        // The status half of the Warehouse scope lives in the DAO predicate, not in
        // this parameter — so asking for `draft` explicitly returns nothing rather
        // than widening the scope (§24).
        final rows = await context.goodsReturns.listForWarehouse(
          statuses: {GoodsReturnStatus.draft},
        );
        expect(rows.map((row) => row.id), isNot(contains(draft.id)));
        expect(rows, isEmpty);
      },
    );

    test('chip cabang menyempitkan, tidak melebarkan', () async {
      final draft = await createGoodsReturnFor(context, fixture);

      final rows = await context.goodsReturns.listForWarehouse(
        filterBranchId: fixture.branch.id,
      );
      expect(
        rows.map((row) => row.id),
        isNot(contains(draft.id)),
        reason:
            'Memilih satu cabang tidak boleh membuka draft cabang tersebut.',
      );
    });

    test('detail cabang lain tidak dapat dibaca', () async {
      final theirs = await context
          .createGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.otherBranchHead.id,
            goodReceiptId: fixture.otherBranchGoodReceiptId,
          );

      expect(
        await context.goodsReturns.getForBranch(
          goodsReturnId: theirs.id,
          branchId: fixture.branch.id,
        ),
        isNull,
      );
      // And the access scope answers the same `null` for "not yours" as for "no such
      // document", so an id cannot be probed for existence (§27).
      expect(
        await context.goodsReturns.findAccessScope(
          goodsReturnId: theirs.id,
          scope: GoodsReturnQueryScope.branch,
          branchId: fixture.branch.id,
        ),
        isNull,
      );
      expect(
        await context.goodsReturns.findAccessScope(
          goodsReturnId: 'tidak-ada',
          scope: GoodsReturnQueryScope.branch,
          branchId: fixture.branch.id,
        ),
        isNull,
      );
    });

    test('antrean GR eligible cabang lain tidak bocor', () async {
      final rows = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );
      expect(
        rows.map((row) => row.grId),
        isNot(contains(fixture.otherBranchGoodReceiptId)),
      );
    });
  });

  group('provider', () {
    test('provider cabang memakai branch sesi, bukan parameter', () async {
      final mine = await createGoodsReturnFor(context, fixture);
      final container = await containerFor(fixture.otherBranchHead);

      // There is no way to *ask* for another branch: the provider takes no branch key.
      // Acting as the other branch head is the only expression of the question, and it
      // answers with their own documents.
      final rows = await readStream(
        container,
        branchGoodsReturnListProvider,
        branchGoodsReturnListProvider.future,
      );
      expect(rows.map((row) => row.id), isNot(contains(mine.id)));
    });

    test('provider cabang kosong untuk peran non-Kacab', () async {
      await createGoodsReturnFor(context, fixture);

      for (final user in [
        fixture.warehouseUser,
        fixture.nurse,
        fixture.superAdmin,
      ]) {
        final container = await containerFor(user);
        expect(
          await readStream(
            container,
            branchGoodsReturnListProvider,
            branchGoodsReturnListProvider.future,
          ),
          isEmpty,
          reason: '${user.role.label} tidak boleh membaca daftar retur cabang.',
        );
      }
    });

    test('provider Warehouse kosong untuk peran lain', () async {
      await shippedGoodsReturnFor(context, fixture);

      for (final user in [
        fixture.branchHead,
        fixture.nurse,
        fixture.superAdmin,
      ]) {
        final container = await containerFor(user);
        expect(
          await readStream(
            container,
            warehouseGoodsReturnListProvider,
            warehouseGoodsReturnListProvider.future,
          ),
          isEmpty,
          reason: '${user.role.label} tidak boleh membaca antrean Warehouse.',
        );
      }
    });

    test('detail Warehouse menolak draft', () async {
      final draft = await createGoodsReturnFor(context, fixture);
      final container = await containerFor(fixture.warehouseUser);

      expect(
        await readStream(
          container,
          warehouseGoodsReturnDetailProvider(draft.id),
          warehouseGoodsReturnDetailProvider(draft.id).future,
        ),
        isNull,
      );
    });

    test('ganti sesi mengganti hasil, bukan menyajikan cache', () async {
      final mine = await createGoodsReturnFor(context, fixture);

      final asBranch = await containerFor(fixture.branchHead);
      expect(
        (await readStream(
          asBranch,
          branchGoodsReturnListProvider,
          branchGoodsReturnListProvider.future,
        )).map((row) => row.id),
        contains(mine.id),
      );

      // A fresh container is what a session switch produces: `autoDispose` plus a
      // rebuilt session means the previous user's verdict is not reachable.
      final asOther = await containerFor(fixture.otherBranchHead);
      expect(
        (await readStream(
          asOther,
          branchGoodsReturnListProvider,
          branchGoodsReturnListProvider.future,
        )).map((row) => row.id),
        isNot(contains(mine.id)),
      );
    });

    test('provider eligibility menolak GR cabang lain', () async {
      final container = await containerFor(fixture.branchHead);

      expect(
        await container.read(
          goodsReturnEligibilityByReceiptProvider(
            fixture.otherBranchGoodReceiptId,
          ).future,
        ),
        isNull,
      );
      expect(
        await container.read(
          goodsReturnEligibilityByReceiptProvider(fixture.goodReceiptId).future,
        ),
        isNotNull,
      );
    });
  });

  group('policy', () {
    test('setiap layar punya satu peran dan satu scope', () {
      for (final kind in GoodsReturnRouteKind.values) {
        final role = GoodsReturnAccessPolicy.requiredRole(kind);
        expect(
          GoodsReturnAccessPolicy.forSection(
            user: MasterUser(
              id: 'x',
              fullName: 'X',
              email: 'x@test.local',
              role: role,
              branchId: role == UserRole.warehouse ? null : 'branch-1',
              isActive: true,
            ),
            kind: kind,
          ).isGranted,
          isTrue,
          reason: '${kind.name} harus dapat dibuka oleh ${role.label}.',
        );
        for (final other in UserRole.values.where((r) => r != role)) {
          expect(
            GoodsReturnAccessPolicy.forSection(
              user: MasterUser(
                id: 'y',
                fullName: 'Y',
                email: 'y@test.local',
                role: other,
                branchId: 'branch-1',
                isActive: true,
              ),
              kind: kind,
            ).isDenied,
            isTrue,
            reason: '${other.label} tidak boleh membuka ${kind.name}.',
          );
        }
      }
    });

    test('hanya layar cabang yang dipin ke branch', () {
      // The asymmetry this whole document turns on (§15).
      expect(
        GoodsReturnAccessPolicy.requiresBranch(
          GoodsReturnRouteKind.branchDocument,
        ),
        isTrue,
      );
      expect(
        GoodsReturnAccessPolicy.requiresBranch(
          GoodsReturnRouteKind.warehouseDocument,
        ),
        isFalse,
      );
    });

    test('akun nonaktif ditolak walau perannya benar', () {
      expect(
        GoodsReturnAccessPolicy.forSection(
          user: MasterUser(
            id: 'z',
            fullName: 'Z',
            email: 'z@test.local',
            role: UserRole.kepalaCabang,
            branchId: 'branch-1',
            isActive: false,
          ),
          kind: GoodsReturnRouteKind.branchList,
        ).reason,
        GoodsReturnAccessDenialReason.role,
      );
    });

    test('pemisahan tugas dijawab sebagai pertanyaan murni', () {
      expect(
        GoodsReturnAccessPolicy.checkSegregation(
          actorUserId: 'a',
          createdBy: 'a',
          shippedBy: 'b',
        ).reason,
        GoodsReturnAccessDenialReason.segregationOfDuties,
      );
      expect(
        GoodsReturnAccessPolicy.checkSegregation(
          actorUserId: 'b',
          createdBy: 'a',
          shippedBy: 'b',
        ).reason,
        GoodsReturnAccessDenialReason.segregationOfDuties,
      );
      expect(
        GoodsReturnAccessPolicy.checkSegregation(
          actorUserId: 'c',
          createdBy: 'a',
          shippedBy: 'b',
        ).isGranted,
        isTrue,
      );
    });
  });

  group('URL langsung', () {
    /// Every fact a refusal must not leak (§27).
    Future<void> expectNothingLeaked(
      WidgetTester tester,
      GoodsReturnDetail detail,
    ) async {
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(find.text(accessDeniedMessage), findsOneWidget);

      final forbidden = <String>[
        detail.goodsReturn.docNumber,
        detail.summary.grDocNumber,
        detail.summary.doDocNumber,
        detail.summary.prDocNumber,
        detail.summary.branchName,
        detail.summary.createdByName,
        for (final line in detail.lines) ...[
          line.itemName,
          line.sku,
          line.rejectReason,
          line.qty.format(),
        ],
      ];
      for (final text in forbidden) {
        expect(
          find.textContaining(text, findRichText: true),
          findsNothing,
          reason: 'Halaman ditolak membocorkan "$text".',
        );
      }
    }

    testWidgets('Kacab cabang lain ditolak di /returns/{id}', (tester) async {
      useTabletSurface(tester);
      final mine = await createGoodsReturnFor(context, fixture);
      final detail = (await context.goodsReturns.getDetail(mine.id))!;

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '/returns/${mine.id}',
      );

      await expectNothingLeaked(tester, detail);
      await disposeWidget(tester);
    });

    testWidgets('Warehouse ditolak membuka draft cabang', (tester) async {
      useTabletSurface(tester);
      final draft = await createGoodsReturnFor(context, fixture);
      final detail = (await context.goodsReturns.getDetail(draft.id))!;

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/returns/${draft.id}',
      );

      await expectNothingLeaked(tester, detail);
      await disposeWidget(tester);
    });

    testWidgets('Perawat ditolak di kedua bagian', (tester) async {
      useTabletSurface(tester);
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final detail = (await context.goodsReturns.getDetail(shipped.id))!;

      for (final location in [
        '/returns/${shipped.id}',
        '/warehouse/returns/${shipped.id}',
      ]) {
        await pumpAppAt(
          tester,
          context: context,
          actingAs: fixture.nurse,
          location: location,
        );
        // The redirect sends an unauthorised role home, so either outcome is a refusal
        // — what must never happen is *this document* rendering. The assertion is on
        // the RET number and the reject reasons rather than on the SKU, because a home
        // screen a nurse is entitled to may legitimately mention a product by name.
        expect(find.text(detail.goodsReturn.docNumber), findsNothing);
        for (final line in detail.lines) {
          expect(find.textContaining(line.rejectReason), findsNothing);
        }
      }
      await disposeWidget(tester);
    });

    testWidgets('id yang tidak ada dan id asing memberi respons sama', (
      tester,
    ) async {
      useTabletSurface(tester);
      final theirs = await context
          .createGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.otherBranchHead.id,
            goodReceiptId: fixture.otherBranchGoodReceiptId,
          );

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/returns/${theirs.id}',
      );
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      await disposeWidget(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/returns/id-yang-tidak-pernah-ada',
      );
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('membuat retur dari GR cabang lain ditolak di route', (
      tester,
    ) async {
      useTabletSurface(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/returns/new/${fixture.otherBranchGoodReceiptId}',
      );

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(
        await context.goodsReturnCountFor(fixture.otherBranchGoodReceiptId),
        0,
      );
      await disposeWidget(tester);
    });
  });

  group('use case memuat ulang aktor', () {
    test('akun dinonaktifkan setelah sesi dibuat tetap ditolak', () async {
      final created = await createGoodsReturnFor(context, fixture);
      await context.deactivate('users', fixture.branchHead.id);

      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<InactiveEntityFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
    });

    test('peran yang diturunkan setelah sesi dibuat tetap ditolak', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      await context.database.customStatement(
        'UPDATE users SET role = ? WHERE id = ?;',
        [UserRole.perawat.dbValue, fixture.warehouseUser.id],
      );

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
            ),
        throwsA(isA<GoodsReturnAccessDeniedFailure>()),
      );
      expect(await context.goodsReturnMovementCount(shipped.id), 0);
    });
  });

  group('tidak ada tujuan sembarang', () {
    test('repository tidak menyediakan parameter lokasi tujuan', () async {
      // The destination is resolved by *type*, once, inside the receive (§21/§24).
      // There is no parameter to pass one — the assertion here is behavioural: the
      // location the ledger credits is the one `stock_locations` says is the warehouse,
      // whatever the caller wanted.
      final received = await receivedGoodsReturnFor(context, fixture);
      final movements = await context.goodsReturnMovements(received.id);

      for (final movement in movements) {
        expect(movement['to_location_id'], fixture.warehouse.id);
        expect(movement['from_location_id'], isNull);
      }
    });
  });
}
