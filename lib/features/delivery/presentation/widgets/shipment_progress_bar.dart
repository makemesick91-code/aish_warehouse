import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/quantity/quantity.dart';
import '../../domain/models/delivery_models.dart';

/// How far one requested position has been shipped (G-D2), in words and as a bar.
///
/// Three numbers are shown rather than one percentage, because the officer's next
/// decision depends on all of them: what the branch asked for, what has already
/// left the warehouse, and what this document adds. A single "80 %" would hide
/// which of those it referred to.
///
/// Quantities are printed through `Quantity.formatWithUnit`, so `0.5` reads as
/// `0.5 box` and a milli-unit never reaches the screen (Q-6).
class ShipmentProgressBar extends StatelessWidget {
  const ShipmentProgressBar({
    super.key,
    required this.progress,
    this.dense = false,
  });

  final ShipmentProgress progress;

  /// Drops the bar, and shows the **cumulative** reading rather than the editing
  /// one.
  ///
  /// The two screens need different numbers from the same object, and giving them
  /// both the same four figures reads wrongly on one of them. While a document is
  /// being *edited*, "sudah dikirim" must exclude it — that is the ceiling the
  /// allocation is bounded by (G-D2). Once it has shipped, excluding it says
  /// "already shipped 0" about a document that just shipped one, so the detail
  /// screen shows the total including it and the remainder after it.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = progress.unit;

    // A fraction for the bar and for nothing else. The ratio itself is computed in
    // integer permille by `Quantity`, so the only division is this one, here, at
    // the last moment a widget needs a `double`. Every rule on this screen — the
    // remaining quantity, whether the position is complete — is decided by exact
    // `Quantity` comparison and never by this number (Q-3/Q-4).
    final fraction =
        progress.cumulativeQty.displayPermilleOf(progress.requestedQty) /
        Quantity.permilleScale;

    final Color barColor = progress.isOverShipped
        ? AppColors.danger
        : progress.isFullyShipped
        ? AppColors.success
        : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!dense) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              key: ValueKey('shipmentProgressBar-${progress.prLineId}'),
              value: fraction,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs / 2,
          children: [
            _Figure(
              label: 'Diminta',
              value: progress.requestedQty.formatWithUnit(unit),
            ),
            if (dense)
              _Figure(
                label: 'Terkirim',
                value: progress.cumulativeQty.formatWithUnit(unit),
              )
            else
              _Figure(
                label: 'Sudah dikirim',
                value: progress.previouslyShippedQty.formatWithUnit(unit),
              ),
            _Figure(
              label: 'Sisa',
              value: dense
                  ? progress.remainingAfterCurrentDo.formatWithUnit(unit)
                  : progress.remainingBeforeCurrentDo.formatWithUnit(unit),
              emphasis: dense
                  ? progress.remainingAfterCurrentDo.isPositive
                  : progress.remainingBeforeCurrentDo.isPositive,
            ),
            if (!dense)
              _Figure(
                label: 'DO ini',
                value: progress.currentDoQty.formatWithUnit(unit),
                emphasis: progress.hasCurrentAllocation,
              ),
          ],
        ),
        if (progress.isOverShipped)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Melebihi permintaan cabang sebanyak '
              '${progress.remainingAfterCurrentDo.absolute.formatWithUnit(unit)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // One `Text.rich` rather than two `Text`s side by side. Visually it is the
    // difference between "Diminta 3 box" reading as a phrase and reading as two
    // words that happen to be adjacent — and it is also what lets a test look for
    // the phrase instead of for its halves.
    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
