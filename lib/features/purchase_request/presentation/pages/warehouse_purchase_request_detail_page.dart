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
import '../../domain/models/purchase_request_models.dart';
import '../providers/purchase_request_providers.dart';
import '../widgets/eligible_opname_tile.dart';
import '../widgets/purchase_request_line_card.dart';
import '../widgets/purchase_request_status_chip.dart';
import '../widgets/purchase_request_timeline.dart';

/// One Purchase Request, as the warehouse sees it (§25).
///
/// **Read-only, with two actions and nothing else.** That is G-R3 rendered:
/// *"Warehouse tidak bisa mengubah isi PR — hanya memenuhi (fulfil) atau menolak
/// dengan alasan"*. Every line card is built with `editable: false`, so there is no
/// quantity input to disable, no note field, no add-item picker and no remove
/// button anywhere on this screen. The only controls are **Mulai Proses** and
/// **Tolak PR**, and each appears only for the status the state machine permits it
/// from.
///
/// `Tolak PR` is available from `processing` alone, not from `submitted`. Refusing
/// an order means somebody looked at it, and taking it on is what "looked at it" is
/// recorded as — which is also why a rejected document always carries both
/// `processed_by` and `rejected_by` (G-A3).
class WarehousePurchaseRequestDetailPage extends ConsumerWidget {
  const WarehousePurchaseRequestDetailPage({super.key, required this.prId});

  final String prId;

  static const Key processButtonKey = ValueKey('warehousePrProcess');
  static const Key rejectButtonKey = ValueKey('warehousePrReject');

  /// The Delivery Order entry point (§27.1). Not a write on this screen — it
  /// navigates to the shipment form, which is where G-D1 is enforced.
  static const Key createDeliveryKey = ValueKey('warehousePrCreateDelivery');

