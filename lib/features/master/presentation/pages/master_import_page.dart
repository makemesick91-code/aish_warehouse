/// `/imports` — template download, upload, preview, commit, history (§42).
///
/// ### Commit is disabled *structurally*, not cosmetically
///
/// The button's `onPressed` is `null` unless [MasterImportState.canCommit], which
/// asks the session — total > 0, zero failures, still `validated`, nothing in
/// flight. There is no path through this widget that calls the commit while a row
/// is in error, and the use case refuses one anyway (G-M3).
///
/// ### The preview list is lazy
///
/// `ListView.builder` over the filtered rows, so a 10,000-row workbook builds the
/// handful of rows on screen rather than ten thousand widgets (§42, §58). The
/// filter chips and the search box narrow the list rather than paginating it,
/// because an operator looking for *the failures* wants all of them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/import_models.dart';
import '../../domain/models/master_admin_models.dart';
import '../providers/master_admin_providers.dart';
import '../providers/master_import_controller.dart';

class MasterImportPage extends ConsumerWidget {
  const MasterImportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Template Import'),
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('import-tab-new'), text: 'Import Baru'),
              Tab(key: Key('import-tab-preview'), text: 'Preview Aktif'),
              Tab(key: Key('import-tab-history'), text: 'Riwayat'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_NewImportTab(), _PreviewTab(), _HistoryTab()],
        ),
      ),
    );
  }
}

// --- tab 1: pick an entity, download a template, upload a file ------------------

class _NewImportTab extends ConsumerWidget {
  const _NewImportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(masterImportControllerProvider);
    final controller = ref.read(masterImportControllerProvider.notifier);
    // Watched, not read: the acting user is resolved asynchronously, and a
    // button that fired before it landed would silently do nothing. Watching it
    // here both starts the resolution when the tab builds and keeps the controls
    // disabled until there is an actor to attribute the import to (§38).
    final actorId = ref.watch(masterAdminActorIdProvider);
    final isReady = !state.isBusy && actorId != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '1. Pilih entitas',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entity in MasterEntityType.values)
              ChoiceChip(
                key: Key('import-entity-${entity.dbValue}'),
                label: Text(entity.label),
                selected: state.entity == entity,
                onSelected: isReady
                    ? (_) => controller.selectEntity(entity)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '2. Unduh template',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Template berisi header, satu baris contoh, dan sheet petunjuk dengan '
          'daftar nilai yang valid. Kunci identitas ${state.entity.label}: '
          '${state.entity.naturalKeyLabel}.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('import-download-template'),
          onPressed: isReady ? controller.downloadTemplate : null,
          icon: const Icon(Icons.download_outlined),
          label: Text('Unduh Template ${state.entity.label}'),
        ),
        const SizedBox(height: 24),
        Text(
          '3. Unggah file .xlsx',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('import-pick-file'),
          onPressed: isReady ? controller.pickAndValidate : null,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Pilih File & Validasi'),
        ),
        if (state.pickedFileName != null) ...[
          const SizedBox(height: 12),
          Text(
            key: const Key('import-picked-file'),
            '${state.pickedFileName} · '
            '${_formatBytes(state.pickedSizeBytes ?? 0)}',
          ),
        ],
        if (state.isBusy) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  key: const Key('import-busy'),
                  state.busyLabel ?? 'Memproses…',
                ),
              ),
            ],
          ),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 16),
          _MessageCard(
            key: const Key('import-error'),
            message: state.errorMessage!,
            isError: true,
            onDismiss: controller.dismissMessages,
          ),
        ],
        if (state.infoMessage != null) ...[
          const SizedBox(height: 16),
          _MessageCard(
            key: const Key('import-info'),
            message: state.infoMessage!,
            isError: false,
            onDismiss: controller.dismissMessages,
          ),
        ],
      ],
    );
  }
}

// --- tab 2: the preview -----------------------------------------------------------

class _PreviewTab extends ConsumerWidget {
  const _PreviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(masterImportControllerProvider);
    final controller = ref.read(masterImportControllerProvider.notifier);
    // Same reason as the first tab: the commit and discard buttons must not be
    // live before the actor is known.
    final actorId = ref.watch(masterAdminActorIdProvider);
    final session = state.session;

