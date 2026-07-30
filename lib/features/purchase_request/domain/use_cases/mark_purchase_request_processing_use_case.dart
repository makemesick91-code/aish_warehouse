import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import 'purchase_request_guards.dart';

/// `submitted → processing` — the central warehouse takes the order on (§20.1).
///
/// It records **who** and **when** and changes nothing else. That is G-R3 in
/// practice: *"Warehouse tidak bisa mengubah isi PR — hanya memenuhi (fulfil) atau
/// menolak dengan alasan"*. There is no argument here for a quantity, an item or a
/// note, and the repository offers the warehouse no writer that could reach one —
/// the line and citation writers are all guarded by `status = 'draft'`, which a
/// submitted document is not.
///
/// Deliberately **not** branch-scoped: the warehouse serves every branch, and its
/// user row carries `branch_id = NULL` by design (spec §2.1). What replaces the
/// branch check is the status check — a `draft` belongs to the device that is
/// writing it (G-Y2) and never appears in the warehouse queue.
///
/// Historic references are read, not re-validated. A branch that was deactivated,
/// an item that was withdrawn or a nurse who left after the request was raised are
/// all still exactly what was ordered, and an order must not become unprocessable
/// because somebody tidied up master data. What is still required is that the row
/// physically exists, and that the officer performing the action is an active
/// account.
///
/// Nothing here touches the ledger. Stock leaves the warehouse when a Delivery
/// Order is shipped (spec §2.5), which is the next milestone.
class MarkPurchaseRequestProcessingUseCase {
  MarkPurchaseRequestProcessingUseCase({
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
  }) async {
    final actor = await _guards.requireWarehouseActor(actorUserId);

    return _requests.runInTransaction(() async {
      final detail = await _requests.getDetail(prId);
      if (detail == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan.',
          prId: prId,
        );
      }

      final request = detail.request;
      _guards.requireStatus(
        request: request,
        expected: PurchaseRequestStatus.submitted,
        attempted: PurchaseRequestStatus.processing,
      );
      _guards.requireTransition(
        actor: actor,
        request: request,
        to: PurchaseRequestStatus.processing,
      );

      // Set integrity before acting: the joins behind `detail` would silently drop
      // a line whose item row is gone or a citation whose count is gone, and an
      // officer must not start picking an order that does not agree with itself.
      await _guards.requireEveryLineLoaded(
        prId: prId,
        storedItemIds: await _requests.lineItemIds(prId),
        loadedItemIds: detail.lines.map((line) => line.itemId),
      );
      _guards.requireEveryOpnameLoaded(
        prId: prId,
        storedOpnameIds: await _requests.linkedOpnameIds(prId),
        loadedOpnameIds: detail.opnames.map((reference) => reference.opnameId),
      );

      final processingAt = _clock().toUtc();
      DocumentTimestampPolicy.requireProcessingNotBeforeSubmit(
        documentId: prId,
        submittedAtUtc: request.submittedAt,
        processingAtUtc: processingAt,
      );

      final moved = await _requests.markProcessing(
        prId: prId,
        processedBy: actor.id,
        processingAtUtc: processingAt,
      );
      if (!moved) _guards.concurrentUpdate(request);

      final updated = await _requests.getById(prId);
      if (updated == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan setelah diproses.',
          prId: prId,
        );
      }
      return updated;
    });
  }
}
