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
import '../../domain/models/purchase_request_models.dart';
import '../providers/purchase_request_providers.dart';
import '../widgets/purchase_request_status_chip.dart';

/// Purchase Request — the Kepala Cabang's own requests (spec §4.2, §24.1).
///
/// Every row here belongs to the acting user's branch, because the provider behind
/// it is scoped by [actingBranchIdProvider] and the branch travels into the SQL
/// predicate (G-R2). There is no "all branches" affordance to accidentally leave
/// on.
class PurchaseRequestListPage extends ConsumerStatefulWidget {
  const PurchaseRequestListPage({super.key});

  /// Lets tests address the list without matching on prose.
  static const Key listKey = ValueKey('purchaseRequestList');

  @override
  ConsumerState<PurchaseRequestListPage> createState() =>
      _PurchaseRequestListPageState();
}

class _PurchaseRequestListPageState
    extends ConsumerState<PurchaseRequestListPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A branch tablet is left open for days. Coming back to the foreground is
    // exactly when the cached operational week may have gone stale, which would
    // otherwise offer last week's eligibility window on the create wizard.
    if (state == AppLifecycleState.resumed) _refreshPeriod();
  }

  void _refreshPeriod() {
    ref.invalidate(purchaseRequestEligiblePeriodsProvider);
    ref.invalidate(eligibleOpnamesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(branchPurchaseRequestListProvider);
    final active = ref.watch(activeBranchPurchaseRequestProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Request')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _refreshPeriod();
          context.pushNamed(AppRoutes.purchaseRequestNewName);
        },
        icon: const Icon(Icons.add),
        label: const Text('Buat Purchase Request'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(branchPurchaseRequestListProvider);
          ref.invalidate(activeBranchPurchaseRequestProvider);
          _refreshPeriod();
        },
        child: ListView(
          key: PurchaseRequestListPage.listKey,
          padding: const EdgeInsets.only(bottom: AppSpacing.xl * 2),
          children: [
            const _BranchHeader(),
            _ActiveRequestNotice(active: active),
            const _StatusFilterRow(),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                'Riwayat Purchase Request',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            requests.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(
                  message: describeFailure(error),
                  onRetry: () =>
                      ref.invalidate(branchPurchaseRequestListProvider),
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? const _EmptyHistory()
                  : Column(
                      children: [
                        for (final summary in rows)
                          _RequestTile(summary: summary),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which branch the list is showing, and the operational week it is read in.
class _BranchHeader extends ConsumerWidget {
  const _BranchHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final period = ref.watch(currentPurchaseRequestPeriodProvider);
    final requests = ref.watch(branchPurchaseRequestListProvider).value;
    final branchName = requests?.isNotEmpty ?? false
        ? requests!.first.branchName
        : null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Periode ${period.label}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                branchName == null
                    ? 'Permintaan barang dari cabang Anda ke Warehouse Pusat.'
                    : 'Cabang $branchName · permintaan barang ke Warehouse '
                          'Pusat.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Zona waktu operasional: '
                    '${AppDateTimeFormatter.timeZoneLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

/// G-P4 made visible: the branch may have only one order in flight, so say which.
class _ActiveRequestNotice extends StatelessWidget {
  const _ActiveRequestNotice({required this.active});

  final AsyncValue<PurchaseRequest?> active;

  /// Lets tests assert the notice without matching on prose.
  static const Key noticeKey = ValueKey('activePurchaseRequestNotice');

  @override
  Widget build(BuildContext context) {
    final request = active.value;
    if (request == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        key: noticeKey,
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Ada permintaan aktif: ${request.docNumber} '
                '(${request.status.label}). Selesaikan atau batalkan permintaan '
                'itu sebelum mengirim permintaan baru.',
                style: theme.textTheme.bodySmall,
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
    final selected = ref.watch(branchPurchaseRequestStatusFilterProvider);
    final notifier = ref.read(
      branchPurchaseRequestStatusFilterProvider.notifier,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Semua'),
            selected: selected == null,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.clear(),
          ),
          for (final status in PurchaseRequestStatus.values) ...[
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              key: ValueKey('prStatusFilter-${status.dbValue}'),
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

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.summary});

  final PurchaseRequestSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = summary.request;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        child: InkWell(
          key: ValueKey('prTile-${summary.id}'),
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.pushNamed(
            AppRoutes.purchaseRequestDetailName,
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
                  // The stored instant is UTC; the formatter converts to GMT+8.
                  'Dibuat ${AppDateTimeFormatter.dateTimeWithZone(request.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  request.neededDate == null
                      ? 'Tanggal dibutuhkan: —'
                      // A civil date is printed exactly as stored (T-9).
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
                    Text(
                      '${summary.linkedOpnameCount} opname acuan',
                      style: theme.textTheme.bodySmall,
                    ),
                    SyncStatusTag(status: request.syncStatus),
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
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  static const Key emptyKey = ValueKey('purchaseRequestEmptyState');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Card(
        key: emptyKey,
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Belum ada Purchase Request'),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Purchase Request dibuat dari hasil stok opname minggu '
                'berjalan atau minggu sebelumnya. Tekan "Buat Purchase '
                'Request" untuk memulai.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The key the empty state renders under, exposed for widget tests.
const Key purchaseRequestEmptyStateKey = _EmptyHistory.emptyKey;

/// The key the active-request notice renders under, exposed for widget tests.
const Key activePurchaseRequestNoticeKey = _ActiveRequestNotice.noticeKey;
