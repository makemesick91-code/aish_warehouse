import 'package:drift/drift.dart' show Value;

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/reporting_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/report_source_models.dart';
import '../../domain/models/reporting_models.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../domain/services/ledger_balance_engine.dart';

/// Drift-backed [ReportingRepository].
///
/// Three things happen here and nowhere else:
///
/// * **Milli-units become [Quantity].** The DAO speaks INTEGER (Q-4); everything
///   above this class speaks fixed-point. No builder, exporter or widget ever sees a
///   scale factor, which is why none of them can drop one.
/// * **Master ids become labels — or admit they cannot.** Every lookup here goes
///   through the `historical…` DAO methods, which filter on neither `deleted_at`
///   nor `is_active`. A row that is genuinely gone produces a warning and a fallback
///   label, never a missing quantity (§51).
/// * **Set integrity is checked.** The scope's movement ids are fetched separately
///   and compared against what came back, so a join that silently dropped a row
///   fails loudly instead of producing a smaller number (§35).
class DriftReportingRepository implements ReportingRepository {
  DriftReportingRepository(this._dao);

  final ReportingDao _dao;

  // --- scope ----------------------------------------------------------------

  @override
  Future<ReportScope> resolveScope({
    required ReportScopeType scopeType,
    String? locationId,
    String? branchId,
  }) async {
    switch (scopeType) {
      case ReportScopeType.warehouse:
      case ReportScopeType.branchStore:
      case ReportScopeType.room:
        return ReportScope(
          type: scopeType,
          locationId: locationId,
          branchId: branchId,
          locationIds: locationId == null ? const <String>{} : {locationId},
        );
      case ReportScopeType.branchAll:
        if (branchId == null) {
          return ReportScope(
            type: scopeType,
            locationIds: const <String>{},
            branchId: branchId,
          );
        }
        final rows = await _dao.locationsOfBranch(branchId);
        return ReportScope(
          type: scopeType,
          branchId: branchId,
          locationIds: rows.map((row) => row.id).toSet(),
        );
      case ReportScopeType.crossBranch:
        // Not a place: a document recap is scoped by the documents it lists.
        return const ReportScope(
          type: ReportScopeType.crossBranch,
          locationIds: <String>{},
        );
      case ReportScopeType.allLocations:
        final all = await _dao.allLocations();
        return ReportScope(
          type: scopeType,
          locationIds: all.map((row) => row.id).toSet(),
        );
    }
  }

  @override
  Future<MasterLocation?> locationById(String id) async =>
      _mapLocation((await _dao.historicalLocations({id})).firstOrNull);

  @override
  Future<MasterCategory?> categoryById(String id) async =>
      _mapCategory((await _dao.historicalCategories({id})).firstOrNull);

  @override
  Future<MasterItem?> itemById(String id) async =>
      _mapItem((await _dao.historicalItems({id})).firstOrNull);

  @override
  Future<MasterBranch?> branchById(String id) async =>
      _mapBranch((await _dao.historicalBranches({id})).firstOrNull);

  @override
  Future<MasterRoom?> roomById(String id) async =>
      _mapRoom((await _dao.historicalRooms({id})).firstOrNull);

  @override
  Future<MasterUser?> userById(String id) async =>
      _mapUser((await _dao.historicalUsers({id})).firstOrNull);

  @override
  Future<MasterRoom?> roomOfLocation(MasterLocation location) async {
    final roomId = location.roomId;
    if (roomId == null) return null;
    return roomById(roomId);
  }

  // --- ledger ---------------------------------------------------------------

  @override
  Future<ReportLedgerSource> loadLedgerSource({
    required ReportScope scope,
    String? itemId,
    String? categoryId,
  }) async {
    // Two reads of the same predicate. The cheap one lists the ids that must be
    // present; the expensive one loads them. Comparing the two is what turns "a
    // join dropped a row" from an invisible undercount into a failure (§35).
    final expectedIds = await _dao.movementIdsForScope(
      locationIds: scope.locationIds,
      itemId: itemId,
      categoryId: categoryId,
    );
    final rawRows = await _dao.movementsForScope(
      locationIds: scope.locationIds,
      itemId: itemId,
      categoryId: categoryId,
    );
    final loadedIds = rawRows.map((row) => row.id).toSet();
    if (!loadedIds.containsAll(expectedIds)) {
      throw ReportLedgerIntegrityFailure(
        'Sebagian data pergerakan stok tidak dapat dibaca. Laporan '
        'dibatalkan agar angka tidak berkurang tanpa penjelasan.',
        expectedMovementIds: expectedIds,
        loadedMovementIds: loadedIds,
      );
    }

    final movements = LedgerBalanceEngine.sorted(rawRows.map(_mapMovement));
    final warnings = <String>[];
    final master = await _loadMasterForMovements(movements, warnings);
    return ReportLedgerSource(
      movements: movements,
      master: master,
      warnings: warnings,
    );
  }

