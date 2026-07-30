import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../models/report_raw_rows.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../services/report_filter_policy.dart';
import '../services/report_grouping_engine.dart';
import '../services/report_sync_snapshot_builder.dart';
import 'report_build_context.dart';

/// *Rekap Distribusi* — stock moving from a Gudang Cabang into its rooms (§28).
///
/// ### One row per destination room, always
///
/// G-T3 lets one document target several rooms, and this recap keeps them apart. The
/// aggregation that would collapse them — one row per item per document — is exactly
/// the operation that destroys the report's only interesting fact: a branch head
/// reading it wants to know *which room* got the gauze, and a document-level total
/// cannot say.
///
/// ### The source shelf comes from the ledger, not the document
///
/// `distributions` names a branch; only the movement names the Gudang Cabang the
/// stock actually left. So the *Gudang Sumber* column is read from
/// `from_location_id`, which is what the ledger asserts — and on a branch with two
/// store locations (a state the schema permits and the use cases refuse to guess
/// at) that is the only column that can be right.
///
/// A `draft` document has posted nothing, so its quantity is zero. It still appears
/// when the status filter allows it.
abstract final class DistributionRecapReportBuilder {
  static const List<ReportColumn> columns = [
    ReportColumn(key: 'docNumber', label: 'Nomor Distribusi', widthFlex: 3),
    ReportColumn(key: 'branch', label: 'Branch', widthFlex: 2),
    ReportColumn(key: 'status', label: 'Status', widthFlex: 2),
    ReportColumn(key: 'distributedBy', label: 'Distributed By', widthFlex: 3),
    ReportColumn(key: 'postedAt', label: 'Posted', widthFlex: 3),
    ReportColumn(key: 'source', label: 'Gudang Sumber', widthFlex: 3),
    ReportColumn(key: 'room', label: 'Ruangan Tujuan', widthFlex: 3),
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
    ReportColumn(key: 'fefo', label: 'FEFO Override Reason', widthFlex: 4),
  ];

