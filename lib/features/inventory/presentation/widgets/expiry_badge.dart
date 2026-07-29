import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/inventory_models.dart';

/// Expiry indicator per batch (G-E6): red when expired, orange when the
/// remaining shelf life is within `expiry_alert_days`, grey otherwise.
///
/// The remaining days come from the operational date in GMT+8, and the printed
/// date is the civil `expiry_date` shown verbatim — neither depends on the
/// device timezone (T-9/T-10).
class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge({super.key, required this.balance, required this.now});

  final StockBalanceView balance;

  /// UTC instant used as the reference "now".
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final expiry = balance.expiryDate;
    if (expiry == null) return const SizedBox.shrink();

    final daysLeft = balance.daysUntilExpiry(now) ?? 0;
    final (Color color, String label) = switch (daysLeft) {
      < 0 => (AppColors.danger, 'Kedaluwarsa'),
      _ when daysLeft <= balance.expiryAlertDays => (
        AppColors.warning,
        'Segera kedaluwarsa · $daysLeft hari',
      ),
      _ => (Colors.blueGrey, 'ED ${AppDateTimeFormatter.civilDate(expiry)}'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
