import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/delivery_models.dart';
import '../../../good_receipt/presentation/widgets/good_receipt_entry_action.dart';
import '../providers/delivery_providers.dart';
import '../widgets/delivery_expiry_badges.dart';
import '../widgets/delivery_order_status_chip.dart';
import '../widgets/shipment_progress_bar.dart';

/// One Delivery Order, read-only, for either reader.
///
/// The same page serves the warehouse and the branch, and the difference between
/// them is entirely in which provider it watches — which in turn decides whether
/// the document is fetched at all. A branch reader's stream carries both the branch
/// predicate and the status predicate in SQL, so a `preparing` document or another
/// branch's shipment never reaches this widget tree (§29).
///
/// Neither reader can change the shipment from here:
///
/// * editing lives on `DeliveryOrderFormPage`, behind a route whose guard
///   additionally requires the document to still be `preparing`;
/// * `shipped → received` is still not something this page writes. What it now
///   offers the *branch* is [GoodReceiptEntryAction] — a link to the Good Receipt
///   that performs the transition as a consequence of being posted (G-G1). There is
///   no "Mark Received" button for anybody, and the warehouse sees no receive
///   affordance at all: they ship, the branch receives (G-R4).
class DeliveryOrderDetailPage extends ConsumerWidget {
  const DeliveryOrderDetailPage({
    super.key,
    required this.doId,
    required this.branchScoped,
  });

  final String doId;

  /// `true` for the Kepala Cabang's read-only view, `false` for the warehouse's.
  final bool branchScoped;

  static const Key linesKey = ValueKey('deliveryDetailLines');
  static const Key notFoundKey = ValueKey('deliveryDetailNotFound');
  static const Key editKey = ValueKey('deliveryDetailEdit');
  static const Key waybillKey = ValueKey('deliveryDetailWaybill');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = branchScoped
        ? ref.watch(branchDeliveryDetailProvider(doId))
        : ref.watch(warehouseDeliveryDetailProvider(doId));
    final nowUtc = ref.watch(deliveryClockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Pengiriman'),
        actions: [
          IconButton(
            key: DeliveryOrderDetailPage.waybillKey,
            tooltip: 'Lihat Surat Jalan',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.pushNamed(
              branchScoped
                  ? AppRoutes.deliveryWaybillName
                  : AppRoutes.warehouseDeliveryOrderWaybillName,
              pathParameters: {'id': doId},
            ),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
        data: (order) {
          if (order == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Card(
                key: DeliveryOrderDetailPage.notFoundKey,
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('Surat Jalan tidak ditemukan.'),
                ),
              ),
            );
          }

          return ListView(
            key: DeliveryOrderDetailPage.linesKey,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _Header(detail: order),
              if (!branchScoped && order.isEditable)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: OutlinedButton.icon(
                    key: DeliveryOrderDetailPage.editKey,
                    onPressed: () => context.pushNamed(
                      AppRoutes.warehouseDeliveryOrderEditName,
                      pathParameters: {'id': doId},
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Ubah alokasi'),
                  ),
                ),
              // Good Receipt's entry point, and only on the branch's own view of a
              // shipment that has actually been sent (G-G1). The warehouse never sees
              // it: they ship, the branch receives, and offering the button to both
              // would be the segregated duty G-R4 exists to keep apart.
              if (branchScoped && order.status.isShipped)
                GoodReceiptEntryAction(deliveryOrderId: doId),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  'Barang dikirim',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (order.lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('Belum ada barang yang dialokasikan.'),
                    ),
                  ),
                )
              else
                for (final line in order.lines)
                  _LineCard(line: line, nowUtc: nowUtc),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  'Progres Purchase Request',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final entry in order.progress)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.itemName} · ${entry.sku}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          ShipmentProgressBar(progress: entry, dense: true),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final DeliveryOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = detail.summary;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
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
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  DeliveryOrderStatusChip(status: summary.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('PR ${summary.prDocNumber}'),
              Text('${summary.branchCode} · ${summary.branchName}'),
              if ((summary.branchAddress ?? '').isNotEmpty)
                Text(
                  summary.branchAddress!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Text(
                'Disiapkan ${summary.preparedByName} · '
                '${AppDateTimeFormatter.dateTimeWithZone(summary.order.createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (summary.order.shippedAt != null)
                Text(
                  'Dikirim ${summary.shippedByName ?? '—'} · '
                  '${AppDateTimeFormatter.dateTimeWithZone(summary.order.shippedAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if ((summary.order.note ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text('Catatan: ${summary.order.note}'),
                ),
              const SizedBox(height: AppSpacing.sm),
              DeliveryOrderStatusNote(status: summary.status),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${detail.lines.length} baris',
                    style: theme.textTheme.bodySmall,
                  ),
                  SyncStatusTag(status: summary.order.syncStatus),
                  if (detail.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (summary.branchIsHistorical) 'Cabang',
                        if (summary.preparedByIsHistorical) 'Petugas',
                        if (detail.lines.any((line) => line.itemIsHistorical))
                          'Barang',
                        if (detail.lines.any((line) => line.batchIsHistorical))
                          'Batch',
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

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.nowUtc});

  final DeliveryOrderLine line;
  final DateTime nowUtc;

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
        key: ValueKey('deliveryDetailLine-${line.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.itemName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${line.sku} · Diminta '
                '${line.requestedQty.formatWithUnit(line.unit)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Dikirim ${line.shippedQty.formatWithUnit(line.unit)}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (line.batchNo != null && line.expiryDate != null)
                    BatchExpiryBadge(
                      batchNo: line.batchNo!,
                      expiryDate: line.expiryDate!,
                      expiryAlertDays: line.expiryAlertDays,
                      nowUtc: nowUtc,
                    )
                  else
                    Text(
                      'Tanpa batch',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
              if (line.hasFefoOverride)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: FefoOverrideBadge(reason: line.fefoOverrideReason!),
                ),
              if (line.nearExpiryConfirmed)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: NearExpiryConfirmedBadge(note: line.nearExpiryNote),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
