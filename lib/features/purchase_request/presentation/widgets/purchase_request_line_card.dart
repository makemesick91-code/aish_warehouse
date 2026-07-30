import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../domain/models/purchase_request_models.dart';
import '../../domain/services/purchase_request_quantity_policy.dart';

/// One requested item on the form.
///
/// Editable while the document is a draft and strictly read-only afterwards
/// (G-P5) — the same widget renders both, so a submitted request cannot
/// accidentally be shown with live inputs.
///
/// The threshold warning is recomputed locally from what is currently typed, so
/// the branch head sees the consequence of a keystroke immediately; the
/// authoritative check is `SubmitPurchaseRequestUseCase`'s, which runs against
/// what is actually stored.
///
/// Every keystroke is reported upward through [onEdited]. That is what lets the
/// form flush pending edits before it submits: without it, a branch head who
/// types a quantity and taps **Kirim ke Warehouse** without first tapping
/// *Simpan baris* would submit the values still sitting in the database — an
/// order for quantities nobody asked for, frozen the moment it is sent.
///
/// No milli-unit ever reaches this widget's output: every quantity goes through
/// `Quantity.formatWithUnit`, so a suggestion of 1500 milli-units renders as
/// `1.5 box` (Q-6).
class PurchaseRequestLineCard extends StatefulWidget {
  const PurchaseRequestLineCard({
    super.key,
    required this.line,
    required this.editable,
    this.breakdown,
    this.onSave,
    this.onEdited,
    this.onRemove,
    this.highlightMissingNote = false,
  });

  final PurchaseRequestLine line;
  final bool editable;

  /// Where the suggestion came from — par level, rooms, counted total. Available
  /// on a draft, whose citations can still be recomputed; `null` on a sent
  /// document, where recomputing would show numbers that are no longer the ones
  /// the order was based on.
  final SuggestedPurchaseRequestLine? breakdown;

  final Future<void> Function({required Quantity requestedQty, String? note})?
  onSave;

  /// Fires on every edit with the values currently on screen, saved or not.
  final void Function({required Quantity requestedQty, String? note})? onEdited;

  final Future<void> Function()? onRemove;

  /// Set after a rejected submit so the offending lines stand out.
  final bool highlightMissingNote;

  @override
  State<PurchaseRequestLineCard> createState() =>
      _PurchaseRequestLineCardState();
}

class _PurchaseRequestLineCardState extends State<PurchaseRequestLineCard> {
  late final TextEditingController _requestedController;
  late final TextEditingController _noteController;
  late Quantity _requested;

  @override
  void initState() {
    super.initState();
    _requested = widget.line.requestedQty;
    _requestedController = TextEditingController(text: _requested.format());
    _noteController = TextEditingController(text: widget.line.note ?? '');
  }

