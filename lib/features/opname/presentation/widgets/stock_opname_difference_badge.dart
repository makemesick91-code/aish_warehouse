import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/quantity/quantity.dart';

/// The selisih indicator: neutral at zero, green for a surplus, red for a
/// shortage.
///
/// The number comes straight from [Quantity.format], so `-1` reads as `-1` and
/// never as `-0.9999999`. Milli-units never reach the screen (Q-6).
class StockOpnameDifferenceBadge extends StatelessWidget {
  const StockOpnameDifferenceBadge({
    super.key,
    required this.difference,
    required this.unit,
  });

  final Quantity difference;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final (Color color, String prefix, IconData? icon) = switch (difference) {
      final value when value.isZero => (Colors.blueGrey, '', null),
      final value when value.isPositive => (
        AppColors.success,
        '+',
        Icons.arrow_upward,
      ),
      _ => (AppColors.danger, '', Icons.arrow_downward),
    };

    final label = difference.isZero
        ? 'Sesuai'
        : '$prefix${difference.formatWithUnit(unit)}';

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: AppSpacing.xs / 2),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
