import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../services/ledger_balance_engine.dart';
import '../services/report_grouping_engine.dart';
import 'report_build_context.dart';

/// *Laporan Kedaluwarsa* — every batch still on a shelf, nearest expiry first
/// (G-E8).
///
/// > *"Laporan Kadaluarsa (per lokasi, diurutkan ED terdekat, kolom: barang, batch,
/// > ED, sisa hari, qty) tersedia di modul Laporan dan bisa diunduh Excel/PDF."*
///
/// ### It is not the Pemusnahan candidate list
///
/// The obvious shortcut is to reuse the query that finds destroyable stock. It
/// answers a narrower question: that one returns **expired** batches, and this
/// report exists to show *Aman* and *Segera kedaluwarsa* alongside them. A branch
/// head reading it is deciding what to use first, not what to throw away — and a
/// list that only appeared once stock had already expired would arrive too late to
/// be worth printing (§23).
///
/// ### Quantities come from the ledger, like every other stock figure
///
/// [LedgerBalanceEngine.totalsByLocationItemBatch] as of the cutoff (G-L4). A batch
/// whose balance has reached zero drops out — it is not on the shelf — and an
/// **archived** batch whose balance has not stays in, because the stock is still
/// physically there and hiding it is how it gets used by mistake.
///
/// ### What is excluded, and why each exclusion is narrow
///
/// * Items with `has_expiry = false`. They have no expiry date, so every column
///   this report is named for would be blank.
/// * Positions with no batch. G-E1 makes a batch mandatory for goods with expiry,
///   so a batchless position of such an item is corrupt data rather than a row —
///   and it is reported through the source's integrity warnings rather than printed
///   as a line with an empty date.
/// * Non-positive balances, as above.
///
/// Expired batches are emphatically **not** excluded: they are the rows that matter
/// most.
abstract final class ExpiryReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'location', label: 'Lokasi', widthFlex: 3),
    ReportColumn(key: 'category', label: 'Kategori', widthFlex: 2),
    ReportColumn(key: 'sku', label: 'SKU', widthFlex: 2),
    ReportColumn(key: 'item', label: 'Barang', widthFlex: 4),
    ReportColumn(key: 'unit', label: 'Satuan', widthFlex: 1),
    ReportColumn(key: 'batch', label: 'Batch', widthFlex: 2),
    ReportColumn(key: 'expiry', label: 'Expiry Date', widthFlex: 2),
    ReportColumn(
      key: 'days',
      label: 'Sisa Hari',
      align: ReportColumnAlign.end,
      widthFlex: 2,
    ),
    ReportColumn(key: 'status', label: 'Status', widthFlex: 2),
    ReportColumn(
      key: 'qty',
      label: 'Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
  ];

  static List<ExpiryReportRow> rows({
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
    final filterCategoryId = context.filter.categoryId;
    final filterItemId = context.filter.itemId;

    final rows = <ExpiryReportRow>[];
    balances.forEach((key, qty) {
      if (key.batchId == null) return;
      if (filterItemId != null && key.itemId != filterItemId) return;
      final item = master.item(key.itemId);
      // A missing item cannot be shown to track expiry, so it cannot be shown on
      // this report — the position still appears on Stok Saat Ini, which is where
      // an unlabelled quantity belongs.
      if (item == null || !item.hasExpiry) return;
      if (filterCategoryId != null && item.categoryId != filterCategoryId) {
        return;
      }
      final batch = master.batch(key.batchId);
      if (batch == null) return;

      rows.add(
        ExpiryReportRow(
          locationId: key.locationId,
          locationName: ReportBuilderSupport.locationLabel(
            master,
            key.locationId,
          ),
          itemId: key.itemId,
          batchId: key.batchId,
          batchNo: batch.batchNo,
          expiryDate: batch.expiryDate,
          daysRemaining: ReportBuilderSupport.daysRemaining(
            operationalDate: operationalDate,
            expiryDate: batch.expiryDate,
          ),
          status: ReportBuilderSupport.expiryStatusOf(
            item: item,
            expiryDate: batch.expiryDate,
            operationalDate: operationalDate,
          ),
          qty: qty,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            locationId: key.locationId,
          ),
        ),
      );
    });

    // G-E8's ordering: nearest expiry first, then location, item and batch so two
    // runs of the same report cannot disagree.
    rows.sort((a, b) {
      final byExpiry = a.expiryDate.compareTo(b.expiryDate);
      if (byExpiry != 0) return byExpiry;
      final byLocation = a.locationName.toLowerCase().compareTo(
        b.locationName.toLowerCase(),
      );
      if (byLocation != 0) return byLocation;
      final byItem = master
          .itemLabel(a.itemId)
          .toLowerCase()
          .compareTo(master.itemLabel(b.itemId).toLowerCase());
      if (byItem != 0) return byItem;
      return a.batchNo.compareTo(b.batchNo);
    });
    return List.unmodifiable(rows);
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
          // Expiry first inside a category — the whole report is "what expires
          // next", and the group heading must not reorder that.
          sortKey:
              '${row.expiryDate.toIso8601String()}|${row.locationName}|'
              '${master.itemLabel(row.itemId)}|${row.batchNo}',
          unit: unit.isEmpty ? null : unit,
          quantity: row.qty,
          isHistorical: row.isHistorical,
          cells: [
            ReportCell(row.locationName),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(row.batchNo),
            ReportCell(ReportBuilderSupport.civilDateLabel(row.expiryDate)),
            ReportCell(
              '${row.daysRemaining}',
              align: ReportColumnAlign.end,
              emphasis: _emphasis(row.status),
            ),
            ReportCell(row.status.label, emphasis: _emphasis(row.status)),
            ReportCell(
              row.qty.format(),
              align: ReportColumnAlign.end,
              emphasis: _emphasis(row.status),
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

    int countOf(ReportExpiryStatus status) =>
        typedRows.where((row) => row.status == status).length;

    return ReportDocument(
      header: context.header(syncSnapshot: snapshot, rowCount: dataRows.length),
      columns: columns,
      groups: groups,
      overallTotals: ReportTotalsEngine.combine(
        groups.map((group) => group.subtotals),
      ),
      sections: [
        ReportSection(
          title: 'Ringkasan Kedaluwarsa',
          metrics: [
            (
              label: ReportExpiryStatus.expired.label,
              value: '${countOf(ReportExpiryStatus.expired)}',
            ),
            (
              label: ReportExpiryStatus.nearExpiry.label,
              value: '${countOf(ReportExpiryStatus.nearExpiry)}',
            ),
            (
              label: ReportExpiryStatus.safe.label,
              value: '${countOf(ReportExpiryStatus.safe)}',
            ),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings),
    );
  }

  static ReportCellEmphasis _emphasis(ReportExpiryStatus status) =>
      switch (status) {
        ReportExpiryStatus.expired => ReportCellEmphasis.danger,
        ReportExpiryStatus.nearExpiry => ReportCellEmphasis.warning,
        ReportExpiryStatus.safe => ReportCellEmphasis.positive,
        ReportExpiryStatus.notTracked => ReportCellEmphasis.muted,
      };
}
