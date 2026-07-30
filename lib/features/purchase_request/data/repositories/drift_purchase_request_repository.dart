import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/purchase_request_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/purchase_request_models.dart';
import '../../domain/repositories/purchase_request_repository.dart';
import '../../domain/services/suggested_purchase_request_calculator.dart';

/// Translates between the database boundary (milli-unit integers, drift rows) and
/// the Purchase Request domain.
///
/// This is the only file in the feature allowed to touch `Quantity.milliUnits` or
/// a generated drift class (Q-4) — the use cases, providers and widgets above it
/// see nothing but domain models.
class DriftPurchaseRequestRepository implements PurchaseRequestRepository {
  DriftPurchaseRequestRepository(this._dao);

  final PurchaseRequestDao _dao;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.runInTransaction(action);

  @override
  Future<PurchaseRequest> createDraft({
    required String docNumber,
    required String branchId,
    required String requestedBy,
    DateTime? neededDate,
    String? note,
    required List<String> opnameIds,
    required List<PurchaseRequestLineDraft> lines,
  }) {
    // Header, citations and lines are written together: a half-created document
    // would either ask for items with no evidence behind them or cite counts it
    // does not act on.
    return _dao.runInTransaction(() async {
      // Deliberately *not* wrapped in the active-order translation `submit` uses. A
      // `draft` sits outside the `(branch_id) WHERE status IN ('submitted',
      // 'processing')` index, so that constraint cannot fire here — and translating
      // whatever else went wrong into "this branch already has an active request"
      // would report a rule that had nothing to do with the failure.
      final header = await _dao.insertHeader(
        PurchaseRequestsCompanion.insert(
          docNumber: docNumber,
          branchId: branchId,
          requestedBy: requestedBy,
          // A civil date is written verbatim — no timezone conversion (T-9).
          neededDate: Value(
            neededDate == null ? null : DateOnly.from(neededDate),
          ),
          note: Value(note),
        ),
      );

      await _dao.insertOpnameLinks(
        opnameIds
            .map(
              (opnameId) => PurchaseRequestOpnamesCompanion.insert(
                prId: header.id,
                opnameId: opnameId,
              ),
            )
            .toList(growable: false),
      );

      await _dao.insertLines(
        lines
            .map(
              (line) => PurchaseRequestLinesCompanion.insert(
                prId: header.id,
                itemId: line.itemId,
                suggestedQty: line.suggestedQty.milliUnits,
                requestedQty: line.requestedQty.milliUnits,
                note: Value(line.note),
              ),
            )
            .toList(growable: false),
      );

      return _toRequest(header);
    });
  }

  /// Turns a constraint violation on the active-order index into the failure the
  /// rule is about.
  ///
  /// The index speaks SQLite, not Indonesian, and matching on a driver-specific
  /// error code would break the day the driver changes. Instead the question the
  /// constraint was protecting is asked directly: does this branch now have an
  /// active request? If so, that is what happened, whatever the driver called it.
  /// If not, the original error is something else and the caller rethrows it
  /// untouched.
  Future<void> _rethrowAsActiveRequestFailure(String branchId) async {
    final active = await _dao.activeRequestForBranch(branchId);
    if (active == null) return;

    throw PurchaseRequestAlreadyActiveFailure(
      'Cabang ini masih memiliki Purchase Request aktif '
      '(${active.docNumber}). Selesaikan atau batalkan permintaan tersebut '
      'sebelum mengirim yang baru.',
      branchId: branchId,
      activePrId: active.id,
    );
  }

  @override
  Future<PurchaseRequest?> getById(String prId) async {
    final row = await _dao.headerById(prId);
    return row == null ? null : _toRequest(row);
  }

  @override
  Future<PurchaseRequestDetail?> getDetail(String prId) =>
      _getDetail(prId, branchId: null);

