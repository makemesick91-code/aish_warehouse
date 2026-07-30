import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../domain/models/delivery_models.dart';
import '../../domain/services/delivery_expiry_policy.dart';
import '../../domain/services/delivery_fefo_policy.dart';
import 'delivery_expiry_badges.dart';
import 'shipment_progress_bar.dart';

/// The uncommitted state of one allocation, as the form holds it between
/// keystrokes.
///
/// The card reports this on **every** change rather than only when a save button
/// is pressed, and the form keeps the latest one per line. That is what makes the
/// pending-input flush before *Kirim* possible: an officer who types `0.5` and goes
/// straight for the ship button must not lose the `0.5`, and a screen that only
/// learned about it on blur would ship the old quantity (§27.4).
class DeliveryAllocationEdit {
  const DeliveryAllocationEdit({
    required this.lineId,
    required this.qty,
    this.batchId,
    this.nearExpiryConfirmed = false,
    this.nearExpiryNote,
    this.fefoOverrideReason,
  });

  final String lineId;

  /// `null` while the text is not a valid quantity — the form refuses to ship on
  /// that rather than guessing (Q-5: no silent rounding).
  final Quantity? qty;

  final String? batchId;
  final bool nearExpiryConfirmed;
  final String? nearExpiryNote;
  final String? fefoOverrideReason;

  bool get isValid => qty != null && qty!.isPositive;
}

/// One requested position of the Purchase Request, with its allocations (§27.2).
///
/// There is deliberately **no item picker anywhere on this screen.** Every card
/// corresponds to a line the branch asked for, and the only thing the warehouse
/// chooses is *which batches* satisfy it and *how much* ships now. That is G-D4
/// enforced by design rather than by validation: there is no control that could
/// express an item outside the request.
///
/// For an expiry-tracked item the card shows a batch picker whose options are the
/// **usable** candidates — expired batches never appear as choices (G-E4) and are
/// listed separately as an explanation, so an officer is told the stock exists and
/// may not ship rather than left wondering where it went.
///
/// Two audit controls appear conditionally, and only when the rule that demands
/// them actually fires:
///
/// * a near-expiry confirmation, when the selected batch has less than the item's
///   `expiry_alert_days` of shelf life left. Never pre-ticked (G-E4).
/// * a FEFO override reason, when the current selection passes over stock that
///   expires sooner. The evaluation is `DeliveryFefoPolicy.violations` — the same
///   function the use case and the ship path call, so the field appears exactly
///   when the write would refuse without it (G-E3).
class DeliveryAllocationCard extends StatefulWidget {
  const DeliveryAllocationCard({
    super.key,
    required this.draft,
    required this.nowUtc,
    required this.enabled,
    required this.onChanged,
    required this.onSave,
    required this.onRemove,
  });

  final DeliveryLineDraft draft;

  /// UTC "now" from the feature clock, so expiry maths is deterministic (T-7).
  final DateTime nowUtc;

  /// `false` once the document has shipped — the card becomes a read-only record
  /// of what was sent (G-S2).
  final bool enabled;

  final ValueChanged<DeliveryAllocationEdit> onChanged;
  final ValueChanged<DeliveryAllocationEdit> onSave;
  final ValueChanged<String> onRemove;

  static Key cardKeyFor(String prLineId) =>
      ValueKey('deliveryAllocationCard-$prLineId');

  static Key qtyFieldKeyFor(String lineId) =>
      ValueKey('deliveryQtyField-$lineId');

  static Key batchPickerKeyFor(String lineId) =>
      ValueKey('deliveryBatchPicker-$lineId');

  static Key nearExpiryCheckKeyFor(String lineId) =>
      ValueKey('deliveryNearExpiryCheck-$lineId');

  static Key fefoReasonKeyFor(String lineId) =>
      ValueKey('deliveryFefoReason-$lineId');

  static Key saveKeyFor(String lineId) => ValueKey('deliverySaveLine-$lineId');

