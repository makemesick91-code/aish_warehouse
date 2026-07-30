import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../master/domain/models/master_models.dart';
import '../providers/purchase_request_providers.dart';

/// Horizontally scrollable category chips for the review step (spec §4.3).
///
/// A Purchase Request copy of the Stok Opname chips rather than a shared widget,
/// because what a chip row *is* is trivial and what differs is everything that
/// matters: which provider holds the selection. Sharing the widget would mean
/// sharing the filter state between two forms, so a chip left active on an opname
/// sheet would silently hide lines on a Purchase Request.
class PurchaseRequestCategoryFilterChips extends ConsumerWidget {
  const PurchaseRequestCategoryFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(purchaseRequestCategoriesProvider);
    final selected = ref.watch(purchaseRequestCategoryFilterProvider);

    return categories.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();

        // Height follows the chips rather than being fixed: Material 3 chips grow
        // with the text scale, and Indonesian category names are long.
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
                onSelected: () => ref
                    .read(purchaseRequestCategoryFilterProvider.notifier)
                    .clear(),
              ),
              for (final category in rows) ...[
                const SizedBox(width: AppSpacing.sm),
                _Chip(
                  label: category.name,
                  selected: selected == category.id,
                  onSelected: () => ref
                      .read(purchaseRequestCategoryFilterProvider.notifier)
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

/// Typeahead search over the local item catalogue, for adding an item by hand
/// (spec §4.3 SearchableDropdown).
///
/// Results are rendered inline beneath the field rather than through
/// [RawAutocomplete], for the reason the Stok Opname dropdown documents:
/// `RawAutocomplete` computes options synchronously from the text change, while
/// these arrive from a debounced Drift query a moment later, so options that
/// resolve after the keystroke would never be shown.
///
/// Every query runs against the local database, so the dropdown keeps working with
/// no network (G-Y1), and it follows the active category chip. Only **active**
/// items are returned: adding an item is new work, and master data that has been
/// withdrawn may not be ordered (G-A4).
class PurchaseRequestItemPicker extends ConsumerStatefulWidget {
  const PurchaseRequestItemPicker({
    super.key,
    required this.onSelected,
    this.label = 'Tambah barang (nama atau SKU)',
    this.enabled = true,
    this.excludedItemIds = const <String>{},
  });

  final ValueChanged<MasterItem> onSelected;
  final String label;
  final bool enabled;

  /// Items already on the request. They are still listed, but marked, so the
  /// branch head can see why picking one will not add a second row (G-P2).
  final Set<String> excludedItemIds;

  @override
  ConsumerState<PurchaseRequestItemPicker> createState() =>
      _PurchaseRequestItemPickerState();
}

class _PurchaseRequestItemPickerState
    extends ConsumerState<PurchaseRequestItemPicker> {
  /// Debounce so a fast typist does not trigger a query per keystroke.
  static const Duration debounce = Duration(milliseconds: 200);

  /// The specification caps the dropdown at about eight scrollable results.
  static const int maxResults = 8;

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
    // Rebuild now so the clear button appears with the first keystroke rather
    // than a debounce later; only the query itself waits.
    setState(() {});
    _debounceTimer = Timer(debounce, () {
      if (!mounted) return;
      setState(() => _query = value);
      // The same text also narrows the lines already on the request, so typing
      // "masker" both finds the item to add and filters the order to it.
      ref.read(purchaseRequestSearchQueryProvider.notifier).update(value);
    });
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() => _query = '');
    ref.read(purchaseRequestSearchQueryProvider.notifier).clear();
  }

  void _select(MasterItem item) {
    widget.onSelected(item);
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _query.trim();
    final results = trimmed.isEmpty
        ? const AsyncValue<List<MasterItem>>.data(<MasterItem>[])
        : ref.watch(purchaseRequestAddableItemSearchProvider(trimmed));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
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
              items: rows.take(maxResults).toList(growable: false),
              query: trimmed,
              excludedItemIds: widget.excludedItemIds,
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
    required this.onSelected,
  });

  final List<MasterItem> items;
  final String query;
  final Set<String> excludedItemIds;
  final ValueChanged<MasterItem> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text('Tidak ditemukan'),
        ),
      );
    }

    return Card(
      child: ConstrainedBox(
        // Roughly four rows tall, then it scrolls.
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            final already = excludedItemIds.contains(item.id);
            return ListTile(
              key: ValueKey('prItemOption-${item.id}'),
              dense: true,
              title: _HighlightedText(text: item.name, needle: query),
              subtitle: Text('${item.sku} · ${item.unit}'),
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
