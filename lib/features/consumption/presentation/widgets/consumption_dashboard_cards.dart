import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/status_card.dart';
import '../providers/consumption_providers.dart';

/// The Perawat's Pemakaian cards on the home dashboard (§32).
///
/// Five numbers, and the last two are G-E6's badges rendered as counts rather than as
/// pills: *"Segera kedaluwarsa"* in the room the nurse is looking at, and
/// *"Kedaluwarsa"* — which they cannot consume at all. The second one is the interesting
/// card: every query this feature offers hides expired positions by design (§24), so the
/// count comes from the inventory repository instead. G-E6 asks for the warning to be
/// *shown*; §17 asks for the stock to be *unusable*. Both are true at once, and the card
/// is where a nurse learns that somebody has to file a Pemusnahan.
///
/// Reads nothing but providers whose scope is derived from the *stored* actor, so a card
/// cannot report another branch's room.
class ConsumptionDashboardCards extends ConsumerWidget {
  const ConsumptionDashboardCards({super.key});

  static const Key cardsKey = ValueKey('consumptionDashboardCards');
  static const Key draftKey = ValueKey('consumptionCardDrafts');
  static const Key todayKey = ValueKey('consumptionCardToday');
  static const Key lowStockKey = ValueKey('consumptionCardLowStock');
  static const Key nearExpiryKey = ValueKey('consumptionCardNearExpiry');
  static const Key expiredKey = ValueKey('consumptionCardExpired');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(nurseConsumptionDashboardProvider).value;
    if (summary == null) return const SizedBox.shrink();

    return Column(
      key: cardsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: draftKey,
                child: StatusCard(
                  label: 'Draft pemakaian',
                  value: '${summary.draftCount}',
                  icon: Icons.edit_note,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: KeyedSubtree(
                key: todayKey,
                child: StatusCard(
                  label: 'Dipakai hari ini',
                  value: '${summary.postedTodayCount}',
                  icon: Icons.today,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: lowStockKey,
                child: StatusCard(
                  label: 'Stok ruangan menipis',
                  value: '${summary.lowStockPositions}',
                  icon: Icons.trending_down,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: KeyedSubtree(
                key: nearExpiryKey,
                child: StatusCard(
                  label: 'Segera kedaluwarsa',
                  value: '${summary.nearExpiryPositions}',
                  icon: Icons.schedule,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: KeyedSubtree(
                key: expiredKey,
                child: StatusCard(
                  label: 'Kedaluwarsa',
                  value: '${summary.expiredPositions}',
                  icon: Icons.block,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The Kepala Cabang's Pemakaian card on the home dashboard (§32).
///
/// Deliberately minimal, as §32 asks: how much was used today across the branch, and
/// which room used the most — as a **document count**, because quantities of different
/// units are not addable and "the busiest room" has no single answer in units. There is
/// no write affordance here and none on the screen it links to.
class BranchConsumptionCard extends ConsumerWidget {
  const BranchConsumptionCard({super.key});

  static const Key cardKey = ValueKey('branchConsumptionCard');
  static const Key todayKey = ValueKey('branchConsumptionCardToday');
  static const Key roomKey = ValueKey('branchConsumptionCardRoom');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(branchConsumptionDashboardProvider);
    final rooms = ref.watch(branchConsumptionRoomsProvider).value ?? const [];

    final busiestId = dashboard.busiestRoomId;
    final match = rooms.where((room) => room.roomId == busiestId);
    final roomLabel = busiestId == null || match.isEmpty
        ? '—'
        : match.first.code;
    final documentCount = busiestId == null
        ? 0
        : dashboard.documentsByRoom[busiestId] ?? 0;

    return Row(
      key: cardKey,
      children: [
        Expanded(
          child: KeyedSubtree(
            key: todayKey,
            child: StatusCard(
              label: 'Pemakaian hari ini',
              value: '${dashboard.postedTodayCount}',
              icon: Icons.today,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: KeyedSubtree(
            key: roomKey,
            child: StatusCard(
              label: 'Ruangan tertinggi · $documentCount dokumen',
              value: roomLabel,
              icon: Icons.meeting_room_outlined,
            ),
          ),
        ),
      ],
    );
  }
}