  static List<DistributionRecapRow> rows({
    required ReportRecapSource<DistributionRecapRawRow> source,
    required ReportBuildContext context,
  }) {
    final master = source.master;
    final filter = context.filter;
    // Keyed by destination room as well as by position: two rooms on one document
    // may receive the same item from the same batch, and one key without the room
    // would fold them together (G-T3).
    final posted = _totalsByRoomPosition(source.movements);
    final sourceLocations = _sourceLocationsByDocument(source.movements);

    final rows = <DistributionRecapRow>[];
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
        master.userLabel(raw.distributedBy),
        master.branchLabel(raw.branchId),
        master.roomLabel(raw.roomId),
      ])) {
        continue;
      }

      final roomLocationId = _roomLocationOf(master, raw.roomId);
      final key = _RoomPositionKey(
        refDocId: raw.distributionId,
        toLocationId: roomLocationId,
        itemId: raw.itemId ?? '',
        batchId: raw.batchId,
      );
      rows.add(
        DistributionRecapRow(
          distributionId: raw.distributionId,
          docNumber: raw.docNumber,
          branchId: raw.branchId,
          status: DistributionStatus.fromDbValue(raw.status),
          distributedBy: raw.distributedBy,
          createdAtUtc: raw.createdAtUtc,
          postedAtUtc: raw.postedAtUtc,
          sourceLocationId: sourceLocations[raw.distributionId],
          roomId: raw.roomId,
          itemId: raw.itemId,
          batchId: raw.batchId,
          qty: posted[key] ?? Quantity.zero(),
          fefoOverrideReason: raw.fefoOverrideReason,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  /// The `room` stock location of a room, as the master data currently has it.
  ///
  /// `null` when the room has no location or several — the same ambiguity §14 makes
  /// the posting path refuse rather than guess. Here it only means the quantity
  /// cannot be attributed, and the row prints zero rather than a number picked from
  /// one of two candidate shelves.
  static String? _roomLocationOf(ReportMasterData master, String? roomId) {
    if (roomId == null) return null;
    final candidates = master.locations.values.where(
      (location) =>
          location.type == StockLocationType.room && location.roomId == roomId,
    );
    return candidates.length == 1 ? candidates.single.id : null;
  }

  static Map<_RoomPositionKey, Quantity> _totalsByRoomPosition(
    Iterable<ReportLedgerMovement> movements,
  ) {
    final totals = <_RoomPositionKey, Quantity>{};
    for (final movement in movements) {
      final refDocId = movement.refDocId;
      if (refDocId == null) continue;
      final key = _RoomPositionKey(
        refDocId: refDocId,
        toLocationId: movement.toLocationId,
        itemId: movement.itemId,
        batchId: movement.batchId,
      );
      totals[key] = (totals[key] ?? Quantity.zero()) + movement.qty;
    }
    return totals;
  }

  /// The Gudang Cabang each document's movements left, per document.
  static Map<String, String> _sourceLocationsByDocument(
    Iterable<ReportLedgerMovement> movements,
  ) {
    final sources = <String, String>{};
    for (final movement in movements) {
      final refDocId = movement.refDocId;
      final from = movement.fromLocationId;
      if (refDocId == null || from == null) continue;
      sources[refDocId] = from;
    }
    return sources;
  }

  static ReportDocument build({
    required ReportRecapSource<DistributionRecapRawRow> source,
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
              '${row.docNumber}|${master.roomLabel(row.roomId)}|'
              '${master.skuLabel(row.itemId)}|${row.batchId ?? ''}',
          unit: unit.isEmpty ? null : unit,
          quantity: row.qty,
          isHistorical: ReportBuilderSupport.isHistorical(
            master,
            itemId: row.itemId,
            batchId: row.batchId,
            userId: row.distributedBy,
          ),
          cells: [
            ReportCell(row.docNumber),
            ReportCell(master.branchLabel(row.branchId)),
            ReportCell(row.status.label),
            ReportCell(master.userLabel(row.distributedBy)),
            ReportCell(ReportBuilderSupport.dateTimeLabel(row.postedAtUtc)),
            ReportCell(
              ReportBuilderSupport.locationLabel(master, row.sourceLocationId),
            ),
            ReportCell(master.roomLabel(row.roomId)),
            ReportCell(category?.name ?? ReportGroup.unresolvedCategoryName),
            ReportCell(master.skuLabel(row.itemId)),
            ReportCell(master.itemLabel(row.itemId)),
            ReportCell(unit),
            ReportCell(master.batchLabel(row.batchId)),
            ReportCell(ReportBuilderSupport.civilDateLabel(expiry)),
            ReportCell(row.qty.format(), align: ReportColumnAlign.end),
            ReportCell(row.fefoOverrideReason ?? ReportLabels.notApplicable),
          ],
        ),
      );
    }

    final groups = ReportGroupingEngine.group(dataRows);
    final snapshot = ReportSyncSnapshotBuilder.buildDeduplicated([
      for (final raw in source.rows)
        (
          id: raw.distributionId,
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
          title: 'Ringkasan Distribusi',
          metrics: [
            (
              label: 'Jumlah dokumen',
              value:
                  '${typedRows.map((row) => row.distributionId).toSet().length}',
            ),
            (
              label: 'Ruangan tujuan',
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

/// `(document, destination room location, item, batch)`.
class _RoomPositionKey {
  const _RoomPositionKey({
    required this.refDocId,
    required this.toLocationId,
    required this.itemId,
    required this.batchId,
  });

  final String refDocId;
  final String? toLocationId;
  final String itemId;
  final String? batchId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _RoomPositionKey &&
          other.refDocId == refDocId &&
          other.toLocationId == toLocationId &&
          other.itemId == itemId &&
          other.batchId == batchId);

  @override
  int get hashCode => Object.hash(refDocId, toLocationId, itemId, batchId);
}
