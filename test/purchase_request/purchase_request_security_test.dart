import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/session/acting_user_providers.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/purchase_request/domain/models/purchase_request_models.dart';
import 'package:aish_warehouse/features/purchase_request/domain/services/purchase_request_access_policy.dart';
import 'package:aish_warehouse/features/purchase_request/presentation/providers/purchase_request_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderListenable` and `Refreshable` live here rather than in the main barrel
// file in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Authorization: who may read which Purchase Request, and who may write to one.
///
/// The tests are split along the line the design draws. `PurchaseRequestAccessPolicy`
/// and the route guard decide whether a document is **fetched at all** — that is what
/// keeps a refusal from leaking a document number, an item or a quantity. The use
/// cases decide whether a write is **permitted**, and they re-read the actor from the
/// database every time, so a route reached by any other means still cannot change
/// anything.
///
/// Both halves are exercised, because either alone would be insufficient: a guard
/// without use-case checks is bypassed by any new call site, and use-case checks
/// without a guard mean the document is already on screen by the time it is refused.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  /// Two branches, each with a submitted request of its own.
  Future<
    ({
      PurchaseRequestFixture fixture,
      String ourPrId,
      String theirPrId,
      String ourDocNumber,
      String theirDocNumber,
    })
  >
  twoBranchesWithRequests() async {
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

  /// A container acting as [user], for provider-level assertions.
  Future<ProviderContainer> containerFor(MasterUser user) async {
    final container = ProviderContainer(
      overrides: [
        // The whole graph hangs off the database provider, exactly as in the app.
        appDatabaseProvider.overrideWithValue(context.database),
        currentSessionProvider.overrideWith(() => FixedSessionController(user)),
        purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
      ],
    );
    addTearDown(container.dispose);
    // Let the session resolve before anything reads it.
    await container.read(currentSessionProvider.future);
    return container;
  }

  group('kebijakan akses (murni)', () {
    MasterUser user({
      required UserRole role,
      String? branchId,
      bool isActive = true,
    }) => MasterUser(
      id: 'user-1',
      fullName: 'Pengguna Uji',
      email: 'uji@test.local',
      role: role,
      branchId: branchId,
      isActive: isActive,
    );

    test('hanya Kepala Cabang menjangkau layar cabang', () {
      for (final kind in [
        PurchaseRequestRouteKind.branchList,
        PurchaseRequestRouteKind.branchCreate,
        PurchaseRequestRouteKind.branchDocument,
        PurchaseRequestRouteKind.branchDraft,
      ]) {
        expect(
          PurchaseRequestAccessPolicy.forSection(
            user: user(role: UserRole.kepalaCabang, branchId: 'branch-1'),
            kind: kind,
          ).isGranted,
          isTrue,
        );
        for (final role in [
          UserRole.perawat,
          UserRole.warehouse,
          UserRole.superAdmin,
        ]) {
          expect(
            PurchaseRequestAccessPolicy.forSection(
              user: user(role: role, branchId: 'branch-1'),
              kind: kind,
            ).reason,
            PurchaseRequestAccessDenialReason.role,
            reason: '$role tidak boleh menjangkau $kind.',
          );
        }
      }
    });

    test('hanya Warehouse menjangkau layar warehouse', () {
      for (final kind in [
        PurchaseRequestRouteKind.warehouseQueue,
        PurchaseRequestRouteKind.warehouseDocument,
      ]) {
        // The warehouse has no branch by design, and demanding one would lock the
        // central inbox out of its own queue.
        expect(
          PurchaseRequestAccessPolicy.forSection(
            user: user(role: UserRole.warehouse),
            kind: kind,
          ).isGranted,
          isTrue,
        );
        expect(
          PurchaseRequestAccessPolicy.forSection(
            user: user(role: UserRole.kepalaCabang, branchId: 'branch-1'),
            kind: kind,
          ).isGranted,
          isFalse,
        );
      }
    });

    test('Super Admin tidak diberi akses PR secara otomatis', () {
      // Spec §3.1 grants Super Admin master data, imports and reports — not
      // "Buat & submit PR" or "Proses PR", both of which are marked for one role.
      for (final kind in PurchaseRequestRouteKind.values) {
        expect(
          PurchaseRequestAccessPolicy.forSection(
            user: user(role: UserRole.superAdmin),
            kind: kind,
          ).isGranted,
          isFalse,
        );
      }
    });

    test('akun nonaktif dan sesi kosong ditolak', () {
      expect(
        PurchaseRequestAccessPolicy.forSection(
          user: null,
          kind: PurchaseRequestRouteKind.branchList,
        ).reason,
        PurchaseRequestAccessDenialReason.noSession,
      );
      expect(
        PurchaseRequestAccessPolicy.forSection(
          user: user(
            role: UserRole.kepalaCabang,
            branchId: 'branch-1',
            isActive: false,
          ),
          kind: PurchaseRequestRouteKind.branchList,
        ).reason,
        PurchaseRequestAccessDenialReason.role,
      );
    });

    test('Kepala Cabang tanpa cabang ditolak', () {
      expect(
        PurchaseRequestAccessPolicy.forSection(
          user: user(role: UserRole.kepalaCabang),
          kind: PurchaseRequestRouteKind.branchList,
        ).reason,
        PurchaseRequestAccessDenialReason.noBranch,
      );
    });

    test('dokumen di luar scope dan tidak ada memberi jawaban yang sama', () {
      final actor = user(role: UserRole.kepalaCabang, branchId: 'branch-1');

      // `null` scope covers both cases, because the lookup that produced it was
      // branch-scoped and cannot tell them apart. That is the intended design.
      expect(
        PurchaseRequestAccessPolicy.forDocument(
          user: actor,
          kind: PurchaseRequestRouteKind.branchDocument,
          scope: null,
        ).reason,
        PurchaseRequestAccessDenialReason.documentOutOfScope,
      );
      expect(
        PurchaseRequestAccessPolicy.forDocument(
          user: actor,
          kind: PurchaseRequestRouteKind.branchDocument,
          scope: const PurchaseRequestAccessScope(
            prId: 'pr-1',
            branchId: 'branch-2',
            status: PurchaseRequestStatus.submitted,
            requestedBy: 'user-2',
          ),
        ).reason,
        PurchaseRequestAccessDenialReason.documentOutOfScope,
      );
    });

    test('editor draft menolak dokumen yang sudah dikirim (G-P5)', () {
      final actor = user(role: UserRole.kepalaCabang, branchId: 'branch-1');
      PurchaseRequestAccessScope scope(PurchaseRequestStatus status) =>
          PurchaseRequestAccessScope(
            prId: 'pr-1',
            branchId: 'branch-1',
            status: status,
            requestedBy: 'user-1',
          );

      expect(
        PurchaseRequestAccessPolicy.forDocument(
          user: actor,
          kind: PurchaseRequestRouteKind.branchDraft,
          scope: scope(PurchaseRequestStatus.draft),
        ).isGranted,
        isTrue,
      );
      for (final status in PurchaseRequestStatus.values.where(
        (status) => !status.isDraft,
      )) {
        expect(
          PurchaseRequestAccessPolicy.forDocument(
            user: actor,
            kind: PurchaseRequestRouteKind.branchDraft,
            scope: scope(status),
          ).reason,
          PurchaseRequestAccessDenialReason.documentStatus,
        );
        // The read-only detail screen, by contrast, renders every status.
        expect(
          PurchaseRequestAccessPolicy.forDocument(
            user: actor,
            kind: PurchaseRequestRouteKind.branchDocument,
            scope: scope(status),
          ).isGranted,
          isTrue,
        );
      }
    });

    test('Warehouse tidak dapat membuka draft cabang', () {
      final officer = user(role: UserRole.warehouse);

      expect(
        PurchaseRequestAccessPolicy.forDocument(
          user: officer,
          kind: PurchaseRequestRouteKind.warehouseDocument,
          scope: const PurchaseRequestAccessScope(
            prId: 'pr-1',
            branchId: 'branch-1',
            status: PurchaseRequestStatus.draft,
            requestedBy: 'user-2',
          ),
        ).reason,
        PurchaseRequestAccessDenialReason.documentStatus,
        reason: 'Draft bersifat device-authoritative sampai dikirim (G-Y2).',
      );
      // Anything from `submitted` onwards is its business, in any branch.
      expect(
        PurchaseRequestAccessPolicy.forDocument(
          user: officer,
          kind: PurchaseRequestRouteKind.warehouseDocument,
          scope: const PurchaseRequestAccessScope(
            prId: 'pr-1',
            branchId: 'branch-9',
            status: PurchaseRequestStatus.submitted,
            requestedBy: 'user-2',
          ),
        ).isGranted,
        isTrue,
      );
    });

    test('hanya layar cabang yang menuntut scope cabang', () {
      expect(
        PurchaseRequestAccessPolicy.requiresBranchScope(
          PurchaseRequestRouteKind.branchDocument,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestAccessPolicy.requiresBranchScope(
          PurchaseRequestRouteKind.warehouseDocument,
        ),
        isFalse,
      );
    });
  });

  group('scope pembacaan', () {
    test('daftar Kepala Cabang hanya memuat PR cabangnya', () async {
      final setup = await twoBranchesWithRequests();
      final container = await containerFor(setup.fixture.branchHead);

      final rows = await readStream(
        container,
        branchPurchaseRequestListProvider,
        branchPurchaseRequestListProvider.future,
      );
      expect(rows.map((summary) => summary.id), [setup.ourPrId]);
    });

    test('provider detail tidak memancarkan PR cabang lain', () async {
      final setup = await twoBranchesWithRequests();
      final container = await containerFor(setup.fixture.branchHead);

      expect(
        await readStream(
          container,
          purchaseRequestDetailProvider(setup.theirPrId),
          purchaseRequestDetailProvider(setup.theirPrId).future,
        ),
        isNull,
        reason:
            'Dokumen cabang lain tidak boleh dimuat lalu disembunyikan — '
            'seharusnya tidak dimuat sama sekali.',
      );
      expect(
        (await readStream(
          container,
          purchaseRequestDetailProvider(setup.ourPrId),
          purchaseRequestDetailProvider(setup.ourPrId).future,
        ))!.id,
        setup.ourPrId,
      );
    });

    test(
      'repository ter-scope tidak mengembalikan dokumen cabang lain',
      () async {
        final setup = await twoBranchesWithRequests();

        expect(
          await context.requests.getDetailForBranch(
            prId: setup.theirPrId,
            branchId: setup.fixture.branch.id,
          ),
          isNull,
        );
        expect(
          await context.requests.findAccessScope(
            prId: setup.theirPrId,
            branchId: setup.fixture.branch.id,
          ),
          isNull,
        );
      },
    );

    test('Warehouse membaca lintas cabang', () async {
      final setup = await twoBranchesWithRequests();
      final container = await containerFor(setup.fixture.warehouseUser);

      final queue = await readStream(
        container,
        warehousePurchaseRequestQueueProvider,
        warehousePurchaseRequestQueueProvider.future,
      );
      expect(queue.map((summary) => summary.id).toSet(), {
        setup.ourPrId,
        setup.theirPrId,
      });

      for (final prId in [setup.ourPrId, setup.theirPrId]) {
        expect(
          (await readStream(
            container,
            warehousePurchaseRequestDetailProvider(prId),
            warehousePurchaseRequestDetailProvider(prId).future,
          ))!.id,
          prId,
        );
      }
    });

    test('provider warehouse tidak melayani peran cabang', () async {
      final setup = await twoBranchesWithRequests();
      final container = await containerFor(setup.fixture.branchHead);

      expect(
        await readStream(
          container,
          warehousePurchaseRequestQueueProvider,
          warehousePurchaseRequestQueueProvider.future,
        ),
        isEmpty,
      );
      expect(
        await readStream(
          container,
          warehousePurchaseRequestDetailProvider(setup.ourPrId),
          warehousePurchaseRequestDetailProvider(setup.ourPrId).future,
        ),
        isNull,
        reason:
            'Baca tanpa scope cabang harus menolak aktor yang bukan Warehouse.',
      );
    });

    test('peran tanpa cabang tidak melihat daftar cabang mana pun', () async {
      final setup = await twoBranchesWithRequests();
      final container = await containerFor(setup.fixture.warehouseUser);

      // `branchId == null` must mean "no branch to scope to", never "every branch".
      expect(container.read(actingBranchIdProvider), isNull);
      expect(
        await readStream(
          container,
          branchPurchaseRequestListProvider,
          branchPurchaseRequestListProvider.future,
        ),
        isEmpty,
      );
    });

    test('daftar draft opname eligible juga ter-scope cabang', () async {
      final setup = await twoBranchesWithRequests();
      final container = await containerFor(setup.fixture.branchHead);

      final eligible = await container.read(eligibleOpnamesProvider.future);
      for (final reference in eligible) {
        expect(reference.branchId, setup.fixture.branch.id);
      }
    });
  });

  group('pergantian sesi', () {
    test('mengganti pengguna mengganti cabang dan mengosongkan cache', () async {
      final setup = await twoBranchesWithRequests();

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(context.database),
          currentSessionProvider.overrideWith(
            () => FixedSessionController(setup.fixture.branchHead),
          ),
          purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
        ],
      );
      addTearDown(container.dispose);

      await container.read(currentSessionProvider.future);

      // Read our own document, so it is warm in the cache.
      expect(
        (await readStream(
          container,
          purchaseRequestDetailProvider(setup.ourPrId),
          purchaseRequestDetailProvider(setup.ourPrId).future,
        ))!.id,
        setup.ourPrId,
      );
      expect(container.read(actingBranchIdProvider), setup.fixture.branch.id);

      // Switch to the other branch's head.
      await container
          .read(currentSessionProvider.notifier)
          .switchTo(setup.fixture.otherBranchHead.id);
      await container.read(currentSessionProvider.future);

      expect(
        container.read(actingBranchIdProvider),
        setup.fixture.otherBranch.id,
        reason: 'Sumber cabang tunggal harus mengikuti sesi.',
      );
      expect(
        (await container.read(actingUserProvider.future))!.id,
        setup.fixture.otherBranchHead.id,
      );

      // The previously warm document now belongs to another branch and must not be
      // served from cache.
      expect(
        await readStream(
          container,
          purchaseRequestDetailProvider(setup.ourPrId),
          purchaseRequestDetailProvider(setup.ourPrId).future,
        ),
        isNull,
      );
      expect(
        (await readStream(
          container,
          purchaseRequestDetailProvider(setup.theirPrId),
          purchaseRequestDetailProvider(setup.theirPrId).future,
        ))!.id,
        setup.theirPrId,
      );

      final rows = await readStream(
        container,
        branchPurchaseRequestListProvider,
        branchPurchaseRequestListProvider.future,
      );
      expect(rows.map((summary) => summary.id), [setup.theirPrId]);
    });

    test('actingUserProvider membaca ulang pengguna dari database', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final container = await containerFor(fixture.branchHead);

      expect(
        (await container.read(actingUserProvider.future))!.isActive,
        isTrue,
      );

      // Deactivated underneath an open session: the guard's decision must follow the
      // stored row, not the session's claim about itself (O-8).
      await context.deactivate('users', fixture.branchHead.id);
      container.invalidate(actingUserProvider);

      final reread = await container.read(actingUserProvider.future);
      expect(reread!.isActive, isFalse);
      expect(
        PurchaseRequestAccessPolicy.forSection(
          user: reread,
          kind: PurchaseRequestRouteKind.branchList,
        ).isGranted,
        isFalse,
      );
    });
  });

  group('otorisasi tulis (use case tetap penjaga terakhir)', () {
    test('Perawat tidak dapat membuat PR', () async {
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

      expect(
        () => context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: fixture.nurse.id, selectedOpnameIds: [opnameId]),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('Kepala Cabang lain tidak dapat mengirim PR cabang kita', () async {
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
      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      await expectLater(
        () => context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: fixture.otherBranchHead.id, prId: request.id),
        throwsA(isA<UnauthorizedPurchaseRequestBranchFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(request.id), 'draft');
    });

    test('Kepala Cabang lain tidak dapat membatalkan PR cabang kita', () async {
      final setup = await twoBranchesWithRequests();

      await expectLater(
        () => context
            .cancelPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.otherBranchHead.id,
              prId: setup.ourPrId,
              reason: 'Tidak berwenang',
            ),
        throwsA(isA<UnauthorizedPurchaseRequestBranchFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(setup.ourPrId), 'submitted');
    });

    test('Kepala Cabang tidak dapat memproses PR (G-R3 dua arah)', () async {
      final setup = await twoBranchesWithRequests();

      await expectLater(
        () => context
            .markPurchaseRequestProcessing(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.branchHead.id,
              prId: setup.ourPrId,
            ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(setup.ourPrId), 'submitted');
    });

    test('Warehouse tidak dapat mengubah isi PR (G-R3)', () async {
      final setup = await twoBranchesWithRequests();
      final detail = await context.requests.getDetail(setup.ourPrId);
      final line = detail!.lines.first;

      // Every editing path refuses a warehouse actor with the failure that says why
      // rather than a generic wrong-role message.
      await expectLater(
        () => context.updatePurchaseRequest.line(
          actorUserId: setup.fixture.warehouseUser.id,
          lineId: line.id,
          requestedQty: Quantity.parse('99'),
          note: 'Disesuaikan warehouse',
        ),
        throwsA(isA<WarehouseCannotEditPurchaseRequestFailure>()),
      );
      await expectLater(
        () => context.updatePurchaseRequest.header(
          actorUserId: setup.fixture.warehouseUser.id,
          prId: setup.ourPrId,
          note: 'Disesuaikan warehouse',
        ),
        throwsA(isA<WarehouseCannotEditPurchaseRequestFailure>()),
      );
      await expectLater(
        () => context.addPurchaseRequestLine.call(
          actorUserId: setup.fixture.warehouseUser.id,
          prId: setup.ourPrId,
          itemId: setup.fixture.unstockedItem.id,
          requestedQty: Quantity.parse('1'),
          note: 'Ditambahkan warehouse',
        ),
        throwsA(isA<WarehouseCannotEditPurchaseRequestFailure>()),
      );
      await expectLater(
        () => context.removePurchaseRequestLine.call(
          actorUserId: setup.fixture.warehouseUser.id,
          lineId: line.id,
        ),
        throwsA(isA<WarehouseCannotEditPurchaseRequestFailure>()),
      );
      await expectLater(
        () => context
            .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.warehouseUser.id,
              prId: setup.ourPrId,
              selectedOpnameIds: const <String>[],
            ),
        throwsA(isA<WarehouseCannotEditPurchaseRequestFailure>()),
      );

      final after = await context.requests.lineById(line.id);
      expect(after!.requestedQty, line.requestedQty);
    });

    test('Perawat tidak dapat memproses atau menolak PR', () async {
      final setup = await twoBranchesWithRequests();

      await expectLater(
        () => context
            .markPurchaseRequestProcessing(clock: prWednesdayUtc)
            .call(actorUserId: setup.fixture.nurse.id, prId: setup.ourPrId),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('aktor Warehouse nonaktif ditolak', () async {
      final setup = await twoBranchesWithRequests();
      await context.deactivate('users', setup.fixture.warehouseUser.id);

      await expectLater(
        () => context
            .markPurchaseRequestProcessing(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.warehouseUser.id,
              prId: setup.ourPrId,
            ),
        throwsA(isA<InactiveEntityFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(setup.ourPrId), 'submitted');
    });

    test('Kepala Cabang nonaktif tidak dapat mengirim PR', () async {
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
      final request = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      await context.deactivate('users', fixture.branchHead.id);

      await expectLater(
        () => context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: fixture.branchHead.id, prId: request.id),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });
  });

  group('URL langsung', () {
    testWidgets('Kepala Cabang A tidak dapat membuka PR cabang B', (
      tester,
    ) async {
      final setup = await twoBranchesWithRequests();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: setup.fixture.branchHead,
        location: '/purchase-requests/${setup.theirPrId}',
        overrides: [
          purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
        ],
      );

      expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);
      // Nothing about the foreign document may appear — not its number, not its
      // items, not its quantities.
      expect(find.textContaining(setup.theirDocNumber), findsNothing);
      expect(find.textContaining(setup.fixture.simpleItem.name), findsNothing);
      expect(find.textContaining(setup.fixture.otherBranch.name), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('Perawat tidak dapat membuka daftar PR', (tester) async {
      final setup = await twoBranchesWithRequests();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: setup.fixture.nurse,
        location: '/purchase-requests',
        overrides: [
          purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
        ],
      );

      // The router's redirect sends a nurse home, so the list never builds.
      expect(find.text('Purchase Request'), findsNothing);
      expect(find.textContaining(setup.ourDocNumber), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('Perawat tidak dapat membuka detail PR lewat URL', (
      tester,
    ) async {
      final setup = await twoBranchesWithRequests();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: setup.fixture.nurse,
        location: '/purchase-requests/${setup.ourPrId}',
        overrides: [
          purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
        ],
      );

      expect(find.textContaining(setup.ourDocNumber), findsNothing);
      expect(find.byType(TextField), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('Kepala Cabang tidak dapat membuka antrean Warehouse', (
      tester,
    ) async {
      final setup = await twoBranchesWithRequests();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: setup.fixture.branchHead,
        location: '/warehouse/purchase-requests',
        overrides: [
          purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
        ],
      );

      expect(find.text('PR Masuk'), findsNothing);
      expect(find.textContaining(setup.theirDocNumber), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('editor draft menolak PR yang sudah dikirim', (tester) async {
      final setup = await twoBranchesWithRequests();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: setup.fixture.branchHead,
        location: '/purchase-requests/${setup.ourPrId}/edit',
        overrides: [
          purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
        ],
      );

      expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);
      // No input of any kind reached the tree.
      expect(find.byType(TextField), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('Warehouse tidak dapat membuka draft cabang lewat URL', (
      tester,
    ) async {
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

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        location: '/warehouse/purchase-requests/${draft.id}',
        overrides: [
          purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
        ],
      );

      expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);
      expect(find.textContaining(draft.docNumber), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('Warehouse dapat membuka PR submitted cabang mana pun', (
      tester,
    ) async {
      final setup = await twoBranchesWithRequests();

      await pumpAppAt(
        tester,
        context: context,
        actingAs: setup.fixture.warehouseUser,
        location: '/warehouse/purchase-requests/${setup.theirPrId}',
        overrides: [
          purchaseRequestClockProvider.overrideWithValue(prWednesdayUtc),
        ],
      );

      expect(find.byKey(AccessDeniedPage.pageKey), findsNothing);
      expect(find.text(setup.theirDocNumber), findsOneWidget);

      await disposeWidget(tester);
    });
  });
}