  Future<ReportMasterData> _loadMasterForMovements(
    List<ReportLedgerMovement> movements,
    List<String> warnings,
  ) {
    final itemIds = <String>{};
    final batchIds = <String>{};
    final locationIds = <String>{};
    final userIds = <String>{};
    for (final movement in movements) {
      itemIds.add(movement.itemId);
      if (movement.batchId != null) batchIds.add(movement.batchId!);
      if (movement.fromLocationId != null) {
        locationIds.add(movement.fromLocationId!);
      }
      if (movement.toLocationId != null) {
        locationIds.add(movement.toLocationId!);
      }
      userIds.add(movement.actorUserId);
    }
    return _loadMaster(
      itemIds: itemIds,
      batchIds: batchIds,
      locationIds: locationIds,
      userIds: userIds,
      warnings: warnings,
    );
  }

  /// Loads every master row a report needs and records what could not be found.
  ///
  /// A missing row is a warning rather than a failure — see the interface note. The
  /// warnings are worded once here so all three surfaces print the same sentence.
  Future<ReportMasterData> _loadMaster({
    Set<String> itemIds = const <String>{},
    Set<String> batchIds = const <String>{},
    Set<String> locationIds = const <String>{},
    Set<String> branchIds = const <String>{},
    Set<String> roomIds = const <String>{},
    Set<String> userIds = const <String>{},
    required List<String> warnings,
  }) async {
    final itemRows = await _dao.historicalItems(itemIds);
    final categoryIds = itemRows.map((row) => row.categoryId).toSet();
    final categoryRows = await _dao.historicalCategories(categoryIds);
    final batchRows = await _dao.historicalBatches(batchIds);

    // A location's branch and room are needed to label it, so the referenced sets
    // are widened before the branch and room reads rather than after.
    final locationRows = await _dao.historicalLocations(locationIds);
    final effectiveBranchIds = {
      ...branchIds,
      for (final row in locationRows)
        if (row.branchId != null) row.branchId!,
    };
    final effectiveRoomIds = {
      ...roomIds,
      for (final row in locationRows)
        if (row.roomId != null) row.roomId!,
    };
    final branchRows = await _dao.historicalBranches(effectiveBranchIds);
    final roomRows = await _dao.historicalRooms(effectiveRoomIds);
    final userRows = await _dao.historicalUsers(userIds);

    _warnMissing(warnings, 'barang', itemIds, itemRows.map((row) => row.id));
    _warnMissing(warnings, 'batch', batchIds, batchRows.map((row) => row.id));
    _warnMissing(
      warnings,
      'lokasi',
      locationIds,
      locationRows.map((row) => row.id),
    );
    _warnMissing(
      warnings,
      'cabang',
      effectiveBranchIds,
      branchRows.map((row) => row.id),
    );
    _warnMissing(
      warnings,
      'ruangan',
      effectiveRoomIds,
      roomRows.map((row) => row.id),
    );
    _warnMissing(warnings, 'pengguna', userIds, userRows.map((row) => row.id));

    return ReportMasterData(
      items: {for (final row in itemRows) row.id: _mapItem(row)!},
      categories: {for (final row in categoryRows) row.id: _mapCategory(row)!},
      batches: {for (final row in batchRows) row.id: _mapBatch(row)!},
      locations: {for (final row in locationRows) row.id: _mapLocation(row)!},
      branches: {for (final row in branchRows) row.id: _mapBranch(row)!},
      rooms: {for (final row in roomRows) row.id: _mapRoom(row)!},
      users: {for (final row in userRows) row.id: _mapUser(row)!},
    );
  }

  void _warnMissing(
    List<String> warnings,
    String entity,
    Set<String> expected,
    Iterable<String> found,
  ) {
    final missing = expected.difference(found.toSet());
    if (missing.isEmpty) return;
    warnings.add(
      'Referensi $entity tidak lengkap: ${missing.length} data historis tidak '
      'ditemukan. Angka tetap dihitung dari ledger.',
    );
  }

