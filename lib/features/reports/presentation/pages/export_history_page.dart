import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/time/date_only.dart';
import '../../domain/models/reporting_models.dart';
import '../providers/reporting_providers.dart';

/// `/reports/export-history` — the Super Admin's audit trail (§48).
///
/// ### It is a trail, not an archive
///
/// The banner says so in as many words, and it matters: the files these rows
/// describe live in an app cache the OS may clear whenever it likes. There is no
/// download button, no "open file" and no regenerate — a regenerate would produce
/// *different* data under the same row's description, which is the one thing an
/// audit row must never be able to mean.
///
/// Read-only throughout: no edit, no delete. The repository offers neither.
class ExportHistoryPage extends ConsumerWidget {
  const ExportHistoryPage({super.key});

  static const Key pageKey = ValueKey('exportHistoryPage');
  static const Key emptyKey = ValueKey('exportHistoryEmpty');
  static const Key listKey = ValueKey('exportHistoryList');

  static const String title = 'Riwayat Ekspor';
  static const String archiveNotice =
      'Riwayat ini adalah jejak audit, bukan arsip file. File laporan disimpan '
      'sementara di perangkat dan dapat dihapus oleh sistem.';
  static const String emptyMessage = 'Belum ada ekspor yang tercatat.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(exportHistoryDetailsProvider);
    final filter = ref.watch(exportHistoryFilterProvider);
    final controller = ref.read(exportHistoryFilterProvider.notifier);

    return Scaffold(
      key: pageKey,
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            color: AppColors.primary.withValues(alpha: 0.06),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(archiveNotice)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FilterCard(filter: filter, controller: controller),
          const SizedBox(height: AppSpacing.md),
          details.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Text(describeReportFailure(error)),
            data: (rows) => rows.isEmpty
                ? const Padding(
                    key: emptyKey,
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: Text(emptyMessage)),
                  )
                : Column(
                    key: listKey,
                    children: [
                      for (final detail in rows) _LogTile(detail: detail),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterCard extends ConsumerWidget {
  const _FilterCard({required this.filter, required this.controller});

  final ExportHistoryFilter filter;
  final ExportHistoryFilterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(reportBranchOptionsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: filter.searchText,
              decoration: const InputDecoration(
                labelText: 'Cari nama file / laporan',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: controller.setSearchText,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ReportType>(
              isExpanded: true,
              initialValue: filter.reportType,
              decoration: const InputDecoration(labelText: 'Jenis Laporan'),
              items: [
                const DropdownMenuItem(child: Text('Semua')),
                for (final type in ReportType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: controller.setReportType,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ReportFormat>(
              isExpanded: true,
              initialValue: filter.format,
              decoration: const InputDecoration(labelText: 'Format File'),
              items: [
                const DropdownMenuItem(child: Text('Semua')),
                for (final format in ReportFormat.values)
                  DropdownMenuItem(value: format, child: Text(format.label)),
              ],
              onChanged: controller.setFormat,
            ),
            const SizedBox(height: AppSpacing.sm),
            branches.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const SizedBox.shrink(),
              data: (options) => DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: filter.branchId,
                decoration: const InputDecoration(labelText: 'Cabang'),
                items: [
                  const DropdownMenuItem(child: Text('Semua')),
                  for (final option in options)
                    DropdownMenuItem(
                      value: option.id,
                      child: Text('${option.code} · ${option.name}'),
                    ),
                ],
                onChanged: controller.setBranch,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    filter.onOperationalDate == null
                        ? 'Semua tanggal'
                        : DateOnly.formatIso(filter.onOperationalDate!),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: filter.onOperationalDate ?? DateTime.now(),
                      firstDate: DateTime.utc(2020),
                      lastDate: DateTime.utc(2100),
                    );
                    if (picked != null) {
                      controller.setDate(DateOnly.from(picked));
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: const Text('Pilih tanggal'),
                ),
                if (filter.onOperationalDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => controller.setDate(null),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.detail});

  final ExportLogDetail detail;

  @override
  Widget build(BuildContext context) {
    final log = detail.log;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          log.format == ReportFormat.xlsx
              ? Icons.table_chart_outlined
              : Icons.picture_as_pdf_outlined,
        ),
        title: Text(log.fileName),
        subtitle: Text(
          '${log.reportType.label} · '
          '${AppDateTimeFormatter.dateTimeWithZone(log.exportedAtUtc)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          _Row(label: 'Format', value: log.format.label),
          _Row(label: 'Cakupan', value: log.scopeType.label),
          _Row(label: 'Cabang', value: detail.branchLabel),
          _Row(label: 'Lokasi', value: detail.locationLabel),
          _Row(label: 'Kategori', value: detail.categoryLabel),
          _Row(label: 'Barang', value: detail.itemLabel),
          _Row(
            label: 'Periode',
            value: log.isAsOf
                ? DateOnly.formatIso(log.periodEnd)
                : '${DateOnly.formatIso(log.periodStart)} – '
                      '${DateOnly.formatIso(log.periodEnd)}',
          ),
          _Row(label: 'Diekspor oleh', value: detail.exportedByLabel),
          _Row(label: 'Jumlah baris', value: '${log.rowCount}'),
          _Row(
            label: 'Data per',
            value: AppDateTimeFormatter.dateTimeWithZone(log.dataCutoffAtUtc),
          ),
          _Row(label: 'Status sinkronisasi data', value: log.syncSummary),
          _Row(label: 'Sync log', value: _syncLabel(log.syncStatus)),
        ],
      ),
    );
  }

  static String _syncLabel(SyncStatus status) => switch (status) {
    SyncStatus.synced => 'Tersinkron',
    SyncStatus.pending => 'Pending',
    SyncStatus.conflict => 'Konflik',
  };
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
