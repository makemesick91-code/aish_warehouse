import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/consumption_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/consumption_models.dart';
import '../../domain/repositories/consumption_repository.dart';
import '../../domain/services/consumption_access_policy.dart';
import '../../domain/services/consumption_expiry_policy.dart';

/// Translates between the database boundary (milli-unit integers, drift rows) and the
/// Pemakaian domain.
///
/// This is the only file in the feature allowed to touch `Quantity.milliUnits` or a
/// generated drift class (Q-4) — the use cases, providers and widgets above it see
/// nothing but domain models.
class DriftConsumptionRepository implements ConsumptionRepository {
  DriftConsumptionRepository(this._dao);

  final ConsumptionDao _dao;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.runInTransaction(action);

  // --- header ---------------------------------------------------------------

  @override
  Future<Consumption> createDraft({
    required String docNumber,
    required String branchId,
    required String roomId,
    required String createdBy,
    String? note,
    DateTime? createdAtUtc,
  }) async {
    // The creation instant comes from the caller's injected clock rather than from the
    // column default (T-7). It is not decoration: the posting refuses to stamp
    // `posted_at` before it, so if the two came from different clocks a test could not
    // pin the ordering — and neither could a device whose clock moved between the two
    // writes.
    final now = (createdAtUtc ?? DateTime.now()).toUtc();

    final row = await _dao.insertHeader(
      ConsumptionsCompanion.insert(
        docNumber: docNumber,
        branchId: branchId,
        roomId: roomId,
        createdBy: createdBy,
        note: Value(note),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return _toConsumption(row);
  }

  @override
  Future<Consumption?> getById(String consumptionId) async {
    final row = await _dao.headerById(consumptionId);
    return row == null ? null : _toConsumption(row);
  }

  @override
  Future<ConsumptionDetail?> getDetail(String consumptionId) => _getDetail(
    consumptionId,
    scope: null,
    actorUserId: null,
    branchId: null,
    statuses: const {},
  );

  @override
  Future<ConsumptionDetail?> getOwn({
    required String consumptionId,
    required String actorUserId,
  }) => _getDetail(
    consumptionId,
    scope: ConsumptionQueryScope.ownDocuments,
    actorUserId: actorUserId,
    branchId: null,
    statuses: ConsumptionAccessPolicy.ownVisibleStatuses,
  );

  @override
  Future<ConsumptionDetail?> getPostedForBranch({
    required String consumptionId,
    required String branchId,
  }) => _getDetail(
    consumptionId,
    scope: ConsumptionQueryScope.branchPosted,
    actorUserId: null,
    branchId: branchId,
    statuses: ConsumptionAccessPolicy.branchVisibleStatuses,
  );

  @override
  Stream<ConsumptionDetail?> watchOwn({
    required String consumptionId,
    required String actorUserId,
  }) => _watchDetail(
    consumptionId,
    scope: ConsumptionQueryScope.ownDocuments,
    actorUserId: actorUserId,
    branchId: null,
    statuses: ConsumptionAccessPolicy.ownVisibleStatuses,
  );

  @override
  Stream<ConsumptionDetail?> watchPostedForBranch({
    required String consumptionId,
    required String branchId,
  }) => _watchDetail(
    consumptionId,
    scope: ConsumptionQueryScope.branchPosted,
    actorUserId: null,
    branchId: branchId,
    statuses: ConsumptionAccessPolicy.branchVisibleStatuses,
  );

  /// The header query carries the scope, and the children are fetched only after it
  /// produced a row. A document outside the scope therefore costs one predicate in
  /// SQLite and never reaches a second query — its items, batches, quantities and note
  /// are not read even to be discarded.
  Stream<ConsumptionDetail?> _watchDetail(
    String consumptionId, {
    required ConsumptionQueryScope scope,
    required String? actorUserId,
    required String? branchId,
    required Set<ConsumptionStatus> statuses,
  }) => _dao
      .watchSummaryById(
        consumptionId,
        scope: scope,
        actorUserId: actorUserId,
        branchId: branchId,
        statuses: statuses,
      )
      .asyncMap((context) async => context == null ? null : _hydrate(context));

  Future<ConsumptionDetail?> _getDetail(
    String consumptionId, {
    required ConsumptionQueryScope? scope,
    required String? actorUserId,
    required String? branchId,
    required Set<ConsumptionStatus> statuses,
  }) async {
    final context = await _dao.summaryById(
      consumptionId,
      scope: scope,
      actorUserId: actorUserId,
      branchId: branchId,
      statuses: statuses,
    );
    if (context == null) return null;
    return _hydrate(context);
  }

  Future<ConsumptionDetail> _hydrate(ConsumptionWithContext context) async {
    final lines = (await _dao.detailLines(
      context.consumption.id,
    )).map(_toLine).toList(growable: false);

    return ConsumptionDetail(summary: _toSummary(context), lines: lines);
  }

  @override
  Future<ConsumptionAccessScope?> findAccessScope({
    required String consumptionId,
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    Set<ConsumptionStatus> statuses = const {},
  }) async {
    final row = await _dao.accessScope(
      consumptionId: consumptionId,
      scope: scope,
      actorUserId: actorUserId,
      branchId: branchId,
      statuses: statuses,
    );
    if (row == null) return null;
    return ConsumptionAccessScope(
      consumptionId: row.consumptionId,
      branchId: row.branchId,
      roomId: row.roomId,
      createdBy: row.createdBy,
      status: row.status,
    );
  }

  @override
  Future<List<ConsumptionSummary>> listOwn({
    required String actorUserId,
    String? roomId,
    Set<ConsumptionStatus> statuses = const {},
    String searchQuery = '',
  }) async {
    final visible = _visibleOwnStatuses(statuses);
    if (visible.isEmpty) return const <ConsumptionSummary>[];
    final rows = await _dao.listConsumptions(
      scope: ConsumptionQueryScope.ownDocuments,
      actorUserId: actorUserId,
      roomId: roomId,
      statuses: visible,
      searchQuery: searchQuery,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Stream<List<ConsumptionSummary>> watchOwnList({
    required String actorUserId,
    String? roomId,
    Set<ConsumptionStatus> statuses = const {},
    String searchQuery = '',
  }) {
    final visible = _visibleOwnStatuses(statuses);
    if (visible.isEmpty) return Stream.value(const <ConsumptionSummary>[]);
    return _dao
        .watchConsumptions(
          scope: ConsumptionQueryScope.ownDocuments,
          actorUserId: actorUserId,
          roomId: roomId,
          statuses: visible,
          searchQuery: searchQuery,
        )
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  @override
  Future<List<ConsumptionSummary>> listPostedForBranch({
    required String branchId,
    String? roomId,
    String? createdBy,
    String searchQuery = '',
  }) async {
    final rows = await _dao.listConsumptions(
      scope: ConsumptionQueryScope.branchPosted,
      branchId: branchId,
      roomId: roomId,
      createdBy: createdBy,
      // Passed as well as baked into the scope predicate: two independent statements of
      // the same rule, so removing either one still leaves a branch head unable to read
      // a draft.
      statuses: ConsumptionAccessPolicy.branchVisibleStatuses,
      searchQuery: searchQuery,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Stream<List<ConsumptionSummary>> watchBranchPostedList({
    required String branchId,
    String? roomId,
    String? createdBy,
    String searchQuery = '',
  }) {
    return _dao
        .watchConsumptions(
          scope: ConsumptionQueryScope.branchPosted,
          branchId: branchId,
          roomId: roomId,
          createdBy: createdBy,
          statuses: ConsumptionAccessPolicy.branchVisibleStatuses,
          searchQuery: searchQuery,
        )
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  /// Intersecting here rather than trusting [statuses] is what makes the visibility
  /// restriction a property of the method instead of a convention its callers follow.
  Set<ConsumptionStatus> _visibleOwnStatuses(Set<ConsumptionStatus> statuses) =>
      statuses.isEmpty
      ? ConsumptionAccessPolicy.ownVisibleStatuses
      : statuses
            .where(ConsumptionAccessPolicy.ownVisibleStatuses.contains)
            .toSet();

  @override
  Future<bool> markPosted({
    required String consumptionId,
    required String actorUserId,
    required DateTime postedAtUtc,
    required String postedBy,
  }) async =>
      await _dao.markPosted(
        consumptionId: consumptionId,
        createdBy: actorUserId,
        postedAtUtc: postedAtUtc,
        postedBy: postedBy,
      ) >
      0;

  @override
  Future<bool> updateOwnDraftNote({
    required String consumptionId,
    required String actorUserId,
    required String? note,
  }) async =>
      await _dao.updateOwnDraftNote(
        consumptionId: consumptionId,
        createdBy: actorUserId,
        note: note,
      ) >
      0;

  // --- lines ----------------------------------------------------------------

  @override
  Future<List<ConsumptionLineReference>> lineReferences(
    String consumptionId,
  ) async => (await _dao.linesOf(
    consumptionId,
  )).map(_toReference).toList(growable: false);

  @override
  Future<ConsumptionLineReference?> lineReferenceById(String lineId) async {
    final row = await _dao.lineById(lineId);
    return row == null ? null : _toReference(row);
  }

  @override
  Future<List<String>> lineIds(String consumptionId) =>
      _dao.lineIdsOf(consumptionId);

  @override
  Future<List<String>> lineItemIds(String consumptionId) =>
      _dao.lineItemIdsOf(consumptionId);

  @override
  Future<List<String>> lineBatchIds(String consumptionId) =>
      _dao.lineBatchIdsOf(consumptionId);

  @override
  Future<ConsumptionLineReference> addDraftLine({
    required String consumptionId,
    required String actorUserId,
    required String itemId,
    String? batchId,
    required Quantity qty,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    try {
      final row = await _dao.insertLine(
        ConsumptionLinesCompanion.insert(
          consumptionId: consumptionId,
          itemId: itemId,
          batchId: Value(batchId),
          qty: qty.milliUnits,
          note: Value(note),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return _toReference(row);
    } on Object catch (error) {
      // The partial unique indexes' last line of defence. Two devices can both read
      // "this position is free" and both insert; the index lets exactly one through, and
      // the loser must see a business failure rather than a driver error.
      if (_isPositionUniqueViolation(error)) {
        throw DuplicateConsumptionLineFailure(
          batchId == null
              ? 'Barang ini sudah ada pada dokumen pemakaian ini. Ubah jumlah '
                    'baris yang ada, bukan menambah baris baru.'
              : 'Batch ini sudah ada pada dokumen pemakaian ini. Ubah jumlah '
                    'baris yang ada, bukan menambah baris baru.',
          consumptionId: consumptionId,
          itemId: itemId,
          batchId: batchId,
        );
      }
      rethrow;
    }
  }

  /// Whether [error] is one of the partial unique indexes on `consumption_lines`
  /// firing.
  ///
  /// Matched on the message rather than on an exception type, because the type comes
  /// from the sqlite3 package and importing it here would drag the native driver into a
  /// repository that otherwise only knows drift. Both index names and the column list
  /// are accepted, and anything else is rethrown untouched rather than swallowed as
  /// "already exists".
  static bool _isPositionUniqueViolation(Object error) {
    final message = error.toString().toLowerCase();
    if (!message.contains('unique')) return false;
    return message.contains('idx_consumption_lines_batched') ||
        message.contains('idx_consumption_lines_unbatched') ||
        message.contains('consumption_lines.batch_id') ||
        message.contains('consumption_lines.item_id');
  }

  @override
  Future<bool> updateDraftLine({
    required String consumptionId,
    required String actorUserId,
    required String lineId,
    required Quantity qty,
    String? note,
  }) async =>
      await _dao.updateOwnDraftLine(
        consumptionId: consumptionId,
        createdBy: actorUserId,
        lineId: lineId,
        qtyMilliUnits: qty.milliUnits,
        note: note,
      ) >
      0;

  @override
  Future<bool> removeDraftLine({
    required String consumptionId,
    required String actorUserId,
    required String lineId,
  }) async =>
      await _dao.softDeleteOwnDraftLine(
        consumptionId: consumptionId,
        createdBy: actorUserId,
        lineId: lineId,
      ) >
      0;

  // --- room stock -----------------------------------------------------------

  @override
  Future<List<RoomStockPosition>> searchRoomCandidates({
    required String roomId,
    required String roomLocationId,
    required DateTime nowUtc,
    String searchQuery = '',
    String? categoryId,
    bool activeItemsOnly = true,
    int limit = 8,
  }) async {
    final positions = await _positions(
      roomId: roomId,
      roomLocationId: roomLocationId,
      nowUtc: nowUtc,
      searchQuery: searchQuery,
      categoryId: categoryId,
      activeItemsOnly: activeItemsOnly,
    );
    return positions.length <= limit
        ? positions
        : List<RoomStockPosition>.unmodifiable(positions.take(limit));
  }

  @override
  Future<List<RoomStockPosition>> roomPositions({
    required String roomId,
    required String roomLocationId,
    required DateTime nowUtc,
    String? categoryId,
    bool activeItemsOnly = false,
  }) => _positions(
    roomId: roomId,
    roomLocationId: roomLocationId,
    nowUtc: nowUtc,
    categoryId: categoryId,
    activeItemsOnly: activeItemsOnly,
  );

  @override
  Stream<List<RoomStockPosition>> watchRoomPositions({
    required String roomId,
    required String roomLocationId,
    required DateTime nowUtc,
    String? categoryId,
    bool activeItemsOnly = false,
  }) async* {
    // The location name is resolved once, outside the stream, because it is master data
    // the balance stream cannot see. A location that vanished entirely yields no
    // positions at all rather than rows labelled with an empty string.
    final locations = await _dao.roomLocationsOf(roomId, activeOnly: false);
    final location = locations
        .where((row) => row.id == roomLocationId)
        .firstOrNull;
    if (location == null) {
      yield const <RoomStockPosition>[];
      return;
    }
    yield* _dao
        .watchRoomStock(
          locationId: roomLocationId,
          categoryId: categoryId,
          activeItemsOnly: activeItemsOnly,
        )
        .map(
          (rows) => _usable(
            rows
                .map((row) => _toPosition(row, roomId, location))
                .toList(growable: false),
            nowUtc,
          ),
        );
  }

  @override
  Future<RoomStockPosition?> roomPositionFor({
    required String roomId,
    required String roomLocationId,
    required String itemId,
    String? batchId,
    required DateTime nowUtc,
  }) async {
    final positions = await _positions(
      roomId: roomId,
      roomLocationId: roomLocationId,
      nowUtc: nowUtc,
      itemId: itemId,
      batchId: batchId,
      activeItemsOnly: false,
    );
    // `batchId == null` cannot be expressed as a SQL equality, so an item's unbatched
    // row and its batched rows both come back when only the item is pinned. Filtering
    // here rather than in the DAO keeps the "is NULL" case explicit instead of relying
    // on a query parameter that silently means "any batch".
    final matches = positions
        .where((position) => position.batchId == batchId)
        .toList(growable: false);
    return matches.isEmpty ? null : matches.single;
  }

  /// The one place the expiry filter is applied.
  ///
  /// The DAO returns every positive balance at the room; this is where
  /// `ConsumptionExpiryPolicy` decides which of them may actually be consumed, in Dart,
  /// on civil dates. Doing it in SQL would compare ISO-8601 TEXT against a serialised
  /// "now" — the trap schema v4 removed from `stock_opnames`.
  Future<List<RoomStockPosition>> _positions({
    required String roomId,
    required String roomLocationId,
    required DateTime nowUtc,
    String? itemId,
    String? batchId,
    String? searchQuery,
    String? categoryId,
    required bool activeItemsOnly,
  }) async {
    final locations = await _dao.roomLocationsOf(roomId, activeOnly: false);
    final location = locations
        .where((row) => row.id == roomLocationId)
        .firstOrNull;
    if (location == null) return const <RoomStockPosition>[];

    final rows = await _dao.roomStock(
      locationId: roomLocationId,
      itemId: itemId,
      batchId: batchId,
      searchQuery: searchQuery,
      categoryId: categoryId,
      activeItemsOnly: activeItemsOnly,
    );
    return _usable(
      rows
          .map((row) => _toPosition(row, roomId, location))
          .toList(growable: false),
      nowUtc,
    );
  }

  /// Drops what may not be consumed and keeps the DAO's order.
  ///
  /// The SQL already ordered by `(item name, expiry, batch no, batch id)`, so filtering
  /// preserves it — which is why nothing here re-sorts. Re-sorting would be a second
  /// definition of the picker order, and the two would eventually differ.
  static List<RoomStockPosition> _usable(
    List<RoomStockPosition> positions,
    DateTime nowUtc,
  ) => ConsumptionExpiryPolicy.usable<RoomStockPosition>(
    positions: positions,
    nowUtc: nowUtc,
    expiryDateOf: (position) => position.expiryDate,
    hasStockOf: (position) => position.qtyOnHand.isPositive,
  );

  // --- rooms ----------------------------------------------------------------

  @override
  Future<List<ConsumptionRoom>> activeRoomsOfBranch(String branchId) async =>
      (await _dao.activeRoomsOfBranch(
        branchId,
      )).map(_toRoom).toList(growable: false);

  @override
  Stream<List<ConsumptionRoom>> watchActiveRoomsOfBranch(String branchId) =>
      _dao
          .watchActiveRoomsOfBranch(branchId)
          .map((rows) => rows.map(_toRoom).toList(growable: false));

  @override
  Future<ConsumptionRoom?> historicalRoomById(String roomId) async {
    final row = await _dao.roomById(roomId);
    return row == null ? null : _toRoom(row);
  }

  @override
  Future<List<MasterLocation>> roomLocations(
    String roomId, {
    bool activeOnly = true,
  }) async => (await _dao.roomLocationsOf(
    roomId,
    activeOnly: activeOnly,
  )).map(_toLocation).toList(growable: false);
}

Consumption _toConsumption(ConsumptionRow row) => Consumption(
  id: row.id,
  docNumber: row.docNumber,
  branchId: row.branchId,
  roomId: row.roomId,
  createdBy: row.createdBy,
  status: row.status,
  note: row.note,
  postedAt: row.postedAt,
  postedBy: row.postedBy,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  syncStatus: row.syncStatus,
);

/// What "historic" means, in one place.
///
/// Deactivated (G-A4) and soft-deleted (G-A5) are separate states with the same
/// consequence for a document that already references the row: a *posted* document stays
/// readable against it, but the row can no longer be picked for anything new.
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

ConsumptionRoom _toRoom(Room row) => ConsumptionRoom(
  roomId: row.id,
  branchId: row.branchId,
  code: row.code,
  name: row.name,
  isActive: row.isActive,
  isArchived: row.deletedAt != null,
);

/// The joins behind [ConsumptionWithContext] filter neither `is_active` nor
/// `deleted_at`, which is what keeps a posted consumption visible after its branch, its
/// room or the nurse who posted it is retired. The flags below turn that fact into
/// something the screens can label, rather than into a document that quietly disappears
/// from the list (§33).
ConsumptionSummary _toSummary(ConsumptionWithContext row) => ConsumptionSummary(
  consumption: _toConsumption(row.consumption),
  room: _toRoom(row.room),
  branchCode: row.branch.code,
  branchName: row.branch.name,
  createdByName: row.createdBy.fullName,
  postedByName: row.postedBy?.fullName,
  lineCount: row.lineCount,
  itemCount: row.itemCount,
  batchCount: row.batchCount,
  branchIsHistorical: _isHistorical(row.branch.isActive, row.branch.deletedAt),
  roomIsHistorical: _isHistorical(row.room.isActive, row.room.deletedAt),
  createdByIsHistorical: _isHistorical(
    row.createdBy.isActive,
    row.createdBy.deletedAt,
  ),
  postedByIsHistorical:
      row.postedBy != null &&
      _isHistorical(row.postedBy!.isActive, row.postedBy!.deletedAt),
);

ConsumptionLine _toLine(ConsumptionLineWithDetails row) => ConsumptionLine(
  id: row.line.id,
  consumptionId: row.line.consumptionId,
  itemId: row.line.itemId,
  sku: row.item.sku,
  itemName: row.item.name,
  categoryId: row.item.categoryId,
  unit: row.item.unit,
  hasExpiry: row.item.hasExpiry,
  expiryAlertDays: row.item.expiryAlertDays,
  batchId: row.line.batchId,
  batchNo: row.batch?.batchNo,
  // A civil date is read back verbatim, never timezone converted (T-9).
  expiryDate: row.batch == null ? null : DateOnly.from(row.batch!.expiryDate),
  qty: Quantity.fromMilliUnits(row.line.qty),
  note: row.line.note,
  itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
  batchIsHistorical: row.batch != null && row.batch!.deletedAt != null,
);

ConsumptionLineReference _toReference(ConsumptionLineRow row) =>
    ConsumptionLineReference(
      id: row.id,
      consumptionId: row.consumptionId,
      itemId: row.itemId,
      batchId: row.batchId,
      qty: Quantity.fromMilliUnits(row.qty),
      note: row.note,
    );

RoomStockPosition _toPosition(
  RoomBatchStockRow row,
  String roomId,
  StockLocation location,
) => RoomStockPosition(
  roomId: roomId,
  locationId: location.id,
  locationName: location.name,
  itemId: row.item.id,
  sku: row.item.sku,
  itemName: row.item.name,
  categoryId: row.item.categoryId,
  unit: row.item.unit,
  hasExpiry: row.item.hasExpiry,
  expiryAlertDays: row.item.expiryAlertDays,
  batchId: row.batch?.id,
  batchNo: row.batch?.batchNo,
  expiryDate: row.batch == null ? null : DateOnly.from(row.batch!.expiryDate),
  qtyOnHand: Quantity.fromMilliUnits(row.qtyOnHandMilliUnits),
  itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
  batchIsHistorical: row.batch != null && row.batch!.deletedAt != null,
);
