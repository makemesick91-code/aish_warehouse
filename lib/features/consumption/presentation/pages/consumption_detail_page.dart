import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../../inventory/presentation/widgets/stock_card_list.dart';
import '../../domain/models/consumption_models.dart';
import '../providers/consumption_providers.dart';
import '../widgets/consumption_badges.dart';
import 'consumption_list_page.dart' show formatTotalsByUnit;

/// One Pemakaian, read-only (§30/§31).
///
/// Shared by both audiences, because a posted document says the same thing whoever is
/// reading it: the nurse who recorded it opens it from their own list, the Kepala Cabang
/// from the branch history. Which of them reached it decides *which provider* resolved the
/// document — [consumptionDetailProvider] switches on the acting role — and nothing on
/// this page needs to know which one won.
///
/// ### What is deliberately absent
///
/// There is **no** edit control, no remove control, no post button, no un-post, no
/// approval and no destination anywhere on this screen. §30 lists them, and their absence
/// is the assertion: a posted consumption is read-only permanently (G-S2), and a
/// correction is a reversal movement against the ledger rather than an edit here.
///
/// A *draft* also renders here when reached from the branch history — which cannot
/// happen, because that scope is `posted`-only (§14) — and when a nurse taps a draft from
/// their own list, the list sends them to the editor instead. Rendering one read-only is
/// therefore the safe fallback rather than a path anybody takes.
class ConsumptionDetailPage extends ConsumerWidget {
  const ConsumptionDetailPage({super.key, required this.consumptionId});

  final String consumptionId;

  static const Key detailKey = ValueKey('consumptionDetail');
  static const Key headerKey = ValueKey('consumptionDetailHeader');
  static const Key summaryKey = ValueKey('consumptionDetailSummary');
  static const Key linesKey = ValueKey('consumptionDetailLines');
  static const Key timelineKey = ValueKey('consumptionDetailTimeline');
  static const Key ledgerKey = ValueKey('consumptionDetailLedger');
  static const Key deniedKey = ValueKey('consumptionDetailDenied');
  static const Key positionCardKey = ValueKey('consumptionPositionStockCard');

  static Key lineKeyFor(String lineId) =>
      ValueKey('consumptionDetailLine-$lineId');

