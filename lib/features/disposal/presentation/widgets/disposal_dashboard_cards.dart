import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../providers/disposal_providers.dart';
import 'disposal_badges.dart';

/// The Pemusnahan card on the Petugas Warehouse's dashboard (§33).
///
/// Two numbers, and each answers a question the warehouse actually has:
///
/// * **kedaluwarsa** — G-E6's automatic warning, counted per batch **position**
///   because that is what somebody acts on: one batch to destroy, rather than "this
///   product has a problem". Before this milestone the number was a dead end — there
///   was no way to remove the stock it counted — and the card is now the entry point
///   to the workflow that resolves it (G-E7).
/// * **draft** — unfinished work, the one thing on this card that is *theirs to do*.
///
/// Deliberately small. §33 warns against building the reporting module here: the
/// full *Laporan Kadaluarsa* with its per-location breakdown and its Excel/PDF export
/// is G-E8, and that is a later milestone. Every count is derived from providers the
/// list screen already uses rather than from new queries — so a number on the
/// dashboard and the list behind it cannot disagree.
class WarehouseDisposalCard extends ConsumerWidget {
  const WarehouseDisposalCard({super.key});

  static const Key cardKey = ValueKey('warehouseDisposalDashboardCard');
  static const Key expiredKey = ValueKey('warehouseDisposalExpiredCount');
  static const Key draftKey = ValueKey('warehouseDisposalDraftCount');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(warehouseDisposalDashboardProvider);

    return Card(
      key: cardKey,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => context.pushNamed(AppRoutes.warehouseDisposalsName),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.delete_forever_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Pemusnahan stok warehouse',
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
                  DisposalPill(
                    pillKey: expiredKey,
                    label: '${summary.expiredPositions} batch kedaluwarsa',
                    color: summary.expiredPositions > 0
                        ? AppColors.danger
                        : Colors.blueGrey,
                    icon: Icons.event_busy,
                  ),
                  DisposalPill(
                    pillKey: draftKey,
                    label: '${summary.draftCount} draft belum diposting',
                    color: summary.draftCount > 0
                        ? AppColors.warning
                        : Colors.blueGrey,
                    icon: Icons.edit_note,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Pemusnahan card on the Kepala Cabang's dashboard (§33).
///
/// The expired count is split between the *Gudang Cabang* and the rooms, because
/// they are acted on by different people on different days: the store is the branch
/// head's own shelf, and a room's expired stock usually surfaces during a nurse's
/// weekly count. One combined number would hide which of the two needs attention.
///
/// Both halves are counted across **every** location in scope rather than following
/// the source selector, so the number does not change when a chip is tapped.
class BranchDisposalCard extends ConsumerWidget {
  const BranchDisposalCard({super.key});

  static const Key cardKey = ValueKey('branchDisposalDashboardCard');
  static const Key storeKey = ValueKey('branchDisposalStoreCount');
  static const Key roomKey = ValueKey('branchDisposalRoomCount');
  static const Key draftKey = ValueKey('branchDisposalDraftCount');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(branchDisposalDashboardProvider);

    return Card(
      key: cardKey,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => context.pushNamed(AppRoutes.disposalsName),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.delete_forever_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Pemusnahan',
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
                  DisposalPill(
                    pillKey: storeKey,
                    label:
                        '${summary.storeExpiredPositions} kedaluwarsa · '
                        'Gudang Cabang',
                    color: summary.storeExpiredPositions > 0
                        ? AppColors.danger
                        : Colors.blueGrey,
                    icon: Icons.store_mall_directory_outlined,
                  ),
                  DisposalPill(
                    pillKey: roomKey,
                    label:
                        '${summary.roomExpiredPositions} kedaluwarsa · Ruangan',
                    color: summary.roomExpiredPositions > 0
                        ? AppColors.danger
                        : Colors.blueGrey,
                    icon: Icons.meeting_room_outlined,
                  ),
                  DisposalPill(
                    pillKey: draftKey,
                    label: '${summary.draftCount} draft belum diposting',
                    color: summary.draftCount > 0
                        ? AppColors.warning
                        : Colors.blueGrey,
                    icon: Icons.edit_note,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
