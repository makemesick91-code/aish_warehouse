import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/disposal/domain/services/disposal_access_policy.dart';
import 'package:aish_warehouse/features/disposal/domain/services/disposal_location_policy.dart';
import 'package:aish_warehouse/features/disposal/domain/services/disposal_state_policy.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Who may destroy what, and where (§40).
///
/// Two roles, two disjoint scopes, and the whole point of the milestone's access
/// design is that neither can reach the other's. A warehouse account destroys what
/// expired at Warehouse Pusat; a Kepala Cabang destroys what expired in their own
/// *Gudang Cabang* and rooms. A nurse and a Super Admin destroy nothing at all.
///
/// The refusals are asserted at the **use case** rather than at the policy alone,
/// because the policy is only the first of three answers: the SQL predicate stops a
/// foreign document being fetched, the route guard stops the screen rendering, and
/// the use case is the one that actually refuses a write. A test that only exercised
/// the policy would pass on a build where the use case had stopped calling it.
void main() {
  final nowUtc = DateTime.utc(2026, 7, 30, 4);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> create({
    required String actorUserId,
    required String sourceLocationId,
  }) => createDisposalDraft(
    context,
    fixture,
    sourceLocationId: sourceLocationId,
    nowUtc: nowUtc,
    actorUserId: actorUserId,
    reason: 'Kedaluwarsa',
  );

  group('Warehouse', () {
    test('dapat memusnahkan stok Warehouse Pusat', () async {
      final id = await create(
        actorUserId: fixture.warehouseUser.id,
        sourceLocationId: fixture.warehouse.id,
      );
      final disposal = await context.disposals.getById(id);
      expect(disposal!.sourceLocationId, fixture.warehouse.id);
      expect(disposal.createdBy, fixture.warehouseUser.id);
    });

    test('tidak dapat memusnahkan stok Gudang Cabang', () async {
      await expectLater(
        create(
          actorUserId: fixture.warehouseUser.id,
          sourceLocationId: fixture.branchStore.id,
        ),
        throwsA(isA<DisposalSourceLocationAccessDeniedFailure>()),
      );
    });

    test('tidak dapat memusnahkan stok Ruangan', () async {
      await expectLater(
        create(
          actorUserId: fixture.warehouseUser.id,
          sourceLocationId: fixture.locationOne.id,
        ),
        throwsA(isA<DisposalSourceLocationAccessDeniedFailure>()),
      );
    });

    test('tidak dapat memposting dokumen cabang', () async {
      // The scope is re-checked inside the posting transaction, not merely at
      // creation: a document raised legitimately by one actor must not become
      // postable by another.
      final id = await create(
        actorUserId: fixture.branchHead.id,
        sourceLocationId: fixture.branchStore.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
      );

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
        throwsA(isA<DisposalSourceLocationAccessDeniedFailure>()),
      );
      expect(await context.disposalStatusOf(id), 'draft');
      expect(await context.disposalMovementCount(id), 0);
    });
  });

  group('Kepala Cabang', () {
    test('dapat memusnahkan stok Gudang Cabang sendiri', () async {
      final id = await create(
        actorUserId: fixture.branchHead.id,
        sourceLocationId: fixture.branchStore.id,
      );
      expect(
        (await context.disposals.getById(id))!.sourceLocationId,
        fixture.branchStore.id,
      );
    });

    test('dapat memusnahkan stok Ruangan sendiri', () async {
      final id = await create(
        actorUserId: fixture.branchHead.id,
        sourceLocationId: fixture.locationOne.id,
      );
      expect(
        (await context.disposals.getById(id))!.sourceLocationId,
        fixture.locationOne.id,
      );
    });

    test('tidak dapat memusnahkan stok Warehouse Pusat', () async {
      await expectLater(
        create(
          actorUserId: fixture.branchHead.id,
          sourceLocationId: fixture.warehouse.id,
        ),
        throwsA(isA<DisposalSourceLocationAccessDeniedFailure>()),
      );
    });

    test('tidak dapat memusnahkan Gudang Cabang lain', () async {
      await expectLater(
        create(
          actorUserId: fixture.branchHead.id,
          sourceLocationId: fixture.otherBranchStore.id,
        ),
        throwsA(isA<DisposalBranchMismatchFailure>()),
      );
    });

    test('tidak dapat memusnahkan Ruangan cabang lain', () async {
      await expectLater(
        create(
          actorUserId: fixture.branchHead.id,
          sourceLocationId: fixture.otherBranchRoomLocation.id,
        ),
        throwsA(isA<DisposalBranchMismatchFailure>()),
      );
    });

    test(
      'Kepala Cabang lain tidak dapat memposting dokumen cabang ini',
      () async {
        final id = await create(
          actorUserId: fixture.branchHead.id,
          sourceLocationId: fixture.branchStore.id,
        );
        await addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
          qty: '1',
          nowUtc: nowUtc,
          actorUserId: fixture.branchHead.id,
        );

        await expectLater(
          context
              .postDisposal(clock: () => nowUtc)
              .call(actorUserId: fixture.otherBranchHead.id, disposalId: id),
          throwsA(isA<DisposalBranchMismatchFailure>()),
        );
        expect(await context.disposalStatusOf(id), 'draft');
      },
    );
  });

  group('peran tanpa cakupan', () {
    test('Perawat ditolak', () async {
      // A nurse sees the expiry badges through the stock module (G-E6). What they do
      // not get is a document that removes inventory.
      await expectLater(
        create(
          actorUserId: fixture.nurse.id,
          sourceLocationId: fixture.locationOne.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('Super Admin ditolak', () async {
      // Widening a workflow permission because an account is powerful is exactly the
      // quiet grant G-R4 is about.
      await expectLater(
        create(
          actorUserId: fixture.superAdmin.id,
          sourceLocationId: fixture.warehouse.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('Perawat tidak dapat menambah baris pada draft cabang', () async {
      final id = await create(
        actorUserId: fixture.branchHead.id,
        sourceLocationId: fixture.branchStore.id,
      );

      await expectLater(
        addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
          qty: '1',
          nowUtc: nowUtc,
          actorUserId: fixture.nurse.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(await context.disposalLineCount(id), 0);
    });

    test('Super Admin tidak dapat memposting', () async {
      final id = await create(
        actorUserId: fixture.warehouseUser.id,
        sourceLocationId: fixture.warehouse.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.superAdmin.id, disposalId: id),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(await context.disposalMovementCount(id), 0);
    });
  });

  group('aktor yang berubah', () {
    test('akun nonaktif ditolak', () async {
      // Unlike the item or batch data a historic document points at, the person
      // destroying stock *right now* has to be a currently valid account (§14).
      await context.deactivate('users', fixture.warehouseUser.id);

      await expectLater(
        create(
          actorUserId: fixture.warehouseUser.id,
          sourceLocationId: fixture.warehouse.id,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test(
      'akun yang dinonaktifkan setelah draft tidak dapat memposting',
      () async {
        final id = await create(
          actorUserId: fixture.warehouseUser.id,
          sourceLocationId: fixture.warehouse.id,
        );
        await addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        );
        await context.deactivate('users', fixture.warehouseUser.id);

        await expectLater(
          context
              .postDisposal(clock: () => nowUtc)
              .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
          throwsA(isA<InactiveEntityFailure>()),
        );
        expect(await context.disposalStatusOf(id), 'draft');
        expect(await context.disposalMovementCount(id), 0);
      },
    );

    test('aktor yang tidak ada ditolak', () async {
      await expectLater(
        create(
          actorUserId: 'pengguna-yang-tidak-ada',
          sourceLocationId: fixture.warehouse.id,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });
  });

  group('lokasi sumber', () {
    test('lokasi yang tidak ada ditolak', () async {
      await expectLater(
        create(
          actorUserId: fixture.warehouseUser.id,
          sourceLocationId: 'lokasi-yang-tidak-ada',
        ),
        throwsA(isA<DisposalSourceLocationNotFoundFailure>()),
      );
    });

    test('lokasi yang diarsipkan ditolak untuk dokumen baru', () async {
      await context.archive('stock_locations', fixture.locationTwo.id);

      await expectLater(
        create(
          actorUserId: fixture.branchHead.id,
          sourceLocationId: fixture.locationTwo.id,
        ),
        throwsA(isA<DisposalSourceLocationInactiveFailure>()),
      );
    });

    test('satu dokumen hanya memiliki satu lokasi sumber', () async {
      // Structural rather than checked: there is no writer anywhere — not on the
      // repository, not on the DAO, not in SQL — that can change
      // `source_location_id`, so a second source is not expressible.
      final id = await create(
        actorUserId: fixture.branchHead.id,
        sourceLocationId: fixture.branchStore.id,
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
      );

      final lines = await context.disposalLineRows(id);
      expect(lines, hasLength(1));
      // Every line draws from the header's location; there is no per-line column.
      final columns = await context.database
          .customSelect('PRAGMA table_xinfo(disposal_lines);')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains('location_id')),
      );
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains('source_location_id')),
      );
    });
  });

  group('kebijakan murni', () {
    MasterUser userWith(UserRole role, {String? branchId}) => MasterUser(
      id: 'u',
      fullName: 'Uji',
      email: 'u@test.local',
      role: role,
      branchId: branchId,
      isActive: true,
    );

    MasterLocation locationOf(
      StockLocationType type, {
      String? branchId,
      String? roomId,
    }) => MasterLocation(
      id: 'l',
      type: type,
      branchId: branchId,
      roomId: roomId,
      name: 'Lokasi',
    );

    test(
      'Warehouse Pusat dikenali dari tipe, bukan dari id yang di-hardcode',
      () {
        // The only definition that survives a second installation being seeded, or a
        // second warehouse being opened.
        expect(
          DisposalLocationPolicy.verifySource(
            actor: userWith(UserRole.warehouse),
            location: locationOf(StockLocationType.warehouse),
          ).isAccepted,
          isTrue,
        );
      },
    );

    test('tipe yang diizinkan per peran', () {
      expect(DisposalLocationPolicy.allowedTypesFor(UserRole.warehouse), {
        StockLocationType.warehouse,
      });
      expect(DisposalLocationPolicy.allowedTypesFor(UserRole.kepalaCabang), {
        StockLocationType.branchStore,
        StockLocationType.room,
      });
      expect(DisposalLocationPolicy.allowedTypesFor(UserRole.perawat), isEmpty);
      expect(
        DisposalLocationPolicy.allowedTypesFor(UserRole.superAdmin),
        isEmpty,
      );
    });

    test('hanya peran cabang yang di-scope per cabang', () {
      expect(
        DisposalLocationPolicy.requiresBranchScope(UserRole.kepalaCabang),
        isTrue,
      );
      expect(
        DisposalLocationPolicy.requiresBranchScope(UserRole.warehouse),
        isFalse,
      );
    });

    test('Kepala Cabang tanpa cabang ditolak', () {
      final verdict = DisposalLocationPolicy.verifySource(
        actor: userWith(UserRole.kepalaCabang),
        location: locationOf(StockLocationType.branchStore, branchId: 'b1'),
      );
      expect(verdict.rejection, DisposalSourceRejection.actorHasNoBranch);
    });

    test('lokasi ruangan tanpa room_id ditolak sebagai bentuk yang korup', () {
      final verdict = DisposalLocationPolicy.verifySource(
        actor: userWith(UserRole.kepalaCabang, branchId: 'b1'),
        location: locationOf(StockLocationType.room, branchId: 'b1'),
      );
      expect(verdict.rejection, DisposalSourceRejection.locationShapeInvalid);
    });

    test('state machine hanya mengizinkan draft → posted', () {
      expect(
        DisposalStatePolicy.isAllowed(
          DisposalStatus.draft,
          DisposalStatus.posted,
        ),
        isTrue,
      );
      expect(
        DisposalStatePolicy.isAllowed(
          DisposalStatus.posted,
          DisposalStatus.draft,
        ),
        isFalse,
      );
      expect(
        DisposalStatePolicy.isAllowed(
          DisposalStatus.posted,
          DisposalStatus.posted,
        ),
        isFalse,
      );
      expect(
        DisposalStatePolicy.isAllowed(
          DisposalStatus.draft,
          DisposalStatus.draft,
        ),
        isFalse,
      );
      expect(DisposalStatePolicy.nextStatesOf(DisposalStatus.posted), isEmpty);
    });

    test('kedua peran penulis dapat mendorong transisi yang sama', () {
      for (final role in const [UserRole.warehouse, UserRole.kepalaCabang]) {
        expect(
          DisposalStatePolicy.isAllowedFor(
            role: role,
            from: DisposalStatus.draft,
            to: DisposalStatus.posted,
          ),
          isTrue,
          reason: '$role harus dapat memposting pemusnahan pada cakupannya.',
        );
      }
      for (final role in const [UserRole.perawat, UserRole.superAdmin]) {
        expect(
          DisposalStatePolicy.isAllowedFor(
            role: role,
            from: DisposalStatus.draft,
            to: DisposalStatus.posted,
          ),
          isFalse,
        );
      }
    });

    test('setiap layar memiliki cakupan dan peran yang pasti', () {
      // Never null: there is no Pemusnahan screen that spans both sides, and having
      // no way to express one is what stops an unscoped lookup being introduced.
      for (final kind in DisposalRouteKind.values) {
        final scope = DisposalAccessPolicy.requiredScope(kind);
        expect(
          DisposalAccessPolicy.requiredRole(kind),
          scope == DisposalLocationScope.warehouse
              ? UserRole.warehouse
              : UserRole.kepalaCabang,
        );
      }
    });

    test('editor hanya menerima draft', () {
      for (final kind in const [
        DisposalRouteKind.warehouseDraft,
        DisposalRouteKind.branchDraft,
      ]) {
        expect(DisposalAccessPolicy.visibleStatusesFor(kind), {
          DisposalStatus.draft,
        });
      }
    });
  });
}
