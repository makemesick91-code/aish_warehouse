import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';

export '../../../../core/widgets/sync_status_tag.dart';

/// Document status chip with the palette fixed by the specification (§4.3):
/// draft is grey, submitted is blue, reviewed is green.
class OpnameStatusChip extends StatelessWidget {
  const OpnameStatusChip({
    super.key,
    required this.status,
    this.compact = true,
  });

  final StockOpnameStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      StockOpnameStatus.draft => (Colors.blueGrey, Icons.edit_note),
      StockOpnameStatus.submitted => (AppColors.primary, Icons.send),
      StockOpnameStatus.reviewed => (AppColors.success, Icons.lock),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
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
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            status.label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
