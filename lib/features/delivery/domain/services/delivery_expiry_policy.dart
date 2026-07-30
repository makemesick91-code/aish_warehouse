import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../models/delivery_models.dart';

/// G-E4 — what expiry means for a shipment, in one place.
///
/// Two rules, and they are not the same rule with a different threshold:
///
/// * **Expired is blocked outright.** No confirmation, no note and no reason can
///   let an expired batch onto a Delivery Order. It is refused when the candidate
///   list is built, refused again if a stale form submits it, and refused a third
///   time inside the posting transaction.
/// * **Near expiry needs an explicit confirmation.** A batch with less than
///   `items.expiry_alert_days` of shelf life left may ship, but only after
///   somebody says so on the record. The confirmation is stored on the line so the
///   Surat Jalan can print it and an audit can find it.
///
/// Every date question is answered in **operational time** (GMT+8), never in the
/// device's zone (T-3/T-4). A batch is usable for the whole of its expiry day and
/// is refused from the next day onwards (T-10):
///
/// | `expiry_date` | operational date | result   |
/// |---------------|------------------|----------|
/// | 2026-07-30    | 2026-07-30       | valid    |
/// | 2026-07-30    | 2026-07-31       | expired  |
///
/// `expiry_date` itself is a **civil date** and is never timezone converted (T-9);
/// what gets converted is "now", into the operational day it falls on.
abstract final class DeliveryExpiryPolicy {
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

  /// Whether shipping this batch needs an explicit confirmation (G-E4).
  ///
  /// Strictly less than, because the specification is worded
  /// *"sisa umur < `expiry_alert_days`"*. Equality is therefore **not** inside the
  /// window: 30 days left against a 30-day threshold ships without a
  /// confirmation, 29 does not. An off-by-one here would either nag on every
  /// shipment or let a nearly-expired batch through unremarked.
  ///
  /// An already-expired batch also answers `true` — its remaining days are
  /// negative — but that is never the check that decides it: [isExpired] is
  /// consulted first and refuses outright.
  static bool requiresNearExpiryConfirmation({
    required DateTime expiryDate,
    required int expiryAlertDays,
    required DateTime nowUtc,
  }) => remainingDays(expiryDate: expiryDate, nowUtc: nowUtc) < expiryAlertDays;

  /// The batches of one item a new allocation may choose from.
  ///
  /// Filters out expired batches and batches with nothing on the shelf, then
  /// orders them the way FEFO consumes them. Archived (`deleted_at IS NOT NULL`)
  /// batches are **kept**: the row is history, not absence, and the stock it holds
  /// is real — a document already allocated against one must still be able to
  /// ship. What is excluded is only what cannot legitimately move.
  static List<DeliveryBatchCandidate> usableCandidates({
    required List<DeliveryBatchCandidate> candidates,
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
    return List<DeliveryBatchCandidate>.unmodifiable(usable);
  }

  /// The expired batches among [candidates] — what the form greys out and
  /// explains rather than silently omitting.
  static List<DeliveryBatchCandidate> expiredCandidates({
    required List<DeliveryBatchCandidate> candidates,
    required DateTime nowUtc,
  }) => candidates
      .where(
        (candidate) =>
            isExpired(expiryDate: candidate.expiryDate, nowUtc: nowUtc),
      )
      .toList(growable: false);

  /// Sorts [candidates] in place into the canonical FEFO order.
  ///
  /// `(expiry_date, batch_no, batch_id)` — three keys, because the first two can
  /// tie and an allocation that depends on the order rows happened to come back in
  /// is an allocation that differs between two devices holding the same stock.
  /// The database query orders the same way; this exists so an in-memory list is
  /// ordered identically.
  static void sortForFefo(List<DeliveryBatchCandidate> candidates) {
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
    required List<DeliveryBatchCandidate> candidates,
    required DateTime nowUtc,
  }) => Quantity.sum(
    usableCandidates(
      candidates: candidates,
      nowUtc: nowUtc,
    ).map((candidate) => candidate.availableQty),
  );
}
