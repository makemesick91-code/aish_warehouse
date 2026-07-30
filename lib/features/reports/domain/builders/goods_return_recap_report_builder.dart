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

/// *Rekap Retur* — rejected goods on their way back to the Warehouse (§31).
///
/// ### Two quantities, and the gap between them is the report
///
/// `Qty Dokumen` is the immutable snapshot on the return line — what is in the box.
/// `Qty Diterima` is the `return` movement that credited Warehouse Pusat — what is
/// on the shelf. They differ for exactly as long as the goods are in transit, and
/// that gap is the thing a Petugas Warehouse reads this report to see: a `shipped`
/// return shows a quantity in the box and zero on the shelf, which is the honest
/// description of a carton somewhere on a road.
///
/// A `draft` return shows zero received too, for the same reason.
///
/// ### An expired batch belongs here
///
/// Every outbound document in this schema refuses expired stock (G-E4). This one
/// does the opposite: G-E5 makes *"kedaluwarsa"* a reason to reject, so an expired
/// batch is one of the most ordinary things on a return, and it is printed without
/// comment.
abstract final class GoodsReturnRecapReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'docNumber', label: 'Nomor Retur', widthFlex: 3),
    ReportColumn(key: 'grNumber', label: 'Nomor GR', widthFlex: 3),
    ReportColumn(key: 'doNumber', label: 'Nomor DO/SJ', widthFlex: 3),
    ReportColumn(key: 'prNumber', label: 'Nomor PR', widthFlex: 3),
    ReportColumn(key: 'branch', label: 'Branch', widthFlex: 2),
    ReportColumn(key: 'status', label: 'Status', widthFlex: 2),
    ReportColumn(key: 'createdBy', label: 'Created By', widthFlex: 3),
    ReportColumn(key: 'shippedBy', label: 'Shipped By', widthFlex: 3),
    ReportColumn(key: 'receivedBy', label: 'Received By', widthFlex: 3),
    ReportColumn(key: 'shippedAt', label: 'Dikirim', widthFlex: 3),
    ReportColumn(key: 'receivedAt', label: 'Diterima', widthFlex: 3),
    ReportColumn(key: 'category', label: 'Kategori', widthFlex: 2),
    ReportColumn(key: 'sku', label: 'SKU', widthFlex: 2),
    ReportColumn(key: 'item', label: 'Barang', widthFlex: 4),
    ReportColumn(key: 'unit', label: 'Satuan', widthFlex: 1),
    ReportColumn(key: 'batch', label: 'Batch', widthFlex: 2),
    ReportColumn(key: 'expiry', label: 'Expiry', widthFlex: 2),
    ReportColumn(
      key: 'documentQty',
      label: 'Qty Dokumen',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'receivedQty',
      label: 'Qty Diterima',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(key: 'rejectReason', label: 'Reject Reason', widthFlex: 3),
    ReportColumn(key: 'branchNote', label: 'Branch Note', widthFlex: 3),
    ReportColumn(key: 'warehouseNote', label: 'Warehouse Note', widthFlex: 3),
  ];

  static List<GoodsReturnRecapRow> rows({
    required ReportRecapSource<GoodsReturnRecapRawRow> source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final filter = context.filter;
    final received = LedgerBalanceEngine.totalsByDocumentPosition(
      movements: source.movements,
    );

    final rows = <GoodsReturnRecapRow>[];
    for (final raw in source.rows) {
      if (!ReportFilterPolicy.matchesStatus(filter, raw.status)) continue;
      if (!context.period.contains(raw.createdAtUtc)) continue;
      final item = master.item(raw.itemId);
      if (filter.categoryId != null && item?.categoryId != filter.categoryId) {
        continue;
      }
      if (!ReportFilterPolicy.matchesSearch(filter.searchText, [
        raw.docNumber,
        raw.grDocNumber,
        raw.doDocNumber,
        raw.prDocNumber,
        raw.rejectReasonSnapshot,
        master.itemLabel(raw.itemId),
        master.skuLabel(raw.itemId),
        master.batchLabel(raw.batchId),
        master.userLabel(raw.createdBy),
        master.branchLabel(raw.branchId),
      ])) {
        continue;
      }

      final key = LedgerDocumentPositionKey(
        refDocId: raw.goodsReturnId,
        itemId: raw.itemId ?? '',
        batchId: raw.batchId,
      );
      rows.add(
        GoodsReturnRecapRow(
          goodsReturnId: raw.goodsReturnId,
          docNumber: raw.docNumber,
          grDocNumber: raw.grDocNumber,
          doDocNumber: raw.doDocNumber,
          prDocNumber: raw.prDocNumber,
          branchId: raw.branchId,
          status: GoodsReturnStatus.fromDbValue(raw.status),
          createdBy: raw.createdBy,
          shippedBy: raw.shippedBy,
          receivedBy: raw.receivedBy,
          createdAtUtc: raw.createdAtUtc,
          shippedAtUtc: raw.shippedAtUtc,
          receivedAtUtc: raw.receivedAtUtc,
          itemId: raw.itemId,
          batchId: raw.batchId,
          documentQty: Quantity.fromMilliUnits(raw.qtyMilliUnits ?? 0),
          receivedQty: raw.itemId == null
              ? Quantity.zero()
              : (received[key] ?? Quantity.zero()),
          rejectReason: raw.rejectReasonSnapshot ?? ReportLabels.notApplicable,
          branchNote: raw.branchNote,
          warehouseNote: raw.warehouseNote,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  static ReportDocument build({
    required ReportRecapSource<GoodsReturnRecapRawRow> source,
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
          // The stock effect: what the Warehouse actually took back onto its shelf.
          quantity: row.receivedQty,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: row.itemId,
            batchId: row.batchId,
            userId: row.createdBy,
          ),
          cells: [
            ReportCell(row.docNumber),
            ReportCell(row.grDocNumber),
            ReportCell(row.doDocNumber),
            ReportCell(row.prDocNumber),
            ReportCell(master.branchLabel(row.branchId)),
            ReportCell(row.status.label),
            ReportCell(master.userLabel(row.createdBy)),
            ReportCell(master.userLabel(row.shippedBy)),
            ReportCell(master.userLabel(row.receivedBy)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.shippedAtUtc)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.receivedAtUtc)),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(master.batchLabel(row.batchId)),
            ReportCell(ReportBuilderSupport.civilDateLabel(expiry)),
            ReportCell(row.documentQty.format(), align: ReportColumnAlign.end),
            ReportCell(
              row.receivedQty.format(),
              align: ReportColumnAlign.end,
              emphasis: row.receivedQty.isZero
                  ? ReportCellEmphasis.warning
                  : ReportCellEmphasis.positive,
            ),
            ReportCell(row.rejectReason),
            ReportCell(row.branchNote ?? ''),
            ReportCell(row.warehouseNote ?? ''),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportSyncSnapshotBuilder.buildDeduplicated([
      for (final raw in source.rows)
        (
          id: raw.goodsReturnId,
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
          title: 'Ringkasan Retur',
          metrics: [
            (
              label: 'Jumlah dokumen',
              value:
                  '${typedRows.map((row) => row.goodsReturnId).toSet().length}',
            ),
            (
              label: 'Baris belum diterima',
              value:
                  '${typedRows.where((row) => row.receivedQty.isZero).length}',
            ),
            (label: 'Jumlah baris', value: '${typedRows.length}'),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings),
    );
  }
}