  static Key removeKeyFor(String lineId) =>
      ValueKey('deliveryRemoveLine-$lineId');

  static const Key emptyAllocationKey = ValueKey('deliveryAllocationEmpty');

  @override
  State<DeliveryAllocationCard> createState() => _DeliveryAllocationCardState();
}

class _DeliveryAllocationCardState extends State<DeliveryAllocationCard> {
  /// Working state per stored allocation, keyed by line id.
  final Map<String, DeliveryAllocationEdit> _edits = {};
  final Map<String, TextEditingController> _reasonControllers = {};
  final Map<String, TextEditingController> _noteControllers = {};

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(DeliveryAllocationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed only when the stored allocation set changes shape. Re-seeding on
    // every rebuild would overwrite what the officer is halfway through typing.
    final oldIds = oldWidget.draft.allocations
        .map((allocation) => allocation.lineId)
        .toList();
    final newIds = widget.draft.allocations
        .map((allocation) => allocation.lineId)
        .toList();
    if (oldIds.length != newIds.length || !oldIds.every(newIds.contains)) {
      _edits.clear();
      _seed();
    }
  }

  void _seed() {
    for (final allocation in widget.draft.allocations) {
      final lineId = allocation.lineId;
      if (lineId == null) continue;
      _edits[lineId] = DeliveryAllocationEdit(
        lineId: lineId,
        qty: allocation.qty,
        batchId: allocation.batchId,
        nearExpiryConfirmed: allocation.nearExpiryConfirmed,
        nearExpiryNote: allocation.nearExpiryNote,
        fefoOverrideReason: allocation.fefoOverrideReason,
      );
      _reasonControllers
              .putIfAbsent(
                lineId,
                () =>
                    TextEditingController(text: allocation.fefoOverrideReason),
              )
              .text =
          allocation.fefoOverrideReason ?? '';
      _noteControllers
              .putIfAbsent(
                lineId,
                () => TextEditingController(text: allocation.nearExpiryNote),
              )
              .text =
          allocation.nearExpiryNote ?? '';
    }
  }

