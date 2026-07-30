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
import '../providers/delivery_providers.dart';
import '../widgets/delivery_allocation_card.dart';
import '../widgets/delivery_order_status_chip.dart';

/// The allocation editor of a `preparing` Delivery Order (§27.2/27.3/27.4).
///
/// Everything an officer may decide is here, and nothing else is:
///
/// * **No item picker.** Every card is a position the branch asked for, so G-D4 is
///   enforced by the absence of a control rather than by a validation.
/// * **Alokasikan FEFO** fills the whole document from the nearest expiry first
///   (G-E3), clamped to what is outstanding and what is on the shelf.
/// * **Kirim** flushes every pending keystroke, confirms, and posts the shipment.
///
/// The flush is the part worth spelling out. Each allocation card reports its state
/// on every change, and this screen keeps the latest per line. Pressing *Kirim*
/// saves the dirty lines **before** shipping, so an officer who types `0.5` and
/// goes straight for the button ships `0.5` rather than the quantity that happened
/// to be stored. A screen that only learned about the edit on blur would ship the
/// stale number and give no sign of it.
class DeliveryOrderFormPage extends ConsumerStatefulWidget {
  const DeliveryOrderFormPage({super.key, required this.doId});

  final String doId;

  static const Key listKey = ValueKey('deliveryFormList');
  static const Key allocateKey = ValueKey('deliveryAllocateFefo');
  static const Key shipKey = ValueKey('deliveryShipButton');
  static const Key waybillKey = ValueKey('deliveryFormWaybillButton');
  static const Key confirmShipKey = ValueKey('deliveryConfirmShip');
  static const Key cancelShipKey = ValueKey('deliveryCancelShip');
  static const Key noteFieldKey = ValueKey('deliveryNoteField');
  static const Key invalidLineNoticeKey = ValueKey('deliveryInvalidLineNotice');

  @override
  ConsumerState<DeliveryOrderFormPage> createState() =>
      _DeliveryOrderFormPageState();
}

class _DeliveryOrderFormPageState extends ConsumerState<DeliveryOrderFormPage> {
  /// The latest reported state of every line the officer has touched.
  final Map<String, DeliveryAllocationEdit> _pending = {};
  final TextEditingController _noteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _noteSeeded = false;

  /// The line whose input is not a valid quantity, so the notice can name it.
  String? _invalidLineId;

  @override
  void dispose() {
    _noteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(warehouseDeliveryDetailProvider(widget.doId));
    final drafts = ref.watch(deliveryAllocationDraftsProvider(widget.doId));
    final controller = ref.watch(deliveryOrderFormControllerProvider);
    final nowUtc = ref.watch(deliveryClockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Surat Jalan'),
        actions: [
          IconButton(
            key: DeliveryOrderFormPage.waybillKey,
            tooltip: 'Lihat Surat Jalan',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.pushNamed(
              AppRoutes.warehouseDeliveryOrderWaybillName,
              pathParameters: {'id': widget.doId},
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
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('Surat Jalan tidak ditemukan.'),
                ),
              ),
            );
          }
          if (!_noteSeeded) {
            _noteController.text = order.order.note ?? '';
            _noteSeeded = true;
          }

          return ListView(
            key: DeliveryOrderFormPage.listKey,
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _HeaderCard(detail: order),
              if (order.isEditable)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: TextField(
                    key: DeliveryOrderFormPage.noteFieldKey,
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: 'Catatan pengiriman (kurir, kendaraan)',
                    ),
                    onSubmitted: (value) => ref
                        .read(deliveryOrderFormControllerProvider.notifier)
                        .saveNote(doId: widget.doId, note: value),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              drafts.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: ErrorNotice(
                    message: describeFailure(error),
                    onRetry: () => ref.invalidate(
                      deliveryAllocationDraftsProvider(widget.doId),
                    ),
                  ),
                ),
                data: (rows) => Column(
                  children: [
                    for (final draft in rows)
                      DeliveryAllocationCard(
                        draft: draft,
                        nowUtc: nowUtc,
                        enabled: order.isEditable && !controller.isLoading,
                        onChanged: (edit) => _pending[edit.lineId] = edit,
                        onSave: _saveLine,
                        onRemove: _removeLine,
                      ),
                  ],
                ),
              ),
              if (_invalidLineId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: ErrorNotice(
                    key: DeliveryOrderFormPage.invalidLineNoticeKey,
                    message:
                        'Ada baris dengan jumlah kirim yang belum valid. '
                        'Periksa kembali jumlah pada baris yang ditandai.',
                  ),
                ),
              if (controller.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: ErrorNotice(
                    message: describeFailure(controller.error ?? ''),
                  ),
                ),
              if (order.isEditable)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      OutlinedButton.icon(
                        key: DeliveryOrderFormPage.allocateKey,
                        onPressed: controller.isLoading
                            ? null
                            : () => ref
                                  .read(
                                    deliveryOrderFormControllerProvider
                                        .notifier,
                                  )
                                  .allocateFefo(doId: widget.doId),
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Alokasikan FEFO'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.icon(
                        key: DeliveryOrderFormPage.shipKey,
                        // Disabled while an action is in flight — the loading
                        // guard that stops a double posting (§27.4).
                        onPressed: controller.isLoading || order.isEmpty
                            ? null
                            : () => _confirmAndShip(order),
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Kirim'),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveLine(DeliveryAllocationEdit edit) async {
    final qty = edit.qty;
    if (qty == null || !qty.isPositive) {
      setState(() => _invalidLineId = edit.lineId);
      return;
    }
    setState(() => _invalidLineId = null);

    await ref
        .read(deliveryOrderFormControllerProvider.notifier)
        .saveLine(
          doId: widget.doId,
          lineId: edit.lineId,
          shippedQty: qty,
          batchId: edit.batchId,
          fefoOverrideReason: edit.fefoOverrideReason,
          nearExpiryConfirmed: edit.nearExpiryConfirmed,
          nearExpiryNote: edit.nearExpiryNote,
        );
    _pending.remove(edit.lineId);
  }

