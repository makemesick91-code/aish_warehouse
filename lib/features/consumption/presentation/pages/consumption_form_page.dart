import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/consumption_models.dart';
import '../../domain/services/consumption_note_policy.dart';
import '../providers/consumption_providers.dart';
import '../widgets/consumption_badges.dart';
import '../widgets/consumption_candidate_picker.dart';
import '../widgets/consumption_filters.dart';

/// The Pemakaian draft editor (§28/§29).
///
/// Everything on this screen is a *proposal* until it is stored, and everything stored is
/// still a proposal until the document is posted. The three checks that matter — the batch
/// has not expired, the quantity fits the room's shelf, the room is still operational —
/// run when a line is added, again when it is edited, and a final time inside the posting
/// transaction against balances read there. What the screen shows is a photograph; the
/// posting is the shelf.
///
/// ### Why the flush matters here
///
/// A quantity typed into a field is not stored until it is saved, and Flutter has no
/// notion of "the user is done typing". So *Posting Pemakaian* flushes every pending edit
/// first, re-reads the document from the database, and only then opens the confirmation
/// dialog — otherwise the dialog would describe a document that differs from the one about
/// to be posted, and the nurse would confirm a number they never saw. §29 asks for exactly
/// that order.
///
/// ### What is deliberately absent
///
/// * **No destination picker.** A consumption has one leg (§19); there is nothing to
///   choose.
/// * **No room picker.** The room is fixed when the document is created, because it
///   decides whose stock this reduces.
/// * **No expired batch anywhere.** The picker asks the repository for consumable
///   positions, and there is no query that would return anything else (G-E7).
/// * **No FEFO override reason.** §17 does not ask for one, so there is no field to hold
///   it — a near-expiry batch is picked exactly as any other, with an orange badge
///   encouraging it.
/// * **No approval action.** The button says *Posting Pemakaian*, and there is no
///   *Setujui* and no *Ajukan* anywhere in this milestone.
/// * **No patient field.** Not a name, not a record number, not a procedure (§9). The
///   only free text is the document's note and each line's own detail, and both are about
///   stock.
class ConsumptionFormPage extends ConsumerStatefulWidget {
  const ConsumptionFormPage({super.key, required this.consumptionId});

  final String consumptionId;

  static const Key formKey = ValueKey('consumptionForm');
  static const Key headerKey = ValueKey('consumptionFormHeader');
  static const Key linesKey = ValueKey('consumptionFormLines');
  static const Key emptyKey = ValueKey('consumptionFormEmpty');
  static const Key addKey = ValueKey('consumptionAddPositionButton');
  static const Key postKey = ValueKey('consumptionPostButton');
  static const Key confirmKey = ValueKey('consumptionPostConfirm');
  static const Key confirmAcceptKey = ValueKey('consumptionPostConfirmAccept');
  static const Key confirmCancelKey = ValueKey('consumptionPostConfirmCancel');
  static const Key noteKey = ValueKey('consumptionNoteField');
  static const Key expiredLineKey = ValueKey('consumptionExpiredLineNotice');

  static Key qtyFieldKeyFor(String lineId) =>
      ValueKey('consumptionQtyField-$lineId');

  static Key lineNoteKeyFor(String lineId) =>
      ValueKey('consumptionLineNote-$lineId');

  static Key removeKeyFor(String lineId) =>
      ValueKey('consumptionRemove-$lineId');

  static Key remainingKeyFor(String lineId) =>
      ValueKey('consumptionRemaining-$lineId');

  static Key lineCardKeyFor(String lineId) =>
      ValueKey('consumptionLineCard-$lineId');

  @override
  ConsumerState<ConsumptionFormPage> createState() =>
      _ConsumptionFormPageState();
}

class _ConsumptionFormPageState extends ConsumerState<ConsumptionFormPage> {
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _noteControllers = {};

