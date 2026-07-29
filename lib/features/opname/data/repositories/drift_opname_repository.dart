import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/opname_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/opname_models.dart';
import '../../domain/repositories/opname_repository.dart';

/// Translates between the database boundary (milli-unit integers, drift rows)
/// and the Stok Opname domain.
///
/// This is the only file in the feature allowed to touch `Quantity.milliUnits`
/// or a generated drift class (Q-4) — the use cases, providers and widgets
/// above it see nothing but domain models.
class DriftOpnameRepository implements OpnameRepository {
  DriftOpnameRepository(this._dao);

  final OpnameDao _dao;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.transaction(action);

  @override
  Future<StockOpname> createDraft({
    required String docNumber,
    required String branchId,
    required String roomId,
    required int periodYear,
    required int periodWeek,
    required String countedBy,
    required List<StockOpnameLineDraft> lines,
  }) {
    // Header and snapshot are written together: a half-created document would
    // report a system quantity of nothing for positions that do hold stock.
    return _dao.transaction(() async {
      final StockOpnameRow header;
      try {
        header = await _dao.insertHeader(
          StockOpnamesCompanion.insert(
            docNumber: docNumber,
            branchId: branchId,
            roomId: roomId,
            periodYear: periodYear,
            periodWeek: periodWeek,
            countedBy: countedBy,
          ),
        );
      } on Object {
        // The weekly unique index is the last guard behind G-O1, and it speaks
        // SQLite, not Indonesian. Rather than matching on a driver-specific
        // error code, ask the question the constraint was protecting: is there
        // now a document for this room and week? If so, that is what happened,
        // whatever the driver called it.
        final existing = await _dao.findForRoomAndPeriod(
          roomId: roomId,
          periodYear: periodYear,
          periodWeek: periodWeek,
        );
        if (existing == null) rethrow;

        throw StockOpnameAlreadyExistsFailure(
          'Stok opname untuk ruangan ini pada minggu '
          '$periodYear-W${periodWeek.toString().padLeft(2, '0')} sudah ada '
          '(${existing.docNumber}).',
          roomId: roomId,
          periodYear: periodYear,
          periodWeek: periodWeek,
          existingOpnameId: existing.id,
        );
      }

      await _dao.insertLines(
        lines
            .map(
              (line) => StockOpnameLinesCompanion.insert(
                opnameId: header.id,
                itemId: line.itemId,
                batchId: Value(line.batchId),
                systemQty: line.systemQty.milliUnits,
                countedQty: line.countedQty.milliUnits,
                note: Value(line.note),
              ),
            )
            .toList(growable: false),
      );

      return _toOpname(header);
    });
  }

  @override
  Future<StockOpname?> getById(String opnameId) async {
    final row = await _dao.headerById(opnameId);
    return row == null ? null : _toOpname(row);
  }

  @override
  Future<StockOpnameDetail?> getDetail(String opnameId) =>
      _getDetail(opnameId, branchId: null);

  @override
  Stream<StockOpnameDetail?> watchDetail(String opnameId) =>
      _watchDetail(opnameId, branchId: null);

  @override
  Future<StockOpnameDetail?> getDetailForBranch({
    required String opnameId,
    required String branchId,
  }) => _getDetail(opnameId, branchId: branchId);

  @override
  Stream<StockOpnameDetail?> watchDetailForBranch({
    required String opnameId,
    required String branchId,
  }) => _watchDetail(opnameId, branchId: branchId);

  @override
  Future<StockOpnameAccessScope?> findAccessScope({
    required String opnameId,
    required String branchId,
  }) async {
    final row = await _dao.accessScope(opnameId: opnameId, branchId: branchId);
    if (row == null) return null;
    return StockOpnameAccessScope(
      opnameId: row.opnameId,
      branchId: row.branchId,
      status: row.status,
      countedBy: row.countedBy,
    );
  }

  Future<StockOpnameDetail?> _getDetail(
    String opnameId, {
    required String? branchId,
  }) async {
    final context = await _dao.summaryById(opnameId, branchId: branchId);
    if (context == null) return null;
    final lines = await _dao.detailLines(opnameId);
    return StockOpnameDetail(
      summary: _toSummary(context),
      lines: lines.map(_toLine).toList(growable: false),
    );
  }

