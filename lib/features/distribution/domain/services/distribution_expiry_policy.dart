import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../models/distribution_models.dart';

/// G-E4 — what expiry means for a distribution, in one place.
///
/// One rule, and it is absolute: **an expired batch is blocked outright.** No
/// confirmation, no note and no override reason can put one on a distribution. It is
/// refused when the candidate list is built, refused again if a stale form submits
/// it, and refused a third time inside the posting transaction. The stock stays on
/// the shelf and leaves the system through disposal instead (G-E7) — a workflow this
/// milestone does not open.
///
/// ### What this policy deliberately does *not* do
///
/// It has no near-expiry **confirmation**. G-E4 gives that requirement to the
/// warehouse when it builds a Delivery Order — *"Warehouse juga tidak boleh mengirim
/// barang dengan sisa umur < `expiry_alert_days` tanpa konfirmasi eksplisit"* — and
/// widening it to the branch head's distribution would be inventing a rule the
/// specification does not state. A near-expiry batch in a branch store is exactly
/// the stock that *should* be used next, and FEFO already puts it first. What the
/// branch head gets is the orange badge G-E6 asks for, not a gate.
///
/// Every date question is answered in **operational time** (GMT+8), never in the
/// device's zone (T-3/T-4). A batch is usable for the whole of its expiry day and is
/// refused from the next day onwards (T-10):
///
/// | `expiry_date` | operational date | result   |
/// |---------------|------------------|----------|
/// | 2026-07-30    | 2026-07-30       | valid    |
/// | 2026-07-30    | 2026-07-31       | expired  |
///
/// `expiry_date` itself is a **civil date** and is never timezone converted (T-9);
/// what gets converted is "now", into the operational day it falls on.
abstract final class DistributionExpiryPolicy {
  /// Whether [expiryDate] has passed as of the UTC instant [nowUtc].
  static bool isExpired({
    required DateTime expiryDate,
    required DateTime nowUtc,
  }) => DateOnly.isBeforeDate(expiryDate, AppTimeZone.operationalDate(nowUtc));

  /// Whole operational days from today to [expiryDate]. Zero on the expiry day
  /// itself, negative once it has passed.
  static int remainingDays({
    required DateTime expiryDate,
    required DateTime nowUtc,
  }) => DateOnly.daysBetween(AppTimeZone.operationalDate(nowUtc), expiryDate);

  /// Whether the batch is inside the item's alert window (G-E6).
  ///
  /// Strictly less than, because the specification words the threshold *"sisa umur <
  /// `expiry_alert_days`"*. An already-expired batch answers `false`: it is a
  /// different, stricter case and [isExpired] is what reports it. Keeping the two
  /// apart is what lets a badge say *kedaluwarsa* rather than *segera kedaluwarsa*.
  ///
  /// This drives a **badge**, never a refusal — see the class note.
  static bool isNearExpiry({
    required DateTime expiryDate,
    required int expiryAlertDays,
    required DateTime nowUtc,
  }) {
    if (isExpired(expiryDate: expiryDate, nowUtc: nowUtc)) return false;
    return remainingDays(expiryDate: expiryDate, nowUtc: nowUtc) <
        expiryAlertDays;
  }

  /// The batches of one item a new allocation may choose from.
  ///
  /// Filters out expired batches and batches with nothing left, then orders them the
  /// way FEFO consumes them. Archived (`deleted_at IS NOT NULL`) batches are
  /// **kept**: the row is history, not absence, and the stock it holds is real — a
  /// draft already allocated against one must still be postable (§32). What is
  /// excluded is only what cannot legitimately move.
  static List<DistributionBatchCandidate> usableCandidates({
    required List<DistributionBatchCandidate> candidates,
    required DateTime nowUtc,
  }) {
    final usable = candidates
        .where(
          (candidate) =>
              candidate.availableQty.isPositive &&
              !isExpired(expiryDate: candidate.expiryDate, nowUtc: nowUtc),
        )
        .toList();
    sortForFefo(usable);
    return List<DistributionBatchCandidate>.unmodifiable(usable);
  }

  /// The expired batches among [candidates] — what the form explains rather than
  /// silently omitting, and what disposal will later have to deal with (G-E7).
  ///
  /// Kept even at zero quantity is *not* the behaviour here: a batch with nothing on
  /// the shelf is not stock anybody has to be told about. What this returns is
  /// expired stock the store still physically holds.
  static List<DistributionBatchCandidate> expiredCandidates({
    required List<DistributionBatchCandidate> candidates,
    required DateTime nowUtc,
  }) {
    final expired = candidates
        .where(
          (candidate) =>
              candidate.availableQty.isPositive &&
              isExpired(expiryDate: candidate.expiryDate, nowUtc: nowUtc),
        )
        .toList();
    sortForFefo(expired);
    return List<DistributionBatchCandidate>.unmodifiable(expired);
  }

  /// Sorts [candidates] in place into the canonical FEFO order.
  ///
  /// `(expiry_date, batch_no, batch_id)` — three keys, because the first two can tie
  /// and an allocation that depends on the order rows happened to come back in is an
  /// allocation that differs between two devices holding the same stock. The
  /// database query orders the same way; this exists so an in-memory list is ordered
  /// identically.
  static void sortForFefo(List<DistributionBatchCandidate> candidates) {
    candidates.sort((a, b) {
      final byExpiry = DateOnly.compare(a.expiryDate, b.expiryDate);
      if (byExpiry != 0) return byExpiry;
      final byBatchNo = a.batchNo.compareTo(b.batchNo);
      if (byBatchNo != 0) return byBatchNo;
      return a.batchId.compareTo(b.batchId);
    });
  }

  /// Total usable (non-expired, positive) stock across [candidates].
  static Quantity usableTotal({
    required List<DistributionBatchCandidate> candidates,
    required DateTime nowUtc,
  }) => Quantity.sum(
    usableCandidates(
      candidates: candidates,
      nowUtc: nowUtc,
    ).map((candidate) => candidate.availableQty),
  );
}
