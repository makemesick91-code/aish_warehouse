import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/services/good_receipt_line_decision_policy.dart';

/// The reason a branch head refused one position (G-G4), as the sheet returns it.
class GoodReceiptRejectResult {
  const GoodReceiptRejectResult({required this.preset, this.detail});

  final GoodReceiptRejectReasonPreset preset;
  final String? detail;

  /// The text that will be stored. Composed through the policy so the sheet and the
  /// use case cannot disagree about what a preset plus a detail reads as.
  String? get reason => GoodReceiptLineDecisionPolicy.composeReason(
    preset: preset,
    detail: detail,
  );
}

/// `✘ Tolak` — the reason sheet (§31, G-G4).
///
/// Presets rather than a bare text field, because a reason typed differently on every
/// receipt cannot be counted, and the warehouse's return list is exactly a count of
/// *why*. *Lainnya* demands a written detail: the word on its own explains nothing, and
/// storing it would produce an audit trail that names no cause.
///
/// The sheet cannot be dismissed into a refusal with no reason. Returning `null` — by
/// tapping outside, or *Batal* — leaves the line exactly as it was, which is the honest
/// outcome of an abandoned decision.
///
/// [forcedPreset] pre-selects and locks the reason when G-E5 has already decided it: a
/// batch that is expired or too close to its date must be refused *as such*, and letting
/// the branch head file it under *Rusak* would lose the one fact the warehouse needs.
class GoodReceiptRejectSheet extends StatefulWidget {
  const GoodReceiptRejectSheet({
    super.key,
    required this.itemName,
    this.batchLabel,
    this.forcedPreset,
  });

  final String itemName;

  /// `B-NEAR · ED 12 Agu 2026`, when the item is batch-tracked.
  final String? batchLabel;

  /// A preset the reader may not change — see the class note.
  final GoodReceiptRejectReasonPreset? forcedPreset;

  static const Key sheetKey = ValueKey('goodReceiptRejectSheet');
  static const Key detailFieldKey = ValueKey('goodReceiptRejectDetail');
  static const Key submitKey = ValueKey('goodReceiptRejectSubmit');
  static const Key cancelKey = ValueKey('goodReceiptRejectCancel');

  static Key presetKeyFor(GoodReceiptRejectReasonPreset preset) =>
      ValueKey('goodReceiptRejectPreset-${preset.name}');

  /// Opens the sheet and returns the reason, or `null` when it was abandoned.
  static Future<GoodReceiptRejectResult?> show(
    BuildContext context, {
    required String itemName,
    String? batchLabel,
    GoodReceiptRejectReasonPreset? forcedPreset,
  }) {
    return showModalBottomSheet<GoodReceiptRejectResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GoodReceiptRejectSheet(
        itemName: itemName,
        batchLabel: batchLabel,
        forcedPreset: forcedPreset,
      ),
    );
  }

  @override
  State<GoodReceiptRejectSheet> createState() => _GoodReceiptRejectSheetState();
}

class _GoodReceiptRejectSheetState extends State<GoodReceiptRejectSheet> {
  late GoodReceiptRejectReasonPreset _preset;
  final TextEditingController _detail = TextEditingController();
  bool _showDetailError = false;

  @override
  void initState() {
    super.initState();
    _preset = widget.forcedPreset ?? GoodReceiptRejectReasonPreset.damaged;
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  bool get _detailMissing =>
      _preset.requiresDetail &&
      !GoodReceiptLineDecisionPolicy.isValidRejectReason(_detail.text);

  void _submit() {
    if (_detailMissing) {
      setState(() => _showDetailError = true);
      return;
    }
    Navigator.of(
      context,
    ).pop(GoodReceiptRejectResult(preset: _preset, detail: _detail.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      key: GoodReceiptRejectSheet.sheetKey,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alasan penolakan',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(widget.itemName, style: theme.textTheme.bodyMedium),
            if (widget.batchLabel != null)
              Text(
                widget.batchLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (widget.forcedPreset != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Barang kedaluwarsa atau terlalu dekat ED wajib ditolak dengan '
                'alasan kedaluwarsa (G-E5).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.danger,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final preset in GoodReceiptRejectReasonPreset.values)
                  ChoiceChip(
                    key: GoodReceiptRejectSheet.presetKeyFor(preset),
                    label: Text(preset.label),
                    selected: _preset == preset,
                    showCheckmark: false,
                    // A locked preset is rendered rather than hidden, so the reader can
                    // see the whole vocabulary and why this one applies.
                    onSelected: widget.forcedPreset != null
                        ? null
                        : (_) => setState(() {
                            _preset = preset;
                            _showDetailError = false;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: GoodReceiptRejectSheet.detailFieldKey,
              controller: _detail,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) {
                if (_showDetailError) setState(() => _showDetailError = false);
              },
              decoration: InputDecoration(
                labelText: _preset.requiresDetail
                    ? 'Detail alasan (wajib)'
                    : 'Detail tambahan (opsional)',
                errorText: _showDetailError
                    ? 'Alasan "Lainnya" wajib disertai detail.'
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: GoodReceiptRejectSheet.cancelKey,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    key: GoodReceiptRejectSheet.submitKey,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    onPressed: _submit,
                    child: const Text('Tolak Barang'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
