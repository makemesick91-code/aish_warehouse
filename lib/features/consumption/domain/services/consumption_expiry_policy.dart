import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';

/// Which stock may be consumed, in one place (§17).
///
/// One rule, and it is absolute: **a batch that has already expired may not be used.**
/// G-E7 states where expired stock does go — *"Barang kedaluwarsa dikeluarkan dari
/// stok hanya lewat movement `disposal` (pemusnahan) dengan catatan & pelaku"* — so
/// consumption is not an alternative route out. It is the same blocking rule G-E4
/// applies to a DO and a distribution, applied to the last leg of the chain.
///
/// ### The boundary
///
/// Every date question is answered in **operational time** (GMT+8), never in the
/// device's zone (T-3/T-4). A batch is usable for the whole of its expiry day and is
/// blocked from the next operational day onwards (T-10):
///
/// | `expiry_date` | operational date | consumable |
/// |---------------|------------------|------------|
/// | 2026-07-30    | 2026-07-30       | yes        |
/// | 2026-07-30    | 2026-07-31       | no         |
///
/// This is exactly `DistributionExpiryPolicy`'s line and exactly the complement of
/// `DisposalExpiryPolicy`'s: a batch becomes disposable on precisely the day this
/// policy stops allowing it to be used. If the two ever disagreed there would be a day
/// on which a batch could go nowhere at all, or one on which it could go to both.
///
/// `expiry_date` itself is a **civil date** and is never timezone converted (T-9);
/// what gets converted is "now", into the operational day it falls on.
///
/// ### Nullable dates are first-class here
///
/// Every method takes `DateTime? expiryDate`, unlike the disposal's equivalents. A
/// consumption legitimately covers items without an expiry date at all (G-E2), and a
/// policy that could not express that would push a `?? false` into every caller —
/// which is how one of them eventually gets the polarity wrong. An item without a date
/// has nothing that can be past it, so [isExpired] answers `false` and [isNearExpiry]
/// answers `false`.
///
/// ### Near-expiry is a badge, not a block
///
/// This is the one place this policy differs in *shape* from the delivery and
/// distribution ones. G-E6 asks for a *"Segera kedaluwarsa"* badge on every role's
/// dashboard, and a nurse reaching for the batch that expires soonest is doing exactly
/// the right thing — that is what FEFO is *for*. So [isNearExpiry] drives an orange
/// badge and nothing else: no confirmation, no override reason, no refusal. Copying
/// G-E4's *"tidak boleh mengirim barang dengan sisa umur < expiry_alert_days tanpa
/// konfirmasi eksplisit"* here would be copying a rule about shipping goods *to* a
/// clinic into the moment they are used *in* one, which would make the nearest-expiry
/// stock the hardest to use up.
///
/// ### What no amount of confirmation can do
///
/// Nothing here takes a `force`, a `confirmed` or an override reason. An expired batch
/// cannot be put on a consumption by any path in this milestone — not by a stale form,
/// not by a note explaining why, not by a user who is certain. `consumption` is a
/// movement type that removes stock without a destination, so letting an expired batch
/// through would take it out of the ledger as though it had been legitimately used and
/// leave G-E7's audit trail — the reason and the actor a Pemusnahan records — with
/// nothing to describe.
///
/// It is asked when a candidate list is built, again when a line is added, again when
/// one is edited, and a fourth time inside the posting transaction. The last one is the
/// one that matters: a batch that had a day of shelf life left when the form opened is
/// a different question by the time the button is pressed — and, in this direction, a
/// batch that expired *while the draft sat open* becomes ineligible, which is why the
/// draft is revalidated rather than frozen.
abstract final class ConsumptionExpiryPolicy {
  /// Whether [expiryDate] has passed as of the UTC instant [nowUtc].
  ///
  /// The canonical rule, stated once: `operationalDate > expiryDate`. Equality is
  /// **not** expired — a batch is good until the end of its date. `null` is never
  /// expired: an item without an expiry date has no date to be past.
  static bool isExpired({
    required DateTime? expiryDate,
    required DateTime nowUtc,
  }) {
    if (expiryDate == null) return false;
    return DateOnly.isBeforeDate(
      expiryDate,
      AppTimeZone.operationalDate(nowUtc),
    );
  }

  /// Whether this batch may be consumed at all.
  ///
  /// The negation of [isExpired] by design rather than by accident. Naming it
  /// separately is what lets a caller say *what it is asking* — "may this be used"
  /// rather than "is this expired" — so that if the two ever diverge (a quarantine
  /// state, say) the divergence happens here rather than at twelve call sites that all
  /// happened to ask the wrong question.
  static bool isConsumable({
    required DateTime? expiryDate,
    required DateTime nowUtc,
  }) => !isExpired(expiryDate: expiryDate, nowUtc: nowUtc);

