/// How urgent an outstanding Good Receipt is (G-G6).
enum GoodReceiptReminderStage {
  /// Inside the deadline with room to spare.
  due,

  /// Inside the deadline, but less than [GoodReceiptReminderPolicy.dueSoonWindow]
  /// of it left.
  dueSoon,

  /// Past the deadline.
  overdue;

  bool get isOverdue => this == overdue;

  bool get isDueSoon => this == dueSoon;

  /// Indonesian badge wording (§30).
  String get label => switch (this) {
    due => 'Dalam tenggat',
    dueSoon => 'Mendekati tenggat',
    overdue => 'Melewati tenggat',
  };

  /// Sort weight, overdue first (§30: overdue → due soon → newest).
  int get priority => switch (this) {
    overdue => 0,
    dueSoon => 1,
    due => 2,
  };
}

/// G-G6 — *"GR harus di-posting maksimal 2×24 jam"*, in one place.
///
/// ### The deadline anchor, stated explicitly
///
/// The rule is worded *"2×24 jam setelah DO diterima"*, and the schema has no
/// column for the moment goods physically arrived at the branch: spec §2.3 gives
/// `delivery_orders` a `shipped_at` and nothing else, and `good_receipts` records
/// only when the checklist was *posted*. So this milestone adopts an explicit
/// operational assumption:
///
/// ```
/// deadline = delivery_orders.shipped_at + 48 hours
/// ```
///
/// `shipped_at` stands in as a **proxy** for arrival until the workflow gains a
/// real arrival event. The substitution is conservative in the right direction — it
/// can only make the deadline earlier than the letter of the rule, never later — so
/// a branch is never told it has more time than it does. When an arrival timestamp
/// exists, only [deadlineFor] changes; nothing that calls it has to.
///
/// ### Why this is a policy and not a widget
///
/// Every method takes the clock as a parameter and none reads one. That is what
/// makes the badge on a list row, the count on the dashboard and the sorting of the
/// queue agree: they are all handed the same injected instant (T-7). A widget that
/// called `DateTime.now()` for itself would disagree with the number beside it as
/// soon as a test froze time — or as soon as a real day rolled over mid-render.
///
/// There is deliberately **no** OS notification and no background task here. G-G6
/// asks for a reminder, and an in-app badge is a reminder; adding a notification
/// package would be a platform dependency this milestone does not need and cannot
/// test.
abstract final class GoodReceiptReminderPolicy {
  /// 2×24 hours.
  static const Duration deadline = Duration(hours: 48);

  /// How long before the deadline a shipment starts being flagged.
  ///
  /// Half a working day: long enough that a branch head who opens the app in the
  /// morning still has time to act, short enough that the badge means something.
  static const Duration dueSoonWindow = Duration(hours: 12);

  /// The instant a shipment's receipt becomes late.
  static DateTime deadlineFor(DateTime shippedAtUtc) =>
      shippedAtUtc.toUtc().add(deadline);

  /// Whether the deadline has passed.
  ///
  /// Exactly 48 hours is **not** late: the rule is "within 2×24 hours", so the
  /// boundary instant is still inside it and only a microsecond beyond it is out.
  /// Comparing the other way round would report every shipment late one instant
  /// early, which is the kind of off-by-one that erodes trust in the badge.
  static bool isOverdue({
    required DateTime shippedAtUtc,
    required DateTime nowUtc,
  }) => nowUtc.toUtc().isAfter(deadlineFor(shippedAtUtc));

  /// How much time is left; negative once the deadline has passed.
  static Duration remaining({
    required DateTime shippedAtUtc,
    required DateTime nowUtc,
  }) => deadlineFor(shippedAtUtc).difference(nowUtc.toUtc());

  /// Whole hours past the deadline; `0` while it has not passed.
  ///
  /// Truncated rather than rounded, so "3 jam terlambat" means at least three full
  /// hours have gone by and never flatters the record.
  static int hoursLate({
    required DateTime shippedAtUtc,
    required DateTime nowUtc,
  }) {
    final overdueBy = -remaining(
      shippedAtUtc: shippedAtUtc,
      nowUtc: nowUtc,
    ).inHours;
    return overdueBy > 0 ? overdueBy : 0;
  }

  /// Whole hours the shipment has been in the branch's hands.
  static int ageInHours({
    required DateTime shippedAtUtc,
    required DateTime nowUtc,
  }) => nowUtc.toUtc().difference(shippedAtUtc.toUtc()).inHours;

  /// Which of the three stages a shipment is in.
  static GoodReceiptReminderStage stageFor({
    required DateTime shippedAtUtc,
    required DateTime nowUtc,
  }) {
    if (isOverdue(shippedAtUtc: shippedAtUtc, nowUtc: nowUtc)) {
      return GoodReceiptReminderStage.overdue;
    }
    final left = remaining(shippedAtUtc: shippedAtUtc, nowUtc: nowUtc);
    return left <= dueSoonWindow
        ? GoodReceiptReminderStage.dueSoon
        : GoodReceiptReminderStage.due;
  }
}
