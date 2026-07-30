import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../providers/distribution_providers.dart';
import 'distribution_badges.dart';

/// The Distribusi cards on the Kepala Cabang's dashboard (§31).
///
/// Four numbers, and each one answers a question the branch head actually has:
///
/// * **drafts** — unfinished work, the one thing on this card that is *theirs to do*;
/// * **posted today** — what has already gone out, in operational time (GMT+8);
/// * **stok menipis** — items below `items.min_stock_branch`, which is what a Purchase
///   Request is raised for;
/// * **kedaluwarsa / segera kedaluwarsa** — G-E6's automatic warning. Expired stock is
///   not distributable at all (G-E4) and leaves through disposal (G-E7), so the number
///   is a prompt to act rather than something the distribution screen can resolve.
///
/// Deliberately small. §31 warns against building a second dashboard here, and every
/// count is derived from providers the list screen already uses rather than from new
/// queries — so a number on the dashboard and the list behind it cannot disagree.
///
/// The whole widget renders nothing for a role that may not distribute: the branch
/// providers behind it emit empty for anyone else, and the dashboard only mounts it for
/// a Kepala Cabang in the first place.
class DistributionDashboardCards extends ConsumerWidget {
  const DistributionDashboardCards({super.key});

  static const Key cardKey = ValueKey('distributionDashboardCard');
  static const Key draftCountKey = ValueKey('distributionDraftCount');
  static const Key todayCountKey = ValueKey('distributionTodayCount');
  static const Key alertsKey = ValueKey('distributionStoreAlerts');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final drafts = ref.watch(branchDraftDistributionCountProvider);
    final today = ref.watch(branchDistributionsPostedTodayProvider);
    final alerts = ref.watch(branchStoreAlertsProvider);

    return Card(
      key: cardKey,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => context.pushNamed(AppRoutes.distributionsName),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.outbound_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Distribusi ruangan',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  DistributionPill(
                    pillKey: draftCountKey,
                    label: '$drafts draft belum diposting',
                    color: drafts > 0 ? AppColors.warning : Colors.blueGrey,
                    icon: Icons.edit_note,
                  ),
                  DistributionPill(
                    pillKey: todayCountKey,
                    label: '$today diposting hari ini',
                    color: AppColors.success,
                    icon: Icons.check_circle_outline,
                  ),
                ],
              ),
              alerts.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (data) {
                  if (data.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Wrap(
                      key: alertsKey,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (data.lowStockItems > 0)
                          DistributionPill(
                            label: '${data.lowStockItems} stok cabang menipis',
                            color: AppColors.warning,
                            icon: Icons.trending_down,
                          ),
                        if (data.nearExpiryPositions > 0)
                          DistributionPill(
                            label:
                                '${data.nearExpiryPositions} segera '
                                'kedaluwarsa',
                            color: AppColors.warning,
                            icon: Icons.timelapse,
                          ),
                        if (data.expiredPositions > 0)
                          DistributionPill(
                            label: '${data.expiredPositions} kedaluwarsa',
                            color: AppColors.danger,
                            icon: Icons.event_busy,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
