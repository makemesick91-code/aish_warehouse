import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/operational_iso_week.dart';
import '../models/report_raw_rows.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../services/ledger_balance_engine.dart';
import '../services/report_filter_policy.dart';
import '../services/report_grouping_engine.dart';
import '../services/report_sync_snapshot_builder.dart';
import 'report_build_context.dart';

/// *Rekap Stok Opname* — what was counted, and what the ledger did about it (§24).
///
/// ### Two quantities that must never be confused
///
/// `Difference` is the **document's** figure: `counted_qty − system_qty`, the
/// generated column on `stock_opname_lines`. `Ledger Adjustment` is the signed
/// `opname_adjustment` movement G-O5 posted when a Kepala Cabang reviewed the
/// document. On a `reviewed` opname they agree, and that agreement is the whole
/// point of printing both — it is the reconciliation an auditor is looking for.
///
/// On a `draft` or `submitted` opname there **is no movement**, and the column is
/// empty rather than a copy of the difference. Filling it in would be the report
/// asserting a posting that never happened: the physical count exists, but the
/// balance was never corrected, and a reader who could not tell those apart could
/// not tell which rooms still need reviewing.
///
/// ### Ownership
///
/// A Perawat sees only opnames they counted, enforced in the SQL predicate through
/// [ReportAccessPolicy.requiresOwnDocuments] rather than by filtering rows after
/// loading them — a nurse must not be able to observe that a colleague's document
/// exists, not even by its absence from a total.
abstract final class OpnameRecapReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'docNumber', label: 'Nomor Opname', widthFlex: 3),
    ReportColumn(key: 'branch', label: 'Branch', widthFlex: 2),
    ReportColumn(key: 'room', label: 'Ruangan', widthFlex: 3),
    ReportColumn(key: 'period', label: 'Periode', widthFlex: 2),
    ReportColumn(key: 'status', label: 'Status', widthFlex: 2),
    ReportColumn(key: 'countedBy', label: 'Dibuat Oleh', widthFlex: 3),
    ReportColumn(key: 'reviewedBy', label: 'Direview Oleh', widthFlex: 3),
    ReportColumn(key: 'createdAt', label: 'Tanggal Dibuat', widthFlex: 3),
    ReportColumn(key: 'submittedAt', label: 'Tanggal Submit', widthFlex: 3),
    ReportColumn(key: 'reviewedAt', label: 'Tanggal Review', widthFlex: 3),
    ReportColumn(key: 'category', label: 'Kategori', widthFlex: 2),
    ReportColumn(key: 'sku', label: 'SKU', widthFlex: 2),
    ReportColumn(key: 'item', label: 'Barang', widthFlex: 4),
    ReportColumn(key: 'batch', label: 'Batch', widthFlex: 2),
    ReportColumn(
      key: 'systemQty',
      label: 'System Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'countedQty',
      label: 'Counted Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'difference',
      label: 'Difference',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'ledger',
      label: 'Ledger Adjustment',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(key: 'note', label: 'Catatan', widthFlex: 4),
  ];

  static List<OpnameRecapRow> rows({
    required ReportRecapSource<OpnameRecapRawRow> source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final filter = context.filter;
    // Signed per position: an adjustment that *reduced* the room's balance has to
    // print as a negative, or it cannot be reconciled against a negative difference.
    final adjustments = _signedAdjustments(source.movements);

    final rows = <OpnameRecapRow>[];
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
        master.userLabel(raw.countedBy),
        master.branchLabel(raw.branchId),
        master.roomLabel(raw.roomId),
      ])) {
        continue;
      }

      final status = StockOpnameStatus.fromDbValue(raw.status);
      final key = LedgerDocumentPositionKey(
        refDocId: raw.opnameId,
        itemId: raw.itemId ?? '',
        batchId: raw.batchId,
      );
      rows.add(
        OpnameRecapRow(
          opnameId: raw.opnameId,
          docNumber: raw.docNumber,
          branchId: raw.branchId,
          roomId: raw.roomId,
          periodLabel: OperationalIsoWeek(
            year: raw.periodYear,
            week: raw.periodWeek,
          ).label,
          status: status,
          countedBy: raw.countedBy,
          reviewedBy: raw.reviewedBy,
          createdAtUtc: raw.createdAtUtc,
          submittedAtUtc: raw.submittedAtUtc,
          reviewedAtUtc: raw.reviewedAtUtc,
          itemId: raw.itemId,
          batchId: raw.batchId,
          systemQty: _quantity(raw.systemQtyMilliUnits),
          countedQty: _quantity(raw.countedQtyMilliUnits),
          difference: _quantity(raw.differenceMilliUnits),
          // Absent, not zero, on a document that was never reviewed.
          ledgerAdjustment: raw.itemId == null ? null : adjustments[key],
          note: raw.lineNote,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  /// Signed `opname_adjustment` totals per `(opname, item, batch)`.
  ///
  /// Signed rather than magnitude, unlike every other recap: an opname correction
  /// goes both ways — a shortfall debits the room and a surplus credits it — so the
  /// direction *is* the information. The sign is read from the movement's own
  /// location columns, which is what the ledger asserts, rather than from the
  /// document's difference, which is what somebody typed.
  static Map<LedgerDocumentPositionKey, Quantity> _signedAdjustments(
    Iterable<ReportLedgerMovement> movements,
  ) {
    final totals = <LedgerDocumentPositionKey, Quantity>{};
    for (final movement in movements) {
      final refDocId = movement.refDocId;
      if (refDocId == null) continue;
      final key = LedgerDocumentPositionKey(
        refDocId: refDocId,
        itemId: movement.itemId,
        batchId: movement.batchId,
      );
      // An adjustment names one room: it credits it or debits it, never both.
      final delta = movement.toLocationId != null
          ? movement.qty
          : -movement.qty;
      totals[key] = (totals[key] ?? Quantity.zero()) + delta;
    }
    return totals;
  }

  static Quantity? _quantity(int? milliUnits) =>
      milliUnits == null ? null : Quantity.fromMilliUnits(milliUnits);

  static ReportDocument build({
    required ReportRecapSource<OpnameRecapRawRow> source,
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
          sortKey:
              '${row.docNumber}|${master.skuLabel(row.itemId)}|'
              '${row.batchId ?? ''}',
          unit: unit.isEmpty ? null : unit,
          // The *stock effect* is what a total on this report means. A document's
          // difference is an intent until somebody reviews it.
          quantity: row.ledgerAdjustment,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: row.itemId,
            batchId: row.batchId,
            userId: row.countedBy,
          ),
          cells: [
            ReportCell(row.docNumber),
            ReportCell(master.branchLabel(row.branchId)),
            ReportCell(master.roomLabel(row.roomId)),
            ReportCell(row.periodLabel),
            ReportCell(row.status.label),
            ReportCell(master.userLabel(row.countedBy)),
            ReportCell(master.userLabel(row.reviewedBy)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.createdAtUtc)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.submittedAtUtc)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.reviewedAtUtc)),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(master.batchLabel(row.batchId)),
            ReportCell(
              row.systemQty?.format() ?? ReportLabels.notApplicable,
              align: ReportColumnAlign.end,
            ),
            ReportCell(
              row.countedQty?.format() ?? ReportLabels.notApplicable,
              align: ReportColumnAlign.end,
            ),
            ReportCell(
              row.difference?.format() ?? ReportLabels.notApplicable,
              align: ReportColumnAlign.end,
              emphasis: (row.difference?.isZero ?? true)
                  ? ReportCellEmphasis.none
                  : ReportCellEmphasis.warning,
            ),
            ReportCell(
              // Empty, not `0` — see the class note.
              row.ledgerAdjustment?.format() ?? '',
              align: ReportColumnAlign.end,
            ),
            ReportCell(row.note ?? ''),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportSyncSnapshotBuilder.buildDeduplicated([
      for (final raw in source.rows)
        (
          id: raw.opnameId,
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
          title: 'Ringkasan Opname',
          metrics: [
            (
              label: 'Jumlah dokumen',
              value: '${typedRows.map((row) => row.opnameId).toSet().length}',
            ),
            (label: 'Jumlah baris', value: '${typedRows.length}'),
            (
              label: 'Baris berselisih',
              value:
                  '${typedRows.where((row) => !(row.difference?.isZero ?? true)).length}',
            ),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings),
    );
  }
}
