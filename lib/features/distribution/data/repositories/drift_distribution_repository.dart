import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/distribution_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/distribution_models.dart';
import '../../domain/repositories/distribution_repository.dart';
import '../../domain/services/distribution_access_policy.dart';
import '../../domain/services/distribution_expiry_policy.dart';

/// Translates between the database boundary (milli-unit integers, drift rows) and
/// the Distribusi domain.
///
/// This is the only file in the feature allowed to touch `Quantity.milliUnits` or a
/// generated drift class (Q-4) — the use cases, providers and widgets above it see
/// nothing but domain models.
class DriftDistributionRepository implements DistributionRepository {
  DriftDistributionRepository(this._dao);

  final DistributionDao _dao;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.runInTransaction(action);

  // --- header ---------------------------------------------------------------

  @override
  Future<Distribution> createDraft({
    required String docNumber,
    required String branchId,
    required String distributedBy,
    String? note,
    DateTime? createdAtUtc,
  }) async {
    // The creation instant comes from the caller's injected clock rather than from
    // the column default (T-7). It is not decoration: the posting refuses to stamp
    // `posted_at` before it, so if the two came from different clocks a test could
    // not pin the ordering — and neither could a device whose clock moved between
    // the two writes.
    final now = (createdAtUtc ?? DateTime.now()).toUtc();

    final row = await _dao.insertHeader(
      DistributionsCompanion.insert(
        docNumber: docNumber,
        branchId: branchId,
        distributedBy: distributedBy,
        note: Value(note),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return _toDistribution(row);
  }

  @override
  Future<Distribution?> getById(String distributionId) async {
    final row = await _dao.headerById(distributionId);
    return row == null ? null : _toDistribution(row);
  }

  @override
  Future<DistributionDetail?> getDetail(String distributionId) =>
      _getDetail(distributionId, branchId: null, statuses: const {});

  @override
  Future<DistributionDetail?> getForBranch({
    required String distributionId,
    required String branchId,
  }) => _getDetail(
    distributionId,
    branchId: branchId,
    statuses: DistributionAccessPolicy.branchVisibleStatuses,
  );

  @override
  Stream<DistributionDetail?> watchForBranch({
    required String distributionId,
    required String branchId,
  }) {
    // The header query carries the branch and status scope, and the children are
    // fetched only after it produced a row. A document outside the scope therefore
    // costs one predicate in SQLite and never reaches a second query — its rooms,
    // items, batches and quantities are not read even to be discarded.
    return _dao
        .watchSummaryById(
          distributionId,
          branchId: branchId,
          statuses: DistributionAccessPolicy.branchVisibleStatuses,
        )
        .asyncMap(
          (context) async => context == null ? null : _hydrate(context),
        );
  }

  Future<DistributionDetail?> _getDetail(
    String distributionId, {
    required String? branchId,
    required Set<DistributionStatus> statuses,
  }) async {
    final context = await _dao.summaryById(
      distributionId,
      branchId: branchId,
      statuses: statuses,
    );
    if (context == null) return null;
    return _hydrate(context);
  }

  Future<DistributionDetail> _hydrate(DistributionWithContext context) async {
    final lines = (await _dao.detailLines(
      context.distribution.id,
    )).map(_toLine).toList(growable: false);

    return DistributionDetail(summary: _toSummary(context), lines: lines);
  }

  @override
  Future<DistributionAccessScope?> findAccessScope({
    required String distributionId,
    String? branchId,
    Set<DistributionStatus> statuses = const {},
  }) async {
    final row = await _dao.accessScope(
      distributionId: distributionId,
      branchId: branchId,
      statuses: statuses,
    );
    if (row == null) return null;
    return DistributionAccessScope(
      distributionId: row.distributionId,
      branchId: row.branchId,
      distributedBy: row.distributedBy,
      status: row.status,
    );
  }

  @override
  Future<List<DistributionSummary>> listForBranch({
    required String branchId,
    Set<DistributionStatus> statuses = const {},
    String searchQuery = '',
  }) async {
    final visible = _branchStatuses(statuses);
    if (visible.isEmpty) return const <DistributionSummary>[];
    final rows = await _dao.listDistributions(
      branchId: branchId,
      statuses: visible,
      searchQuery: searchQuery,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Stream<List<DistributionSummary>> watchListForBranch({
    required String branchId,
    Set<DistributionStatus> statuses = const {},
    String searchQuery = '',
  }) {
    final visible = _branchStatuses(statuses);
    if (visible.isEmpty) return Stream.value(const <DistributionSummary>[]);
    return _dao
        .watchDistributions(
          branchId: branchId,
          statuses: visible,
          searchQuery: searchQuery,
        )
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  /// Intersecting here rather than trusting [statuses] is what makes the branch
  /// restriction a property of the method instead of a convention its callers follow.
  Set<DistributionStatus> _branchStatuses(Set<DistributionStatus> statuses) =>
      statuses.isEmpty
      ? DistributionAccessPolicy.branchVisibleStatuses
      : statuses
            .where(DistributionAccessPolicy.branchVisibleStatuses.contains)
            .toSet();

  @override
  Future<bool> markPosted({
    required String distributionId,
    required DateTime postedAtUtc,
  }) async =>
      await _dao.markPosted(
        distributionId: distributionId,
        postedAtUtc: postedAtUtc,
      ) >
      0;

  @override
  Future<bool> updateDraftNote({
    required String distributionId,
    String? note,
  }) async =>
      await _dao.updateDraftNote(distributionId: distributionId, note: note) >
      0;

  // --- lines ----------------------------------------------------------------

  @override
  Future<List<DistributionLineReference>> lineReferences(
    String distributionId,
  ) async => (await _dao.linesOf(
    distributionId,
  )).map(_toReference).toList(growable: false);

  @override
  Future<DistributionLineReference?> lineReferenceById(String lineId) async {
    final row = await _dao.lineById(lineId);
    return row == null ? null : _toReference(row);
  }

  @override
  Future<List<String>> lineIds(String distributionId) =>
      _dao.lineIdsOf(distributionId);

  @override
  Future<List<String>> lineRoomIds(String distributionId) =>
      _dao.lineRoomIdsOf(distributionId);

  @override
  Future<List<String>> lineItemIds(String distributionId) =>
      _dao.lineItemIdsOf(distributionId);

  @override
  Future<List<String>> lineBatchIds(String distributionId) =>
      _dao.lineBatchIdsOf(distributionId);

  @override
  Future<void> addAllocations({
    required String distributionId,
    required List<DistributionAllocation> allocations,
  }) async {
    if (allocations.isEmpty) return;
    final now = DateTime.now().toUtc();
    try {
      await _dao.insertLines(
        allocations
            .map(
              (allocation) => DistributionLinesCompanion.insert(
                distributionId: distributionId,
                roomId: allocation.roomId,
                itemId: allocation.itemId,
                batchId: Value(allocation.batchId),
                qty: allocation.qty.milliUnits,
                fefoOverrideReason: Value(allocation.fefoOverrideReason),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            )
            .toList(growable: false),
      );
    } on Object catch (error) {
      // The partial unique indexes' last line of defence. Two devices can both read
      // "this position is free" and both insert; the index lets exactly one through,
      // and the loser must see a business failure rather than a driver error.
      if (_isPositionUniqueViolation(error)) {
        final first = allocations.first;
        throw DuplicateDistributionLineFailure(
          'Barang ini sudah ada pada ruangan tersebut di distribusi ini. '
          'Ubah jumlah baris yang ada, bukan menambah baris baru.',
          distributionId: distributionId,
          roomId: first.roomId,
          itemId: first.itemId,
          batchId: first.batchId,
        );
      }
      rethrow;
    }
  }

  /// Whether [error] is one of the two partial unique indexes on
  /// `distribution_lines` firing.
  ///
  /// Matched on the message rather than on an exception type, because the type comes
  /// from the sqlite3 package and importing it here would drag the native driver into
  /// a repository that otherwise only knows drift. Both index names and the column
  /// list are accepted, and anything else is rethrown untouched rather than swallowed
  /// as "already exists".
  static bool _isPositionUniqueViolation(Object error) {
    final message = error.toString().toLowerCase();
    if (!message.contains('unique')) return false;
    return message.contains('idx_distribution_lines_batched') ||
        message.contains('idx_distribution_lines_unbatched') ||
        message.contains('distribution_lines.room_id');
  }

  @override
  Future<bool> updateDraftLine({
    required String distributionId,
    required String lineId,
    required Quantity qty,
    String? batchId,
    String? fefoOverrideReason,
  }) async {
    try {
      return await _dao.updateDraftLine(
            distributionId: distributionId,
            lineId: lineId,
            qtyMilliUnits: qty.milliUnits,
            batchId: batchId,
            fefoOverrideReason: fefoOverrideReason,
          ) >
          0;
    } on Object catch (error) {
      // Moving a line onto a batch the same position already holds collides with the
      // partial unique index. The branch head has to merge the two rather than
      // duplicate one.
      if (_isPositionUniqueViolation(error)) {
        throw DuplicateDistributionLineFailure(
          'Alokasi batch ini sudah ada pada ruangan tersebut. Gabungkan '
          'jumlahnya pada baris yang sudah ada.',
          distributionId: distributionId,
          roomId: '',
          itemId: '',
          batchId: batchId,
        );
      }
      rethrow;
    }
  }

  @override
  Future<bool> removeDraftLine({
    required String distributionId,
    required String lineId,
  }) async =>
      await _dao.softDeleteDraftLine(
        distributionId: distributionId,
        lineId: lineId,
      ) >
      0;

  // --- branch-store stock ---------------------------------------------------

  @override
  Future<List<DistributionStockItem>> searchBranchStock({
    required String branchStoreLocationId,
    required DateTime nowUtc,
    String searchQuery = '',
    String? categoryId,
    int limit = 8,
  }) async {
    final rows = await _dao.branchStoreStock(
      locationId: branchStoreLocationId,
      searchQuery: searchQuery,
      categoryId: categoryId,
    );
    return _toStockItems(rows, nowUtc: nowUtc, limit: limit);
  }

  @override
  Stream<List<DistributionStockItem>> watchBranchStock({
    required String branchStoreLocationId,
    required DateTime nowUtc,
    String searchQuery = '',
    String? categoryId,
    int limit = 8,
  }) => _dao
      .watchBranchStoreStock(
        locationId: branchStoreLocationId,
        searchQuery: searchQuery,
        categoryId: categoryId,
      )
      .map((rows) => _toStockItems(rows, nowUtc: nowUtc, limit: limit));

  @override
  Future<DistributionStockItem?> branchStockFor({
    required String branchStoreLocationId,
    required String itemId,
    required DateTime nowUtc,
    bool activeItemsOnly = true,
  }) async {
    final rows = await _dao.branchStoreStock(
      locationId: branchStoreLocationId,
      itemId: itemId,
      activeItemsOnly: activeItemsOnly,
    );
    final items = _toStockItems(
      rows,
      nowUtc: nowUtc,
      limit: 1,
      // An item whose only stock has expired still has to be *reportable* here: the
      // add path needs to say "all of it is expired" rather than "no such item", and
      // G-E7 says that stock leaves through disposal instead.
      keepUnusable: true,
    );
    return items.isEmpty ? null : items.single;
  }

  /// Groups balance rows into one row per item.
  ///
  /// The expiry split happens here rather than in SQL, and deliberately: `expiry_date`
  /// is ISO-8601 TEXT (`build.yaml`), so a SQL comparison would compare characters
  /// rather than dates — the trap schema v4 removed from `stock_opnames`.
  /// [DistributionExpiryPolicy] answers it on civil dates instead.
  ///
  /// [limit] is applied to **items**, after the per-item totals are summed: capping
  /// rows would cut a multi-batch item off mid-way and report a total lower than the
  /// store actually holds.
  List<DistributionStockItem> _toStockItems(
    List<BranchStoreStockRow> rows, {
    required DateTime nowUtc,
    required int limit,
    bool keepUnusable = false,
  }) {
    final byItem = <String, List<BranchStoreStockRow>>{};
    final order = <String>[];
    for (final row in rows) {
      if (byItem
          .putIfAbsent(row.item.id, () => <BranchStoreStockRow>[])
          .isEmpty) {
        order.add(row.item.id);
      }
      byItem[row.item.id]!.add(row);
    }

    final items = <DistributionStockItem>[];
    for (final itemId in order) {
      final group = byItem[itemId]!;
      final item = group.first.item;

      final candidates = <DistributionBatchCandidate>[];
      var unbatched = Quantity.zero();
      for (final row in group) {
        final batch = row.batch;
        final qty = Quantity.fromMilliUnits(row.qtyOnHandMilliUnits);
        if (batch == null) {
          unbatched += qty;
          continue;
        }
        candidates.add(
          DistributionBatchCandidate(
            batchId: batch.id,
            batchNo: batch.batchNo,
            // A civil date is read back verbatim, never timezone converted (T-9).
            expiryDate: DateOnly.from(batch.expiryDate),
            availableQty: qty,
            isArchived: batch.deletedAt != null,
          ),
        );
      }

      final usable = DistributionExpiryPolicy.usableCandidates(
        candidates: candidates,
        nowUtc: nowUtc,
      );
      final expired = DistributionExpiryPolicy.expiredCandidates(
        candidates: candidates,
        nowUtc: nowUtc,
      );
      // An expiry-tracked item distributes per batch (G-E2); one without expiry has a
      // single balance and no batch picker. Reading the wrong one is how an item
      // silently reports zero.
      final available = item.hasExpiry
          ? Quantity.sum(usable.map((candidate) => candidate.availableQty))
          : unbatched;

      if (!available.isPositive && !keepUnusable) continue;

      items.add(
        DistributionStockItem(
          itemId: item.id,
          sku: item.sku,
          itemName: item.name,
          categoryId: item.categoryId,
          unit: item.unit,
          hasExpiry: item.hasExpiry,
          expiryAlertDays: item.expiryAlertDays,
          availableQty: available,
          candidates: item.hasExpiry ? usable : const [],
          expiredCandidates: item.hasExpiry ? expired : const [],
        ),
      );
      if (items.length >= limit) break;
    }
    return List<DistributionStockItem>.unmodifiable(items);
  }

  // --- rooms ----------------------------------------------------------------

  @override
  Future<List<MasterRoom>> branchRooms(String branchId) async =>
      (await _dao.activeRoomsOfBranch(
        branchId,
      )).map(_toRoom).toList(growable: false);

  @override
  Stream<List<MasterRoom>> watchBranchRooms(String branchId) => _dao
      .watchActiveRoomsOfBranch(branchId)
      .map((rows) => rows.map(_toRoom).toList(growable: false));

  @override
  Future<MasterRoom?> historicalRoomById(String roomId) async {
    final row = await _dao.roomById(roomId);
    return row == null ? null : _toRoom(row);
  }
}

Distribution _toDistribution(DistributionRow row) => Distribution(
  id: row.id,
  docNumber: row.docNumber,
  branchId: row.branchId,
  distributedBy: row.distributedBy,
  status: row.status,
  postedAt: row.postedAt,
  note: row.note,
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

/// The joins behind [DistributionWithContext] filter neither `is_active` nor
/// `deleted_at`, which is what keeps a posted distribution visible after its branch
/// or the branch head who posted it is retired. The flags below turn that fact into
/// something the screens can label, rather than into a document that quietly
/// disappears from the branch's list (§32).
DistributionSummary _toSummary(DistributionWithContext row) =>
    DistributionSummary(
      distribution: _toDistribution(row.distribution),
      branchCode: row.branch.code,
      branchName: row.branch.name,
      branchAddress: row.branch.address,
      distributedByName: row.distributedBy.fullName,
      lineCount: row.lineCount,
      roomCount: row.roomCount,
      overrideCount: row.overrideCount,
      branchIsHistorical: _isHistorical(
        row.branch.isActive,
        row.branch.deletedAt,
      ),
      distributedByIsHistorical: _isHistorical(
        row.distributedBy.isActive,
        row.distributedBy.deletedAt,
      ),
    );

DistributionLine _toLine(DistributionLineWithDetails row) => DistributionLine(
  id: row.line.id,
  distributionId: row.line.distributionId,
  roomId: row.line.roomId,
  roomCode: row.room.code,
  roomName: row.room.name,
  itemId: row.line.itemId,
  sku: row.item.sku,
  itemName: row.item.name,
  categoryId: row.item.categoryId,
  unit: row.item.unit,
  hasExpiry: row.item.hasExpiry,
  expiryAlertDays: row.item.expiryAlertDays,
  qty: Quantity.fromMilliUnits(row.line.qty),
  batchId: row.line.batchId,
  batchNo: row.batch?.batchNo,
  // A civil date is read back verbatim, never timezone converted (T-9).
  expiryDate: row.batch == null ? null : DateOnly.from(row.batch!.expiryDate),
  fefoOverrideReason: row.line.fefoOverrideReason,
  roomIsHistorical: _isHistorical(row.room.isActive, row.room.deletedAt),
  itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
  batchIsHistorical: row.batch != null && row.batch!.deletedAt != null,
);

DistributionLineReference _toReference(DistributionLineRow row) =>
    DistributionLineReference(
      id: row.id,
      distributionId: row.distributionId,
      roomId: row.roomId,
      itemId: row.itemId,
      batchId: row.batchId,
      qty: Quantity.fromMilliUnits(row.qty),
      fefoOverrideReason: row.fefoOverrideReason,
    );

MasterRoom _toRoom(Room row) => MasterRoom(
  id: row.id,
  branchId: row.branchId,
  code: row.code,
  name: row.name,
  isActive: row.isActive,
  isArchived: row.deletedAt != null,
);