  Stream<StockOpnameDetail?> _watchDetail(
    String opnameId, {
    required String? branchId,
  }) {
    // Two streams rather than one wide join: the header changes on every
    // status transition while the lines change on every keystroke that is
    // saved, and combining them keeps either from re-emitting the other's
    // rows.
    //
    // The header query is also what carries the branch scope, and the lines
    // are fetched only after it produced a row. A document outside [branchId]
    // therefore costs one predicate in SQLite and never reaches a second
    // query — its lines are not read even to be discarded.
    return _dao.watchSummaryById(opnameId, branchId: branchId).asyncMap((
      context,
    ) async {
      if (context == null) return null;
      final lines = await _dao.detailLines(opnameId);
      return StockOpnameDetail(
        summary: _toSummary(context),
        lines: lines.map(_toLine).toList(growable: false),
      );
    });
  }

  @override
  Future<List<StockOpnameSummary>> list(StockOpnameFilter filter) async {
    final rows = await _dao.listOpnames(
      branchId: filter.branchId,
      roomId: filter.roomId,
      countedBy: filter.countedBy,
      statuses: filter.statuses,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Stream<List<StockOpnameSummary>> watchList(StockOpnameFilter filter) {
    return _dao
        .watchOpnames(
          branchId: filter.branchId,
          roomId: filter.roomId,
          countedBy: filter.countedBy,
          statuses: filter.statuses,
        )
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  @override
  Future<StockOpname?> findForRoomAndPeriod({
    required String roomId,
    required int periodYear,
    required int periodWeek,
  }) async {
    final row = await _dao.findForRoomAndPeriod(
      roomId: roomId,
      periodYear: periodYear,
      periodWeek: periodWeek,
    );
    return row == null ? null : _toOpname(row);
  }

  @override
  Future<StockOpnameLine?> lineById(String lineId) async {
    final row = await _dao.lineById(lineId);
    if (row == null) return null;
    return _hydrateLine(row);
  }

  @override
  Future<StockOpnameLine?> findLine({
    required String opnameId,
    required String itemId,
    String? batchId,
  }) async {
    final row = await _dao.findLine(
      opnameId: opnameId,
      itemId: itemId,
      batchId: batchId,
    );
    if (row == null) return null;
    return _hydrateLine(row);
  }

  @override
  Future<bool> updateDraftLine({
    required String lineId,
    required Quantity countedQty,
    String? note,
  }) async {
    final affected = await _dao.updateDraftLine(
      lineId: lineId,
      countedQtyMilliUnits: countedQty.milliUnits,
      note: note,
    );
    return affected > 0;
  }

  @override
  Future<StockOpnameLine?> addDraftLine({
    required String opnameId,
    required String itemId,
    String? batchId,
    required Quantity systemQty,
    required Quantity countedQty,
    String? note,
  }) async {
    final row = await _dao.insertDraftLine(
      opnameId: opnameId,
      line: StockOpnameLinesCompanion.insert(
        opnameId: opnameId,
        itemId: itemId,
        batchId: Value(batchId),
        systemQty: systemQty.milliUnits,
        countedQty: countedQty.milliUnits,
        note: Value(note),
      ),
    );
    if (row == null) return null;
    return _hydrateLine(row);
  }

  @override
  Future<bool> removeDraftLine(String lineId) async =>
      await _dao.softDeleteDraftLine(lineId) > 0;

  @override
  Future<bool> submit({
    required String opnameId,
    required DateTime submittedAtUtc,
  }) async {
    final affected = await _dao.transitionStatus(
      opnameId: opnameId,
      from: StockOpnameStatus.draft,
      to: StockOpnameStatus.submitted,
      submittedAt: submittedAtUtc,
    );
    return affected > 0;
  }

  @override
  Future<bool> markReviewed({
    required String opnameId,
    required String reviewedBy,
    required DateTime reviewedAtUtc,
  }) async {
    final affected = await _dao.transitionStatus(
      opnameId: opnameId,
      from: StockOpnameStatus.submitted,
      to: StockOpnameStatus.reviewed,
      reviewedAt: reviewedAtUtc,
      reviewedBy: reviewedBy,
    );
    return affected > 0;
  }

  @override
  Future<bool> removeDraft(String opnameId) async =>
      await _dao.softDeleteDraft(opnameId) > 0;

  @override
  Future<List<MasterItem>> searchAddableItems({
    required String query,
    String? categoryId,
    int limit = 8,
  }) async {
    final rows = await _dao.searchAddableItems(
      query: query,
      categoryId: categoryId,
      limit: limit,
    );
    return rows.map(_toItem).toList(growable: false);
  }

  @override
  Future<int> countDifferenceLines(String opnameId) =>
      _dao.countDifferenceLines(opnameId);

  @override
  Future<List<String>> lineItemIds(String opnameId) =>
      _dao.lineItemIds(opnameId);

  /// Re-reads a bare line row through the joined query so the returned domain
  /// model always carries its item and batch details.
  Future<StockOpnameLine?> _hydrateLine(StockOpnameLineRow row) async {
    final lines = await _dao.detailLines(row.opnameId);
    for (final candidate in lines) {
      if (candidate.line.id == row.id) return _toLine(candidate);
    }
    return null;
  }
}

StockOpname _toOpname(StockOpnameRow row) => StockOpname(
  id: row.id,
  docNumber: row.docNumber,
  branchId: row.branchId,
  roomId: row.roomId,
  periodYear: row.periodYear,
  periodWeek: row.periodWeek,
  countedBy: row.countedBy,
  status: row.status,
  submittedAt: row.submittedAt,
  reviewedAt: row.reviewedAt,
  reviewedBy: row.reviewedBy,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  syncStatus: row.syncStatus,
);

/// The joins behind [OpnameWithContext] filter neither `is_active` nor
/// `deleted_at`, which is what keeps a submitted document visible after its
/// room or branch is retired (§7.6). The flags below turn that fact into
/// something the screens can label, rather than into a document that quietly
/// disappears from a list.
StockOpnameSummary _toSummary(OpnameWithContext row) => StockOpnameSummary(
  opname: _toOpname(row.opname),
  roomCode: row.room.code,
  roomName: row.room.name,
  branchName: row.branch.name,
  countedByName: row.countedBy.fullName,
  reviewedByName: row.reviewedBy?.fullName,
  lineCount: row.lineCount,
  differenceLineCount: row.differenceLineCount,
  branchIsHistorical: _isHistorical(row.branch.isActive, row.branch.deletedAt),
  roomIsHistorical: _isHistorical(row.room.isActive, row.room.deletedAt),
  countedByIsHistorical: _isHistorical(
    row.countedBy.isActive,
    row.countedBy.deletedAt,
  ),
);

/// What "historic" means, in one place.
///
/// Deactivated (G-A4) and soft-deleted (G-A5) are separate states with the same
/// consequence for a document that already references the row: it stays valid,
/// stays readable and stays completable, but the row can no longer be picked
/// for anything new. Spelling the disjunction out at each call site is how the
/// four copies eventually stop agreeing.
bool _isHistorical(bool isActive, DateTime? deletedAt) =>
    !isActive || deletedAt != null;

StockOpnameLine _toLine(OpnameLineWithDetails row) => StockOpnameLine(
  id: row.line.id,
  opnameId: row.line.opnameId,
  itemId: row.line.itemId,
  batchId: row.line.batchId,
  sku: row.item.sku,
  itemName: row.item.name,
  categoryId: row.item.categoryId,
  unit: row.item.unit,
  hasExpiry: row.item.hasExpiry,
  expiryAlertDays: row.item.expiryAlertDays,
  batchNo: row.batch?.batchNo,
  // `expiry_date` is a civil date: its calendar fields are kept verbatim (T-9).
  expiryDate: row.batch == null ? null : DateOnly.from(row.batch!.expiryDate),
  systemQty: Quantity.fromMilliUnits(row.line.systemQty),
  countedQty: Quantity.fromMilliUnits(row.line.countedQty),
  // Read from the generated column rather than recomputed, so a mismatch
  // between the two would surface instead of being silently papered over.
  difference: Quantity.fromMilliUnits(row.line.difference),
  note: row.line.note,
  itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
);

MasterItem _toItem(Item row) => MasterItem(
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
