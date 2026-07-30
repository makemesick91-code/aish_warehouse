import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/disposal_models.dart';
import '../../domain/services/disposal_reason_policy.dart';
import '../providers/disposal_providers.dart';
import '../widgets/disposal_badges.dart';
import '../widgets/disposal_candidate_picker.dart';

/// The Pemusnahan draft editor (§30/§31).
///
/// Everything on this screen is a *proposal* until it is stored, and everything
/// stored is still a proposal until the document is posted. The three checks that
/// matter — the batch is expired, the quantity fits the shelf, the reason says
/// something — run when a line is added, again when it is edited, and a final time
/// inside the posting transaction against balances read there. What the screen shows
/// is a photograph; the posting is the shelf.
///
/// ### Why the flush matters here
///
/// A quantity typed into a field is not stored until it is saved, and Flutter has no
/// notion of "the user is done typing". So *Posting Pemusnahan* flushes every pending
/// edit first, re-reads the document from the database, and only then opens the
/// confirmation dialog — otherwise the dialog would describe a document that differs
/// from the one about to be posted, and the user would confirm a number they never
/// saw. §31 asks for exactly that order.
///
/// ### What is deliberately absent
///
/// * **No destination picker.** A disposal has one leg (§20); there is nothing to
///   choose.
/// * **No source picker.** The source is fixed when the document is created, because
///   it decides who may post it.
/// * **No near-expiry or valid batch anywhere.** The picker asks the repository for
///   expired positions, and there is no query that would return anything else.
/// * **No approval action.** The button says *Posting Pemusnahan*, and there is no
///   *Setujui* anywhere in this milestone.
class DisposalFormPage extends ConsumerStatefulWidget {
  const DisposalFormPage({
    super.key,
    required this.disposalId,
    required this.scope,
  });

  final String disposalId;

  /// Which side reached this document, so navigation after posting stays on it.
  final DisposalLocationScope scope;

  static const Key formKey = ValueKey('disposalForm');
  static const Key headerKey = ValueKey('disposalFormHeader');
  static const Key linesKey = ValueKey('disposalFormLines');
  static const Key emptyKey = ValueKey('disposalFormEmpty');
  static const Key addKey = ValueKey('disposalAddPositionButton');
  static const Key postKey = ValueKey('disposalPostButton');
  static const Key confirmKey = ValueKey('disposalPostConfirm');
  static const Key confirmAcceptKey = ValueKey('disposalPostConfirmAccept');
  static const Key confirmCancelKey = ValueKey('disposalPostConfirmCancel');
  static const Key reasonDetailKey = ValueKey('disposalReasonDetail');
  static const Key reasonMissingKey = ValueKey('disposalReasonMissing');

  static Key reasonPresetKeyFor(String code) =>
      ValueKey('disposalReasonPreset-$code');

  static Key qtyFieldKeyFor(String lineId) =>
      ValueKey('disposalQtyField-$lineId');

  static Key lineNoteKeyFor(String lineId) =>
      ValueKey('disposalLineNote-$lineId');

  static Key removeKeyFor(String lineId) => ValueKey('disposalRemove-$lineId');

  static Key remainingKeyFor(String lineId) =>
      ValueKey('disposalRemaining-$lineId');

  @override
  ConsumerState<DisposalFormPage> createState() => _DisposalFormPageState();
}

class _DisposalFormPageState extends ConsumerState<DisposalFormPage> {
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _noteControllers = {};

  /// One [GlobalKey] per line, so the form can scroll to a specific card (§31.5).
  ///
  /// Created once per line id and reused for the lifetime of the page — never
  /// rebuilt in `build`. A key recreated on each build would attach to a different
  /// element every frame, which makes `currentContext` point at whatever was there
  /// last time and `ensureVisible` scroll to the wrong card, or to nothing.
  final Map<String, GlobalKey> _lineKeys = {};

  /// One [FocusNode] per line's quantity field, for the same reason and with the
  /// same lifetime. The page owns them, so `QuantityField` does not dispose them.
  final Map<String, FocusNode> _qtyFocusNodes = {};

  final TextEditingController _reasonDetail = TextEditingController();

  /// Which preset chip is selected, or `null` for free text only. Never stored —
  /// what goes into the column is the *label* (§19).
  String? _presetCode;

