import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/disposal_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/disposal_models.dart';
import '../../domain/repositories/disposal_repository.dart';
import '../../domain/services/disposal_access_policy.dart';
import '../../domain/services/disposal_expiry_policy.dart';

/// Translates between the database boundary (milli-unit integers, drift rows) and
/// the Pemusnahan domain.
///
/// This is the only file in the feature allowed to touch `Quantity.milliUnits` or a
/// generated drift class (Q-4) — the use cases, providers and widgets above it see
/// nothing but domain models.
class DriftDisposalRepository implements DisposalRepository {
  DriftDisposalRepository(this._dao);

  final DisposalDao _dao;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.runInTransaction(action);

  // --- header ---------------------------------------------------------------

  @override
  Future<Disposal> createDraft({
    required String docNumber,
    required String sourceLocationId,
    required String createdBy,
    String? reason,
    DateTime? createdAtUtc,
  }) async {
    // The creation instant comes from the caller's injected clock rather than from
    // the column default (T-7). It is not decoration: the posting refuses to stamp
    // `posted_at` before it, so if the two came from different clocks a test could
    // not pin the ordering — and neither could a device whose clock moved between
    // the two writes.
    final now = (createdAtUtc ?? DateTime.now()).toUtc();

    final row = await _dao.insertHeader(
      DisposalsCompanion.insert(
        docNumber: docNumber,
        sourceLocationId: sourceLocationId,
        createdBy: createdBy,
        reason: Value(reason),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return _toDisposal(row);
  }

  @override
  Future<Disposal?> getById(String disposalId) async {
    final row = await _dao.headerById(disposalId);
    return row == null ? null : _toDisposal(row);
  }

  @override
  Future<DisposalDetail?> getDetail(String disposalId) =>
      _getDetail(disposalId, scope: null, branchId: null, statuses: const {});

  @override
  Future<DisposalDetail?> getForWarehouse(String disposalId) => _getDetail(
    disposalId,
    scope: DisposalLocationScope.warehouse,
    branchId: null,
    statuses: DisposalAccessPolicy.visibleStatuses,
  );

  @override
  Future<DisposalDetail?> getForBranch({
    required String disposalId,
    required String branchId,
  }) => _getDetail(
    disposalId,
    scope: DisposalLocationScope.branch,
    branchId: branchId,
    statuses: DisposalAccessPolicy.visibleStatuses,
  );

  @override
  Stream<DisposalDetail?> watchForWarehouse(String disposalId) => _watchDetail(
    disposalId,
    scope: DisposalLocationScope.warehouse,
    branchId: null,
  );

  @override
  Stream<DisposalDetail?> watchForBranch({
    required String disposalId,
    required String branchId,
  }) => _watchDetail(
    disposalId,
    scope: DisposalLocationScope.branch,
    branchId: branchId,
  );

  /// The header query carries the scope, and the children are fetched only after it
  /// produced a row. A document outside the scope therefore costs one predicate in
  /// SQLite and never reaches a second query — its items, batches, quantities and
  /// reason are not read even to be discarded.
  Stream<DisposalDetail?> _watchDetail(
    String disposalId, {
    required DisposalLocationScope scope,
    required String? branchId,
  }) => _dao
      .watchSummaryById(
        disposalId,
        scope: scope,
        branchId: branchId,
        statuses: DisposalAccessPolicy.visibleStatuses,
      )
      .asyncMap((context) async => context == null ? null : _hydrate(context));

  Future<DisposalDetail?> _getDetail(
    String disposalId, {
    required DisposalLocationScope? scope,
    required String? branchId,
    required Set<DisposalStatus> statuses,
  }) async {
    final context = await _dao.summaryById(
      disposalId,
      scope: scope,
      branchId: branchId,
      statuses: statuses,
    );
    if (context == null) return null;
    return _hydrate(context);
  }

  Future<DisposalDetail> _hydrate(DisposalWithContext context) async {
    final lines = (await _dao.detailLines(
      context.disposal.id,
    )).map(_toLine).toList(growable: false);

    return DisposalDetail(summary: _toSummary(context), lines: lines);
  }

  @override
  Future<DisposalAccessScope?> findAccessScope({
    required String disposalId,
    DisposalLocationScope? scope,
    String? branchId,
    Set<DisposalStatus> statuses = const {},
  }) async {
    final row = await _dao.accessScope(
      disposalId: disposalId,
      scope: scope,
      branchId: branchId,
      statuses: statuses,
    );
    if (row == null) return null;
    return DisposalAccessScope(
      disposalId: row.disposalId,
      sourceLocationId: row.sourceLocationId,
      createdBy: row.createdBy,
      status: row.status,
    );
  }

  @override
  Future<List<DisposalSummary>> listForWarehouse({
    Set<DisposalStatus> statuses = const {},
    String searchQuery = '',
  }) async {
    final visible = _visibleStatuses(statuses);
    if (visible.isEmpty) return const <DisposalSummary>[];
    final rows = await _dao.listDisposals(
      scope: DisposalLocationScope.warehouse,
      statuses: visible,
      searchQuery: searchQuery,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Stream<List<DisposalSummary>> watchListForWarehouse({
    Set<DisposalStatus> statuses = const {},
    String searchQuery = '',
  }) {
    final visible = _visibleStatuses(statuses);
    if (visible.isEmpty) return Stream.value(const <DisposalSummary>[]);
    return _dao
        .watchDisposals(
          scope: DisposalLocationScope.warehouse,
          statuses: visible,
          searchQuery: searchQuery,
        )
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  @override
  Future<List<DisposalSummary>> listForBranch({
    required String branchId,
    String? sourceLocationId,
    Set<DisposalStatus> statuses = const {},
    String searchQuery = '',
  }) async {
    final visible = _visibleStatuses(statuses);
    if (visible.isEmpty) return const <DisposalSummary>[];
    final rows = await _dao.listDisposals(
      scope: DisposalLocationScope.branch,
      branchId: branchId,
      sourceLocationId: sourceLocationId,
      statuses: visible,
      searchQuery: searchQuery,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Stream<List<DisposalSummary>> watchListForBranch({
    required String branchId,
    String? sourceLocationId,
    Set<DisposalStatus> statuses = const {},
    String searchQuery = '',
  }) {
    final visible = _visibleStatuses(statuses);
    if (visible.isEmpty) return Stream.value(const <DisposalSummary>[]);
    return _dao
        .watchDisposals(
          scope: DisposalLocationScope.branch,
          branchId: branchId,
          sourceLocationId: sourceLocationId,
          statuses: visible,
          searchQuery: searchQuery,
        )
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  /// Intersecting here rather than trusting [statuses] is what makes the visibility
  /// restriction a property of the method instead of a convention its callers
  /// follow.
  Set<DisposalStatus> _visibleStatuses(Set<DisposalStatus> statuses) =>
      statuses.isEmpty
      ? DisposalAccessPolicy.visibleStatuses
      : statuses.where(DisposalAccessPolicy.visibleStatuses.contains).toSet();

  @override
  Future<bool> markPosted({
    required String disposalId,
    required DateTime postedAtUtc,
    required String postedBy,
  }) async =>
      await _dao.markPosted(
        disposalId: disposalId,
        postedAtUtc: postedAtUtc,
        postedBy: postedBy,
      ) >
      0;

  @override
  Future<bool> updateDraftReason({
    required String disposalId,
    required String? reason,
  }) async =>
      await _dao.updateDraftReason(disposalId: disposalId, reason: reason) > 0;

  // --- lines ----------------------------------------------------------------

  @override
  Future<List<DisposalLineReference>> lineReferences(String disposalId) async =>
      (await _dao.linesOf(
        disposalId,
      )).map(_toReference).toList(growable: false);

  @override
  Future<DisposalLineReference?> lineReferenceById(String lineId) async {
    final row = await _dao.lineById(lineId);
    return row == null ? null : _toReference(row);
  }

  @override
  Future<List<String>> lineIds(String disposalId) => _dao.lineIdsOf(disposalId);

  @override
  Future<List<String>> lineItemIds(String disposalId) =>
      _dao.lineItemIdsOf(disposalId);

  @override
  Future<List<String>> lineBatchIds(String disposalId) =>
      _dao.lineBatchIdsOf(disposalId);

  @override
  Future<DisposalLineReference> addLine({
    required String disposalId,
    required String itemId,
    required String batchId,
    required Quantity qty,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    try {
      final row = await _dao.insertLine(
        DisposalLinesCompanion.insert(
          disposalId: disposalId,
          itemId: itemId,
          batchId: batchId,
          qty: qty.milliUnits,
          note: Value(note),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return _toReference(row);
    } on Object catch (error) {
      // The partial unique index's last line of defence. Two devices can both read
      // "this position is free" and both insert; the index lets exactly one through,
      // and the loser must see a business failure rather than a driver error.
      if (_isPositionUniqueViolation(error)) {
        throw DuplicateDisposalLineFailure(
          'Batch ini sudah ada pada dokumen pemusnahan ini. Ubah jumlah baris '
          'yang ada, bukan menambah baris baru.',
          disposalId: disposalId,
          itemId: itemId,
          batchId: batchId,
        );
      }
      rethrow;
    }
  }

  /// Whether [error] is the partial unique index on `disposal_lines` firing.
  ///
  /// Matched on the message rather than on an exception type, because the type comes
  /// from the sqlite3 package and importing it here would drag the native driver into
  /// a repository that otherwise only knows drift. The index name and the column list
  /// are both accepted, and anything else is rethrown untouched rather than swallowed
  /// as "already exists".
  static bool _isPositionUniqueViolation(Object error) {
    final message = error.toString().toLowerCase();
    if (!message.contains('unique')) return false;
    return message.contains('idx_disposal_lines_position') ||
        message.contains('disposal_lines.batch_id');
  }

  @override
  Future<bool> updateDraftLine({
    required String disposalId,
    required String lineId,
    required Quantity qty,
    String? note,
  }) async =>
      await _dao.updateDraftLine(
        disposalId: disposalId,
        lineId: lineId,
        qtyMilliUnits: qty.milliUnits,
        note: note,
      ) >
      0;

  @override
  Future<bool> removeDraftLine({
    required String disposalId,
    required String lineId,
  }) async =>
      await _dao.softDeleteDraftLine(disposalId: disposalId, lineId: lineId) >
      0;

  // --- expired stock --------------------------------------------------------

  @override
  Future<List<ExpiredStockPosition>> searchExpiredCandidates({
    required String sourceLocationId,
    required DateTime nowUtc,
    String searchQuery = '',
    String? categoryId,
    int limit = 8,
  }) async {
    final positions = await _expired(
      sourceLocationId: sourceLocationId,
      nowUtc: nowUtc,
      searchQuery: searchQuery,
      categoryId: categoryId,
    );
    return positions.length <= limit
        ? positions
        : List<ExpiredStockPosition>.unmodifiable(positions.take(limit));
  }

  @override
  Future<List<ExpiredStockPosition>> expiredPositions({
    required String sourceLocationId,
    required DateTime nowUtc,
    String? categoryId,
  }) => _expired(
    sourceLocationId: sourceLocationId,
    nowUtc: nowUtc,
    categoryId: categoryId,
  );

  @override
  Stream<List<ExpiredStockPosition>> watchExpiredPositions({
    required String sourceLocationId,
    required DateTime nowUtc,
    String? categoryId,
  }) async* {
    // The location name is resolved once, outside the stream, because it is master
    // data the balance stream cannot see. A location that vanished entirely yields
    // no positions at all rather than rows labelled with an empty string.
    final location = await _dao.locationById(sourceLocationId);
    if (location == null) {
      yield const <ExpiredStockPosition>[];
      return;
    }
    yield* _dao
        .watchExpiredStock(locationId: sourceLocationId, categoryId: categoryId)
        .map(
          (rows) => DisposalExpiryPolicy.disposablePositions(
            positions: rows
                .map((row) => _toPosition(row, location))
                .toList(growable: false),
            nowUtc: nowUtc,
          ),
        );
  }

  @override
  Future<ExpiredStockPosition?> expiredPositionFor({
    required String sourceLocationId,
    required String itemId,
    required String batchId,
    required DateTime nowUtc,
  }) async {
    final positions = await _expired(
      sourceLocationId: sourceLocationId,
      nowUtc: nowUtc,
      itemId: itemId,
      batchId: batchId,
    );
    return positions.isEmpty ? null : positions.single;
  }

  /// The one place the expiry filter is applied.
  ///
  /// The DAO returns every positive batch balance at the location; this is where
  /// `DisposalExpiryPolicy` decides which of them may actually be destroyed, in
  /// Dart, on civil dates. Doing it in SQL would compare ISO-8601 TEXT against a
  /// serialised "now" — the trap schema v4 removed from `stock_opnames`.
  Future<List<ExpiredStockPosition>> _expired({
    required String sourceLocationId,
    required DateTime nowUtc,
    String? itemId,
    String? batchId,
    String? searchQuery,
    String? categoryId,
  }) async {
    final location = await _dao.locationById(sourceLocationId);
    if (location == null) return const <ExpiredStockPosition>[];

    final rows = await _dao.expiredStock(
      locationId: sourceLocationId,
      itemId: itemId,
      batchId: batchId,
      searchQuery: searchQuery,
      categoryId: categoryId,
    );
    return DisposalExpiryPolicy.disposablePositions(
      positions: rows
          .map((row) => _toPosition(row, location))
          .toList(growable: false),
      nowUtc: nowUtc,
    );
  }

  // --- locations ------------------------------------------------------------

  @override
  Future<List<MasterLocation>> warehouseSourceLocations() async =>
      (await _dao.warehouseLocations())
          .map(_toLocation)
          .toList(growable: false);

  @override
  Future<List<MasterLocation>> branchSourceLocations(String branchId) async =>
      (await _dao.branchSourceLocations(
        branchId,
      )).map(_toLocation).toList(growable: false);

  @override
  Stream<List<MasterLocation>> watchBranchSourceLocations(String branchId) =>
      _dao
          .watchBranchSourceLocations(branchId)
          .map((rows) => rows.map(_toLocation).toList(growable: false));

  @override
  Future<MasterLocation?> historicalLocationById(String locationId) async {
    final row = await _dao.locationById(locationId);
    return row == null ? null : _toLocation(row);
  }
}

Disposal _toDisposal(DisposalRow row) => Disposal(
  id: row.id,
  docNumber: row.docNumber,
  sourceLocationId: row.sourceLocationId,
  createdBy: row.createdBy,
  status: row.status,
  reason: row.reason,
  postedAt: row.postedAt,
  postedBy: row.postedBy,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  syncStatus: row.syncStatus,
);

/// What "historic" means, in one place.
///
/// Deactivated (G-A4) and soft-deleted (G-A5) are separate states with the same
/// consequence for a document that already references the row: a *posted* document
/// stays readable against it, but the row can no longer be picked for anything new.
bool _isHistorical(bool isActive, DateTime? deletedAt) =>
    !isActive || deletedAt != null;

MasterLocation _toLocation(StockLocation row) => MasterLocation(
  id: row.id,
  type: row.type,
  branchId: row.branchId,
  roomId: row.roomId,
  name: row.name,
  isArchived: row.deletedAt != null,
);

DisposalSourceLocation _toSource(StockLocation row) => DisposalSourceLocation(
  locationId: row.id,
  type: row.type,
  name: row.name,
  branchId: row.branchId,
  roomId: row.roomId,
  isArchived: row.deletedAt != null,
);

/// The joins behind [DisposalWithContext] filter neither `is_active` nor
/// `deleted_at`, which is what keeps a posted disposal visible after its source
/// location, its branch, its room or the person who posted it is retired. The flags
/// below turn that fact into something the screens can label, rather than into a
/// document that quietly disappears from the list (§34).
DisposalSummary _toSummary(DisposalWithContext row) => DisposalSummary(
  disposal: _toDisposal(row.disposal),
  source: _toSource(row.sourceLocation),
  branchCode: row.branch?.code,
  branchName: row.branch?.name,
  roomCode: row.room?.code,
  roomName: row.room?.name,
  createdByName: row.createdBy.fullName,
  postedByName: row.postedBy?.fullName,
  lineCount: row.lineCount,
  itemCount: row.itemCount,
  batchCount: row.batchCount,
  sourceIsHistorical: row.sourceLocation.deletedAt != null,
  branchIsHistorical:
      row.branch != null &&
      _isHistorical(row.branch!.isActive, row.branch!.deletedAt),
  roomIsHistorical:
      row.room != null &&
      _isHistorical(row.room!.isActive, row.room!.deletedAt),
  createdByIsHistorical: _isHistorical(
    row.createdBy.isActive,
    row.createdBy.deletedAt,
  ),
  postedByIsHistorical:
      row.postedBy != null &&
      _isHistorical(row.postedBy!.isActive, row.postedBy!.deletedAt),
);

DisposalLine _toLine(DisposalLineWithDetails row) => DisposalLine(
  id: row.line.id,
  disposalId: row.line.disposalId,
  itemId: row.line.itemId,
  sku: row.item.sku,
  itemName: row.item.name,
  categoryId: row.item.categoryId,
  unit: row.item.unit,
  hasExpiry: row.item.hasExpiry,
  batchId: row.line.batchId,
  batchNo: row.batch.batchNo,
  // A civil date is read back verbatim, never timezone converted (T-9).
  expiryDate: DateOnly.from(row.batch.expiryDate),
  qty: Quantity.fromMilliUnits(row.line.qty),
  note: row.line.note,
  itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
  batchIsHistorical: row.batch.deletedAt != null,
);

DisposalLineReference _toReference(DisposalLineRow row) =>
    DisposalLineReference(
      id: row.id,
      disposalId: row.disposalId,
      itemId: row.itemId,
      batchId: row.batchId,
      qty: Quantity.fromMilliUnits(row.qty),
      note: row.note,
    );

ExpiredStockPosition _toPosition(
  LocationBatchStockRow row,
  StockLocation location,
) => ExpiredStockPosition(
  locationId: location.id,
  locationName: location.name,
  itemId: row.item.id,
  sku: row.item.sku,
  itemName: row.item.name,
  categoryId: row.item.categoryId,
  unit: row.item.unit,
  batchId: row.batch.id,
  batchNo: row.batch.batchNo,
  expiryDate: DateOnly.from(row.batch.expiryDate),
  qtyOnHand: Quantity.fromMilliUnits(row.qtyOnHandMilliUnits),
  itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
  batchIsHistorical: row.batch.deletedAt != null,
);
