import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import '../services/purchase_request_quantity_policy.dart';
import 'purchase_request_guards.dart';

/// Edits a Purchase Request **draft** (G-P2, G-P3, G-P5).
///
/// Two operations rather than two classes, because they are the same rule set
/// applied to two parts of one document and both are reached from the same screen:
/// the header carries the needed date and an overall note, each line carries a
/// requested quantity and its justification.
///
/// What cannot be reached from here at all:
///
/// * **`suggested_qty`.** The repository's line writer does not accept it, so
///   there is no argument to pass. Recomputing the snapshot is
///   `ReplacePurchaseRequestOpnamesUseCase`'s alone.
/// * **Anything on a submitted document.** G-P5: a submitted request is corrected
///   by cancelling it and creating a new one. Both operations check the status in
///   Dart for a good message *and* rely on the repository's `WHERE status =
///   'draft'` predicate, so a stale screen cannot slip an edit through the gap.
class UpdatePurchaseRequestUseCase {
  UpdatePurchaseRequestUseCase({
    required this._requests,
    required MasterDataRepository master,
  }) : _guards = PurchaseRequestGuards(master);

  final PurchaseRequestRepository _requests;
  final PurchaseRequestGuards _guards;

  /// Needed date and header note.
  ///
  /// [neededDate] is a civil date: only its calendar fields are kept, and no
  /// timezone conversion happens on the way in (T-8/T-9).
  Future<PurchaseRequest> header({
    required String actorUserId,
    required String prId,
    DateTime? neededDate,
    String? note,
  }) async {
    final actor = await _guards.requireBranchActor(actorUserId, prId: prId);

    return _requests.runInTransaction(() async {
      final request = await _requireDraft(prId);
      _guards.requireSameBranch(actor: actor, request: request);

      final moved = await _requests.updateDraftHeader(
        prId: prId,
        neededDate: neededDate == null ? null : DateOnly.from(neededDate),
        note: _normalizeNote(note),
      );
      if (!moved) _guards.concurrentUpdate(request);

      final updated = await _requests.getById(prId);
      if (updated == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan setelah diperbarui.',
          prId: prId,
        );
      }
      return updated;
    });
  }

  /// Requested quantity and justification of one line.
  Future<PurchaseRequestLine> line({
    required String actorUserId,
    required String lineId,
    required Quantity requestedQty,
    String? note,
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

      final request = await _requireDraft(line.prId);
      _guards.requireSameBranch(actor: actor, request: request);

      // G-P2: a request for nothing is not a request. Removing the item is the
      // way to express that, and it is a different operation.
      if (!requestedQty.isPositive) {
        throw InvalidRequestedQuantityFailure(
          'Jumlah permintaan ${line.itemName} harus lebih dari 0.',
          itemId: line.itemId,
          requested: requestedQty,
        );
      }

      // G-P3, checked against the line's *stored* suggestion rather than anything
      // the caller supplied — the snapshot is not the editor's to move.
      final normalizedNote = _normalizeNote(note);
      if (PurchaseRequestQuantityPolicy.requiresJustification(
            suggested: line.suggestedQty,
            requested: requestedQty,
          ) &&
          !PurchaseRequestQuantityPolicy.hasJustification(normalizedNote)) {
        throw PurchaseRequestJustificationRequiredFailure(
          _justificationMessage(line: line, requested: requestedQty),
          lineIds: [lineId],
        );
      }

      final moved = await _requests.updateDraftLine(
        lineId: lineId,
        requestedQty: requestedQty,
        note: normalizedNote,
      );
      if (!moved) _guards.concurrentUpdate(request);

      final updated = await _requests.lineById(lineId);
      if (updated == null) {
        throw PurchaseRequestLineNotFoundFailure(
          'Baris permintaan tidak ditemukan setelah diperbarui.',
          lineId: lineId,
        );
      }
      return updated;
    });
  }

  Future<PurchaseRequest> _requireDraft(String prId) async {
    final request = await _requests.getById(prId);
    if (request == null) {
      throw PurchaseRequestNotFoundFailure(
        'Purchase Request tidak ditemukan.',
        prId: prId,
      );
    }
    _guards.requireStatus(
      request: request,
      expected: PurchaseRequestStatus.draft,
    );
    return request;
  }

  /// A note of only whitespace is stored as absent, so `note IS NULL` and
  /// `note = '   '` cannot mean two different things to the justification rule.
  static String? _normalizeNote(String? note) {
    final trimmed = (note ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _justificationMessage({
    required PurchaseRequestLine line,
    required Quantity requested,
  }) {
    if (PurchaseRequestQuantityPolicy.isManualRequest(line.suggestedQty)) {
      return 'Catatan alasan wajib diisi untuk ${line.itemName}: '
          '${PurchaseRequestQuantityPolicy.manualRequestWarning}';
    }
    return 'Catatan alasan wajib diisi untuk ${line.itemName}: jumlah '
        '${requested.formatWithUnit(line.unit)} lebih dari '
        '${PurchaseRequestQuantityPolicy.thresholdPercent}% saran sistem '
        '(${line.suggestedQty.formatWithUnit(line.unit)}).';
  }
}
