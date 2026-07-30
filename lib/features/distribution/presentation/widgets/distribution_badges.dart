import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/services/distribution_expiry_policy.dart';

/// The small labelled pill every badge on these screens is made of.
///
/// One widget rather than five near-identical `Container`s, because the padding, radius
/// and alpha values were being retyped per badge on the earlier screens and had already
/// drifted apart.
class DistributionPill extends StatelessWidget {
  const DistributionPill({
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

/// Document status chip: `draft` orange (work in progress), `posted` green (final).
class DistributionStatusChip extends StatelessWidget {
  const DistributionStatusChip({super.key, required this.status});

  final DistributionStatus status;

  static Key keyFor(DistributionStatus status) =>
      ValueKey('distributionStatusChip-${status.dbValue}');

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      DistributionStatus.draft => (AppColors.warning, Icons.edit_note),
      DistributionStatus.posted => (
        AppColors.success,
        Icons.check_circle_outline,
      ),
    };

    return DistributionPill(
      pillKey: keyFor(status),
      label: status.label,
      color: color,
      icon: icon,
    );
  }
}

/// Expiry indicator for one batch on a distribution (G-E6).
///
/// Red when expired, orange inside the item's alert window, grey otherwise. The verdict
/// comes from [DistributionExpiryPolicy] rather than being decided here, so the badge
/// and the refusal a use case produces can never disagree about which batch is past its
/// date.
///
/// A red badge is not a warning about something the branch head can push through:
/// expired stock is blocked outright (G-E4) and never appears in the picker at all. It
/// exists for a *posted* document that was distributed while the batch was still valid.
class DistributionExpiryBadge extends StatelessWidget {
  const DistributionExpiryBadge({
    super.key,
    required this.expiryDate,
    required this.expiryAlertDays,
    required this.nowUtc,
  });

  /// Civil date — never timezone converted (T-9).
  final DateTime expiryDate;
  final int expiryAlertDays;

  /// UTC instant used as the reference "now" (T-7).
  final DateTime nowUtc;

  static const Key badgeKey = ValueKey('distributionExpiryBadge');
  static const Key expiredKey = ValueKey('distributionExpiredBadge');
  static const Key nearExpiryKey = ValueKey('distributionNearExpiryBadge');

  @override
  Widget build(BuildContext context) {
    final expired = DistributionExpiryPolicy.isExpired(
      expiryDate: expiryDate,
      nowUtc: nowUtc,
    );
    final nearExpiry = DistributionExpiryPolicy.isNearExpiry(
      expiryDate: expiryDate,
      expiryAlertDays: expiryAlertDays,
      nowUtc: nowUtc,
    );
    final remaining = DistributionExpiryPolicy.remainingDays(
      expiryDate: expiryDate,
      nowUtc: nowUtc,
    );

    final (Color color, String label, Key key) = switch ((
      expired,
      nearExpiry,
    )) {
      (true, _) => (
        AppColors.danger,
        'Kedaluwarsa · lewat ${-remaining} hari',
        expiredKey,
      ),
      (false, true) => (
        AppColors.warning,
        'Segera kedaluwarsa · $remaining hari',
        nearExpiryKey,
      ),
      _ => (
        Colors.blueGrey,
        'ED ${AppDateTimeFormatter.civilDate(expiryDate)}',
        badgeKey,
      ),
    };

    return DistributionPill(pillKey: key, label: label, color: color);
  }
}

/// Marks a line whose batch was chosen outside the FEFO order (G-E3).
///
/// The reason is shown rather than merely the fact, because a badge that says only
/// *"override"* sends the reader looking for the note that explains it.
class DistributionFefoOverrideBadge extends StatelessWidget {
  const DistributionFefoOverrideBadge({super.key, required this.reason});

  final String reason;

  static const Key badgeKey = ValueKey('distributionFefoOverrideBadge');

  @override
  Widget build(BuildContext context) {
    return DistributionPill(
      pillKey: badgeKey,
      label: 'Di luar FEFO · $reason',
      color: AppColors.warning,
      icon: Icons.swap_vert,
    );
  }
}

/// The warning the form shows *before* a younger batch is saved, with the batch that
/// would be passed over named — the one fact that makes it actionable.
class DistributionFefoWarning extends StatelessWidget {
  const DistributionFefoWarning({
    super.key,
    required this.skippedBatchNo,
    required this.skippedExpiryDate,
  });

  final String skippedBatchNo;
  final DateTime skippedExpiryDate;

  static const Key warningKey = ValueKey('distributionFefoWarning');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: warningKey,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Batch $skippedBatchNo (ED '
              '${AppDateTimeFormatter.civilDate(skippedExpiryDate)}) masih '
              'tersisa dan lebih dahulu kedaluwarsa. Pemilihan di luar urutan '
              'FEFO wajib disertai catatan alasan.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
