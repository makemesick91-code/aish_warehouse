import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../models/stock_card_entry.dart';
import '../stock_movement_presenter.dart';

/// The **kartu stok** renderer: a ledger movement list, feature-agnostic (§2).
///
/// Before this existed, every document rendered its own movements from inside its own
/// screens and nothing ever showed a *mixed* history. This widget is the surface the
/// acceptance criterion asks for — it renders whatever touched a position, whichever
/// document wrote it — and it is deliberately generic: it knows nothing about Pemakaian,
/// Distribusi or Pemusnahan beyond what [StockMovementPresenter] tells it, so a new
/// movement type appears here the moment the presenter words it.
///
/// ### What it never does
///
/// * **Filter.** A stock card that dropped rows would not add up. It renders every entry it
///   is handed, including ones whose item, batch, actor or document can no longer be
///   resolved — those get a safe label, never a missing row (§6).
/// * **Show milli-units.** Quantities go through [Quantity.formatWithUnit], so `2500`
///   milli-units read as `2.5 ampul` (Q-4).
/// * **Call `toLocal()`.** Timestamps go through [AppDateTimeFormatter.dateTimeWithZone],
///   which converts through `AppTimeZone` and prints the GMT+8 label explicitly (T-4).
/// * **Navigate.** See [documentReferenceIsReadOnly].
class StockCardList extends StatelessWidget {
  const StockCardList({
    super.key,
    required this.entries,
    this.locationId,
    this.emptyMessage,
  });

  /// The rows to render, in any order — the widget sorts them itself so the sequence is
  /// chronological on instants rather than on ISO-8601 spelling (see
  /// [compareStockCardEntries]).
  final List<StockCardEntry> entries;

  /// The location the card is being read *from*, when it has one.
  ///
  /// Supplies the `+`/`−` sign beside each quantity. `null` on a card that spans locations —
  /// a document's own movements, say — where a sign would have no fixed meaning.
  final String? locationId;

  final String? emptyMessage;

  /// A stock card shows a document **number**, not a link.
  ///
  /// §5 asks for one or the other, not an invention: the existing movement reference was
  /// never tappable anywhere in this application, so nothing is made tappable here. The
  /// number is the audit fact a reader needs, and the screens that own each document already
  /// reach it through their own scoped routes.
  ///
  /// It is also the safer half of the choice. A tappable reference on a *mixed* card would
  /// have to decide, per row, whether the reader is scoped to that document — a nurse
  /// looking at a room's history sees Distribusi rows belonging to their branch head — and a
  /// link that resolved for some rows and not others would turn the card into a way to probe
  /// which document ids are real. Rendering the number the caller could resolve, and
  /// [StockMovementPresenter.unresolvedDocumentLabel] where it could not, leaks nothing.
  static const bool documentReferenceIsReadOnly = true;

  static const Key listKey = ValueKey('stockCardList');
  static const Key emptyKey = ValueKey('stockCardEmpty');

  static Key rowKeyFor(String movementId) =>
      ValueKey('stockCardRow-$movementId');

  static Key typeKeyFor(String movementId) =>
      ValueKey('stockCardType-$movementId');

  static Key documentKeyFor(String movementId) =>
      ValueKey('stockCardDocument-$movementId');

  static Key qtyKeyFor(String movementId) =>
      ValueKey('stockCardQty-$movementId');

  static Key actorKeyFor(String movementId) =>
      ValueKey('stockCardActor-$movementId');

  static Key timestampKeyFor(String movementId) =>
      ValueKey('stockCardTime-$movementId');

  static Key batchKeyFor(String movementId) =>
      ValueKey('stockCardBatch-$movementId');

  static Key noteKeyFor(String movementId) =>
      ValueKey('stockCardNote-$movementId');

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        key: emptyKey,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          emptyMessage ?? 'Belum ada pergerakan stok untuk posisi ini.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final ordered = [...entries]..sort(compareStockCardEntries);

    return Column(
      key: listKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: StockCardRow(entry: entry, locationId: locationId),
          ),
      ],
    );
  }
}

