import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../inventory/domain/models/inventory_models.dart';
import '../../../inventory/presentation/widgets/expiry_badge.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../../good_receipt/presentation/widgets/good_receipt_dashboard_cards.dart';
import '../../../distribution/presentation/widgets/distribution_dashboard_cards.dart';
import '../providers/development_home_providers.dart';

/// Development screen that proves the foundation works end to end: the local
/// database opens, master data can be seeded, and warehouse balances come from
/// the ledger through providers. This is not the final dashboard.
class DevelopmentHomePage extends ConsumerWidget {
  const DevelopmentHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(masterSummaryProvider);
    final seedState = ref.watch(seedControllerProvider);

    ref.listen(seedControllerProvider, (previous, next) {
      final error = next.error;
      if (error != null) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(describeFailure(error))));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aish Warehouse'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () {
              ref.invalidate(masterSummaryProvider);
              ref.invalidate(warehouseLocationProvider);
              ref.invalidate(databaseStatusProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(masterSummaryProvider);
          ref.invalidate(warehouseLocationProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const _DatabaseStatusCard(),
            const SizedBox(height: AppSpacing.md),
            const _SessionCard(),
            const SizedBox(height: AppSpacing.md),
            // G-G6's reminder and §33's selisih card. Both render nothing for a role
            // they do not belong to, and both are scoped by the acting session, so
            // switching user re-runs them rather than serving the previous branch's
            // count from cache.
            const GoodReceiptReminderCard(),
            const GoodReceiptDiscrepancyCard(),
            summary.when(
              loading: () =>
                  const _LoadingBlock(message: 'Memuat ringkasan master data…'),
              error: (error, _) => ErrorNotice(
                message: describeFailure(error),
                onRetry: () => ref.invalidate(masterSummaryProvider),
              ),
              data: (data) => _SummarySection(
                summary: data,
                isSeeding: seedState.isLoading,
                onSeed: () =>
                    ref.read(seedControllerProvider.notifier).runSeed(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Saldo Warehouse Pusat',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            const _OperationalTimeZoneNote(),
            const SizedBox(height: AppSpacing.sm),
            const _WarehouseBalanceSection(),
          ],
        ),
      ),
    );
  }
}

