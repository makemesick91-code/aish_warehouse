import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/opname_models.dart';

/// Who did what, and when (spec §4.3 DocTimeline, G-A3).
///
/// Every timestamp is a UTC instant converted to GMT+8 for display, with the
/// zone spelled out so nobody reads it as device time (T-2).
class DocumentTimeline extends StatelessWidget {
  const DocumentTimeline({super.key, required this.summary});

  final StockOpnameSummary summary;

  @override
  Widget build(BuildContext context) {
    final opname = summary.opname;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Step(
          icon: Icons.edit_note,
          title: 'Dibuat',
          actor: summary.countedByName,
          timestamp: opname.createdAt,
          done: true,
        ),
        _Step(
          icon: Icons.send,
          title: 'Dikirim',
          actor: summary.countedByName,
          timestamp: opname.submittedAt,
          done: opname.submittedAt != null,
          pendingLabel: 'Belum dikirim',
        ),
        _Step(
          icon: Icons.lock,
          title: 'Direview & dikunci',
          actor: summary.reviewedByName,
          timestamp: opname.reviewedAt,
          done: opname.isReviewed,
          pendingLabel: opname.isSubmitted
              ? 'Menunggu review Kepala Cabang'
              : 'Belum direview',
          isLast: true,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.actor,
    required this.timestamp,
    required this.done,
    this.pendingLabel,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String? actor;

  /// UTC instant, or `null` while this step has not happened.
  final DateTime? timestamp;
  final bool done;
  final String? pendingLabel;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = done ? AppColors.primary : theme.colorScheme.outline;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(icon, size: 18, color: color),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: color.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                      color: done ? null : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (done && timestamp != null)
                    Text(
                      '${actor ?? '—'} · '
                      '${AppDateTimeFormatter.dateTimeWithZone(timestamp!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Text(
                      pendingLabel ?? '—',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
