import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../purchase_request/presentation/providers/purchase_request_providers.dart';
import '../../domain/models/good_receipt_models.dart';
import '../providers/good_receipt_providers.dart';
import '../widgets/good_receipt_badges.dart';

/// Selisih GR dari Cabang — the warehouse's discrepancy and return queue (§33,
/// G-G3/G-G5).
///
/// **Read-only, and that is the whole design.** There is no button here that adds stock
/// back to the warehouse, no button that marks a return complete, and no way to remove a
/// row. Every one of those would create stock nobody has counted: the goods a branch
/// refused are physically on the branch's counter, and the warehouse's balance is
/// correct as it stands until somebody receives them back. That receiving is a physical
/// return document, and it belongs to a later milestone.
///
/// What the page *is*, is a derived read of the receipt lines themselves — no
/// `discrepancies` table, no writer, and therefore no second version of the numbers that
/// could disagree with the receipts they came from.
///
/// Two kinds of row, distinguished because they need different follow-up:
///
/// * **Kekurangan** — accepted, but less arrived than was sent. Nothing to return; the
///   warehouse investigates where it went.
/// * **Perlu Retur** — refused outright. The goods are at the branch and have to travel
///   back.
class WarehouseGoodReceiptDiscrepancyPage extends ConsumerWidget {
  const WarehouseGoodReceiptDiscrepancyPage({super.key});

  static const Key listKey = ValueKey('warehouseDiscrepancyList');
  static const Key emptyKey = ValueKey('warehouseDiscrepancyEmpty');
  static const Key searchKey = ValueKey('warehouseDiscrepancySearch');
  static const Key summaryKey = ValueKey('warehouseDiscrepancySummary');

  static Key rowKeyFor(String lineId) =>
      ValueKey('warehouseDiscrepancyRow-$lineId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(warehouseDiscrepancyQueueProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Selisih GR dari Cabang')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(warehouseDiscrepancyQueueProvider(null)),
        child: ListView(
          key: listKey,
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                key: searchKey,
                onChanged: ref
                    .read(warehouseDiscrepancySearchProvider.notifier)
                    .update,
                decoration: const InputDecoration(
                  labelText: 'Cari nomor GR / SJ / PR / cabang / barang',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const _KindFilterRow(),
            const _BranchFilterRow(),
            const _DateFilterRow(),
            rows.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(
                  message: describeFailure(error),
                  onRetry: () =>
                      ref.invalidate(warehouseDiscrepancyQueueProvider(null)),
                ),
              ),
              data: (entries) => entries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Card(
                        key: emptyKey,
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            'Belum ada selisih penerimaan dari cabang.',
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        _SummaryCard(entries: entries),
                        for (final entry in entries)
                          _DiscrepancyTile(entry: entry),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.entries});

