import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/time/date_only.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/purchase_request_models.dart';
import '../providers/purchase_request_providers.dart';
import '../widgets/eligible_opname_tile.dart';
import '../widgets/purchase_request_item_picker.dart';
import '../widgets/purchase_request_line_card.dart';

/// Step 2 of the wizard: **tinjau & sesuaikan permintaan** (§24.2).
///
/// Only ever reached for a `draft` — the route guard refuses the editor for
/// anything else (G-P5), and the sent document is read on
/// `PurchaseRequestDetailPage` instead. The screen therefore does not have a
/// read-only mode to fall back into; if the document is not editable it says so and
/// offers the detail screen.
///
/// The most important behaviour here is **flushing pending edits before submit**.
/// Each line card reports every keystroke upward, and `_flushPendingEdits` writes
/// them before validation runs. Without it, a branch head who types a quantity and
/// taps *Kirim ke Warehouse* without first tapping *Simpan baris* would submit the
/// values still in the database — an order for quantities nobody asked for, frozen
/// permanently the moment it is sent. That is exactly the bug the Stok Opname form
/// was found to have, and it is fixed the same way here.
class PurchaseRequestFormPage extends ConsumerStatefulWidget {
  const PurchaseRequestFormPage({super.key, required this.prId});

  final String prId;

  static const Key lineListKey = ValueKey('purchaseRequestLineList');
  static const Key submitButtonKey = ValueKey('purchaseRequestSubmit');

  @override
  ConsumerState<PurchaseRequestFormPage> createState() =>
      _PurchaseRequestFormPageState();
}

/// One line's on-screen values that have not been written yet.
class _PendingEdit {
  const _PendingEdit({required this.requestedQty, this.note});

  final Quantity requestedQty;
  final String? note;
}

