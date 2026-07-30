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
import '../../domain/models/good_receipt_models.dart';
import '../../domain/services/good_receipt_reminder_policy.dart';
import '../providers/good_receipt_providers.dart';
import '../widgets/good_receipt_badges.dart';

/// Penerimaan — the Kepala Cabang's Good Receipt section (§30).
///
/// One screen, three groups, in the order the work arrives:
///
/// 1. **shipments to check in** — `shipped` Delivery Orders with no receipt yet, and
///    `checking` receipts already started. Sorted overdue first, then due soon, then
///    oldest shipment (G-G6), because a list ordered by document number buries the one
///    row that matters.
/// 2. **posted receipts** — the branch's own history.
///
/// The reminder badges and the sort order are both resolved from one injected instant,
/// so a row cannot be badged *overdue* and sorted below a *due soon* one because the
/// two were judged a microsecond apart (T-7).
class BranchGoodReceiptListPage extends ConsumerWidget {
  const BranchGoodReceiptListPage({super.key});

  static const Key listKey = ValueKey('branchGoodReceiptList');
  static const Key emptyKey = ValueKey('branchGoodReceiptEmpty');
  static const Key awaitingSectionKey = ValueKey('branchGoodReceiptAwaiting');
  static const Key historySectionKey = ValueKey('branchGoodReceiptHistory');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(branchGoodReceiptRemindersProvider(null));
    final awaiting = ref.watch(branchAwaitingDeliveriesProvider(null));
    final receipts = ref.watch(branchGoodReceiptListProvider(null));
    final nowUtc = ref.watch(goodReceiptClockProvider)();

