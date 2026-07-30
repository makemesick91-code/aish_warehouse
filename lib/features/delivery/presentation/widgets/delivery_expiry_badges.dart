import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/delivery_models.dart';
import '../../domain/services/delivery_expiry_policy.dart';

/// Batch, expiry date and remaining shelf life, colour-coded (§4.3 ExpiryBadge,
/// G-E6).
///
/// Red = expired and blocked from shipping outright (G-E4); orange = inside the
/// item's `expiry_alert_days` window and needs an explicit confirmation; grey =
/// safe. The dates are **civil dates** and are printed exactly as stored, with no
/// timezone conversion (T-9); the remaining days are counted from the operational
/// day in GMT+8 (T-3/T-10).
class BatchExpiryBadge extends StatelessWidget {
  const BatchExpiryBadge({
    super.key,
    required this.batchNo,
    required this.expiryDate,
    required this.expiryAlertDays,
    required this.nowUtc,
  });

  /// The same badge for a candidate the picker is offering.
  BatchExpiryBadge.forCandidate({
    Key? key,
    required DeliveryBatchCandidate candidate,
    required int expiryAlertDays,
    required DateTime nowUtc,
  }) : this(
         key: key,
         batchNo: candidate.batchNo,
         expiryDate: candidate.expiryDate,
         expiryAlertDays: expiryAlertDays,
         nowUtc: nowUtc,
       );

  final String batchNo;

  /// Civil date — never timezone converted (T-8/T-9).
  final DateTime expiryDate;

  final int expiryAlertDays;

  /// UTC instant "now" comes from the feature clock, so the badge is deterministic
  /// under an overridden clock in tests (T-7).
  final DateTime nowUtc;

  static const Key expiredKey = ValueKey('deliveryBatchExpired');
  static const Key nearExpiryKey = ValueKey('deliveryBatchNearExpiry');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = DeliveryExpiryPolicy.isExpired(
      expiryDate: expiryDate,
      nowUtc: nowUtc,
    );
    final remaining = DeliveryExpiryPolicy.remainingDays(
      expiryDate: expiryDate,
      nowUtc: nowUtc,
    );
    final near =
        !expired &&
        DeliveryExpiryPolicy.requiresNearExpiryConfirmation(
          expiryDate: expiryDate,
          expiryAlertDays: expiryAlertDays,
          nowUtc: nowUtc,
        );

    final (Color color, String suffix) = expired
        ? (AppColors.danger, 'Kedaluwarsa')
        : near
        ? (AppColors.warning, 'Sisa $remaining hari')
        : (theme.colorScheme.onSurfaceVariant, 'Sisa $remaining hari');

    return Container(
      key: expired
          ? expiredKey
          : near
          ? nearExpiryKey
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$batchNo · ED ${AppDateTimeFormatter.civilDate(expiryDate)} · $suffix',
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// Marks a line whose batch was chosen against the FEFO suggestion (G-E3).
///
/// The reason is shown rather than merely the fact: an audit that records only
/// "overridden" explains nothing, and the Surat Jalan prints the same sentence.
class FefoOverrideBadge extends StatelessWidget {
  const FefoOverrideBadge({super.key, required this.reason});

  final String reason;

  static const Key badgeKey = ValueKey('deliveryFefoOverrideBadge');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_horiz, size: 14, color: AppColors.warning),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              'FEFO diganti · $reason',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a line whose near-expiry shelf life was explicitly accepted (G-E4).
class NearExpiryConfirmedBadge extends StatelessWidget {
  const NearExpiryConfirmedBadge({super.key, this.note});

  final String? note;

  static const Key badgeKey = ValueKey('deliveryNearExpiryConfirmedBadge');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = (note ?? '').trim().isEmpty
        ? 'Dekat kedaluwarsa · dikonfirmasi'
        : 'Dekat kedaluwarsa · dikonfirmasi · ${note!.trim()}';

    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 14, color: AppColors.warning),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
