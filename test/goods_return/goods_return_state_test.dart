import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/goods_return/domain/models/goods_return_models.dart';
import 'package:aish_warehouse/features/goods_return/domain/services/goods_return_state_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The state machine and segregation of duties (§14/§15/§20/§43).
///
/// ```
/// draft ──▶ shipped ──▶ received   (final)
/// ```
///
/// Two transitions, two different roles, and a document that is read-only forever once
/// it lands. The rule with the most weight here is G-R4 — *"tidak ada satu peran pun
/// yang bisa membuat sekaligus menyetujui dokumen yang sama"* — which this is the first
/// document in the schema to enforce structurally rather than to cite as a reason for
/// having no approval stage at all.
///
/// The two segregation tests that matter most are the ones where a **role changed**.
/// Every role check in the application would let a former Kepala Cabang who has moved
/// to the Warehouse team confirm a return they themselves raised; only comparing user
/// *ids* catches it, and that comparison lives in three places (§15).
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('policy murni', () {
    test('hanya dua transisi yang diizinkan', () {
      expect(GoodsReturnStatePolicy.nextStatesOf(GoodsReturnStatus.draft), {
        GoodsReturnStatus.shipped,
      });
      expect(GoodsReturnStatePolicy.nextStatesOf(GoodsReturnStatus.shipped), {
        GoodsReturnStatus.received,
      });
      expect(
        GoodsReturnStatePolicy.nextStatesOf(GoodsReturnStatus.received),
        isEmpty,
      );
    });

    test('transisi terlarang ditolak oleh policy', () {
      const forbidden = <(GoodsReturnStatus, GoodsReturnStatus)>[
        // Skipping transit would credit the Warehouse for goods nobody has sent.
        (GoodsReturnStatus.draft, GoodsReturnStatus.received),
        (GoodsReturnStatus.shipped, GoodsReturnStatus.draft),
        (GoodsReturnStatus.received, GoodsReturnStatus.shipped),
        (GoodsReturnStatus.received, GoodsReturnStatus.draft),
        (GoodsReturnStatus.received, GoodsReturnStatus.received),
        (GoodsReturnStatus.draft, GoodsReturnStatus.draft),
        (GoodsReturnStatus.shipped, GoodsReturnStatus.shipped),
      ];
      for (final (from, to) in forbidden) {
        expect(
          GoodsReturnStatePolicy.isAllowed(from, to),
          isFalse,
          reason: '${from.dbValue} → ${to.dbValue} tidak boleh diizinkan.',
        );
        expect(
          from.canTransitionTo(to),
          isFalse,
          reason: 'Enum dan policy harus sepakat tentang ${from.dbValue}.',
        );
      }
    });

    test('setiap transisi punya satu peran', () {
      expect(
        GoodsReturnStatePolicy.isAllowedFor(
          role: UserRole.kepalaCabang,
          from: GoodsReturnStatus.draft,
          to: GoodsReturnStatus.shipped,
        ),
        isTrue,
      );
      expect(
        GoodsReturnStatePolicy.isAllowedFor(
          role: UserRole.warehouse,
          from: GoodsReturnStatus.draft,
          to: GoodsReturnStatus.shipped,
        ),
        isFalse,
      );
      expect(
        GoodsReturnStatePolicy.isAllowedFor(
          role: UserRole.warehouse,
          from: GoodsReturnStatus.shipped,
          to: GoodsReturnStatus.received,
        ),
        isTrue,
      );
      expect(
        GoodsReturnStatePolicy.isAllowedFor(
          role: UserRole.kepalaCabang,
          from: GoodsReturnStatus.shipped,
          to: GoodsReturnStatus.received,
        ),
        isFalse,
      );
    });

    test('Perawat dan Super Admin tidak punya peran apa pun', () {
      for (final role in const [UserRole.perawat, UserRole.superAdmin]) {
        expect(GoodsReturnStatePolicy.actorOf(role), isNull);
        expect(GoodsReturnStatePolicy.writeRoles.contains(role), isFalse);
      }
    });
  });

  group('pengiriman oleh Kepala Cabang', () {
    test('Kacab cabang sendiri dapat mengirim draft', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final shipped = await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: created.id);

      expect(shipped.status, GoodsReturnStatus.shipped);
      expect(shipped.shippedBy, fixture.branchHead.id);
      expect(shipped.shippedAt, isNotNull);
      expect(shipped.shippedAt!.isUtc, isTrue);
      expect(shipped.receivedAt, isNull);
      expect(shipped.receivedBy, isNull);
      expect(shipped.syncStatus, SyncStatus.pending);
    });

    test('pengiriman tidak menulis movement dan tidak mengubah saldo', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      final branchBefore = await context.balancesAt(fixture.branchStore.id);
      final movementsBefore = await context.totalMovementCount();

      await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: created.id);

      // The rule §20 exists for: the goods are on a road, and the Warehouse balance
      // must not move until somebody has counted them in.
      expect(await context.goodsReturnMovementCount(created.id), 0);
      expect(await context.totalMovementCount(), movementsBefore);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
      expect(await context.balancesAt(fixture.branchStore.id), branchBefore);
    });

    test('Kacab cabang lain ditolak', () async {
      final created = await createGoodsReturnFor(context, fixture);

      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.otherBranchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<GoodsReturnBranchMismatchFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
    });

    test('Warehouse, Perawat dan Super Admin tidak dapat mengirim', () async {
      final created = await createGoodsReturnFor(context, fixture);

      for (final actor in [
        fixture.warehouseUser,
        fixture.nurse,
        fixture.superAdmin,
      ]) {
        await expectLater(
          context
              .shipGoodsReturn(clock: () => nowUtc)
              .call(actorUserId: actor.id, goodsReturnId: created.id),
          throwsA(isA<GoodsReturnAccessDeniedFailure>()),
          reason: '${actor.role.label} tidak boleh mengirim retur.',
        );
      }
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
    });

    test('pengiriman ganda ditolak', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: shipped.id,
            ),
        throwsA(isA<GoodsReturnAlreadyShippedFailure>()),
      );
    });

    test('shippedAt lebih awal dari createdAt ditolak', () async {
      final created = await createGoodsReturnFor(context, fixture);

      // One microsecond is enough. Equal instants are accepted — two events really can
      // land on the same microsecond on a fast device (§39).
      await expectLater(
        context
            .shipGoodsReturn(
              clock: () =>
                  created.createdAt.subtract(const Duration(microseconds: 1)),
            )
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<InvalidGoodsReturnTimestampFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');

      final same = await context
          .shipGoodsReturn(clock: () => created.createdAt)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: created.id);
      expect(same.status, GoodsReturnStatus.shipped);
    });
  });

  group('penerimaan oleh Warehouse', () {
    test('Warehouse dapat menerima retur yang dikirim', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      final received = await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: shipped.id,
          );

      expect(received.status, GoodsReturnStatus.received);
      expect(received.goodsReturn.receivedBy, fixture.warehouseUser.id);
      expect(received.goodsReturn.receivedAt, isNotNull);
      expect(received.goodsReturn.receivedAt!.isUtc, isTrue);
      expect(received.isFinal, isTrue);
    });

    test('Warehouse tidak dapat menerima draft', () async {
      final created = await createGoodsReturnFor(context, fixture);

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<InvalidGoodsReturnStateFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
      expect(await context.goodsReturnMovementCount(created.id), 0);
    });

    test('Kacab, Perawat dan Super Admin tidak dapat menerima', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      for (final actor in [
        fixture.branchHead,
        fixture.otherBranchHead,
        fixture.nurse,
        fixture.superAdmin,
      ]) {
        await expectLater(
          context
              .receiveGoodsReturn(clock: () => nowUtc)
              .call(actorUserId: actor.id, goodsReturnId: shipped.id),
          throwsA(isA<GoodsReturnAccessDeniedFailure>()),
          reason: '${actor.role.label} tidak boleh menerima retur.',
        );
      }
      expect(await context.goodsReturnStatusOf(shipped.id), 'shipped');
      expect(await context.goodsReturnMovementCount(shipped.id), 0);
    });

    test('penerimaan ganda ditolak dan tidak menggandakan movement', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: shipped.id,
          );
      final afterFirst = await context.balancesAt(fixture.warehouse.id);

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.secondWarehouseUser.id,
              goodsReturnId: shipped.id,
            ),
        throwsA(isA<GoodsReturnAlreadyReceivedFailure>()),
      );
      expect(await context.goodsReturnMovementCount(shipped.id), 2);
      expect(await context.balancesAt(fixture.warehouse.id), afterFirst);
    });

    test('receivedAt lebih awal dari shippedAt ditolak', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await expectLater(
        context
            .receiveGoodsReturn(
              clock: () =>
                  shipped.shippedAt!.subtract(const Duration(microseconds: 1)),
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
            ),
        throwsA(isA<InvalidGoodsReturnTimestampFailure>()),
      );
      expect(await context.goodsReturnStatusOf(shipped.id), 'shipped');
      expect(await context.goodsReturnMovementCount(shipped.id), 0);
    });

    test('catatan Warehouse tersimpan, spasi saja ditolak', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
              warehouseNote: '   ',
            ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await context.goodsReturnStatusOf(shipped.id), 'shipped');

      final received = await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: shipped.id,
            warehouseNote: ' Kardus penyok, isi lengkap ',
          );
      expect(received.goodsReturn.warehouseNote, 'Kardus penyok, isi lengkap');
    });
  });

  group('pemisahan tugas (G-R4)', () {
    test('receivedBy berbeda dari createdBy dan shippedBy', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      final document = received.goodsReturn;

      expect(document.receivedBy, isNot(document.createdBy));
      expect(document.receivedBy, isNot(document.shippedBy));
    });

    test(
      'pembuat yang berpindah ke Warehouse tetap tidak boleh menerima',
      () async {
        final shipped = await shippedGoodsReturnFor(context, fixture);

        // The case no role check can catch. The branch head who raised this document
        // is now a Petugas Warehouse — every RBAC gate in the application says yes, and
        // G-R4 still says no, because it is about the person.
        await context.database.customStatement(
          'UPDATE users SET role = ? WHERE id = ?;',
          [UserRole.warehouse.dbValue, fixture.branchHead.id],
        );

        await expectLater(
          context
              .receiveGoodsReturn(clock: () => nowUtc)
              .call(
                actorUserId: fixture.branchHead.id,
                goodsReturnId: shipped.id,
              ),
          throwsA(isA<GoodsReturnSegregationOfDutiesFailure>()),
        );
        expect(await context.goodsReturnStatusOf(shipped.id), 'shipped');
        expect(await context.goodsReturnMovementCount(shipped.id), 0);
      },
    );

    test(
      'pengirim yang berpindah ke Warehouse tetap tidak boleh menerima',
      () async {
        // A second branch head raises nothing but ships this one, so the creator and
        // the shipper really are different people — which is what makes the assertion
        // about `shipped_by` rather than about `created_by` in disguise.
        final created = await createGoodsReturnFor(context, fixture);
        final shipper = await context.master.ensureUser(
          email: 'kacab-pengirim@test.local',
          fullName: 'Kepala Cabang Pengirim',
          role: UserRole.kepalaCabang,
          branchId: fixture.branch.id,
        );
        await context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(actorUserId: shipper.id, goodsReturnId: created.id);

        await context.database.customStatement(
          'UPDATE users SET role = ? WHERE id = ?;',
          [UserRole.warehouse.dbValue, shipper.id],
        );

        await expectLater(
          context
              .receiveGoodsReturn(clock: () => nowUtc)
              .call(actorUserId: shipper.id, goodsReturnId: created.id),
          throwsA(isA<GoodsReturnSegregationOfDutiesFailure>()),
        );
        expect(await context.goodsReturnStatusOf(created.id), 'shipped');
        expect(await context.goodsReturnMovementCount(created.id), 0);
      },
    );

    test('petugas Warehouse lain tetap boleh menerima', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      final received = await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.secondWarehouseUser.id,
            goodsReturnId: shipped.id,
          );
      expect(received.status, GoodsReturnStatus.received);
    });

    test('SQL markReceived menolak pembuat walau guard dilewati', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      // Straight at the repository, past every domain guard: the predicate has to hold
      // on its own, because a role that changed between the check and the write would
      // otherwise slip through (§21).
      final applied = await context.goodsReturns.markReceived(
        goodsReturnId: shipped.id,
        receivedAtUtc: nowUtc,
        receivedBy: fixture.branchHead.id,
      );
      expect(applied, isFalse);
      expect(await context.goodsReturnStatusOf(shipped.id), 'shipped');
    });
  });

  group('finalitas', () {
    test('dokumen received tidak dapat diubah lagi', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      final id = received.id;

      await expectLater(
        context.updateGoodsReturnNote.call(
          actorUserId: fixture.branchHead.id,
          goodsReturnId: id,
          note: 'terlambat',
        ),
        throwsA(isA<GoodsReturnAlreadyReceivedFailure>()),
      );
      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, goodsReturnId: id),
        throwsA(isA<GoodsReturnAlreadyReceivedFailure>()),
      );
      expect(await context.goodsReturnStatusOf(id), 'received');
    });

    test('catatan cabang hanya dapat diubah saat draft', () async {
      final created = await createGoodsReturnFor(context, fixture);

      final updated = await context.updateGoodsReturnNote.call(
        actorUserId: fixture.branchHead.id,
        goodsReturnId: created.id,
        note: 'Diserahkan ke kurir pagi',
      );
      expect(updated.note, 'Diserahkan ke kurir pagi');

      // `null` clears it — a legitimate value, unlike whitespace.
      final cleared = await context.updateGoodsReturnNote.call(
        actorUserId: fixture.branchHead.id,
        goodsReturnId: created.id,
        note: null,
      );
      expect(cleared.note, isNull);

      await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: created.id);

      await expectLater(
        context.updateGoodsReturnNote.call(
          actorUserId: fixture.branchHead.id,
          goodsReturnId: created.id,
          note: 'terlambat',
        ),
        throwsA(isA<GoodsReturnAlreadyShippedFailure>()),
      );
    });

    test('cabang tidak dapat menulis catatan Warehouse', () async {
      final received = await receivedGoodsReturnFor(
        context,
        fixture,
        warehouseNote: 'Diterima lengkap',
      );

      // There is no writer that reaches it — not on the repository, not on the DAO —
      // so the assertion is that the branch's own note path leaves it alone (§19).
      expect(
        await context.goodsReturnColumn(received.id, 'warehouse_note'),
        'Diterima lengkap',
      );
      await expectLater(
        context.updateGoodsReturnNote.call(
          actorUserId: fixture.branchHead.id,
          goodsReturnId: received.id,
          note: 'apa pun',
        ),
        throwsA(isA<GoodsReturnAlreadyReceivedFailure>()),
      );
      expect(
        await context.goodsReturnColumn(received.id, 'warehouse_note'),
        'Diterima lengkap',
      );
    });
  });

  group('penerimaan bersamaan', () {
    test('dua penerimaan serentak menghasilkan tepat satu', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      final results = await Future.wait([
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
            )
            .then<Object?>((value) => value, onError: (Object e) => e),
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.secondWarehouseUser.id,
              goodsReturnId: shipped.id,
            )
            .then<Object?>((value) => value, onError: (Object e) => e),
      ]);

      final succeeded = results.whereType<GoodsReturnDetail>().length;
      expect(succeeded, 1, reason: 'Tepat satu penerimaan boleh berhasil.');
      expect(await context.goodsReturnStatusOf(shipped.id), 'received');
      // The assertion that matters: the balance went up **once**.
      expect(await context.goodsReturnMovementCount(shipped.id), 2);
    });
  });
}
