import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/opname_models.dart';
import '../providers/opname_providers.dart';
import '../widgets/opname_status_chip.dart';

/// Review Stok Opname — the Kepala Cabang's inbox (spec §4.2).
///
/// Shows submitted documents of the reviewer's own branch only. That scoping is
/// applied in the query (G-R2), not by hiding rows in the widget.
class OpnameReviewListPage extends ConsumerWidget {
  const OpnameReviewListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionValueProvider);
    final pending = ref.watch(submittedOpnameListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review Stok Opname')),
      body: session == null || !session.canReviewOpname
          ? const _Notice(
              icon: Icons.lock_outline,
              message:
                  'Hanya Kepala Cabang yang dapat mereview stok opname. '
                  'Ganti peran pada halaman pengembangan untuk mencobanya.',
            )
          : RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(submittedOpnameListProvider),
              child: pending.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _Notice(
                  icon: Icons.error_outline,
                  message: describeFailure(error),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return ListView(
                      children: const [
                        _Notice(
                          icon: Icons.inbox_outlined,
                          message:
                              'Tidak ada stok opname yang menunggu review '
                              'saat ini.',
                        ),
                      ],
                    );
                  }

                  final grouped = _groupByPeriod(rows);

                  return ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    children: [
                      for (final entry in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.sm,
                          ),
                          child: Text(
                            'Periode ${entry.key}',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        for (final summary in entry.value)
                          _ReviewTile(summary: summary),
                      ],
                    ],
                  );
                },
              ),
            ),
    );
  }

  /// Groups by ISO period so a reviewer sees a week's counts together.
  Map<String, List<StockOpnameSummary>> _groupByPeriod(
    List<StockOpnameSummary> rows,
  ) {
    final grouped = <String, List<StockOpnameSummary>>{};
    for (final summary in rows) {
      grouped.putIfAbsent(summary.opname.periodLabel, () => []).add(summary);
    }
    return grouped;
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.summary});

  final StockOpnameSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opname = summary.opname;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.pushNamed(
            AppRoutes.opnameReviewDetailName,
            pathParameters: {'id': opname.id},
          ),
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
                  '${summary.roomName} · ${summary.countedByName}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Text(
                      '${summary.lineCount} baris',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (summary.hasDifference)
                      Text(
                        '${summary.differenceLineCount} berselisih',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        'Tanpa selisih',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                  ],
                ),
                if (opname.submittedAt != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Dikirim '
                    '${AppDateTimeFormatter.dateTimeWithZone(opname.submittedAt!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}
