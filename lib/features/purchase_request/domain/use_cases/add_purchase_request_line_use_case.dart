import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import '../services/purchase_request_quantity_policy.dart';
import 'purchase_request_guards.dart';

/// Adds an item to a **draft** that the cited counts did not propose (§19.4).
///
/// A manual line always starts with `suggested_qty = 0`, and that is not a
/// placeholder — it is the honest statement that no count asked for this item. By
/// G-P3 it therefore requires a written reason, which is the whole point: the
/// branch head is overriding the evidence, and the document has to record why.
///
/// The item must be **active**: this is new work, and master data that has been
/// withdrawn may not be ordered (G-A4). A deactivated item already on a document
/// stays perfectly readable — that is the historical path, not this one.
///
/// There is deliberately no batch argument. A Purchase Request asks for an item;
/// which batches satisfy it is the warehouse's FEFO decision at Delivery Order
/// time (G-E3).
class AddPurchaseRequestLineUseCase {
  AddPurchaseRequestLineUseCase({
    required this._requests,
    required MasterDataRepository master,
  }) : _guards = PurchaseRequestGuards(master);

  final PurchaseRequestRepository _requests;
  final PurchaseRequestGuards _guards;

  Future<PurchaseRequestLine> call({
    required String actorUserId,
    required String prId,
    required String itemId,
    required Quantity requestedQty,
    String? note,
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
      _guards.requireStatus(
        request: request,
        expected: PurchaseRequestStatus.draft,
      );

      final item = await _guards.requireActiveItem(itemId);

      // G-P2, second half. The partial unique index already makes this
      // impossible; checking here turns a constraint error into a sentence the
      // branch head can act on, and points at the line they should edit instead.
      final duplicate = await _requests.findLineByItem(
        prId: prId,
        itemId: itemId,
      );
      if (duplicate != null) {
        throw DuplicatePurchaseRequestItemFailure(
          '${item.name} sudah ada pada permintaan ini. Ubah jumlah pada baris '
          'yang sudah ada.',
          prId: prId,
          itemId: itemId,
        );
      }

      if (!requestedQty.isPositive) {
        throw InvalidRequestedQuantityFailure(
          'Jumlah permintaan ${item.name} harus lebih dari 0.',
          itemId: itemId,
          requested: requestedQty,
        );
      }

      final normalizedNote = (note ?? '').trim();
      if (!PurchaseRequestQuantityPolicy.hasJustification(normalizedNote)) {
        throw PurchaseRequestJustificationRequiredFailure(
          'Catatan alasan wajib diisi untuk ${item.name}: '
          '${PurchaseRequestQuantityPolicy.manualRequestWarning}',
          lineIds: const <String>[],
        );
      }

      final line = await _requests.addDraftLine(
        prId: prId,
        itemId: itemId,
        // No count proposed this item, so the system suggests nothing.
        suggestedQty: Quantity.zero(),
        requestedQty: requestedQty,
        note: normalizedNote,
      );
      // `null` means the repository's `status = 'draft'` guard fired between the
      // read above and the insert — another device submitted in the gap.
      if (line == null) _guards.concurrentUpdate(request);
      return line;
    });
  }
}
