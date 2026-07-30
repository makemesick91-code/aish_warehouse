import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import '../services/purchase_request_suggestion_builder.dart';
import 'purchase_request_guards.dart';

/// Changes which stock opnames a **draft** rests on, and recomputes the
/// suggestions that follow (§19.3).
///
/// This is the only operation allowed to move `suggested_qty` after creation, and
/// the reconciliation it performs is the interesting part. Three things happen to
/// a line when the citation list changes, and each is a deliberate answer to a
/// question about whose number it is:
///
/// * **An item that is still suggested** keeps the branch head's `requested_qty`
///   and note, and gets the new suggestion. Overwriting a typed quantity because
///   another room was added would throw away work nobody asked to discard.
/// * **An item that is newly suggested** starts with `requested = suggested`, the
///   same way a fresh draft does.
/// * **An item that is no longer suggested** is *not* deleted. Its suggestion
///   drops to zero, which by G-P3 turns it into a manual request — so it stays
///   visible, stays requested, and now requires a written reason. Silently
///   removing a line the branch head had already edited would lose a decision
///   they made; the note requirement is how the document asks them to confirm it
///   instead.
///
/// The whole reconciliation is one transaction: a document citing new counts while
/// its lines still hold the old arithmetic is a state no reader should ever see.
class ReplacePurchaseRequestOpnamesUseCase {
  ReplacePurchaseRequestOpnamesUseCase({
    required this._requests,
    required MasterDataRepository master,
    PurchaseRequestSuggestionBuilder? suggestions,
    DateTime Function()? clock,
  }) : _guards = PurchaseRequestGuards(master),
       _suggestions =
           suggestions ??
           PurchaseRequestSuggestionBuilder(
             requests: _requests,
             master: master,
           ),
       _clock = clock ?? _defaultClock;

  final PurchaseRequestRepository _requests;
  final PurchaseRequestGuards _guards;
  final PurchaseRequestSuggestionBuilder _suggestions;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<PurchaseRequestDetail> call({
    required String actorUserId,
    required String prId,
    required List<String> selectedOpnameIds,
  }) async {
    final actor = await _guards.requireBranchActor(actorUserId, prId: prId);
    final now = _clock().toUtc();

    return _requests.runInTransaction(() async {
      final detail = await _requests.getDetail(prId);
      if (detail == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan.',
          prId: prId,
        );
      }

      final request = detail.request;
      _guards.requireSameBranch(actor: actor, request: request);
      // G-P5. Re-picking the citations of a submitted document would change the
      // evidence under an order the warehouse is already acting on.
      _guards.requireStatus(
        request: request,
        expected: PurchaseRequestStatus.draft,
      );

      // Every reference is validated afresh, at *now* rather than at the instant
      // the draft was created: a draft left open across a week boundary must not
      // be able to keep citing a count that has since aged out (G-P1).
      final suggestion = await _suggestions.build(
        branchId: request.branchId,
        opnameIds: selectedOpnameIds,
        utcNow: now,
        prId: prId,
      );

      await _requests.replaceOpnameLinksAndSuggestions(
        prId: prId,
        opnameIds: suggestion.references
            .map((reference) => reference.opnameId)
            .toList(growable: false),
        lines: _reconcile(existing: detail.lines, suggested: suggestion.lines),
      );

      final updated = await _requests.getDetail(prId);
      if (updated == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan setelah diperbarui.',
          prId: prId,
        );
      }
      return updated;
    });
  }

  /// Merges the new proposal with what the branch head already has.
  List<PurchaseRequestLineReconciliation> _reconcile({
    required List<PurchaseRequestLine> existing,
    required List<SuggestedPurchaseRequestLine> suggested,
  }) {
    final byItem = {for (final line in existing) line.itemId: line};
    final reconciled = <PurchaseRequestLineReconciliation>[];
    final touched = <String>{};

    for (final proposal in suggested) {
      touched.add(proposal.itemId);
      final current = byItem[proposal.itemId];
      reconciled.add(
        PurchaseRequestLineReconciliation(
          lineId: current?.id,
          itemId: proposal.itemId,
          suggestedQty: proposal.suggestedQty,
          // An existing line keeps what was typed into it; a new one starts from
          // the system's number.
          requestedQty: current?.requestedQty ?? proposal.suggestedQty,
          note: current?.note,
        ),
      );
    }

    for (final line in existing) {
      if (touched.contains(line.itemId)) continue;
      reconciled.add(
        PurchaseRequestLineReconciliation(
          lineId: line.id,
          itemId: line.itemId,
          // No longer proposed by any cited room, so the system suggests nothing
          // — which is exactly what makes it a manual request needing a reason.
          suggestedQty: Quantity.zero(),
          requestedQty: line.requestedQty,
          note: line.note,
        ),
      );
    }

    return reconciled;
  }
}
