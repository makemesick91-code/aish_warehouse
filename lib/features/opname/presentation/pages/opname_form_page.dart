import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/opname_models.dart';
import '../providers/opname_providers.dart';
import '../widgets/category_filter_chips.dart';
import '../widgets/document_timeline.dart';
import '../widgets/historical_master_badge.dart';
import '../widgets/opname_status_chip.dart';
import '../widgets/searchable_item_dropdown.dart';
import '../widgets/stock_opname_line_card.dart';

/// Identifies the scrollable list of counted lines.
///
/// The form contains three scrollables — the category chips, the search field's
/// internal editable, and this list — so anything that needs *this* one has to
/// say so rather than picking by position.
const Key opnameLineListKey = ValueKey('opnameLineList');

/// The counting sheet (spec §4.2, Perawat → Stok Opname — form).
///
/// A draft is editable; a submitted or reviewed document renders the same
/// content strictly read-only (G-S2), with a timeline instead of buttons.
class OpnameFormPage extends ConsumerStatefulWidget {
  const OpnameFormPage({super.key, required this.opnameId});

  final String opnameId;

  @override
  ConsumerState<OpnameFormPage> createState() => _OpnameFormPageState();
}

/// One line's on-screen values that have not been written yet.
class _PendingEdit {
  const _PendingEdit({required this.countedQty, this.note});

  final Quantity countedQty;
  final String? note;
}

class _OpnameFormPageState extends ConsumerState<OpnameFormPage> {
  final ScrollController _scrollController = ScrollController();

  /// Set after a rejected submit so the offending lines show their error.
  Set<String> _linesMissingNote = const <String>{};

  /// What the nurse has typed but not saved, keyed by line id.
  ///
  /// Submitting flushes these first. Without it, tapping **Kirim** without
  /// tapping *Simpan baris* would submit the values still in the database —
  /// a count the nurse never entered, locked in permanently at review.
  final Map<String, _PendingEdit> _pendingEdits = <String, _PendingEdit>{};

