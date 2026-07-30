import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/distribution_models.dart';
import '../providers/distribution_providers.dart';
import '../widgets/distribution_badges.dart';

/// Distribusi — the Kepala Cabang's list (§28).
///
/// One screen, one branch: drafts to continue and posted documents to read. There is no
/// warehouse counterpart, because spec §3.1 gives this document to `kepala_cabang`
/// alone — a cross-branch recap is a reporting question, and the reporting module is a
/// later milestone.
///
/// Every row and every count comes from [branchDistributionListProvider], which carries
/// the branch predicate inside its SQL. A session that may not write distributions gets
/// an empty list rather than a cross-branch read, so the route guard is never the only
/// defence.
class DistributionListPage extends ConsumerWidget {
  const DistributionListPage({super.key});

  static const Key listKey = ValueKey('distributionList');
  static const Key emptyKey = ValueKey('distributionListEmpty');
  static const Key createKey = ValueKey('distributionCreateButton');
  static const Key searchKey = ValueKey('distributionListSearch');
  static const Key branchKey = ValueKey('distributionListBranch');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(branchDistributionListProvider(null));
    final nowUtc = ref.watch(distributionClockProvider)();
    final creating = ref.watch(createDistributionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Distribusi')),
      floatingActionButton: FloatingActionButton.extended(
        key: createKey,
        // Disabled while a creation is in flight: two taps must not produce two
        // documents.
        onPressed: creating.isLoading
            ? null
            : () async {
                final id = await ref
                    .read(createDistributionControllerProvider.notifier)
                    .create();
                if (!context.mounted) return;
                if (id == null) {
                  final error = ref
                      .read(createDistributionControllerProvider)
                      .error;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        describeFailure(error ?? 'Gagal membuat distribusi.'),
                      ),
                    ),
                  );
                  return;
                }
                context.pushNamed(
                  AppRoutes.distributionEditName,
                  pathParameters: {'id': id},
                );
              },
        icon: const Icon(Icons.add),
        label: const Text('Buat Distribusi'),
      ),
      body: Column(
        children: [
          const _BranchHeader(),
          const _StatusFilterRow(),
          const _SearchField(),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(
                  message: describeFailure(error),
                  onRetry: () =>
                      ref.invalidate(branchDistributionListProvider(null)),
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Card(
                      key: emptyKey,
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'Belum ada distribusi untuk cabang ini. Tekan '
                          '"Buat Distribusi" untuk memulai.',
                        ),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(branchDistributionListProvider(null)),
                  child: ListView.builder(
                    key: listKey,
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl * 2),
                    itemCount: rows.length,
                    itemBuilder: (context, index) => DistributionSummaryTile(
                      summary: rows[index],
                      nowUtc: nowUtc,
                      onTap: () => context.pushNamed(
                        // A draft opens in the editor, a posted document in the
                        // read-only detail. Both routes are guarded independently; this
                        // only chooses which one to try.
                        rows[index].distribution.isDraft
                            ? AppRoutes.distributionEditName
                            : AppRoutes.distributionDetailName,
                        pathParameters: {'id': rows[index].id},
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchHeader extends ConsumerWidget {
  const _BranchHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // From master data, not from whatever documents happen to be on screen: a status
    // filter that matches nothing must not make the branch name disappear.
    final branch = ref.watch(actingBranchProvider).value;
    if (branch == null) return const SizedBox.shrink();

    return Padding(
      key: DistributionListPage.branchKey,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          const Icon(Icons.store_mall_directory_outlined, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${branch.code} · ${branch.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterRow extends ConsumerWidget {
  const _StatusFilterRow();

  static Key keyFor(DistributionStatus status) =>
      ValueKey('distributionStatusFilter-${status.dbValue}');

  static const Key allKey = ValueKey('distributionStatusFilter-all');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(distributionStatusFilterProvider);
    final notifier = ref.read(distributionStatusFilterProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          FilterChip(
            key: allKey,
            label: const Text('Semua'),
            selected: selected == null,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.clear(),
          ),
          for (final status in DistributionStatus.values) ...[
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              key: keyFor(status),
              label: Text(status.label),
              selected: selected == status,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => notifier.select(status),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: TextField(
        key: DistributionListPage.searchKey,
        controller: _controller,
        onChanged: (value) =>
            ref.read(distributionSearchProvider.notifier).update(value),
        decoration: InputDecoration(
          labelText: 'Cari nomor, ruangan atau barang',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Hapus pencarian',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    ref.read(distributionSearchProvider.notifier).clear();
                    setState(() {});
                  },
                ),
        ),
      ),
    );
  }
}

/// One row of the distribution list.
class DistributionSummaryTile extends StatelessWidget {
  const DistributionSummaryTile({
    super.key,
    required this.summary,
    required this.nowUtc,
    required this.onTap,
  });

  final DistributionSummary summary;

  /// UTC instant used as the reference "now" (T-7).
  final DateTime nowUtc;
  final VoidCallback onTap;

  static Key tileKeyFor(String distributionId) =>
      ValueKey('distributionTile-$distributionId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distribution = summary.distribution;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        child: InkWell(
          key: tileKeyFor(summary.id),
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.docNumber,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DistributionStatusChip(status: summary.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${summary.branchCode} · ${summary.branchName}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Didistribusikan ${summary.distributedByName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  // Both instants are UTC in storage and rendered in operational time
                  // (T-1/T-2); `toLocal()` is never called.
                  'Dibuat ${AppDateTimeFormatter.dateTimeWithZone(distribution.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (distribution.postedAt != null)
                  Text(
                    'Diposting ${AppDateTimeFormatter.dateTimeWithZone(distribution.postedAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
                    Text(summary.label, style: theme.textTheme.bodySmall),
                    if (summary.overrideCount > 0)
                      DistributionPill(
                        label: '${summary.overrideCount} di luar FEFO',
                        color: AppColors.warning,
                        icon: Icons.swap_vert,
                      ),
                    SyncStatusTag(status: distribution.syncStatus),
                    if (summary.usesHistoricalMaster)
                      HistoricalMasterBadge.forDetail(
                        [
                          if (summary.branchIsHistorical) 'Cabang',
                          if (summary.distributedByIsHistorical) 'Petugas',
                        ].join(', '),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A per-unit total row, shared by the list summary and the posted detail.
///
/// Quantities of different units are never added together: `2 box` and `3 pcs` are not
/// `5` of anything, and one headline number would mislead.
class DistributionUnitTotals extends StatelessWidget {
  const DistributionUnitTotals({super.key, required this.totals});

  final Map<String, Quantity> totals;

  static const Key totalsKey = ValueKey('distributionUnitTotals');

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final units = totals.keys.toList()..sort();

    return Wrap(
      key: totalsKey,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final unit in units)
          DistributionPill(
            label: totals[unit]!.formatWithUnit(unit),
            color: theme.colorScheme.primary,
          ),
      ],
    );
  }
}
