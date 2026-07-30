import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../models/disposal_models.dart';

/// G-E7 — which stock may be destroyed, in one place (§16).
///
/// One rule, and it is absolute: **only a batch that has already expired.** Not a
/// batch expiring today, not one inside its alert window, not one that is merely
/// damaged — those are different situations with different answers, and none of
/// them is this milestone's.
///
/// ### The boundary
///
/// Every date question is answered in **operational time** (GMT+8), never in the
/// device's zone (T-3/T-4). A batch is usable for the whole of its expiry day and
/// becomes disposable from the next operational day onwards (T-10):
///
/// | `expiry_date` | operational date | disposable |
/// |---------------|------------------|------------|
/// | 2026-07-30    | 2026-07-30       | no         |
/// | 2026-07-30    | 2026-07-31       | yes        |
///
/// The two halves are the same line drawn from opposite sides, and they must stay
/// exactly complementary: `DistributionExpiryPolicy.isExpired` blocks a batch from
/// a distribution on precisely the day this policy starts allowing it onto a
/// disposal. If they ever disagreed there would be a day on which a batch could go
/// nowhere at all, or one on which it could go to both.
///
/// `expiry_date` itself is a **civil date** and is never timezone converted (T-9);
/// what gets converted is "now", into the operational day it falls on.
///
/// ### What no amount of confirmation can do
///
/// Nothing here takes a `force`, a `confirmed` or an override reason. A batch that
/// has not expired cannot be put on a disposal by any path in this milestone — not
/// by a stale form, not by a note explaining why, not by a user who is certain. The
/// reason is not squeamishness: `disposal` is the one movement type that removes
/// stock without a destination, so a mistake here is a quantity that simply
/// vanishes from the ledger with no counter-entry to find it by. Damaged, recalled
/// and rejected goods leave through workflows that do not exist yet, and inventing
/// one by loosening this check is exactly how they would come to have no audit
/// trail of their own.
///
/// It is asked when a candidate list is built, again when a line is added, again
/// when one is edited, and a fourth time inside the posting transaction. The last
/// one is the one that matters: a batch that had a day of shelf life left when the
/// form opened is a different question by the time the button is pressed — and, in
/// this direction, a batch that expired *while the draft sat open* legitimately
/// becomes eligible, which is why the draft is revalidated rather than frozen.
abstract final class DisposalExpiryPolicy {
  /// Whether [expiryDate] has passed as of the UTC instant [nowUtc].
  ///
  /// The canonical rule, stated once: `operationalDate > expiryDate`. Equality is
  /// **not** expired — a batch is good until the end of its date.
  static bool isExpired({
    required DateTime expiryDate,
    required DateTime nowUtc,
  }) => DateOnly.isBeforeDate(expiryDate, AppTimeZone.operationalDate(nowUtc));

  /// Whether this batch may go on a disposal at all.
  ///
  /// A synonym of [isExpired] by design rather than by accident. Naming it
  /// separately is what lets a caller say *what it is asking* — "is this
  /// disposable" rather than "is this expired" — so that if the two ever diverge
  /// (a damaged-goods workflow, say) the divergence happens here rather than at
  /// twelve call sites that all happened to ask the wrong question.
  static bool isDisposable({
    required DateTime expiryDate,
    required DateTime nowUtc,
  }) => isExpired(expiryDate: expiryDate, nowUtc: nowUtc);

  /// Whole operational days **since** expiry. Zero on the expiry day itself — when
  /// the batch is not yet disposable — and one on the first day it is.
  ///
  /// An `int`, never a `double` (§12): a count of days has no fractional part.
  static int daysExpired({
    required DateTime expiryDate,
    required DateTime nowUtc,
  }) => DateOnly.daysBetween(expiryDate, AppTimeZone.operationalDate(nowUtc));

  /// Whole operational days **until** expiry; negative once it has passed.
  ///
  /// The mirror of [daysExpired], kept so the *informational* near-expiry section
  /// on the screens can be worded the way G-E6 words it without a caller negating
  /// a number and getting the sign wrong.
  static int remainingDays({
    required DateTime expiryDate,
    required DateTime nowUtc,
  }) => DateOnly.daysBetween(AppTimeZone.operationalDate(nowUtc), expiryDate);

