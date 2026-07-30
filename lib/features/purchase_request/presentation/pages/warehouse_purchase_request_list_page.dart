import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../domain/models/purchase_request_models.dart';
import '../providers/purchase_request_providers.dart';
import '../widgets/purchase_request_status_chip.dart';

/// PR Masuk — the central warehouse's inbox across every branch (§25).
///
/// Unscoped by branch **on purpose**: the warehouse serves the whole clinic group,
/// and spec §4.2 describes this screen as "daftar PR `submitted` semua cabang".
/// What replaces the branch predicate is the status set — a `draft` is
/// device-authoritative until it is submitted (G-Y2), so it never appears here and
/// cannot be reached by typing its id either (the route guard refuses it).
class WarehousePurchaseRequestListPage extends ConsumerStatefulWidget {
  const WarehousePurchaseRequestListPage({super.key});

  static const Key listKey = ValueKey('warehousePurchaseRequestList');
  static const Key emptyKey = ValueKey('warehousePurchaseRequestEmpty');

  @override
  ConsumerState<WarehousePurchaseRequestListPage> createState() =>
      _WarehousePurchaseRequestListPageState();
}

class _WarehousePurchaseRequestListPageState
    extends ConsumerState<WarehousePurchaseRequestListPage> {
  static const Duration _debounce = Duration(milliseconds: 200);

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    setState(() {});
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      ref.read(warehousePurchaseRequestSearchProvider.notifier).update(value);
    });
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {});
    ref.read(warehousePurchaseRequestSearchProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(warehousePurchaseRequestQueueProvider);
    // "Now" comes from the feature clock, so the age column is deterministic under
    // an overridden clock in tests (T-7).
    final now = ref.watch(purchaseRequestClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('PR Masuk')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(warehousePurchaseRequestQueueProvider),
        child: ListView(
          key: WarehousePurchaseRequestListPage.listKey,
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                key: const ValueKey('warehousePrSearch'),
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Cari nomor PR atau nama cabang',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
            const _StatusFilterRow(),
            const _BranchFilterRow(),
            queue.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(
                  message: describeFailure(error),
                  onRetry: () =>
                      ref.invalidate(warehousePurchaseRequestQueueProvider),
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Card(
                        key: WarehousePurchaseRequestListPage.emptyKey,
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            'Belum ada Purchase Request yang menunggu diproses.',
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final summary in rows)
                          _QueueTile(summary: summary, now: now),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusFilterRow extends ConsumerWidget {
  const _StatusFilterRow();

  /// The statuses that make sense on a warehouse queue. `draft` is absent because
  /// the warehouse never sees one, and offering the chip would suggest otherwise.
  static const List<PurchaseRequestStatus> _statuses = [
    PurchaseRequestStatus.submitted,
    PurchaseRequestStatus.processing,
    PurchaseRequestStatus.shipped,
    PurchaseRequestStatus.closed,
    PurchaseRequestStatus.rejected,
    PurchaseRequestStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(warehousePurchaseRequestStatusFilterProvider);
    final notifier = ref.read(
      warehousePurchaseRequestStatusFilterProvider.notifier,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Menunggu & Diproses'),
            selected: selected == null,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.clear(),
          ),
          for (final status in _statuses) ...[
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              key: ValueKey('warehousePrStatusFilter-${status.dbValue}'),
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

class _BranchFilterRow extends ConsumerWidget {
  const _BranchFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider);
    final selected = ref.watch(warehouseBranchFilterProvider);
    final notifier = ref.read(warehouseBranchFilterProvider.notifier);

    return branches.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (rows) => rows.isEmpty
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Semua cabang'),
                    selected: selected == null,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => notifier.select(null),
                  ),
                  for (final branch in rows) ...[
                    const SizedBox(width: AppSpacing.sm),
                    FilterChip(
                      key: ValueKey('warehousePrBranchFilter-${branch.code}'),
                      label: Text(branch.name),
                      selected: selected == branch.id,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => notifier.select(branch.id),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.summary, required this.now});

  final PurchaseRequestSummary summary;

  /// UTC instant used for the "age" column.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = summary.request;
    final age = summary.ageSinceSubmission(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        child: InkWell(
          key: ValueKey('warehousePrTile-${summary.id}'),
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.pushNamed(
            AppRoutes.warehousePurchaseRequestDetailName,
            pathParameters: {'id': summary.id},
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
                        summary.docNumber,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PurchaseRequestStatusChip(status: summary.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${summary.branchCode} · ${summary.branchName}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Diminta ${summary.requestedByName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  request.neededDate == null
                      ? 'Tanggal dibutuhkan: —'
                      : 'Dibutuhkan ${AppDateTimeFormatter.civilDate(request.neededDate!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${summary.lineCount} barang',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (age != null)
                      Text(
                        'Umur permintaan ${_formatAge(age)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: age.inHours >= 48
                              ? AppColors.warning
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (summary.usesHistoricalMaster)
                      HistoricalMasterBadge.forDetail(
                        [
                          if (summary.branchIsHistorical) 'Cabang',
                          if (summary.requestedByIsHistorical) 'Pemohon',
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

  static String _formatAge(Duration age) {
    if (age.inDays >= 1) return '${age.inDays} hari';
    if (age.inHours >= 1) return '${age.inHours} jam';
    return '${age.inMinutes} menit';
  }
}
