import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../enums/app_enums.dart';

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
