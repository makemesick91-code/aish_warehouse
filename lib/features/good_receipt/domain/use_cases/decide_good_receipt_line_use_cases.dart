/// The three decisions a branch head may record against one position (§24.2–24.4).
///
/// They live in one library because they are one operation with three answers, and
/// they share the whole approach shot: load the actor, load the receipt, prove it is
/// this branch's, prove it is still `checking`, prove the line is on it. Split across
/// three files that sequence would be written three times, and the copies would drift
/// — which on this path means one of them forgetting the branch check.
///
/// What is deliberately **not** here:
///
/// * no `updateLine(anything)`. Each class writes one shape of decision, and the DAO
///   underneath offers nothing more general (G-G2/G-G4);
/// * no delete. *"Hapus yang tidak sesuai"* is [RejectGoodReceiptLineUseCase], and
///   the row it writes is the audit trail;
/// * no way to reach `item_id`, `batch_id` or `shipped_qty`. Those are the snapshot
///   the shipment left. A branch head decides *about* a delivery; they do not rewrite
///   what was sent.
///
/// Every write is guarded inside its own statement, so a receipt posted by another
/// device between the read and the write yields zero rows and a
/// [ConcurrentGoodReceiptUpdateFailure] rather than a decision landing on a final
/// document.
library;

import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/good_receipt_models.dart';
import '../repositories/good_receipt_repository.dart';
import '../services/good_receipt_line_decision_policy.dart';
import 'good_receipt_guards.dart';

/// Everything the three use cases load before they decide anything.
class _DecisionTarget {
  const _DecisionTarget({
    required this.actor,
    required this.receipt,
    required this.line,
  });

  final MasterUser actor;
  final GoodReceipt receipt;
  final GoodReceiptLineReference line;
}

/// The shared approach shot. Subclasses add the one write that differs.
abstract class _GoodReceiptLineDecisionUseCase {
  _GoodReceiptLineDecisionUseCase({
    required this.receipts,
    required MasterDataRepository master,
    DateTime Function()? clock,
  }) : guards = GoodReceiptGuards(master),
       clock = clock ?? _defaultClock;

  final GoodReceiptRepository receipts;

  /// Shared so a rule fixed here is fixed for all three.
  final GoodReceiptGuards guards;

  /// UTC, injected, because G-E5 is a function of the current operational day (T-7).
  final DateTime Function() clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  /// Loads and authorises one position, or throws.
  ///
  /// The branch comes from [GoodReceiptRepository.findAccessScope], which reads five
  /// columns and nothing else: deciding whether this actor may touch the receipt must
  /// not be the reason its items, quantities and reject reasons are loaded.
  Future<_DecisionTarget> resolve({
    required String actorUserId,
    required String goodReceiptId,
    required String goodReceiptLineId,
  }) async {
    final actor = await guards.requireBranchHeadActor(actorUserId);

    final receipt = await receipts.getById(goodReceiptId);
    if (receipt == null) {
      throw GoodReceiptNotFoundFailure(
        'Good Receipt tidak ditemukan.',
        grId: goodReceiptId,
      );
    }
    // Status first: "already posted" is the message a user needs, and the transition
    // check below is the structural assertion behind it.
    guards.requireStatus(
      receipt: receipt,
      expected: GoodReceiptStatus.checking,
    );

    final scope = await receipts.findAccessScope(grId: receipt.id);
    if (scope == null) {
      throw GoodReceiptNotFoundFailure(
        'Good Receipt tidak ditemukan.',
        grId: goodReceiptId,
      );
    }
    guards.requireBranchMatches(actor: actor, documentBranchId: scope.branchId);

    final line = guards.requireLineOf(
      grId: receipt.id,
      lineId: goodReceiptLineId,
      line: await receipts.lineReferenceById(goodReceiptLineId),
    );

    return _DecisionTarget(actor: actor, receipt: receipt, line: line);
  }

  /// The item and batch behind one position, with their references verified.
  Future<({MasterItem item, MasterBatch? batch})> resolveMaster({
    required String grId,
    required GoodReceiptLineReference line,
  }) async {
    final item = await guards.requireHistoricalItem(
      grId: grId,
      itemId: line.itemId,
    );
    final batch = await guards.requireBatchConsistency(
      grId: grId,
      item: item,
      batchId: line.batchId,
    );
    return (item: item, batch: batch);
  }
}

/// `✔ Sesuai` — accepts a position, with the quantity that actually arrived
/// (§24.2, G-G2/G-G3).
///
/// The received quantity may be anything from `0` to what was shipped. A shortfall is
/// not an error: it becomes the discrepancy the warehouse investigates (G-G3), and
/// the position still counts as decided for G-G2. Accepting zero is legal too and
/// writes no movement at all — the honest record for a box that was on the manifest
/// and not in the van.
///
/// G-E5 is enforced here as well as at posting time: an expired or nearly expired
/// batch cannot be accepted, whatever quantity is typed, and no confirmation
/// overrides it. Checking again at posting is what catches a batch that crossed its
/// threshold while the checklist was open.
class CheckGoodReceiptLineUseCase extends _GoodReceiptLineDecisionUseCase {
  CheckGoodReceiptLineUseCase({
    required super.receipts,
    required super.master,
    super.clock,
  });