  @override
  Future<PurchaseRequestDetail?> getDetailForBranch({
    required String prId,
    required String branchId,
  }) => _getDetail(prId, branchId: branchId);

  @override
  Stream<PurchaseRequestDetail?> watchDetailForBranch({
    required String prId,
    required String branchId,
  }) => _watchDetail(prId, branchId: branchId);

  @override
  Future<PurchaseRequestDetail?> getDetailForWarehouse(String prId) =>
      _getDetail(prId, branchId: null);

  @override
  Stream<PurchaseRequestDetail?> watchDetailForWarehouse(String prId) =>
      _watchDetail(prId, branchId: null);

  @override
  Future<PurchaseRequestAccessScope?> findAccessScope({
    required String prId,
    String? branchId,
  }) async {
    final row = await _dao.accessScope(prId: prId, branchId: branchId);
    if (row == null) return null;
    return PurchaseRequestAccessScope(
      prId: row.prId,
      branchId: row.branchId,
      status: row.status,
      requestedBy: row.requestedBy,
    );
  }

  Future<PurchaseRequestDetail?> _getDetail(
    String prId, {
    required String? branchId,
  }) async {
    final context = await _dao.summaryById(prId, branchId: branchId);
    if (context == null) return null;
    return PurchaseRequestDetail(
      summary: _toSummary(context),
      lines: (await _dao.detailLines(
        prId,
      )).map(_toLine).toList(growable: false),
      opnames: (await _dao.linkedOpnames(
        prId,
      )).map(_toLinkedOpname).toList(growable: false),
    );
  }

  Stream<PurchaseRequestDetail?> _watchDetail(
    String prId, {
    required String? branchId,
  }) {
    // The header query carries the branch scope, and the children are fetched
    // only after it produced a row. A document outside [branchId] therefore costs
    // one predicate in SQLite and never reaches a second query — its lines and
    // citations are not read even to be discarded.
    return _dao.watchSummaryById(prId, branchId: branchId).asyncMap((
      context,
    ) async {
      if (context == null) return null;
      return PurchaseRequestDetail(
        summary: _toSummary(context),
        lines: (await _dao.detailLines(
          prId,
        )).map(_toLine).toList(growable: false),
        opnames: (await _dao.linkedOpnames(
          prId,
        )).map(_toLinkedOpname).toList(growable: false),
      );
    });
  }