class _PurchaseRequestFormPageState
    extends ConsumerState<PurchaseRequestFormPage> {
  final ScrollController _scrollController = ScrollController();

  /// Set after a rejected submit so the offending lines show their error.
  Set<String> _linesMissingNote = const <String>{};

  /// What the branch head has typed but not saved, keyed by line id.
  final Map<String, _PendingEdit> _pendingEdits = <String, _PendingEdit>{};

  @override
  void initState() {
    super.initState();
    // Filter state is app-scoped, so a chip left active elsewhere would silently
    // hide lines here and read as a shorter order than the document actually is.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(purchaseRequestCategoryFilterProvider.notifier).clear();
      ref.read(purchaseRequestSearchQueryProvider.notifier).clear();
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

    final controller = ref.read(purchaseRequestFormControllerProvider.notifier);
    final pending = Map<String, _PendingEdit>.from(_pendingEdits);
    for (final entry in pending.entries) {
      final saved = await controller.saveLine(
        lineId: entry.key,
        requestedQty: entry.value.requestedQty,
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

  Future<void> _submit(PurchaseRequestDetail detail) async {
    // Persist what is on screen before validating it, so the request that gets
    // submitted is the one the branch head is looking at.
    final flushed = await _flushPendingEdits();
    if (!mounted) return;
    if (!flushed) {
      _notify(
        describeFailure(
          ref.read(purchaseRequestFormControllerProvider).error ??
              'Sebagian baris gagal disimpan. Periksa kembali lalu coba lagi.',
        ),
      );
      return;
    }

    final controller = ref.read(purchaseRequestFormControllerProvider.notifier);
    final succeeded = await controller.submit(detail.id);
    if (!mounted) return;

    if (succeeded) {
      setState(() => _linesMissingNote = const <String>{});
      ref.read(purchaseRequestSearchQueryProvider.notifier).clear();
      ref.read(purchaseRequestCategoryFilterProvider.notifier).clear();
      _notify('Purchase Request dikirim. Menunggu diproses Warehouse.');
      context.pushReplacementNamed(
        AppRoutes.purchaseRequestDetailName,
        pathParameters: {'id': detail.id},
      );
      return;
    }

    final error = ref.read(purchaseRequestFormControllerProvider).error;
    if (error is PurchaseRequestJustificationRequiredFailure) {
      // Mark every offending line at once and bring the first one into view,
      // rather than making the branch head hunt for it.
      setState(() => _linesMissingNote = error.lineIds.toSet());
      _scrollToFirstInvalid(detail, error.lineIds.toSet());
    }
    _notify(describeFailure(error ?? 'Gagal mengirim'));
  }

  void _scrollToFirstInvalid(
    PurchaseRequestDetail detail,
    Set<String> invalid,
  ) {
    // Index into the lines actually rendered, not the full document: with a
    // category chip active the two differ, and scrolling by the unfiltered index
    // would land on the wrong card.
    final filter = ref.read(purchaseRequestLineFilterProvider);
    final visible = detail.lines
        .where(filter.matchesLine)
        .toList(growable: false);

    final index = visible.indexWhere((line) => invalid.contains(line.id));
    if (index < 0) {
      // The offending line is hidden by the current filter, so scrolling would
      // change nothing visible. Clearing the filter is what actually helps.
      ref.read(purchaseRequestCategoryFilterProvider.notifier).clear();
      ref.read(purchaseRequestSearchQueryProvider.notifier).clear();
      return;
    }
    if (!_scrollController.hasClients) return;

    const estimatedCardHeight = 320.0;
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

  Future<void> _addItem(PurchaseRequestDetail detail, MasterItem item) async {
    final result = await showDialog<({Quantity qty, String note})>(
      context: context,
      builder: (_) => _AddManualLineDialog(item: item),
    );
    if (result == null || !mounted) return;

    final added = await ref
        .read(purchaseRequestFormControllerProvider.notifier)
        .addLine(
          prId: detail.id,
          itemId: item.id,
          requestedQty: result.qty,
          note: result.note,
        );
    if (!mounted) return;
    _notify(
      added
          ? '${item.name} ditambahkan sebagai permintaan manual.'
          : describeFailure(
              ref.read(purchaseRequestFormControllerProvider).error ??
                  'Gagal menambahkan barang.',
            ),
    );
  }

  Future<void> _editCitations(PurchaseRequestDetail detail) async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _EditCitationsDialog(
        branchId: detail.request.branchId,
        initial: detail.opnames.map((reference) => reference.opnameId).toSet(),
      ),
    );
    if (selected == null || !mounted) return;

    final replaced = await ref
        .read(purchaseRequestFormControllerProvider.notifier)
        .replaceOpnames(prId: detail.id, opnameIds: selected);
    if (!mounted) return;

    if (replaced) {
      // The suggestions moved, so the breakdown beside them has to be re-read.
      ref.invalidate(draftSuggestionBreakdownProvider(detail.id));
      _notify('Acuan stok opname diperbarui dan saran dihitung ulang.');
      return;
    }
    _notify(
      describeFailure(
        ref.read(purchaseRequestFormControllerProvider).error ??
            'Gagal memperbarui acuan stok opname.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(purchaseRequestDetailProvider(widget.prId));
    final busy = ref.watch(purchaseRequestFormControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Tinjau & Sesuaikan Permintaan')),
      body: detailState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(
            message: describeFailure(error),
            onRetry: () =>
                ref.invalidate(purchaseRequestDetailProvider(widget.prId)),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('Purchase Request tidak ditemukan.'),
              ),
            );
          }
          if (!detail.isEditable) {
            return _NotEditableNotice(detail: detail);
          }
          return _DraftBody(
            detail: detail,
            busy: busy,
            scrollController: _scrollController,
            linesMissingNote: _linesMissingNote,
            onLineEdited: (lineId, edit) => _pendingEdits[lineId] = edit,
            onLineSaved: (lineId) => _pendingEdits.remove(lineId),
            onAddItem: (item) => _addItem(detail, item),
            onEditCitations: () => _editCitations(detail),
            onSubmit: () => _submit(detail),
            onNotify: _notify,
          );
        },
      ),
    );
  }
}

/// The whole editable form, extracted so the builder above stays readable.
class _DraftBody extends ConsumerWidget {
  const _DraftBody({
    required this.detail,
    required this.busy,
    required this.scrollController,
    required this.linesMissingNote,
    required this.onLineEdited,
    required this.onLineSaved,
    required this.onAddItem,
    required this.onEditCitations,
    required this.onSubmit,
    required this.onNotify,
  });