  /// Whole operational days **until** expiry; negative once it has passed. `null` for
  /// an item without an expiry date.
  ///
  /// An `int`, never a `double` (§18): a count of days has no fractional part.
  static int? remainingDays({
    required DateTime? expiryDate,
    required DateTime nowUtc,
  }) {
    if (expiryDate == null) return null;
    return DateOnly.daysBetween(
      AppTimeZone.operationalDate(nowUtc),
      expiryDate,
    );
  }

  /// Whole operational days **since** expiry; negative while it is still in date.
  ///
  /// The mirror of [remainingDays], kept so a message can say *how long ago* a batch
  /// expired without a caller negating a number and getting the sign wrong.
  static int? daysExpired({
    required DateTime? expiryDate,
    required DateTime nowUtc,
  }) {
    if (expiryDate == null) return null;
    return DateOnly.daysBetween(
      expiryDate,
      AppTimeZone.operationalDate(nowUtc),
    );
  }

  /// Whether the batch is inside the item's alert window (G-E6) — *segera
  /// kedaluwarsa*.
  ///
  /// This drives a **badge**, never a refusal (see the class note). An already-expired
  /// batch answers `false`: it is the stricter case and [isExpired] is what reports it,
  /// which is what lets a badge say *Kedaluwarsa* rather than *Segera kedaluwarsa*. An
  /// item without an expiry date answers `false` too.
  ///
  /// The comparison is `<=`, following G-E6's wording — *"sisa umur ≤
  /// `expiry_alert_days`"* — so a batch exactly at the boundary is badged rather than
  /// silently ignored.
  static bool isNearExpiry({
    required DateTime? expiryDate,
    required int expiryAlertDays,
    required DateTime nowUtc,
  }) {
    if (expiryDate == null) return false;
    if (isExpired(expiryDate: expiryDate, nowUtc: nowUtc)) return false;
    final remaining = remainingDays(expiryDate: expiryDate, nowUtc: nowUtc);
    if (remaining == null) return false;
    return remaining <= expiryAlertDays;
  }

  /// Sorts positions into the canonical picker order and drops what may not be used.
  ///
  /// [expiryDateOf] and [nameOf] are read from whatever shape the caller holds —
  /// `RoomStockPosition` on the dashboard, `ConsumptionCandidate` on a form — so the
  /// two never come to be ordered differently.
  ///
  /// The order is `(item name, expiry date, batch no, batch id)` — four keys, because
  /// the first three can tie and a list that depends on the order rows happened to
  /// come back in is a list that differs between two devices holding the same stock.
  /// The database query orders the same way; this exists so an in-memory list is
  /// ordered identically.
  ///
  /// Nearest expiry first *within one item* is **operational help, not a rule**: G-E3
  /// names FEFO for a Delivery Order and a Distribusi, and §17 is explicit that
  /// consumption does not inherit it. The nurse records the batch they actually took
  /// out of the drawer, and no override reason is asked for when that is not the first
  /// one offered.
  static List<T> usable<T>({
    required List<T> positions,
    required DateTime nowUtc,
    required DateTime? Function(T) expiryDateOf,
    required bool Function(T) hasStockOf,
  }) {
    final consumable = positions
        .where(
          (position) =>
              hasStockOf(position) &&
              isConsumable(expiryDate: expiryDateOf(position), nowUtc: nowUtc),
        )
        .toList();
    return List<T>.unmodifiable(consumable);
  }

  /// The comparator every picker and every in-memory list sorts by.
  ///
  /// Nulls sort last within one item: an item without an expiry date has one position,
  /// so the only way a null and a non-null date meet under the same name is a corrupt
  /// document — and putting the batch-tracked rows first keeps the ordinary case
  /// stable.
  static int compare({
    required String itemNameA,
    required String itemNameB,
    required DateTime? expiryA,
    required DateTime? expiryB,
    required String batchNoA,
    required String batchNoB,
    required String tieBreakerA,
    required String tieBreakerB,
  }) {
    final byItem = itemNameA.compareTo(itemNameB);
    if (byItem != 0) return byItem;
    if (expiryA != null && expiryB != null) {
      final byExpiry = DateOnly.compare(expiryA, expiryB);
      if (byExpiry != 0) return byExpiry;
    } else if (expiryA != null) {
      return -1;
    } else if (expiryB != null) {
      return 1;
    }
    final byBatch = batchNoA.compareTo(batchNoB);
    if (byBatch != 0) return byBatch;
    return tieBreakerA.compareTo(tieBreakerB);
  }
}
