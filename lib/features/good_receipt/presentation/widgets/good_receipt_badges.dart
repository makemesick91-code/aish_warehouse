import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/good_receipt_models.dart';
import '../../domain/services/good_receipt_expiry_policy.dart';
import '../../domain/services/good_receipt_reminder_policy.dart';

/// The small labelled pill every badge on these screens is made of.
///
/// One widget rather than six near-identical `Container`s, because the padding, radius
/// and alpha values were being retyped per badge and had already drifted apart on the
/// earlier screens.
class GoodReceiptPill extends StatelessWidget {
  const GoodReceiptPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.pillKey,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Lets a test address the badge without matching on prose.
  final Key? pillKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: pillKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Document status chip: `checking` orange (work in progress), `posted` green (final).
class GoodReceiptStatusChip extends StatelessWidget {
  const GoodReceiptStatusChip({super.key, required this.status});

  final GoodReceiptStatus status;

  static Key keyFor(GoodReceiptStatus status) =>
      ValueKey('goodReceiptStatusChip-${status.dbValue}');

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      GoodReceiptStatus.checking => (
        AppColors.warning,
        Icons.fact_check_outlined,
      ),
      GoodReceiptStatus.posted => (
        AppColors.success,
        Icons.check_circle_outline,
      ),
    };

    return GoodReceiptPill(
      pillKey: keyFor(status),
      label: status.label,
      color: color,
      icon: icon,
    );
  }
}

/// The decision recorded against one position (G-G2).
class GoodReceiptLineStatusChip extends StatelessWidget {
  const GoodReceiptLineStatusChip({super.key, required this.status});

  final GoodReceiptLineStatus status;

  static Key keyFor(GoodReceiptLineStatus status) =>
      ValueKey('goodReceiptLineStatusChip-${status.dbValue}');

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      GoodReceiptLineStatus.pending => (
        Colors.blueGrey,
        Icons.radio_button_unchecked,
      ),
      GoodReceiptLineStatus.checked => (AppColors.success, Icons.check),
      GoodReceiptLineStatus.rejected => (AppColors.danger, Icons.close),
    };

    return GoodReceiptPill(
      pillKey: keyFor(status),
      label: status.label,
      color: color,
      icon: icon,
    );
  }
}

/// G-E5's verdict for one batch, as a badge.
///
/// Reads the verdict from [GoodReceiptExpiryPolicy] rather than deciding it, so the
/// badge and the refusal the use case produces can never disagree about which batch is
/// too close to its date.
class GoodReceiptExpiryBadge extends StatelessWidget {
  const GoodReceiptExpiryBadge({
    super.key,
    required this.expiryDate,
    required this.expiryAlertDays,
    required this.nowUtc,
  });

  final DateTime expiryDate;
  final int expiryAlertDays;
  final DateTime nowUtc;

  static const Key badgeKey = ValueKey('goodReceiptExpiryBadge');

  @override
  Widget build(BuildContext context) {
    final verdict = GoodReceiptExpiryPolicy.verdictFor(
      expiryDate: expiryDate,
      expiryAlertDays: expiryAlertDays,
      nowUtc: nowUtc,
    );
    final remaining = GoodReceiptExpiryPolicy.remainingDays(
      expiryDate: expiryDate,
      nowUtc: nowUtc,
    );

    final (Color color, IconData icon) = switch (verdict) {
      GoodReceiptExpiryVerdict.valid => (
        AppColors.success,
        Icons.event_available,
      ),
      GoodReceiptExpiryVerdict.nearExpiry => (
        AppColors.warning,
        Icons.timelapse,
      ),
      GoodReceiptExpiryVerdict.expired => (AppColors.danger, Icons.event_busy),
    };

    // Days are shown alongside the verdict so the reader can see *how* close it is —
    // "Dekat ED · 5 hari" is actionable in a way "Dekat ED" is not.
    final days = remaining < 0 ? 'lewat ${-remaining} hari' : '$remaining hari';

    return GoodReceiptPill(
      pillKey: badgeKey,
      label: '${verdict.label} · $days',
      color: color,
      icon: icon,
    );
  }
}

