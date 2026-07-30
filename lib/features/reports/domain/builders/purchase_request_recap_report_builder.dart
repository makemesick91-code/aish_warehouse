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

/// *Rekap Purchase Request* — what was asked for, and what actually arrived (§25).
///
/// ### Intent and effect, side by side and never mixed
///
/// `Suggested Qty` and `Requested Qty` come from `purchase_request_lines`. They are
/// **document intent**: numbers a branch head typed, which move no stock and which
/// the ledger has never heard of. `Shipped`, `Accepted GR` and `Rejected Return`
/// come from the ledger, through the shipments, receipts and returns that the
/// request produced ([PurchaseRequestFulfilmentSource] explains why they have to be
/// assembled rather than queried).
///
/// Keeping the two apart is the entire value of this report: *"we asked for 100 and
/// 60 arrived"* is the question a Kepala Cabang runs it to answer, and a column that
/// silently mixed the sources could not answer it.
///
/// ### Outstanding, defined once and exactly
///
/// ```text
/// outstanding = max(0, requested − shipped)
/// ```
///
/// Two decisions inside that line:
///
/// * **Against `shipped`, not `accepted`.** What is still owed is what the Warehouse
///   has not sent. Goods that arrived and were refused went back through the Retur
///   workflow, which is a separate story with its own document — treating a
///   rejection as an open order would quietly re-order stock nobody asked for twice.
/// * **Floored at zero.** An over-shipment is refused by G-D2, so a negative here
///   would be corrupt data; showing it as a negative "outstanding" would read as the
///   branch owing the Warehouse goods, which is not a thing.
///
/// Computed in exact fixed point, like every quantity in this module.
abstract final class PurchaseRequestRecapReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'docNumber', label: 'Nomor PR', widthFlex: 3),
    ReportColumn(key: 'branch', label: 'Branch', widthFlex: 2),
    ReportColumn(key: 'status', label: 'Status', widthFlex: 2),
    ReportColumn(key: 'neededDate', label: 'Needed Date', widthFlex: 2),
    ReportColumn(key: 'requestedBy', label: 'Dibuat Oleh', widthFlex: 3),
    ReportColumn(key: 'createdAt', label: 'Dibuat', widthFlex: 3),
    ReportColumn(key: 'submittedAt', label: 'Submitted', widthFlex: 3),
    ReportColumn(key: 'processingAt', label: 'Processing', widthFlex: 3),
    ReportColumn(key: 'category', label: 'Kategori', widthFlex: 2),
    ReportColumn(key: 'sku', label: 'SKU', widthFlex: 2),
    ReportColumn(key: 'item', label: 'Barang', widthFlex: 4),
    ReportColumn(key: 'unit', label: 'Satuan', widthFlex: 1),
    ReportColumn(
      key: 'suggested',
      label: 'Suggested Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'requested',
      label: 'Requested Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'shipped',
      label: 'Shipped Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'accepted',
      label: 'Accepted GR Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'returned',
      label: 'Rejected Return Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'outstanding',
      label: 'Outstanding Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(key: 'note', label: 'Catatan', widthFlex: 4),
  ];

  static List<PurchaseRequestRecapRow> rows({
    required ReportRecapSource<PurchaseRequestRecapRawRow> source,
    required PurchaseRequestFulfilmentSource fulfilment,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final filter = context.filter;
    final shipped = _totalsByRequestItem(
      fulfilment.shipmentMovements,
      fulfilment.deliveryOrderToPr,
    );
    final accepted = _totalsByRequestItem(
      fulfilment.receiptMovements,
      fulfilment.goodReceiptToPr,
    );
    final returned = _totalsByRequestItem(
      fulfilment.returnMovements,
      fulfilment.goodsReturnToPr,
    );

    final rows = <PurchaseRequestRecapRow>[];
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
        master.userLabel(raw.requestedBy),
        master.branchLabel(raw.branchId),
      ])) {
        continue;
      }

      final key = LedgerDocumentItemKey(
        refDocId: raw.prId,
        itemId: raw.itemId ?? '',
      );
      final requested = _quantity(raw.requestedQtyMilliUnits);
      final shippedQty = shipped[key] ?? Quantity.zero();
      rows.add(
        PurchaseRequestRecapRow(
          prId: raw.prId,
          docNumber: raw.docNumber,
          branchId: raw.branchId,
          status: PurchaseRequestStatus.fromDbValue(raw.status),
          neededDate: raw.neededDate,
          requestedBy: raw.requestedBy,
          createdAtUtc: raw.createdAtUtc,
          submittedAtUtc: raw.submittedAtUtc,
          processingAtUtc: raw.processingAtUtc,
          itemId: raw.itemId,
          suggestedQty: _quantity(raw.suggestedQtyMilliUnits),
          requestedQty: requested,
          shippedQty: shippedQty,
          acceptedQty: accepted[key] ?? Quantity.zero(),
          returnedQty: returned[key] ?? Quantity.zero(),
          outstandingQty: _outstanding(requested, shippedQty),
          note: raw.lineNote ?? raw.headerNote,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  /// `max(0, requested − shipped)` — see the class note on both halves.
  static Quantity _outstanding(Quantity? requested, Quantity shipped) {
    if (requested == null) return Quantity.zero();
    return Quantity.max(Quantity.zero(), requested - shipped);
  }

  /// Movement magnitudes re-keyed from the document that posted them to the request
  /// that document belongs to.
  static Map<LedgerDocumentItemKey, Quantity> _totalsByRequestItem(
    Iterable<ReportLedgerMovement> movements,
    Map<String, String> documentToRequest,
  ) {
    final totals = <LedgerDocumentItemKey, Quantity>{};
    for (final movement in movements) {
      final refDocId = movement.refDocId;
      if (refDocId == null) continue;
      final prId = documentToRequest[refDocId];
      // A movement whose document is outside the actor's scope is skipped rather
      // than attributed to a request they cannot see.
      if (prId == null) continue;
      final key = LedgerDocumentItemKey(
        refDocId: prId,
        itemId: movement.itemId,
      );
      totals[key] = (totals[key] ?? Quantity.zero()) + movement.qty;
    }
    return totals;
  }

  static Quantity? _quantity(int? milliUnits) =>
      milliUnits == null ? null : Quantity.fromMilliUnits(milliUnits);

  static ReportDocument build({
    required ReportRecapSource<PurchaseRequestRecapRawRow> source,
    required PurchaseRequestFulfilmentSource fulfilment,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final typedRows = rows(
      source: source,
      fulfilment: fulfilment,
      context: context,
    );

    final dataRows = <ReportDataRow>[];
    for (final row in typedRows) {
      final item = master.item(row.itemId);
      final category = master.categoryOfItem(row.itemId);
      final unit = item?.unit ?? '';
      dataRows.add(
        ReportDataRow(
          categoryId: category?.id,
          categoryName: category?.name ?? ReportGroup.unresolvedCategoryName,
          sortKey: '${row.docNumber}|${master.skuLabel(row.itemId)}',
          unit: unit.isEmpty ? null : unit,
          // The stock effect, as on every recap: what the Warehouse actually sent.
          quantity: row.shippedQty,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: row.itemId,
            userId: row.requestedBy,
          ),
          cells: [
            ReportCell(row.docNumber),
            ReportCell(master.branchLabel(row.branchId)),
            ReportCell(row.status.label),
            ReportCell(ReportBuilderSupport.civilDateLabel(row.neededDate)),
            ReportCell(master.userLabel(row.requestedBy)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.createdAtUtc)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.submittedAtUtc)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.processingAtUtc)),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(
              row.suggestedQty?.format() ?? ReportLabels.notApplicable,
              align: ReportColumnAlign.end,
            ),
            ReportCell(
              row.requestedQty?.format() ?? ReportLabels.notApplicable,
              align: ReportColumnAlign.end,
            ),
            ReportCell(row.shippedQty.format(), align: ReportColumnAlign.end),
            ReportCell(row.acceptedQty.format(), align: ReportColumnAlign.end),
            ReportCell(
              row.returnedQty.format(),
              align: ReportColumnAlign.end,
              emphasis: row.returnedQty.isZero
                  ? ReportCellEmphasis.none
                  : ReportCellEmphasis.warning,
            ),
            ReportCell(
              row.outstandingQty.format(),
              align: ReportColumnAlign.end,
              emphasis: row.outstandingQty.isZero
                  ? ReportCellEmphasis.positive
                  : ReportCellEmphasis.warning,
            ),
            ReportCell(row.note ?? ''),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportSyncSnapshotBuilder.buildDeduplicated([
      for (final raw in source.rows)
        (id: raw.prId, status: raw.syncStatus, updatedAtUtc: raw.updatedAtUtc),
      for (final movement in [
        ...fulfilment.shipmentMovements,
        ...fulfilment.receiptMovements,
        ...fulfilment.returnMovements,
      ])
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
          title: 'Ringkasan Purchase Request',
          metrics: [
            (
              label: 'Jumlah PR',
              value: '${typedRows.map((row) => row.prId).toSet().length}',
            ),
            (label: 'Jumlah baris', value: '${typedRows.length}'),
            (
              label: 'Baris belum terpenuhi',
              value:
                  '${typedRows.where((row) => !row.outstandingQty.isZero).length}',
            ),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings),
    );
  }
}
