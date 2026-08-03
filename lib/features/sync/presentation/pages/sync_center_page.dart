import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/sync/realtime_invalidation_coordinator.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/offline_banner.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/sync_center_providers.dart';

class SyncCenterPage extends ConsumerWidget {
  const SyncCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(syncPendingCountProvider).value ?? 0;
    final processing = ref.watch(syncProcessingCountProvider).value ?? 0;
    final conflicts = ref.watch(syncConflictCountProvider).value ?? 0;
    final uploads = ref.watch(syncUploadCountProvider).value ?? 0;
    final waitingActor = ref.watch(syncWaitingForActorCountProvider).value ?? 0;
    final unknownActor = ref.watch(syncUnknownActorCountProvider).value ?? 0;
    final groups =
        ref.watch(syncGroupedPendingProvider).value ??
        const <SyncPendingGroup>[];
    final uploadGroups =
        ref.watch(syncUploadGroupsProvider).value ?? const <SyncUploadGroup>[];
    final lastSuccess = ref.watch(syncLastSuccessProvider).value;
    final lastError = ref.watch(syncLastSafeErrorProvider).value;
    final lastPull = ref.watch(syncLastPullProvider).value;
    final lastPullSuccess = ref.watch(syncLastSuccessfulPullProvider).value;
    final appliedChanges = ref.watch(syncAppliedChangeCountProvider).value ?? 0;
    final tombstonesApplied = ref.watch(syncTombstoneCountProvider).value ?? 0;
    final recoveredConflicts =
        ref.watch(syncResolvedConflictCountProvider).value ?? 0;
    final manualReview = ref.watch(syncManualReviewCountProvider).value ?? 0;
    final actor = ref.watch(currentDomainUserProvider);
    // Only a conflict a person still has to settle is a conflict as far as the
    // banner is concerned. One that recovery already resolved is history, and
    // showing it as an alarm would train users to ignore the alarm.
    final state = manualReview > 0
        ? SyncPresentationState.conflict
        : processing > 0
        ? SyncPresentationState.syncing
        : lastError != null && pending > 0
        ? SyncPresentationState.retryableError
        : pending > 0
        ? SyncPresentationState.pending
        : SyncPresentationState.synced;
    return Scaffold(
      appBar: AppBar(title: const Text('Pusat Sinkronisasi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OfflineBanner(state: state),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CountCard(label: 'Menunggu', value: pending),
              _CountCard(label: 'Diproses', value: processing),
              _CountCard(label: 'Konflik', value: conflicts),
              _CountCard(label: 'File', value: uploads),
              _CountCard(label: 'Akun lain', value: waitingActor),
              _CountCard(label: 'Actor tak diketahui', value: unknownActor),
              _CountCard(label: 'Perubahan masuk', value: appliedChanges),
              _CountCard(label: 'Dihapus server', value: tombstonesApplied),
              _CountCard(
                label: 'Konflik dipulihkan',
                value: recoveredConflicts,
              ),
              _CountCard(label: 'Perlu ditinjau', value: manualReview),
            ],
          ),
          const SizedBox(height: 20),
          ListTile(
            title: const Text('Akun aktif'),
            subtitle: Text(actor?.fullName ?? 'Tidak ada sesi produksi'),
          ),
          const ListTile(
            title: Text('Revisi server minimum'),
            subtitle: Text(SupabaseConfig.expectedSchemaRevision),
          ),
          ListTile(
            title: const Text('Sinkronisasi berhasil terakhir'),
            subtitle: Text(
              lastSuccess == null
                  ? 'Belum ada konfirmasi server pada perangkat ini'
                  : AppDateTimeFormatter.dateTimeWithZone(lastSuccess),
            ),
          ),
          ListTile(
            title: const Text('Kesalahan aman terakhir'),
            subtitle: Text(lastError ?? 'Tidak ada'),
          ),
          ListTile(
            title: const Text('Data server terbaca terakhir'),
            subtitle: Text(
              lastPullSuccess == null
                  ? 'Belum pernah membaca perubahan server'
                  : AppDateTimeFormatter.dateTimeWithZone(lastPullSuccess),
            ),
          ),
          ListTile(
            leading: Icon(_pullIcon(lastPull?.outcome)),
            title: const Text('Status pembacaan server'),
            subtitle: Text(_pullOutcomeLabel(lastPull)),
          ),
          if (waitingActor > 0)
            const ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('Menunggu akun pembuat'),
              subtitle: Text(
                'Operasi tetap tersimpan dan tidak akan dikirim memakai akun lain.',
              ),
            ),
          if (unknownActor > 0)
            const ListTile(
              leading: Icon(Icons.person_off_outlined),
              title: Text('Actor data lama tidak diketahui'),
              subtitle: Text(
                'Tidak dapat disinkronkan karena akun pembuat data lama tidak dapat ditentukan.',
              ),
            ),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Antrean per jenis',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final group in groups)
              ListTile(
                dense: true,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(_aggregateLabel(group.aggregateType)),
                subtitle: Text(_queueStatusLabel(group.status)),
                trailing: Text('${group.count}'),
              ),
          ],
          if (uploadGroups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Upload file privat',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final group in uploadGroups)
              ListTile(
                dense: true,
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(_uploadStatusLabel(group.status)),
                trailing: Text('${group.count}'),
              ),
          ],
          ListTile(
            leading: Icon(
              manualReview > 0
                  ? Icons.report_problem_outlined
                  : Icons.verified_outlined,
            ),
            title: const Text('Konflik'),
            subtitle: Text(
              manualReview > 0
                  ? 'Sebagian perbedaan tidak dapat dipulihkan otomatis dan '
                        'menunggu peninjauan.'
                  : 'Perbedaan dipulihkan otomatis. Data final server selalu '
                        'menang dan nomor dokumennya dipertahankan.',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: actor == null
                ? null
                : () async {
                    // One cycle, not a bare push: a manual tap means "make this
                    // device current", which is push *and* pull. The coordinator
                    // is single-flight, so a repeated tap joins the run already
                    // in progress instead of starting a second one.
                    await ref
                        .read(syncInvalidationCoordinatorProvider)
                        .flush(SyncInvalidationSource.manual);
                    ref.invalidate(syncPendingCountProvider);
                  },
            icon: const Icon(Icons.sync),
            label: const Text('Sinkronkan sekarang'),
          ),
        ],
      ),
    );
  }
}

