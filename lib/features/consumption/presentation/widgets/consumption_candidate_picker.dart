import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../../../core/widgets/status_card.dart';
import '../../domain/models/consumption_models.dart';
import '../providers/consumption_providers.dart';
import 'consumption_badges.dart';

/// What the picker hands back: one room position and how much of it was used.
class ConsumptionCandidateChoice {
  const ConsumptionCandidateChoice({required this.position, required this.qty});

  final RoomStockPosition position;
  final Quantity qty;
}

/// Chooses one room position to add to a draft (§28).
///
/// Everything it can offer is **consumable**: it reads
/// [consumptionCandidateSearchResultsProvider], which applies
/// `ConsumptionExpiryPolicy` inside the repository, so there is no code path here that
/// could surface an expired batch — not a greyed-out row, not a disabled tile, not a
/// checkbox that overrides anything. §17 asks for that directly, and the absence of a
/// control is a stronger guarantee than a disabled one. Expired stock leaves through a
/// Pemusnahan (G-E7), which is a different screen with a different actor.
///
/// A **near-expiry** batch is offered plainly, with an orange badge and a notice saying
/// it should be used first. That is the opposite of the Pemusnahan picker's treatment of
/// the same badge, and it is the whole point of §17: the stock closest to its date is the
/// stock a nurse should reach for, so nothing here makes it harder to pick and no
/// override reason is asked for.
///
/// The quantity is left **empty** rather than defaulted to the whole position, and the
/// difference from the Pemusnahan picker is deliberate: destroying all of an expired batch
/// is the ordinary case, whereas using all of a room's stock of something is the
/// exception. A pre-filled maximum would be a number a tired nurse accepts.
///
/// Search runs against the local database with a short debounce, so the clinic keeps
/// searching offline (G-Y1) without a query per keystroke. The result set is capped at
/// eight positions by the repository.
class ConsumptionCandidatePicker extends ConsumerStatefulWidget {
  const ConsumptionCandidatePicker({
    super.key,
    required this.consumptionId,
    required this.alreadyChosen,
  });

  /// The document being edited. The picker reads *its* room rather than the room
  /// selector's, because a form is open on one specific document whose room is fixed.
  final String consumptionId;

  /// `item|batch` keys already on the document. Shown as taken rather than hidden, so a
  /// nurse looking for a batch they have already added finds it and understands why it
  /// cannot be added twice.
  final Set<String> alreadyChosen;

  static const Key sheetKey = ValueKey('consumptionCandidatePicker');
  static const Key searchKey = ValueKey('consumptionCandidatePickerSearch');
  static const Key emptyKey = ValueKey('consumptionCandidatePickerEmpty');
  static const Key listKey = ValueKey('consumptionCandidatePickerList');
  static const Key qtyKey = ValueKey('consumptionCandidatePickerQty');
  static const Key addKey = ValueKey('consumptionCandidatePickerAdd');

  static Key tileKeyFor(String positionKey) =>
      ValueKey('consumptionCandidateTile-$positionKey');

  /// Debounce window for the search field. Long enough to skip the keystrokes of a word,
  /// short enough that the list feels live.
  static const Duration searchDebounce = Duration(milliseconds: 200);

  @override
  ConsumerState<ConsumptionCandidatePicker> createState() =>
      _ConsumptionCandidatePickerState();
}

