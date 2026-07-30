import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import 'good_receipt_line_decision_policy.dart';

/// The three answers a batch can give when the goods are on the counter.
enum GoodReceiptExpiryVerdict {
  /// Acceptable — the position may be `checked`.
  valid,

  /// Less than `items.expiry_alert_days` of shelf life left. Must be rejected
  /// (G-E5).
  nearExpiry,

  /// Past its expiry date. Must be rejected (G-E5).
  expired;

  /// G-E5 — whether the position may not be accepted at all.
  bool get mustBeRejected => this != valid;

  bool get isValid => this == valid;

  bool get isNearExpiry => this == nearExpiry;

  bool get isExpired => this == expired;

  /// Badge wording for the checklist (§4.2).
  String get label => switch (this) {
    valid => 'ED aman',
    nearExpiry => 'Dekat ED',
    expired => 'Kedaluwarsa',
  };
}

/// G-E5 — what expiry means when a branch checks goods in, in one place.
///
/// The rule here is **stricter than the shipment's** (G-E4), and the difference is
/// the whole reason this is a separate policy rather than a reused one:
///
/// * On a Delivery Order, a batch inside its alert window may still be sent after
///   the warehouse officer confirms it explicitly. The goods are in the central
///   warehouse and somebody is deciding to move them anyway.
/// * On a Good Receipt there is **no confirmation that accepts it**. Spec §3.11
///   says goods that are expired *or too close to their expiry date* are refused
///   with `kedaluwarsa` and go on the return list. So both verdicts force
///   `rejected`, and no note, tick or override can carry either into the branch's
///   stock.
///
/// Every date question is answered in **operational time** (GMT+8), never in the
/// device's zone (T-3/T-4). A batch is usable for the whole of its expiry day and
/// is expired from the next day onwards (T-10):
///
/// | `expiry_date` | operational date | verdict  |
/// |---------------|------------------|----------|
/// | 2026-07-30    | 2026-07-30       | valid    |
/// | 2026-07-30    | 2026-07-31       | expired  |
///
/// `expiry_date` itself is a **civil date** and is never timezone converted (T-9);
/// what gets converted is "now", into the operational day it falls on. The boundary
/// that matters in practice is 16:00 UTC: at 15:59 the operational day is still
/// yesterday's, at 16:00 it has rolled over, and a batch expiring "today" flips
/// from valid to expired across that single minute.
abstract final class GoodReceiptExpiryPolicy {
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

  /// Whether the batch is inside its alert window but not yet expired.
  ///
  /// Strictly less than, because the specification is worded *"sisa umur <
  /// `expiry_alert_days`"*. Equality is therefore **not** inside the window: 30 days
  /// left against a 30-day threshold may be accepted, 29 may not. An off-by-one here
  /// would either refuse deliveries the branch should take or let a nearly expired
  /// batch onto the shelf unremarked.
  ///
  /// An already-expired batch answers `false` — it is the stricter case and
  /// [isExpired] reports it. Keeping the two apart is what lets a badge say
  /// *kedaluwarsa* rather than *dekat ED*, and what lets the two failures name
  /// different remedies.
  static bool isNearExpiry({
    required DateTime expiryDate,
    required int expiryAlertDays,
    required DateTime nowUtc,
  }) {
    if (isExpired(expiryDate: expiryDate, nowUtc: nowUtc)) return false;
    return remainingDays(expiryDate: expiryDate, nowUtc: nowUtc) <
        expiryAlertDays;
  }

  /// The full verdict for one batch.
  static GoodReceiptExpiryVerdict verdictFor({
    required DateTime expiryDate,
    required int expiryAlertDays,
    required DateTime nowUtc,
  }) {
    if (isExpired(expiryDate: expiryDate, nowUtc: nowUtc)) {
      return GoodReceiptExpiryVerdict.expired;
    }
    if (isNearExpiry(
      expiryDate: expiryDate,
      expiryAlertDays: expiryAlertDays,
      nowUtc: nowUtc,
    )) {
      return GoodReceiptExpiryVerdict.nearExpiry;
    }
    return GoodReceiptExpiryVerdict.valid;
  }

  /// G-E5 — whether the position must be refused rather than accepted.
  ///
  /// An item without expiry has no batch and therefore no verdict at all: passing
  /// `null` answers `false`, which is what keeps the policy from being invoked on a
  /// box of masks (G-E2).
  static bool mustBeRejected({
    required DateTime? expiryDate,
    required int expiryAlertDays,
    required DateTime nowUtc,
  }) {
    if (expiryDate == null) return false;
    return verdictFor(
      expiryDate: expiryDate,
      expiryAlertDays: expiryAlertDays,
      nowUtc: nowUtc,
    ).mustBeRejected;
  }

  /// The reason preset G-E5 forces on a batch that may not be accepted.
  ///
  /// Named here rather than typed at the two call sites, so the sheet's default and
  /// the message the use case produces cannot drift apart.
  static GoodReceiptRejectReasonPreset get forcedRejectPreset =>
      GoodReceiptRejectReasonPreset.expiryPreset;
}
