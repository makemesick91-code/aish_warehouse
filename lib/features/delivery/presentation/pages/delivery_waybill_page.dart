import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/delivery_models.dart';
import '../providers/delivery_providers.dart';

/// Surat Jalan — the printable handover document (§28).
///
/// Generated **entirely from the local database** (G-L3), so it works offline like
/// everything else. It is a print-friendly page rather than a PDF: the report
/// module and its `export_logs` audit trail are a later milestone, and producing a
/// file now would mean an export nobody records.
///
/// A `preparing` document prints with a `DRAFT — BELUM DIKIRIM` banner, and that is
/// not decoration: a draft has taken nothing out of the warehouse, so a piece of
/// paper that looked like a Surat Jalan could travel with goods that were never
/// posted. Once shipped, the banner is gone and the title is the document.
///
/// Quantities are printed through `Quantity.formatWithUnit`, so `0.5 box` reads as
/// `0.5 box` and a milli-unit never reaches paper (Q-6).
class DeliveryWaybillPage extends ConsumerWidget {
  const DeliveryWaybillPage({
    super.key,
    required this.doId,
    required this.branchScoped,
  });

  final String doId;

  /// `true` when a Kepala Cabang is reading it — the lookup is then pinned to
  /// their branch and to shipped documents.
  final bool branchScoped;

  static const Key draftBannerKey = ValueKey('waybillDraftBanner');
  static const Key titleKey = ValueKey('waybillTitle');
  static const Key tableKey = ValueKey('waybillTable');
  static const Key signaturesKey = ValueKey('waybillSignatures');
  static const Key notFoundKey = ValueKey('waybillNotFound');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waybill = ref.watch(
      deliveryWaybillProvider((doId: doId, branchScoped: branchScoped)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Surat Jalan')),
      body: waybill.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
        data: (model) => model == null
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Card(
                  key: DeliveryWaybillPage.notFoundKey,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text('Surat Jalan tidak ditemukan.'),
                  ),
                ),
              )
            : _WaybillBody(model: model),
      ),
    );
  }
}

class _WaybillBody extends StatelessWidget {
  const _WaybillBody({required this.model});

  final WaybillViewModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = model.summary;
    final order = summary.order;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (model.isDraft)
          Container(
            key: DeliveryWaybillPage.draftBannerKey,
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.warning),
            ),
            child: Text(
              'DRAFT — BELUM DIKIRIM',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'AISH WAREHOUSE',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(letterSpacing: 3),
        ),
        Text(
          key: DeliveryWaybillPage.titleKey,
          model.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Field(label: 'Nomor DO', value: summary.docNumber),
        _Field(label: 'Nomor PR', value: summary.prDocNumber),
        _Field(
          label: 'Tanggal',
          value: AppDateTimeFormatter.dateTimeWithZone(
            order.shippedAt ?? order.createdAt,
          ),
        ),
        _Field(label: 'Warehouse asal', value: model.warehouseName),
        _Field(
          label: 'Cabang tujuan',
          value: '${summary.branchCode} · ${summary.branchName}',
        ),
        _Field(
          label: 'Alamat cabang',
          value: (summary.branchAddress ?? '').isEmpty
              ? '—'
              : summary.branchAddress!,
        ),
        _Field(label: 'Disiapkan oleh', value: summary.preparedByName),
        _Field(label: 'Dikirim oleh', value: summary.shippedByName ?? '—'),
        _Field(label: 'Status', value: order.status.label),
        if ((order.note ?? '').isNotEmpty)
          _Field(label: 'Catatan', value: order.note!),
        const Divider(height: AppSpacing.xl),
        _LineTable(model: model),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Total ${model.lineCount} baris',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final entry in model.detail.shippedByUnit.entries)
          Text(
            'Total ${entry.value.formatWithUnit(entry.key)}',
            style: theme.textTheme.bodySmall,
          ),
        if (model.hasNearExpiryBatch)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '⚠ Terdapat batch yang mendekati kedaluwarsa. Periksa tanggal '
              'kedaluwarsa saat penerimaan.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (model.hasFefoOverride)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '⚠ Terdapat penggantian batch di luar saran FEFO. Alasan tercatat '
              'pada kolom catatan.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        const Divider(height: AppSpacing.xl),
        const _Signatures(),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            SyncStatusTag(status: order.syncStatus),
            const Spacer(),
            Text(
              'Dicetak ${AppDateTimeFormatter.dateTimeWithZone(model.printedAtUtc)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LineTable extends StatelessWidget {
  const _LineTable({required this.model});

  final WaybillViewModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The table scrolls inside its own viewport rather than making the page
    // scroll sideways: a Surat Jalan with long item names on a narrow tablet must
    // stay readable without the header drifting off screen.
    return SingleChildScrollView(
      key: DeliveryWaybillPage.tableKey,
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: AppSpacing.lg,
        headingTextStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: theme.textTheme.bodySmall,
        columns: const [
          DataColumn(label: Text('No')),
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('Barang')),
          DataColumn(label: Text('Batch')),
          DataColumn(label: Text('Expiry Date')),
          DataColumn(label: Text('Qty')),
          DataColumn(label: Text('Satuan')),
          DataColumn(label: Text('Catatan')),
        ],
        rows: [
          for (final (index, line) in model.lines.indexed)
            DataRow(
              key: ValueKey('waybillRow-${line.id}'),
              cells: [
                DataCell(Text('${index + 1}')),
                DataCell(Text(line.sku)),
                DataCell(Text(line.itemName)),
                DataCell(Text(line.batchNo ?? '—')),
                DataCell(
                  Text(
                    line.expiryDate == null
                        // Civil dates are printed verbatim, never converted (T-9).
                        ? '—'
                        : AppDateTimeFormatter.civilDate(line.expiryDate!),
                  ),
                ),
                DataCell(Text(line.shippedQty.format())),
                DataCell(Text(line.unit)),
                DataCell(Text(_noteFor(line))),
              ],
            ),
        ],
      ),
    );
  }

  /// The audit trail that belongs on paper: why a batch was substituted, and that
  /// a short shelf life was accepted (G-E3/G-E4).
  static String _noteFor(DeliveryOrderLine line) {
    final parts = <String>[
      if (line.hasFefoOverride) 'FEFO: ${line.fefoOverrideReason}',
      if (line.nearExpiryConfirmed)
        (line.nearExpiryNote ?? '').trim().isEmpty
            ? 'Dekat ED: dikonfirmasi'
            : 'Dekat ED: ${line.nearExpiryNote!.trim()}',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

class _Signatures extends StatelessWidget {
  const _Signatures();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: DeliveryWaybillPage.signaturesKey,
      children: const [
        Expanded(child: _SignatureSlot(role: 'Petugas Warehouse')),
        Expanded(child: _SignatureSlot(role: 'Pengantar')),
        Expanded(child: _SignatureSlot(role: 'Penerima Cabang')),
      ],
    );
  }
}

class _SignatureSlot extends StatelessWidget {
  const _SignatureSlot({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          role,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          color: theme.colorScheme.outlineVariant,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '(  nama & tanda tangan  )',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