  /// One [GlobalKey] per line, so the form can scroll to a specific card (§29.5).
  ///
  /// Created once per line id and reused for the lifetime of the page — never rebuilt in
  /// `build`. A key recreated on each build would attach to a different element every
  /// frame, which makes `currentContext` point at whatever was there last time and
  /// `ensureVisible` scroll to the wrong card, or to nothing.
  final Map<String, GlobalKey> _lineKeys = {};

  /// One [FocusNode] per line's quantity field, for the same reason and with the same
  /// lifetime. The page owns them, so `QuantityField` does not dispose them.
  final Map<String, FocusNode> _qtyFocusNodes = {};

  final TextEditingController _note = TextEditingController();

  /// Set once the stored note has been copied into the field, so a rebuild does not
  /// overwrite what the nurse is typing.
  bool _notePrimed = false;

  @override
  void dispose() {
    // Everything the page created, released exactly once — including the entries
    // belonging to lines that were removed while it was open (see `_removeLine`).
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    for (final node in _qtyFocusNodes.values) {
      node.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  TextEditingController _qtyControllerFor(ConsumptionLine line) =>
      _qtyControllers.putIfAbsent(
        line.id,
        () => TextEditingController(text: line.qty.format()),
      );

  TextEditingController _noteControllerFor(ConsumptionLine line) =>
      _noteControllers.putIfAbsent(
        line.id,
        () => TextEditingController(text: line.note ?? ''),
      );

  /// The card's key, created once per line id and never rebuilt.
  GlobalKey _lineKeyFor(ConsumptionLine line) =>
      _lineKeys.putIfAbsent(line.id, GlobalKey.new);

  /// The quantity field's focus node, created once per line id.
  FocusNode _qtyFocusFor(ConsumptionLine line) => _qtyFocusNodes.putIfAbsent(
    line.id,
    () => FocusNode(debugLabel: 'consumptionQty-${line.id}'),
  );

  /// Brings the first invalid line into view and puts the cursor in it (§29.5).
  ///
  /// A message on its own is not enough on a long document: it names a batch the nurse
  /// then has to go looking for, and the field they need is the one thing the screen can
  /// point at directly.
  ///
  /// Both halves are guarded rather than assumed. The card may have been unmounted between
  /// the validation and this call — a stream emission removing the line, the page being
  /// popped — so a null `currentContext` and an unattached focus node are ordinary
  /// outcomes, not errors: the message still appears and nothing throws.
  Future<void> _revealLine(ConsumptionLine line) async {
    final cardContext = _lineKeys[line.id]?.currentContext;
    if (cardContext != null && cardContext.mounted) {
      await Scrollable.ensureVisible(
        cardContext,
        // Just below the top edge, so the card is fully visible with a little of the
        // previous one showing — enough context to see where in the document it sits.
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
    if (!mounted) return;

    // Re-read the card's context *after* the scroll rather than reusing the one captured
    // above: awaiting gave the stream a chance to emit, and the line may have been removed
    // in the meantime. A node whose field has been unmounted has no context of its own
    // either, so both checks answer the same question and neither throws when the answer
    // is no.
    final node = _qtyFocusNodes[line.id];
    final stillMounted = _lineKeys[line.id]?.currentContext?.mounted ?? false;
    if (node != null && stillMounted && node.context != null) {
      node.requestFocus();
    }
  }

  Future<void> _openPicker(ConsumptionDetail document) async {
    final taken = {for (final line in document.lines) line.positionKey};
    final chosen = await showModalBottomSheet<ConsumptionCandidateChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConsumptionCandidatePicker(
        consumptionId: document.id,
        alreadyChosen: taken,
      ),
    );
    if (chosen == null || !mounted) return;

    final ok = await ref
        .read(consumptionEditorControllerProvider.notifier)
        .addPosition(
          consumptionId: document.id,
          itemId: chosen.position.itemId,
          batchId: chosen.position.batchId,
          qty: chosen.qty,
        );
    if (!mounted) return;
    if (!ok) _reportLastError('Gagal menambah barang.');
  }

  Future<void> _removeLine(ConsumptionLine line) async {
    final ok = await ref
        .read(consumptionEditorControllerProvider.notifier)
        .removeLine(consumptionId: widget.consumptionId, lineId: line.id);
    if (!mounted) return;
    if (!ok) _reportLastError('Gagal menghapus baris.');
    // The removed line's controllers are deliberately **not** disposed here. The card that
    // owns them is still mounted at this instant — the stream has not re-emitted yet — and
    // its `State.dispose` will detach a listener from them a moment later. Disposing first
    // would make that detach throw. They stay in the maps and go with the page, which
    // costs two objects per removed line and cannot be reused by mistake: a re-added
    // position is a new row with a new id.
  }

  /// Writes every pending edit, returning `false` as soon as one is refused.
  ///
  /// The note first, then each line. Order matters only in that a refusal stops the rest:
  /// a document half-flushed and then posted would be posted with numbers the nurse never
  /// confirmed.
  ///
  /// The lines are walked in **display** order, so "the first invalid line" means the
  /// first one the nurse can see rather than whichever row the database happened to return
  /// first — the two differ, and scrolling to the wrong one would be worse than not
  /// scrolling at all.
  Future<bool> _flushPendingEdits(ConsumptionDetail document) async {
    final controller = ref.read(consumptionEditorControllerProvider.notifier);

    final note = ConsumptionNotePolicy.normalize(_note.text);
    if (note != document.consumption.note) {
      final ok = await controller.updateNote(
        consumptionId: document.id,
        note: note,
      );
      if (!ok) return false;
    }

    for (final line in document.orderedLines) {
      final typed = Quantity.tryParse(_qtyControllers[line.id]?.text ?? '');
      final lineNote = ConsumptionNotePolicy.normalize(
        _noteControllers[line.id]?.text,
      );
      // Two ways a field can be unusable, and both are the *nurse's* to fix rather than
      // the use case's to refuse: text that is not a quantity at all, and a quantity of
      // zero. Caught here so the screen can point at the field; the use case and the
      // database CHECK refuse them again underneath.
      if (typed == null || !typed.isPositive) {
        await _revealLine(line);
        if (!mounted) return false;
        _reportError('Jumlah untuk ${_positionLabel(line)} belum valid.');
        return false;
      }
      if (typed == line.qty && lineNote == line.note) continue;
      final ok = await controller.updateLine(
        consumptionId: document.id,
        lineId: line.id,
        qty: typed,
        note: lineNote,
      );
      if (!ok) {
        // The write itself was refused — an over-balance quantity, a batch that expired
        // overnight. The line is still the one to look at.
        await _revealLine(line);
        return false;
      }
    }
    return true;
  }

  Future<void> _post(ConsumptionDetail document) async {
    // 1. Flush, so what is confirmed is what is stored (§29).
    if (!await _flushPendingEdits(document)) {
      if (mounted) _reportLastError('Perubahan belum tersimpan.');
      return;
    }
    if (!mounted) return;

    // 2. Re-read from the database after the flush (§29). `refresh` rather than `read`:
    // the live stream may not have re-emitted yet, and the dialog has to describe the
    // *stored* document rather than the one this method was handed.
    final refreshed = await ref.refresh(
      consumptionDetailSnapshotProvider(widget.consumptionId).future,
    );
    if (!mounted) return;
    if (refreshed == null) {
      _reportError('Dokumen tidak lagi tersedia.');
      return;
    }

    // 3. The one precondition a nurse can still fix. There is deliberately no note check
    // here: a consumption note is optional (§8).
    if (refreshed.isEmpty) {
      _reportError(
        'Belum ada barang yang dipilih, sehingga pemakaian tidak dapat '
        'diposting.',
      );
      return;
    }

    // 4. And the one that can drift underneath an open form: a batch that expired
    // overnight. Reported before the dialog, so the nurse fixes the document rather than
    // confirming a posting the use case will refuse.
    final progress = refreshed.progressOn(ref.read(consumptionClockProvider)());
    if (!progress.allUsable) {
      _reportError(
        '${progress.expiredCount} baris memuat batch yang sudah kedaluwarsa. '
        'Hapus baris tersebut — barang kedaluwarsa hanya keluar melalui '
        'pemusnahan.',
      );
      return;
    }

    // 5. And the other thing that can drift: the room's balance. Checked here against the
    // freshly-read positions so the nurse is told *before* being asked to confirm, rather
    // than after — §29's wording is the same either way, but confirming a posting that is
    // already doomed teaches people to dismiss dialogs. The posting re-reads the balances
    // inside its transaction regardless; this is a courtesy, not the authority.
    final positions = await ref.refresh(
      consumptionDocumentPositionsProvider(widget.consumptionId).future,
    );
    if (!mounted) return;
    for (final line in refreshed.orderedLines) {
      final available =
          positions[line.positionKey]?.qtyOnHand ?? Quantity.zero();
      if (line.qty > available) {
        await _revealLine(line);
        if (!mounted) return;
        _reportError(
          '${ConsumptionFinalityNotice.stockChangedMessage} '
          '${_positionLabel(line)}: tersedia '
          '${available.formatWithUnit(line.unit)}, tercatat '
          '${line.qty.formatWithUnit(line.unit)}.',
        );
        return;
      }
    }

    // 6–11. Confirm, naming the room, the number of positions and what will happen to the
    // stock.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: ConsumptionFormPage.confirmKey,
        title: const Text('Posting Pemakaian'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${refreshed.lineCount} posisi akan dicatat sebagai pemakaian di '
              '${refreshed.room.label}.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Tidak ada lokasi tujuan — stok keluar dari sistem.'),
            const SizedBox(height: AppSpacing.sm),
            const ConsumptionFinalityNotice(),
          ],
        ),
        actions: [
          TextButton(
            key: ConsumptionFormPage.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: ConsumptionFormPage.confirmAcceptKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Posting Pemakaian'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 12–14. The button is already disabled while `state.isLoading`, and the controller
    // refuses a second call on top of an in-flight one.
    final ok = await ref
        .read(consumptionEditorControllerProvider.notifier)
        .post(refreshed.id);
    if (!mounted) return;

    if (!ok) {
      _reportLastError('Pemakaian gagal diposting.');
      return;
    }

    final result = ref
        .read(consumptionEditorControllerProvider.notifier)
        .lastPosting;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pemakaian diposting: ${result?.lineCount ?? refreshed.lineCount} '
          'posisi keluar dari stok ruangan.',
        ),
      ),
    );
    // 15. Straight into the read-only detail, so the next thing the nurse sees is what the
    // document now says rather than a form they can no longer use.
    context.pushReplacementNamed(
      AppRoutes.consumptionDetailName,
      pathParameters: {'id': refreshed.id},
    );
  }