class _ConsumptionCandidatePickerState
    extends ConsumerState<ConsumptionCandidatePicker> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _qty = TextEditingController();
  Timer? _debounce;
  RoomStockPosition? _selected;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      ConsumptionCandidatePicker.searchDebounce,
      () => ref.read(consumptionCandidateSearchProvider.notifier).update(value),
    );
  }

  void _select(RoomStockPosition position) {
    setState(() {
      _selected = position;
      // Deliberately blank: how much was used is a fact only the nurse knows, and
      // pre-filling the maximum would be a number they might simply accept.
      _qty.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(
      consumptionCandidateSearchResultsProvider(widget.consumptionId),
    );
    final nowUtc = ref.watch(consumptionClockProvider)();
    final selected = _selected;

    return SafeArea(
      key: ConsumptionCandidatePicker.sheetKey,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                key: ConsumptionCandidatePicker.searchKey,
                controller: _search,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  labelText: 'Cari barang, SKU atau batch di ruangan ini',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: results.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: ErrorNotice(message: describeFailure(error)),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: ConsumptionNotice(
                        key: ConsumptionCandidatePicker.emptyKey,
                        title: 'Tidak ada stok yang dapat dipakai',
                        message:
                            'Ruangan ini tidak memiliki barang bersaldo yang '
                            'masih berlaku. Batch yang sudah kedaluwarsa tidak '
                            'dapat dipakai dan hanya keluar melalui pemusnahan.',
                        icon: Icons.inventory_2_outlined,
                      ),
                    );
                  }
                  final hasNearExpiry = rows.any(
                    (position) => position.isNearExpiryOn(nowUtc),
                  );
                  return ListView.builder(
                    key: ConsumptionCandidatePicker.listKey,
                    shrinkWrap: true,
                    itemCount: rows.length + (hasNearExpiry ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (hasNearExpiry && index == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: ConsumptionNearExpiryNotice(),
                        );
                      }
                      final position = rows[index - (hasNearExpiry ? 1 : 0)];
                      final taken = widget.alreadyChosen.contains(
                        position.positionKey,
                      );
                      return _CandidateTile(
                        position: position,
                        nowUtc: nowUtc,
                        taken: taken,
                        selected: selected?.positionKey == position.positionKey,
                        onTap: taken ? null : () => _select(position),
                      );
                    },
                  );
                },
              ),
            ),
            if (selected != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.isBatched
                          ? '${selected.itemName} · batch ${selected.batchNo}'
                          : selected.itemName,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    QuantityField(
                      key: ConsumptionCandidatePicker.qtyKey,
                      controller: _qty,
                      label: 'Jumlah dipakai',
                      unit: selected.unit,
                      helperText:
                          'Tersedia '
                          '${selected.qtyOnHand.formatWithUnit(selected.unit)}',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: ConsumptionCandidatePicker.addKey,
                        onPressed: () {
                          final qty = Quantity.tryParse(_qty.text);
                          // Refused here as well as in the use case, so a bad number
                          // never closes the sheet and loses the nurse's selection.
                          if (qty == null || !qty.isPositive) return;
                          Navigator.of(context).pop(
                            ConsumptionCandidateChoice(
                              position: selected,
                              qty: qty,
                            ),
                          );
                        },
                        child: const Text('Tambahkan'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.position,
    required this.nowUtc,
    required this.taken,
    required this.selected,
    required this.onTap,
  });

  final RoomStockPosition position;
  final DateTime nowUtc;
  final bool taken;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      key: ConsumptionCandidatePicker.tileKeyFor(position.positionKey),
      selected: selected,
      enabled: !taken,
      onTap: onTap,
      title: Text(position.itemName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            position.isBatched
                ? '${position.sku} · batch ${position.batchNo}'
                : '${position.sku} · tanpa batch',
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConsumptionExpiryBadge(
                expiryDate: position.expiryDate,
                expiryAlertDays: position.expiryAlertDays,
                nowUtc: nowUtc,
              ),
              ConsumptionPill(
                label: position.qtyOnHand.formatWithUnit(position.unit),
                color: theme.colorScheme.primary,
              ),
              if (taken)
                const ConsumptionPill(
                  label: 'Sudah dipilih',
                  color: Colors.blueGrey,
                ),
              if (position.usesHistoricalMaster)
                HistoricalMasterBadge.forDetail(
                  [
                    if (position.itemIsHistorical) 'Barang',
                    if (position.batchIsHistorical) 'Batch',
                  ].join(', '),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
