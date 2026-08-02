import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../enums/app_enums.dart';

/// Small "belum tersinkron" marker (G-Y1). Offline work is normal here, so this
/// is informational rather than a warning.
class SyncStatusTag extends StatelessWidget {
  const SyncStatusTag({
    super.key,
    required this.status,
    this.finalDocument = false,
    this.waitingForOriginalActor = false,
    this.originalActorUnknown = false,
    this.dependencyBlocked = false,
  });

  final SyncStatus status;
  final bool finalDocument;
  final bool waitingForOriginalActor;
  final bool originalActorUnknown;
  final bool dependencyBlocked;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = originalActorUnknown
        ? (
            AppColors.warning,
            Icons.person_off_outlined,
            'Tidak dapat disinkronkan karena akun pembuat data lama tidak dapat ditentukan.',
          )
        : waitingForOriginalActor
        ? (AppColors.warning, Icons.person_outline, 'Menunggu akun pembuat')
        : dependencyBlocked
        ? (AppColors.warning, Icons.account_tree, 'Menunggu data terkait')
        : switch (status) {
            SyncStatus.synced => (
              AppColors.success,
              Icons.cloud_done,
              'Tersinkron',
            ),
            SyncStatus.pending => (
              Colors.blueGrey,
              Icons.cloud_upload,
              finalDocument
                  ? 'Sudah diposting di perangkat ini, menunggu konfirmasi server.'
                  : 'Menunggu sinkron',
            ),
            SyncStatus.conflict => (
              AppColors.warning,
              Icons.sync_problem,
              'Konflik sinkron',
            ),
          };

    return Row(
      mainAxisSize: originalActorUnknown ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: AppSpacing.xs),
        if (originalActorUnknown)
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          )
        else
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
      ],
    );
  }
}
