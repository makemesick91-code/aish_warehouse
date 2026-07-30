import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../domain/models/good_receipt_models.dart';
import '../../domain/services/good_receipt_expiry_policy.dart';
import 'good_receipt_badges.dart';

/// One position on the checklist (§31).
///
/// The card is a pure function of its line plus a [TextEditingController] the *page*
/// owns. That ownership matters for one reason: pressing *Posting Good Receipt* has to
/// be able to flush a quantity the branch head typed and never committed, and a
/// controller that lived inside this widget would be gone the moment the list scrolled
/// it out of the tree.
///
/// ### What the reader can and cannot do
///
/// While the receipt is `checking`, both buttons are live and the quantity is editable
/// from `0` to what was shipped (G-G3). Once it is `posted`, everything here is text:
/// no field, no buttons, and the decision plus its reason on display. There is no
/// "remove" affordance at any point — refusing is [onReject], and the row stays (G-G4).
///
/// ### Expiry
///
/// A batch that G-E5 refuses gets its ✔ button disabled and a sentence saying why.
/// Disabling rather than hiding is deliberate: the branch head has the goods in their
/// hands and needs to be told *why* they cannot accept them, and the reject sheet then
/// opens with the reason already locked to `kedaluwarsa`.
class GoodReceiptLineCard extends StatelessWidget {
  const GoodReceiptLineCard({
    super.key,
    required this.line,
    required this.nowUtc,
    required this.editable,
    required this.controller,
    this.onCheck,
    this.onReject,
    this.onReset,
    this.busy = false,
  });

  final GoodReceiptLine line;

  /// The instant every expiry question is judged against, injected from the page so a
  /// badge and the refusal the use case produces agree (T-7).
  final DateTime nowUtc;

  /// Whether the parent receipt is still `checking`.
  final bool editable;

  /// Owned by the page — see the class note.
  final TextEditingController controller;

  /// Called with the quantity currently in [controller], or `null` when the text is not
  /// a valid quantity.
  final ValueChanged<Quantity?>? onCheck;
  final VoidCallback? onReject;
  final VoidCallback? onReset;

  /// Whether an action is in flight. Disables both buttons so a double tap cannot
  /// produce two writes.
  final bool busy;

  static Key cardKeyFor(String lineId) => ValueKey('goodReceiptLine-$lineId');

  static Key checkKeyFor(String lineId) =>
      ValueKey('goodReceiptLineCheck-$lineId');

  static Key rejectKeyFor(String lineId) =>
      ValueKey('goodReceiptLineReject-$lineId');

  static Key resetKeyFor(String lineId) =>
      ValueKey('goodReceiptLineReset-$lineId');

  static Key quantityKeyFor(String lineId) =>
      ValueKey('goodReceiptLineQty-$lineId');

  static Key discrepancyKeyFor(String lineId) =>
      ValueKey('goodReceiptLineDiscrepancy-$lineId');

  /// G-E5 — whether this position may not be accepted at the given instant.
  bool get mustBeRejected => GoodReceiptExpiryPolicy.mustBeRejected(
    expiryDate: line.expiryDate,
    expiryAlertDays: line.expiryAlertDays,
    nowUtc: nowUtc,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocked = mustBeRejected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: cardKeyFor(line.id),
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
                        Text(
                          line.itemName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${line.sku} · ${line.unit}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GoodReceiptLineStatusChip(status: line.lineStatus),
                ],
              ),
              if (line.batchNo != null || line.expiryDate != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (line.batchNo != null)
                      Text(
                        'Batch ${line.batchNo}',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (line.expiryDate != null)
                      Text(
                        // A civil date, printed exactly as stored (T-9).
                        'ED ${AppDateTimeFormatter.civilDate(line.expiryDate!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (line.expiryDate != null)
                      GoodReceiptExpiryBadge(
                        expiryDate: line.expiryDate!,
                        expiryAlertDays: line.expiryAlertDays,
                        nowUtc: nowUtc,
                      ),
                    if (line.usesHistoricalMaster)
                      HistoricalMasterBadge.inactive(
                        detail: [
                          if (line.itemIsHistorical) 'Barang',
                          if (line.batchIsHistorical) 'Batch',
                        ].join(', '),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dikirim ${line.shippedQty.formatWithUnit(line.unit)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (!editable)
                          Text(
                            'Diterima '
                            '${line.receivedQty.formatWithUnit(line.unit)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (line.discrepancyQty.isPositive)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              key: discrepancyKeyFor(line.id),
                              'Selisih '
                              '${line.discrepancyQty.formatWithUnit(line.unit)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (editable)
                    SizedBox(
                      width: 132,
                      child: QuantityField(
                        key: quantityKeyFor(line.id),
                        controller: controller,
                        label: 'Diterima',
                        unit: line.unit,
                        // A physical delivery may be short, or absent: zero is a real
                        // answer here and refusing it would push the reader towards
                        // `rejected`, which claims the goods are on their counter.
                        allowZero: true,
                        enabled: !busy,
                      ),
                    ),
                ],
              ),
              if (line.rejectReason != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        line.rejectReason!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (editable && blocked) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Batch ini kedaluwarsa atau terlalu dekat ED, sehingga harus '
                  'ditolak dan tidak boleh masuk stok cabang.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ],
              if (editable) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: checkKeyFor(line.id),
                        onPressed: busy || blocked
                            ? null
                            : () => onCheck?.call(
                                Quantity.tryParse(controller.text),
                              ),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Sesuai'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: rejectKeyFor(line.id),
                        onPressed: busy ? null : onReject,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Tolak'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                        ),
                      ),
                    ),
                    if (line.isDecided) ...[
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        key: resetKeyFor(line.id),
                        tooltip: 'Batalkan keputusan',
                        onPressed: busy ? null : onReset,
                        icon: const Icon(Icons.undo),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
