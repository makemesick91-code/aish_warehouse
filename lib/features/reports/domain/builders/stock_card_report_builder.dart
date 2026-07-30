import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../inventory/presentation/stock_movement_presenter.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../services/ledger_balance_engine.dart';
import '../services/report_grouping_engine.dart';
import 'report_build_context.dart';

/// *Kartu Stok* — every movement of one item at one location, with a running
/// balance.
///
/// ### Exactly one location and exactly one item
///
/// Enforced upstream by [ReportType.requiresExactLocation] and
/// [ReportType.requiresItem], and the reason is arithmetic rather than tidiness: a
/// running balance is a statement about *one shelf*. Two locations folded into one
/// column produce a sequence of numbers that reconciles against neither of them, and
/// two items produce one that reconciles against nothing at all.
///
/// Batches are **not** narrowed, though. An item with three batches on the shelf has
/// one card covering all three, because the card answers *"how much of this item is
/// here"* — G-E2 splits balances per batch, but the card's balance column is the
/// position's, and the batch column says which batch each row moved.
///
/// ### Opening balance is computed, not stored
///
/// `saldo awal` is a fold over every ledger row before the period
/// ([LedgerBalanceEngine.openingBalance]). There is no stored opening figure that
/// G-L4 would let this read, and computing it is what makes the card add up:
/// `opening + Σ deltas = closing`, provably, on every run.
///
/// ### Masuk and Keluar are never both filled, and never both zero
///
/// A row writes its quantity into one column and leaves the other **empty**. A zero
/// there would read as *"nothing moved in"* rather than *"this row is not an
/// inbound"* — on a document an auditor is reconciling, that distinction is the
/// whole column (§22).
///
/// Nothing is hidden: reversals appear as their own rows (G-A1 makes a correction a
/// new movement, not an edit), and a movement whose item or actor was archived keeps
/// its quantity and gets a historical label.
abstract final class StockCardReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'timestamp', label: 'Tanggal/Waktu', widthFlex: 3),
    ReportColumn(key: 'type', label: 'Jenis Movement', widthFlex: 3),
    ReportColumn(key: 'refType', label: 'Referensi', widthFlex: 3),
    ReportColumn(key: 'docNumber', label: 'Nomor Dokumen', widthFlex: 3),
    ReportColumn(key: 'actor', label: 'Actor', widthFlex: 3),
    ReportColumn(key: 'from', label: 'Dari', widthFlex: 3),
    ReportColumn(key: 'to', label: 'Ke', widthFlex: 3),
    ReportColumn(key: 'batch', label: 'Batch', widthFlex: 2),
    ReportColumn(key: 'expiry', label: 'Expiry', widthFlex: 2),
    ReportColumn(
      key: 'in',
      label: 'Masuk',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'out',
      label: 'Keluar',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'balance',
      label: 'Saldo',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(key: 'note', label: 'Catatan', widthFlex: 4),
    ReportColumn(key: 'sync', label: 'Sync', widthFlex: 2),
  ];

  static List<StockCardReportRow> rows({
    required ReportLedgerSource source,
    required ReportBuildContext context,
    required String locationId,
    required String itemId,
    Map<String, String> documentNumbers = const <String, String>{},
    List<LedgerIntegrityWarning>? integrityWarnings,
  }) {
    final master = source.master;
    final opening = LedgerBalanceEngine.openingBalance(
      movements: source.movements,
      locationId: locationId,
      itemId: itemId,
      startUtc: context.period.startUtc,
    );
    final periodMovements = LedgerBalanceEngine.movementsInPeriod(
      movements: source.movements,
      period: context.period,
      locationId: locationId,
      itemId: itemId,
    );
    final balances = LedgerBalanceEngine.runningBalance(
      movements: periodMovements,
      locationId: locationId,
      opening: opening,
      warnings: integrityWarnings,
    );

    return List.unmodifiable([
      for (var index = 0; index < periodMovements.length; index++)
        () {
          final movement = periodMovements[index];
          final delta = movement.signedDeltaFor(locationId);
          return StockCardReportRow(
            movement: movement,
            // Exactly one of the two — see the class note.
            incoming: delta.isPositive ? delta : null,
            outgoing: delta.isNegative ? delta.absolute : null,
            balanceAfter: balances[index],
            documentNumber: documentNumberOf(movement, documentNumbers),
            isHistorical: ReportBuilderSupport.isHistorical(
              master,
              itemId: movement.itemId,
              batchId: movement.batchId,
              userId: movement.actorUserId,
            ),
          );
        }(),
    ]);
  }

  /// The document number a movement points at, resolved historically.
  ///
  /// Three outcomes, and all three are legitimate:
  ///
  /// * a number, when the document is still there — soft-deleted included;
  /// * [StockMovementPresenter.noDocumentLabel], when the movement carries no
  ///   reference at all (a seeded opening balance);
  /// * [StockMovementPresenter.unresolvedDocumentLabel], when the reference names
  ///   a document that is physically gone or a `ref_doc_type` this build does not
  ///   know.
  ///
  /// A **raw UUID is never printed.** The id is an internal identifier; an auditor
  /// reading *"Referensi tidak tersedia"* learns that the trail is broken, which is
  /// more than a hex string tells them. And the row is never dropped: the stock
  /// left the shelf either way, and a card that hid it would not add up (§22).
  static String documentNumberOf(
    ReportLedgerMovement movement,
    Map<String, String> documentNumbers,
  ) {
    if (movement.refDocType == null || movement.refDocId == null) {
      return StockMovementPresenter.noDocumentLabel;
    }
    return documentNumbers[movement.refDocId] ??
        StockMovementPresenter.unresolvedDocumentLabel;
  }

  static ReportDocument build({
    required ReportLedgerSource source,
    required ReportBuildContext context,
    required String locationId,
    required String itemId,
    Map<String, String> documentNumbers = const <String, String>{},
  }) {
    final master = source.master;
    final integrity = <LedgerIntegrityWarning>[];
    final typedRows = rows(
      source: source,
      context: context,
      locationId: locationId,
      itemId: itemId,
      documentNumbers: documentNumbers,
      integrityWarnings: integrity,
    );

    final item = master.item(itemId);
    final category = master.categoryOfItem(itemId);
    final unit = item?.unit ?? '';
    final opening = LedgerBalanceEngine.openingBalance(
      movements: source.movements,
      locationId: locationId,
      itemId: itemId,
      startUtc: context.period.startUtc,
    );
    final closing = typedRows.isEmpty ? opening : typedRows.last.balanceAfter;
    final totalIn = Quantity.sum([
      for (final row in typedRows) row.incoming ?? Quantity.zero(),
    ]);
    final totalOut = Quantity.sum([
      for (final row in typedRows) row.outgoing ?? Quantity.zero(),
    ]);

    final dataRows = <ReportDataRow>[];
    for (var index = 0; index < typedRows.length; index++) {
      final row = typedRows[index];
      final movement = row.movement;
      final batch = master.batch(movement.batchId);
      dataRows.add(
        ReportDataRow(
          categoryId: category?.id,
          categoryName: category?.name ?? ReportGroup.unresolvedCategoryName,
          // Timestamp then movement id — the same tie-break the engine sorts by,
          // so the rendered order is provably the order the balance was folded in.
          sortKey: '${movement.createdAtUtc.toIso8601String()}|${movement.id}',
          unit: unit.isEmpty ? null : unit,
          // Signed: a Kartu Stok's subtotal is the period's *net* movement, which
          // is the only per-unit total that means anything on a card (§32).
          quantity: movement.signedDeltaFor(locationId),
          isHistorical: row.isHistorical,
          cells: [
            ReportCell(
              ReportBuilderSupport.dateTimeLabel(movement.createdAtUtc),
            ),
            ReportCell(StockMovementPresenter.labelOf(movement.movementType)),
            ReportCell(
              StockMovementPresenter.documentLabelOf(movement.refDocType),
            ),
            ReportCell(row.documentNumber),
            ReportCell(master.userLabel(movement.actorUserId)),
            ReportCell(
              ReportBuilderSupport.locationLabel(
                master,
                movement.fromLocationId,
              ),
            ),
            ReportCell(
              ReportBuilderSupport.locationLabel(master, movement.toLocationId),
            ),
            ReportCell(master.batchLabel(movement.batchId)),
            ReportCell(ReportBuilderSupport.civilDateLabel(batch?.expiryDate)),
            ReportCell(
              row.incoming?.format() ?? '',
              align: ReportColumnAlign.end,
              emphasis: ReportCellEmphasis.positive,
            ),
            ReportCell(
              row.outgoing?.format() ?? '',
              align: ReportColumnAlign.end,
              emphasis: ReportCellEmphasis.danger,
            ),
            ReportCell(
              row.balanceAfter.format(),
              align: ReportColumnAlign.end,
              emphasis: row.balanceAfter.isNegative
                  ? ReportCellEmphasis.danger
                  : ReportCellEmphasis.none,
            ),
            ReportCell(movement.note ?? ''),
            ReportCell(
              _syncLabel(movement.syncStatus),
              emphasis: movement.syncStatus == SyncStatus.synced
                  ? ReportCellEmphasis.muted
                  : ReportCellEmphasis.warning,
            ),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportBuilderSupport.ledgerSnapshot(
      typedRows.map((row) => row.movement),
    );

    return ReportDocument(
      header: context.header(syncSnapshot: snapshot, rowCount: dataRows.length),
      columns: columns,
      groups: groups,
      overallTotals: ReportTotalsEngine.combine(
        groups.map((group) => group.subtotals),
      ),
      sections: [
        ReportSection(
          title: 'Ringkasan Kartu Stok',
          metrics: [
            (label: 'Saldo awal', value: opening.formatWithUnit(unit)),
            (label: 'Total masuk', value: totalIn.formatWithUnit(unit)),
            (label: 'Total keluar', value: totalOut.formatWithUnit(unit)),
            (label: 'Saldo akhir', value: closing.formatWithUnit(unit)),
            (label: 'Jumlah mutasi', value: '${typedRows.length}'),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings, [
        for (final warning in integrity) warning.message,
      ]),
    );
  }

  static String _syncLabel(SyncStatus status) => switch (status) {
    SyncStatus.synced => 'Tersinkron',
    SyncStatus.pending => 'Pending',
    SyncStatus.conflict => 'Konflik',
  };
}