  @override
  void initState() {
    super.initState();
    // Filter state is app-scoped, so a chip left active on another document
    // would silently hide lines here and read as an empty count.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(opnameCategoryFilterProvider.notifier).clear();
      ref.read(opnameSearchQueryProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Writes everything typed but unsaved. Returns false if any write failed.
  Future<bool> _flushPendingEdits() async {
    if (_pendingEdits.isEmpty) return true;

    final controller = ref.read(opnameFormControllerProvider.notifier);
    final pending = Map<String, _PendingEdit>.from(_pendingEdits);
    for (final entry in pending.entries) {
      final saved = await controller.saveLine(
        lineId: entry.key,
        countedQty: entry.value.countedQty,
        note: entry.value.note,
      );
      if (!saved) return false;
      _pendingEdits.remove(entry.key);
    }
    return true;
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit(StockOpnameDetail detail) async {
    // Persist what is on screen before validating it, so the document that
    // gets submitted is the one the nurse is looking at.
    final flushed = await _flushPendingEdits();
    if (!mounted) return;
    if (!flushed) {
      _notify(
        describeFailure(
          ref.read(opnameFormControllerProvider).error ??
              'Sebagian baris gagal disimpan. Periksa kembali lalu coba lagi.',
        ),
      );
      return;
    }

    final controller = ref.read(opnameFormControllerProvider.notifier);
    final succeeded = await controller.submit(detail.id);
    if (!mounted) return;

    if (succeeded) {
      setState(() => _linesMissingNote = const <String>{});
      // The search box disappears with the draft, so its filter has to go too —
      // otherwise the read-only document would render partially filtered with
      // no visible control explaining why.
      ref.read(opnameSearchQueryProvider.notifier).clear();
      ref.read(opnameCategoryFilterProvider.notifier).clear();
      _notify('Stok opname dikirim. Menunggu review Kepala Cabang.');
      return;
    }

    final error = ref.read(opnameFormControllerProvider).error;
    if (error is DifferenceNoteRequiredFailure) {
      // Mark every offending line at once and bring the first one into view,
      // rather than making the nurse hunt for it.
      setState(() => _linesMissingNote = error.lineIds.toSet());
      _scrollToFirstInvalid(detail, error.lineIds.toSet());
    }
    _notify(describeFailure(error ?? 'Gagal mengirim'));
  }

  void _scrollToFirstInvalid(StockOpnameDetail detail, Set<String> invalid) {
    // Index into the lines actually rendered, not the full document: with a
    // category chip active the two differ, and scrolling by the unfiltered
    // index would land on the wrong card.
    final filter = ref.read(opnameLineFilterProvider);
    final visible = detail.lines
        .where(filter.matchesLine)
        .toList(growable: false);

    final index = visible.indexWhere((line) => invalid.contains(line.id));
    if (index < 0) {
      // The offending line is hidden by the current filter, so scrolling would
      // change nothing visible. Clearing the filter is what actually helps.
      ref.read(opnameCategoryFilterProvider.notifier).clear();
      ref.read(opnameSearchQueryProvider.notifier).clear();
      return;
    }
    if (!_scrollController.hasClients) return;

    // Cards are roughly uniform, so an estimated offset is enough to put the
    // first problem on screen.
    const estimatedCardHeight = 260.0;
    final target = (index * estimatedCardHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(opnameDetailProvider(widget.opnameId));
    final session = ref.watch(currentSessionValueProvider);
    final action = ref.watch(opnameFormControllerProvider);
    final filter = ref.watch(opnameLineFilterProvider);
    final now = DateTime.now().toUtc();

    return Scaffold(
      appBar: AppBar(title: const Text('Form Stok Opname')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Centered(
          child: Text(describeFailure(error), textAlign: TextAlign.center),
        ),
        data: (data) {
          if (data == null) {
            return const _Centered(
              child: Text('Dokumen stok opname tidak ditemukan.'),
            );
          }

          // Editable only for a draft, and only for the nurse who owns it.
          final editable =
              data.canEdit &&
              session != null &&
              session.canFillOpname &&
              session.branchId == data.opname.branchId;

          final visibleLines = data.lines
              .where(filter.matchesLine)
              .toList(growable: false);

          return Column(
            children: [
              _DocumentHeader(detail: data),
              if (editable) ...[
                const CategoryFilterChips(),
                _AddLineBar(detail: data, enabled: !action.isLoading),
              ] else
                const CategoryFilterChips(),
              const Divider(height: 1),
              Expanded(
                child: visibleLines.isEmpty
                    ? _EmptyLines(
                        hasFilter:
                            filter.hasSearch || filter.categoryId != null,
                      )
                    : ListView.builder(
                        key: opnameLineListKey,
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.xl,
                        ),
                        itemCount: visibleLines.length,
                        itemBuilder: (context, index) {
                          final line = visibleLines[index];
                          return StockOpnameLineCard(
                            key: ValueKey(line.id),
                            line: line,
                            editable: editable,
                            now: now,
                            highlightMissingNote: _linesMissingNote.contains(
                              line.id,
                            ),
                            // Per-line writes are gated on the same guard as
                            // Kirim: a save and a delete racing each other
                            // would report a failure for something that simply
                            // never ran.
                            onSave: editable && !action.isLoading
                                ? ({required countedQty, note}) =>
                                      _saveLine(line.id, countedQty, note)
                                : null,
                            onEdited: editable
                                ? ({required countedQty, note}) =>
                                      _pendingEdits[line.id] = _PendingEdit(
                                        countedQty: countedQty,
                                        note: note,
                                      )
                                : null,
                            onRemove: editable && !action.isLoading
                                ? () => _removeLine(line.id)
                                : null,
                          );
                        },
                      ),
              ),
              // Always shown: a draft gets Kirim, a submitted document the
              // waiting message, a reviewed one the final notice. The previous
              // condition excluded exactly the reviewed case it meant to cover.
              _FooterBar(
                detail: data,
                editable: editable,
                busy: action.isLoading,
                onSubmit: () => _submit(data),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveLine(
    String lineId,
    Quantity countedQty,
    String? note,
  ) async {
    final succeeded = await ref
        .read(opnameFormControllerProvider.notifier)
        .saveLine(lineId: lineId, countedQty: countedQty, note: note);
    if (!mounted) return;

    if (succeeded) {
      _pendingEdits.remove(lineId);
      setState(
        () => _linesMissingNote = _linesMissingNote.difference({lineId}),
      );
      _notify('Baris tersimpan.');
    } else {
      _notify(
        describeFailure(
          ref.read(opnameFormControllerProvider).error ?? 'Gagal menyimpan',
        ),
      );
    }
  }

  Future<void> _removeLine(String lineId) async {
    final succeeded = await ref
        .read(opnameFormControllerProvider.notifier)
        .removeLine(lineId);
    if (!mounted) return;
    _notify(succeeded ? 'Baris dihapus.' : 'Baris tidak dapat dihapus.');
  }
}

class _DocumentHeader extends StatelessWidget {
  const _DocumentHeader({required this.detail});

  final StockOpnameDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opname = detail.opname;

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
                      opname.docNumber,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  OpnameStatusChip(status: opname.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${detail.summary.branchName} · ${detail.summary.roomName}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Periode ${opname.periodLabel} '
                '(${AppDateTimeFormatter.timeZoneLabel})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              HistoricalMasterBadge.forSummary(detail.summary),
              const SizedBox(height: AppSpacing.sm),
              SyncStatusTag(status: opname.syncStatus),
              if (!opname.isDraft) ...[
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                DocumentTimeline(summary: detail.summary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// SearchableDropdown plus the sheet that captures quantity, batch and note for
/// a newly found position.
class _AddLineBar extends ConsumerWidget {
  const _AddLineBar({required this.detail, required this.enabled});

  final StockOpnameDetail detail;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Non-expiry items already on the sheet cannot be added twice; expiry
    // items can still gain another batch, so they are never excluded.
    final excluded = detail.lines
        .where((line) => !line.hasExpiry)
        .map((line) => line.itemId)
        .toSet();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: SearchableItemDropdown(
        enabled: enabled,
        excludedItemIds: excluded,
        onSelected: (item) => _openAddSheet(context, ref, item),
      ),
    );
  }

  Future<void> _openAddSheet(
    BuildContext context,
    WidgetRef ref,
    MasterItem item,
  ) async {
    final result = await showModalBottomSheet<_AddLineResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddLineSheet(item: item),
    );
    if (result == null || !context.mounted) return;

    final succeeded = await ref
        .read(opnameFormControllerProvider.notifier)
        .addLine(
          opnameId: detail.id,
          itemId: item.id,
          batchId: result.batchId,
          countedQty: result.countedQty,
          note: result.note,
        );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            succeeded
                ? '${item.name} ditambahkan.'
                : describeFailure(
                    ref.read(opnameFormControllerProvider).error ??
                        'Gagal menambahkan barang',
                  ),
          ),
        ),
      );
  }
}

class _AddLineResult {
  const _AddLineResult({required this.countedQty, this.batchId, this.note});

  final Quantity countedQty;
  final String? batchId;
  final String? note;
}

class _AddLineSheet extends ConsumerStatefulWidget {
  const _AddLineSheet({required this.item});

  final MasterItem item;

  @override
  ConsumerState<_AddLineSheet> createState() => _AddLineSheetState();
}

class _AddLineSheetState extends ConsumerState<_AddLineSheet> {
  final TextEditingController _noteController = TextEditingController();
  Quantity? _counted;
  String? _batchId;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _counted != null && (!widget.item.hasExpiry || _batchId != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batches = widget.item.hasExpiry
        ? ref.watch(itemBatchOptionsProvider(widget.item.id))
        : const AsyncValue<List<MasterBatch>>.data(<MasterBatch>[]);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tambah ${widget.item.name}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${widget.item.sku} · ${widget.item.unit}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.item.hasExpiry)
            batches.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(describeFailure(error)),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Text(
                    'Barang ini dilacak per batch, tetapi belum ada batch '
                    'terdaftar. Hubungi Warehouse untuk mendaftarkan batch.',
                  );
                }
                return DropdownButtonFormField<String>(
                  initialValue: _batchId,
                  decoration: const InputDecoration(labelText: 'Batch'),
                  items: [
                    for (final batch in rows)
                      DropdownMenuItem(
                        value: batch.id,
                        child: Text(
                          '${batch.batchNo} · ED '
                          '${AppDateTimeFormatter.civilDate(batch.expiryDate)}',
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _batchId = value),
                );
              },
            ),
          const SizedBox(height: AppSpacing.md),
          QuantityField(
            label: 'Hasil hitung',
            unit: widget.item.unit,
            allowZero: true,
            autofocus: true,
            onChanged: (value) => setState(() => _counted = value),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Catatan',
              helperText:
                  'Wajib bila hasil hitung berbeda dari stok sistem (0).',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: _canSubmit
                      ? () {
                          final note = _noteController.text.trim();
                          Navigator.of(context).pop(
                            _AddLineResult(
                              countedQty: _counted!,
                              batchId: _batchId,
                              note: note.isEmpty ? null : note,
                            ),
                          );
                        }
                      : null,
                  child: const Text('Tambah'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar({
    required this.detail,
    required this.editable,
    required this.busy,
    required this.onSubmit,
  });

  final StockOpnameDetail detail;
  final bool editable;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!editable) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                detail.opname.isReviewed ? Icons.lock : Icons.hourglass_empty,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  detail.opname.isReviewed
                      ? 'Dokumen sudah direview dan bersifat final.'
                      : 'Menunggu review Kepala Cabang.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final missing = detail.linesMissingNote.length;

    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${detail.lines.length} baris · '
                    '${detail.linesWithDifference.length} berselisih',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (missing > 0)
                  Text(
                    '$missing baris butuh catatan',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                // Disabled while any write is in flight — the double-submit
                // guard.
                onPressed: busy || detail.isEmpty ? null : onSubmit,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(busy ? 'Mengirim…' : 'Kirim'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLines extends StatelessWidget {
  const _EmptyLines({required this.hasFilter});

  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return _Centered(
      child: Text(
        hasFilter
            ? 'Tidak ditemukan barang yang cocok dengan filter.'
            : 'Belum ada barang pada dokumen ini. Tambahkan lewat pencarian '
                  'di atas.',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: child),
  );
}