  @override
  void didUpdateWidget(PurchaseRequestLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only adopt a value that arrived from elsewhere (a reload, a stream
    // emission, a recompute); overwriting while the user types would fight
    // their input.
    if (widget.line.requestedQty != oldWidget.line.requestedQty &&
        widget.line.requestedQty != _requested) {
      _requested = widget.line.requestedQty;
      _requestedController.text = _requested.format();
    }
    if (widget.line.note != oldWidget.line.note &&
        (widget.line.note ?? '') != _noteController.text) {
      _noteController.text = widget.line.note ?? '';
    }
  }

  @override
  void dispose() {
    _requestedController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Quantity get _suggested => widget.line.suggestedQty;

  /// The warning for what is on screen right now — exact fixed-point, never a
  /// `double` comparison (G-P3).
  String? get _warning => PurchaseRequestQuantityPolicy.warningFor(
    suggested: _suggested,
    requested: _requested,
  );

  bool get _needsNote =>
      PurchaseRequestQuantityPolicy.requiresJustification(
        suggested: _suggested,
        requested: _requested,
      ) &&
      !PurchaseRequestQuantityPolicy.hasJustification(_noteController.text);

  String? get _note {
    final note = _noteController.text.trim();
    return note.isEmpty ? null : note;
  }

  /// Publishes what is on screen right now, so the form can persist it even if
  /// the branch head never taps *Simpan baris*.
  void _notifyEdited() =>
      widget.onEdited?.call(requestedQty: _requested, note: _note);

  Future<void> _save() async {
    final save = widget.onSave;
    if (save == null) return;
    await save(requestedQty: _requested, note: _note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = widget.line;
    final warning = _warning;
    final showNoteError = widget.highlightMissingNote && _needsNote;

    return Card(
      key: ValueKey('prLine-${line.id}'),
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
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs / 2),
                      Text(
                        '${line.sku} · ${line.unit}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.editable && widget.onRemove != null)
                  IconButton(
                    tooltip: 'Hapus baris',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => widget.onRemove!(),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (line.isManualRequest)
                  const _Tag(
                    label: 'Permintaan manual',
                    color: AppColors.warning,
                    icon: Icons.edit_note,
                  ),
                if (line.itemIsHistorical)
                  const HistoricalMasterBadge.inactive(detail: 'Barang'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _SuggestionSummary(line: line, breakdown: widget.breakdown),
            const SizedBox(height: AppSpacing.md),
            if (widget.editable) ...[
              QuantityField(
                key: ValueKey('prRequestedQty-${line.id}'),
                controller: _requestedController,
                label: 'Jumlah diminta',
                unit: line.unit,
                helperText: _helperText(line),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _requested = value);
                  _notifyEdited();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _DifferenceRow(
                suggested: _suggested,
                requested: _requested,
                unit: line.unit,
              ),
              if (warning != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _WarningBanner(message: warning),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: ValueKey('prNote-${line.id}'),
                controller: _noteController,
                minLines: 1,
                maxLines: 3,
                onChanged: (_) {
                  setState(() {});
                  _notifyEdited();
                },
                decoration: InputDecoration(
                  labelText: warning == null
                      ? 'Catatan (opsional)'
                      : 'Catatan alasan (wajib)',
                  errorText: showNoteError
                      ? 'Catatan alasan wajib diisi.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: widget.onSave == null ? null : _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan baris'),
                ),
              ),
            ] else ...[
              _ReadOnlyRow(
                label: 'Jumlah diminta',
                value: line.requestedQty.formatWithUnit(line.unit),
                emphasise: true,
              ),
              _DifferenceRow(
                suggested: line.suggestedQty,
                requested: line.requestedQty,
                unit: line.unit,
              ),
              if (line.note != null && line.note!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _ReadOnlyRow(label: 'Catatan', value: line.note!),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// The largest quantity that still needs no reason, so the branch head can see
  /// the boundary rather than discovering it by tripping over it.
  String? _helperText(PurchaseRequestLine line) {
    final ceiling = PurchaseRequestQuantityPolicy.justificationFreeCeiling(
      _suggested,
    );
    if (ceiling == null) {
      return 'Tanpa saran sistem — catatan alasan wajib.';
    }
    return 'Tanpa catatan hingga ${ceiling.formatWithUnit(line.unit)} '
        '(${PurchaseRequestQuantityPolicy.thresholdPercent}% saran).';
  }
}

/// Suggested quantity plus the working behind it (§24.2).
class _SuggestionSummary extends StatelessWidget {
  const _SuggestionSummary({required this.line, this.breakdown});

  final PurchaseRequestLine line;
  final SuggestedPurchaseRequestLine? breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final work = breakdown;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadOnlyRow(
            label: 'Saran sistem',
            value: line.suggestedQty.formatWithUnit(line.unit),
            emphasise: true,
          ),
          if (work != null) ...[
            _ReadOnlyRow(
              label: 'Par level per ruangan',
              value: work.parLevelPerRoom.formatWithUnit(line.unit),
            ),
            _ReadOnlyRow(
              label: 'Total hasil opname',
              value: work.countedTotal.formatWithUnit(line.unit),
            ),
            if (work.sourceRoomNames.isNotEmpty)
              _ReadOnlyRow(
                label: 'Ruangan sumber',
                value: work.sourceRoomNames.join(', '),
              ),
          ],
        ],
      ),
    );
  }
}

class _DifferenceRow extends StatelessWidget {
  const _DifferenceRow({
    required this.suggested,
    required this.requested,
    required this.unit,
  });

  final Quantity suggested;
  final Quantity requested;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final difference = requested - suggested;
    if (difference.isZero) {
      return _ReadOnlyRow(label: 'Selisih dari saran', value: 'Sesuai saran');
    }

    final sign = difference.isPositive ? '+' : '';
    final color = difference.isPositive
        ? AppColors.warning
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Selisih dari saran',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$sign${difference.formatWithUnit(unit)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: emphasise
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )
                  : theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The G-P3 warning banner (§24.3).
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  /// Lets tests address the warning without matching on prose.
  static const Key bannerKey = ValueKey('prThresholdWarning');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: bannerKey,
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The key the threshold warning renders under, exposed so widget tests do not
/// have to reach into a private class.
const Key purchaseRequestThresholdWarningKey = _WarningBanner.bannerKey;

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
