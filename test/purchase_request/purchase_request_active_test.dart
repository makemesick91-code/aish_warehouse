import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-P4 — only one `submitted`/`processing` Purchase Request per branch at a time.
///
/// The rule is enforced twice, and both halves are tested here. The use case checks
/// first so the branch head gets a sentence naming the order already in flight; the
/// partial unique index
/// `(branch_id) WHERE status IN ('submitted','processing') AND deleted_at IS NULL`
/// is the guarantee, and it is what makes two devices submitting at the same moment
/// produce exactly one active order rather than two.
///
/// Everything the rule deliberately *permits* follows from that WHERE clause, so each
/// permission gets its own test: several drafts do not collide, and a cancelled,
/// rejected, shipped or closed request releases the slot.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  /// A branch with two citable counts, one per room.
  Future<({PurchaseRequestFixture fixture, String opnameOne, String opnameTwo})>
  branchWithCounts() async {
    final fixture = await buildPurchaseRequestFixture(
      context,
      now: prWednesdayUtc(),
    );
    final one = await fileOpnameForRoom(
      context,
      roomId: fixture.roomOne.id,
      nurseId: fixture.nurse.id,
      utcNow: prWednesdayUtc(),
    );
    final two = await fileOpnameForRoom(
      context,
      roomId: fixture.roomTwo.id,
      nurseId: fixture.nurse.id,
      utcNow: prWednesdayUtc(),
    );
    return (fixture: fixture, opnameOne: one, opnameTwo: two);
  }

  Future<String> createDraft(
    PurchaseRequestFixture fixture,
    List<String> opnameIds,
  ) async {
    final request = await context
        .createPurchaseRequest(clock: prWednesdayUtc)
        .call(actorUserId: fixture.branchHead.id, selectedOpnameIds: opnameIds);
    return request.id;
  }

  Future<void> submit(PurchaseRequestFixture fixture, String prId) => context
      .submitPurchaseRequest(clock: prWednesdayUtc)
      .call(actorUserId: fixture.branchHead.id, prId: prId);

  group('yang diizinkan', () {
    test('draft tidak memblokir draft lain', () async {
      final setup = await branchWithCounts();

      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      final second = await createDraft(setup.fixture, [setup.opnameTwo]);

      expect(first, isNot(second));
      expect(await context.purchaseRequestStatusOf(first), 'draft');
      expect(await context.purchaseRequestStatusOf(second), 'draft');
      expect(
        await context.activePurchaseRequestCount(setup.fixture.branch.id),
        0,
        reason: 'Draft tidak menempati slot aktif.',
      );
    });

    test('cabang lain dapat memiliki PR aktif sendiri', () async {
      final setup = await branchWithCounts();
      final otherCount = await fileOpnameForRoom(
        context,
        roomId: setup.fixture.otherBranchRoom.id,
        nurseId: setup.fixture.otherBranchNurse.id,
        utcNow: prWednesdayUtc(),
      );

      final ours = await createDraft(setup.fixture, [setup.opnameOne]);
      await submit(setup.fixture, ours);

      final theirs = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.otherBranchHead.id,
            selectedOpnameIds: [otherCount],
          );
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.otherBranchHead.id, prId: theirs.id);

      expect(
        await context.activePurchaseRequestCount(setup.fixture.branch.id),
        1,
      );
      expect(
        await context.activePurchaseRequestCount(setup.fixture.otherBranch.id),
        1,
      );
    });

    test('membatalkan PR submitted membebaskan slot', () async {
      final setup = await branchWithCounts();

      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      final second = await createDraft(setup.fixture, [setup.opnameTwo]);
      await submit(setup.fixture, first);

      await context
          .cancelPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.branchHead.id,
            prId: first,
            reason: 'Salah pilih ruangan acuan',
          );

      await submit(setup.fixture, second);
      expect(await context.purchaseRequestStatusOf(second), 'submitted');
      expect(
        await context.activePurchaseRequestCount(setup.fixture.branch.id),
        1,
      );
    });

    test('PR yang ditolak Warehouse membebaskan slot', () async {
      final setup = await branchWithCounts();

      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      final second = await createDraft(setup.fixture, [setup.opnameTwo]);
      await submit(setup.fixture, first);
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: first);
      await context
          .rejectPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.warehouseUser.id,
            prId: first,
            reason: 'Stok warehouse kosong',
          );

      await submit(setup.fixture, second);
      expect(await context.purchaseRequestStatusOf(second), 'submitted');
    });

    test('PR shipped dan closed membebaskan slot', () async {
      final setup = await branchWithCounts();
      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      final second = await createDraft(setup.fixture, [setup.opnameTwo]);
      await submit(setup.fixture, first);
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: first);

      // `shipped` and `closed` are Delivery Order and Good Receipt territory, so no
      // use case reaches them yet. The index behaviour they will rely on is testable
      // now, which is the point of having them in the enum and the schema already.
      await context.database.customStatement(
        "UPDATE purchase_requests SET status = 'shipped' WHERE id = ?;",
        [first],
      );
      await submit(setup.fixture, second);
      expect(await context.purchaseRequestStatusOf(second), 'submitted');

      await context.database.customStatement(
        "UPDATE purchase_requests SET status = 'closed' WHERE id = ?;",
        [first],
      );
      expect(
        await context.activePurchaseRequestCount(setup.fixture.branch.id),
        1,
        reason: 'Hanya `second` yang aktif; closed tidak menempati slot.',
      );
    });

    test('PR soft-deleted tidak memblokir', () async {
      final setup = await branchWithCounts();
      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      final second = await createDraft(setup.fixture, [setup.opnameTwo]);
      await submit(setup.fixture, first);

      // Only a sync payload could produce this; the app has no path to soft-delete a
      // submitted document. The index must still be scoped to live rows.
      await context.archive('purchase_requests', first);

      await submit(setup.fixture, second);
      expect(
        await context.activePurchaseRequestCount(setup.fixture.branch.id),
        1,
      );
    });
  });

  group('yang diblokir', () {
    test('PR submitted memblokir submit kedua', () async {
      final setup = await branchWithCounts();
      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      final second = await createDraft(setup.fixture, [setup.opnameTwo]);
      await submit(setup.fixture, first);

      await expectLater(
        () => submit(setup.fixture, second),
        throwsA(
          isA<PurchaseRequestAlreadyActiveFailure>()
              .having(
                (failure) => failure.branchId,
                'branchId',
                setup.fixture.branch.id,
              )
              .having((failure) => failure.activePrId, 'activePrId', first),
        ),
      );
      expect(await context.purchaseRequestStatusOf(second), 'draft');
      expect(
        await context.activePurchaseRequestCount(setup.fixture.branch.id),
        1,
      );
    });

    test('PR processing memblokir submit kedua', () async {
      final setup = await branchWithCounts();
      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      final second = await createDraft(setup.fixture, [setup.opnameTwo]);
      await submit(setup.fixture, first);
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: first);

      await expectLater(
        () => submit(setup.fixture, second),
        throwsA(isA<PurchaseRequestAlreadyActiveFailure>()),
      );
      expect(
        await context.activePurchaseRequestCount(setup.fixture.branch.id),
        1,
      );
    });

    test('PR aktif memblokir pembuatan draft baru', () async {
      final setup = await branchWithCounts();
      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      await submit(setup.fixture, first);

      // Checked at creation rather than only at submit: a branch already waiting on
      // the warehouse would otherwise type a whole request before being refused.
      await expectLater(
        () => createDraft(setup.fixture, [setup.opnameTwo]),
        throwsA(isA<PurchaseRequestAlreadyActiveFailure>()),
      );
    });

    test(
      'index parsial menolak submitted kedua meski use case dilewati',
      () async {
        final setup = await branchWithCounts();
        final first = await createDraft(setup.fixture, [setup.opnameOne]);
        final second = await createDraft(setup.fixture, [setup.opnameTwo]);
        await submit(setup.fixture, first);

        // Straight through SQL, so the use case's own check cannot be what refuses it.
        await expectLater(
          () => context.database.customStatement(
            "UPDATE purchase_requests SET status = 'submitted', "
            'submitted_at = ? WHERE id = ?;',
            ['2026-07-29T04:00:00.000Z', second],
          ),
          throwsA(anything),
          reason:
              'Index unik parsial adalah penjaga terakhir G-P4, bukan use case.',
        );
      },
    );

    test('submit bersamaan menghasilkan tepat satu PR aktif', () async {
      final setup = await branchWithCounts();
      final first = await createDraft(setup.fixture, [setup.opnameOne]);
      final second = await createDraft(setup.fixture, [setup.opnameTwo]);

      // Both submits are started before either completes — the race two devices
      // produce. `Future.wait` with `eagerError: false` lets both settle so the
      // outcome can be inspected rather than the first failure aborting the other.
      final outcomes = await Future.wait([
        submit(setup.fixture, first)
            .then((_) => 'ok')
            .catchError((Object error) => error.runtimeType.toString()),
        submit(setup.fixture, second)
            .then((_) => 'ok')
            .catchError((Object error) => error.runtimeType.toString()),
      ], eagerError: false);

      expect(
        outcomes.where((outcome) => outcome == 'ok'),
        hasLength(1),
        reason: 'Tepat satu submit boleh berhasil.',
      );
      expect(
        await context.activePurchaseRequestCount(setup.fixture.branch.id),
        1,
        reason:
            'Apa pun yang terjadi pada lapisan Dart, database hanya boleh '
            'memuat satu PR aktif per cabang.',
      );
    });
  });

  group('lookup PR aktif', () {
    test('mengembalikan PR aktif cabang, bukan draft', () async {
      final setup = await branchWithCounts();
      final draft = await createDraft(setup.fixture, [setup.opnameOne]);

      expect(
        await context.requests.activeRequestForBranch(setup.fixture.branch.id),
        isNull,
      );

      await submit(setup.fixture, draft);
      final active = await context.requests.activeRequestForBranch(
        setup.fixture.branch.id,
      );
      expect(active!.id, draft);
      expect(active.isActiveOrder, isTrue);
    });

    test('tidak mengembalikan PR cabang lain', () async {
      final setup = await branchWithCounts();
      final draft = await createDraft(setup.fixture, [setup.opnameOne]);
      await submit(setup.fixture, draft);

      expect(
        await context.requests.activeRequestForBranch(
          setup.fixture.otherBranch.id,
        ),
        isNull,
      );
    });
  });
}