  /// Lets tests scroll the document without guessing which scrollable is which.
  static const Key bodyKey = ValueKey('warehousePurchaseRequestDetailBody');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch(warehousePurchaseRequestDetailProvider(prId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detail PR Masuk')),
      body: detailState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(
            message: describeFailure(error),
            onRetry: () =>
                ref.invalidate(warehousePurchaseRequestDetailProvider(prId)),
          ),
        ),
        data: (detail) => detail == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('Purchase Request tidak ditemukan.'),
                ),
              )
            : _Body(detail: detail),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final PurchaseRequestDetail detail;

  Future<void> _process(BuildContext context, WidgetRef ref) async {
    final started = await ref
        .read(warehousePurchaseRequestControllerProvider.notifier)
        .markProcessing(detail.id);
    if (!context.mounted) return;
    _notify(
      context,
      started
          ? 'Purchase Request ${detail.request.docNumber} mulai diproses.'
          : describeFailure(
              ref.read(warehousePurchaseRequestControllerProvider).error ??
                  'Gagal memproses permintaan.',
            ),
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectReasonDialog(),
    );
    if (reason == null || !context.mounted) return;

    final rejected = await ref
        .read(warehousePurchaseRequestControllerProvider.notifier)
        .reject(prId: detail.id, reason: reason);
    if (!context.mounted) return;
    _notify(
      context,
      rejected
          ? 'Purchase Request ${detail.request.docNumber} ditolak.'
          : describeFailure(
              ref.read(warehousePurchaseRequestControllerProvider).error ??
                  'Gagal menolak permintaan.',
            ),
    );
  }

  static void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = detail.request;
    final busy = ref
        .watch(warehousePurchaseRequestControllerProvider)
        .isLoading;

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: WarehousePurchaseRequestDetailPage.bodyKey,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _HeaderCard(detail: detail),
              _SectionTitle('Stok opname acuan (${detail.opnames.length})'),
              if (detail.opnames.isEmpty)
                const _InfoCard(
                  message: 'Permintaan ini tidak menautkan stok opname acuan.',
                )
              else
                for (final reference in detail.opnames)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: Card(
                      child: EligibleOpnameTile(
                        reference: reference,
                        selected: true,
                      ),
                    ),
                  ),
              _SectionTitle('Barang diminta (${detail.lines.length})'),
              for (final line in detail.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  // `editable: false` — the warehouse never changes what was asked
                  // for (G-R3). There is no branch of this screen where it is true.
                  child: PurchaseRequestLineCard(line: line, editable: false),
                ),
              const _SectionTitle('Riwayat dokumen'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PurchaseRequestTimeline(summary: detail.summary),
                        const SizedBox(height: AppSpacing.md),
                        PurchaseRequestSyncNote(status: request.syncStatus),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // G-D1's entry point. Offered for `submitted` as well as `processing`,
        // because creating the first Delivery Order is what moves the request to
        // `processing` — and only while something is still outstanding (G-D2), which
        // `DeliveryOrderCreatePage` shows and this button therefore does not have to
        // decide.
        if (request.isSubmitted || request.isProcessing)
          SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: OutlinedButton.icon(
                key: WarehousePurchaseRequestDetailPage.createDeliveryKey,
                onPressed: busy
                    ? null
                    : () => context.pushNamed(
                        AppRoutes.warehouseDeliveryOrderNewName,
                        pathParameters: {'purchaseRequestId': request.id},
                      ),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Buat Delivery Order'),
              ),
            ),
          ),
        if (request.isSubmitted || request.isProcessing)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  if (request.isSubmitted)
                    Expanded(
                      child: FilledButton.icon(
                        key:
                            WarehousePurchaseRequestDetailPage.processButtonKey,
                        onPressed: busy ? null : () => _process(context, ref),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Mulai Proses'),
                      ),
                    ),
                  if (request.isProcessing)
                    Expanded(
                      child: OutlinedButton.icon(
                        key: WarehousePurchaseRequestDetailPage.rejectButtonKey,
                        onPressed: busy ? null : () => _reject(context, ref),
                        icon: const Icon(Icons.block),
                        label: const Text('Tolak PR'),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.detail});

  final PurchaseRequestDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = detail.request;

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
                      request.docNumber,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PurchaseRequestStatusChip(
                    status: request.status,
                    compact: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              PurchaseRequestStatusNote(status: request.status),
              const Divider(height: AppSpacing.lg),
              _Row(
                label: 'Cabang',
                value:
                    '${detail.summary.branchCode} · '
                    '${detail.summary.branchName}',
              ),
              _Row(
                label: 'Diminta oleh',
                value: detail.summary.requestedByName,
              ),
              _Row(
                label: 'Dikirim',
                value: request.submittedAt == null
                    ? '—'
                    : AppDateTimeFormatter.dateTimeWithZone(
                        request.submittedAt!,
                      ),
              ),
              _Row(
                label: 'Tanggal dibutuhkan',
                value: request.neededDate == null
                    ? '—'
                    : AppDateTimeFormatter.civilDate(request.neededDate!),
              ),
              if (request.note != null && request.note!.trim().isNotEmpty)
                _Row(label: 'Catatan cabang', value: request.note!),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SyncStatusTag(status: request.syncStatus),
                  if (detail.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (detail.summary.branchIsHistorical) 'Cabang',
                        if (detail.summary.requestedByIsHistorical) 'Pemohon',
                        if (detail.lines.any((line) => line.itemIsHistorical))
                          'Barang',
                        if (detail.opnames.any(
                          (reference) => reference.usesHistoricalMaster,
                        ))
                          'Opname acuan',
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(message),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Asks for the mandatory rejection reason (spec §3.2, §25).
class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _controller.text.trim().isNotEmpty;

    return AlertDialog(
      key: const ValueKey('warehousePrRejectDialog'),
      title: const Text('Tolak Purchase Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Penolakan bersifat final. Cabang harus membuat permintaan baru '
            'setelah memperbaikinya.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('warehousePrRejectReason'),
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Alasan penolakan (wajib)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
        FilledButton(
          key: const ValueKey('warehousePrRejectConfirm'),
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('Tolak PR'),
        ),
      ],
    );
  }
}
