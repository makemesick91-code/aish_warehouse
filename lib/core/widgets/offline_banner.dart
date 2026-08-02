import 'package:flutter/material.dart';

enum SyncPresentationState {
  offline,
  pending,
  syncing,
  synced,
  conflict,
  retryableError,
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.state});
  final SyncPresentationState state;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (state) {
      SyncPresentationState.offline => (
        Icons.cloud_off,
        'Offline — perubahan akan disinkronkan',
        Colors.amber,
      ),
      SyncPresentationState.pending => (
        Icons.cloud_upload,
        'Perubahan menunggu sinkronisasi',
        Colors.blueGrey,
      ),
      SyncPresentationState.syncing => (
        Icons.sync,
        'Sedang menyinkronkan…',
        Colors.blue,
      ),
      SyncPresentationState.synced => (
        Icons.cloud_done,
        'Semua perubahan telah dikonfirmasi server',
        Colors.green,
      ),
      SyncPresentationState.conflict => (
        Icons.sync_problem,
        'Ada konflik yang perlu ditinjau',
        Colors.orange,
      ),
      SyncPresentationState.retryableError => (
        Icons.cloud_off,
        'Sinkronisasi tertunda — akan dicoba lagi',
        Colors.redAccent,
      ),
    };
    return Material(
      color: color.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
