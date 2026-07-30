import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../../../core/widgets/status_card.dart';
import '../../domain/models/disposal_models.dart';
import '../providers/disposal_providers.dart';
import 'disposal_badges.dart';

/// What the picker hands back: one expired position and how much of it to destroy.
class DisposalCandidateChoice {
  const DisposalCandidateChoice({required this.position, required this.qty});

  final ExpiredStockPosition position;
  final Quantity qty;
}

/// Chooses one expired position to add to a draft (§30).
///
/// Everything it can offer is already expired: it reads
/// [disposalCandidateSearchResultsProvider], which applies `DisposalExpiryPolicy`
/// inside the repository, so there is no code path here that could surface a
/// near-expiry or in-date batch — not a greyed-out row, not a disabled tile, not a
/// checkbox that overrides anything. §28 asks for that directly, and the absence of
/// a control is a stronger guarantee than a disabled one.
///
/// The quantity defaults to the whole position, because destroying all of an expired
/// batch is the ordinary case rather than the edge one. A smaller number is accepted
/// — partial disposal is legitimate (§9) — and a larger one is refused by the field
/// and again by the use case.
///
/// Search runs against the local database with a short debounce, so the clinic keeps
/// searching offline (G-Y1) without a query per keystroke. The result set is capped
/// at eight rows by the repository.
class DisposalCandidatePicker extends ConsumerStatefulWidget {
  const DisposalCandidatePicker({super.key, required this.alreadyChosen});

  /// `item|batch` keys already on the document. Shown as taken rather than hidden,
  /// so a user looking for a batch they have already added finds it and understands
  /// why it cannot be added twice.
  final Set<String> alreadyChosen;

  static const Key sheetKey = ValueKey('disposalCandidatePicker');
  static const Key searchKey = ValueKey('disposalCandidatePickerSearch');
  static const Key emptyKey = ValueKey('disposalCandidatePickerEmpty');
  static const Key listKey = ValueKey('disposalCandidatePickerList');
  static const Key qtyKey = ValueKey('disposalCandidatePickerQty');
  static const Key addKey = ValueKey('disposalCandidatePickerAdd');

  static Key tileKeyFor(String positionKey) =>
      ValueKey('disposalCandidateTile-$positionKey');

  /// Debounce window for the search field. Long enough to skip the keystrokes of a
  /// word, short enough that the list feels live.
  static const Duration searchDebounce = Duration(milliseconds: 200);

  @override
  ConsumerState<DisposalCandidatePicker> createState() =>
      _DisposalCandidatePickerState();
}

class _DisposalCandidatePickerState
    extends ConsumerState<DisposalCandidatePicker> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _qty = TextEditingController();
  Timer? _debounce;
  ExpiredStockPosition? _selected;

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
      DisposalCandidatePicker.searchDebounce,
      () => ref.read(disposalCandidateSearchProvider.notifier).update(value),
    );
  }

  void _select(ExpiredStockPosition position) {
    setState(() {
      _selected = position;
      // The whole position by default — the ordinary case for expired stock.
      _qty.text = position.qtyOnHand.format();
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(disposalCandidateSearchResultsProvider);
    final nowUtc = ref.watch(disposalClockProvider)();
    final selected = _selected;

    return SafeArea(
      key: DisposalCandidatePicker.sheetKey,
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
                key: DisposalCandidatePicker.searchKey,
                controller: _search,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  labelText: 'Cari barang, SKU atau batch kedaluwarsa',
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
                      child: DisposalNotice(
                        key: DisposalCandidatePicker.emptyKey,
                        title: 'Tidak ada stok kedaluwarsa',
                        message:
                            'Tidak ada batch yang sudah melewati tanggal '
                            'kedaluwarsa di lokasi ini. Barang yang segera '
                            'kedaluwarsa belum dapat dimusnahkan.',
                        icon: Icons.inventory_2_outlined,
                      ),
                    );
                  }
                  return ListView.builder(
                    key: DisposalCandidatePicker.listKey,
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final position = rows[index];
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
                      '${selected.itemName} · batch ${selected.batchNo}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    QuantityField(
                      key: DisposalCandidatePicker.qtyKey,
                      controller: _qty,
                      label: 'Jumlah dimusnahkan',
                      unit: selected.unit,
                      helperText:
                          'Tersedia ${selected.qtyOnHand.formatWithUnit(selected.unit)}',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: DisposalCandidatePicker.addKey,
                        onPressed: () {
                          final qty = Quantity.tryParse(_qty.text);
                          // Refused here as well as in the use case, so a bad number
                          // never closes the sheet and loses the user's selection.
                          if (qty == null || !qty.isPositive) return;
                          Navigator.of(context).pop(
                            DisposalCandidateChoice(
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

  final ExpiredStockPosition position;
  final DateTime nowUtc;
  final bool taken;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      key: DisposalCandidatePicker.tileKeyFor(position.positionKey),
      selected: selected,
      enabled: !taken,
      onTap: onTap,
      title: Text(position.itemName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${position.sku} · batch ${position.batchNo}'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DisposalExpiryBadge(
                expiryDate: position.expiryDate,
                // Every row here is already expired, so the alert threshold cannot
                // change the verdict.
                expiryAlertDays: 0,
                nowUtc: nowUtc,
              ),
              DisposalPill(
                label: position.qtyOnHand.formatWithUnit(position.unit),
                color: theme.colorScheme.primary,
              ),
              if (taken)
                const DisposalPill(
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
