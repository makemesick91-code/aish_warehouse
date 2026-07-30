import 'package:uuid/uuid.dart';

import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import '../services/purchase_request_suggestion_builder.dart';
import 'purchase_request_guards.dart';

/// Opens a Purchase Request draft from one or more cited stock opnames (G-P1,
/// G-P3, G-P4).
///
/// The document is created already filled in: every item whose cited rooms are
/// below par level becomes a line whose `suggested_qty` is the aggregated
/// deficiency, and whose `requested_qty` starts equal to it. That snapshot is
/// written once and only ever recomputed while the draft's citation list changes
/// (`ReplacePurchaseRequestOpnamesUseCase`) — never in response to stock moving
/// afterwards, because the whole point of ordering against a count is that the
/// numbers are the ones somebody physically wrote down.
///
/// A draft with no proposed lines is a legitimate outcome, not an error: every
/// counted room may genuinely be at or above par. The branch head can still add
/// items by hand, and it is `SubmitPurchaseRequestUseCase` that refuses to send an
/// empty document.
///
/// Nothing here touches the ledger. A Purchase Request never moves stock (spec
/// §2.5).
class CreatePurchaseRequestUseCase {
  CreatePurchaseRequestUseCase({
    required this._requests,
    required MasterDataRepository master,
    PurchaseRequestSuggestionBuilder? suggestions,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _guards = PurchaseRequestGuards(master),
       _suggestions =
           suggestions ??
           PurchaseRequestSuggestionBuilder(
             requests: _requests,
             master: master,
           ),
       _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final PurchaseRequestRepository _requests;
  final PurchaseRequestGuards _guards;
  final PurchaseRequestSuggestionBuilder _suggestions;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  Future<PurchaseRequest> call({
    required String actorUserId,
    required List<String> selectedOpnameIds,
    DateTime? neededDate,
    String? note,
  }) async {
    final actor = await _guards.requireBranchActor(actorUserId);
    final branchId = actor.branchId!;
    final now = _clock().toUtc();

    // One transaction covers the active-order check, the eligibility checks, the
    // snapshot reads and the insert. Two devices tapping at the same moment
    // therefore cannot both pass the G-P4 check — and if they somehow did, the
    // partial unique index on `(branch_id) WHERE status IN (…)` is the final
    // guard.
    return _requests.runInTransaction(() async {
      // G-P4. A draft does not occupy the active-order slot, but a branch that is
      // already waiting on the warehouse has no business starting a second order:
      // the draft would only be refused at submit, after the branch head had
      // typed the whole thing.
      _guards.requireNoActiveRequest(
        branchId: branchId,
        active: await _requests.activeRequestForBranch(branchId),
      );

      final suggestion = await _suggestions.build(
        branchId: branchId,
        opnameIds: selectedOpnameIds,
        utcNow: now,
      );

      return _requests.createDraft(
        // Local temporary number: the sync backend assigns the final
        // `PR-{cabang}-{yyyyMMdd}-{seq}` when the document reaches it (G-Y4).
        // Minting a server-shaped number offline would collide across devices.
        docNumber: 'TMP-PR-${_newId()}',
        branchId: branchId,
        requestedBy: actor.id,
        neededDate: neededDate,
        note: note,
        opnameIds: suggestion.references
            .map((reference) => reference.opnameId)
            .toList(growable: false),
        lines: suggestion.lines
            .map(
              (line) => PurchaseRequestLineDraft(
                itemId: line.itemId,
                suggestedQty: line.suggestedQty,
                // The branch head starts from the system's number and edits down
                // or up from there. Starting at zero would violate
                // `requested_qty > 0` and starting blank would make every line
                // look like it needs attention.
                requestedQty: line.suggestedQty,
              ),
            )
            .toList(growable: false),
      );
    });
  }
}