  /// The "open this position's kartu stok" affordance on one line.
  static Key stockCardButtonKeyFor(String lineId) =>
      ValueKey('consumptionStockCardButton-$lineId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(consumptionDetailProvider(consumptionId));
    final nowUtc = ref.watch(consumptionClockProvider)();

    return detail.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Pemakaian')),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
      ),
      data: (document) {
        if (document == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Pemakaian')),
            body: const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: ConsumptionNotice(
                key: deniedKey,
                title: 'Dokumen tidak tersedia',
                message: accessDeniedMessage,
                icon: Icons.lock_outline,
              ),
            ),
          );
        }

        final progress = document.progressOn(nowUtc);

        return Scaffold(
          key: detailKey,
          appBar: AppBar(
            title: Text(document.consumption.docNumber),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Center(
                  child: ConsumptionStatusChip(status: document.status),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _Header(document: document),
              const SizedBox(height: AppSpacing.md),
              _Summary(document: document, progress: progress),
              const SizedBox(height: AppSpacing.md),
              _Timeline(document: document),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Barang dipakai',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Column(
                key: linesKey,
                children: [
                  for (final line in document.orderedLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _LineRow(
                        line: line,
                        nowUtc: nowUtc,
                        consumptionId: document.id,
                        roomLabel: document.room.label,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _LedgerReference(document: document),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.document});

  final ConsumptionDetail document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consumption = document.consumption;
    final summary = document.summary;

    return Card(
      key: ConsumptionDetailPage.headerKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(consumption.docNumber, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${summary.branchName} · ${document.room.label}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Dicatat oleh ${summary.createdByName}',
              style: theme.textTheme.bodySmall,
            ),
            if (summary.postedByName != null)
              Text(
                'Diposting oleh ${summary.postedByName}',
                style: theme.textTheme.bodySmall,
              ),
            if (consumption.hasNote) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Catatan umum', style: theme.textTheme.labelMedium),
              Text(consumption.note!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SyncStatusTag(status: consumption.syncStatus),
                if (summary.usesHistoricalMaster)
                  HistoricalMasterBadge.forDetail(
                    [
                      if (summary.roomIsHistorical) 'Ruangan',
                      if (summary.branchIsHistorical) 'Cabang',
                      if (summary.createdByIsHistorical) 'Perawat',
                      if (summary.postedByIsHistorical) 'Pemosting',
                    ].join(', '),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The counters §30 asks for: line count, per-unit totals, the room's balance effect and
/// how many near-expiry positions were used.
class _Summary extends StatelessWidget {
  const _Summary({required this.document, required this.progress});

  final ConsumptionDetail document;
  final ConsumptionProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: ConsumptionDetailPage.summaryKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ringkasan', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(progress.label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Total: ${formatTotalsByUnit(document.totalQuantityByUnit)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              // The whole shape of the movement, in one sentence: the room falls and
              // nothing anywhere rises (§19).
              'Efek stok: ${document.room.label} berkurang; tidak ada lokasi '
              'tujuan.',
              style: theme.textTheme.bodySmall,
            ),
            if (progress.hasNearExpiry) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Posisi segera kedaluwarsa yang dipakai: '
                '${progress.nearExpiryCount}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The two events this document has, in order (§30).
class _Timeline extends StatelessWidget {
  const _Timeline({required this.document});

  final ConsumptionDetail document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consumption = document.consumption;
    final postedAt = consumption.postedAt;

    return Card(
      key: ConsumptionDetailPage.timelineKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Riwayat dokumen', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _TimelineRow(
              icon: Icons.edit_note,
              label: 'Dibuat',
              detail: AppDateTimeFormatter.dateTimeWithZone(
                consumption.createdAt,
              ),
            ),
            _TimelineRow(
              icon: postedAt == null
                  ? Icons.radio_button_unchecked
                  : Icons.check_circle_outline,
              label: 'Diposting',
              detail: postedAt == null
                  ? 'Belum diposting'
                  : AppDateTimeFormatter.dateTimeWithZone(postedAt),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              detail,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.nowUtc,
    required this.consumptionId,
    required this.roomLabel,
  });

  final ConsumptionLine line;
  final DateTime nowUtc;
  final String consumptionId;
  final String roomLabel;

  /// Opens the **kartu stok** of this position at the document's room (§32).
  ///
  /// A sheet rather than a route, and deliberately: a new route would need its own guard and
  /// its own scope, whereas a sheet opened from an already-guarded page inherits both. The
  /// room comes from the document, which came from the acting role's own scoped query — so
  /// nobody reaches a card for a room they could not already read.
  Future<void> _openStockCard(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PositionStockCardSheet(
        consumptionId: consumptionId,
        line: line,
        roomLabel: roomLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: ConsumptionDetailPage.lineKeyFor(line.id),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(line.itemName, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  line.qty.formatWithUnit(line.unit),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            Text(
              line.isBatched
                  ? '${line.sku} · batch ${line.batchNo}'
                  : '${line.sku} · tanpa batch',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConsumptionExpiryBadge(
                  expiryDate: line.expiryDate,
                  expiryAlertDays: line.expiryAlertDays,
                  nowUtc: nowUtc,
                ),
                if (line.usesHistoricalMaster)
                  HistoricalMasterBadge.forDetail(
                    [
                      if (line.itemIsHistorical) 'Barang',
                      if (line.batchIsHistorical) 'Batch',
                    ].join(', '),
                  ),
              ],
            ),
            if (line.hasNote) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(line.note!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ConsumptionDetailPage.stockCardButtonKeyFor(line.id),
                onPressed: () => _openStockCard(context),
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('Kartu stok posisi ini'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The **kartu stok** of one position at the document's room (§32).
///
/// Shows every movement that touched `(item, batch)` at that room — the Distribusi that
/// brought the stock in, the opname adjustment that corrected it, the Pemakaian that used it,
/// the Pemusnahan that destroyed it. That mix is the point: a reader can see where a balance
/// went rather than only what this one document did.
///
/// Rows whose document belongs to somebody else still appear, with
/// `StockMovementPresenter.unresolvedDocumentLabel` instead of a number: the stock moved, and
/// a card that hid the row would not add up (§6).
class _PositionStockCardSheet extends ConsumerWidget {
  const _PositionStockCardSheet({
    required this.consumptionId,
    required this.line,
    required this.roomLabel,
  });

  final String consumptionId;
  final ConsumptionLine line;
  final String roomLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(
      consumptionPositionStockCardProvider((
        consumptionId: consumptionId,
        itemId: line.itemId,
        batchId: line.batchId,
      )),
    );

    return SafeArea(
      key: ConsumptionDetailPage.positionCardKey,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kartu Stok', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    line.isBatched
                        ? '${line.itemName} · batch ${line.batchNo}'
                        : '${line.itemName} · tanpa batch',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(roomLabel, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: ErrorNotice(message: describeFailure(error)),
                ),
                data: (rows) => SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: StockCardList(
                    entries: rows,
                    emptyMessage:
                        'Belum ada pergerakan stok tercatat untuk posisi ini '
                        'di ruangan ini.',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ledger rows this document wrote, rendered as a stock card (§30/§32).
///
/// Until this hardening the section printed the raw `movement_type` and `ref_doc_type` codes
/// — `consumption`, `CONS` — which told a developer what to grep for and a nurse nothing. It
/// now renders the **actual movements** through `StockCardList`, so the words, the quantities,
/// the actor and the GMT+8 timestamps all come from the shared presenter and formatter rather
/// than from string interpolation here.
class _LedgerReference extends ConsumerWidget {
  const _LedgerReference({required this.document});

  final ConsumptionDetail document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (!document.isPosted) {
      return const ConsumptionNotice(
        key: ConsumptionDetailPage.ledgerKey,
        title: 'Belum tercatat di ledger',
        message:
            'Dokumen ini masih draft, sehingga belum ada pergerakan stok yang '
            'tercatat.',
        icon: Icons.receipt_long_outlined,
      );
    }

    final entries = ref.watch(consumptionLedgerProvider(document.id));

    return Column(
      key: ConsumptionDetailPage.ledgerKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pergerakan stok', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        entries.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => ErrorNotice(message: describeFailure(error)),
          data: (rows) => StockCardList(
            entries: rows,
            // No `locationId`: a document's own rows all leave the same room, so a `−` sign
            // beside every one of them would add nothing. The location line already says
            // where the stock went.
            emptyMessage:
                'Tidak ada pergerakan stok yang tercatat untuk dokumen ini.',
          ),
        ),
      ],
    );
  }
}
