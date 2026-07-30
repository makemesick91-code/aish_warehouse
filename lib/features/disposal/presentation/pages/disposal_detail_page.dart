import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/disposal_models.dart';
import '../providers/disposal_providers.dart';
import '../widgets/disposal_badges.dart';

/// The read-only Pemusnahan detail (§32).
///
/// What is *not* on this screen is the specification: no edit, no remove, no
/// re-post, no un-post, no approval. `posted` has no outgoing transition (G-S2), and
/// there is no writer anywhere that could express one — so the absence of a button
/// here is a description of the domain rather than a UI decision.
///
/// It renders a draft too, as a preview. Both routes lead here for a posted
/// document; a draft ordinarily opens in the form, and this is what a deep link to
/// the detail route shows.
///
/// Every reference is read through the scoped detail provider, whose joins filter
/// neither `is_active` nor `deleted_at` — so a document whose source room was
/// retired, whose product was withdrawn or whose batch was archived stays readable,
/// with a badge saying so rather than a row that quietly disappears (§34).
class DisposalDetailPage extends ConsumerWidget {
  const DisposalDetailPage({super.key, required this.disposalId});

  final String disposalId;

  static const Key detailKey = ValueKey('disposalDetail');
  static const Key summaryKey = ValueKey('disposalDetailSummary');
  static const Key timelineKey = ValueKey('disposalDetailTimeline');
  static const Key linesKey = ValueKey('disposalDetailLines');
  static const Key reasonKey = ValueKey('disposalDetailReason');
  static const Key totalsKey = ValueKey('disposalDetailTotals');
  static const Key noDestinationKey = ValueKey('disposalDetailNoDestination');
  static const Key missingKey = ValueKey('disposalDetailMissing');

  static Key lineKeyFor(String lineId) =>
      ValueKey('disposalDetailLine-$lineId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(disposalDetailProvider(disposalId));
    final nowUtc = ref.watch(disposalClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Pemusnahan')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
        data: (document) {
          if (document == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: DisposalNotice(
                key: missingKey,
                title: 'Dokumen tidak tersedia',
                message:
                    'Pemusnahan ini tidak ditemukan atau berada di luar '
                    'cakupan akun Anda.',
                icon: Icons.lock_outline,
              ),
            );
          }
          return ListView(
            key: detailKey,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _SummaryCard(document: document, nowUtc: nowUtc),
              _TimelineCard(document: document),
              for (final line in document.orderedLines)
                _LineCard(line: line, nowUtc: nowUtc),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.document, required this.nowUtc});

  final DisposalDetail document;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disposal = document.disposal;
    final summary = document.summary;
    final progress = document.progressOn(nowUtc);
    final totals = document.totalQuantityByUnit;
    final units = totals.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        key: DisposalDetailPage.summaryKey,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      disposal.docNumber,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  DisposalStatusChip(status: disposal.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Sumber: ${summary.source.kindLabel} · ${summary.sourceLabel}',
                style: theme.textTheme.bodySmall,
              ),
              if (summary.roomName != null)
                Text(
                  'Ruangan ${summary.roomCode} · ${summary.roomName}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: AppSpacing.sm),
              // The one fact that distinguishes this document from every other
              // stock movement in the application, stated rather than left to be
              // inferred from an absent field (§20/§32).
              Row(
                key: DisposalDetailPage.noDestinationKey,
                children: [
                  const Icon(Icons.block, size: 16, color: AppColors.danger),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Tidak ada lokasi tujuan — stok keluar dari sistem.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Catatan pemusnahan',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                key: DisposalDetailPage.reasonKey,
                disposal.reason ?? 'Belum diisi',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                key: DisposalDetailPage.totalsKey,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(progress.label, style: theme.textTheme.bodySmall),
                  for (final unit in units)
                    DisposalPill(
                      label: totals[unit]!.formatWithUnit(unit),
                      color: theme.colorScheme.primary,
                    ),
                  if (progress.oldestExpiryDate != null)
                    DisposalPill(
                      label:
                          'ED terlama '
                          '${AppDateTimeFormatter.civilDate(progress.oldestExpiryDate!)}',
                      color: AppColors.danger,
                    ),
                  SyncStatusTag(status: disposal.syncStatus),
                  if (summary.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (summary.sourceIsHistorical) 'Lokasi',
                        if (summary.branchIsHistorical) 'Cabang',
                        if (summary.roomIsHistorical) 'Ruangan',
                        if (summary.createdByIsHistorical) 'Pembuat',
                        if (summary.postedByIsHistorical) 'Pemosting',
                      ].join(', '),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who did what, and when. Both instants are UTC in storage and rendered in
/// operational time (T-1/T-2); `toLocal()` is never called.
class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.document});

  final DisposalDetail document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disposal = document.disposal;
    final summary = document.summary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: DisposalDetailPage.timelineKey,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_note),
                title: const Text('Dibuat'),
                subtitle: Text(
                  '${summary.createdByName} · '
                  '${AppDateTimeFormatter.dateTimeWithZone(disposal.createdAt)}',
                ),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  disposal.isPosted
                      ? Icons.check_circle_outline
                      : Icons.hourglass_empty,
                ),
                // Never "Disetujui": posting is the moment the stock left, not an
                // approval of somebody else's work.
                title: const Text('Diposting'),
                subtitle: Text(
                  disposal.postedAt == null
                      ? 'Belum diposting'
                      : '${summary.postedByName ?? '-'} · '
                            '${AppDateTimeFormatter.dateTimeWithZone(disposal.postedAt!)}',
                ),
              ),
              if (disposal.isPosted)
                Text(
                  'Referensi ledger: ${RefDocType.disposal} · '
                  '${disposal.docNumber}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.nowUtc});

  final DisposalLine line;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: DisposalDetailPage.lineKeyFor(line.id),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      line.itemName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Milli-units never reach a screen (Q-6); `format` renders
                  // `2.375`, never `2375`.
                  Text(
                    line.qty.formatWithUnit(line.unit),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              Text(
                '${line.sku} · batch ${line.batchNo}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DisposalExpiryBadge(
                    expiryDate: line.expiryDate,
                    expiryAlertDays: 0,
                    nowUtc: nowUtc,
                  ),
                  if (line.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (line.itemIsHistorical) 'Barang',
                        if (line.batchIsHistorical) 'Batch',
                      ].join(', '),
                    ),
                ],
              ),
              if (line.hasNote)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(line.note!, style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A per-unit total row, shared by the summary and the tests.
class DisposalUnitTotals extends StatelessWidget {
  const DisposalUnitTotals({super.key, required this.totals});

  final Map<String, Quantity> totals;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final units = totals.keys.toList()..sort();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final unit in units)
          DisposalPill(
            label: totals[unit]!.formatWithUnit(unit),
            color: theme.colorScheme.primary,
          ),
      ],
    );
  }
}