  @override
  Future<List<PurchaseRequestSummary>> list(
    PurchaseRequestFilter filter,
  ) async {
    final rows = await _dao.listRequests(
      branchId: filter.branchId,
      statuses: filter.statuses,
      searchQuery: filter.searchQuery,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Stream<List<PurchaseRequestSummary>> watchList(PurchaseRequestFilter filter) {
    return _dao
        .watchRequests(
          branchId: filter.branchId,
          statuses: filter.statuses,
          searchQuery: filter.searchQuery,
        )
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  @override
  Stream<List<PurchaseRequestSummary>> watchForBranch({
    required String branchId,
    Set<PurchaseRequestStatus> statuses = const {},
  }) =>
      watchList(PurchaseRequestFilter(branchId: branchId, statuses: statuses));

  @override
  Stream<List<PurchaseRequestSummary>> watchWarehouseQueue({
    Set<PurchaseRequestStatus> statuses = warehouseQueueStatuses,
    String? branchId,
    String? searchQuery,
  }) => watchList(
    PurchaseRequestFilter(
      branchId: branchId,
      statuses: statuses,
      searchQuery: searchQuery ?? '',
    ),
  );

  @override
  Future<PurchaseRequest?> activeRequestForBranch(String branchId) async {
    final row = await _dao.activeRequestForBranch(branchId);
    return row == null ? null : _toRequest(row);
  }

  @override
  Future<List<PurchaseRequestOpnameReference>> eligibleOpnames({
    required String branchId,
    required List<({int year, int week})> periods,
  }) async {
    final rows = await _dao.eligibleOpnames(
      branchId: branchId,
      periods: periods,
    );
    return rows.map(_toEligibleOpname).toList(growable: false);
  }

  @override
  Future<PurchaseRequestOpnameReference?> opnameReferenceById(
    String opnameId,
  ) async {
    final row = await _dao.opnameReferenceById(opnameId);
    return row == null ? null : _toEligibleOpname(row);
  }

  @override
  Future<List<PurchaseRequestOpnameReference>> linkedOpnames(
    String prId,
  ) async {
    final rows = await _dao.linkedOpnames(prId);
    return rows.map(_toLinkedOpname).toList(growable: false);
  }

  @override
  Future<List<String>> linkedOpnameIds(String prId) =>
      _dao.linkedOpnameIds(prId);

  @override
  Future<List<String>> lineItemIds(String prId) => _dao.lineItemIds(prId);

  @override
  Future<List<OpnameCountedPosition>> countedPositionsOf(
    String opnameId,
  ) async {
    final rows = await _dao.opnameLinesOf(opnameId);
    return rows
        .map(
          (row) => (
            itemId: row.itemId,
            countedQty: Quantity.fromMilliUnits(row.countedQty),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<PurchaseRequestLine?> lineById(String lineId) async {
    final row = await _dao.lineById(lineId);
    if (row == null) return null;
    return _hydrateLine(row);
  }

  @override
  Future<PurchaseRequestLine?> findLineByItem({
    required String prId,
    required String itemId,
  }) async {
    final row = await _dao.findLineByItem(prId: prId, itemId: itemId);
    if (row == null) return null;
    return _hydrateLine(row);
  }

  @override
  Future<bool> updateDraftHeader({
    required String prId,
    DateTime? neededDate,
    String? note,
  }) async {
    final affected = await _dao.updateDraftHeader(
      prId: prId,
      neededDate: neededDate == null ? null : DateOnly.from(neededDate),
      note: note,
    );
    return affected > 0;
  }

  @override
  Future<bool> updateDraftLine({
    required String lineId,
    required Quantity requestedQty,
    String? note,
  }) async {
    final affected = await _dao.updateDraftLine(
      lineId: lineId,
      requestedQtyMilliUnits: requestedQty.milliUnits,
      note: note,
    );
    return affected > 0;
  }

  @override
  Future<PurchaseRequestLine?> addDraftLine({
    required String prId,
    required String itemId,
    required Quantity suggestedQty,
    required Quantity requestedQty,
    String? note,
  }) async {
    final row = await _dao.insertDraftLine(
      prId: prId,
      line: PurchaseRequestLinesCompanion.insert(
        prId: prId,
        itemId: itemId,
        suggestedQty: suggestedQty.milliUnits,
        requestedQty: requestedQty.milliUnits,
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
  Future<void> replaceOpnameLinksAndSuggestions({
    required String prId,
    required List<String> opnameIds,
    required List<PurchaseRequestLineReconciliation> lines,
  }) {
    return _dao.runInTransaction(() async {
      // Citations first. Links that survive are left alone rather than deleted
      // and re-created, so a link's id and `created_at` stay stable — the
      // partial unique index would also refuse an insert while the old live row
      // is still there.
      final desired = opnameIds.toSet();
      final existing = await _dao.opnameLinksOf(prId);
      final kept = <String>{};

      for (final link in existing) {
        if (desired.contains(link.opnameId)) {
          kept.add(link.opnameId);
        } else {
          await _dao.softDeleteDraftOpnameLink(link.id);
        }
      }
      for (final opnameId in desired.difference(kept)) {
        await _dao.insertDraftOpnameLink(
          prId: prId,
          link: PurchaseRequestOpnamesCompanion.insert(
            prId: prId,
            opnameId: opnameId,
          ),
        );
      }

      // Then the arithmetic. Existing lines are updated in two guarded steps
      // rather than one: the suggestion writer is a separate method precisely so
      // no editor path can reach it, and using it here is what keeps that true.
      for (final line in lines) {
        final lineId = line.lineId;
        if (lineId == null) {
          await _dao.insertDraftLine(
            prId: prId,
            line: PurchaseRequestLinesCompanion.insert(
              prId: prId,
              itemId: line.itemId,
              suggestedQty: line.suggestedQty.milliUnits,
              requestedQty: line.requestedQty.milliUnits,
              note: Value(line.note),
            ),
          );
          continue;
        }

        await _dao.updateDraftLineSuggestion(
          lineId: lineId,
          suggestedQtyMilliUnits: line.suggestedQty.milliUnits,
        );
        await _dao.updateDraftLine(
          lineId: lineId,
          requestedQtyMilliUnits: line.requestedQty.milliUnits,
          note: line.note,
        );
      }
    });
  }

  @override
  Future<bool> submit({
    required String prId,
    required DateTime submittedAtUtc,
  }) async {
    final header = await _dao.headerById(prId);
    try {
      return await _dao.submit(prId: prId, submittedAtUtc: submittedAtUtc) > 0;
    } on Object {
      // Two devices submitting at the same moment: the branch's partial unique
      // index lets exactly one through, and the loser lands here.
      if (header != null) {
        await _rethrowAsActiveRequestFailure(header.branchId);
      }
      rethrow;
    }
  }

  @override
  Future<bool> cancel({
    required String prId,
    required PurchaseRequestStatus from,
    required String cancelledBy,
    required DateTime cancelledAtUtc,
    required String reason,
  }) async {
    final affected = await _dao.cancel(
      prId: prId,
      from: from,
      cancelledBy: cancelledBy,
      cancelledAtUtc: cancelledAtUtc,
      reason: reason,
    );
    return affected > 0;
  }

  @override
  Future<bool> markProcessing({
    required String prId,
    required String processedBy,
    required DateTime processingAtUtc,
  }) async {
    final affected = await _dao.markProcessing(
      prId: prId,
      processedBy: processedBy,
      processingAtUtc: processingAtUtc,
    );
    return affected > 0;
  }

  @override
  Future<bool> reject({
    required String prId,
    required String rejectedBy,
    required DateTime rejectedAtUtc,
    required String reason,
  }) async {
    final affected = await _dao.reject(
      prId: prId,
      rejectedBy: rejectedBy,
      rejectedAtUtc: rejectedAtUtc,
      reason: reason,
    );
    return affected > 0;
  }

  @override
  Future<bool> removeDraft(String prId) async =>
      await _dao.softDeleteDraft(prId) > 0;

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

  /// Re-reads a bare line row through the joined query so the returned domain
  /// model always carries its item details.
  Future<PurchaseRequestLine?> _hydrateLine(PurchaseRequestLineRow row) async {
    final lines = await _dao.detailLines(row.prId);
    for (final candidate in lines) {
      if (candidate.line.id == row.id) return _toLine(candidate);
    }
    return null;
  }
}

PurchaseRequest _toRequest(PurchaseRequestRow row) => PurchaseRequest(
  id: row.id,
  docNumber: row.docNumber,
  branchId: row.branchId,
  requestedBy: row.requestedBy,
  status: row.status,
  // A civil date is read back verbatim, never timezone converted (T-9).
  neededDate: row.neededDate == null ? null : DateOnly.from(row.neededDate!),
  note: row.note,
  submittedAt: row.submittedAt,
  processingAt: row.processingAt,
  processedBy: row.processedBy,
  cancelledAt: row.cancelledAt,
  cancelledBy: row.cancelledBy,
  cancelReason: row.cancelReason,
  rejectedAt: row.rejectedAt,
  rejectedBy: row.rejectedBy,
  rejectReason: row.rejectReason,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  syncStatus: row.syncStatus,
);

/// The joins behind [PurchaseRequestWithContext] filter neither `is_active` nor
/// `deleted_at`, which is what keeps a submitted request visible after its branch
/// or its author is retired. The flags below turn that fact into something the
/// screens can label, rather than into a document that quietly disappears from
/// the warehouse queue.
PurchaseRequestSummary _toSummary(PurchaseRequestWithContext row) =>
    PurchaseRequestSummary(
      request: _toRequest(row.request),
      branchCode: row.branch.code,
      branchName: row.branch.name,
      requestedByName: row.requestedBy.fullName,
      processedByName: row.processedBy?.fullName,
      cancelledByName: row.cancelledBy?.fullName,
      rejectedByName: row.rejectedBy?.fullName,
      lineCount: row.lineCount,
      linkedOpnameCount: row.linkedOpnameCount,
      branchIsHistorical: _isHistorical(
        row.branch.isActive,
        row.branch.deletedAt,
      ),
      requestedByIsHistorical: _isHistorical(
        row.requestedBy.isActive,
        row.requestedBy.deletedAt,
      ),
    );

/// What "historic" means, in one place.
///
/// Deactivated (G-A4) and soft-deleted (G-A5) are separate states with the same
/// consequence for a document that already references the row: it stays valid,
/// stays readable and stays processable, but the row can no longer be picked for
/// anything new.
bool _isHistorical(bool isActive, DateTime? deletedAt) =>
    !isActive || deletedAt != null;

PurchaseRequestLine _toLine(PurchaseRequestLineWithDetails row) =>
    PurchaseRequestLine(
      id: row.line.id,
      prId: row.line.prId,
      itemId: row.line.itemId,
      sku: row.item.sku,
      itemName: row.item.name,
      categoryId: row.item.categoryId,
      unit: row.item.unit,
      suggestedQty: Quantity.fromMilliUnits(row.line.suggestedQty),
      requestedQty: Quantity.fromMilliUnits(row.line.requestedQty),
      note: row.line.note,
      itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
    );

PurchaseRequestOpnameReference _toLinkedOpname(
  PurchaseRequestOpnameWithDetails row,
) => PurchaseRequestOpnameReference(
  linkId: row.link.id,
  opnameId: row.opname.id,
  docNumber: row.opname.docNumber,
  branchId: row.opname.branchId,
  roomId: row.room.id,
  roomCode: row.room.code,
  roomName: row.room.name,
  periodYear: row.opname.periodYear,
  periodWeek: row.opname.periodWeek,
  status: row.opname.status,
  countedByName: row.countedBy.fullName,
  submittedAt: row.opname.submittedAt,
  reviewedAt: row.opname.reviewedAt,
  differenceLineCount: row.differenceLineCount,
  roomIsHistorical: _isHistorical(row.room.isActive, row.room.deletedAt),
  countedByIsHistorical: _isHistorical(
    row.countedBy.isActive,
    row.countedBy.deletedAt,
  ),
);

/// A candidate the branch head has not cited yet — same facts, no link id.
PurchaseRequestOpnameReference _toEligibleOpname(EligibleOpnameRow row) =>
    PurchaseRequestOpnameReference(
      opnameId: row.opname.id,
      docNumber: row.opname.docNumber,
      branchId: row.opname.branchId,
      roomId: row.room.id,
      roomCode: row.room.code,
      roomName: row.room.name,
      periodYear: row.opname.periodYear,
      periodWeek: row.opname.periodWeek,
      status: row.opname.status,
      countedByName: row.countedBy.fullName,
      submittedAt: row.opname.submittedAt,
      reviewedAt: row.opname.reviewedAt,
      differenceLineCount: row.differenceLineCount,
      roomIsHistorical: _isHistorical(row.room.isActive, row.room.deletedAt),
      countedByIsHistorical: _isHistorical(
        row.countedBy.isActive,
        row.countedBy.deletedAt,
      ),
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