    final awaitingById = {
      for (final row in awaiting.value ?? const <GoodReceiptAwaitingDelivery>[])
        row.doId: row,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Penerimaan')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(branchAwaitingDeliveriesProvider(null));
          ref.invalidate(branchGoodReceiptListProvider(null));
        },
        child: ListView(
          key: listKey,
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            if (awaiting.hasError)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(
                  message: describeFailure(awaiting.error!),
                  onRetry: () =>
                      ref.invalidate(branchAwaitingDeliveriesProvider(null)),
                ),
              ),
            if (awaiting.isLoading && !awaiting.hasValue)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (reminders.isNotEmpty) ...[
              _SectionHeader(
                sectionKey: awaitingSectionKey,
                title: 'Menunggu diperiksa',
                trailing: '${reminders.length}',
              ),
              for (final reminder in reminders)
                _AwaitingTile(
                  reminder: reminder,
                  row: awaitingById[reminder.doId],
                  nowUtc: nowUtc,
                ),
            ],
            receipts.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(
                  message: describeFailure(error),
                  onRetry: () =>
                      ref.invalidate(branchGoodReceiptListProvider(null)),
                ),
              ),
              data: (rows) {
                final posted = rows
                    .where((summary) => summary.receipt.isPosted)
                    .toList(growable: false);
                if (reminders.isEmpty && posted.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Card(
                      key: emptyKey,
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'Belum ada pengiriman yang perlu diperiksa untuk '
                          'cabang ini.',
                        ),
                      ),
                    ),
                  );
                }
                if (posted.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    const _SectionHeader(
                      sectionKey: historySectionKey,
                      title: 'Riwayat penerimaan',
                    ),
                    for (final summary in posted)
                      GoodReceiptSummaryTile(
                        summary: summary,
                        nowUtc: nowUtc,
                        onTap: () => context.pushNamed(
                          AppRoutes.receiptDetailName,
                          pathParameters: {'id': summary.id},
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.sectionKey,
    required this.title,
    this.trailing,
  });

  final Key sectionKey;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: sectionKey,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// One shipment the branch still has to check in.
///
/// The action depends on whether a receipt exists: *Mulai Pemeriksaan* creates one,
/// *Lanjutkan Pemeriksaan* opens the one already open. Both routes go through the same
/// guard; this only chooses which sentence to show.
class _AwaitingTile extends ConsumerWidget {
  const _AwaitingTile({
    required this.reminder,
    required this.row,
    required this.nowUtc,
  });

  final GoodReceiptReminder reminder;
  final GoodReceiptAwaitingDelivery? row;
  final DateTime nowUtc;

  static Key tileKeyFor(String doId) => ValueKey('awaitingReceiptTile-$doId');

  static Key actionKeyFor(String doId) =>
      ValueKey('awaitingReceiptAction-$doId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final started = reminder.hasReceipt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: tileKeyFor(reminder.doId),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reminder.doDocNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GoodReceiptDeadlineBadge(
                    shippedAtUtc: reminder.shippedAtUtc,
                    nowUtc: nowUtc,
                    showWhenDue: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'PR ${reminder.prDocNumber}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${reminder.branchCode} · ${reminder.branchName}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                // Both instants are UTC in storage and rendered in operational time
                // (T-1/T-2); `toLocal()` is never called.
                'Dikirim ${AppDateTimeFormatter.dateTimeWithZone(reminder.shippedAtUtc)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '${GoodReceiptReminderPolicy.ageInHours(shippedAtUtc: reminder.shippedAtUtc, nowUtc: nowUtc)} '
                'jam sejak dikirim · '
                '${GoodReceiptDeadlineBadge.deadlineLabel(reminder.shippedAtUtc)}',
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
                    '${reminder.lineCount} baris',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (started)
                    Text(
                      '${reminder.decidedCount}/${reminder.lineCount} diperiksa',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (row?.branchIsHistorical ?? false)
                    HistoricalMasterBadge.forDetail('Cabang'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: actionKeyFor(reminder.doId),
                  onPressed: () {
                    if (started) {
                      context.pushNamed(
                        AppRoutes.receiptDetailName,
                        pathParameters: {'id': reminder.receiptId!},
                      );
                    } else {
                      context.pushNamed(
                        AppRoutes.receiptNewName,
                        pathParameters: {'deliveryOrderId': reminder.doId},
                      );
                    }
                  },
                  child: Text(
                    started ? 'Lanjutkan Pemeriksaan' : 'Mulai Pemeriksaan',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of a Good Receipt list.
///
/// Shared between the branch's history and the warehouse's cross-branch list, because
/// the facts a reader needs are the same and keeping two near-identical tiles in step by
/// hand is how they stop agreeing. What differs is only where the tap goes, which the
/// caller supplies.
class GoodReceiptSummaryTile extends StatelessWidget {
  const GoodReceiptSummaryTile({
    super.key,
    required this.summary,
    required this.nowUtc,
    required this.onTap,
  });

  final GoodReceiptSummary summary;
  final DateTime nowUtc;
  final VoidCallback onTap;

  static Key tileKeyFor(String grId) => ValueKey('goodReceiptTile-$grId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receipt = summary.receipt;
    final progress = summary.progress;

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
                    GoodReceiptStatusChip(status: summary.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'SJ ${summary.doDocNumber} · PR ${summary.prDocNumber}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '${summary.branchCode} · ${summary.branchName}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Diperiksa ${summary.receivedByName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (summary.doShippedAt != null)
                  Text(
                    'Dikirim ${AppDateTimeFormatter.dateTimeWithZone(summary.doShippedAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (receipt.postedAt != null)
                  Text(
                    'Diposting ${AppDateTimeFormatter.dateTimeWithZone(receipt.postedAt!)}',
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
                      '${progress.total} baris · ${progress.label} diperiksa',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (progress.rejected > 0)
                      GoodReceiptPill(
                        label: '${progress.rejected} ditolak',
                        color: AppColors.danger,
                        icon: Icons.close,
                      ),
                    if (progress.shortage > 0)
                      GoodReceiptPill(
                        label: '${progress.shortage} kurang',
                        color: AppColors.warning,
                        icon: Icons.remove_circle_outline,
                      ),
                    if (summary.isOverdueOn(nowUtc) &&
                        summary.doShippedAt != null)
                      GoodReceiptDeadlineBadge(
                        shippedAtUtc: summary.doShippedAt!,
                        nowUtc: nowUtc,
                      ),
                    SyncStatusTag(status: receipt.syncStatus),
                    if (summary.usesHistoricalMaster)
                      HistoricalMasterBadge.forDetail(
                        [
                          if (summary.branchIsHistorical) 'Cabang',
                          if (summary.receivedByIsHistorical) 'Petugas',
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

/// A status chip row for a receipt list. Kept here rather than inlined so the branch and
/// warehouse lists filter identically.
class GoodReceiptStatusFilterRow extends ConsumerWidget {
  const GoodReceiptStatusFilterRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(branchGoodReceiptStatusFilterProvider);
    final notifier = ref.read(branchGoodReceiptStatusFilterProvider.notifier);

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
          for (final status in GoodReceiptStatus.values) ...[
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              key: ValueKey('goodReceiptStatusFilter-${status.dbValue}'),
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
