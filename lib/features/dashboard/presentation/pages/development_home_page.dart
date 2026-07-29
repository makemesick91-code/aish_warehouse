import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../inventory/domain/models/inventory_models.dart';
import '../../../inventory/presentation/widgets/expiry_badge.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
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
        ],
      ),
      trailing: Text(
        '${balance.qtyOnHand} ${balance.unit}',
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

/// Turns a thrown object into an Indonesian message. Business failures already
/// carry one; anything else falls back to a generic sentence so users never see
/// a raw stack trace.
String describeFailure(Object error) {
  if (error is AppFailure) return error.message;
  return 'Terjadi kesalahan tak terduga. Silakan coba lagi.';
}
