import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/goods_return_models.dart';

/// The status chip both sections show (§8/§29/§31).
///
/// The wording is [GoodsReturnStatus.label]'s and nothing else, so a chip can never
/// disagree with the enum a use case decides on. Deliberately *not* approval wording —
/// there is no approval stage to describe.
class GoodsReturnStatusChip extends StatelessWidget {
  const GoodsReturnStatusChip({super.key, required this.status});

  final GoodsReturnStatus status;

  static Key keyFor(String id) => ValueKey('goodsReturnStatus-$id');

  Color get _color => switch (status) {
    GoodsReturnStatus.draft => AppColors.warning,
    GoodsReturnStatus.shipped => AppColors.primary,
    GoodsReturnStatus.received => AppColors.success,
  };

  IconData get _icon => switch (status) {
    GoodsReturnStatus.draft => Icons.edit_note,
    GoodsReturnStatus.shipped => Icons.local_shipping_outlined,
    GoodsReturnStatus.received => Icons.inventory_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 14, color: _color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              status.label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The red *Kedaluwarsa* and orange *Segera kedaluwarsa* badges (§32/§36).
///
/// Both are **information**, never a refusal. G-E5 makes an expired or near-expiry
/// batch a legitimate reason to have rejected a delivery, and a rejection has to be able
/// to go home — so the badge tells the Warehouse what is arriving and lets them plan the
/// Pemusnahan that follows, rather than blocking the receipt.
class GoodsReturnExpiryBadge extends StatelessWidget {
  const GoodsReturnExpiryBadge({
    super.key,
    required this.line,
    required this.nowUtc,
  });

  final GoodsReturnLine line;
  final DateTime nowUtc;

  static Key keyFor(String lineId) => ValueKey('goodsReturnExpiry-$lineId');

  @override
  Widget build(BuildContext context) {
    final expiry = line.expiryDate;
    if (expiry == null) return const SizedBox.shrink();

    final expired = line.isExpired(nowUtc);
    final near = line.isNearExpiry(nowUtc);
    if (!expired && !near) {
      return Text(
        'ED ${AppDateTimeFormatter.civilDate(expiry)}',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final color = expired ? AppColors.danger : AppColors.warning;
    final label = expired ? 'Kedaluwarsa' : 'Segera kedaluwarsa';
    return Container(
      key: keyFor(line.id),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        '$label · ${AppDateTimeFormatter.civilDate(expiry)}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// An empty-state or informational panel, worded rather than blank.
class GoodsReturnNotice extends StatelessWidget {
  const GoodsReturnNotice({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Totals per unit, rendered as *"2 box · 1,5 ampul"*.
///
/// Per unit and never summed: §29 and §31 both ask for it, and the reason is arithmetic
/// rather than presentational — adding boxes to ampoules produces a number that means
/// nothing.
class GoodsReturnQuantitySummary extends StatelessWidget {
  const GoodsReturnQuantitySummary({
    super.key,
    required this.totalsByUnit,
    this.style,
  });

  final Map<String, Quantity> totalsByUnit;
  final TextStyle? style;

  static Key keyFor(String id) => ValueKey('goodsReturnTotals-$id');

  /// The same value as text, for callers that compose their own row.
  static String format(Map<String, Quantity> totalsByUnit) {
    if (totalsByUnit.isEmpty) return '—';
    final units = totalsByUnit.keys.toList()..sort();
    return units
        .map((unit) => '${totalsByUnit[unit]!.format()} $unit')
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) => Text(
    format(totalsByUnit),
    style: style ?? Theme.of(context).textTheme.bodyMedium,
  );
}

/// One row of the branch or Warehouse list (§29/§31).
class GoodsReturnSummaryCard extends StatelessWidget {
  const GoodsReturnSummaryCard({
    super.key,
    required this.summary,
    required this.nowUtc,
    this.showBranch = false,
    this.onTap,
  });

  final GoodsReturnSummary summary;
  final DateTime nowUtc;

  /// The Warehouse queue shows which branch sent the goods; the branch's own list does
  /// not, because every row on it is theirs.
  final bool showBranch;

  final VoidCallback? onTap;

  static Key keyFor(String id) => ValueKey('goodsReturnCard-$id');

  @override
  Widget build(BuildContext context) {
    final document = summary.goodsReturn;
    final transit = summary.transitAge(nowUtc);

    return Card(
      key: keyFor(summary.id),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      document.docNumber,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GoodsReturnStatusChip(status: document.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'GR ${summary.grDocNumber} · SJ ${summary.doDocNumber} · '
                'PR ${summary.prDocNumber}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (showBranch) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  summary.branchLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${summary.lineCount} posisi · '
                '${GoodsReturnQuantitySummary.format(summary.totalsByUnit)}',
                key: GoodsReturnQuantitySummary.keyFor(summary.id),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _timeline(document, transit),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.progressLabel,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (document.isPendingSync)
                    SyncStatusTag(status: document.syncStatus),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The instant that matters to the reader, in operational time (GMT+8).
  String _timeline(GoodsReturn document, Duration? transit) {
    if (document.isReceived && document.receivedAt != null) {
      return 'Diterima ${AppDateTimeFormatter.dateTimeWithZone(document.receivedAt!)}'
          '${summary.receivedByName == null ? '' : ' · ${summary.receivedByName}'}';
    }
    if (document.isShipped && document.shippedAt != null) {
      final age = transit == null ? '' : ' · ${_ageLabel(transit)} di jalan';
      return 'Dikirim '
          '${AppDateTimeFormatter.dateTimeWithZone(document.shippedAt!)}$age';
    }
    return 'Dibuat ${AppDateTimeFormatter.dateTimeWithZone(document.createdAt)}';
  }

  static String _ageLabel(Duration age) {
    if (age.inDays >= 1) return '${age.inDays} hari';
    if (age.inHours >= 1) return '${age.inHours} jam';
    return '${age.inMinutes} menit';
  }
}
