import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/models/opname_models.dart';

/// Names which parts of a header are historic, e.g. `Ruangan, Perawat`.
String _historicalMasterDetail(StockOpnameSummary summary) => [
  if (summary.branchIsHistorical) 'Cabang',
  if (summary.roomIsHistorical) 'Ruangan',
  if (summary.countedByIsHistorical) 'Perawat',
].join(', ');

/// Marks a document that rests on master data which is no longer in service.
///
/// The alternative — dropping such documents out of the lists — is what makes a
/// submitted count look like it was never filed at all, and it is why the
/// queries behind these screens filter neither `is_active` nor `deleted_at`
/// (§7.6). A count whose room was retired last week is still a real count that
/// still has to be reviewed; the reader just needs to be told why the room no
/// longer appears in the room picker.
///
/// Wording is deliberately plain rather than alarming: nothing is wrong with
/// the document.
class HistoricalMasterBadge extends StatelessWidget {
  const HistoricalMasterBadge({super.key, required this.label, this.detail});

  /// `Data historis · Ruangan, Perawat` for a document header.
  const HistoricalMasterBadge.historical({Key? key, String? detail})
    : this(key: key, label: 'Data historis', detail: detail);

  /// `Nonaktif` for a single row, e.g. one line's item.
  const HistoricalMasterBadge.inactive({Key? key, String? detail})
    : this(key: key, label: 'Nonaktif', detail: detail);

  /// The header badge, or nothing at all when the document rests entirely on
  /// current master data.
  ///
  /// One call instead of the `if (summary.usesHistoricalMaster) … detail: …`
  /// pair that all four screens would otherwise repeat — two predicates over
  /// the same three booleans, in four places, is how they drift apart.
  static Widget forSummary(StockOpnameSummary summary) {
    if (!summary.usesHistoricalMaster) return const SizedBox.shrink();
    return HistoricalMasterBadge.historical(
      detail: _historicalMasterDetail(summary),
    );
  }

  final String label;

  /// What exactly is historic, e.g. `Ruangan, Perawat`.
  final String? detail;

  /// Lets tests address the badge without matching on prose.
  static const Key badgeKey = ValueKey('historicalMasterBadge');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = detail == null ? label : '$label · $detail';

    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