  final PurchaseRequestDetail detail;
  final bool busy;
  final ScrollController scrollController;
  final Set<String> linesMissingNote;
  final void Function(String lineId, _PendingEdit edit) onLineEdited;
  final void Function(String lineId) onLineSaved;
  final Future<void> Function(MasterItem item) onAddItem;
  final Future<void> Function() onEditCitations;
  final Future<void> Function() onSubmit;
  final void Function(String message) onNotify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(purchaseRequestLineFilterProvider);
    final breakdown =
        ref.watch(draftSuggestionBreakdownProvider(detail.id)).value ??
        const <String, SuggestedPurchaseRequestLine>{};
    final visible = detail.lines
        .where(filter.matchesLine)
        .toList(growable: false);

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: PurchaseRequestFormPage.lineListKey,
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _HeaderCard(detail: detail, onEditCitations: onEditCitations),
              const PurchaseRequestCategoryFilterChips(),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: PurchaseRequestItemPicker(
                  onSelected: onAddItem,
                  excludedItemIds: detail.lines
                      .map((line) => line.itemId)
                      .toSet(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  'Barang diminta (${detail.lines.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (detail.lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Card(
                    key: ValueKey('purchaseRequestNoLines'),
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'Seluruh ruangan pada stok opname acuan berada di atas '
                        'par level, sehingga sistem tidak menyarankan barang. '
                        'Tambahkan barang secara manual bila tetap dibutuhkan.',
                      ),
                    ),
                  ),
                )
              else if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'Tidak ada barang yang cocok dengan filter kategori '
                        'atau pencarian saat ini.',
                      ),
                    ),
                  ),
                )
              else
                for (final line in visible)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: PurchaseRequestLineCard(
                      line: line,
                      editable: true,
                      breakdown: breakdown[line.itemId],
                      highlightMissingNote: linesMissingNote.contains(line.id),
                      onEdited: ({required requestedQty, note}) => onLineEdited(
                        line.id,
                        _PendingEdit(requestedQty: requestedQty, note: note),
                      ),
                      onSave: ({required requestedQty, note}) async {
                        final saved = await ref
                            .read(
                              purchaseRequestFormControllerProvider.notifier,
                            )
                            .saveLine(
                              lineId: line.id,
                              requestedQty: requestedQty,
                              note: note,
                            );
                        if (saved) {
                          onLineSaved(line.id);
                          onNotify('${line.itemName} disimpan.');
                          return;
                        }
                        onNotify(
                          describeFailure(
                            ref
                                    .read(purchaseRequestFormControllerProvider)
                                    .error ??
                                'Gagal menyimpan baris.',
                          ),
                        );
                      },
                      onRemove: () async {
                        final removed = await ref
                            .read(
                              purchaseRequestFormControllerProvider.notifier,
                            )
                            .removeLine(line.id);
                        onLineSaved(line.id);
                        onNotify(
                          removed
                              ? '${line.itemName} dihapus dari permintaan.'
                              : describeFailure(
                                  ref
                                          .read(
                                            purchaseRequestFormControllerProvider,
                                          )
                                          .error ??
                                      'Gagal menghapus baris.',
                                ),
                        );
                      },
                    ),
                  ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.icon(
              key: PurchaseRequestFormPage.submitButtonKey,
              onPressed: busy ? null : onSubmit,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(busy ? 'Mengirim…' : 'Kirim ke Warehouse'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Document number, needed date, note and the citations behind the suggestions.
class _HeaderCard extends ConsumerStatefulWidget {
  const _HeaderCard({required this.detail, required this.onEditCitations});

  final PurchaseRequestDetail detail;
  final Future<void> Function() onEditCitations;

  @override
  ConsumerState<_HeaderCard> createState() => _HeaderCardState();
}

class _HeaderCardState extends ConsumerState<_HeaderCard> {
  late final TextEditingController _noteController;
  DateTime? _neededDate;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(
      text: widget.detail.request.note ?? '',
    );
    _neededDate = widget.detail.request.neededDate;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveHeader() async {
    final note = _noteController.text.trim();
    final saved = await ref
        .read(purchaseRequestFormControllerProvider.notifier)
        .saveHeader(
          prId: widget.detail.id,
          neededDate: _neededDate,
          note: note.isEmpty ? null : note,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Informasi permintaan disimpan.'
                : describeFailure(
                    ref.read(purchaseRequestFormControllerProvider).error ??
                        'Gagal menyimpan informasi permintaan.',
                  ),
          ),
        ),
      );
  }

  Future<void> _pickNeededDate() async {
    final today = DateOnly.from(
      ref.read(currentPurchaseRequestPeriodProvider).mondayDate,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: _neededDate ?? DateOnly.addDays(today, 7),
      firstDate: DateOnly.addDays(today, -30),
      lastDate: DateOnly.addDays(today, 365),
    );
    if (picked == null || !mounted) return;
    setState(() => _neededDate = DateOnly.from(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = widget.detail;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.request.docNumber,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Nomor sementara sampai dokumen tersinkron ke server.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Stok opname acuan (${detail.opnames.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('prEditCitations'),
                    onPressed: widget.onEditCitations,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Ubah'),
                  ),
                ],
              ),
              for (final reference in detail.opnames)
                EligibleOpnameTile(reference: reference, selected: true),
              const Divider(height: AppSpacing.lg),
              ListTile(
                key: const ValueKey('prNeededDateField'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Tanggal barang dibutuhkan'),
                subtitle: Text(
                  _neededDate == null
                      ? 'Belum dipilih (opsional)'
                      : AppDateTimeFormatter.civilDate(_neededDate!),
                ),
                trailing: _neededDate == null
                    ? null
                    : IconButton(
                        tooltip: 'Hapus tanggal',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _neededDate = null),
                      ),
                onTap: _pickNeededDate,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('prHeaderNoteField'),
                controller: _noteController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan permintaan (opsional)',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _saveHeader,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan informasi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the editor is opened on a document that is no longer a draft.
///
/// The route guard already refuses this, so reaching it means the document was
/// submitted from another device while the screen was open — a race, not a
/// permission problem, and the right answer is to offer the read-only view rather
/// than an access refusal.
class _NotEditableNotice extends StatelessWidget {
  const _NotEditableNotice({required this.detail});

  final PurchaseRequestDetail detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Purchase Request ${detail.request.docNumber} sudah '
              '${detail.status.label.toLowerCase()} dan tidak dapat diubah.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => context.pushReplacementNamed(
                AppRoutes.purchaseRequestDetailName,
                pathParameters: {'id': detail.id},
              ),
              child: const Text('Lihat detail permintaan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the quantity and the mandatory reason of a manual line (G-P3).
class _AddManualLineDialog extends StatefulWidget {
  const _AddManualLineDialog({required this.item});

  final MasterItem item;

  @override
  State<_AddManualLineDialog> createState() => _AddManualLineDialogState();
}

class _AddManualLineDialogState extends State<_AddManualLineDialog> {
  final TextEditingController _noteController = TextEditingController();
  Quantity? _qty;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      (_qty?.isPositive ?? false) && _noteController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('prAddManualLineDialog'),
      title: Text('Tambah ${widget.item.name}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Barang ini tidak disarankan oleh stok opname acuan, sehingga '
              'catatan alasan wajib diisi.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            QuantityField(
              key: const ValueKey('prManualQty'),
              label: 'Jumlah diminta',
              unit: widget.item.unit,
              autofocus: true,
              onChanged: (value) => setState(() => _qty = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('prManualNote'),
              controller: _noteController,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Catatan alasan (wajib)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const ValueKey('prManualConfirm'),
          onPressed: _canSubmit
              ? () => Navigator.of(
                  context,
                ).pop((qty: _qty!, note: _noteController.text.trim()))
              : null,
          child: const Text('Tambahkan'),
        ),
      ],
    );
  }
}

/// Re-picks the citations of a draft, which recomputes every suggestion (§19.3).
class _EditCitationsDialog extends ConsumerStatefulWidget {
  const _EditCitationsDialog({required this.branchId, required this.initial});

  final String branchId;
  final Set<String> initial;

  @override
  ConsumerState<_EditCitationsDialog> createState() =>
      _EditCitationsDialogState();
}

class _EditCitationsDialogState extends ConsumerState<_EditCitationsDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final eligible = ref.watch(eligibleOpnamesProvider);

    return AlertDialog(
      key: const ValueKey('prEditCitationsDialog'),
      title: const Text('Ubah Stok Opname Acuan'),
      content: SizedBox(
        width: 420,
        child: eligible.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(describeFailure(error)),
          data: (rows) => rows.isEmpty
              ? const Text(
                  'Tidak ada stok opname yang dapat dijadikan acuan pada '
                  'minggu berjalan atau minggu sebelumnya.',
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final reference in rows)
                        EligibleOpnameTile(
                          reference: reference,
                          selected: _selected.contains(reference.opnameId),
                          onChanged: (value) => setState(() {
                            if (value) {
                              _selected.add(reference.opnameId);
                            } else {
                              _selected.remove(reference.opnameId);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const ValueKey('prEditCitationsConfirm'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Hitung ulang saran'),
        ),
      ],
    );
  }
}
