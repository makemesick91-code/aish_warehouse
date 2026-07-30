import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../repositories/purchase_request_repository.dart';
import 'purchase_request_guards.dart';

/// Removes a line from a **draft** (§19.5).
///
/// The line is soft-deleted, never destroyed (G-A5), and the partial unique index
/// on `(pr_id, item_id) WHERE deleted_at IS NULL` is what lets the same item be
/// added back afterwards: uniqueness applies to live rows, so a removed line does
/// not hold that position hostage.
///
/// Removing the *last* line is allowed. The alternative — refusing it — would trap
/// a branch head who wants to replace the only item on the document into adding
/// the replacement first. The invariant that matters, "nothing empty is ever
/// sent", is `SubmitPurchaseRequestUseCase`'s and is enforced there, where it is
/// meaningful.
class RemovePurchaseRequestLineUseCase {
  RemovePurchaseRequestLineUseCase({
    required this._requests,
    required MasterDataRepository master,
  }) : _guards = PurchaseRequestGuards(master);

  final PurchaseRequestRepository _requests;
  final PurchaseRequestGuards _guards;

  Future<void> call({
    required String actorUserId,
    required String lineId,
  }) async {
    final actor = await _guards.requireBranchActor(actorUserId);

    return _requests.runInTransaction(() async {
      final line = await _requests.lineById(lineId);
      if (line == null) {
        throw PurchaseRequestLineNotFoundFailure(
          'Baris permintaan tidak ditemukan.',
          lineId: lineId,
        );
      }

      final request = await _requests.getById(line.prId);
      if (request == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan.',
          prId: line.prId,
        );
      }
      _guards.requireSameBranch(actor: actor, request: request);
      // G-P5: submitted and later documents keep every line they were sent with.
      _guards.requireStatus(
        request: request,
        expected: PurchaseRequestStatus.draft,
      );

      final removed = await _requests.removeDraftLine(lineId);
      if (!removed) _guards.concurrentUpdate(request);
    });
  }
}