  Future<void> _removeLine(String lineId) async {
    _pending.remove(lineId);
    await ref
        .read(deliveryOrderFormControllerProvider.notifier)
        .removeLine(doId: widget.doId, lineId: lineId);
  }

  /// Saves every line the officer has touched but not saved.
  ///
  /// Returns `false` when one of them cannot be saved — an invalid quantity, or a
  /// rule the use case refused — in which case shipping must not proceed. The
  /// screen scrolls to the top so the error notice is in view rather than leaving
  /// the officer with a button that did nothing (§27.4 step 3).
  Future<bool> _flushPending() async {
    final dirty = _pending.values.toList(growable: false);
    for (final edit in dirty) {
      final qty = edit.qty;
      if (qty == null || !qty.isPositive) {
        setState(() => _invalidLineId = edit.lineId);
        await _scrollToTop();
        return false;
      }
      final saved = await ref
          .read(deliveryOrderFormControllerProvider.notifier)
          .saveLine(
            doId: widget.doId,
            lineId: edit.lineId,
            shippedQty: qty,
            batchId: edit.batchId,
            fefoOverrideReason: edit.fefoOverrideReason,
            nearExpiryConfirmed: edit.nearExpiryConfirmed,
            nearExpiryNote: edit.nearExpiryNote,
          );
      if (!saved) {
        await _scrollToTop();
        return false;
      }
      _pending.remove(edit.lineId);
    }
    if (mounted) setState(() => _invalidLineId = null);
    return true;
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  Future<void> _confirmAndShip(DeliveryOrderDetail detail) async {
    if (!await _flushPending()) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kirim Surat Jalan?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stok Warehouse Pusat akan langsung berkurang sesuai alokasi '
              'Surat Jalan ${detail.summary.docNumber}.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Aksi ini final: Surat Jalan yang sudah dikirim tidak dapat '
              'diubah lagi.',
            ),
          ],
        ),
        actions: [
          TextButton(
            key: DeliveryOrderFormPage.cancelShipKey,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: DeliveryOrderFormPage.confirmShipKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kirim sekarang'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final notifier = ref.read(deliveryOrderFormControllerProvider.notifier);
    final shipped = await notifier.ship(widget.doId);
    if (!mounted) return;

    if (!shipped) {
      // The message itself comes from the failure; the notice above renders it.
      // Nothing is navigated, so the officer keeps the document and its
      // allocations exactly as they were.
      return;
    }

    final result = notifier.lastShipment;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result != null && result.purchaseRequestCompleted
              ? 'Surat Jalan dikirim. Purchase Request terkirim penuh.'
              : 'Surat Jalan dikirim. Purchase Request masih menunggu '
                    'pengiriman berikutnya.',
        ),
      ),
    );
    context.pushReplacementNamed(
      AppRoutes.warehouseDeliveryOrderWaybillName,
      pathParameters: {'id': widget.doId},
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.detail});

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
              Text(
                'Diminta ${summary.requestedByName}',
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
                      ].where((label) => label.isNotEmpty).join(', '),
                    ),
                ],
              ),
              if (detail.isPartialShipment && !summary.status.isPreparing)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Pengiriman parsial: Purchase Request masih memiliki sisa '
                    'yang belum dikirim.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
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
