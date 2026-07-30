import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import 'purchase_request_guards.dart';

/// `draft → cancelled` and `submitted → cancelled` — the branch head withdraws
/// the request (G-P5, G-S3, §19.7).
///
/// The window closes the moment the warehouse starts work: a `processing` request
/// is being picked and packed, and letting a branch pull it out from under the
/// officer would be the coordination failure G-S3 exists to prevent. That boundary
/// is enforced three times over — [PurchaseRequestStatePolicy] has no
/// `processing → cancelled` edge, the repository's writer takes the status it
/// expects to move *from*, and the SQL predicate is in the same statement as the
/// write.
///
/// **A reason is mandatory.** The specification leaves this to the audit design,
/// and the detail screen has to be able to say *why* a request disappeared (§24.4)
/// — "cancelled" on its own explains nothing to the warehouse officer who was
/// waiting for it, or to whoever reads the branch's history next month. The column
/// is `cancel_reason`, and the database enforces a non-blank value with
/// `trim(cancel_reason) <> ''` so this rule cannot be bypassed by raw SQL either.
///
/// Cancelling releases the branch's active-order slot (G-P4): the partial unique
/// index covers only `submitted` and `processing`, so a new request can be sent
/// immediately. The record itself is never removed (G-A5) — a withdrawn order is
/// part of the branch's history.
class CancelPurchaseRequestUseCase {
  CancelPurchaseRequestUseCase({
    required this._requests,
    required MasterDataRepository master,
    DateTime Function()? clock,
  }) : _guards = PurchaseRequestGuards(master),
       _clock = clock ?? _defaultClock;

  final PurchaseRequestRepository _requests;
  final PurchaseRequestGuards _guards;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<PurchaseRequest> call({
    required String actorUserId,
    required String prId,
    required String reason,
  }) async {
    final actor = await _guards.requireBranchActor(actorUserId, prId: prId);

    return _requests.runInTransaction(() async {
      final request = await _requests.getById(prId);
      if (request == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan.',
          prId: prId,
        );
      }

      _guards.requireSameBranch(actor: actor, request: request);
      // One check for both permitted origins: the policy lists `draft →
      // cancelled` and `submitted → cancelled` and nothing else, so `processing`,
      // `shipped`, `closed`, `rejected` and an already-cancelled document are all
      // refused here with a message that says which.
      _guards.requireTransition(
        actor: actor,
        request: request,
        to: PurchaseRequestStatus.cancelled,
      );

      final trimmedReason = _guards.requireReason(
        reason,
        onMissing: () => PurchaseRequestCancelReasonRequiredFailure(
          'Alasan pembatalan wajib diisi.',
          prId: prId,
        ),
      );

      final cancelledAt = _clock().toUtc();
      // Ordered against the submission when there is one. A draft has no
      // `submitted_at`, and that is a legitimate absence rather than a check to
      // route around: cancelling a draft follows no earlier workflow event, so
      // there is nothing for the ordering rule to compare it to. `created_at` is
      // deliberately not used as a substitute — see the note in
      // `SubmitPurchaseRequestUseCase` for why a storage timestamp is not a
      // workflow event.
      DocumentTimestampPolicy.requireCancellationNotBeforeSubmit(
        documentId: prId,
        submittedAtUtc: request.submittedAt,
        cancelledAtUtc: cancelledAt,
      );

      final moved = await _requests.cancel(
        prId: prId,
        // The status the caller believes it is leaving, so a document that moved
        // to `processing` in the meantime fails the write instead of being
        // cancelled anyway.
        from: request.status,
        cancelledBy: actor.id,
        cancelledAtUtc: cancelledAt,
        reason: trimmedReason,
      );
      if (!moved) _guards.concurrentUpdate(request);

      final updated = await _requests.getById(prId);
      if (updated == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan setelah dibatalkan.',
          prId: prId,
        );
      }
      return updated;
    });
  }
}
