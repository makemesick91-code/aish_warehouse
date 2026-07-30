import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
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

/// One Purchase Request, read-only, for the branch head who raised it (§24.4).
///
/// Every status renders through this screen, including `draft` — which is why the
/// only edit affordance here is a link to the editor rather than an input. A
/// submitted, processing, shipped, closed, rejected or cancelled document has no
/// editable control at all (G-P5): the line cards are constructed with
/// `editable: false`, so there is no input to disable and no code path where one
/// could appear.
///
/// The two actions that do exist are the ones the state machine permits:
/// **Lanjutkan Draft** while it is a draft, and **Batalkan Permintaan** while it is
/// a draft or submitted (G-S3). Both read their availability from
/// `status.canCancel` / `status.isEditable` rather than from a hand-written
/// condition, so the buttons and the use cases cannot disagree.
class PurchaseRequestDetailPage extends ConsumerWidget {
  const PurchaseRequestDetailPage({super.key, required this.prId});

  final String prId;

  static const Key cancelButtonKey = ValueKey('purchaseRequestCancel');
  static const Key editButtonKey = ValueKey('purchaseRequestContinueDraft');

  /// Lets tests scroll the document without guessing which scrollable is which.
  static const Key bodyKey = ValueKey('purchaseRequestDetailBody');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch(purchaseRequestDetailProvider(prId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Purchase Request')),
      body: detailState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(
            message: describeFailure(error),
            onRetry: () => ref.invalidate(purchaseRequestDetailProvider(prId)),
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

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelReasonDialog(),
    );
    if (reason == null || !context.mounted) return;

    final cancelled = await ref
        .read(cancelPurchaseRequestControllerProvider.notifier)
        .cancel(prId: detail.id, reason: reason);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            cancelled
                ? 'Purchase Request dibatalkan.'
                : describeFailure(
                    ref.read(cancelPurchaseRequestControllerProvider).error ??
                        'Gagal membatalkan permintaan.',
                  ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = detail.request;
    final busy = ref.watch(cancelPurchaseRequestControllerProvider).isLoading;

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: PurchaseRequestDetailPage.bodyKey,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _HeaderCard(detail: detail),
              _TotalsCard(detail: detail),
              _SectionTitle('Stok opname acuan (${detail.opnames.length})'),
              if (detail.opnames.isEmpty)
                const _InfoCard(
                  message: 'Belum ada stok opname acuan pada permintaan ini.',
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
              if (detail.lines.isEmpty)
                const _InfoCard(
                  message: 'Belum ada barang pada permintaan ini.',
                )
              else
                for (final line in detail.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    // `editable: false` — a sent document has no inputs at all.
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
        if (request.isEditable || request.status.canCancel)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  if (request.isEditable)
                    Expanded(
                      child: FilledButton.icon(
                        key: PurchaseRequestDetailPage.editButtonKey,
                        onPressed: () => context.pushNamed(
                          AppRoutes.purchaseRequestEditName,
                          pathParameters: {'id': detail.id},
                        ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Lanjutkan Draft'),
                      ),
                    ),
                  if (request.isEditable && request.status.canCancel)
                    const SizedBox(width: AppSpacing.sm),
                  if (request.status.canCancel)
                    Expanded(
                      child: OutlinedButton.icon(
                        key: PurchaseRequestDetailPage.cancelButtonKey,
                        onPressed: busy ? null : () => _cancel(context, ref),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Batalkan Permintaan'),
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
              _Row(label: 'Cabang', value: detail.summary.branchName),
              _Row(
                label: 'Diminta oleh',
                value: detail.summary.requestedByName,
              ),
              _Row(
                label: 'Tanggal dibutuhkan',
                value: request.neededDate == null
                    ? '—'
                    // A civil date is printed exactly as stored (T-9).
                    : AppDateTimeFormatter.civilDate(request.neededDate!),
              ),
              _Row(
                label: 'Dibuat',
                value: AppDateTimeFormatter.dateTimeWithZone(request.createdAt),
              ),
              if (request.note != null && request.note!.trim().isNotEmpty)
                _Row(label: 'Catatan', value: request.note!),
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

/// Requested totals, grouped by unit — never one number across units.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.detail});

  final PurchaseRequestDetail detail;

  @override
  Widget build(BuildContext context) {
    final totals = detail.requestedByUnit;
    if (totals.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total diminta',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final entry in totals.entries)
                    Text(_formatTotal(entry.key, entry.value)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Quantities of different units are never added together: `2 box` and `3 pcs`
  /// are not `5` of anything.
  static String _formatTotal(String unit, Quantity total) =>
      total.formatWithUnit(unit);
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

/// Asks for the mandatory cancellation reason (§19.7, §24.4).
///
/// The confirm button stays disabled until there is non-whitespace text, so the
/// rule is visible before it is enforced — and the use case and the database's
/// `trim(cancel_reason) <> ''` CHECK enforce it again regardless.
class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog();

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
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
      key: const ValueKey('prCancelDialog'),
      title: const Text('Batalkan Purchase Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Permintaan yang dibatalkan tidak dapat dikembalikan menjadi draft. '
            'Buat permintaan baru bila barang masih dibutuhkan.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('prCancelReason'),
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Alasan pembatalan (wajib)',
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
          key: const ValueKey('prCancelConfirm'),
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('Batalkan Permintaan'),
        ),
      ],
    );
  }
}
