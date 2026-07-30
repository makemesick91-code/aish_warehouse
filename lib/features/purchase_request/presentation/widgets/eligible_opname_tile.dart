import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../domain/models/purchase_request_models.dart';

/// One stock opname the branch head may cite, as a checkbox row (§24.2).
///
/// Everything shown here is what makes a count worth citing or not: the room, the
/// ISO period, whether it has merely been submitted or already reviewed, who
/// counted it, when it was handed over — in GMT+8, with the zone spelled out
/// (T-2) — and how many positions came out different from the system.
///
/// The list this appears in contains **only eligible counts**: the query behind it
/// is already restricted to the actor's branch, to `submitted`/`reviewed`, and to
/// the current and previous operational weeks (G-P1). There is deliberately no
/// "ineligible, greyed out" state, because rendering a count that cannot be chosen
/// invites the question of why, and the honest answer — "it is from another branch"
/// — is one this screen should not be in the business of answering.
class EligibleOpnameTile extends StatelessWidget {
  const EligibleOpnameTile({
    super.key,
    required this.reference,
    required this.selected,
    this.onChanged,
  });

  final PurchaseRequestOpnameReference reference;
  final bool selected;

  /// `null` renders the tile read-only — the detail screen of a sent request.
  final ValueChanged<bool>? onChanged;

  /// Lets tests address one tile without matching on prose.
  static Key keyFor(String opnameId) => ValueKey('eligibleOpname-$opnameId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handedOver = reference.handedOverAt;

    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xs / 2),
        Text(
          '${reference.docNumber} · ${reference.periodLabel} · '
          '${reference.status.label}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          'Dihitung ${reference.countedByName}'
          '${handedOver == null ? '' : ' · ${AppDateTimeFormatter.dateTimeWithZone(handedOver)}'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _Tag(
              label: reference.hasDifference
                  ? '${reference.differenceLineCount} baris berselisih'
                  : 'Tanpa selisih',
              color: reference.hasDifference
                  ? AppColors.warning
                  : AppColors.success,
            ),
            if (reference.usesHistoricalMaster)
              HistoricalMasterBadge.historical(
                detail: [
                  if (reference.roomIsHistorical) 'Ruangan',
                  if (reference.countedByIsHistorical) 'Perawat',
                ].join(', '),
              ),
          ],
        ),
      ],
    );

    final title = Text(
      '${reference.roomCode} · ${reference.roomName}',
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    if (onChanged == null) {
      return ListTile(
        key: keyFor(reference.opnameId),
        leading: const Icon(Icons.fact_check_outlined),
        title: title,
        subtitle: subtitle,
        isThreeLine: true,
      );
    }

    return CheckboxListTile(
      key: keyFor(reference.opnameId),
      value: selected,
      onChanged: (value) => onChanged!(value ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      title: title,
      subtitle: subtitle,
      isThreeLine: true,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

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
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
