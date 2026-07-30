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
import '../../../../core/widgets/sync_status_tag.dart';
import '../../../purchase_request/presentation/providers/purchase_request_providers.dart';
import '../../domain/models/delivery_models.dart';
import '../providers/delivery_providers.dart';
import '../widgets/delivery_order_status_chip.dart';

/// Pengiriman — every shipment the central warehouse has raised (§27.1).
///
/// Unscoped by branch **on purpose**: the warehouse serves the whole clinic group
/// (spec §4.2). What stands in for a branch predicate is the role check, applied
/// both by the section guard on the route and again inside
/// [warehouseDeliveryListProvider] — so this screen reached by any other means
/// still shows nothing.
class WarehouseDeliveryOrderListPage extends ConsumerStatefulWidget {
  const WarehouseDeliveryOrderListPage({super.key});

  static const Key listKey = ValueKey('warehouseDeliveryList');
  static const Key emptyKey = ValueKey('warehouseDeliveryEmpty');
  static const Key searchKey = ValueKey('warehouseDeliverySearch');

  @override
  ConsumerState<WarehouseDeliveryOrderListPage> createState() =>
      _WarehouseDeliveryOrderListPageState();
}

class _WarehouseDeliveryOrderListPageState
    extends ConsumerState<WarehouseDeliveryOrderListPage> {
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
      ref.read(warehouseDeliverySearchProvider.notifier).update(value);
    });
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {});
    ref.read(warehouseDeliverySearchProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(warehouseDeliveryListProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Pengiriman')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(warehouseDeliveryListProvider(null)),
        child: ListView(
          key: WarehouseDeliveryOrderListPage.listKey,
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                key: WarehouseDeliveryOrderListPage.searchKey,
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Cari nomor DO, nomor PR, cabang atau barang',
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
            orders.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(
                  message: describeFailure(error),
                  onRetry: () =>
                      ref.invalidate(warehouseDeliveryListProvider(null)),
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Card(
                        key: WarehouseDeliveryOrderListPage.emptyKey,
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            'Belum ada Surat Jalan. Buat pengiriman dari '
                            'Purchase Request yang sedang diproses.',
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final summary in rows)
                          DeliveryOrderTile(
                            summary: summary,
                            onTap: () => context.pushNamed(
                              AppRoutes.warehouseDeliveryOrderDetailName,
                              pathParameters: {'id': summary.id},
                            ),
                          ),
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

  static const List<DeliveryOrderStatus> _statuses = DeliveryOrderStatus.values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(warehouseDeliveryStatusFilterProvider);
    final notifier = ref.read(warehouseDeliveryStatusFilterProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Semua status'),
            selected: selected == null,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.clear(),
          ),
          for (final status in _statuses) ...[
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              key: ValueKey('deliveryStatusFilter-${status.dbValue}'),
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
    final selected = ref.watch(warehouseDeliveryBranchFilterProvider);
    final notifier = ref.read(warehouseDeliveryBranchFilterProvider.notifier);

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
                      key: ValueKey('deliveryBranchFilter-${branch.code}'),
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

/// One row of a delivery list.
///
/// Shared between the warehouse list and the branch's incoming list, because the
/// facts a reader needs are the same and keeping two near-identical tiles in step
/// by hand is how they stop agreeing. What differs is only where the tap goes,
/// which the caller supplies.
class DeliveryOrderTile extends StatelessWidget {
  const DeliveryOrderTile({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final DeliveryOrderSummary summary;
  final VoidCallback onTap;

  static Key tileKeyFor(String doId) => ValueKey('deliveryTile-$doId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = summary.order;

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
                    DeliveryOrderStatusChip(status: summary.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'PR ${summary.prDocNumber}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '${summary.branchCode} · ${summary.branchName}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Disiapkan ${summary.preparedByName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  // Both instants are UTC in storage and rendered in operational
                  // time (T-1/T-2); `toLocal()` is never called.
                  'Dibuat ${AppDateTimeFormatter.dateTimeWithZone(order.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (order.shippedAt != null)
                  Text(
                    'Dikirim ${AppDateTimeFormatter.dateTimeWithZone(order.shippedAt!)}',
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
                      '${summary.lineCount} baris',
                      style: theme.textTheme.bodySmall,
                    ),
                    SyncStatusTag(status: order.syncStatus),
                    if (summary.usesHistoricalMaster)
                      HistoricalMasterBadge.forDetail(
                        [
                          if (summary.branchIsHistorical) 'Cabang',
                          if (summary.preparedByIsHistorical) 'Petugas',
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