  @override
  Future<Map<String, String>> resolveDocumentNumbers(
    Iterable<ReportLedgerMovement> movements,
  ) async {
    // Grouped by type first: each type lives in its own table, so one query per
    // type present is the fewest queries this can be done in.
    final byType = <String, Set<String>>{};
    for (final movement in movements) {
      final type = movement.refDocType;
      final id = movement.refDocId;
      if (type == null || id == null) continue;
      byType.putIfAbsent(type, () => <String>{}).add(id);
    }
    final resolved = <String, String>{};
    for (final entry in byType.entries) {
      resolved.addAll(
        await _dao.documentNumbers(
          refDocType: entry.key,
          refDocIds: entry.value,
        ),
      );
    }
    return resolved;
  }

  // --- recaps ---------------------------------------------------------------

  @override
  Future<ReportRecapSource<OpnameRecapRawRow>> loadOpnameRecap({
    String? branchId,
    String? countedBy,
    String? roomId,
  }) async {
    final rows = await _dao.opnameRecap(
      branchId: branchId,
      countedBy: countedBy,
      roomId: roomId,
    );
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(rows.map((row) => row.itemId)),
      batchIds: _nonNull(rows.map((row) => row.batchId)),
      branchIds: rows.map((row) => row.branchId).toSet(),
      roomIds: rows.map((row) => row.roomId).toSet(),
      userIds: {
        ...rows.map((row) => row.countedBy),
        ..._nonNull(rows.map((row) => row.reviewedBy)),
      },
      warnings: warnings,
    );
    final movements = await _movementsFor(
      RefDocType.stockOpname,
      rows.map((row) => row.opnameId).toSet(),
    );
    return ReportRecapSource(
      rows: rows,
      movements: movements,
      master: master,
      warnings: warnings,
    );
  }

  @override
  Future<ReportRecapSource<PurchaseRequestRecapRawRow>>
  loadPurchaseRequestRecap({String? branchId}) async {
    final rows = await _dao.purchaseRequestRecap(branchId: branchId);
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(rows.map((row) => row.itemId)),
      branchIds: rows.map((row) => row.branchId).toSet(),
      userIds: rows.map((row) => row.requestedBy).toSet(),
      warnings: warnings,
    );
    // A Purchase Request posts nothing itself: its fulfilment lives on the
    // shipments, receipts and returns raised from it (§25). Those are loaded by the
    // builder through the DO/GR/RET recaps rather than guessed at here.
    return ReportRecapSource(
      rows: rows,
      movements: const <ReportLedgerMovement>[],
      master: master,
      warnings: warnings,
    );
  }

  @override
  Future<ReportRecapSource<DeliveryOrderRecapRawRow>> loadDeliveryOrderRecap({
    String? branchId,
  }) async {
    final rows = await _dao.deliveryOrderRecap(branchId: branchId);
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(rows.map((row) => row.itemId)),
      batchIds: _nonNull(rows.map((row) => row.batchId)),
      branchIds: rows.map((row) => row.branchId).toSet(),
      userIds: {
        ...rows.map((row) => row.preparedBy),
        ..._nonNull(rows.map((row) => row.shippedBy)),
      },
      warnings: warnings,
    );
    final movements = await _movementsFor(
      RefDocType.deliveryOrder,
      rows.map((row) => row.doId).toSet(),
    );
    return ReportRecapSource(
      rows: rows,
      movements: movements,
      master: master,
      warnings: warnings,
    );
  }

  @override
  Future<ReportRecapSource<GoodReceiptRecapRawRow>> loadGoodReceiptRecap({
    String? branchId,
  }) async {
    final rows = await _dao.goodReceiptRecap(branchId: branchId);
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(rows.map((row) => row.itemId)),
      batchIds: _nonNull(rows.map((row) => row.batchId)),
      branchIds: rows.map((row) => row.branchId).toSet(),
      userIds: rows.map((row) => row.receivedBy).toSet(),
      warnings: warnings,
    );
    final movements = await _movementsFor(
      RefDocType.goodReceipt,
      rows.map((row) => row.grId).toSet(),
    );
    return ReportRecapSource(
      rows: rows,
      movements: movements,
      master: master,
      warnings: warnings,
    );
  }

  @override
  Future<ReportRecapSource<DistributionRecapRawRow>> loadDistributionRecap({
    String? branchId,
  }) async {
    final rows = await _dao.distributionRecap(branchId: branchId);
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(rows.map((row) => row.itemId)),
      batchIds: _nonNull(rows.map((row) => row.batchId)),
      branchIds: rows.map((row) => row.branchId).toSet(),
      roomIds: _nonNull(rows.map((row) => row.roomId)),
      userIds: rows.map((row) => row.distributedBy).toSet(),
      warnings: warnings,
    );
    final movements = await _movementsFor(
      RefDocType.distribution,
      rows.map((row) => row.distributionId).toSet(),
    );
    // A distribution's movements name the Gudang Cabang they left and the room they
    // entered; both have to be nameable, and neither is on the document row.
    final withLocations = await _widenWithMovementLocations(
      master,
      movements,
      warnings,
    );
    return ReportRecapSource(
      rows: rows,
      movements: movements,
      master: withLocations,
      warnings: warnings,
    );
  }

  @override
  Future<ReportRecapSource<ConsumptionRecapRawRow>> loadConsumptionRecap({
    String? branchId,
    String? createdBy,
    String? roomId,
  }) async {
    final rows = await _dao.consumptionRecap(
      branchId: branchId,
      createdBy: createdBy,
      roomId: roomId,
    );
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(rows.map((row) => row.itemId)),
      batchIds: _nonNull(rows.map((row) => row.batchId)),
      branchIds: rows.map((row) => row.branchId).toSet(),
      roomIds: rows.map((row) => row.roomId).toSet(),
      userIds: {
        ...rows.map((row) => row.createdBy),
        ..._nonNull(rows.map((row) => row.postedBy)),
      },
      warnings: warnings,
    );
    final movements = await _movementsFor(
      RefDocType.consumption,
      rows.map((row) => row.consumptionId).toSet(),
    );
    return ReportRecapSource(
      rows: rows,
      movements: movements,
      master: master,
      warnings: warnings,
    );
  }

  @override
  Future<ReportRecapSource<DisposalRecapRawRow>> loadDisposalRecap({
    Set<String>? sourceLocationIds,
  }) async {
    final rows = await _dao.disposalRecap(sourceLocationIds: sourceLocationIds);
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(rows.map((row) => row.itemId)),
      batchIds: _nonNull(rows.map((row) => row.batchId)),
      locationIds: rows.map((row) => row.sourceLocationId).toSet(),
      userIds: {
        ...rows.map((row) => row.createdBy),
        ..._nonNull(rows.map((row) => row.postedBy)),
      },
      warnings: warnings,
    );
    final movements = await _movementsFor(
      RefDocType.disposal,
      rows.map((row) => row.disposalId).toSet(),
    );
    return ReportRecapSource(
      rows: rows,
      movements: movements,
      master: master,
      warnings: warnings,
    );
  }

  @override
  Future<ReportRecapSource<GoodsReturnRecapRawRow>> loadGoodsReturnRecap({
    String? branchId,
  }) async {
    final rows = await _dao.goodsReturnRecap(branchId: branchId);
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(rows.map((row) => row.itemId)),
      batchIds: _nonNull(rows.map((row) => row.batchId)),
      branchIds: rows.map((row) => row.branchId).toSet(),
      userIds: {
        ...rows.map((row) => row.createdBy),
        ..._nonNull(rows.map((row) => row.shippedBy)),
        ..._nonNull(rows.map((row) => row.receivedBy)),
      },
      warnings: warnings,
    );
    final movements = await _movementsFor(
      RefDocType.goodsReturn,
      rows.map((row) => row.goodsReturnId).toSet(),
    );
    return ReportRecapSource(
      rows: rows,
      movements: movements,
      master: master,
      warnings: warnings,
    );
  }

  Future<List<ReportLedgerMovement>> _movementsFor(
    String refDocType,
    Set<String> refDocIds,
  ) async {
    final rows = await _dao.movementsForDocuments(
      refDocType: refDocType,
      refDocIds: refDocIds,
    );
    return LedgerBalanceEngine.sorted(rows.map(_mapMovement));
  }

  /// Adds the locations a movement names to an already-loaded master set.
  ///
  /// A second read rather than a wider first one: the location ids are only known
  /// once the movements have been loaded, and guessing them from the document would
  /// mean the report labelling a shelf the ledger never mentioned.
  Future<ReportMasterData> _widenWithMovementLocations(
    ReportMasterData master,
    List<ReportLedgerMovement> movements,
    List<String> warnings,
  ) async {
    final ids = <String>{};
    for (final movement in movements) {
      if (movement.fromLocationId != null) ids.add(movement.fromLocationId!);
      if (movement.toLocationId != null) ids.add(movement.toLocationId!);
    }
    final missing = ids.difference(master.locations.keys.toSet());
    if (missing.isEmpty) return master;

    final rows = await _dao.historicalLocations(missing);
    _warnMissing(warnings, 'lokasi', missing, rows.map((row) => row.id));
    return ReportMasterData(
      items: master.items,
      categories: master.categories,
      batches: master.batches,
      locations: {
        ...master.locations,
        for (final row in rows) row.id: _mapLocation(row)!,
      },
      branches: master.branches,
      rooms: master.rooms,
      users: master.users,
    );
  }

  Set<String> _nonNull(Iterable<String?> values) => {
    for (final value in values) ?value,
  };

  // --- export audit ---------------------------------------------------------

  @override
  Future<ExportLog> insertExportLog({
    required ReportType reportType,
    required ReportFormat format,
    required ReportScopeType scopeType,
    String? locationId,
    String? categoryId,
    String? branchId,
    String? itemId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String exportedBy,
    required String fileName,
    required DateTime dataCutoffAtUtc,
    required String syncSummary,
    required int rowCount,
  }) async {
    final row = await _dao.insertExportLog(
      ExportLogsCompanion.insert(
        reportType: reportType,
        format: format,
        scopeType: scopeType,
        locationId: Value(locationId),
        categoryId: Value(categoryId),
        branchId: Value(branchId),
        itemId: Value(itemId),
        periodStart: periodStart,
        periodEnd: periodEnd,
        exportedBy: exportedBy,
        fileName: fileName,
        dataCutoffAt: dataCutoffAtUtc,
        syncSummary: syncSummary,
        rowCount: rowCount,
      ),
    );
    return _mapExportLog(row);
  }

  @override
  Stream<List<ExportLog>> watchExportHistory() =>
      _dao.watchExportLogs().map(_sortedLogs);

  @override
  Stream<List<ExportLog>> watchExportHistoryOf(String userId) =>
      _dao.watchExportLogsOf(userId).map(_sortedLogs);

  @override
  Future<List<ExportLog>> recentExportsOf(
    String userId, {
    int limit = 5,
  }) async {
    final logs = _sortedLogs(await _dao.exportLogsOf(userId));
    return logs.take(limit).toList(growable: false);
  }

  @override
  Future<List<ExportLog>> listExportHistory() async =>
      _sortedLogs(await _dao.allExportLogs());

  /// Newest first, sorted on the parsed instant.
  ///
  /// Not `ORDER BY created_at DESC`: the column is ISO-8601 TEXT, so SQL would
  /// compare it character by character. Ties are broken by id so two logs written in
  /// the same microsecond still come back in a stable order.
  List<ExportLog> _sortedLogs(List<ExportLogRow> rows) {
    final logs = rows.map(_mapExportLog).toList()
      ..sort((a, b) {
        final byTime = b.exportedAtUtc.compareTo(a.exportedAtUtc);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return List.unmodifiable(logs);
  }

  @override
  Future<ExportLog?> getExportLog(String id) async {
    final row = await _dao.exportLogById(id);
    return row == null ? null : _mapExportLog(row);
  }

  @override
  Future<ExportLogDetail?> getExportLogDetail(String id) async {
    final log = await getExportLog(id);
    if (log == null) return null;
    final details = await resolveExportLogDetails([log]);
    return details.firstOrNull;
  }

  @override
  Future<List<ExportLogDetail>> resolveExportLogDetails(
    List<ExportLog> logs,
  ) async {
    if (logs.isEmpty) return const <ExportLogDetail>[];
    final warnings = <String>[];
    final master = await _loadMaster(
      itemIds: _nonNull(logs.map((log) => log.itemId)),
      locationIds: _nonNull(logs.map((log) => log.locationId)),
      branchIds: _nonNull(logs.map((log) => log.branchId)),
      userIds: logs.map((log) => log.exportedBy).toSet(),
      warnings: warnings,
    );
    final categoryRows = await _dao.historicalCategories(
      _nonNull(logs.map((log) => log.categoryId)),
    );
    final categories = {
      for (final row in categoryRows) row.id: _mapCategory(row)!,
    };

    return List.unmodifiable([
      for (final log in logs)
        ExportLogDetail(
          log: log,
          exportedByLabel: master.userLabel(log.exportedBy),
          branchLabel: log.branchId == null
              ? ReportLabels.allBranches
              : master.branchLabel(log.branchId),
          locationLabel: log.locationId == null
              ? ReportLabels.allLocations
              : master.locationLabel(log.locationId),
          categoryLabel: log.categoryId == null
              ? ReportLabels.allCategories
              : (categories[log.categoryId]?.name ??
                    ReportGroup.unresolvedCategoryName),
          itemLabel: log.itemId == null
              ? ReportLabels.notApplicable
              : master.itemLabel(log.itemId),
        ),
    ]);
  }

  // --- mapping --------------------------------------------------------------

  ReportLedgerMovement _mapMovement(ReportMovementRawRow row) =>
      ReportLedgerMovement(
        id: row.id,
        createdAtUtc: row.createdAtUtc,
        updatedAtUtc: row.updatedAtUtc,
        syncStatus: row.syncStatus,
        itemId: row.itemId,
        batchId: row.batchId,
        fromLocationId: row.fromLocationId,
        toLocationId: row.toLocationId,
        qty: Quantity.fromMilliUnits(row.qtyMilliUnits),
        movementType: row.movementType,
        refDocType: row.refDocType,
        refDocId: row.refDocId,
        actorUserId: row.actorUserId,
        note: row.note,
        reversalOfMovementId: row.reversalOfMovementId,
      );

  ExportLog _mapExportLog(ExportLogRow row) => ExportLog(
    id: row.id,
    exportedAtUtc: row.createdAt,
    reportType: row.reportType,
    format: row.format,
    scopeType: row.scopeType,
    locationId: row.locationId,
    categoryId: row.categoryId,
    branchId: row.branchId,
    itemId: row.itemId,
    periodStart: row.periodStart,
    periodEnd: row.periodEnd,
    exportedBy: row.exportedBy,
    fileName: row.fileName,
    dataCutoffAtUtc: row.dataCutoffAt,
    syncSummary: row.syncSummary,
    rowCount: row.rowCount,
    syncStatus: row.syncStatus,
  );

  MasterItem? _mapItem(Item? row) => row == null
      ? null
      : MasterItem(
          id: row.id,
          sku: row.sku,
          name: row.name,
          categoryId: row.categoryId,
          unit: row.unit,
          minStockRoom: row.minStockRoom,
          minStockBranch: row.minStockBranch,
          hasExpiry: row.hasExpiry,
          expiryAlertDays: row.expiryAlertDays,
          isActive: row.isActive,
        );

  MasterCategory? _mapCategory(ItemCategory? row) =>
      row == null ? null : MasterCategory(id: row.id, name: row.name);

  MasterBatch? _mapBatch(ItemBatch? row) => row == null
      ? null
      : MasterBatch(
          id: row.id,
          itemId: row.itemId,
          batchNo: row.batchNo,
          expiryDate: row.expiryDate,
        );

  MasterLocation? _mapLocation(StockLocation? row) => row == null
      ? null
      : MasterLocation(
          id: row.id,
          type: row.type,
          branchId: row.branchId,
          roomId: row.roomId,
          name: row.name,
          isArchived: row.deletedAt != null,
        );

  MasterBranch? _mapBranch(Branch? row) => row == null
      ? null
      : MasterBranch(
          id: row.id,
          code: row.code,
          name: row.name,
          address: row.address,
          isActive: row.isActive,
          isArchived: row.deletedAt != null,
        );

  MasterRoom? _mapRoom(Room? row) => row == null
      ? null
      : MasterRoom(
          id: row.id,
          branchId: row.branchId,
          code: row.code,
          name: row.name,
          isActive: row.isActive,
          isArchived: row.deletedAt != null,
        );

  MasterUser? _mapUser(AppUser? row) => row == null
      ? null
      : MasterUser(
          id: row.id,
          fullName: row.fullName,
          email: row.email,
          role: row.role,
          branchId: row.branchId,
          isActive: row.isActive,
        );
}