  final List<GoodReceiptDiscrepancy> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final returns = entries.where((entry) => entry.returnRequired).length;
    final shortages = entries.length - returns;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: WarehouseGoodReceiptDiscrepancyPage.summaryKey,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entries.length} baris selisih',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  GoodReceiptPill(
                    label: '$shortages kekurangan',
                    color: AppColors.warning,
                    icon: Icons.remove_circle_outline,
                  ),
                  GoodReceiptPill(
                    label: '$returns perlu retur',
                    color: AppColors.danger,
                    icon: Icons.assignment_return_outlined,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Daftar ini bersifat laporan. Barang yang ditolak belum kembali '
                'ke saldo Warehouse — pengembalian fisik dicatat pada dokumen '
                'retur tersendiri.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscrepancyTile extends StatelessWidget {
  const _DiscrepancyTile({required this.entry});

  final GoodReceiptDiscrepancy entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: WarehouseGoodReceiptDiscrepancyPage.rowKeyFor(entry.lineId),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.itemName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GoodReceiptDiscrepancyBadge(kind: entry.kind),
                ],
              ),
              Text(
                '${entry.sku} · ${entry.unit}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'GR ${entry.grDocNumber} · SJ ${entry.doDocNumber} · '
                'PR ${entry.prDocNumber}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${entry.branchCode} · ${entry.branchName}',
                style: theme.textTheme.bodySmall,
              ),
              if (entry.batchNo != null)
                Text(
                  'Batch ${entry.batchNo}'
                  '${entry.expiryDate == null ? '' : ' · ED ${AppDateTimeFormatter.civilDate(entry.expiryDate!)}'}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dikirim ${entry.shippedQty.formatWithUnit(entry.unit)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Diterima ${entry.receivedQty.formatWithUnit(entry.unit)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Selisih '
                      '${entry.discrepancyQty.formatWithUnit(entry.unit)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
              if (entry.rejectReason != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        entry.rejectReason!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Diposting '
                    '${AppDateTimeFormatter.dateTimeWithZone(entry.postedAtUtc)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  GoodReceiptLineStatusChip(status: entry.lineStatus),
                  if (entry.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (entry.branchIsHistorical) 'Cabang',
                        if (entry.itemIsHistorical) 'Barang',
                      ].join(', '),
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

class _KindFilterRow extends ConsumerWidget {
  const _KindFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(warehouseDiscrepancyKindFilterProvider);
    final notifier = ref.read(warehouseDiscrepancyKindFilterProvider.notifier);

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
          for (final kind in GoodReceiptDiscrepancyKind.values) ...[
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              key: ValueKey('discrepancyKindFilter-${kind.name}'),
              label: Text(kind.label),
              selected: selected == kind,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => notifier.select(kind),
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
    final selected = ref.watch(warehouseDiscrepancyBranchFilterProvider);
    final notifier = ref.read(
      warehouseDiscrepancyBranchFilterProvider.notifier,
    );

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
                      key: ValueKey('discrepancyBranchFilter-${branch.code}'),
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

/// A posted-date window, as three chips rather than a date picker.
///
/// The three windows the warehouse actually asks for — today, this week, everything —
/// answered without a dialog. The bounds are UTC instants derived from operational days
/// (T-3), so "hari ini" means the GMT+8 day rather than the device's.
class _DateFilterRow extends ConsumerWidget {
  const _DateFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(warehouseDiscrepancyDateFilterProvider);
    final notifier = ref.read(warehouseDiscrepancyDateFilterProvider.notifier);
    final nowUtc = ref.watch(goodReceiptClockProvider)();

    // Which chip is lit is decided by comparing the stored `from` against the instant each
    // chip would set, rather than by "is a range selected at all" — otherwise choosing
    // *7 hari* would light *Hari ini* as well.
    final today = _startOfOperationalDay(nowUtc);
    final weekAgo = _startOfOperationalDay(
      nowUtc.subtract(const Duration(days: 6)),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          FilterChip(
            key: const ValueKey('discrepancyDateFilter-all'),
            label: const Text('Semua tanggal'),
            selected: range.from == null && range.to == null,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.clear(),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterChip(
            key: const ValueKey('discrepancyDateFilter-today'),
            label: const Text('Hari ini'),
            selected: range.from == today,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.select(from: today, to: nowUtc),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterChip(
            key: const ValueKey('discrepancyDateFilter-week'),
            label: const Text('7 hari'),
            selected: range.from == weekAgo,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.select(from: weekAgo, to: nowUtc),
          ),
        ],
      ),
    );
  }

  /// First UTC instant of the operational day [utc] falls on.
  ///
  /// Through [AppTimeZone] rather than by subtracting eight hours here: that class is
  /// the single place the operational offset lives (T-5), and a second copy of the
  /// arithmetic is how a filter comes to disagree with the badges beside it.
  DateTime _startOfOperationalDay(DateTime utc) =>
      AppTimeZone.startOfOperationalDayUtc(AppTimeZone.operationalDate(utc));
}
