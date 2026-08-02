import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import 'purchase_request_guards.dart';

/// `processing → rejected` — the warehouse refuses the order (§20.2).
///
/// **A reason is mandatory**, and the specification says so outright: *"rejected
/// (oleh warehouse, wajib alasan)"*. A branch head whose request comes back with no
/// explanation cannot act on it, so the rule is enforced in three places — here,
/// in the dialog that will not enable its button without text, and in the database,
/// whose CHECK demands `trim(reject_reason) <> ''` for a rejected row.
///
/// Rejection is only reachable from `processing`, not from `submitted`. That is the
/// state machine of spec §3.2 read literally, and it is also the more honest
/// workflow: refusing an order means somebody looked at it, and taking it on is
/// what "looked at it" is recorded as. The consequence is that a rejected document
/// always carries both `processed_by` and `rejected_by`, which is exactly the audit
/// trail G-A3 asks for.
///
/// `rejected` is final (G-S2): there is no edge out of it in
/// [PurchaseRequestStatePolicy], so it cannot be rejected twice, reopened, or
/// pushed on to `shipped`. It also releases the branch's active-order slot, so the
/// branch can raise a corrected request immediately (G-P4).
///
/// Nothing here touches the ledger, and nothing changes what the request asked for
/// (G-R3).
class RejectPurchaseRequestUseCase {
  RejectPurchaseRequestUseCase({
    required this._requests,
    required MasterDataRepository master,
    this._outbox = const NoopSyncOutboxWriter(),
    DateTime Function()? clock,
  }) : _guards = PurchaseRequestGuards(master),
       _clock = clock ?? _defaultClock;

  final PurchaseRequestRepository _requests;
  final PurchaseRequestGuards _guards;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<PurchaseRequest> call({
    required String actorUserId,
    required String prId,
    required String reason,
  }) async {
    final actor = await _guards.requireWarehouseActor(actorUserId);

    return _requests.runInTransaction(() async {
      final request = await _requests.getById(prId);
      if (request == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan.',
          prId: prId,
        );
      }

      _guards.requireStatus(
        request: request,
        expected: PurchaseRequestStatus.processing,
        attempted: PurchaseRequestStatus.rejected,
      );
      _guards.requireTransition(
        actor: actor,
        request: request,
        to: PurchaseRequestStatus.rejected,
      );

      final trimmedReason = _guards.requireReason(
        reason,
        onMissing: () => PurchaseRequestRejectReasonRequiredFailure(
          'Alasan penolakan wajib diisi.',
          prId: prId,
        ),
      );

      final rejectedAt = _clock().toUtc();
      DocumentTimestampPolicy.requireRejectionNotBeforeProcessing(
        documentId: prId,
        processingAtUtc: request.processingAt,
        rejectedAtUtc: rejectedAt,
      );

      final moved = await _requests.reject(
        prId: prId,
        rejectedBy: actor.id,
        rejectedAtUtc: rejectedAt,
        reason: trimmedReason,
      );
      if (!moved) _guards.concurrentUpdate(request);

      await _outbox.enqueueCurrentAggregate(
        operation: SyncOperationType.rejectPurchaseRequest,
        aggregateType: SyncAggregateType.purchaseRequest,
        aggregateId: prId,
        actorUserId: actor.id,
        occurredAtUtc: rejectedAt,
      );

      final updated = await _requests.getById(prId);
      if (updated == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan setelah ditolak.',
          prId: prId,
        );
      }
      return updated;
    });
  }
}
