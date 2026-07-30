import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/distribution_models.dart';
import '../providers/distribution_providers.dart';
import '../widgets/distribution_badges.dart';
import 'distribution_list_page.dart';

/// The read-only Distribusi detail (§30).
///
/// What a posted distribution *is*: a record of stock that moved. So this page has no
/// edit control, no remove control, no post button and no un-post — not disabled ones,
/// **absent** ones. G-S2 makes a posted document read-only permanently, and a screen
/// that renders an action the use case would refuse is a screen that has to be kept in
/// step with the refusal by hand.
///
/// A draft opens here too, and is equally read-only: the editor is where a draft is
/// changed, and offering two write surfaces for one document is how they come to
/// disagree. What this page adds for a draft is the plain statement that it has not been
/// posted yet.
///
/// The lines are grouped per room (G-T3) and each names its source and destination in
/// words — *Gudang Cabang → Ruang Dental 2* — because §30 asks for both and because a
/// reader six months later should not have to know that "distribution" implies them.
class DistributionDetailPage extends ConsumerWidget {
  const DistributionDetailPage({super.key, required this.distributionId});

  final String distributionId;

  static const Key listKey = ValueKey('distributionDetailList');
  static const Key headerKey = ValueKey('distributionDetailHeader');
  static const Key summaryKey = ValueKey('distributionDetailSummary');
  static const Key timelineKey = ValueKey('distributionDetailTimeline');
  static const Key notFoundKey = ValueKey('distributionDetailNotFound');

  static Key roomKeyFor(String roomId) =>
      ValueKey('distributionDetailRoom-$roomId');

  static Key lineKeyFor(String lineId) =>
      ValueKey('distributionDetailLine-$lineId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(branchDistributionDetailProvider(distributionId));
    final nowUtc = ref.watch(distributionClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Distribusi')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(
            message: describeFailure(error),
            onRetry: () => ref.invalidate(
              branchDistributionDetailProvider(distributionId),
            ),
          ),
        ),
        data: (document) {
          if (document == null) {
            // One answer for "no such document" and for "another branch's", so the id
            // cannot be probed from the address bar.
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Card(
                key: notFoundKey,
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Distribusi tidak ditemukan atau bukan milik cabang ini.',
                  ),
                ),
              ),
            );
          }

          final progress = document.progressOn(nowUtc);

          return ListView(
            key: listKey,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _Header(detail: document),
              _Timeline(detail: document),
              _Summary(detail: document, progress: progress),
              const _SectionTitle('Rincian per ruangan'),
              for (final group in document.roomGroups)
                _RoomGroup(
                  group: group,
                  branchStoreLabel: 'Gudang Cabang',
                  nowUtc: nowUtc,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final DistributionDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distribution = detail.distribution;

    return Padding(
      key: DistributionDetailPage.headerKey,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      distribution.docNumber,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  DistributionStatusChip(status: distribution.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${detail.summary.branchCode} · ${detail.summary.branchName}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Didistribusikan ${detail.summary.distributedByName}',
                style: theme.textTheme.bodySmall,
              ),
              if ((distribution.note ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    distribution.note!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SyncStatusTag(status: distribution.syncStatus),
                  if (detail.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (detail.summary.branchIsHistorical) 'Cabang',
                        if (detail.summary.distributedByIsHistorical) 'Petugas',
                        if (detail.lines.any((line) => line.roomIsHistorical))
                          'Ruangan',
                        if (detail.lines.any((line) => line.itemIsHistorical))
                          'Barang',
                        if (detail.lines.any((line) => line.batchIsHistorical))
                          'Batch',
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

class _Timeline extends StatelessWidget {
  const _Timeline({required this.detail});

  final DistributionDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distribution = detail.distribution;

    return Padding(
      key: DistributionDetailPage.timelineKey,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Riwayat dokumen',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Both instants are UTC in storage and rendered in operational time
              // (T-1/T-2); `toLocal()` is never called anywhere on this path.
              _TimelineRow(
                label: 'Dibuat',
                value: AppDateTimeFormatter.dateTimeWithZone(
                  distribution.createdAt,
                ),
              ),
              _TimelineRow(
                label: 'Diposting',
                value: distribution.postedAt == null
                    ? 'Belum diposting'
                    : AppDateTimeFormatter.dateTimeWithZone(
                        distribution.postedAt!,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.detail, required this.progress});

  final DistributionDetail detail;
  final DistributionProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      key: DistributionDetailPage.summaryKey,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ringkasan',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${progress.roomCount} ruangan · ${progress.lineCount} baris · '
                '${progress.itemCount} barang',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              DistributionUnitTotals(totals: detail.totalsByUnit),
              if (progress.overrideCount > 0 ||
                  progress.nearExpiryCount > 0 ||
                  progress.expiredCount > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (progress.overrideCount > 0)
                      DistributionPill(
                        label: '${progress.overrideCount} di luar FEFO',
                        color: AppColors.warning,
                        icon: Icons.swap_vert,
                      ),
                    if (progress.nearExpiryCount > 0)
                      DistributionPill(
                        label: '${progress.nearExpiryCount} segera kedaluwarsa',
                        color: AppColors.warning,
                        icon: Icons.timelapse,
                      ),
                    if (progress.expiredCount > 0)
                      DistributionPill(
                        label: '${progress.expiredCount} kedaluwarsa',
                        color: AppColors.danger,
                        icon: Icons.event_busy,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _RoomGroup extends StatelessWidget {
  const _RoomGroup({
    required this.group,
    required this.branchStoreLabel,
    required this.nowUtc,
  });

  final DistributionRoomGroup group;
  final String branchStoreLabel;
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
        key: DistributionDetailPage.roomKeyFor(group.roomId),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${group.roomCode} · ${group.roomName}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (group.roomIsHistorical)
                    HistoricalMasterBadge.inactive(detail: 'Ruangan'),
                ],
              ),
              Text(
                // §30 asks for both sides in words, so a reader does not have to know
                // that "distribution" implies them.
                '$branchStoreLabel → ${group.roomName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Divider(),
              for (final line in group.lines) ...[
                Padding(
                  key: DistributionDetailPage.lineKeyFor(line.id),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.itemName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            line.qty.formatWithUnit(line.unit),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${line.sku}'
                        '${line.batchNo == null ? ' · tanpa batch' : ' · ${line.batchNo}'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (line.expiryDate != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: DistributionExpiryBadge(
                            expiryDate: line.expiryDate!,
                            expiryAlertDays: line.expiryAlertDays,
                            nowUtc: nowUtc,
                          ),
                        ),
                      if (line.hasFefoOverride)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: DistributionFefoOverrideBadge(
                            reason: line.fefoOverrideReason!,
                          ),
                        ),
                      if (line.usesHistoricalMaster)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: HistoricalMasterBadge.inactive(
                            detail: [
                              if (line.itemIsHistorical) 'Barang',
                              if (line.batchIsHistorical) 'Batch',
                            ].join(', '),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
              const SizedBox(height: AppSpacing.sm),
              DistributionUnitTotals(totals: group.totalsByUnit),
            ],
          ),
        ),
      ),
    );
  }
}
