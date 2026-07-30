import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/opname_models.dart';
import '../providers/opname_providers.dart';
import '../widgets/category_filter_chips.dart';
import '../widgets/document_timeline.dart';
import '../widgets/historical_master_badge.dart';
import '../widgets/opname_status_chip.dart';
import '../widgets/stock_opname_line_card.dart';

/// Detail review — where the Kepala Cabang inspects the count and locks it.
///
/// Everything on this screen is read-only; the single action is
/// **Review & Kunci**, which is final and therefore confirmed first (G-S1).
class OpnameReviewDetailPage extends ConsumerStatefulWidget {
  const OpnameReviewDetailPage({super.key, required this.opnameId});

  final String opnameId;

  @override
  ConsumerState<OpnameReviewDetailPage> createState() =>
      _OpnameReviewDetailPageState();
}

class _OpnameReviewDetailPageState
    extends ConsumerState<OpnameReviewDetailPage> {
  String get opnameId => widget.opnameId;

  @override
  void initState() {
    super.initState();
    // The category/search filter is app-scoped. A chip the nurse left active
    // on her form would otherwise silently hide lines from the reviewer — who
    // would be locking a count they had not fully seen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(opnameCategoryFilterProvider.notifier).clear();
      ref.read(opnameSearchQueryProvider.notifier).clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(opnameDetailProvider(opnameId));
    final session = ref.watch(currentSessionValueProvider);
    final action = ref.watch(reviewOpnameControllerProvider);
    final filter = ref.watch(opnameLineFilterProvider);
    final now = DateTime.now().toUtc();

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Review Opname')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(describeFailure(error), textAlign: TextAlign.center),
          ),
        ),
        data: (data) {
          if (data == null) {
            return const Center(
              child: Text('Dokumen stok opname tidak ditemukan.'),
            );
          }

          // The button is offered only when this reviewer could actually
          // perform the action; the use case re-checks all of it anyway.
          final canReview =
              session != null &&
              session.canReviewOpname &&
              session.branchId == data.opname.branchId &&
              session.userId != data.opname.countedBy &&
              data.opname.canReview;

          final visibleLines = data.lines
              .where(filter.matchesLine)
              .toList(growable: false);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  children: [
                    _ReviewHeader(detail: data),
                    _SummaryCard(detail: data),
                    const CategoryFilterChips(),
                    const SizedBox(height: AppSpacing.sm),
                    if (visibleLines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: Text(
                            'Tidak ditemukan barang yang cocok dengan filter.',
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Column(
                          children: [
                            for (final line in visibleLines)
                              StockOpnameLineCard(
                                key: ValueKey(line.id),
                                line: line,
                                // Never editable here, whatever the status.
                                editable: false,
                                now: now,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _ReviewFooter(
                detail: data,
                canReview: canReview,
                busy: action.isLoading,
                onReview: () => _confirmAndReview(context, ref, data),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAndReview(
    BuildContext context,
    WidgetRef ref,
    StockOpnameDetail detail,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review & Kunci?'),
        content: Text(
          'Saldo ruangan ${detail.summary.roomName} akan disesuaikan agar sama '
          'dengan hasil hitung fisik pada dokumen ${detail.opname.docNumber}.\n\n'
          'Tindakan ini bersifat final dan tidak dapat dibatalkan. Koreksi '
          'setelahnya hanya bisa lewat dokumen penyesuaian baru.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Review & Kunci'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final succeeded = await ref
        .read(reviewOpnameControllerProvider.notifier)
        .review(detail.id);
    if (!context.mounted) return;

    if (succeeded) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Stok opname direview. Saldo ruangan sudah disesuaikan.',
            ),
          ),
        );
      // Stay on the document, which the stream has just re-rendered read-only.
      return;
    }

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            describeFailure(
              ref.read(reviewOpnameControllerProvider).error ??
                  'Gagal mereview dokumen',
            ),
          ),
        ),
      );
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({required this.detail});

  final StockOpnameDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opname = detail.opname;

    return Padding(
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
                      opname.docNumber,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  OpnameStatusChip(status: opname.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${detail.summary.roomName} · Perawat '
                '${detail.summary.countedByName}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Periode ${opname.periodLabel} '
                '(${AppDateTimeFormatter.timeZoneLabel})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // Shown, never hidden: a room or nurse deactivated after the
              // count does not stop this document from needing a decision, and
              // the reviewer should know the master data behind it has moved
              // on (§7.6).
              const SizedBox(height: AppSpacing.sm),
              opnameHistoricalBadge(detail.summary),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              DocumentTimeline(summary: detail.summary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.detail});

  final StockOpnameDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
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
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Jumlah barang',
                      value: '${detail.lines.length}',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Baris berselisih',
                      value: '${detail.linesWithDifference.length}',
                      color: detail.linesWithDifference.isEmpty
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Quantities of different units are reported per unit rather
              // than added together — "5" across box and pcs would be a
              // number that means nothing.
              _TotalsRow(
                label: 'Total kelebihan',
                totals: detail.surplusByUnit,
                color: AppColors.success,
              ),
              const SizedBox(height: AppSpacing.xs),
              _TotalsRow(
                label: 'Total kekurangan',
                totals: detail.shortageByUnit,
                color: AppColors.danger,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.totals,
    required this.color,
  });

  final String label;
  final Map<String, Quantity> totals;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: entries.isEmpty
              ? Text('—', style: theme.textTheme.bodySmall)
              : Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final entry in entries)
                      Text(
                        entry.value.formatWithUnit(entry.key),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs / 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({
    required this.detail,
    required this.canReview,
    required this.busy,
    required this.onReview,
  });

  final StockOpnameDetail detail;
  final bool canReview;
  final bool busy;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (detail.opname.isReviewed) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.lock, size: 18, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Sudah direview '
                  '${detail.summary.reviewedByName ?? ''} · '
                  '${AppDateTimeFormatter.dateTimeWithZone(detail.opname.reviewedAt!)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!canReview) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Anda tidak dapat mereview dokumen ini.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            // Disabled while the posting runs, so the ledger cannot be asked
            // to adjust the same document twice.
            onPressed: busy ? null : onReview,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline),
            label: Text(busy ? 'Memproses…' : 'Review & Kunci'),
          ),
        ),
      ),
    );
  }
}
