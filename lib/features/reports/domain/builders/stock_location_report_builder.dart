import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../services/ledger_balance_engine.dart';
import '../services/report_grouping_engine.dart';
import 'report_build_context.dart';

/// *Stok Saat Ini* — what is on each shelf as of one date, derived from the ledger.
///
/// ### The whole point is the word "derived"
///
/// Every quantity here is a fold over `stock_movements` up to the cutoff
/// ([LedgerBalanceEngine.totalsByLocationItemBatch]). `stock_balances` holds the
/// same numbers and is never read, because G-L4 says report figures must come from
/// the ledger: a cached balance is a number nobody can trace to an event, and the
/// entire value of an exported stock report is that somebody can.
///
/// ### `branch_all` keeps its locations apart
///
/// A branch scope covers the Gudang Cabang and every room in it, and the rows stay
/// grouped **per location** (§21). The tempting simplification — one row per item
/// across the branch — would net a distribution: the store went down by ten, the
/// room went up by ten, and the branch total is unchanged. That total is arithmetically
/// correct and operationally useless, because the question a stock report answers is
/// *where is it*, and netting is exactly the operation that destroys the answer.
///
/// ### Minimums, and the one this report does not invent
///
/// Low stock is measured against `min_stock_branch` at a Gudang Cabang and
/// `min_stock_room` at a room. Warehouse Pusat has neither column in this schema, so
/// its rows carry no minimum and are never flagged — making one up (the branch
/// minimum? their sum?) would be the report asserting a threshold the business never
/// set.
abstract final class StockLocationReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'location', label: 'Lokasi', widthFlex: 3),
    ReportColumn(key: 'category', label: 'Kategori', widthFlex: 2),
    ReportColumn(key: 'sku', label: 'SKU', widthFlex: 2),
    ReportColumn(key: 'item', label: 'Barang', widthFlex: 4),
    ReportColumn(key: 'unit', label: 'Satuan', widthFlex: 1),
    ReportColumn(key: 'batch', label: 'Batch', widthFlex: 2),
    ReportColumn(key: 'expiry', label: 'Expiry', widthFlex: 2),
    ReportColumn(key: 'expiryStatus', label: 'Status Expiry', widthFlex: 2),
    ReportColumn(
      key: 'qty',
      label: 'Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'minimum',
      label: 'Minimum',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(key: 'stockStatus', label: 'Status Stok', widthFlex: 2),
  ];

  /// The typed rows, before any rendering.
  ///
  /// Separated from [build] so the ledger arithmetic can be asserted directly in
  /// tests rather than through a table of strings — a test that reads cell text is
  /// a test that passes when the numbers are right *and* when the formatter is
  /// wrong in a compensating way.
  static List<StockLocationReportRow> rows({
    required ReportLedgerSource source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final balances = LedgerBalanceEngine.totalsByLocationItemBatch(
      movements: source.movements,
      locationIds: context.scope.locationIds,
      cutoffExclusiveUtc: context.period.endExclusiveUtc,
    );
    final operationalDate = context.asOfDate;
    final filterItemId = context.filter.itemId;
    final filterCategoryId = context.filter.categoryId;

    final rows = <StockLocationReportRow>[];
    balances.forEach((key, qty) {
      if (filterItemId != null && key.itemId != filterItemId) return;
      final item = master.item(key.itemId);
      if (filterCategoryId != null && item?.categoryId != filterCategoryId) {
        return;
      }
      final batch = master.batch(key.batchId);
      final location = master.location(key.locationId);
      final minimum = _minimumFor(location: location, item: item);

      rows.add(
        StockLocationReportRow(
          locationId: key.locationId,
          locationName: ReportBuilderSupport.locationLabel(
            master,
            key.locationId,
          ),
          itemId: key.itemId,
          batchId: key.batchId,
          qty: qty,
          expiryDate: batch?.expiryDate,
          expiryStatus: ReportBuilderSupport.expiryStatusOf(
            item: item,
            expiryDate: batch?.expiryDate,
            operationalDate: operationalDate,
          ),
          isBelowMinimum: minimum != null && qty < minimum,
          minimum: minimum,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: key.itemId,
            batchId: key.batchId,
            locationId: key.locationId,
          ),
        ),
      );
    });
    return List.unmodifiable(rows);
  }

  /// `min_stock_branch` at a store, `min_stock_room` at a room, nothing at the
  /// warehouse — see the class note.
  static Quantity? _minimumFor({
    required MasterLocation? location,
    required MasterItem? item,
  }) {
    if (location == null || item == null) return null;
    return switch (location.type) {
      StockLocationType.branchStore => Quantity.fromWhole(item.minStockBranch),
      StockLocationType.room => Quantity.fromWhole(item.minStockRoom),
      StockLocationType.warehouse => null,
    };
  }

  static ReportDocument build({
    required ReportLedgerSource source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final typedRows = rows(source: source, context: context);

    final dataRows = <ReportDataRow>[];
    for (final row in typedRows) {
      final item = master.item(row.itemId);
      final category = master.categoryOfItem(row.itemId);
      final unit = item?.unit ?? '';
      dataRows.add(
        ReportDataRow(
          categoryId: category?.id,
          categoryName: category?.name ?? ReportGroup.unresolvedCategoryName,
          // Location first: the report is grouped by category, and within a
          // category the reader is looking for a place before a name.
          sortKey:
              '${row.locationName}|${master.skuLabel(row.itemId)}|'
              '${row.expiryDate?.toIso8601String() ?? ''}|'
              '${row.batchId ?? ''}',
          unit: unit.isEmpty ? null : unit,
          quantity: row.qty,
          isHistorical: row.isHistorical,
          cells: [
            ReportCell(row.locationName),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(master.batchLabel(row.batchId)),
            ReportCell(ReportBuilderSupport.civilDateLabel(row.expiryDate)),
            ReportCell(
              row.expiryStatus.label,
              emphasis: _expiryEmphasis(row.expiryStatus),
            ),
            ReportCell(
              row.qty.format(),
              align: ReportColumnAlign.end,
              emphasis: row.isBelowMinimum
                  ? ReportCellEmphasis.warning
                  : ReportCellEmphasis.none,
            ),
            ReportCell(
              row.minimum?.format() ?? ReportLabels.notApplicable,
              align: ReportColumnAlign.end,
              emphasis: ReportCellEmphasis.muted,
            ),
            ReportCell(
              row.minimum == null
                  ? ReportLabels.notApplicable
                  : (row.isBelowMinimum ? 'Di bawah minimum' : 'Aman'),
              emphasis: row.isBelowMinimum
                  ? ReportCellEmphasis.warning
                  : ReportCellEmphasis.none,
            ),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportBuilderSupport.ledgerSnapshot(
      source.movements.where(
        (movement) =>
            movement.createdAtUtc.isBefore(context.period.endExclusiveUtc),
      ),
    );

    // Reported, never clamped: a negative historical balance means the ledger and
    // the balance cache disagree, which is exactly what a report exists to expose.
    final negative = LedgerBalanceEngine.detectNegativeBalances(
      movements: source.movements,
      locationIds: context.scope.locationIds,
      cutoffExclusiveUtc: context.period.endExclusiveUtc,
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
          title: 'Ringkasan',
          metrics: [
            (label: 'Jumlah posisi stok', value: '${dataRows.length}'),
            (
              label: 'Posisi di bawah minimum',
              value: '${typedRows.where((row) => row.isBelowMinimum).length}',
            ),
            (
              label: 'Batch kedaluwarsa',
              value:
                  '${typedRows.where((row) => row.expiryStatus == ReportExpiryStatus.expired).length}',
            ),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings, [
        for (final warning in negative) warning.message,
      ]),
    );
  }

  static ReportCellEmphasis _expiryEmphasis(ReportExpiryStatus status) =>
      switch (status) {
        ReportExpiryStatus.expired => ReportCellEmphasis.danger,
        ReportExpiryStatus.nearExpiry => ReportCellEmphasis.warning,
        ReportExpiryStatus.safe => ReportCellEmphasis.positive,
        ReportExpiryStatus.notTracked => ReportCellEmphasis.muted,
      };
}
