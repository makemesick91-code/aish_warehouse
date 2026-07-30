import '../models/good_receipt_models.dart';
import 'good_receipt_reminder_policy.dart';

/// Turns the outstanding-shipment queue into the reminder rows a dashboard and a
/// list render (G-G6).
///
/// A separate builder from [GoodReceiptReminderPolicy] because the policy answers
/// questions about *one* deadline and this assembles and orders a list. Keeping them
/// apart also keeps the policy free of every model in the feature, which is what lets
/// the models themselves ask it about a deadline without an import cycle.
///
/// The clock is a parameter, never read here: the badge on a row, the count on the
/// card and the sort order all have to be resolved against the same instant, or a
/// list would put an "overdue" row below a "due soon" one because the two were judged
/// a microsecond apart (T-7).
abstract final class GoodReceiptReminderBuilder {
  /// One reminder per outstanding shipment, ordered the way §30 asks: overdue first,
  /// then due soon, then the oldest shipment.
  ///
  /// Every row of [awaiting] qualifies by construction — the query behind it returns
  /// `shipped` Delivery Orders only, so a posted receipt has already taken its
  /// shipment out (posting moves it to `received`). There is deliberately no filter
  /// here that could disagree with that query.
  static List<GoodReceiptReminder> build({
    required Iterable<GoodReceiptAwaitingDelivery> awaiting,
    required DateTime nowUtc,
  }) {
    final reminders = awaiting
        .map((row) => _reminderOf(row, nowUtc))
        .toList(growable: false);
    return sorted(reminders);
  }

  /// Only the ones a badge should shout about — overdue, then due soon.
  ///
  /// What a dashboard card counts. A shipment comfortably inside its deadline is
  /// ordinary work rather than a reminder, and counting it would make the card a
  /// second copy of the list's length.
  static List<GoodReceiptReminder> urgentOnly(
    Iterable<GoodReceiptReminder> reminders,
  ) => sorted(
    reminders
        .where((reminder) => reminder.isOverdue || reminder.isDueSoon)
        .toList(growable: false),
  );

  /// Overdue first, then due soon, then oldest shipment — and `doId` last so two rows
  /// shipped in the same instant do not swap places between rebuilds.
  static List<GoodReceiptReminder> sorted(List<GoodReceiptReminder> reminders) {
    final ordered = [...reminders];
    ordered.sort((a, b) {
      final byStage = a.stage.priority.compareTo(b.stage.priority);
      if (byStage != 0) return byStage;
      final byShipped = a.shippedAtUtc.compareTo(b.shippedAtUtc);
      if (byShipped != 0) return byShipped;
      return a.doId.compareTo(b.doId);
    });
    return List<GoodReceiptReminder>.unmodifiable(ordered);
  }

  static GoodReceiptReminder _reminderOf(
    GoodReceiptAwaitingDelivery row,
    DateTime nowUtc,
  ) => GoodReceiptReminder(
    doId: row.doId,
    doDocNumber: row.doDocNumber,
    prDocNumber: row.prDocNumber,
    branchId: row.branchId,
    branchCode: row.branchCode,
    branchName: row.branchName,
    shippedAtUtc: row.shippedAtUtc,
    deadlineUtc: GoodReceiptReminderPolicy.deadlineFor(row.shippedAtUtc),
    stage: GoodReceiptReminderPolicy.stageFor(
      shippedAtUtc: row.shippedAtUtc,
      nowUtc: nowUtc,
    ),
    hoursLate: GoodReceiptReminderPolicy.hoursLate(
      shippedAtUtc: row.shippedAtUtc,
      nowUtc: nowUtc,
    ),
    lineCount: row.lineCount,
    decidedCount: row.decidedCount,
    receiptId: row.receiptId,
    receiptStatus: row.receiptStatus,
  );
}