String _aggregateLabel(String value) => switch (value) {
  'branch' => 'Cabang',
  'room' => 'Ruangan',
  'user' => 'Pengguna',
  'category' => 'Kategori',
  'item' => 'Barang',
  'batch' => 'Batch',
  'stock_location' => 'Lokasi stok',
  'stock_opname' => 'Stok opname',
  'purchase_request' => 'Permintaan barang',
  'delivery_order' => 'Surat jalan',
  'good_receipt' => 'Penerimaan barang',
  'distribution' => 'Distribusi',
  'disposal' => 'Pemusnahan',
  'consumption' => 'Pemakaian',
  'goods_return' => 'Retur barang',
  'import_audit' => 'Audit impor',
  'export_audit' => 'Audit ekspor',
  _ => 'Data aplikasi',
};

/// Describes the last pull without naming an entity, a cursor or a server
/// message. A user needs to know whether their data is current and whether the
/// app will try again; everything beyond that belongs in the local log.
String _pullOutcomeLabel(SyncPullSummary? log) {
  if (log == null) return 'Belum ada pembacaan pada perangkat ini';
  return switch (log.outcome) {
    'applied' =>
      '${log.changeCount} perubahan diterapkan'
          '${log.tombstoneCount > 0 ? ', ${log.tombstoneCount} dihapus server' : ''}',
    'empty' => 'Sudah sesuai dengan server',
    'scope_reset' => 'Akses berubah — data disiapkan ulang',
    'cancelled' => 'Dihentikan saat sesi berakhir',
    'failed' =>
      log.safeErrorMessage ?? 'Gagal membaca server. Akan dicoba lagi.',
    _ => 'Status pembacaan tidak diketahui',
  };
}

IconData _pullIcon(String? outcome) => switch (outcome) {
  'applied' => Icons.cloud_download_outlined,
  'empty' => Icons.cloud_done_outlined,
  'scope_reset' => Icons.restart_alt,
  'cancelled' => Icons.pause_circle_outline,
  'failed' => Icons.cloud_off_outlined,
  _ => Icons.cloud_queue_outlined,
};

String _queueStatusLabel(String value) => switch (value) {
  'processing' => 'Sedang dikirim',
  'blocked' => 'Diblokir dengan aman',
  _ => 'Menunggu sinkronisasi',
};

String _uploadStatusLabel(String value) => switch (value) {
  'queued' => 'Menunggu upload',
  'processing' => 'Sedang diupload',
  'uploaded' => 'Menunggu verifikasi',
  'finalized' => 'Terverifikasi server',
  'blocked' => 'Menunggu data terkait',
  'conflict' => 'Upload bermasalah',
  _ => 'Status file',
};

class _CountCard extends StatelessWidget {
  const _CountCard({required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
