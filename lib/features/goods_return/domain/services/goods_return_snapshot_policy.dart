import '../models/goods_return_models.dart';

/// The precise way a stored snapshot has stopped describing the Good Receipt it was
/// cut from (§18/§26).
///
/// Each value names one *shape* of disagreement rather than one line, because the
/// caller reports the first mismatch it finds and the reader needs to know what kind of
/// thing went wrong — a line that vanished is a different problem from a quantity that
/// moved.
enum GoodsReturnSnapshotMismatch {
  /// The document has no lines at all. A return of nothing cannot be shipped or
  /// received.
  empty,

  /// A rejected Good Receipt position has no return line. Either the line was removed
  /// — nothing in this application can do that — or a *join* dropped it because the
  /// item or batch it points at is physically gone. Both must refuse, and this is
  /// exactly why the check reads plain ids rather than a joined result (§26).
  missingLine,

  /// The document carries a line for a position the receipt does not list as rejected.
  /// A line was added, or a receipt line was revised after the fact.
  extraLine,

  /// The same Good Receipt position appears on two return lines. The unique index
  /// makes this unreachable through SQLite; it is checked because the check is what
  /// makes that a *verified* fact rather than an assumption about an index that a
  /// future migration might relax.
  duplicateLine,

  /// A return line's quantity is no longer the source line's `shipped_qty`.
  quantity,

  /// A return line points at a different item than the source position.
  item,

  /// A return line points at a different batch — or carries one where the source has
  /// none, or vice versa.
  batch,

  /// The snapshotted reject reason no longer matches the source line's, or has become
  /// blank.
  rejectReason,
}

/// The outcome of a snapshot check. Carries the offending line so the failure message
/// can name a position rather than a document.
class GoodsReturnSnapshotVerdict {
  const GoodsReturnSnapshotVerdict._(this.mismatch, this.grLineId);

  const GoodsReturnSnapshotVerdict.matches() : mismatch = null, grLineId = null;

  const GoodsReturnSnapshotVerdict.mismatched(
    GoodsReturnSnapshotMismatch mismatch, {
    String? grLineId,
  }) : this._(mismatch, grLineId);

  final GoodsReturnSnapshotMismatch? mismatch;

  /// The Good Receipt line the disagreement is about, when there is one.
  final String? grLineId;

  bool get matches => mismatch == null;

  bool get isMismatched => mismatch != null;
}

/// What a Retur snapshot must always be, and how that is verified (§18/§26).
///
/// ### The rule
///
/// A return covers **every** rejected line of its Good Receipt and **only** those
/// lines, and each line reproduces its source exactly:
///
/// ```text
/// item_id                = GR line item_id
/// batch_id               = GR line batch_id
/// qty                    = GR line shipped_qty
/// reject_reason_snapshot = GR line reject_reason
/// ```
///
/// There is no partial return: a branch head cannot tick three of five rejections and
/// keep the other two. That is a deliberate scope decision (§4) and it is also the
/// honest one — the two they kept would be goods with no document explaining where they
/// went, sitting in a branch that has already told the Warehouse the receipt is closed.
///
/// ### Why this is checked *three* times
///
/// Once at creation, so a document is never written wrong. Again before shipping, and
/// again before receiving — and those two are the ones that earn their keep, because
/// the snapshot is not the only copy of these facts. The Good Receipt line still
/// exists, the item still exists, the batch still exists, and something could have
/// happened to any of them since. Receiving a return whose lines no longer match the
/// receipt would credit the Warehouse from a document that has stopped being evidence.
///
/// ### Why the input is plain ids
///
/// [verifyLineSet] takes two id collections and nothing else. Handing it a joined read
/// would defeat it: an `INNER JOIN items` silently drops a line whose item row was
/// physically deleted, so a corrupted document would arrive here looking *smaller* but
/// perfectly consistent, and the check would pass. The DAO therefore exposes
/// `rejectedGoodReceiptLineIdsOf` and `lineGrLineIdsOf` as single-column, join-free
/// queries, and this is what compares them (§26).
///
/// Nothing here repairs anything. A mismatch is always a refusal — never a line
/// skipped, never a reference substituted, never a quantity adjusted to fit.
abstract final class GoodsReturnSnapshotPolicy {
  /// Whether the set of Good Receipt lines a document claims is exactly the set the
  /// receipt rejects.
  ///
  /// [expectedGrLineIds] comes from the receipt, [actualGrLineIds] from the return —
  /// both as plain ids read without a join. Duplicates in [actualGrLineIds] are a
  /// mismatch in their own right rather than being collapsed by the set conversion.
  static GoodsReturnSnapshotVerdict verifyLineSet({
    required Iterable<String> expectedGrLineIds,
    required Iterable<String> actualGrLineIds,
  }) {
    final actualList = actualGrLineIds.toList(growable: false);
    if (actualList.isEmpty) {
      return const GoodsReturnSnapshotVerdict.mismatched(
        GoodsReturnSnapshotMismatch.empty,
      );
    }

    final seen = <String>{};
    for (final id in actualList) {
      if (!seen.add(id)) {
        return GoodsReturnSnapshotVerdict.mismatched(
          GoodsReturnSnapshotMismatch.duplicateLine,
          grLineId: id,
        );
      }
    }

    final expected = expectedGrLineIds.toSet();
    for (final id in expected) {
      if (!seen.contains(id)) {
        return GoodsReturnSnapshotVerdict.mismatched(
          GoodsReturnSnapshotMismatch.missingLine,
          grLineId: id,
        );
      }
    }
    for (final id in seen) {
      if (!expected.contains(id)) {
        return GoodsReturnSnapshotVerdict.mismatched(
          GoodsReturnSnapshotMismatch.extraLine,
          grLineId: id,
        );
      }
    }
    return const GoodsReturnSnapshotVerdict.matches();
  }

