import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/import_models.dart';
import '../providers/master_admin_providers.dart';

/// `/imports/{id}` — one audit row in full (§36).
///
/// ### What it shows, and the one thing it never does
///
/// Entity, original filename, template version, file size, a **shortened**
/// SHA-256, the time in operational GMT+8, the actor, the status, the counts, the
/// errors and the sync status — and the sentence *"File sumber tersimpan untuk
/// audit."*
///
/// It never renders `stored_file_path`. The domain's [ImportLog] does not even
/// carry it: only the commit reads the path, straight from the database, so no
/// screen can print one by accident (§11, §36).
///
/// ### Read-only, permanently
///
/// There is no edit control and no delete control, because there is no writer
/// behind either. An import log moves `validated → committed` or
/// `validated → discarded` and stops (§3.4).
///
/// An id that does not exist and an id the actor may not read produce the same
/// screen — telling them apart is how a detail route becomes a way to enumerate
/// which imports are real (§37).
class ImportLogDetailPage extends ConsumerWidget {
  const ImportLogDetailPage({super.key, required this.importId});

  final String importId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(importLogDetailProvider(importId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Import')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Detail gagal dimuat.')),
        data: (value) => value == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    key: Key('import-detail-missing'),
                    'Data impor tidak ditemukan.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _DetailBody(detail: value),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final ImportLogDetail detail;

  @override
  Widget build(BuildContext context) {
    final log = detail.log;
    final issues = log.issues;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(log.fileName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            Chip(
              key: Key('import-detail-status-${log.status.dbValue}'),
              label: Text(log.status.label),
            ),
            const SizedBox(width: 8),
            SyncStatusTag(status: log.syncStatus),
          ],
        ),
        const SizedBox(height: 16),
        for (final entry in <({String label, String value})>[
          (label: 'Entitas', value: log.entity.label),
          (label: 'Versi template', value: log.templateVersion),
          (label: 'Ukuran file', value: _formatBytes(log.fileSizeBytes)),
          // Shortened: enough for a human to compare two rows, not enough to be
          // mistaken for the file itself.
          (label: 'SHA-256', value: '${log.shortHash}…'),
          (
            label: 'Waktu',
            value: AppDateTimeFormatter.dateTimeWithZone(log.createdAtUtc),
          ),
          (
            label: 'Oleh',
            value: '${detail.importedByName} (${detail.importedByEmail})',
          ),
          (label: 'Total baris', value: '${log.totalRows}'),
          (label: 'Ditambahkan', value: '${log.insertedRows}'),
          (label: 'Diperbarui', value: '${log.updatedRows}'),
          (label: 'Gagal', value: '${log.failedRows}'),
        ])
          ListTile(
            dense: true,
            title: Text(entry.label),
            subtitle: Text(
              key: Key('import-detail-${entry.label.toLowerCase()}'),
              entry.value,
            ),
          ),
        const Divider(),
        const ListTile(
          key: Key('import-detail-source-notice'),
          leading: Icon(Icons.lock_outline),
          title: Text(ImportLogDetail.sourceFileNotice),
          subtitle: Text(
            'Lokasi penyimpanan bersifat internal dan tidak ditampilkan.',
          ),
        ),
        if (issues.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Rincian kesalahan (${issues.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final issue in issues)
            ListTile(
              key: Key('import-detail-issue-${issue.rowNumber}-${issue.code}'),
              dense: true,
              leading: const Icon(Icons.error_outline, size: 18),
              title: Text(issue.message),
              subtitle: Text(
                'Baris ${issue.rowNumber}'
                '${issue.column.isEmpty ? '' : ' · ${issue.column}'}',
              ),
            ),
        ],
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
