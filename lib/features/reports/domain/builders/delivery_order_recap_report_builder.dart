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

/// *Rekap Delivery Order* — what left the Warehouse, per branch and per period
/// (§26).
///
/// ### A `preparing` document ships nothing
///
/// Its allocations exist on `delivery_order_lines`, but no `shipment` movement has
/// been posted, so `Shipped Qty` is **zero** rather than the allocated figure. The
/// document still appears when the status filter allows it — a Warehouse user
/// asking *"what is being prepared"* is asking a real question — but the quantity
/// column answers *"what has left the building"*, and an allocation has not.
///
/// ### An expired outbound batch is flagged, not hidden
///
/// G-E4 blocks shipping expired stock, so a `shipped` line whose batch had already
/// expired cannot be produced by this application going forward. It can still be
/// *present*: a row written before the rule existed, or one that arrived through
/// sync. Dropping it would make the recap disagree with the ledger, and printing it
/// silently would bury the one row somebody needs to investigate — so it is printed
/// with an integrity warning attached (§26).
abstract final class DeliveryOrderRecapReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'docNumber', label: 'Nomor DO/SJ', widthFlex: 3),
    ReportColumn(key: 'prNumber', label: 'Nomor PR', widthFlex: 3),
    ReportColumn(key: 'branch', label: 'Branch', widthFlex: 2),
    ReportColumn(key: 'status', label: 'Status', widthFlex: 2),
    ReportColumn(key: 'preparedBy', label: 'Prepared By', widthFlex: 3),
    ReportColumn(key: 'shippedBy', label: 'Shipped By', widthFlex: 3),
    ReportColumn(key: 'createdAt', label: 'Dibuat', widthFlex: 3),
    ReportColumn(key: 'shippedAt', label: 'Dikirim', widthFlex: 3),
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
      key: 'nearExpiry',
      label: 'Konfirmasi Near-expiry',
      widthFlex: 2,
    ),
    ReportColumn(key: 'fefo', label: 'FEFO Override', widthFlex: 4),
    ReportColumn(key: 'note', label: 'Catatan', widthFlex: 4),
  ];

  static List<DeliveryOrderRecapRow> rows({
    required ReportRecapSource<DeliveryOrderRecapRawRow> source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final filter = context.filter;
    final shipped = LedgerBalanceEngine.totalsByDocumentPosition(
      movements: source.movements,
    );

    final rows = <DeliveryOrderRecapRow>[];
    for (final raw in source.rows) {
      if (!ReportFilterPolicy.matchesStatus(filter, raw.status)) continue;
      if (!context.period.contains(raw.createdAtUtc)) continue;
      final item = master.item(raw.itemId);
      if (filter.categoryId != null && item?.categoryId != filter.categoryId) {
        continue;
      }
      if (!ReportFilterPolicy.matchesSearch(filter.searchText, [
        raw.docNumber,
        raw.prDocNumber,
        master.itemLabel(raw.itemId),
        master.skuLabel(raw.itemId),
        master.batchLabel(raw.batchId),
        master.userLabel(raw.preparedBy),
        master.branchLabel(raw.branchId),
      ])) {
        continue;
      }

      final key = LedgerDocumentPositionKey(
        refDocId: raw.doId,
        itemId: raw.itemId ?? '',
        batchId: raw.batchId,
      );
      final shippedQty = raw.itemId == null
          ? Quantity.zero()
          : (shipped[key] ?? Quantity.zero());

      rows.add(
        DeliveryOrderRecapRow(
          doId: raw.doId,
          docNumber: raw.docNumber,
          prDocNumber: raw.prDocNumber,
          branchId: raw.branchId,
          status: DeliveryOrderStatus.fromDbValue(raw.status),
          preparedBy: raw.preparedBy,
          shippedBy: raw.shippedBy,
          createdAtUtc: raw.createdAtUtc,
          shippedAtUtc: raw.shippedAtUtc,
          itemId: raw.itemId,
          batchId: raw.batchId,
          shippedQty: shippedQty,
          nearExpiryConfirmed: raw.nearExpiryConfirmed ?? false,
          fefoOverrideReason: raw.fefoOverrideReason,
          note: raw.nearExpiryNote ?? raw.headerNote,
          integrityWarning: _expiredOutboundWarning(
            master: master,
            raw: raw,
            shippedQty: shippedQty,
          ),
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  /// The warning for stock that left the warehouse after its expiry date.
  ///
  /// Measured against the **shipment date**, not today: whether a batch had expired
  /// when it was sent is a fact about that moment, and comparing it to the current
  /// date would flag every old shipment of a batch that has since expired normally.
  static String? _expiredOutboundWarning({
    required ReportMasterData master,
    required DeliveryOrderRecapRawRow raw,
    required Quantity shippedQty,
  }) {
    if (shippedQty.isZero) return null;
    final shippedAt = raw.shippedAtUtc;
    final expiry = master.batch(raw.batchId)?.expiryDate;
    if (shippedAt == null || expiry == null) return null;
    final shippedOn = ReportBuilderSupport.operationalDateOf(shippedAt);
    if (!DateOnly.isAfterDate(shippedOn, expiry)) return null;
    return 'Integritas: ${raw.docNumber} mengirim batch '
        '${master.batchLabel(raw.batchId)} yang sudah kedaluwarsa pada tanggal '
        'pengiriman.';
  }

  static ReportDocument build({
    required ReportRecapSource<DeliveryOrderRecapRawRow> source,
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
          quantity: row.shippedQty,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: row.itemId,
            batchId: row.batchId,
            userId: row.preparedBy,
          ),
          cells: [
            ReportCell(row.docNumber),
            ReportCell(row.prDocNumber),
            ReportCell(master.branchLabel(row.branchId)),
            ReportCell(row.status.label),
            ReportCell(master.userLabel(row.preparedBy)),
            ReportCell(master.userLabel(row.shippedBy)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.createdAtUtc)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.shippedAtUtc)),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(master.batchLabel(row.batchId)),
            ReportCell(ReportBuilderSupport.civilDateLabel(expiry)),
            ReportCell(
              row.shippedQty.format(),
              align: ReportColumnAlign.end,
              emphasis: row.integrityWarning == null
                  ? ReportCellEmphasis.none
                  : ReportCellEmphasis.danger,
            ),
            ReportCell(
              row.nearExpiryConfirmed ? 'Ya' : ReportLabels.notApplicable,
              emphasis: row.nearExpiryConfirmed
                  ? ReportCellEmphasis.warning
                  : ReportCellEmphasis.none,
            ),
            ReportCell(row.fefoOverrideReason ?? ReportLabels.notApplicable),
            ReportCell(row.note ?? ''),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportSyncSnapshotBuilder.buildDeduplicated([
      for (final raw in source.rows)
        (id: raw.doId, status: raw.syncStatus, updatedAtUtc: raw.updatedAtUtc),
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
          title: 'Ringkasan Pengiriman',
          metrics: [
            (
              label: 'Jumlah DO',
              value: '${typedRows.map((row) => row.doId).toSet().length}',
            ),
            (label: 'Jumlah baris', value: '${typedRows.length}'),
            (
              label: 'Baris dengan FEFO override',
              value:
                  '${typedRows.where((row) => row.fefoOverrideReason != null).length}',
            ),
          ],
        ),
      ],
      warnings: ReportBuilderSupport.warnings(source.warnings, [
        for (final row in typedRows)
          if (row.integrityWarning != null) row.integrityWarning!,
      ]),
    );
  }
}
