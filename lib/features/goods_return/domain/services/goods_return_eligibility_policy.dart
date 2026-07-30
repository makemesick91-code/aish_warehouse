import '../../../../core/enums/app_enums.dart';
import '../models/goods_return_models.dart';

/// Why one Good Receipt cannot be returned from.
enum GoodsReturnEligibilityRejection {
  /// No such receipt, or it is soft-deleted.
  missing,

  /// The receipt is still `checking`. A branch head part way through deciding has not
  /// refused anything yet, and a decision may still be revised in either direction
  /// while the parent is open (see [GoodReceiptLineStatus]).
  notPosted,

  /// The receipt belongs to another branch.
  branchMismatch,

  /// Every position was accepted. There is nothing to send back.
  noRejectedLines,

  /// A return already exists for this receipt — one Good Receipt, one Retur.
  alreadyReturned,
}

/// The outcome of an eligibility check.
class GoodsReturnEligibilityVerdict {
  const GoodsReturnEligibilityVerdict._(this.rejection);

  const GoodsReturnEligibilityVerdict.accepted() : rejection = null;

  const GoodsReturnEligibilityVerdict.rejected(
    GoodsReturnEligibilityRejection rejection,
  ) : this._(rejection);

  final GoodsReturnEligibilityRejection? rejection;

  bool get isAccepted => rejection == null;

  bool get isRejected => rejection != null;
}

/// Which Good Receipts a Retur may be raised from, in one place (§16).
///
/// Five conditions, all of them necessary, and the interesting one is the fourth.
///
/// ### `rejected` is the only source. A shortage is not one.
///
/// A posted Good Receipt can be short in two entirely different ways, and the schema
/// records them as two different things:
///
/// * a **`rejected`** line accepted nothing (`received_qty = 0`, mandatory reason) —
///   the goods arrived, the branch head looked at them and refused them, and they are
///   physically sitting at the branch. Those goods have to go somewhere, and G-G5 says
///   where: *"Barang rejected masuk daftar retur ke Warehouse."*
/// * a **`checked`** line with `received_qty < shipped_qty` is a **shortage** — the
///   quantity on the waybill never arrived. There is no box to send back. Whatever
///   happened, happened between the Warehouse door and the branch door, and raising a
///   return for it would create a document claiming a branch is sending back goods it
///   never had — which, once received, would credit the Warehouse with stock that does
///   not exist.
///
/// Both appear on the Warehouse discrepancy queue, because the Warehouse needs to see
/// both. Only the first is returnable, and §33 keeps them visibly distinct there: a
/// shortage reads *Kekurangan* and never carries a *Buat Retur* button.
///
/// ### Why `posted` and not `checking`
///
/// While a receipt is `checking`, a line's decision may still be revised in either
/// direction — that is exactly what `GoodReceiptLineStatus` declines to make terminal,
/// and what freezes it is the parent's status. Raising a return from an open receipt
/// would snapshot a decision that has not been made yet.
///
/// ### Why the *count* is not enough
///
/// [verify] answers from a summary; it is what the queue and the button read. The
/// create use case re-asks every one of these questions against the plain, unjoined
/// line ids inside its transaction (§17/§26), because between a screen rendering and a
/// button being pressed another device may have raised the return — and because a
/// count derived from a join is a count that can be wrong in exactly the direction that
/// matters.
abstract final class GoodsReturnEligibilityPolicy {
  /// The one Good Receipt status a return may be raised from.
  static const GoodReceiptStatus requiredReceiptStatus =
      GoodReceiptStatus.posted;

  /// The one line status that is returnable.
  static const GoodReceiptLineStatus returnableLineStatus =
      GoodReceiptLineStatus.rejected;

  /// Whether one rejected position is in a shape a return line can be cut from (§16).
  ///
  /// Four conditions, and each is a distinct way a source line could be wrong:
  ///
  /// * the status is `rejected` — the whole rule above;
  /// * `received_qty` is zero. The Good Receipt's own CHECK already guarantees this
  ///   for a rejected line, and it is verified rather than assumed because the return
  ///   quantity *is* `shipped_qty`: if anything had been accepted, sending the whole
  ///   shipped quantity back would return goods the branch kept;
  /// * `shipped_qty` is strictly positive. A return line of nothing is not a line
  ///   (G-A1), and the database refuses `qty > 0` anyway;
  /// * the reject reason is non-blank. G-G4 made it mandatory upstream; a blank one
  ///   here means the guarantee failed somewhere, and the snapshot would carry an
  ///   empty explanation into the ledger note.
  static bool isReturnablePosition(RejectedGoodReceiptPosition position) =>
      position.receivedQty.isZero &&
      position.shippedQty.isPositive &&
      position.rejectReason.trim().isNotEmpty;

  /// Whether a `checked` line that arrived short is returnable. **Always false**, and
  /// it is a named function rather than an absence so the rule is testable and the
  /// architecture check has something to point at (§16.10/§44).
  static bool isShortageReturnable() => false;

  /// Whether a Kepala Cabang of [actorBranchId] may raise a return from this receipt.
  ///
  /// The branch check runs before the content checks so a message never confirms
  /// anything about another branch's receipt — including whether it had rejections.
  static GoodsReturnEligibilityVerdict verify({
    required GoodReceiptStatus? receiptStatus,
    required String? receiptBranchId,
    required String actorBranchId,
    required int rejectedLineCount,
    required bool hasExistingReturn,
  }) {
    if (receiptStatus == null || receiptBranchId == null) {
      return const GoodsReturnEligibilityVerdict.rejected(
        GoodsReturnEligibilityRejection.missing,
      );
    }
    if (receiptBranchId != actorBranchId) {
      return const GoodsReturnEligibilityVerdict.rejected(
        GoodsReturnEligibilityRejection.branchMismatch,
      );
    }
    if (receiptStatus != requiredReceiptStatus) {
      return const GoodsReturnEligibilityVerdict.rejected(
        GoodsReturnEligibilityRejection.notPosted,
      );
    }
    if (hasExistingReturn) {
      return const GoodsReturnEligibilityVerdict.rejected(
        GoodsReturnEligibilityRejection.alreadyReturned,
      );
    }
    if (rejectedLineCount <= 0) {
      return const GoodsReturnEligibilityVerdict.rejected(
        GoodsReturnEligibilityRejection.noRejectedLines,
      );
    }
    return const GoodsReturnEligibilityVerdict.accepted();
  }

  /// [verify], asked of a queue row the screen already holds.
  static GoodsReturnEligibilityVerdict verifyEligibility({
    required GoodsReturnEligibility eligibility,
    required String actorBranchId,
  }) => verify(
    // A row only ever comes out of the eligible query for a posted receipt, so the
    // status is known — but it is stated rather than skipped, because this function is
    // also what a test hands a hand-built row to.
    receiptStatus: requiredReceiptStatus,
    receiptBranchId: eligibility.branchId,
    actorBranchId: actorBranchId,
    rejectedLineCount: eligibility.rejectedLineCount,
    hasExistingReturn: eligibility.hasReturn,
  );
}
