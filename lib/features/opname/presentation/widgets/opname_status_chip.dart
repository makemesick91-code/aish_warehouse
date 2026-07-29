import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';

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

/// Small "belum tersinkron" marker (G-Y1). Offline work is normal here, so this
/// is informational rather than a warning.
class SyncStatusTag extends StatelessWidget {
  const SyncStatusTag({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (status) {
      SyncStatus.synced => (AppColors.success, Icons.cloud_done, 'Tersinkron'),
      SyncStatus.pending => (
        Colors.blueGrey,
        Icons.cloud_upload,
        'Menunggu sinkron',
      ),
      SyncStatus.conflict => (
        AppColors.warning,
        Icons.sync_problem,
        'Konflik sinkron',
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