    if (session == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            key: Key('import-no-preview'),
            'Belum ada pratinjau. Unggah file pada tab "Import Baru".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final summary = session.summary;
    final rows = state.visibleRows;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const Key('import-preview-file'),
                '${session.fileName} · ${session.entity.label} · '
                '${session.templateVersion}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _SummaryChip(
                    key: const Key('import-summary-total'),
                    label: 'Total',
                    value: summary.totalRows,
                  ),
                  _SummaryChip(
                    key: const Key('import-summary-insert'),
                    label: 'Tambah',
                    value: summary.insertedRows,
                  ),
                  _SummaryChip(
                    key: const Key('import-summary-update'),
                    label: 'Perbarui',
                    value: summary.updatedRows,
                  ),
                  _SummaryChip(
                    key: const Key('import-summary-failed'),
                    label: 'Gagal',
                    value: summary.failedRows,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.isFinalised)
                const Text(
                  key: Key('import-finalised'),
                  'Impor ini sudah diterapkan. Pratinjau bersifat hanya-baca.',
                )
              else if (summary.hasErrors)
                const Text(
                  key: Key('import-has-errors'),
                  'Impor tidak dapat dijalankan selama masih ada baris gagal. '
                  'Perbaiki file lalu unggah ulang, atau batalkan impor ini.',
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('import-commit'),
                      // Structurally disabled — see the library note.
                      onPressed: state.canCommit && actorId != null
                          ? () => _confirmCommit(context, ref)
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Commit Impor'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    key: const Key('import-discard'),
                    onPressed: state.canDiscard && actorId != null
                        ? () => _confirmDiscard(context, ref)
                        : null,
                    child: const Text('Batalkan'),
                  ),
                ],
              ),
              if (state.isFinalised) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('import-start-over'),
                  onPressed: controller.startOver,
                  child: const Text('Mulai Impor Baru'),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            key: const Key('import-row-search'),
            onChanged: controller.setRowQuery,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Cari nomor baris atau kunci…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (final filter in ImportPreviewRowFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('import-row-filter-${filter.name}'),
                    label: Text(filter.label),
                    selected: state.rowFilter == filter,
                    onSelected: (_) => controller.setRowFilter(filter),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // Lazy: only the rows on screen are built (§42, §58).
          child: ListView.builder(
            key: const Key('import-preview-rows'),
            itemCount: rows.length,
            itemBuilder: (context, index) => _PreviewRowTile(row: rows[index]),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmCommit(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terapkan Impor?'),
        content: const Text(
          'Semua perubahan akan diterapkan dalam satu transaksi.\n'
          'Tidak ada data yang dihapus.\n'
          'Data baru dan berubah akan berstatus pending untuk sinkronisasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('import-commit-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(masterImportControllerProvider.notifier).commit();
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan Impor?'),
        content: const Text(
          'Tidak ada data master yang berubah. Catatan impor dan file '
          'sumbernya tetap tersimpan untuk audit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('import-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Batalkan Impor'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(masterImportControllerProvider.notifier).discard();
  }
}

class _PreviewRowTile extends StatelessWidget {
  const _PreviewRowTile({required this.row});

  final ImportRowPreview row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: Key('import-row-${row.rowNumber}'),
      leading: Icon(
        row.isValid ? Icons.check_circle_outline : Icons.error_outline,
        color: row.isValid
            ? theme.colorScheme.primary
            : theme.colorScheme.error,
      ),
      title: Text('Baris ${row.rowNumber} · ${row.naturalKeyDisplay}'),
      subtitle: Text(
        row.isValid
            ? row.action.label
            : '${row.errors.length} masalah'
                  '${row.warnings.isEmpty ? '' : ' · ${row.warnings.length} peringatan'}',
      ),
      children: [
        for (final issue in row.issues)
          ListTile(
            dense: true,
            leading: Icon(
              issue.isError ? Icons.close : Icons.info_outline,
              size: 18,
              color: issue.isError ? theme.colorScheme.error : null,
            ),
            title: Text(issue.message),
            subtitle: issue.column.isEmpty ? null : Text(issue.column),
          ),
        for (final entry in row.normalizedValues.entries)
          ListTile(
            dense: true,
            title: Text(entry.key),
            subtitle: Text(entry.value.isEmpty ? '—' : entry.value),
          ),
      ],
    );
  }
}

// --- tab 3: history ------------------------------------------------------------------

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(importHistoryFilterProvider);
    final history = ref.watch(importHistoryProvider(filter));

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (final status in ImportStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: Key('import-history-status-${status.dbValue}'),
                    label: Text(status.label),
                    selected: filter.status == status,
                    onSelected: (selected) => ref
                        .read(importHistoryFilterProvider.notifier)
                        .setStatus(selected ? status : null),
                  ),
                ),
              for (final entity in MasterEntityType.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: Key('import-history-entity-${entity.dbValue}'),
                    label: Text(entity.label),
                    selected: filter.entity == entity,
                    onSelected: (selected) => ref
                        .read(importHistoryFilterProvider.notifier)
                        .setEntity(selected ? entity : null),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const Center(child: Text('Riwayat impor gagal dimuat.')),
            data: (logs) => logs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        key: Key('import-history-empty'),
                        'Belum ada riwayat impor.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: logs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return ListTile(
                        key: Key('import-history-${log.id}'),
                        title: Text('${log.entity.label} · ${log.fileName}'),
                        subtitle: Text(
                          '${log.status.label} · ${log.totalRows} baris '
                          '(${log.insertedRows} tambah, ${log.updatedRows} '
                          'perbarui, ${log.failedRows} gagal)\n'
                          '${AppDateTimeFormatter.dateTimeWithZone(log.createdAtUtc)}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.go('${AppRoutes.imports}/${log.id}'),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

// --- shared bits -----------------------------------------------------------------------

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({super.key, required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label: $value'));
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    super.key,
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: isError ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
              tooltip: 'Tutup',
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
