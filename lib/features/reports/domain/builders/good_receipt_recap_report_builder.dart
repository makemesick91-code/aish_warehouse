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

/// *Rekap Penerimaan dan Selisih GR* — what arrived, what did not, and what went
/// back (§27).
///
/// ### Shortage and rejection are different things, and the report says so
///
/// This is the distinction the whole report exists for, and conflating them is the
/// easy mistake:
///
/// * **Shortage** — a `checked` line whose `received_qty` is less than
///   `shipped_qty`. Goods that were listed on the shipment and *never arrived*
///   (G-G3). There is nothing to send back, because nothing is there. It is a
///   delivery discrepancy the Warehouse investigates.
/// * **Rejected** — a line refused whole, with a mandatory reason (G-G4). The goods
///   *are* in the branch, they were never credited to its stock (G-G5), and they go
///   home through a Retur.
///
/// A report that added them into one "selisih" column would tell a Warehouse user
/// that a carton is coming back when it never left the depot.
///
/// ### Accepted comes from the ledger, received from the document
///
/// `Received Qty` is what the branch head keyed in. `Accepted Ledger Qty` is the
/// `good_receipt` movement that actually credited the Gudang Cabang. On a posted
/// receipt with a `checked` line they agree; on a `checking` one the ledger column is
/// zero, because nothing has been credited yet. Printing both is what makes the
/// document auditable against the balance it produced.
abstract final class GoodReceiptRecapReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'docNumber', label: 'Nomor GR', widthFlex: 3),
    ReportColumn(key: 'doNumber', label: 'Nomor DO/SJ', widthFlex: 3),
    ReportColumn(key: 'prNumber', label: 'Nomor PR', widthFlex: 3),
    ReportColumn(key: 'branch', label: 'Branch', widthFlex: 2),
    ReportColumn(key: 'status', label: 'Status', widthFlex: 2),
    ReportColumn(key: 'receivedBy', label: 'Diperiksa Oleh', widthFlex: 3),
    ReportColumn(key: 'postedAt', label: 'Posted', widthFlex: 3),
    ReportColumn(key: 'category', label: 'Kategori', widthFlex: 2),
    ReportColumn(key: 'sku', label: 'SKU', widthFlex: 2),
    ReportColumn(key: 'item', label: 'Barang', widthFlex: 4),
    ReportColumn(key: 'unit', label: 'Satuan', widthFlex: 1),
    ReportColumn(key: 'batch', label: 'Batch', widthFlex: 2),
    ReportColumn(key: 'expiry', label: 'Expiry', widthFlex: 2),
    ReportColumn(
      key: 'shipped',
      label: 'Shipped Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'received',
      label: 'Received Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'accepted',
      label: 'Accepted Ledger Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'shortage',
      label: 'Shortage Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'rejected',
      label: 'Rejected Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(key: 'discrepancy', label: 'Discrepancy', widthFlex: 2),
    ReportColumn(key: 'rejectReason', label: 'Reject Reason', widthFlex: 3),
    ReportColumn(key: 'returnStatus', label: 'Return Status', widthFlex: 2),
  ];

  static List<GoodReceiptRecapRow> rows({
    required ReportRecapSource<GoodReceiptRecapRawRow> source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final filter = context.filter;
    final accepted = LedgerBalanceEngine.totalsByDocumentPosition(
      movements: source.movements,
    );

    final rows = <GoodReceiptRecapRow>[];
    for (final raw in source.rows) {
      if (!ReportFilterPolicy.matchesStatus(filter, raw.status)) continue;
      if (!context.period.contains(raw.createdAtUtc)) continue;
      final item = master.item(raw.itemId);
      if (filter.categoryId != null && item?.categoryId != filter.categoryId) {
        continue;
      }
      if (!ReportFilterPolicy.matchesSearch(filter.searchText, [
        raw.docNumber,
        raw.doDocNumber,
        raw.prDocNumber,
        master.itemLabel(raw.itemId),
        master.skuLabel(raw.itemId),
        master.batchLabel(raw.batchId),
        master.userLabel(raw.receivedBy),
        master.branchLabel(raw.branchId),
      ])) {
        continue;
      }

      final shipped = Quantity.fromMilliUnits(raw.shippedQtyMilliUnits ?? 0);
      final received = Quantity.fromMilliUnits(raw.receivedQtyMilliUnits ?? 0);
      final key = LedgerDocumentPositionKey(
        refDocId: raw.grId,
        itemId: raw.itemId ?? '',
        batchId: raw.batchId,
      );
      final acceptedQty = raw.itemId == null
          ? Quantity.zero()
          : (accepted[key] ?? Quantity.zero());
      final isRejected =
          raw.lineStatus == GoodReceiptLineStatus.rejected.dbValue;
      final isChecked = raw.lineStatus == GoodReceiptLineStatus.checked.dbValue;

      // Shortage only on a *checked* line. A rejected line received nothing by
      // definition, and calling its whole quantity a shortage would double-count it
      // against the rejection column.
      final shortage = isChecked
          ? Quantity.max(Quantity.zero(), shipped - received)
          : Quantity.zero();
      final rejected = isRejected ? shipped : Quantity.zero();

      final discrepancy = rejected.isPositive
          ? GoodReceiptDiscrepancyFilter.rejected
          : (shortage.isPositive
                ? GoodReceiptDiscrepancyFilter.shortage
                : GoodReceiptDiscrepancyFilter.none);
      if (filter.discrepancy != GoodReceiptDiscrepancyFilter.all &&
          filter.discrepancy != discrepancy) {
        continue;
      }

      rows.add(
        GoodReceiptRecapRow(
          grId: raw.grId,
          docNumber: raw.docNumber,
          doDocNumber: raw.doDocNumber,
          prDocNumber: raw.prDocNumber,
          branchId: raw.branchId,
          status: GoodReceiptStatus.fromDbValue(raw.status),
          receivedBy: raw.receivedBy,
          createdAtUtc: raw.createdAtUtc,
          postedAtUtc: raw.postedAtUtc,
          itemId: raw.itemId,
          batchId: raw.batchId,
          shippedQty: shipped,
          receivedQty: received,
          acceptedQty: acceptedQty,
          shortageQty: shortage,
          rejectedQty: rejected,
          discrepancy: discrepancy,
          rejectReason: raw.rejectReason,
          returnStatusLabel: _returnStatusLabel(raw),
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  /// What happened to the goods this receipt refused.
  ///
  /// Resolved from the Retur raised against the receipt, not inferred from the
  /// rejection: *"a line was rejected"* and *"a return was created for it"* are
  /// different facts, and a branch that has not raised the return yet is exactly
  /// what the Warehouse's queue is for (§27).
  static String _returnStatusLabel(GoodReceiptRecapRawRow raw) {
    final status = raw.returnStatus;
    if (status == null) return 'Belum dibuat';
    return GoodsReturnStatus.fromDbValue(status).label;
  }

  static ReportDocument build({
    required ReportRecapSource<GoodReceiptRecapRawRow> source,
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
          // What actually reached the branch's shelf.
          quantity: row.acceptedQty,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: row.itemId,
            batchId: row.batchId,
            userId: row.receivedBy,
          ),
          cells: [
            ReportCell(row.docNumber),
            ReportCell(row.doDocNumber),
            ReportCell(row.prDocNumber),
            ReportCell(master.branchLabel(row.branchId)),
            ReportCell(row.status.label),
            ReportCell(master.userLabel(row.receivedBy)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.postedAtUtc)),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(master.batchLabel(row.batchId)),
            ReportCell(ReportBuilderSupport.civilDateLabel(expiry)),
            ReportCell(row.shippedQty.format(), align: ReportColumnAlign.end),
            ReportCell(row.receivedQty.format(), align: ReportColumnAlign.end),
            ReportCell(
              row.acceptedQty.format(),
              align: ReportColumnAlign.end,
              emphasis: ReportCellEmphasis.positive,
            ),
            ReportCell(
              row.shortageQty.format(),
              align: ReportColumnAlign.end,
              emphasis: row.shortageQty.isZero
                  ? ReportCellEmphasis.none
                  : ReportCellEmphasis.warning,
            ),
            ReportCell(
              row.rejectedQty.format(),
              align: ReportColumnAlign.end,
              emphasis: row.rejectedQty.isZero
                  ? ReportCellEmphasis.none
                  : ReportCellEmphasis.danger,
            ),
            ReportCell(row.discrepancy.label),
            ReportCell(row.rejectReason ?? ReportLabels.notApplicable),
            ReportCell(row.returnStatusLabel),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportSyncSnapshotBuilder.buildDeduplicated([
      for (final raw in source.rows)
        (id: raw.grId, status: raw.syncStatus, updatedAtUtc: raw.updatedAtUtc),
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
          title: 'Ringkasan Selisih',
          metrics: [
            (
              label: 'Jumlah GR',
              value: '${typedRows.map((row) => row.grId).toSet().length}',
            ),
            (
              label: GoodReceiptDiscrepancyFilter.shortage.label,
              value:
                  '${typedRows.where((row) => row.discrepancy == GoodReceiptDiscrepancyFilter.shortage).length}',
            ),
            (
              label: GoodReceiptDiscrepancyFilter.rejected.label,
              value:
                  '${typedRows.where((row) => row.discrepancy == GoodReceiptDiscrepancyFilter.rejected).length}',
            ),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings),
    );
  }
}
