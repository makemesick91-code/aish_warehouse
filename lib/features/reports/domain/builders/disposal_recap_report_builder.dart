import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../models/report_raw_rows.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../services/ledger_balance_engine.dart';
import '../services/report_filter_policy.dart';
import '../services/report_grouping_engine.dart';
import '../services/report_sync_snapshot_builder.dart';
import 'report_build_context.dart';

/// *Rekap Pemusnahan* — stock destroyed, and how far past its date it was (§30).
///
/// ### There is no destination, and there never will be
///
/// A `disposal` movement carries a source and no `to_location_id` (G-E7): the goods
/// left the system. A "destination" column would have nothing true to put in it.
///
/// ### The branch is derived from the location, and may legitimately be absent
///
/// `disposals` has no branch column because the stock may have left Warehouse
/// Pusat, which belongs to no branch at all — `stock_locations` CHECKs that. So the
/// branch here is resolved *through* the source location, and a warehouse disposal
/// shows `—` rather than being forced under some branch heading.
///
/// ### `Days Expired` is measured at posting, not today
///
/// How overdue a batch was when it was destroyed is a fact about that day. Comparing
/// its expiry to the current date instead would make the same historical document
/// report a larger number every month.
abstract final class DisposalRecapReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'docNumber', label: 'Nomor Pemusnahan', widthFlex: 3),
    ReportColumn(key: 'source', label: 'Source Location', widthFlex: 3),
    ReportColumn(key: 'branch', label: 'Branch', widthFlex: 2),
    ReportColumn(key: 'createdBy', label: 'Created By', widthFlex: 3),
    ReportColumn(key: 'postedBy', label: 'Posted By', widthFlex: 3),
    ReportColumn(key: 'postedAt', label: 'Posted', widthFlex: 3),
    ReportColumn(key: 'reason', label: 'Reason', widthFlex: 4),
    ReportColumn(key: 'category', label: 'Kategori', widthFlex: 2),
    ReportColumn(key: 'sku', label: 'SKU', widthFlex: 2),
    ReportColumn(key: 'item', label: 'Barang', widthFlex: 4),
    ReportColumn(key: 'unit', label: 'Satuan', widthFlex: 1),
    ReportColumn(key: 'batch', label: 'Batch', widthFlex: 2),
    ReportColumn(key: 'expiry', label: 'Expiry', widthFlex: 2),
    ReportColumn(
      key: 'daysExpired',
      label: 'Days Expired',
      align: ReportColumnAlign.end,
      widthFlex: 2,
    ),
    ReportColumn(
      key: 'qty',
      label: 'Qty',
      align: ReportColumnAlign.end,
      isNumeric: true,
      widthFlex: 2,
    ),
    ReportColumn(key: 'note', label: 'Line Note', widthFlex: 4),
  ];

  static List<DisposalRecapRow> rows({
    required ReportRecapSource<DisposalRecapRawRow> source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final filter = context.filter;
    final posted = LedgerBalanceEngine.totalsByDocumentPosition(
      movements: source.movements,
    );

    final rows = <DisposalRecapRow>[];
    for (final raw in source.rows) {
      if (!ReportFilterPolicy.matchesStatus(filter, raw.status)) continue;
      if (!context.period.contains(raw.createdAtUtc)) continue;
      final item = master.item(raw.itemId);
      if (filter.categoryId != null && item?.categoryId != filter.categoryId) {
        continue;
      }
      if (!ReportFilterPolicy.matchesSearch(filter.searchText, [
        raw.docNumber,
        raw.reason,
        master.itemLabel(raw.itemId),
        master.skuLabel(raw.itemId),
        master.batchLabel(raw.batchId),
        master.userLabel(raw.createdBy),
        ReportBuilderSupport.locationLabel(master, raw.sourceLocationId),
      ])) {
        continue;
      }

      final key = LedgerDocumentPositionKey(
        refDocId: raw.disposalId,
        itemId: raw.itemId ?? '',
        batchId: raw.batchId,
      );
      final expiry = master.batch(raw.batchId)?.expiryDate;
      rows.add(
        DisposalRecapRow(
          disposalId: raw.disposalId,
          docNumber: raw.docNumber,
          sourceLocationId: raw.sourceLocationId,
          branchId: master.location(raw.sourceLocationId)?.branchId,
          status: DisposalStatus.fromDbValue(raw.status),
          createdBy: raw.createdBy,
          postedBy: raw.postedBy,
          reason: raw.reason,
          createdAtUtc: raw.createdAtUtc,
          postedAtUtc: raw.postedAtUtc,
          itemId: raw.itemId,
          batchId: raw.batchId,
          expiryDate: expiry,
          daysExpired: _daysExpired(
            expiryDate: expiry,
            postedAtUtc: raw.postedAtUtc,
          ),
          qty: raw.itemId == null
              ? Quantity.zero()
              : (posted[key] ?? Quantity.zero()),
          note: raw.lineNote,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  /// Whole operational days between the expiry date and the posting.
  ///
  /// `null` while the document is a draft — nothing has been destroyed yet, so
  /// "how overdue was it when it was" has no answer. A negative value means stock
  /// destroyed before it expired, which is legitimate (damage, recall) and printed
  /// as it is rather than clamped.
  static int? _daysExpired({
    required DateTime? expiryDate,
    required DateTime? postedAtUtc,
  }) {
    if (expiryDate == null || postedAtUtc == null) return null;
    return DateOnly.daysBetween(
      expiryDate,
      ReportBuilderSupport.operationalDateOf(postedAtUtc),
    );
  }

  static ReportDocument build({
    required ReportRecapSource<DisposalRecapRawRow> source,
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
          quantity: row.qty,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: row.itemId,
            batchId: row.batchId,
            locationId: row.sourceLocationId,
            userId: row.createdBy,
          ),
          cells: [
            ReportCell(row.docNumber),
            ReportCell(
              ReportBuilderSupport.locationLabel(master, row.sourceLocationId),
            ),
            ReportCell(
              row.branchId == null
                  ? ReportLabels.notApplicable
                  : master.branchLabel(row.branchId),
            ),
            ReportCell(master.userLabel(row.createdBy)),
            ReportCell(master.userLabel(row.postedBy)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.postedAtUtc)),
            ReportCell(row.reason),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(master.batchLabel(row.batchId)),
            ReportCell(ReportBuilderSupport.civilDateLabel(row.expiryDate)),
            ReportCell(
              row.daysExpired?.toString() ?? ReportLabels.notApplicable,
              align: ReportColumnAlign.end,
              emphasis: (row.daysExpired ?? 0) > 0
                  ? ReportCellEmphasis.danger
                  : ReportCellEmphasis.none,
            ),
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
          id: raw.disposalId,
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
          title: 'Ringkasan Pemusnahan',
          metrics: [
            (
              label: 'Jumlah dokumen',
              value: '${typedRows.map((row) => row.disposalId).toSet().length}',
            ),
            (
              label: 'Lokasi sumber',
              value:
                  '${typedRows.map((row) => row.sourceLocationId).toSet().length}',
            ),
            (label: 'Jumlah baris', value: '${typedRows.length}'),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings),
    );
  }
}
