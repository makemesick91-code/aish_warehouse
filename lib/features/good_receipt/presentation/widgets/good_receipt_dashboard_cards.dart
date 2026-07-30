import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../providers/good_receipt_providers.dart';

/// G-G6's in-app reminder, on the Kepala Cabang's dashboard (§18/§30).
///
/// An in-app card rather than a platform notification, deliberately. G-G6 asks for a
/// reminder; a badge the branch head sees the moment they open the app is one, and it
/// costs no notification package, no permission prompt and no background task — three
/// things this milestone would have to ship untested. When the clinic wants a push, the
/// count this card reads is already the number to send.
///
/// Renders nothing for a role it does not belong to, and nothing when there is nothing
/// urgent: a card that is always on screen is a card nobody reads. "Urgent" is overdue
/// or within twelve hours of the deadline — [GoodReceiptReminderBuilder.urgentOnly]
/// decides, so this card and the list it links to agree by construction.
class GoodReceiptReminderCard extends ConsumerWidget {
  const GoodReceiptReminderCard({super.key});

  static const Key cardKey = ValueKey('goodReceiptReminderCard');
  static const Key countKey = ValueKey('goodReceiptReminderCount');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
      return const SizedBox.shrink();
    }

    final urgent = ref.watch(branchGoodReceiptUrgentRemindersProvider(null));
    if (urgent.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final overdue = urgent.where((reminder) => reminder.isOverdue).length;
    final color = overdue > 0 ? AppColors.danger : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        key: cardKey,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.pushNamed(AppRoutes.receiptsName),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.timer_outlined, color: color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        key: countKey,
                        overdue > 0
                            ? '$overdue penerimaan melewati batas 2×24 jam'
                            : '${urgent.length} penerimaan mendekati batas 2×24 jam',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Periksa dan posting Good Receipt agar stok Gudang '
                        'Cabang mencerminkan barang yang benar-benar diterima.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// *Selisih GR dari Cabang* — the warehouse's dashboard card (§33).
///
/// Counts the rows on the selisih/retur queue and links to it. Nothing here is
/// actionable beyond navigating: the physical return is a later milestone's document,
/// and a card that offered to "resolve" a discrepancy would be inventing stock nobody
/// has counted back in.
class GoodReceiptDiscrepancyCard extends ConsumerWidget {
  const GoodReceiptDiscrepancyCard({super.key});

  static const Key cardKey = ValueKey('goodReceiptDiscrepancyCard');
  static const Key countKey = ValueKey('goodReceiptDiscrepancyCount');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
      return const SizedBox.shrink();
    }

    final entries =
        ref.watch(warehouseDiscrepancyQueueProvider(null)).value ?? const [];
    if (entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final returns = entries.where((entry) => entry.returnRequired).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        key: cardKey,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.pushNamed(
            AppRoutes.warehouseGoodReceiptDiscrepanciesName,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(
                  Icons.rule_folder_outlined,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        key: countKey,
                        'Selisih GR dari Cabang · ${entries.length} baris',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        returns > 0
                            ? '$returns baris ditolak cabang dan perlu retur ke '
                                  'Warehouse.'
                            : 'Seluruh selisih berupa kekurangan pengiriman.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