  Future<void> call({
    required String actorUserId,
    required String goodReceiptId,
    required String goodReceiptLineId,
    required Quantity receivedQty,
  }) async {
    return receipts.runInTransaction(() async {
      final target = await resolve(
        actorUserId: actorUserId,
        goodReceiptId: goodReceiptId,
        goodReceiptLineId: goodReceiptLineId,
      );
      final line = target.line;
      final resolved = await resolveMaster(grId: goodReceiptId, line: line);

      // G-G3, against the shipped snapshot rather than against whatever the form
      // believed was sent.
      guards.requireValidReceivedQty(
        lineId: line.id,
        shippedQty: line.shippedQty,
        receivedQty: receivedQty,
        unit: resolved.item.unit,
      );

      // G-E5. Refused outright — there is no note, tick or override that accepts an
      // expired or nearly expired batch into branch stock.
      guards.requireAcceptableExpiry(
        lineId: line.id,
        item: resolved.item,
        batch: resolved.batch,
        nowUtc: clock().toUtc(),
      );

      final applied = await receipts.decideChecked(
        grId: target.receipt.id,
        lineId: line.id,
        receivedQty: receivedQty,
      );
      if (!applied) guards.concurrentUpdate(target.receipt);
    });
  }
}

/// `✘ Tolak` — refuses a position, with a mandatory reason (§24.3, G-G4).
///
/// The row is **not** removed and never can be: the reason it carries is exactly what
/// the warehouse's retur queue reports, and a deleted line would be a refusal nobody
/// could audit. `received_qty` is forced to zero in the same statement, because a
/// refused position accepted nothing and G-G5 reads that column to decide what enters
/// the branch store.
///
/// Whitespace is not a reason, and the check happens in three places for three
/// different attackers: here for the ordinary caller, in the `UPDATE`'s `trim(?) <>
/// ''` for a stale client, and in the table's CHECK for anything that reaches the
/// file directly.
class RejectGoodReceiptLineUseCase extends _GoodReceiptLineDecisionUseCase {
  RejectGoodReceiptLineUseCase({
    required super.receipts,
    required super.master,
    super.clock,
  });

  /// [reason] is free text — usually [GoodReceiptLineDecisionPolicy.composeReason]
  /// applied to a preset from the sheet, so the audit trail survives a preset being
  /// renamed and the sync backend never has to know the enum exists.
  Future<void> call({
    required String actorUserId,
    required String goodReceiptId,
    required String goodReceiptLineId,
    required String? reason,
  }) async {
    return receipts.runInTransaction(() async {
      final target = await resolve(
        actorUserId: actorUserId,
        goodReceiptId: goodReceiptId,
        goodReceiptLineId: goodReceiptLineId,
      );
      final line = target.line;

      // The references still have to resolve. A refusal writes no movement, but it
      // does write a row that names an item and a batch, and one pointing at a
      // physically missing master row is a receipt that can never be posted.
      await resolveMaster(grId: goodReceiptId, line: line);

      final normalized = guards.requireRejectReason(
        lineId: line.id,
        reason: reason,
      );

      final applied = await receipts.decideRejected(
        grId: target.receipt.id,
        lineId: line.id,
        reason: normalized,
      );
      if (!applied) guards.concurrentUpdate(target.receipt);
    });
  }
}

/// Undo — puts a decided position back to `pending` (§24.4).
///
/// A branch head who ticked the wrong row has to be able to take it back, and G-G2 is
/// about the state at *posting* time rather than about the order the rows were
/// touched in. The received quantity returns to the shipped snapshot and the reason is
/// cleared, so the position is exactly as the snapshot left it.
///
/// A controlled operation rather than a generic update: "undo this decision" is one
/// reachable, guarded action, and "write whatever you like into a line" is not one at
/// all. After the receipt is posted this refuses like every other write.
class ResetGoodReceiptLineUseCase extends _GoodReceiptLineDecisionUseCase {
  ResetGoodReceiptLineUseCase({
    required super.receipts,
    required super.master,
    super.clock,
  });

  Future<void> call({
    required String actorUserId,
    required String goodReceiptId,
    required String goodReceiptLineId,
  }) async {
    return receipts.runInTransaction(() async {
      final target = await resolve(
        actorUserId: actorUserId,
        goodReceiptId: goodReceiptId,
        goodReceiptLineId: goodReceiptLineId,
      );

      final applied = await receipts.resetDecision(
        grId: target.receipt.id,
        lineId: target.line.id,
      );
      if (!applied) guards.concurrentUpdate(target.receipt);
    });
  }
}