/// The 2×24 hour deadline of one outstanding shipment (G-G6).
///
/// The instant is passed in rather than read from a clock, so the badge, the count on
/// the dashboard and the sort order of the list are all judged against the same "now"
/// (T-7). It renders nothing for a shipment comfortably inside its deadline: a badge on
/// every row is a badge nobody reads.
class GoodReceiptDeadlineBadge extends StatelessWidget {
  const GoodReceiptDeadlineBadge({
    super.key,
    required this.shippedAtUtc,
    required this.nowUtc,
    this.showWhenDue = false,
  });

  final DateTime shippedAtUtc;
  final DateTime nowUtc;

  /// Whether to render anything for a shipment that is neither late nor close to it.
  final bool showWhenDue;

  static const Key overdueKey = ValueKey('goodReceiptOverdueBadge');
  static const Key dueSoonKey = ValueKey('goodReceiptDueSoonBadge');
  static const Key dueKey = ValueKey('goodReceiptDueBadge');

  @override
  Widget build(BuildContext context) {
    final stage = GoodReceiptReminderPolicy.stageFor(
      shippedAtUtc: shippedAtUtc,
      nowUtc: nowUtc,
    );
    if (stage == GoodReceiptReminderStage.due && !showWhenDue) {
      return const SizedBox.shrink();
    }

    final (Color color, IconData icon, Key key) = switch (stage) {
      GoodReceiptReminderStage.overdue => (
        AppColors.danger,
        Icons.report_gmailerrorred,
        overdueKey,
      ),
      GoodReceiptReminderStage.dueSoon => (
        AppColors.warning,
        Icons.timer_outlined,
        dueSoonKey,
      ),
      GoodReceiptReminderStage.due => (Colors.blueGrey, Icons.schedule, dueKey),
    };

    final hoursLate = GoodReceiptReminderPolicy.hoursLate(
      shippedAtUtc: shippedAtUtc,
      nowUtc: nowUtc,
    );
    final label = stage.isOverdue
        ? '${stage.label} · $hoursLate jam'
        : stage.label;

    return GoodReceiptPill(
      pillKey: key,
      label: label,
      color: color,
      icon: icon,
    );
  }

  /// `Tenggat 31 Jul 2026, 11:00 GMT+8` — the deadline spelled out, for a header.
  static String deadlineLabel(DateTime shippedAtUtc) =>
      'Tenggat ${AppDateTimeFormatter.dateTimeWithZone(GoodReceiptReminderPolicy.deadlineFor(shippedAtUtc))}';
}

/// Which kind of discrepancy one row is (§17/§33).
class GoodReceiptDiscrepancyBadge extends StatelessWidget {
  const GoodReceiptDiscrepancyBadge({super.key, required this.kind});

  final GoodReceiptDiscrepancyKind kind;

  static Key keyFor(GoodReceiptDiscrepancyKind kind) =>
      ValueKey('goodReceiptDiscrepancyBadge-${kind.name}');

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (kind) {
      GoodReceiptDiscrepancyKind.shortage => (
        AppColors.warning,
        Icons.remove_circle_outline,
      ),
      GoodReceiptDiscrepancyKind.rejectedReturn => (
        AppColors.danger,
        Icons.assignment_return_outlined,
      ),
    };

    return GoodReceiptPill(
      pillKey: keyFor(kind),
      label: kind.label,
      color: color,
      icon: icon,
    );
  }
}

/// `8/12 diperiksa` with a bar behind it (§31).
///
/// The fraction comes from [GoodReceiptProgress] rather than being recomputed here, so
/// the label the branch head reads and the predicate that enables the post button are
/// the same number.
class GoodReceiptProgressBar extends StatelessWidget {
  const GoodReceiptProgressBar({super.key, required this.progress});

  final GoodReceiptProgress progress;

  static const Key progressKey = ValueKey('goodReceiptProgress');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: progressKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${progress.label} diperiksa',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (progress.rejected > 0)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: GoodReceiptPill(
                  label: '${progress.rejected} ditolak',
                  color: AppColors.danger,
                  icon: Icons.close,
                ),
              ),
            if (progress.shortage > 0)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: GoodReceiptPill(
                  label: '${progress.shortage} kurang',
                  color: AppColors.warning,
                  icon: Icons.remove_circle_outline,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(
            // Integer permille divided at the last moment: `Quantity` deliberately
            // offers no `double` conversion and neither does the progress value, so the
            // only place a fraction appears is the widget that needs one.
            value: progress.permille / 1000,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
