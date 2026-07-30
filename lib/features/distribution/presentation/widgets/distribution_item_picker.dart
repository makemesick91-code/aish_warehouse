import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../domain/models/distribution_models.dart';
import '../providers/distribution_providers.dart';
import 'distribution_badges.dart';

/// Horizontally scrollable category chips for the distribution form (spec §4.3).
///
/// A Distribusi copy of the Stok Opname and Purchase Request chips rather than a shared
/// widget, because what a chip row *is* is trivial and what differs is everything that
/// matters: which provider holds the selection. Sharing the widget would mean sharing
/// the filter state between three forms, so a chip left active on a Purchase Request
/// would silently hide items on a distribution.
class DistributionCategoryFilterChips extends ConsumerWidget {
  const DistributionCategoryFilterChips({super.key});

  static const Key allKey = ValueKey('distributionCategoryAll');

  static Key keyFor(String categoryId) =>
      ValueKey('distributionCategory-$categoryId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(distributionCategoriesProvider);
    final selected = ref.watch(distributionCategoryFilterProvider);

    return categories.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();

        // Height follows the chips rather than being fixed: Material 3 chips grow with
        // the text scale, and Indonesian category names are long.
        return SingleChildScrollView(
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
                    .read(distributionCategoryFilterProvider.notifier)
                    .clear(),
              ),
              for (final category in rows) ...[
                const SizedBox(width: AppSpacing.sm),
                _Chip(
                  chipKey: keyFor(category.id),
                  label: category.name,
                  selected: selected == category.id,
                  onSelected: () => ref
                      .read(distributionCategoryFilterProvider.notifier)
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

/// The destination-room chips (§29).
///
/// Dynamic from the database, never a hard-coded `R1 / R2 / R3`: rooms are master data
/// managed by the Super Admin (spec §2.1), and a branch with four rooms must show four
/// chips. Only the acting branch's rooms appear, which is the read half of G-T1.
class DistributionRoomChips extends ConsumerWidget {
  const DistributionRoomChips({super.key, required this.enabled});

  final bool enabled;

  static const Key rowKey = ValueKey('distributionRoomChips');
  static const Key emptyKey = ValueKey('distributionRoomChipsEmpty');

  static Key keyFor(String roomId) => ValueKey('distributionRoom-$roomId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(branchDistributionRoomsProvider(null));
    final selected = ref.watch(distributionSelectedRoomProvider);

    return rooms.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(describeFailure(error)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Padding(
            key: emptyKey,
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text(
              'Cabang ini belum memiliki ruangan aktif, sehingga belum ada '
              'tujuan distribusi.',
            ),
          );
        }

        return SingleChildScrollView(
          key: rowKey,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              for (final room in rows) ...[
                _Chip(
                  chipKey: keyFor(room.id),
                  label: '${room.code} · ${room.name}',
                  selected: selected == room.id,
                  onSelected: enabled
                      ? () => ref
                            .read(distributionSelectedRoomProvider.notifier)
                            .select(room.id)
                      : null,
                ),
                const SizedBox(width: AppSpacing.sm),
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
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Key chipKey;
  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      key: chipKey,
      label: Text(label),
      selected: selected,
      onSelected: onSelected == null ? null : (_) => onSelected!(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Typeahead search over what the **branch store** actually holds (§15, spec §4.3).
///
/// Results are rendered inline beneath the field rather than through [RawAutocomplete],
/// for the reason the Stok Opname and Purchase Request pickers document:
/// `RawAutocomplete` computes options synchronously from the text change, while these
/// arrive from a debounced Drift query a moment later, so options that resolve after the
/// keystroke would never be shown.
///
/// Three rules make this picker different from the Purchase Request one, and all three
/// come from §15:
///
/// * only items with a **positive branch-store balance** appear — a distribution moves
///   goods that are already at the branch, so there is nothing to offer otherwise;
/// * expired batches never count towards that balance (G-E4), so an item whose only
///   stock has expired is absent rather than offered and then refused;
/// * every query runs against the local database, so it keeps working with no network
///   (G-Y1) and follows the active category chip.
class DistributionItemPicker extends ConsumerStatefulWidget {
  const DistributionItemPicker({
    super.key,
    required this.onSelected,
    this.label = 'Cari barang bersaldo (nama atau SKU)',
    this.enabled = true,
    this.excludedItemIds = const <String>{},
  });

  final ValueChanged<DistributionStockItem> onSelected;
  final String label;
  final bool enabled;

  /// Items the selected room already holds. They are still listed, but marked, so the
  /// branch head can see why picking one will not add a second row.
  final Set<String> excludedItemIds;

  static const Key fieldKey = ValueKey('distributionItemSearchField');
  static const Key emptyKey = ValueKey('distributionItemSearchEmpty');

  static Key optionKeyFor(String itemId) =>
      ValueKey('distributionItemOption-$itemId');

  /// Debounce so a fast typist does not trigger a query per keystroke — the ±200 ms
  /// spec §4.3 asks for.
  static const Duration debounce = Duration(milliseconds: 200);

  /// The specification caps the dropdown at about eight scrollable results.
  static const int maxResults = 8;

  @override
  ConsumerState<DistributionItemPicker> createState() =>
      _DistributionItemPickerState();
}

class _DistributionItemPickerState
    extends ConsumerState<DistributionItemPicker> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;
  String _query = '';

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    // Rebuild now so the clear button appears with the first keystroke rather than a
    // debounce later; only the query itself waits.
    setState(() {});
    _debounceTimer = Timer(DistributionItemPicker.debounce, () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  void _select(DistributionStockItem item) {
    widget.onSelected(item);
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _query.trim();
    final categoryId = ref.watch(distributionCategoryFilterProvider);
    final results = trimmed.isEmpty
        ? const AsyncValue<List<DistributionStockItem>>.data(
            <DistributionStockItem>[],
          )
        : ref.watch(
            distributionStockSearchProvider((
              query: trimmed,
              categoryId: categoryId,
            )),
          );
    final nowUtc = ref.watch(distributionClockProvider)();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: DistributionItemPicker.fieldKey,
          controller: _controller,
          enabled: widget.enabled,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Hapus pencarian',
                    icon: const Icon(Icons.clear),
                    onPressed: _clear,
                  ),
          ),
        ),
        if (trimmed.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          results.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(describeFailure(error)),
            ),
            data: (rows) => _ResultsPanel(
              items: rows
                  .take(DistributionItemPicker.maxResults)
                  .toList(growable: false),
              query: trimmed,
              excludedItemIds: widget.excludedItemIds,
              nowUtc: nowUtc,
              onSelected: _select,
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({
    required this.items,
    required this.query,
    required this.excludedItemIds,
    required this.nowUtc,
    required this.onSelected,
  });

  final List<DistributionStockItem> items;
  final String query;
  final Set<String> excludedItemIds;
  final DateTime nowUtc;
  final ValueChanged<DistributionStockItem> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          key: DistributionItemPicker.emptyKey,
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text('Tidak ditemukan'),
        ),
      );
    }

    return Card(
      child: ConstrainedBox(
        // Roughly four rows tall, then it scrolls.
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            final already = excludedItemIds.contains(item.itemId);
            final nearestExpiry = item.nearestExpiryDate;

            return ListTile(
              key: DistributionItemPicker.optionKeyFor(item.itemId),
              dense: true,
              title: _HighlightedText(text: item.itemName, needle: query),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.sku} · ${item.availableQty.formatWithUnit(item.unit)}'
                    '${item.hasExpiry ? ' · ${item.batchCount} batch' : ''}',
                  ),
                  if (nearestExpiry != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: DistributionExpiryBadge(
                        expiryDate: nearestExpiry,
                        expiryAlertDays: item.expiryAlertDays,
                        nowUtc: nowUtc,
                      ),
                    ),
                ],
              ),
              isThreeLine: nearestExpiry != null,
              trailing: already
                  ? const Text('Sudah ada')
                  : const Icon(Icons.add, size: 18),
              onTap: already ? null : () => onSelected(item),
            );
          },
        ),
      ),
    );
  }
}

/// Bolds the part of [text] that matched what the user typed.
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.needle});

  final String text;
  final String needle;

  @override
  Widget build(BuildContext context) {
    final trimmed = needle.trim();
    final base = DefaultTextStyle.of(context).style;
    if (trimmed.isEmpty) return Text(text, style: base);

    final start = text.toLowerCase().indexOf(trimmed.toLowerCase());
    if (start < 0) return Text(text, style: base);
    final end = start + trimmed.length;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      style: base,
    );
  }
}
