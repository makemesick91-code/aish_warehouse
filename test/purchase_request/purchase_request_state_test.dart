import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/purchase_request/domain/services/purchase_request_state_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-P5 and the state machine of spec §3.2.
///
/// ```
/// draft ──▶ submitted ──▶ processing ──▶ shipped ──▶ closed
///       └─▶ cancelled  └─▶ cancelled   └─▶ rejected
/// ```
///
/// Two things this file is careful about. First, `shipped` and `closed` are *permitted*
/// transitions that no user may trigger in this milestone — they belong to Delivery
/// Order and Good Receipt — so the policy has to distinguish "allowed" from
/// "allowed for a person", and the tests check both answers. Second, every refusal is
/// asserted to have left the stored status alone: a failed transition that still wrote
/// a timestamp would be worse than one that failed loudly.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  group('kebijakan status (murni)', () {
    test('transisi yang diizinkan sesuai spesifikasi', () {
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.draft,
          PurchaseRequestStatus.submitted,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.draft,
          PurchaseRequestStatus.cancelled,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.submitted,
          PurchaseRequestStatus.processing,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.submitted,
          PurchaseRequestStatus.cancelled,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.processing,
          PurchaseRequestStatus.rejected,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.processing,
          PurchaseRequestStatus.shipped,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.shipped,
          PurchaseRequestStatus.closed,
        ),
        isTrue,
      );
    });

    test('transisi yang ditolak', () {
      const refused = <(PurchaseRequestStatus, PurchaseRequestStatus)>[
        (PurchaseRequestStatus.submitted, PurchaseRequestStatus.draft),
        (PurchaseRequestStatus.processing, PurchaseRequestStatus.submitted),
        (PurchaseRequestStatus.processing, PurchaseRequestStatus.cancelled),
        (PurchaseRequestStatus.rejected, PurchaseRequestStatus.processing),
        (PurchaseRequestStatus.cancelled, PurchaseRequestStatus.draft),
        (PurchaseRequestStatus.shipped, PurchaseRequestStatus.processing),
        (PurchaseRequestStatus.draft, PurchaseRequestStatus.processing),
        (PurchaseRequestStatus.draft, PurchaseRequestStatus.rejected),
        (PurchaseRequestStatus.submitted, PurchaseRequestStatus.rejected),
      ];

      for (final (from, to) in refused) {
        expect(
          PurchaseRequestStatePolicy.isAllowed(from, to),
          isFalse,
          reason: '${from.dbValue} → ${to.dbValue} harus ditolak.',
        );
      }
    });

    test('closed tidak memiliki transisi keluar', () {
      expect(
        PurchaseRequestStatePolicy.nextStatesOf(PurchaseRequestStatus.closed),
        isEmpty,
      );
      for (final to in PurchaseRequestStatus.values) {
        expect(
          PurchaseRequestStatePolicy.isAllowed(
            PurchaseRequestStatus.closed,
            to,
          ),
          isFalse,
        );
      }
    });

    test('rejected dan cancelled bersifat final', () {
      for (final from in [
        PurchaseRequestStatus.rejected,
        PurchaseRequestStatus.cancelled,
      ]) {
        expect(PurchaseRequestStatePolicy.nextStatesOf(from), isEmpty);
        expect(from.isFinal, isTrue);
      }
    });

    test('shipped bukan final karena masih menunggu penerimaan', () {
      expect(PurchaseRequestStatus.shipped.isFinal, isFalse);
      expect(
        PurchaseRequestStatePolicy.nextStatesOf(PurchaseRequestStatus.shipped),
        {PurchaseRequestStatus.closed},
      );
    });

    test('shipped dan closed adalah transisi sistem, bukan aksi pengguna', () {
      expect(
        PurchaseRequestStatePolicy.isSystemTransition(
          PurchaseRequestStatus.processing,
          PurchaseRequestStatus.shipped,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isUserTransition(
          PurchaseRequestStatus.processing,
          PurchaseRequestStatus.shipped,
        ),
        isFalse,
      );
      expect(
        PurchaseRequestStatePolicy.isUserTransition(
          PurchaseRequestStatus.shipped,
          PurchaseRequestStatus.closed,
        ),
        isFalse,
      );

      // The user-facing next states of `processing` are therefore rejection alone —
      // which is what keeps a "Kirim" button off the screen in this milestone.
      expect(
        PurchaseRequestStatePolicy.userNextStatesOf(
          PurchaseRequestStatus.processing,
        ),
        {PurchaseRequestStatus.rejected},
      );
      expect(
        PurchaseRequestStatePolicy.userNextStatesOf(
          PurchaseRequestStatus.shipped,
        ),
        isEmpty,
      );
    });

    test('peran menentukan siapa yang boleh melakukan transisi', () {
      // The branch head sends and withdraws.
      expect(
        PurchaseRequestStatePolicy.isAllowedFor(
          role: UserRole.kepalaCabang,
          from: PurchaseRequestStatus.draft,
          to: PurchaseRequestStatus.submitted,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowedFor(
          role: UserRole.warehouse,
          from: PurchaseRequestStatus.draft,
          to: PurchaseRequestStatus.submitted,
        ),
        isFalse,
      );

      // The warehouse processes and refuses — and never cancels somebody else's
      // order (G-R3).
      expect(
        PurchaseRequestStatePolicy.isAllowedFor(
          role: UserRole.warehouse,
          from: PurchaseRequestStatus.submitted,
          to: PurchaseRequestStatus.processing,
        ),
        isTrue,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowedFor(
          role: UserRole.kepalaCabang,
          from: PurchaseRequestStatus.submitted,
          to: PurchaseRequestStatus.processing,
        ),
        isFalse,
      );
      expect(
        PurchaseRequestStatePolicy.isAllowedFor(
          role: UserRole.warehouse,
          from: PurchaseRequestStatus.submitted,
          to: PurchaseRequestStatus.cancelled,
        ),
        isFalse,
      );

      // Nobody at all may perform a system transition.
      for (final role in UserRole.values) {
        expect(
          PurchaseRequestStatePolicy.isAllowedFor(
            role: role,
            from: PurchaseRequestStatus.processing,
            to: PurchaseRequestStatus.shipped,
          ),
          isFalse,
        );
      }
    });

    test('predikat enum konsisten dengan kebijakan', () {
      expect(PurchaseRequestStatus.draft.isEditable, isTrue);
      for (final status in PurchaseRequestStatus.values.where(
        (status) => !status.isDraft,
      )) {
        expect(status.isEditable, isFalse);
      }

      expect(PurchaseRequestStatus.submitted.isActiveOrder, isTrue);
      expect(PurchaseRequestStatus.processing.isActiveOrder, isTrue);
      for (final status in [
        PurchaseRequestStatus.draft,
        PurchaseRequestStatus.shipped,
        PurchaseRequestStatus.closed,
        PurchaseRequestStatus.rejected,
        PurchaseRequestStatus.cancelled,
      ]) {
        expect(status.isActiveOrder, isFalse);
      }

      // `canCancel` and the policy's own answer must agree, or a button appears for a
      // transition the use case refuses.
      for (final status in PurchaseRequestStatus.values) {
        expect(
          status.canCancel,
          PurchaseRequestStatePolicy.isAllowedFor(
            role: UserRole.kepalaCabang,
            from: status,
            to: PurchaseRequestStatus.cancelled,
          ),
          reason: 'canCancel harus setuju dengan kebijakan untuk $status.',
        );
      }
    });

    test('setiap status punya label Bahasa Indonesia', () {
      final labels = PurchaseRequestStatus.values
          .map((status) => status.label)
          .toSet();
      expect(labels, hasLength(PurchaseRequestStatus.values.length));
      for (final label in labels) {
        expect(label.trim(), isNotEmpty);
      }
    });

    test('nilai database enum stabil', () {
      // The strings are the database contract; renaming a Dart identifier must not
      // change them.
      expect(PurchaseRequestStatus.values.map((status) => status.dbValue), [
        'draft',
        'submitted',
        'processing',
        'shipped',
        'closed',
        'rejected',
        'cancelled',
      ]);
      expect(
        PurchaseRequestStatus.fromDbValue('processing'),
        PurchaseRequestStatus.processing,
      );
      expect(
        () => PurchaseRequestStatus.fromDbValue('approved'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('transisi terhadap database', () {
    late PurchaseRequestFixture fixture;
    late String prId;

    setUp(() async {
      fixture = await buildPurchaseRequestFixture(
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
      prId = request.id;
    });

    Future<void> submit() => context
        .submitPurchaseRequest(clock: prWednesdayUtc)
        .call(actorUserId: fixture.branchHead.id, prId: prId);

    Future<void> process() => context
        .markPurchaseRequestProcessing(clock: prWednesdayUtc)
        .call(actorUserId: fixture.warehouseUser.id, prId: prId);

    test('draft dapat dikirim dan menjadi read-only', () async {
      await submit();
      expect(await context.purchaseRequestStatusOf(prId), 'submitted');

      final detail = await context.requests.getDetail(prId);
      expect(detail!.isEditable, isFalse);
      expect(detail.request.isSubmitted, isTrue);
    });

    test('header PR submitted tidak dapat diubah', () async {
      await submit();

      await expectLater(
        () => context.updatePurchaseRequest.header(
          actorUserId: fixture.branchHead.id,
          prId: prId,
          note: 'Ubah setelah dikirim',
        ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      expect(
        (await context.requests.getById(prId))!.note,
        isNull,
        reason: 'Isi header tidak boleh berubah.',
      );
    });

    test('baris PR submitted tidak dapat diubah', () async {
      final line = (await context.requests.getDetail(prId))!.lines.first;
      await submit();

      await expectLater(
        () => context.updatePurchaseRequest.line(
          actorUserId: fixture.branchHead.id,
          lineId: line.id,
          requestedQty: Quantity.parse('1'),
        ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      final after = (await context.requests.lineById(line.id))!;
      expect(after.requestedQty, line.requestedQty);
    });

    test('baris PR submitted tidak dapat dihapus atau ditambah', () async {
      final line = (await context.requests.getDetail(prId))!.lines.first;
      final lineCount = await context.purchaseRequestLineCount(prId);
      await submit();

      await expectLater(
        () => context.removePurchaseRequestLine.call(
          actorUserId: fixture.branchHead.id,
          lineId: line.id,
        ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      await expectLater(
        () => context.addPurchaseRequestLine.call(
          actorUserId: fixture.branchHead.id,
          prId: prId,
          itemId: fixture.unstockedItem.id,
          requestedQty: Quantity.parse('1'),
          note: 'Tambahan',
        ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      expect(await context.purchaseRequestLineCount(prId), lineCount);
    });

    test('tautan opname PR submitted tidak dapat diubah', () async {
      final linkCount = await context.purchaseRequestOpnameLinkCount(prId);
      final other = await fileOpnameForRoom(
        context,
        roomId: fixture.roomTwo.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      await submit();

      await expectLater(
        () => context
            .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              prId: prId,
              selectedOpnameIds: [other],
            ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      expect(await context.purchaseRequestOpnameLinkCount(prId), linkCount);
    });

    test('draft dapat dibatalkan', () async {
      await context
          .cancelPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            prId: prId,
            reason: 'Salah acuan',
          );

      expect(await context.purchaseRequestStatusOf(prId), 'cancelled');
      final request = (await context.requests.getById(prId))!;
      expect(request.cancelReason, 'Salah acuan');
      expect(request.cancelledBy, fixture.branchHead.id);
      expect(
        request.submittedAt,
        isNull,
        reason:
            'Draft yang dibatalkan sebelum dikirim tidak punya submitted_at.',
      );
    });

    test('submitted dapat dibatalkan', () async {
      await submit();
      await context
          .cancelPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            prId: prId,
            reason: 'Sudah dipenuhi dari cabang lain',
          );

      expect(await context.purchaseRequestStatusOf(prId), 'cancelled');
      expect((await context.requests.getById(prId))!.submittedAt, isNotNull);
    });

    test('processing tidak dapat dibatalkan (G-S3)', () async {
      await submit();
      await process();

      await expectLater(
        () => context
            .cancelPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              prId: prId,
              reason: 'Berubah pikiran',
            ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(prId), 'processing');
      expect(await context.purchaseRequestColumn(prId, 'cancelled_at'), isNull);
    });

    test('cancelled tidak dapat diedit atau dibatalkan lagi', () async {
      final line = (await context.requests.getDetail(prId))!.lines.first;
      await context
          .cancelPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            prId: prId,
            reason: 'Salah acuan',
          );

      await expectLater(
        () => context.updatePurchaseRequest.line(
          actorUserId: fixture.branchHead.id,
          lineId: line.id,
          requestedQty: Quantity.parse('1'),
        ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      await expectLater(
        () => context
            .cancelPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              prId: prId,
              reason: 'Sekali lagi',
            ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
    });

    test('cancelled tidak dapat kembali menjadi draft', () async {
      await context
          .cancelPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            prId: prId,
            reason: 'Salah acuan',
          );

      // There is no use case for this at all, and the policy refuses the transition.
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.cancelled,
          PurchaseRequestStatus.draft,
        ),
        isFalse,
      );
      await expectLater(
        () => submit(),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
    });

    test('alasan pembatalan wajib', () async {
      await expectLater(
        () => context
            .cancelPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              prId: prId,
              reason: '   ',
            ),
        throwsA(isA<PurchaseRequestCancelReasonRequiredFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(prId), 'draft');
    });

    test('submitted tidak dapat kembali menjadi draft', () async {
      await submit();
      // No API expresses it; the only way to ask is through the policy, which refuses.
      expect(
        PurchaseRequestStatePolicy.isAllowed(
          PurchaseRequestStatus.submitted,
          PurchaseRequestStatus.draft,
        ),
        isFalse,
      );
      expect(await context.purchaseRequestStatusOf(prId), 'submitted');
    });

    test('processing tidak dapat kembali menjadi submitted', () async {
      await submit();
      await process();

      // Processing twice is the closest a caller can come to asking for it.
      await expectLater(
        () => process(),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(prId), 'processing');
    });

    test('processing dapat ditolak Warehouse dengan alasan', () async {
      await submit();
      await process();
      await context
          .rejectPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            prId: prId,
            reason: 'Stok warehouse tidak mencukupi',
          );

      final request = (await context.requests.getById(prId))!;
      expect(request.isRejected, isTrue);
      expect(request.rejectReason, 'Stok warehouse tidak mencukupi');
      expect(request.rejectedBy, fixture.warehouseUser.id);
      // The rejection keeps the processing audit trail — somebody looked at it.
      expect(request.processedBy, fixture.warehouseUser.id);
      expect(request.processingAt, isNotNull);
    });

    test('alasan penolakan wajib', () async {
      await submit();
      await process();

      await expectLater(
        () => context
            .rejectPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              prId: prId,
              reason: '  ',
            ),
        throwsA(isA<PurchaseRequestRejectReasonRequiredFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(prId), 'processing');
      expect(await context.purchaseRequestColumn(prId, 'rejected_at'), isNull);
    });

    test('submitted tidak dapat langsung ditolak', () async {
      await submit();

      // Refusing an order means somebody looked at it, and `processing` is what
      // "looked at it" is recorded as.
      await expectLater(
        () => context
            .rejectPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              prId: prId,
              reason: 'Tidak tersedia',
            ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(prId), 'submitted');
    });

    test('rejected bersifat final dan tidak dapat ditolak dua kali', () async {
      await submit();
      await process();
      await context
          .rejectPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            prId: prId,
            reason: 'Stok kosong',
          );

      await expectLater(
        () => context
            .rejectPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              prId: prId,
              reason: 'Sekali lagi',
            ),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      expect(
        (await context.requests.getById(prId))!.rejectReason,
        'Stok kosong',
        reason: 'Alasan penolakan pertama tidak boleh ditimpa.',
      );
    });

    test('draft tidak dapat diproses Warehouse', () async {
      await expectLater(
        () => process(),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(prId), 'draft');
    });

    test('tidak ada jalur use case menuju shipped atau closed', () async {
      await submit();
      await process();

      // The repository offers no writer for either, and the policy classifies both as
      // system transitions. This test is the standing reminder that adding one is a
      // Delivery Order / Good Receipt decision, not a Purchase Request one.
      expect(
        PurchaseRequestStatePolicy.userNextStatesOf(
          PurchaseRequestStatus.processing,
        ),
        {PurchaseRequestStatus.rejected},
      );
      expect(await context.purchaseRequestStatusOf(prId), 'processing');
    });

    test('PR tidak pernah menulis ke ledger', () async {
      final before = await context.movementCountFor(prId);
      await submit();
      await process();
      await context
          .rejectPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            prId: prId,
            reason: 'Stok kosong',
          );

      // Spec §2.5: the first posting happens when a Delivery Order is shipped.
      expect(before, 0);
      expect(await context.movementCountFor(prId), 0);
    });
  });
}