  /// The refusal a changed balance produces, worded the way §29 asks.
  ///
  /// A separate sentence from the generic failure text because it is the one refusal a
  /// nurse can act on immediately — and because §29 states it verbatim.
  void _reportLastError(String fallback) {
    final error = ref.read(consumptionEditorControllerProvider).error;
    if (error is InsufficientRoomStockFailure) {
      _reportError(
        '${ConsumptionFinalityNotice.stockChangedMessage} ${error.message}',
      );
      return;
    }
    _reportError(describeFailure(error ?? fallback));
  }

  void _reportError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _positionLabel(ConsumptionLine line) =>
      line.isBatched ? '${line.itemName} batch ${line.batchNo}' : line.itemName;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(consumptionDetailProvider(widget.consumptionId));
    final busy = ref.watch(consumptionEditorControllerProvider).isLoading;
    final nowUtc = ref.watch(consumptionClockProvider)();
    final positions =
        ref
            .watch(consumptionDocumentPositionsProvider(widget.consumptionId))
            .value ??
        const <String, RoomStockPosition>{};

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
                title: 'Dokumen tidak tersedia',
                message:
                    'Dokumen pemakaian ini tidak ditemukan atau bukan milik '
                    'Anda.',
                icon: Icons.lock_outline,
              ),
            ),
          );
        }

        // Prime the note field once, from the stored value.
        if (!_notePrimed) {
          _note.text = document.consumption.note ?? '';
          _notePrimed = true;
        }

        final progress = document.progressOn(nowUtc);

        return Scaffold(
          key: ConsumptionFormPage.formKey,
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
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton.icon(
                key: ConsumptionFormPage.postKey,
                // Disabled while any write is in flight, and while the document has
                // nothing to post. The use case remains the authority.
                onPressed: busy || !document.canPost
                    ? null
                    : () => _post(document),
                icon: const Icon(Icons.outbox),
                label: const Text('Posting Pemakaian'),
              ),
            ),
          ),
          body: ListView(
            key: ConsumptionFormPage.linesKey,
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _Header(document: document, noteController: _note),
              const SizedBox(height: AppSpacing.md),
              if (!progress.allUsable) ...[
                Container(
                  key: ConsumptionFormPage.expiredLineKey,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '${progress.expiredCount} baris memuat batch yang sudah '
                    'kedaluwarsa dan tidak dapat diposting. Hapus baris '
                    'tersebut — barang kedaluwarsa hanya keluar melalui '
                    'pemusnahan.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (progress.hasNearExpiry) ...[
                const ConsumptionNearExpiryNotice(),
                const SizedBox(height: AppSpacing.md),
              ],
              const ConsumptionCategoryChips(),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: ConsumptionFormPage.addKey,
                onPressed: busy ? null : () => _openPicker(document),
                icon: const Icon(Icons.add),
                label: const Text('Tambah barang dipakai'),
              ),
              const SizedBox(height: AppSpacing.md),
              if (document.isEmpty)
                const ConsumptionNotice(
                  key: ConsumptionFormPage.emptyKey,
                  title: 'Belum ada barang',
                  message:
                      'Tambahkan barang yang dipakai di ruangan ini. Hanya '
                      'barang bersaldo dan belum kedaluwarsa yang dapat '
                      'dipilih.',
                  icon: Icons.inventory_2_outlined,
                )
              else
                for (final line in document.orderedLines)
                  Padding(
                    key: _lineKeyFor(line),
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _LineCard(
                      line: line,
                      nowUtc: nowUtc,
                      position: positions[line.positionKey],
                      qtyController: _qtyControllerFor(line),
                      noteController: _noteControllerFor(line),
                      focusNode: _qtyFocusFor(line),
                      enabled: !busy,
                      onRemove: busy ? null : () => _removeLine(line),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// The document header: number, branch, room, nurse, status, created time, note (§28).
class _Header extends StatelessWidget {
  const _Header({required this.document, required this.noteController});

  final ConsumptionDetail document;
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consumption = document.consumption;

    return Card(
      key: ConsumptionFormPage.headerKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(consumption.docNumber, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${document.summary.branchName} · ${document.room.label}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Perawat: ${document.summary.createdByName}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Dibuat ${AppDateTimeFormatter.dateTimeWithZone(consumption.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SyncStatusTag(status: consumption.syncStatus),
                if (document.usesHistoricalMaster)
                  HistoricalMasterBadge.forDetail(
                    [
                      if (document.summary.roomIsHistorical) 'Ruangan',
                      if (document.lines.any((line) => line.itemIsHistorical))
                        'Barang',
                      if (document.lines.any((line) => line.batchIsHistorical))
                        'Batch',
                    ].join(', '),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: ConsumptionFormPage.noteKey,
              controller: noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Catatan umum (opsional)',
                helperText:
                    'Misalnya "pemakaian shift pagi". Jangan mencantumkan '
                    'data pasien.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One editable line: the position, its availability, the quantity and the remainder.
///
/// Stateful for one reason: *"sisa setelah pemakaian"* has to follow the field as it is
/// typed. A stateless card would compute the remainder once per parent rebuild, so the
/// number a nurse reads while deciding how much to record would be the number from before
/// they started typing — which is exactly the figure §28 asks the screen to show.
class _LineCard extends StatefulWidget {
  const _LineCard({
    required this.line,
    required this.nowUtc,
    required this.position,
    required this.qtyController,
    required this.noteController,
    required this.focusNode,
    required this.enabled,
    required this.onRemove,
  });

  final ConsumptionLine line;
  final DateTime nowUtc;

  /// The room's current holding of this position, or `null` when it holds none — which
  /// after a concurrent posting is a state the form has to render rather than crash on.
  final RoomStockPosition? position;

  final TextEditingController qtyController;
  final TextEditingController noteController;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback? onRemove;

  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  @override
  void initState() {
    super.initState();
    widget.qtyController.addListener(_onQtyChanged);
  }

  @override
  void didUpdateWidget(_LineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent reuses one controller per line id, so this normally does nothing — but a
    // card rebuilt against a different controller would otherwise keep listening to the old
    // one and stop updating.
    if (oldWidget.qtyController != widget.qtyController) {
      oldWidget.qtyController.removeListener(_onQtyChanged);
      widget.qtyController.addListener(_onQtyChanged);
    }
  }

  @override
  void dispose() {
    // The listener comes off; the controller itself belongs to the page, which disposes it
    // (see `_ConsumptionFormPageState.dispose`). Disposing it here would break the page's
    // own map and any other card that had been handed the same one.
    widget.qtyController.removeListener(_onQtyChanged);
    super.dispose();
  }

  void _onQtyChanged() {
    if (mounted) setState(() {});
  }

  ConsumptionLine get line => widget.line;

  DateTime get nowUtc => widget.nowUtc;

  TextEditingController get qtyController => widget.qtyController;

  TextEditingController get noteController => widget.noteController;

  FocusNode get focusNode => widget.focusNode;

  bool get enabled => widget.enabled;

  VoidCallback? get onRemove => widget.onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = widget.position?.qtyOnHand ?? Quantity.zero();
    final typed = Quantity.tryParse(qtyController.text) ?? line.qty;
    final exceeds = typed > available;
    final remaining = available - typed;

    return Card(
      key: ConsumptionFormPage.lineCardKeyFor(line.id),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.itemName, style: theme.textTheme.titleSmall),
                      Text(
                        line.isBatched
                            ? '${line.sku} · batch ${line.batchNo}'
                            : '${line.sku} · tanpa batch',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    key: ConsumptionFormPage.removeKeyFor(line.id),
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Hapus baris',
                  ),
              ],
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
                ConsumptionPill(
                  label: 'Tersedia ${available.formatWithUnit(line.unit)}',
                  color: theme.colorScheme.primary,
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
              key: ConsumptionFormPage.qtyFieldKeyFor(line.id),
              controller: qtyController,
              focusNode: focusNode,
              enabled: enabled,
              label: 'Jumlah dipakai',
              unit: line.unit,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              key: ConsumptionFormPage.remainingKeyFor(line.id),
              exceeds
                  // Named rather than clamped silently: a reassuring "sisa 0" beside a
                  // quantity the posting will refuse is worse than saying so (§28).
                  ? 'Jumlah melebihi saldo ruangan '
                        '(${available.formatWithUnit(line.unit)}).'
                  : 'Sisa setelah pemakaian: '
                        '${remaining.formatWithUnit(line.unit)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: exceeds ? AppColors.danger : null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: ConsumptionFormPage.lineNoteKeyFor(line.id),
              controller: noteController,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Catatan baris (opsional)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
