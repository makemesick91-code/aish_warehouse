import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/widgets/status_card.dart';
import '../../domain/services/delivery_order_access_policy.dart';
import '../providers/delivery_providers.dart';
import 'warehouse_delivery_order_list_page.dart';

/// Pengiriman Masuk — the Kepala Cabang's read-only view of incoming shipments
/// (§29).
///
/// Read-only in this milestone by design, not by omission. The next step for a
/// shipped document is Good Receipt (G-G1), and that document does not exist yet;
/// rendering a "Terima" button would promise something no use case can deliver. So
/// the page says what is true instead: *Menunggu pemeriksaan Good Receipt*.
///
/// What a branch head can see is `shipped` and `received` only. A `preparing`
/// document is the warehouse's working draft — nothing has left the building — and
/// the status predicate travels into the SQL query, so it is not fetched and then
/// hidden. Typing its id does not help either: the route guard refuses it.
class BranchDeliveryListPage extends ConsumerWidget {
  const BranchDeliveryListPage({super.key});

  static const Key listKey = ValueKey('branchDeliveryList');
  static const Key emptyKey = ValueKey('branchDeliveryEmpty');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(branchDeliveryListProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Pengiriman Masuk')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(branchDeliveryListProvider(null)),
        child: ListView(
          key: BranchDeliveryListPage.listKey,
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const _StatusFilterRow(),
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
                      ref.invalidate(branchDeliveryListProvider(null)),
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Card(
                        key: BranchDeliveryListPage.emptyKey,
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            'Belum ada pengiriman masuk untuk cabang ini.',
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
                              AppRoutes.deliveryDetailName,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(branchDeliveryStatusFilterProvider);
    final notifier = ref.read(branchDeliveryStatusFilterProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Semua'),
            selected: selected == null,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.clear(),
          ),
          // Only the statuses a branch may see. Offering a `preparing` chip would
          // suggest there is something behind it.
          //
          // Deliberately no `avatar`: a `FilterChip`'s avatar slot is a small fixed
          // box, and putting the status chip in it overflows the row. The chip
          // belongs on the list rows, where it labels a document rather than a
          // filter.
          for (final status
              in DeliveryOrderAccessPolicy.branchVisibleStatuses) ...[
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              key: ValueKey('branchDeliveryStatusFilter-${status.dbValue}'),
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
