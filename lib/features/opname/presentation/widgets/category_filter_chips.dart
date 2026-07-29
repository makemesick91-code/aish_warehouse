import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../providers/opname_providers.dart';

/// Horizontally scrollable category chips (spec §4.3).
///
/// The selection drives both the visible item list *and* the results of the
/// SearchableDropdown, which is why it lives in a provider rather than in the
/// widget's own state.
class CategoryFilterChips extends ConsumerWidget {
  const CategoryFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(itemCategoriesProvider);
    final selected = ref.watch(opnameCategoryFilterProvider);

    return categories.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();

        // Height follows the chips rather than being fixed at 44: Material 3
        // chips grow with the text scale, and a fixed box would overflow at
        // accessibility sizes — Indonesian category names are long.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              _Chip(
                label: 'Semua',
                selected: selected == null,
                onSelected: () =>
                    ref.read(opnameCategoryFilterProvider.notifier).clear(),
              ),
              for (final category in rows) ...[
                const SizedBox(width: AppSpacing.sm),
                _Chip(
                  label: category.name,
                  selected: selected == category.id,
                  onSelected: () => ref
                      .read(opnameCategoryFilterProvider.notifier)
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}