  /// Whether the batch is inside the item's alert window (G-E6) — *segera
  /// kedaluwarsa*.
  ///
  /// This drives a **badge and an informational list**, never a disposal
  /// candidate. §28 is explicit: near-expiry stock may be shown on its own section
  /// so a reader knows what is coming, and it must not be selectable. An
  /// already-expired batch answers `false` here: it is the stricter case and
  /// [isExpired] is what reports it, which is what lets a badge say *kedaluwarsa*
  /// rather than *segera kedaluwarsa*.
  static bool isNearExpiry({
    required DateTime expiryDate,
    required int expiryAlertDays,
    required DateTime nowUtc,
  }) {
    if (isExpired(expiryDate: expiryDate, nowUtc: nowUtc)) return false;
    return remainingDays(expiryDate: expiryDate, nowUtc: nowUtc) <
        expiryAlertDays;
  }

  /// The positions of [positions] that may actually be destroyed.
  ///
  /// Filters out everything not yet expired and everything with nothing left on the
  /// shelf, then orders by risk. Archived items and batches are **kept**: the row
  /// is history, not absence, and the stock it describes is physically there — a
  /// product withdrawn from the catalogue can still be rotting on a shelf, and
  /// refusing to list it would leave stock nobody can ever remove (§17).
  static List<ExpiredStockPosition> disposablePositions({
    required List<ExpiredStockPosition> positions,
    required DateTime nowUtc,
  }) {
    final disposable = positions
        .where(
          (position) =>
              position.qtyOnHand.isPositive &&
              isDisposable(expiryDate: position.expiryDate, nowUtc: nowUtc),
        )
        .toList();
    sortByRisk(disposable);
    return List<ExpiredStockPosition>.unmodifiable(disposable);
  }

  /// The candidates of [candidates] that may actually be destroyed — the same rule
  /// as [disposablePositions], applied to a document's own candidate shape.
  static List<DisposalCandidate> disposableCandidates({
    required List<DisposalCandidate> candidates,
    required DateTime nowUtc,
  }) {
    final disposable = candidates
        .where(
          (candidate) =>
              candidate.availableQty.isPositive &&
              isDisposable(expiryDate: candidate.expiryDate, nowUtc: nowUtc),
        )
        .toList();
    sortCandidatesByRisk(disposable);
    return List<DisposalCandidate>.unmodifiable(disposable);
  }

  /// Sorts [positions] in place into the canonical risk order.
  ///
  /// `(expiry_date, item name, batch_no, batch_id)` — four keys, because the first
  /// three can tie and a list that depends on the order rows happened to come back
  /// in is a list that differs between two devices holding the same stock. The
  /// database query orders the same way; this exists so an in-memory list is
  /// ordered identically.
  ///
  /// Oldest first, which is the opposite emphasis to FEFO's "use this next" and the
  /// same arithmetic: everything here is already expired, so the batch that has
  /// been sitting there longest is the one to deal with first (§17).
  static void sortByRisk(List<ExpiredStockPosition> positions) {
    positions.sort((a, b) {
      final byExpiry = DateOnly.compare(a.expiryDate, b.expiryDate);
      if (byExpiry != 0) return byExpiry;
      final byItem = a.itemName.compareTo(b.itemName);
      if (byItem != 0) return byItem;
      final byBatch = a.batchNo.compareTo(b.batchNo);
      if (byBatch != 0) return byBatch;
      return a.batchId.compareTo(b.batchId);
    });
  }

  /// [sortByRisk] for a document's candidates.
  static void sortCandidatesByRisk(List<DisposalCandidate> candidates) {
    candidates.sort((a, b) {
      final byExpiry = DateOnly.compare(a.expiryDate, b.expiryDate);
      if (byExpiry != 0) return byExpiry;
      final byItem = a.itemName.compareTo(b.itemName);
      if (byItem != 0) return byItem;
      final byBatch = a.batchNo.compareTo(b.batchNo);
      if (byBatch != 0) return byBatch;
      return a.batchId.compareTo(b.batchId);
    });
  }
}
