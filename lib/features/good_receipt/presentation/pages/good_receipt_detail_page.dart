import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/good_receipt_models.dart';
import '../../domain/services/good_receipt_expiry_policy.dart';
import '../../domain/services/good_receipt_line_decision_policy.dart';
import '../providers/good_receipt_providers.dart';
import '../widgets/good_receipt_badges.dart';
import '../widgets/good_receipt_line_card.dart';
import '../widgets/good_receipt_reject_sheet.dart';

/// The checklist while a receipt is `checking`, and the read-only result once it is
/// `posted` (§31/§32).
///
/// One page for both, deliberately. The difference between them is a single predicate —
/// `detail.isEditable` — and splitting them into two screens would mean two headers, two
/// line lists and two ways for a posted document to grow an action it must not have.
/// Here, everything that could change the document reads that predicate, so *posted is
/// read-only* is one fact rather than a habit maintained in a second file.
///
/// ### Pending input
///
/// The quantity controllers are owned by this state, not by the cards. That is what lets
/// *Posting Good Receipt* flush a number the branch head typed and never confirmed:
/// controllers living inside a lazily built list would be disposed the moment the row
/// scrolled out of view, and the edit would be silently lost.
///
/// ### `branchScoped`
///
/// A warehouse reader reaches the same page through
/// `/warehouse/good-receipts/{id}`, and every write affordance is absent for them
/// because their document is `posted` by definition — the query behind
/// [warehouseGoodReceiptDetailProvider] returns nothing else. The flag chooses which
/// scoped provider to watch; it never chooses whether a rule applies.
class GoodReceiptDetailPage extends ConsumerStatefulWidget {
  const GoodReceiptDetailPage({
    super.key,
    required this.grId,
    this.branchScoped = true,
  });

  final String grId;

  /// `true` for the Kepala Cabang's route, `false` for the warehouse's read-only one.
  final bool branchScoped;

  static const Key listKey = ValueKey('goodReceiptDetailList');
  static const Key postButtonKey = ValueKey('goodReceiptPostButton');
  static const Key pendingNoticeKey = ValueKey('goodReceiptPendingNotice');
  static const Key confirmDialogKey = ValueKey('goodReceiptConfirmDialog');
  static const Key confirmSubmitKey = ValueKey('goodReceiptConfirmSubmit');
  static const Key confirmCancelKey = ValueKey('goodReceiptConfirmCancel');
  static const Key summaryKey = ValueKey('goodReceiptSummaryCard');
  static const Key notFoundKey = ValueKey('goodReceiptNotFound');
  static const Key postedNoticeKey = ValueKey('goodReceiptPostedNotice');

  /// The sentence a branch head sees when a position is still undecided (§31).
  static const String pendingMessage =
      'Semua barang harus diperiksa sebelum Good Receipt diposting.';

  @override
  ConsumerState<GoodReceiptDetailPage> createState() =>
      _GoodReceiptDetailPageState();
}

class _GoodReceiptDetailPageState extends ConsumerState<GoodReceiptDetailPage> {
  final Map<String, TextEditingController> _quantities = {};

  /// The text this state last wrote into each controller.
  ///
  /// Without it, every stream emission would overwrite what the branch head is typing —
  /// and a stream emits on *any* change to the receipt, including another line's
  /// decision. Comparing against what we wrote lets a genuine server-side change through
  /// while leaving an in-progress edit alone.
  final Map<String, String> _lastWritten = {};

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(GoodReceiptLine line) {
    final stored = line.receivedQty.format();
    final controller = _quantities.putIfAbsent(line.id, () {
      _lastWritten[line.id] = stored;
      return TextEditingController(text: stored);
    });
    if (_lastWritten[line.id] != stored) {
      _lastWritten[line.id] = stored;
      controller.text = stored;
    }
    return controller;
  }

  /// Commits a quantity that was typed into an already-accepted line but never
  /// confirmed.
  ///
  /// Only `checked` lines are flushed, and that is not a shortcut: a `pending` line
  /// disables the post button anyway (G-G2), so there is nothing to flush there — and
  /// silently accepting one because a number happened to be in its field would make the
  /// button decide something the branch head never pressed.
  ///
  /// Returns `false` when a flush failed, so the caller stops rather than posting a
  /// document whose quantities were not all written.
  Future<bool> _flushPendingInput(GoodReceiptDetail detail) async {
    final controller = ref.read(goodReceiptCheckingControllerProvider.notifier);
    for (final line in detail.lines) {
      if (!line.isChecked) continue;
      final text = _quantities[line.id]?.text;
      if (text == null) continue;
      final typed = Quantity.tryParse(text);
      if (typed == null || typed == line.receivedQty) continue;
      final ok = await controller.check(
        grId: detail.id,
        lineId: line.id,
        receivedQty: typed,
      );
      if (!ok) return false;
    }
    return true;
  }

