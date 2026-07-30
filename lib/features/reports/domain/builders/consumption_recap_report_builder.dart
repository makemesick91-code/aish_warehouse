import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../models/report_raw_rows.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../services/ledger_balance_engine.dart';
import '../services/report_filter_policy.dart';
import '../services/report_grouping_engine.dart';
import '../services/report_sync_snapshot_builder.dart';
import 'report_build_context.dart';

/// *Rekap Pemakaian* — what rooms actually used (§29).
///
/// ### There is no patient anywhere in this report
///
/// Not a column, not a filter, not a note field this builder reads. The schema holds
/// none, and this is the report where somebody would most plausibly want one — which
/// is exactly why the absence is stated rather than left to be noticed. A Pemakaian
/// records that a room consumed a quantity of an item; who it was used on is
/// clinical data this application does not hold and this report will not imply.
///
/// ### Ownership again
///
/// A Perawat sees only their own consumptions, scoped in the SQL predicate through
/// [ReportAccessPolicy.requiresOwnDocuments] (§14). A Kepala Cabang sees the whole
/// branch, a Petugas Warehouse every branch, a Super Admin everything.
abstract final class ConsumptionRecapReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'docNumber', label: 'Nomor Pemakaian', widthFlex: 3),
    ReportColumn(key: 'branch', label: 'Branch', widthFlex: 2),
    ReportColumn(key: 'room', label: 'Ruangan', widthFlex: 3),
    ReportColumn(key: 'nurse', label: 'Perawat', widthFlex: 3),
    ReportColumn(key: 'status', label: 'Status', widthFlex: 2),
    ReportColumn(key: 'postedAt', label: 'Posted', widthFlex: 3),
    ReportColumn(key: 'category', label: 'Kategori', widthFlex: 2),
    ReportColumn(key: 'sku', label: 'SKU', widthFlex: 2),
    ReportColumn(key: 'item', label: 'Barang', widthFlex: 4),
    ReportColumn(key: 'unit', label: 'Satuan', widthFlex: 1),
    ReportColumn(key: 'batch', label: 'Batch', widthFlex: 2),
    ReportColumn(key: 'expiry', label: 'Expiry', widthFlex: 2),
    ReportColumn(
      key: 'qty',
      label: 'Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(key: 'note', label: 'Catatan', widthFlex: 4),
  ];

  static List<ConsumptionRecapRow> rows({
    required ReportRecapSource<ConsumptionRecapRawRow> source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final filter = context.filter;
    final posted = LedgerBalanceEngine.totalsByDocumentPosition(
      movements: source.movements,
    );

    final rows = <ConsumptionRecapRow>[];
    for (final raw in source.rows) {
      if (!ReportFilterPolicy.matchesStatus(filter, raw.status)) continue;
      if (!context.period.contains(raw.createdAtUtc)) continue;
      final item = master.item(raw.itemId);
      if (filter.categoryId != null && item?.categoryId != filter.categoryId) {
        continue;
      }
      if (!ReportFilterPolicy.matchesSearch(filter.searchText, [
        raw.docNumber,
        master.itemLabel(raw.itemId),
        master.skuLabel(raw.itemId),
        master.batchLabel(raw.batchId),
        master.userLabel(raw.createdBy),
        master.branchLabel(raw.branchId),
        master.roomLabel(raw.roomId),
      ])) {
        continue;
      }

      final key = LedgerDocumentPositionKey(
        refDocId: raw.consumptionId,
        itemId: raw.itemId ?? '',
        batchId: raw.batchId,
      );
      rows.add(
        ConsumptionRecapRow(
          consumptionId: raw.consumptionId,
          docNumber: raw.docNumber,
          branchId: raw.branchId,
          roomId: raw.roomId,
          status: ConsumptionStatus.fromDbValue(raw.status),
          createdBy: raw.createdBy,
          createdAtUtc: raw.createdAtUtc,
          postedAtUtc: raw.postedAtUtc,
          itemId: raw.itemId,
          batchId: raw.batchId,
          qty: raw.itemId == null
              ? Quantity.zero()
              : (posted[key] ?? Quantity.zero()),
          note: raw.lineNote ?? raw.headerNote,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  static ReportDocument build({
    required ReportRecapSource<ConsumptionRecapRawRow> source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final typedRows = rows(source: source, context: context);

    final dataRows = <ReportDataRow>[];
    for (final row in typedRows) {
      final item = master.item(row.itemId);
      final category = master.categoryOfItem(row.itemId);
      final unit = item?.unit ?? '';
      final expiry = master.batch(row.batchId)?.expiryDate;
      dataRows.add(
        ReportDataRow(
          categoryId: category?.id,
          categoryName: category?.name ?? ReportGroup.unresolvedCategoryName,
          sortKey:
              '${row.docNumber}|${master.skuLabel(row.itemId)}|'
              '${row.batchId ?? ''}',
          unit: unit.isEmpty ? null : unit,
          quantity: row.qty,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: row.itemId,
            batchId: row.batchId,
            userId: row.createdBy,
          ),
          cells: [
            ReportCell(row.docNumber),
            ReportCell(master.branchLabel(row.branchId)),
            ReportCell(master.roomLabel(row.roomId)),
            ReportCell(master.userLabel(row.createdBy)),
            ReportCell(row.status.label),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.postedAtUtc)),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(master.batchLabel(row.batchId)),
            ReportCell(ReportBuilderSupport.civilDateLabel(expiry)),
            ReportCell(row.qty.format(), align: ReportColumnAlign.end),
            ReportCell(row.note ?? ''),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportSyncSnapshotBuilder.buildDeduplicated([
      for (final raw in source.rows)
        (
          id: raw.consumptionId,
          status: raw.syncStatus,
          updatedAtUtc: raw.updatedAtUtc,
        ),
      for (final movement in source.movements)
        (
          id: movement.id,
          status: movement.syncStatus,
          updatedAtUtc: movement.updatedAtUtc,
        ),
    ]);

    return ReportDocument(
      header: context.header(syncSnapshot: snapshot, rowCount: dataRows.length),
      columns: columns,
      groups: groups,
      overallTotals: ReportTotalsEngine.combine(
        groups.map((group) => group.subtotals),
      ),
      sections: [
        ReportSection(
          title: 'Ringkasan Pemakaian',
          metrics: [
            (
              label: 'Jumlah dokumen',
              value:
                  '${typedRows.map((row) => row.consumptionId).toSet().length}',
            ),
            (
              label: 'Ruangan terlibat',
              value: '${typedRows.map((row) => row.roomId).toSet().length}',
            ),
            (label: 'Jumlah baris', value: '${typedRows.length}'),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings),
    );
  }
}