  /// Whether one stored line still reproduces its source position exactly.
  ///
  /// Checked field by field rather than by equality on a value object, so the failure
  /// can say *which* fact moved — the difference between *"quantity no longer matches"*
  /// and *"this document no longer matches"* is the difference between a message an
  /// administrator can act on and one they cannot.
  static GoodsReturnSnapshotVerdict verifyLine({
    required GoodsReturnLineReference line,
    required RejectedGoodReceiptPosition position,
  }) {
    if (line.itemId != position.itemId) {
      return GoodsReturnSnapshotVerdict.mismatched(
        GoodsReturnSnapshotMismatch.item,
        grLineId: position.grLineId,
      );
    }
    if (line.batchId != position.batchId) {
      return GoodsReturnSnapshotVerdict.mismatched(
        GoodsReturnSnapshotMismatch.batch,
        grLineId: position.grLineId,
      );
    }
    // The quantity rule, stated once: it is the source line's `shipped_qty`, because a
    // rejection accepted nothing and everything that was sent is coming back (§18).
    if (line.qty != position.returnQty) {
      return GoodsReturnSnapshotVerdict.mismatched(
        GoodsReturnSnapshotMismatch.quantity,
        grLineId: position.grLineId,
      );
    }
    final stored = line.rejectReason.trim();
    if (stored.isEmpty || stored != position.rejectReason.trim()) {
      return GoodsReturnSnapshotVerdict.mismatched(
        GoodsReturnSnapshotMismatch.rejectReason,
        grLineId: position.grLineId,
      );
    }
    return const GoodsReturnSnapshotVerdict.matches();
  }

  /// Both halves at once: the set, then every line in it.
  ///
  /// The order matters. Checking the set first means a missing line is reported as a
  /// *missing line* rather than as whatever the per-line loop happens to trip over
  /// while walking a document that is already the wrong shape.
  static GoodsReturnSnapshotVerdict verify({
    required List<GoodsReturnLineReference> lines,
    required List<RejectedGoodReceiptPosition> positions,
  }) {
    final setVerdict = verifyLineSet(
      expectedGrLineIds: positions.map((position) => position.grLineId),
      actualGrLineIds: lines.map((line) => line.grLineId),
    );
    if (setVerdict.isMismatched) return setVerdict;

    final byGrLineId = {
      for (final position in positions) position.grLineId: position,
    };
    for (final line in lines) {
      final position = byGrLineId[line.grLineId];
      if (position == null) {
        // Unreachable after the set check; kept because "the set said so" is an
        // assumption and this is a verification.
        return GoodsReturnSnapshotVerdict.mismatched(
          GoodsReturnSnapshotMismatch.extraLine,
          grLineId: line.grLineId,
        );
      }
      final verdict = verifyLine(line: line, position: position);
      if (verdict.isMismatched) return verdict;
    }
    return const GoodsReturnSnapshotVerdict.matches();
  }
}
