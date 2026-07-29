import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/opname/domain/models/opname_models.dart';
import 'package:aish_warehouse/features/opname/domain/services/opname_access_policy.dart';
import 'package:aish_warehouse/features/opname/presentation/providers/opname_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderListenable` and `Refreshable` live here rather than in the main
// barrel file in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Milestone 2.1, risk 1 — a document of another branch must not be readable,
/// however it is asked for.
///
/// The write guards were already in place and still are; what these tests are
/// about is the *read* path. A refused write that has already rendered the
/// other branch's room, nurse and quantities on screen has leaked everything
/// that mattered before it refused anything.
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildOpnameFixture(context);
  });

  tearDown(() => context.dispose());

  /// A submitted document belonging to branch A, counted by the nurse.
  Future<String> submittedInBranchA() => submitOpnameFor(context, fixture);

  /// A draft belonging to branch A's second room, so "same branch" cases have
  /// something to succeed on.
  Future<String> draftInBranchA() async {
    final opname = await context.createOpname().call(
      actorUserId: fixture.nurse.id,
      roomId: fixture.secondRoom.id,
    );
    return opname.id;
  }

  group('repository ter-scope cabang', () {
    test('detail cabang sendiri terbaca', () async {
      final id = await draftInBranchA();

      final detail = await context.opnames.getDetailForBranch(
        opnameId: id,
        branchId: fixture.branch.id,
      );

      expect(detail, isNotNull);
      expect(detail!.opname.branchId, fixture.branch.id);
    });

    test('detail cabang lain tidak terbaca', () async {
      final id = await draftInBranchA();

      final detail = await context.opnames.getDetailForBranch(
        opnameId: id,
        branchId: fixture.otherBranch.id,
      );

      expect(detail, isNull);
    });

    test(
      'stream detail cabang lain tidak pernah memancarkan dokumen',
      () async {
        final id = await submittedInBranchA();

        final emissions = await context.opnames
            .watchDetailForBranch(
              opnameId: id,
              branchId: fixture.otherBranch.id,
            )
            .take(1)
            .toList();

        expect(emissions.single, isNull);
      },
    );

    test('stream detail cabang sendiri memancarkan dokumen', () async {
      final id = await submittedInBranchA();

      final emissions = await context.opnames
          .watchDetailForBranch(opnameId: id, branchId: fixture.branch.id)
          .take(1)
          .toList();

      expect(emissions.single, isNotNull);
      expect(emissions.single!.id, id);
    });

    test(
      'access scope cabang sendiri mengembalikan status dan penghitung',
      () async {
        final id = await submittedInBranchA();

        final scope = await context.opnames.findAccessScope(
          opnameId: id,
          branchId: fixture.branch.id,
        );

        expect(scope, isNotNull);
        expect(scope!.branchId, fixture.branch.id);
        expect(scope.status.isSubmitted, isTrue);
        expect(scope.countedBy, fixture.nurse.id);
      },
    );

    test(
      'access scope cabang lain tidak dapat dibedakan dari id palsu',
      () async {
        final id = await submittedInBranchA();

        final foreign = await context.opnames.findAccessScope(
          opnameId: id,
          branchId: fixture.otherBranch.id,
        );
        final nonsense = await context.opnames.findAccessScope(
          opnameId: 'id-yang-tidak-ada',
          branchId: fixture.otherBranch.id,
        );

        // Same answer for both, which is what stops the address bar being used
        // to enumerate which document ids are real.
        expect(foreign, isNull);
        expect(nonsense, isNull);
      },
    );

    test('daftar tetap ter-scope cabang', () async {
      await submittedInBranchA();

      final own = await context.opnames.list(
        StockOpnameFilter(branchId: fixture.branch.id),
      );
      final other = await context.opnames.list(
        StockOpnameFilter(branchId: fixture.otherBranch.id),
      );

      expect(own, isNotEmpty);
      expect(other, isEmpty);
    });
  });

  group('kebijakan akses', () {
    OpnameAccess documentAccess({
      required MasterUser user,
      required OpnameRouteKind kind,
      StockOpnameAccessScope? scope,
    }) => OpnameAccessPolicy.forDocument(user: user, kind: kind, scope: scope);

    StockOpnameAccessScope scopeOf(String branchId, StockOpnameStatus status) =>
        StockOpnameAccessScope(
          opnameId: 'so-1',
          branchId: branchId,
          status: status,
          countedBy: fixture.nurse.id,
        );

    test('perawat cabang A boleh membuka dokumen cabang A', () {
      expect(
        documentAccess(
          user: fixture.nurse,
          kind: OpnameRouteKind.document,
          scope: scopeOf(fixture.branch.id, StockOpnameStatus.draft),
        ).isGranted,
        isTrue,
      );
    });

    test('perawat cabang A ditolak untuk dokumen cabang B', () {
      final access = documentAccess(
        user: fixture.nurse,
        kind: OpnameRouteKind.document,
        scope: scopeOf(fixture.otherBranch.id, StockOpnameStatus.draft),
      );

      expect(access.isDenied, isTrue);
      expect(access.reason, OpnameAccessDenialReason.documentOutOfScope);
    });

    test('kepala cabang A boleh membuka review cabang A', () {
      expect(
        documentAccess(
          user: fixture.branchHead,
          kind: OpnameRouteKind.reviewDocument,
          scope: scopeOf(fixture.branch.id, StockOpnameStatus.submitted),
        ).isGranted,
        isTrue,
      );
    });

    test('kepala cabang A ditolak untuk review cabang B', () {
      final access = documentAccess(
        user: fixture.branchHead,
        kind: OpnameRouteKind.reviewDocument,
        scope: scopeOf(fixture.otherBranch.id, StockOpnameStatus.submitted),
      );

      expect(access.reason, OpnameAccessDenialReason.documentOutOfScope);
    });

    test('perawat tidak dapat membuka layar review', () {
      final access = OpnameAccessPolicy.forSection(
        user: fixture.nurse,
        kind: OpnameRouteKind.reviewList,
      );

      expect(access.reason, OpnameAccessDenialReason.role);
    });

    test('draft belum dapat dibuka pada layar review', () {
      final access = documentAccess(
        user: fixture.branchHead,
        kind: OpnameRouteKind.reviewDocument,
        scope: scopeOf(fixture.branch.id, StockOpnameStatus.draft),
      );

      expect(access.reason, OpnameAccessDenialReason.documentStatus);
    });

    test('peran tanpa cabang ditolak seluruhnya', () {
      final access = OpnameAccessPolicy.forSection(
        user: fixture.warehouseUser,
        kind: OpnameRouteKind.list,
      );

      expect(access.reason, OpnameAccessDenialReason.role);
    });

    test('sesi kosong ditolak', () {
      final access = OpnameAccessPolicy.forSection(
        user: null,
        kind: OpnameRouteKind.list,
      );

      expect(access.reason, OpnameAccessDenialReason.noSession);
    });

    test('pesan penolakan tidak mengidentifikasi cabang atau dokumen', () {
      final message = OpnameAccess.deniedMessage.toLowerCase();

      // The wording may say the words "cabang lain" — that is the explanation.
      // What it must never carry is anything that *identifies* a branch or a
      // document, because that is what would make the address bar a probe.
      expect(message, isNot(contains(fixture.branch.code.toLowerCase())));
      expect(message, isNot(contains(fixture.otherBranch.code.toLowerCase())));
      expect(message, isNot(contains('tmp-so')));
      expect(message, isNot(contains(fixture.room.name.toLowerCase())));
      expect(message, isNot(contains(fixture.nurse.fullName.toLowerCase())));
    });
  });

  group('provider ter-scope aktor', () {
    /// Reads a stream provider while holding it open.
    ///
    /// `container.read(p.future)` alone opens and immediately closes its own
    /// subscription, so an `autoDispose` provider is torn down before its first
    /// emission ever arrives. A screen holds the provider for as long as it is
    /// on screen; this reproduces that rather than racing it.
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

    Future<ProviderContainer> containerFor(MasterUser user) async {
      final container = ProviderContainer(
        overrides: [
          // The whole graph hangs off the database provider, exactly as in the
          // app — overriding the repository alone would leave the session
          // controller reaching for a real device database.
          appDatabaseProvider.overrideWithValue(context.database),
          currentSessionProvider.overrideWith(
            () => FixedSessionController(user),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Let the session resolve before anything reads it.
      await container.read(currentSessionProvider.future);
      return container;
    }

    test('provider detail cabang A membaca dokumen cabang A', () async {
      final id = await submittedInBranchA();
      final container = await containerFor(fixture.nurse);

      final detail = await readStream(
        container,
        opnameDetailProvider(id),
        opnameDetailProvider(id).future,
      );

      expect(detail, isNotNull);
      expect(detail!.id, id);
    });

    test('provider detail cabang B tidak membaca dokumen cabang A', () async {
      final id = await submittedInBranchA();
      final container = await containerFor(fixture.otherBranchHead);

      final detail = await readStream(
        container,
        opnameDetailProvider(id),
        opnameDetailProvider(id).future,
      );

      expect(detail, isNull);
    });

    test('mengganti sesi ke cabang lain menghapus detail lama', () async {
      final id = await submittedInBranchA();
      // The real session controller this time, because switching user is the
      // behaviour under test.
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(context.database)],
      );
      addTearDown(container.dispose);

      // Keep the provider alive across both reads the way a screen would. If
      // the branch were captured once at first build, the cached document
      // would still be there after the switch — which is the leak this checks.
      final subscription = container.listen(
        opnameDetailProvider(id),
        (_, _) {},
      );
      addTearDown(subscription.close);

      final controller = container.read(currentSessionProvider.notifier);

      // Branch A's head reads the document…
      await controller.switchTo(fixture.branchHead.id);
      expect(await container.read(opnameDetailProvider(id).future), isNotNull);

      // …then the acting user becomes branch B's head.
      await controller.switchTo(fixture.otherBranchHead.id);
      expect(await container.read(opnameDetailProvider(id).future), isNull);
    });

    test('daftar perawat hanya memuat cabang aktor', () async {
      await submittedInBranchA();
      final container = await containerFor(fixture.otherBranchHead);

      final rows = await readStream(
        container,
        nurseOpnameListProvider,
        nurseOpnameListProvider.future,
      );

      expect(rows, isEmpty);
    });
  });

  group('URL langsung', () {
    testWidgets('perawat cabang A membuka dokumen cabang A', (tester) async {
      final id = await draftInBranchA();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '/opname/$id',
      );

      expect(find.text('Form Stok Opname'), findsOneWidget);
      expect(find.byKey(AccessDeniedPage.pageKey), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('perawat cabang B ditolak pada dokumen cabang A', (
      tester,
    ) async {
      final id = await submittedInBranchA();
      // A nurse of the other branch, so the role check passes and only the
      // branch check can be what refuses.
      final foreignNurse = await context.master.ensureUser(
        email: 'perawat-lain@test.local',
        fullName: 'Perawat Cabang Lain',
        role: UserRole.perawat,
        branchId: fixture.otherBranch.id,
      );

      await pumpAppAt(
        tester,
        context: context,
        actingAs: foreignNurse,
        location: '/opname/$id',
      );

      expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);
      expect(find.text(AccessDeniedPage.title), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('kepala cabang A membuka review cabang A', (tester) async {
      final id = await submittedInBranchA();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/opname/review/$id',
      );

      expect(find.text('Detail Review Opname'), findsOneWidget);
      expect(find.byKey(AccessDeniedPage.pageKey), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('kepala cabang B ditolak pada review cabang A', (tester) async {
      final id = await submittedInBranchA();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '/opname/review/$id',
      );

      expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('tidak ada data dokumen asing pada widget tree', (
      tester,
    ) async {
      final id = await submittedInBranchA();
      final docNumber = (await context.opnames.getById(id))!.docNumber;

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '/opname/review/$id',
      );

      // Nothing about the document may have reached the screen: not its
      // number, not the room, not the nurse, not the status, not a quantity.
      expect(find.textContaining(docNumber), findsNothing);
      expect(find.textContaining(fixture.room.name), findsNothing);
      expect(find.textContaining(fixture.nurse.fullName), findsNothing);
      expect(find.textContaining('Menunggu Review'), findsNothing);
      expect(find.textContaining('8 box'), findsNothing);
      expect(find.textContaining(fixture.simpleItem.name), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('id yang tidak ada memberi respons yang sama', (tester) async {
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '/opname/review/id-yang-tidak-ada',
      );

      expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('perawat diarahkan keluar dari daftar review', (tester) async {
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '/opname/review',
      );

      // The synchronous redirect sends a nurse back to their own list rather
      // than showing an inbox that would always be empty for them.
      expect(find.text('Stok Opname'), findsWidgets);
      expect(find.text('Review Stok Opname'), findsNothing);

      await disposeWidget(tester);
    });
  });

  group('penjaga tulis lama tetap berlaku', () {
    test('review dokumen cabang lain tetap ditolak use case', () async {
      final id = await submittedInBranchA();

      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.otherBranchHead.id,
          opnameId: id,
        ),
        throwsA(isA<UnauthorizedBranchFailure>()),
      );
      // And nothing moved.
      expect(await context.statusOf(id), 'submitted');
      expect(await context.movementCountFor(id), 0);
    });

    test('membuat opname di ruangan cabang lain tetap ditolak', () async {
      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.otherBranchRoom.id,
        ),
        throwsA(isA<UnauthorizedRoomFailure>()),
      );
    });
  });
}