  Future<void> _check(GoodReceiptDetail detail, GoodReceiptLine line) async {
    final typed = Quantity.tryParse(_quantities[line.id]?.text ?? '');
    if (typed == null) {
      _showMessage('Masukkan jumlah diterima yang valid terlebih dahulu.');
      return;
    }
    await ref
        .read(goodReceiptCheckingControllerProvider.notifier)
        .check(grId: detail.id, lineId: line.id, receivedQty: typed);
    _reportFailure();
  }

  Future<void> _reject(GoodReceiptDetail detail, GoodReceiptLine line) async {
    // G-E5 decides the reason for an expired or nearly expired batch. Letting the
    // reader file it under `Rusak` would lose the one fact the warehouse needs.
    final forced =
        GoodReceiptExpiryPolicy.mustBeRejected(
          expiryDate: line.expiryDate,
          expiryAlertDays: line.expiryAlertDays,
          nowUtc: ref.read(goodReceiptClockProvider)(),
        )
        ? GoodReceiptExpiryPolicy.forcedRejectPreset
        : null;

    final result = await GoodReceiptRejectSheet.show(
      context,
      itemName: '${line.itemName} (${line.sku})',
      batchLabel: line.batchNo == null
          ? null
          : 'Batch ${line.batchNo}'
                '${line.expiryDate == null ? '' : ' · ED ${AppDateTimeFormatter.civilDate(line.expiryDate!)}'}',
      forcedPreset: forced,
    );
    // Abandoning the sheet leaves the line exactly as it was — the honest outcome of a
    // decision that was not made.
    if (result == null || !mounted) return;

    await ref
        .read(goodReceiptCheckingControllerProvider.notifier)
        .reject(grId: detail.id, lineId: line.id, reason: result.reason);
    _reportFailure();
  }

  Future<void> _reset(GoodReceiptDetail detail, GoodReceiptLine line) async {
    await ref
        .read(goodReceiptCheckingControllerProvider.notifier)
        .reset(grId: detail.id, lineId: line.id);
    _reportFailure();
  }

  Future<void> _post(GoodReceiptDetail detail) async {
    if (!await _flushPendingInput(detail)) {
      _reportFailure();
      return;
    }
    if (!mounted) return;

    // Re-read after the flush: a quantity written above may have changed the picture the
    // dialog is about to describe.
    final current =
        ref.read(_detailProvider(widget.branchScoped, widget.grId)).value ??
        detail;
    if (!current.canPost) {
      _showMessage(GoodReceiptDetailPage.pendingMessage);
      return;
    }

    final confirmed = await _confirm(current);
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(goodReceiptCheckingControllerProvider.notifier)
        .post(current.id);
    if (!mounted) return;
    if (!ok) {
      _reportFailure();
      return;
    }

    final result = ref
        .read(goodReceiptCheckingControllerProvider.notifier)
        .lastPosting;
    _showMessage(
      result == null
          ? 'Good Receipt berhasil diposting.'
          : 'Good Receipt diposting. Stok Gudang Cabang bertambah untuk '
                '${result.movements.length} baris'
                '${result.purchaseRequestClosed ? ', dan Purchase Request ditutup' : ''}.',
    );
  }