  /// Set once the stored reason has been decomposed back into a chip plus a detail,
  /// so a rebuild does not overwrite what the user is typing.
  bool _reasonPrimed = false;

  @override
  void dispose() {
    // Everything the page created, released exactly once — including the entries
    // belonging to lines that were removed while it was open. `_removeLine`
    // deliberately leaves those in place rather than disposing them under a card
    // that is still mounted; this is where they finally go.
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    for (final node in _qtyFocusNodes.values) {
      node.dispose();
    }
    _qtyControllers.clear();
    _noteControllers.clear();
    _qtyFocusNodes.clear();
    _lineKeys.clear();
    _reasonDetail.dispose();
    super.dispose();
  }

  bool get _isBranch => widget.scope == DisposalLocationScope.branch;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(disposalDetailProvider(widget.disposalId));
    final nowUtc = ref.watch(disposalClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Pemusnahan Stok')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
        data: (document) {
          if (document == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: DisposalNotice(
                title: 'Dokumen tidak tersedia',
                message:
                    'Pemusnahan ini tidak ditemukan atau berada di luar '
                    'cakupan akun Anda.',
                icon: Icons.lock_outline,
              ),
            );
          }
          // A posted document is read-only permanently (G-S2). The route guard
          // already refuses it, and this is the second answer for a document that
          // posted while the screen was open.
          if (!document.isEditable) {
            return _PostedRedirect(
              disposalId: widget.disposalId,
              scope: widget.scope,
            );
          }
          _primeReason(document);
          return _buildForm(document, nowUtc);
        },
      ),
    );
  }

  /// Splits a stored reason back into the chip that produced it plus its detail, so
  /// reopening a draft shows the choice that was made rather than a blank form.
  ///
  /// Runs once. A rebuild triggered by the stream — another field being saved, say —
  /// must not overwrite text the user is halfway through typing.
  void _primeReason(DisposalDetail document) {
    if (_reasonPrimed) return;
    _reasonPrimed = true;
    final reason = document.disposal.reason;
    if (reason == null) return;

    for (final preset in DisposalReasonPolicy.presets) {
      if (reason == preset.label) {
        _presetCode = preset.code;
        return;
      }
      final prefix = '${preset.label}${DisposalReasonPolicy.separator}';
      if (reason.startsWith(prefix)) {
        _presetCode = preset.code;
        _reasonDetail.text = reason.substring(prefix.length);
        return;
      }
    }
    _reasonDetail.text = reason;
  }

  Widget _buildForm(DisposalDetail document, DateTime nowUtc) {
    final busy = ref.watch(disposalEditorControllerProvider).isLoading;
    final lines = document.orderedLines;
    // What the document's own shelf holds right now, so each line can say how much
    // is there and how much would be left (§30). A snapshot: the posting re-reads
    // it inside its transaction, and that read is the authority.
    final positions =
        ref.watch(disposalDocumentPositionsProvider(widget.disposalId)).value ??
        const <String, ExpiredStockPosition>{};

    return Column(
      key: DisposalFormPage.formKey,
      children: [
        Expanded(
          // A `SingleChildScrollView` rather than a lazy `ListView`, and the choice
          // is what makes §31.5 work at all: a lazy list does not mount a card that
          // is far below the fold, so its `GlobalKey.currentContext` is null and
          // `Scrollable.ensureVisible` silently does nothing — for exactly the line
          // the user most needs to be shown. Every card is mounted here, so the
          // scroll always lands. A document holds one line per expired position on
          // one shelf, so the cost is bounded and small.
          child: SingleChildScrollView(
            key: DisposalFormPage.linesKey,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl * 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(document: document),
                _ReasonSection(
                  presetCode: _presetCode,
                  detailController: _reasonDetail,
                  enabled: !busy,
                  onPresetSelected: (code) => setState(
                    () => _presetCode = _presetCode == code ? null : code,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: FilledButton.tonalIcon(
                    key: DisposalFormPage.addKey,
                    onPressed: busy ? null : () => _openPicker(document),
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Tambah Stok Kedaluwarsa'),
                  ),
                ),
                if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Card(
                      key: DisposalFormPage.emptyKey,
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'Belum ada barang yang dipilih. Tekan "Tambah Stok '
                          'Kedaluwarsa" untuk memilih batch yang sudah melewati '
                          'tanggal kedaluwarsa.',
                        ),
                      ),
                    ),
                  )
                else
                  for (final line in lines)
                    _LineCard(
                      key: _lineKeyFor(line),
                      line: line,
                      nowUtc: nowUtc,
                      enabled: !busy,
                      available: positions[line.positionKey]?.qtyOnHand,
                      qtyController: _qtyControllerFor(line),
                      qtyFocusNode: _qtyFocusFor(line),
                      noteController: _noteControllerFor(line),
                      onRemove: () => _removeLine(line),
                    ),
              ],
            ),
          ),
        ),
        _PostBar(document: document, busy: busy, onPost: () => _post(document)),
      ],
    );
  }

  TextEditingController _qtyControllerFor(DisposalLine line) =>
      _qtyControllers.putIfAbsent(
        line.id,
        () => TextEditingController(text: line.qty.format()),
      );

  TextEditingController _noteControllerFor(DisposalLine line) =>
      _noteControllers.putIfAbsent(
        line.id,
        () => TextEditingController(text: line.note ?? ''),
      );

  /// The card's key, created once per line id and never rebuilt.
  GlobalKey _lineKeyFor(DisposalLine line) =>
      _lineKeys.putIfAbsent(line.id, GlobalKey.new);

  /// The quantity field's focus node, created once per line id.
  FocusNode _qtyFocusFor(DisposalLine line) => _qtyFocusNodes.putIfAbsent(
    line.id,
    () => FocusNode(debugLabel: 'disposalQty-${line.id}'),
  );

  /// Brings the first invalid line into view and puts the cursor in it (§31.5).
  ///
  /// A message on its own is not enough on a long document: it names a batch the
  /// user then has to go looking for, and the field they need is the one thing the
  /// screen can point at directly.
  ///
  /// Both halves are guarded rather than assumed. The card may have been unmounted
  /// between the validation and this call — a stream emission removing the line, the
  /// page being popped — so a null `currentContext` and an unattached focus node are
  /// ordinary outcomes, not errors: the message still appears and nothing throws.
  Future<void> _revealLine(DisposalLine line) async {
    final context = _lineKeys[line.id]?.currentContext;
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(
        context,
        // Just below the top edge, so the card is fully visible with a little of the
        // previous one showing — enough context to see where in the document it sits.
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
    if (!mounted) return;

    // Re-read the card's context *after* the scroll rather than reusing the one
    // captured above: awaiting gave the stream a chance to emit, and the line may
    // have been removed in the meantime. A node whose field has been unmounted has
    // no context of its own either, so both checks answer the same question and
    // neither throws when the answer is no.
    final node = _qtyFocusNodes[line.id];
    final stillMounted = _lineKeys[line.id]?.currentContext?.mounted ?? false;
    if (node != null && stillMounted && node.context != null) {
      node.requestFocus();
    }
  }

  Future<void> _openPicker(DisposalDetail document) async {
    final taken = {for (final line in document.lines) line.positionKey};
    final chosen = await showModalBottomSheet<DisposalCandidateChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DisposalCandidatePicker(alreadyChosen: taken),
    );
    if (chosen == null || !mounted) return;

    final ok = await ref
        .read(disposalEditorControllerProvider.notifier)
        .addPosition(
          disposalId: document.id,
          itemId: chosen.position.itemId,
          batchId: chosen.position.batchId,
          qty: chosen.qty,
        );
    if (!mounted) return;
    if (!ok) _reportLastError('Gagal menambah barang.');
  }

  Future<void> _removeLine(DisposalLine line) async {
    final ok = await ref
        .read(disposalEditorControllerProvider.notifier)
        .removeLine(disposalId: widget.disposalId, lineId: line.id);
    if (!mounted) return;
    if (!ok) _reportLastError('Gagal menghapus baris.');
    // The removed line's controllers are deliberately **not** disposed here. The
    // card that owns them is still mounted at this instant — the stream has not
    // re-emitted yet — and its `State.dispose` will detach a listener from them a
    // moment later. Disposing first would make that detach throw. They stay in the
    // maps and go with the page, which costs two objects per removed line and
    // cannot be reused by mistake: a re-added position is a new row with a new id.
  }

  /// Writes every pending edit, returning `false` as soon as one is refused.
  ///
  /// The reason first, then each line. Order matters only in that a refusal stops
  /// the rest: a document half-flushed and then posted would be posted with numbers
  /// the user never confirmed.
  ///
  /// The lines are walked in **display** order, so "the first invalid line" means the
  /// first one the user can see rather than whichever row the database happened to
  /// return first — the two differ, and scrolling to the wrong one would be worse
  /// than not scrolling at all.
  Future<bool> _flushPendingEdits(DisposalDetail document) async {
    final controller = ref.read(disposalEditorControllerProvider.notifier);

    final composed = DisposalReasonPolicy.compose(
      presetCode: _presetCode,
      detail: _reasonDetail.text,
    );
    if (composed != document.disposal.reason) {
      final ok = await controller.updateReason(
        disposalId: document.id,
        reason: composed,
      );
      if (!ok) return false;
    }

    for (final line in document.orderedLines) {
      final typed = Quantity.tryParse(_qtyControllers[line.id]?.text ?? '');
      final note = DisposalReasonPolicy.normalize(
        _noteControllers[line.id]?.text,
      );
      // Two ways a field can be unusable, and both are the *user's* to fix rather
      // than the use case's to refuse: text that is not a quantity at all, and a
      // quantity of zero. Caught here so the screen can point at the field; the use
      // case and the database CHECK refuse them again underneath.
      if (typed == null || !typed.isPositive) {
        await _revealLine(line);
        if (!mounted) return false;
        _reportError(
          'Jumlah untuk ${line.itemName} batch ${line.batchNo} belum valid.',
        );
        return false;
      }
      if (typed == line.qty && note == line.note) continue;
      final ok = await controller.updateLine(
        disposalId: document.id,
        lineId: line.id,
        qty: typed,
        note: note,
      );
      if (!ok) {
        // The write itself was refused — an over-balance quantity, a batch that
        // stopped qualifying. The line is still the one to look at.
        await _revealLine(line);
        return false;
      }
    }
    return true;
  }

  Future<void> _post(DisposalDetail document) async {
    // 1. Flush, so what is confirmed is what is stored (§31).
    if (!await _flushPendingEdits(document)) {
      if (mounted) _reportLastError('Perubahan belum tersimpan.');
      return;
    }
    if (!mounted) return;

    // 2. Re-read from the database after the flush (§31). `refresh` rather than
    // `read`: the live stream may not have re-emitted yet, and the dialog has to
    // describe the *stored* document rather than the one this method was handed.
    final refreshed = await ref.refresh(
      disposalDetailSnapshotProvider(widget.disposalId).future,
    );
    if (!mounted) return;
    if (refreshed == null) {
      _reportError('Dokumen tidak lagi tersedia.');
      return;
    }

    // 3–4. The two preconditions a user can still fix, each with its own sentence.
    if (refreshed.isEmpty) {
      _reportError(
        'Belum ada barang yang dipilih, sehingga pemusnahan tidak dapat '
        'diposting.',
      );
      return;
    }
    if (!refreshed.disposal.hasReason) {
      _reportError(
        'Catatan pemusnahan wajib diisi sebelum dokumen dapat diposting.',
      );
      return;
    }

    // 5–10. Confirm, naming the source, the number of positions and what will
    // happen to the stock.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: DisposalFormPage.confirmKey,
        title: const Text('Posting Pemusnahan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${refreshed.lineCount} posisi akan dikeluarkan dari '
              '${refreshed.source.kindLabel} ${refreshed.source.name}.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Tidak ada lokasi tujuan — stok keluar dari sistem.'),
            const SizedBox(height: AppSpacing.sm),
            const DisposalFinalityNotice(),
          ],
        ),
        actions: [
          TextButton(
            key: DisposalFormPage.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: DisposalFormPage.confirmAcceptKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Posting Pemusnahan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 12–14. The button is already disabled while `state.isLoading`, and the
    // controller refuses a second call on top of an in-flight one.
    final ok = await ref
        .read(disposalEditorControllerProvider.notifier)
        .post(refreshed.id);
    if (!mounted) return;

    if (!ok) {
      _reportLastError('Pemusnahan gagal diposting.');
      return;
    }

    final result = ref
        .read(disposalEditorControllerProvider.notifier)
        .lastPosting;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pemusnahan diposting: ${result?.lineCount ?? refreshed.lineCount} '
          'posisi dikeluarkan dari stok.',
        ),
      ),
    );
    // 15. Straight into the read-only detail, so the next thing the user sees is
    // what the document now says rather than a form they can no longer use.
    context.pushReplacementNamed(
      _isBranch
          ? AppRoutes.disposalDetailName
          : AppRoutes.warehouseDisposalDetailName,
      pathParameters: {'id': refreshed.id},
    );
  }

  void _reportLastError(String fallback) {
    final error = ref.read(disposalEditorControllerProvider).error;
    _reportError(describeFailure(error ?? fallback));
  }

  void _reportError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Sends a document that is no longer editable to its read-only detail.