class _DatabaseStatusCard extends ConsumerWidget {
  const _DatabaseStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(databaseStatusProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: status.when(
          loading: () => const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppSpacing.md),
              Text('Membuka database lokal…'),
            ],
          ),
          error: (error, _) => Row(
            children: [
              Icon(Icons.storage, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Database lokal gagal dibuka: ${describeFailure(error)}',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
          data: (version) => Row(
            children: [
              const Icon(Icons.storage, color: AppColors.success),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Database lokal siap (offline-first)'),
                    Text(
                      'SQLite $version · aish_warehouse.sqlite',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Development-only role switcher and the entry point into Stok Opname.
///
/// Authentication is not part of this milestone, so the acting user is chosen
/// here instead of logged in. Switching between the seeded Perawat and Kepala
/// Cabang is what makes the count → review handover demonstrable on one device.
class _SessionCard extends ConsumerWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final users = ref.watch(selectableSessionUsersProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined, color: AppColors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Sesi pengembangan',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            users.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(describeFailure(error)),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Text(
                    'Belum ada pengguna. Jalankan seed pengembangan terlebih '
                    'dahulu.',
                  );
                }

                return DropdownButtonFormField<String>(
                  initialValue: session.value?.userId,
                  // Names and role labels are user data, and Indonesian role labels
                  // are long ("Petugas Warehouse"). Without `isExpanded` the button
                  // sizes to its content and overflows the field on a narrow screen;
                  // without the ellipsis the selected item still would.
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Bertindak sebagai',
                  ),
                  items: [
                    for (final user in rows)
                      DropdownMenuItem(
                        value: user.id,
                        child: Text(
                          '${user.fullName} · '
                          '${CurrentUserSession(user).roleLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(currentSessionProvider.notifier).switchTo(value);
                  },
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.pushNamed(AppRoutes.opnameName),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Stok Opname'),
                  ),
                ),
                if (session.value?.canReviewOpname ?? false) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.pushNamed(AppRoutes.opnameReviewName),
                      icon: const Icon(Icons.rule),
                      label: const Text('Review'),
                    ),
                  ),
                ],
              ],
            ),
            // Purchase Request entry points. Offered per role rather than to
            // everybody, so the development home mirrors the navigation map of
            // spec §4.2 instead of listing every screen to every user.
            if (session.value?.canManagePurchaseRequest ?? false) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('homePurchaseRequests'),
                  onPressed: () =>
                      context.pushNamed(AppRoutes.purchaseRequestsName),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Purchase Request'),
                ),
              ),
            ],
            if (session.value?.canProcessPurchaseRequest ?? false) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('homeWarehousePurchaseRequests'),
                  onPressed: () => context.pushNamed(
                    AppRoutes.warehousePurchaseRequestsName,
                  ),
                  icon: const Icon(Icons.inbox_outlined),
                  label: const Text('PR Masuk (Warehouse)'),
                ),
              ),
            ],
            // Delivery Order entry points, per role for the same reason: the
            // warehouse prepares and ships, the branch only reads what is on its
            // way (§27/§29).
            if (session.value?.canProcessPurchaseRequest ?? false) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('homeWarehouseDeliveryOrders'),
                  onPressed: () =>
                      context.pushNamed(AppRoutes.warehouseDeliveryOrdersName),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Pengiriman (Warehouse)'),
                ),
              ),
            ],
            if (session.value?.canManagePurchaseRequest ?? false) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('homeBranchDeliveries'),
                  onPressed: () => context.pushNamed(AppRoutes.deliveriesName),
                  icon: const Icon(Icons.move_to_inbox_outlined),
                  label: const Text('Pengiriman Masuk'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('homeBranchGoodReceipts'),
                  onPressed: () => context.pushNamed(AppRoutes.receiptsName),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Penerimaan'),
                ),
              ),
            ],
            // Distribusi. Offered to the Kepala Cabang alone (spec §3.1), which is
            // also what `canDistribute` says — the button and the route guard read the
            // same predicate rather than two similar-looking ones.
            if (session.value?.canDistribute ?? false) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('homeBranchDistributions'),
                  onPressed: () =>
                      context.pushNamed(AppRoutes.distributionsName),
                  icon: const Icon(Icons.outbound_outlined),
                  label: const Text('Distribusi'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const DistributionDashboardCards(),
            ],
            // Good Receipt's warehouse side is read-only: the posted receipts and
            // the selisih/retur queue (§33). No create, decide or post route
            // exists for them at all.
            if (session.value?.canProcessPurchaseRequest ?? false) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('homeWarehouseGoodReceipts'),
                  onPressed: () =>
                      context.pushNamed(AppRoutes.warehouseGoodReceiptsName),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Penerimaan Cabang'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.summary,
    required this.isSeeding,
    required this.onSeed,
  });

  final MasterSummary summary;
  final bool isSeeding;
  final Future<void> Function() onSeed;

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Belum ada data',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Database lokal masih kosong. Jalankan seed pengembangan '
                'untuk membuat cabang, ruangan, pengguna, barang, batch, dan '
                'saldo awal Warehouse Pusat melalui ledger.',
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: isSeeding ? null : onSeed,
                icon: isSeeding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  isSeeding
                      ? 'Menjalankan seed…'
                      : 'Jalankan Seed Pengembangan',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.1,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      children: [
        StatusCard(
          label: 'Cabang',
          value: '${summary.branches}',
          icon: Icons.apartment,
        ),
        StatusCard(
          label: 'Ruangan',
          value: '${summary.rooms}',
          icon: Icons.meeting_room,
        ),
        StatusCard(
          label: 'Barang',
          value: '${summary.items}',
          icon: Icons.inventory_2,
        ),
      ],
    );
  }
}

class _WarehouseBalanceSection extends ConsumerWidget {
  const _WarehouseBalanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(warehouseBalancesProvider);
    final now = DateTime.now().toUtc();

    return balances.when(
      loading: () =>
          const _LoadingBlock(message: 'Memuat saldo Warehouse Pusat…'),
      error: (error, _) => ErrorNotice(
        message: describeFailure(error),
        onRetry: () => ref.invalidate(warehouseLocationProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Belum ada saldo di Warehouse Pusat. Jalankan seed '
                'pengembangan terlebih dahulu.',
              ),
            ),
          );
        }

        return Card(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(),
                _BalanceTile(balance: rows[i], now: now),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Makes the operational timezone explicit, so nobody reads a displayed time as
/// device time (T-2).
class _OperationalTimeZoneNote extends StatelessWidget {
  const _OperationalTimeZoneNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          Icons.schedule,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'Zona waktu operasional: ${AppDateTimeFormatter.timeZoneLabel}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.balance, required this.now});

  final StockBalanceView balance;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      title: Text(balance.itemName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            balance.batchNo == null
                ? balance.sku
                : '${balance.sku} · Batch ${balance.batchNo}',
            style: theme.textTheme.bodySmall,
          ),
          if (balance.hasExpiry) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _Tag(label: 'Ber-ED', color: AppColors.gold),
                ExpiryBadge(balance: balance, now: now),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            // The stored instant is UTC; the formatter converts it to GMT+8.
            'Diperbarui ${AppDateTimeFormatter.dateTimeWithZone(balance.updatedAt)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      // `Quantity.formatWithUnit` drops trailing zeros, so a whole balance
      // shows as `10 pcs` and never `10.0`, and a decimal one as `0.5 box`.
      trailing: Text(
        balance.qtyOnHand.formatWithUnit(balance.unit),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