  Future<bool?> _confirm(GoodReceiptDetail detail) {
    final progress = detail.progress;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: GoodReceiptDetailPage.confirmDialogKey,
        title: const Text('Posting Good Receipt?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stok Gudang Cabang akan bertambah sebesar jumlah yang diterima '
              'pada ${progress.checked} baris yang disetujui.',
            ),
            const SizedBox(height: AppSpacing.sm),
            if (progress.rejected > 0)
              Text(
                '${progress.rejected} baris ditolak tidak menambah stok dan '
                'masuk daftar retur ke Warehouse.',
              ),
            if (progress.shortage > 0)
              Text(
                '${progress.shortage} baris diterima kurang dari yang dikirim '
                'dan dilaporkan sebagai selisih pengiriman.',
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Tindakan ini final: Good Receipt tidak dapat dibuka kembali, dan '
              'Surat Jalan akan ditandai diterima.',
            ),
          ],
        ),
        actions: [
          TextButton(
            key: GoodReceiptDetailPage.confirmCancelKey,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: GoodReceiptDetailPage.confirmSubmitKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Posting'),
          ),
        ],
      ),
    );
  }

  void _reportFailure() {
    final state = ref.read(goodReceiptCheckingControllerProvider);
    if (!state.hasError) return;
    // Never a raw exception or a stack trace: `describeFailure` returns the Indonesian
    // sentence the business failure carries, and one generic sentence for anything else.
    _showMessage(describeFailure(state.error!));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(_detailProvider(widget.branchScoped, widget.grId));
    final action = ref.watch(goodReceiptCheckingControllerProvider);
    final nowUtc = ref.watch(goodReceiptClockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.branchScoped ? 'Pemeriksaan Barang' : 'Good Receipt',
        ),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
        data: (value) {
          if (value == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Card(
                key: GoodReceiptDetailPage.notFoundKey,
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('Good Receipt tidak tersedia.'),
                ),
              ),
            );
          }
          return _body(value, nowUtc, action.isLoading);
        },
      ),
      bottomNavigationBar: detail.value == null || !detail.value!.isEditable
          ? null
          : _postBar(detail.value!, action.isLoading),
    );
  }

  Widget _body(GoodReceiptDetail detail, DateTime nowUtc, bool busy) {
    return ListView(
      key: GoodReceiptDetailPage.listKey,
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        _HeaderCard(detail: detail, nowUtc: nowUtc),
        if (detail.isPosted) _PostedSummaryCard(detail: detail),
        for (final line in detail.lines)
          GoodReceiptLineCard(
            line: line,
            nowUtc: nowUtc,
            editable: detail.isEditable,
            controller: _controllerFor(line),
            busy: busy,
            onCheck: (_) => _check(detail, line),
            onReject: () => _reject(detail, line),
            onReset: () => _reset(detail, line),
          ),
      ],
    );
  }

  Widget _postBar(GoodReceiptDetail detail, bool busy) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!detail.allLinesDecided)
              Padding(
                key: GoodReceiptDetailPage.pendingNoticeKey,
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  GoodReceiptDetailPage.pendingMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),
            FilledButton(
              key: GoodReceiptDetailPage.postButtonKey,
              // G-G2 in the affordance as well as in the use case: the button is dead
              // until every position has been decided. The use case checks again, and
              // the guarded `UPDATE` checks a third time inside the statement.
              onPressed: busy || !detail.canPost ? null : () => _post(detail),
              child: Text(busy ? 'Memproses…' : 'Posting Good Receipt'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which scoped stream to watch. Never a widened read: a warehouse reader gets the
/// `posted`-only provider and a branch head the branch-scoped one.
StreamProvider<GoodReceiptDetail?> _detailProvider(
  bool branchScoped,
  String grId,
) => branchScoped
    ? branchGoodReceiptDetailProvider(grId)
    : warehouseGoodReceiptDetailProvider(grId);

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.detail, required this.nowUtc});

  final GoodReceiptDetail detail;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = detail.summary;
    final receipt = detail.receipt;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        key: GoodReceiptDetailPage.summaryKey,
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
                      style: theme.textTheme.titleMedium?.copyWith(
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
              if (summary.shippedByName != null)
                Text(
                  'Dikirim oleh ${summary.shippedByName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (summary.doShippedAt != null) ...[
                Text(
                  'Waktu kirim '
                  '${AppDateTimeFormatter.dateTimeWithZone(summary.doShippedAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  GoodReceiptDeadlineBadge.deadlineLabel(summary.doShippedAt!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              Text(
                'Diperiksa ${summary.receivedByName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (receipt.postedAt != null)
                Text(
                  key: GoodReceiptDetailPage.postedNoticeKey,
                  'Diposting '
                  '${AppDateTimeFormatter.dateTimeWithZone(receipt.postedAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              GoodReceiptProgressBar(progress: detail.progress),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SyncStatusTag(status: receipt.syncStatus),
                  if (summary.doShippedAt != null && !receipt.isPosted)
                    GoodReceiptDeadlineBadge(
                      shippedAtUtc: summary.doShippedAt!,
                      nowUtc: nowUtc,
                      showWhenDue: true,
                    ),
                  if (detail.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (summary.branchIsHistorical) 'Cabang',
                        if (summary.receivedByIsHistorical) 'Petugas',
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

/// The read-only summary a posted receipt carries (§32).
class _PostedSummaryCard extends StatelessWidget {
  const _PostedSummaryCard({required this.detail});

  final GoodReceiptDetail detail;

  static const Key cardKey = ValueKey('goodReceiptPostedSummary');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = detail.progress;

    // Totals are grouped by unit: `2 box` and `3 pcs` are not `5` of anything, and one
    // headline number would mislead.
    String totals(Map<String, Quantity> byUnit) => byUnit.isEmpty
        ? '—'
        : byUnit.entries
              .map((entry) => entry.value.formatWithUnit(entry.key))
              .join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: cardKey,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ringkasan penerimaan',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _row(theme, 'Total baris', '${progress.total}'),
              _row(theme, 'Disetujui', '${progress.checked}'),
              _row(theme, 'Ditolak', '${progress.rejected}'),
              _row(theme, 'Baris kurang', '${progress.shortage}'),
              const Divider(height: AppSpacing.lg),
              _row(theme, 'Dikirim', totals(detail.shippedByUnit)),
              _row(theme, 'Diterima', totals(detail.receivedByUnit)),
              _row(theme, 'Selisih', totals(detail.discrepancyByUnit)),
              const Divider(height: AppSpacing.lg),
              _row(
                theme,
                'Stok Gudang Cabang',
                GoodReceiptLineDecisionPolicy.allDecided(
                      detail.lines.map((line) => line.lineStatus),
                    )
                    ? 'Bertambah sesuai jumlah diterima'
                    : '—',
              ),
              _row(theme, 'Surat Jalan', detail.summary.doStatus.label),
              _row(theme, 'Purchase Request', detail.summary.prStatus.label),
              if (detail.hasRejectedLines)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Barang yang ditolak masuk daftar retur Warehouse dan tidak '
                    'menambah stok cabang.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