/// One movement, as a stock-card row.
///
/// Laid out so it survives a narrow screen: the type label and the quantity share a `Row`
/// with the label in an `Expanded` and the quantity in a fixed-width column, and every
/// secondary fact goes on its own line or into a `Wrap`. Nothing here is a fixed-height box,
/// because Indonesian labels and Material 3 text scaling both grow.
class StockCardRow extends StatelessWidget {
  const StockCardRow({super.key, required this.entry, this.locationId});

  final StockCardEntry entry;
  final String? locationId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = StockMovementPresenter.colorOf(entry.type);
    final sign = StockMovementPresenter.signFor(
      locationId: locationId,
      fromLocationId: entry.movement.fromLocationId,
      toLocationId: entry.movement.toLocationId,
    );
    final unit = entry.unit;
    final qtyText = unit == null
        ? entry.qty.format()
        : entry.qty.formatWithUnit(unit);

    return Card(
      key: StockCardList.rowKeyFor(entry.id),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  StockMovementPresenter.iconOf(entry.type),
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    key: StockCardList.typeKeyFor(entry.id),
                    StockMovementPresenter.labelOf(entry.type),
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  key: StockCardList.qtyKeyFor(entry.id),
                  sign == null ? qtyText : '$sign$qtyText',
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              entry.itemName == null
                  ? StockMovementPresenter.unresolvedMasterLabel
                  : '${entry.sku ?? '—'} · ${entry.itemName}',
              style: theme.textTheme.bodySmall,
            ),
            // Batch and expiry only when the movement actually carries a batch. An item
            // without expiry renders neither, rather than an empty "batch —" line that would
            // read as missing data (G-E2).
            if (entry.isBatched)
              Text(
                key: StockCardList.batchKeyFor(entry.id),
                [
                  'Batch ${entry.batchNo ?? StockMovementPresenter.unresolvedMasterLabel}',
                  if (entry.expiryDate != null)
                    'ED ${AppDateTimeFormatter.civilDate(entry.expiryDate!)}',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(_locationLine(), style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              key: StockCardList.timestampKeyFor(entry.id),
              // Through the formatter, which converts via `AppTimeZone` and never calls
              // `toLocal()` (T-4).
              AppDateTimeFormatter.dateTimeWithZone(entry.createdAt),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              key: StockCardList.actorKeyFor(entry.id),
              'Oleh ${entry.actorName ?? StockMovementPresenter.unresolvedMasterLabel}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            // Read-only, never a link — see `StockCardList.documentReferenceIsReadOnly`.
            Text(
              key: StockCardList.documentKeyFor(entry.id),
              _documentLine(),
              style: theme.textTheme.bodySmall,
            ),
            if (entry.hasNote) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                key: StockCardList.noteKeyFor(entry.id),
                entry.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (entry.usesHistoricalMaster) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  HistoricalMasterBadge.forDetail(
                    [
                      if (entry.itemIsHistorical) 'Barang',
                      if (entry.batchIsHistorical) 'Batch',
                      if (entry.actorIsHistorical) 'Pelaku',
                    ].join(', '),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// `Dari Ruang Dental 1 · Ke —` — both halves, so an outbound movement visibly has no
  /// destination rather than simply omitting it (§2.2/§19).
  String _locationLine() {
    final direction = StockMovementPresenter.directionLabelOf(
      fromLocationId: entry.movement.fromLocationId,
      toLocationId: entry.movement.toLocationId,
    );
    final from = entry.movement.fromLocationId == null
        ? '—'
        : entry.fromLocationName ??
              StockMovementPresenter.unresolvedMasterLabel;
    final to = entry.movement.toLocationId == null
        ? '—'
        : entry.toLocationName ?? StockMovementPresenter.unresolvedMasterLabel;
    return '$direction · Dari $from · Ke $to';
  }

  /// `dokumen Pemakaian · TMP-CNS-…`, or the safe label when the number is out of scope or
  /// the row is gone.
  String _documentLine() {
    final label = StockMovementPresenter.documentLabelOf(entry.refDocType);
    if (entry.refDocType == null) return label;
    final number = entry.hasDocumentNumber
        ? entry.documentNumber!
        : StockMovementPresenter.unresolvedDocumentLabel;
    return '$label · $number';
  }
}