///
/// Reached when a draft posts while its form is open — from another device, or from
/// this one after a successful post. Rendering the form's fields against a final
/// document would offer edits every write path refuses.
class _PostedRedirect extends StatelessWidget {
  const _PostedRedirect({required this.disposalId, required this.scope});

  final String disposalId;
  final DisposalLocationScope scope;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DisposalNotice(
            title: 'Sudah diposting',
            message:
                'Pemusnahan ini sudah diposting dan tidak dapat diubah lagi.',
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () => context.pushReplacementNamed(
              scope == DisposalLocationScope.branch
                  ? AppRoutes.disposalDetailName
                  : AppRoutes.warehouseDisposalDetailName,
              pathParameters: {'id': disposalId},
            ),
            child: const Text('Lihat detail'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.document});

  final DisposalDetail document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disposal = document.disposal;

    return Padding(
      key: DisposalFormPage.headerKey,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
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
                      disposal.docNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DisposalStatusChip(status: disposal.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Sumber: ${document.source.kindLabel} · '
                '${document.summary.sourceLabel}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Dibuat ${document.summary.createdByName} · '
                // UTC in storage, operational time on screen (T-1/T-2).
                '${AppDateTimeFormatter.dateTimeWithZone(disposal.createdAt)}',
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
                    document.summary.label,
                    style: theme.textTheme.bodySmall,
                  ),
                  SyncStatusTag(status: disposal.syncStatus),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// G-E7's mandatory note, as a set of chips plus a free-text detail (§19).
class _ReasonSection extends StatelessWidget {
  const _ReasonSection({
    required this.presetCode,
    required this.detailController,
    required this.enabled,
    required this.onPresetSelected,
  });

  final String? presetCode;
  final TextEditingController detailController;
  final bool enabled;
  final ValueChanged<String> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = DisposalReasonPolicy.presetByCode(presetCode);
    final needsDetail = preset?.requiresDetail ?? false;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Catatan pemusnahan',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Wajib diisi. Catatan ini tersimpan pada setiap pergerakan stok '
                'sebagai alasan pemusnahan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final option in DisposalReasonPolicy.presets)
                    ChoiceChip(
                      key: DisposalFormPage.reasonPresetKeyFor(option.code),
                      label: Text(option.label),
                      selected: presetCode == option.code,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: enabled
                          ? (_) => onPresetSelected(option.code)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: DisposalFormPage.reasonDetailKey,
                controller: detailController,
                enabled: enabled,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: needsDetail
                      ? 'Detail alasan (wajib)'
                      : 'Detail tambahan (opsional)',
                  helperText: needsDetail
                      ? 'Pilihan "Lainnya" harus dijelaskan agar catatan audit '
                            'dapat dibaca.'
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One chosen position on the form.
class _LineCard extends StatefulWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.nowUtc,
    required this.enabled,
    required this.available,
    required this.qtyController,
    required this.qtyFocusNode,
    required this.noteController,
    required this.onRemove,
  });

  final DisposalLine line;
  final DateTime nowUtc;
  final bool enabled;

  /// What the shelf holds for this exact position, or `null` while it is still
  /// loading. Never a number the widget derived itself.
  final Quantity? available;

  final TextEditingController qtyController;

  /// Owned by the page, so it survives this card being rebuilt and stays reachable
  /// when the form needs to focus this line (§31.5).
  final FocusNode qtyFocusNode;

  final TextEditingController noteController;
  final VoidCallback onRemove;

  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  @override
  void initState() {
    super.initState();
    // The remaining figure has to follow the field as it is typed, not only once it
    // is saved — a number that lagged a keystroke behind would reassure the user
    // about a quantity they had already changed.
    widget.qtyController.addListener(_onQtyChanged);
  }

  @override
  void dispose() {
    widget.qtyController.removeListener(_onQtyChanged);
    super.dispose();
  }

  void _onQtyChanged() {
    if (mounted) setState(() {});
  }

  DisposalLine get line => widget.line;

  DateTime get nowUtc => widget.nowUtc;

  bool get enabled => widget.enabled;

  TextEditingController get qtyController => widget.qtyController;

  TextEditingController get noteController => widget.noteController;

  VoidCallback get onRemove => widget.onRemove;

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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                          '${line.sku} · batch ${line.batchNo}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: DisposalFormPage.removeKeyFor(line.id),
                    tooltip: 'Hapus baris',
                    onPressed: enabled ? onRemove : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DisposalExpiryBadge(
                    expiryDate: line.expiryDate,
                    expiryAlertDays: 0,
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
              const SizedBox(height: AppSpacing.sm),
              QuantityField(
                key: DisposalFormPage.qtyFieldKeyFor(line.id),
                controller: qtyController,
                focusNode: widget.qtyFocusNode,
                label: 'Jumlah dimusnahkan',
                unit: line.unit,
                enabled: enabled,
              ),
              _RemainingRow(
                lineId: line.id,
                unit: line.unit,
                available: widget.available,
                typed: Quantity.tryParse(qtyController.text),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: DisposalFormPage.lineNoteKeyFor(line.id),
                controller: noteController,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Catatan baris (opsional)',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// *"Tersedia 5.5 ampul · sisa 3.125 ampul"* — what the shelf holds and what would
/// be left (§30).
///
/// The arithmetic comes from [DisposalDraft] rather than being done here, because it
/// is the same subtraction the use case performs and a widget that reimplemented it
/// would eventually show a reassuring number the ledger then contradicts. When the
/// typed quantity exceeds the shelf the row says so instead of rendering a
/// meaningless remainder — clamping silently is what §31 forbids.
class _RemainingRow extends StatelessWidget {
  const _RemainingRow({
    required this.lineId,
    required this.unit,
    required this.available,
    required this.typed,
  });

  final String lineId;
  final String unit;
  final Quantity? available;

  /// `null` while the field is not (yet) a valid quantity.
  final Quantity? typed;

  @override
  Widget build(BuildContext context) {
    final shelf = available;
    if (shelf == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final qty = typed ?? Quantity.zero();
    final exceeds = qty > shelf;
    final remaining = exceeds ? Quantity.zero() : shelf - qty;

    return Padding(
      key: DisposalFormPage.remainingKeyFor(lineId),
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        exceeds
            ? 'Tersedia ${shelf.formatWithUnit(unit)} — jumlah melebihi saldo '
                  'lokasi.'
            : 'Tersedia ${shelf.formatWithUnit(unit)} · sisa '
                  '${remaining.formatWithUnit(unit)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: exceeds
              ? AppColors.danger
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The posting bar: what the document says, and the one button that acts on it.
class _PostBar extends StatelessWidget {
  const _PostBar({
    required this.document,
    required this.busy,
    required this.onPost,
  });

  final DisposalDetail document;
  final bool busy;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!document.disposal.hasReason)
              Padding(
                key: DisposalFormPage.reasonMissingKey,
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Catatan pemusnahan wajib diisi.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    document.summary.label,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                FilledButton.icon(
                  key: DisposalFormPage.postKey,
                  // Disabled while an action is in flight and while the document has
                  // nothing on it. The reason is deliberately *not* part of this
                  // predicate: the button stays live so pressing it produces the
                  // sentence that says what is missing, rather than a control that
                  // is dead for a reason the user has to guess.
                  onPressed: busy || document.isEmpty ? null : onPost,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Posting Pemusnahan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
