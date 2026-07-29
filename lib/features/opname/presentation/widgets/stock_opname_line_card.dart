import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../domain/models/opname_models.dart';
import 'historical_master_badge.dart';
import 'stock_opname_difference_badge.dart';

/// One counted position on the form.
///
/// Editable while the document is a draft and strictly read-only afterwards
/// (G-S2) — the same widget renders both, so a submitted document cannot
/// accidentally be shown with live inputs.
///
/// The difference shown here is recomputed locally from what is currently
/// typed, so the nurse sees the consequence of a keystroke immediately; the
/// authoritative value is the database's generated column, which arrives with
/// the next stream emission.
///
/// Every keystroke is reported upward through [onEdited]. That is what lets the
/// form flush pending edits before it submits: without it, a nurse who types a
/// count and taps **Kirim** without first tapping *Simpan baris* would submit
/// the values still sitting in the database — and after review the ledger would
/// be adjusted to a number nobody counted.
class StockOpnameLineCard extends StatefulWidget {
  const StockOpnameLineCard({
    super.key,
    required this.line,
    required this.editable,
    required this.now,
    this.onSave,
    this.onEdited,
    this.onRemove,
    this.highlightMissingNote = false,
  });

  final StockOpnameLine line;
  final bool editable;

  /// UTC instant used for the expiry badge.
  final DateTime now;

  final Future<void> Function({required Quantity countedQty, String? note})?
  onSave;

  /// Fires on every edit with the values currently on screen, saved or not.
  final void Function({required Quantity countedQty, String? note})? onEdited;

  final Future<void> Function()? onRemove;

  /// Set after a rejected submit so the offending lines stand out.
  final bool highlightMissingNote;

  @override
  State<StockOpnameLineCard> createState() => _StockOpnameLineCardState();
}

class _StockOpnameLineCardState extends State<StockOpnameLineCard> {
  late final TextEditingController _countedController;
  late final TextEditingController _noteController;
  late Quantity _counted;

  @override
  void initState() {
    super.initState();
    _counted = widget.line.countedQty;
    _countedController = TextEditingController(text: _counted.format());
    _noteController = TextEditingController(text: widget.line.note ?? '');
  }

  @override
  void didUpdateWidget(StockOpnameLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only adopt a value that arrived from elsewhere (a reload, a stream
    // emission); overwriting while the user types would fight their input.
    if (widget.line.countedQty != oldWidget.line.countedQty &&
        widget.line.countedQty != _counted) {
      _counted = widget.line.countedQty;
      _countedController.text = _counted.format();
    }
    if (widget.line.note != oldWidget.line.note &&
        (widget.line.note ?? '') != _noteController.text) {
      _noteController.text = widget.line.note ?? '';
    }
  }

  @override
  void dispose() {
    _countedController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Quantity get _difference => _counted - widget.line.systemQty;

  bool get _needsNote =>
      !_difference.isZero && _noteController.text.trim().isEmpty;

  String? get _note {
    final note = _noteController.text.trim();
    return note.isEmpty ? null : note;
  }

  /// Publishes what is on screen right now, so the form can persist it even if
  /// the nurse never taps *Simpan baris*.
  void _notifyEdited() =>
      widget.onEdited?.call(countedQty: _counted, note: _note);

  Future<void> _save() async {
    final save = widget.onSave;
    if (save == null) return;
    await save(countedQty: _counted, note: _note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = widget.line;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                        line.batchNo == null
                            ? line.sku
                            : '${line.sku} · Batch ${line.batchNo}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      // An item deactivated after this line was counted stays
                      // on the sheet and stays postable — it is physically on
                      // the shelf. The badge explains why it can no longer be
                      // found in the "add item" search (§7.6).
                      if (line.itemIsHistorical) ...[
                        const SizedBox(height: AppSpacing.xs),
                        const HistoricalMasterBadge.inactive(detail: 'Barang'),
                      ],
                    ],
                  ),
                ),
                if (widget.editable && widget.onRemove != null)
                  IconButton(
                    tooltip: 'Hapus baris',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => widget.onRemove!.call(),
                  ),
              ],
            ),
            if (line.expiryDate != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ExpiryTag(line: line, now: widget.now),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ReadOnlyValue(
                    label: 'Stok sistem',
                    // Trailing zeros are dropped, so 10.5 shows as `10.5 box`
                    // and 150 as `150 box` (Q-6).
                    value: line.systemQty.formatWithUnit(line.unit),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: widget.editable
                      ? QuantityField(
                          controller: _countedController,
                          label: 'Hasil hitung',
                          unit: line.unit,
                          // A physical count may legitimately be zero (G-O3).
                          allowZero: true,
                          textInputAction: TextInputAction.next,
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _counted = value);
                            _notifyEdited();
                          },
                          onSubmitted: (_) => _save(),
                        )
                      : _ReadOnlyValue(
                          label: 'Hasil hitung',
                          value: line.countedQty.formatWithUnit(line.unit),
                        ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text('Selisih', style: theme.textTheme.bodySmall),
                const SizedBox(width: AppSpacing.sm),
                // Flexible so a long unit at a large text scale wraps inside
                // the badge instead of overflowing the card.
                Flexible(
                  child: StockOpnameDifferenceBadge(
                    difference: widget.editable ? _difference : line.difference,
                    unit: line.unit,
                  ),
                ),
              ],
            ),
            if (widget.editable) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _noteController,
                // Always editable. A note is *mandatory* when there is a
                // difference and optional otherwise — optional means the nurse
                // may leave it empty, not that the field is unusable. Disabling
                // it would block a perfectly reasonable "segel kemasan rusak"
                // on a line that counted exactly right.
                minLines: 1,
                maxLines: 3,
                onChanged: (_) {
                  setState(() {});
                  _notifyEdited();
                },
                onEditingComplete: _save,
                decoration: InputDecoration(
                  labelText: _difference.isZero
                      ? 'Catatan (opsional)'
                      : 'Catatan alasan selisih *',
                  helperText: _difference.isZero
                      ? null
                      : 'Wajib diisi karena ada selisih.',
                  errorText: widget.highlightMissingNote && _needsNote
                      ? 'Catatan wajib diisi untuk baris yang berselisih.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: widget.onSave == null ? null : _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan baris'),
                ),
              ),
            ] else if ((line.note ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _ReadOnlyValue(label: 'Catatan', value: line.note!.trim()),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyValue extends StatelessWidget {
  const _ReadOnlyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs / 2),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Expiry indicator for an opname line (G-E6). Mirrors `ExpiryBadge`, which is
/// bound to a stock balance rather than a counted line.
class _ExpiryTag extends StatelessWidget {
  const _ExpiryTag({required this.line, required this.now});

  final StockOpnameLine line;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final expiry = line.expiryDate;
    if (expiry == null) return const SizedBox.shrink();

    final daysLeft = line.daysUntilExpiry(now) ?? 0;
    final (Color color, String label) = switch (daysLeft) {
      < 0 => (AppColors.danger, 'Kedaluwarsa'),
      _ when daysLeft <= line.expiryAlertDays => (
        AppColors.warning,
        'Segera kedaluwarsa · $daysLeft hari',
      ),
      // The civil expiry date is printed exactly as stored (T-9).
      _ => (Colors.blueGrey, 'ED ${AppDateTimeFormatter.civilDate(expiry)}'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