  @override
  void dispose() {
    for (final controller in _reasonControllers.values) {
      controller.dispose();
    }
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _update(String lineId, DeliveryAllocationEdit edit) {
    setState(() => _edits[lineId] = edit);
    widget.onChanged(edit);
  }

  /// The selection as it currently stands on screen, for the FEFO evaluation.
  ///
  /// Built from the working state rather than from the stored rows, so the reason
  /// field appears the moment a batch is changed rather than after a save.
  List<DeliveryAllocation> get _currentSelection => _edits.values
      .map(
        (edit) => DeliveryAllocation(
          lineId: edit.lineId,
          prLineId: widget.draft.prLineId,
          itemId: widget.draft.itemId,
          batchId: edit.batchId,
          qty: edit.qty ?? Quantity.zero(),
          fefoOverrideReason: edit.fefoOverrideReason,
          nearExpiryConfirmed: edit.nearExpiryConfirmed,
          nearExpiryNote: edit.nearExpiryNote,
        ),
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;

    final violations = draft.hasExpiry
        ? DeliveryFefoPolicy.violations(
            candidates: draft.candidates,
            selection: _currentSelection,
            nowUtc: widget.nowUtc,
          )
        : const <FefoViolation>[];
    final violatingBatchIds = violations
        .map((violation) => violation.selectedBatchId)
        .toSet();

    final usable = DeliveryExpiryPolicy.usableCandidates(
      candidates: draft.candidates,
      nowUtc: widget.nowUtc,
    );
    final expired = DeliveryExpiryPolicy.expiredCandidates(
      candidates: draft.candidates,
      nowUtc: widget.nowUtc,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: DeliveryAllocationCard.cardKeyFor(draft.prLineId),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                draft.itemName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${draft.sku} · ${draft.unit}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ShipmentProgressBar(progress: draft.progress),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Saldo Warehouse ${draft.availableQty.formatWithUnit(draft.unit)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: draft.availableQty.isPositive
                      ? theme.colorScheme.onSurfaceVariant
                      : AppColors.danger,
                ),
              ),
              if (expired.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '${expired.length} batch kedaluwarsa tidak dapat dikirim '
                    'dan tidak muncul sebagai pilihan.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
              const Divider(height: AppSpacing.lg),
              if (draft.allocations.isEmpty)
                Text(
                  key: DeliveryAllocationCard.emptyAllocationKey,
                  'Belum dialokasikan. Tekan "Alokasikan FEFO" untuk mengisi '
                  'otomatis.',
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final allocation in draft.allocations)
                  if (allocation.lineId != null)
                    _AllocationRow(
                      draft: draft,
                      allocation: allocation,
                      edit: _edits[allocation.lineId!],
                      usableCandidates: usable,
                      nowUtc: widget.nowUtc,
                      enabled: widget.enabled,
                      requiresReason: violatingBatchIds.contains(
                        _edits[allocation.lineId!]?.batchId ??
                            allocation.batchId,
                      ),
                      violation: violations
                          .where(
                            (violation) =>
                                violation.selectedBatchId ==
                                (_edits[allocation.lineId!]?.batchId ??
                                    allocation.batchId),
                          )
                          .firstOrNull,
                      reasonController: _reasonControllers[allocation.lineId!]!,
                      noteController: _noteControllers[allocation.lineId!]!,
                      onChanged: (edit) => _update(edit.lineId, edit),
                      onSave: widget.onSave,
                      onRemove: widget.onRemove,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.draft,
    required this.allocation,
    required this.edit,
    required this.usableCandidates,
    required this.nowUtc,
    required this.enabled,
    required this.requiresReason,
    required this.violation,
    required this.reasonController,
    required this.noteController,
    required this.onChanged,
    required this.onSave,
    required this.onRemove,
  });

  final DeliveryLineDraft draft;
  final DeliveryAllocation allocation;
  final DeliveryAllocationEdit? edit;
  final List<DeliveryBatchCandidate> usableCandidates;
  final DateTime nowUtc;
  final bool enabled;
  final bool requiresReason;
  final FefoViolation? violation;
  final TextEditingController reasonController;
  final TextEditingController noteController;
  final ValueChanged<DeliveryAllocationEdit> onChanged;
  final ValueChanged<DeliveryAllocationEdit> onSave;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineId = allocation.lineId!;
    final current =
        edit ??
        DeliveryAllocationEdit(
          lineId: lineId,
          qty: allocation.qty,
          batchId: allocation.batchId,
          nearExpiryConfirmed: allocation.nearExpiryConfirmed,
          nearExpiryNote: allocation.nearExpiryNote,
          fefoOverrideReason: allocation.fefoOverrideReason,
        );

    final selected = usableCandidates
        .where((candidate) => candidate.batchId == current.batchId)
        .firstOrNull;
    final needsNearExpiry =
        selected != null &&
        DeliveryExpiryPolicy.requiresNearExpiryConfirmation(
          expiryDate: selected.expiryDate,
          expiryAlertDays: draft.expiryAlertDays,
          nowUtc: nowUtc,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuantityField(
            key: DeliveryAllocationCard.qtyFieldKeyFor(lineId),
            label: 'Qty DO ini',
            unit: draft.unit,
            initialValue: allocation.qty,
            enabled: enabled,
            onChanged: (qty) => onChanged(
              DeliveryAllocationEdit(
                lineId: lineId,
                qty: qty,
                batchId: current.batchId,
                nearExpiryConfirmed: current.nearExpiryConfirmed,
                nearExpiryNote: current.nearExpiryNote,
                fefoOverrideReason: current.fefoOverrideReason,
              ),
            ),
          ),
          if (draft.hasExpiry) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: DeliveryAllocationCard.batchPickerKeyFor(lineId),
              initialValue:
                  usableCandidates.any(
                    (candidate) => candidate.batchId == current.batchId,
                  )
                  ? current.batchId
                  : null,
              decoration: const InputDecoration(labelText: 'Batch'),
              isExpanded: true,
              items: [
                for (final candidate in usableCandidates)
                  DropdownMenuItem<String>(
                    value: candidate.batchId,
                    child: Text(
                      '${candidate.batchNo} · '
                      '${candidate.availableQty.formatWithUnit(draft.unit)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: enabled
                  ? (value) => onChanged(
                      DeliveryAllocationEdit(
                        lineId: lineId,
                        qty: current.qty,
                        batchId: value,
                        // Changing the batch invalidates a confirmation given for
                        // the previous one: the new batch's shelf life is a
                        // different fact, and carrying the tick over would be the
                        // silent auto-confirmation G-E4 forbids.
                        nearExpiryConfirmed: false,
                        nearExpiryNote: null,
                        fefoOverrideReason: current.fefoOverrideReason,
                      ),
                    )
                  : null,
            ),
            if (selected != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: BatchExpiryBadge.forCandidate(
                  candidate: selected,
                  expiryAlertDays: draft.expiryAlertDays,
                  nowUtc: nowUtc,
                ),
              ),
            if (needsNearExpiry) ...[
              CheckboxListTile(
                key: DeliveryAllocationCard.nearExpiryCheckKeyFor(lineId),
                value: current.nearExpiryConfirmed,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Saya konfirmasi mengirim batch yang mendekati kedaluwarsa',
                ),
                onChanged: enabled
                    ? (value) => onChanged(
                        DeliveryAllocationEdit(
                          lineId: lineId,
                          qty: current.qty,
                          batchId: current.batchId,
                          nearExpiryConfirmed: value ?? false,
                          nearExpiryNote: noteController.text,
                          fefoOverrideReason: current.fefoOverrideReason,
                        ),
                      )
                    : null,
              ),
              TextField(
                controller: noteController,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Catatan konfirmasi (opsional)',
                ),
                onChanged: (value) => onChanged(
                  DeliveryAllocationEdit(
                    lineId: lineId,
                    qty: current.qty,
                    batchId: current.batchId,
                    nearExpiryConfirmed: current.nearExpiryConfirmed,
                    nearExpiryNote: value,
                    fefoOverrideReason: current.fefoOverrideReason,
                  ),
                ),
              ),
            ],
            if (requiresReason) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                violation == null
                    ? 'Batch ini bukan saran FEFO. Isi alasan penggantian.'
                    : 'Batch ${violation!.skippedBatchNo} lebih dekat '
                          'kedaluwarsa dan masih bersaldo '
                          '${violation!.skippedAvailableQty.formatWithUnit(draft.unit)}. '
                          'Isi alasan penggantian batch.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                ),
              ),
              TextField(
                key: DeliveryAllocationCard.fefoReasonKeyFor(lineId),
                controller: reasonController,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Alasan penggantian batch (wajib)',
                ),
                onChanged: (value) => onChanged(
                  DeliveryAllocationEdit(
                    lineId: lineId,
                    qty: current.qty,
                    batchId: current.batchId,
                    nearExpiryConfirmed: current.nearExpiryConfirmed,
                    nearExpiryNote: current.nearExpiryNote,
                    fefoOverrideReason: value,
                  ),
                ),
              ),
            ],
          ],
          if (enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                TextButton.icon(
                  key: DeliveryAllocationCard.saveKeyFor(lineId),
                  onPressed: () => onSave(current),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan baris'),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  key: DeliveryAllocationCard.removeKeyFor(lineId),
                  onPressed: () => onRemove(lineId),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Hapus'),
                ),
              ],
            ),
          ] else ...[
            if (allocation.hasFefoOverride)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: FefoOverrideBadge(
                  reason: allocation.fefoOverrideReason!,
                ),
              ),
            if (allocation.nearExpiryConfirmed)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: NearExpiryConfirmedBadge(
                  note: allocation.nearExpiryNote,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
