import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../domain/models/consumption_models.dart';
import '../providers/consumption_providers.dart';

/// Horizontally scrollable **room** chips (§27).
///
/// Built from [consumptionRoomsProvider] for a nurse and
/// [branchConsumptionRoomsProvider] for a branch head, and the caller says which — so
/// one widget serves both screens without either of them deciding a scope.
///
/// The list is master data, never a hard-coded `R1 / R2 / R3`: spec §2.1 makes rooms the
/// Super Admin's to manage, and a branch with four rooms must show four chips. What it
/// can never show is another branch's room: the provider derives the branch from the
/// *stored* actor, so there is no argument a widget could fill in wrongly.
class ConsumptionRoomChips extends ConsumerWidget {
  const ConsumptionRoomChips({super.key, this.forBranchHistory = false});

  /// `true` on the Kepala Cabang's history, `false` on the nurse's own screens.
  final bool forBranchHistory;

  static const Key chipsKey = ValueKey('consumptionRoomChips');
  static const Key allKey = ValueKey('consumptionRoomChip-all');

  static Key chipKeyFor(String roomId) =>
      ValueKey('consumptionRoomChip-$roomId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = forBranchHistory
        ? ref.watch(branchConsumptionRoomsProvider)
        : ref.watch(consumptionRoomsProvider);
    final selected = ref.watch(selectedConsumptionRoomProvider);

    return rooms.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();

        // Height follows the chips rather than being fixed: Material 3 chips grow with
        // the text scale, and a fixed box would overflow at accessibility sizes —
        // Indonesian room names are long.
        return SingleChildScrollView(
          key: chipsKey,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              _Chip(
                chipKey: allKey,
                label: 'Semua ruangan',
                selected: selected == null,
                onSelected: () =>
                    ref.read(selectedConsumptionRoomProvider.notifier).clear(),
              ),
              for (final room in rows) ...[
                const SizedBox(width: AppSpacing.sm),
                _Chip(
                  chipKey: chipKeyFor(room.roomId),
                  label: room.label,
                  selected: selected == room.roomId,
                  onSelected: () => ref
                      .read(selectedConsumptionRoomProvider.notifier)
                      .select(room.roomId),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Status chips for the nurse's own list; `null` means *Semua*.
///
/// Deliberately absent from the branch history: that list is `posted`-only by scope
/// (§14), so a status filter there would offer one option and imply the other exists.
class ConsumptionStatusChips extends ConsumerWidget {
  const ConsumptionStatusChips({super.key});

  static const Key chipsKey = ValueKey('consumptionStatusChips');
  static const Key allKey = ValueKey('consumptionStatusChip-all');

  static Key chipKeyFor(ConsumptionStatus status) =>
      ValueKey('consumptionStatusFilter-${status.dbValue}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(consumptionStatusFilterProvider);

    return SingleChildScrollView(
      key: chipsKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          _Chip(
            chipKey: allKey,
            label: 'Semua status',
            selected: selected == null,
            onSelected: () =>
                ref.read(consumptionStatusFilterProvider.notifier).clear(),
          ),
          for (final status in visibleConsumptionStatuses) ...[
            const SizedBox(width: AppSpacing.sm),
            _Chip(
              chipKey: chipKeyFor(status),
              label: status.label,
              selected: selected == status,
              onSelected: () => ref
                  .read(consumptionStatusFilterProvider.notifier)
                  .select(status),
            ),
          ],
        ],
      ),
    );
  }
}

/// Category chips for the candidate picker; `null` means *Semua* (§28).
class ConsumptionCategoryChips extends ConsumerWidget {
  const ConsumptionCategoryChips({super.key});

  static const Key chipsKey = ValueKey('consumptionCategoryChips');
  static const Key allKey = ValueKey('consumptionCategoryChip-all');

  static Key chipKeyFor(String categoryId) =>
      ValueKey('consumptionCategoryChip-$categoryId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(consumptionCategoriesProvider);
    final selected = ref.watch(consumptionCategoryFilterProvider);

    return categories.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        return SingleChildScrollView(
          key: chipsKey,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              _Chip(
                chipKey: allKey,
                label: 'Semua',
                selected: selected == null,
                onSelected: () => ref
                    .read(consumptionCategoryFilterProvider.notifier)
                    .clear(),
              ),
              for (final category in rows) ...[
                const SizedBox(width: AppSpacing.sm),
                _Chip(
                  chipKey: chipKeyFor(category.id),
                  label: category.name,
                  selected: selected == category.id,
                  onSelected: () => ref
                      .read(consumptionCategoryFilterProvider.notifier)
                      .select(category.id),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Perawat chips on the branch head's history; `null` means every nurse (§31).
class ConsumptionNurseChips extends ConsumerWidget {
  const ConsumptionNurseChips({super.key});

  static const Key chipsKey = ValueKey('consumptionNurseChips');
  static const Key allKey = ValueKey('consumptionNurseChip-all');

  static Key chipKeyFor(String userId) =>
      ValueKey('consumptionNurseChip-$userId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nurses = ref.watch(branchNursesProvider);
    final selected = ref.watch(consumptionNurseFilterProvider);

    return nurses.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        return SingleChildScrollView(
          key: chipsKey,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              _Chip(
                chipKey: allKey,
                label: 'Semua perawat',
                selected: selected == null,
                onSelected: () =>
                    ref.read(consumptionNurseFilterProvider.notifier).clear(),
              ),
              for (final nurse in rows) ...[
                const SizedBox(width: AppSpacing.sm),
                _Chip(
                  chipKey: chipKeyFor(nurse.id),
                  label: nurse.fullName,
                  selected: selected == nurse.id,
                  onSelected: () => ref
                      .read(consumptionNurseFilterProvider.notifier)
                      .select(nurse.id),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.chipKey,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Key? chipKey;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      key: chipKey,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}
