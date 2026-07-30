import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/goods_return_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/goods_return_models.dart';
import '../../domain/repositories/goods_return_repository.dart';
import '../../domain/services/goods_return_access_policy.dart';

/// Translates between the database boundary (milli-unit integers, drift rows) and the
/// Retur Barang domain.
///
/// This is the only file in the feature allowed to touch `Quantity.milliUnits` or a
/// generated drift class (Q-4) — the use cases, providers and widgets above it see
/// nothing but domain models.
///
/// ### Two orderings are re-done here, in Dart
///
/// The DAO orders the eligible queue by `good_receipts.posted_at` and the lists by
/// `goods_returns.created_at`, and both of those are ISO-8601 **TEXT** columns
/// (`build.yaml`) — so SQLite compares characters rather than instants. That is a
/// *stable* order, which is all the SQL promises and all it can. Where chronology is
/// the point (§16: oldest posting first; §29: newest first) this class re-sorts the
/// mapped result on parsed UTC `DateTime`s. It is the same trap schema v4 removed from
/// `stock_opnames`, and the same reason `GoodsReturnFilter` applies date windows here
/// rather than in a `WHERE`.
class DriftGoodsReturnRepository implements GoodsReturnRepository {
  DriftGoodsReturnRepository(this._dao, {DateTime Function()? clock})
    : _clock = clock ?? _defaultClock;

  final GoodsReturnDao _dao;

  /// The clock the **expiry badges** on a detail are judged against (T-7).
  ///
  /// Injected rather than read from `DateTime.now()` inside the mapper, because
  /// *"expired"* is a question about today and a test that could not pin today could
  /// not assert the answer. It decides nothing else: no read is filtered by it, and no
  /// write consults it — a return is never refused for expiry (§36), so the only thing
  /// this changes is which lines carry a red badge.
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.runInTransaction(action);

  // --- eligibility -----------------------------------------------------------

  @override
  Future<List<GoodsReturnEligibility>> eligibleGoodReceiptsForBranch({
    required String branchId,
    String searchQuery = '',
  }) async => _mapEligible(
    await _dao.rejectedGoodReceipts(
      branchId: branchId,
      searchQuery: searchQuery,
    ),
  );

  @override
  Stream<List<GoodsReturnEligibility>> watchEligibleGoodReceiptsForBranch({
    required String branchId,
    String searchQuery = '',
  }) => _dao
      // `asyncMap` rather than an `async*` with `await for`, and the difference is not
      // stylistic: each emission runs further queries to load the rejected positions,
      // and awaiting those *inside* a loop that is itself suspended on a drift query
      // stream leaves the stream holding its subscription while the executor is asked
      // for more work. `asyncMap` hands the row set over and lets the mapping run
      // outside the loop, which is also how the two list streams below are built.
      .watchRejectedGoodReceipts(branchId: branchId, searchQuery: searchQuery)
      .asyncMap(_mapEligible);

  /// Loads each receipt's rejected positions and sorts the queue by **instant**.
  ///
  /// One extra query per receipt rather than one enormous join, and deliberately so:
  /// the positions carry reject reasons and expiry dates the queue shows (§29), and
  /// folding them into the aggregate query would either duplicate the counts or force a
  /// second pass anyway. A branch's *Perlu Dibuat* list is a work queue of a handful of
  /// receipts, not a report.
  Future<List<GoodsReturnEligibility>> _mapEligible(
    List<RejectedGoodReceiptRow> rows,
  ) async {
    final result = <GoodsReturnEligibility>[];
    for (final row in rows) {
      result.add(
        GoodsReturnEligibility(
          grId: row.receipt.id,
          grDocNumber: row.receipt.docNumber,
          grPostedAt: row.receipt.postedAt?.toUtc(),
          doId: row.order.id,
          doDocNumber: row.order.docNumber,
          prId: row.request.id,
          prDocNumber: row.request.docNumber,
          branchId: row.branch.id,
          branchCode: row.branch.code,
          branchName: row.branch.name,
          rejectedLineCount: row.rejectedLineCount,
          rejectedQty: Quantity.fromMilliUnits(row.rejectedQtyMilliUnits),
          positions: await rejectedPositionsOf(row.receipt.id),
          existingReturnId: row.existingReturn?.id,
          existingReturnDocNumber: row.existingReturn?.docNumber,
          existingReturnStatus: row.existingReturn?.status,
        ),
      );
    }

    // §16's ordering, on parsed instants. A receipt with no `posted_at` cannot occur —
    // the Good Receipt's CHECK pairs `posted` with the instant — but it sorts last
    // rather than throwing, because a corrupt row should still render.
    result.sort((a, b) {
      final left = a.grPostedAt;
      final right = b.grPostedAt;
      if (left != null && right != null && left != right) {
        return left.compareTo(right);
      }
      if (left == null && right != null) return 1;
      if (left != null && right == null) return -1;
      final byBranch = a.branchCode.compareTo(b.branchCode);
      if (byBranch != 0) return byBranch;
      return a.grDocNumber.compareTo(b.grDocNumber);
    });
    return List.unmodifiable(result);
  }

  @override
  Future<List<RejectedGoodReceiptPosition>> rejectedPositionsOf(
    String grId,
  ) async {
    final rows = await _dao.rejectedGoodReceiptLineDetails(grId);
    return rows
        .map(
          (row) => RejectedGoodReceiptPosition(
            grLineId: row.line.id,
            grId: row.line.grId,
            itemId: row.item.id,
            sku: row.item.sku,
            itemName: row.item.name,
            categoryId: row.item.categoryId,
            unit: row.item.unit,
            hasExpiry: row.item.hasExpiry,
            expiryAlertDays: row.item.expiryAlertDays,
            batchId: row.batch?.id,
            batchNo: row.batch?.batchNo,
            expiryDate: row.batch?.expiryDate,
            shippedQty: Quantity.fromMilliUnits(row.line.shippedQty),
            receivedQty: Quantity.fromMilliUnits(row.line.receivedQty),
            rejectReason: row.line.rejectReason ?? '',
            itemIsHistorical: !row.item.isActive || row.item.deletedAt != null,
            batchIsHistorical:
                row.batch != null && row.batch!.deletedAt != null,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<String>> rejectedGoodReceiptLineIds(String grId) =>
      _dao.rejectedGoodReceiptLineIdsOf(grId);

  @override
  Future<GoodReceiptStatus?> goodReceiptStatusOf(String grId) async =>
      (await _dao.goodReceiptById(grId))?.status;

  @override
  Future<String?> goodReceiptBranchOf(String grId) async {
    // Three joins away — `good_receipts` has no branch column of its own, which is
    // exactly why `goods_returns` stores one (§10).
    final rows = await _dao
        .customSelect(
          'SELECT pr.branch_id AS branch_id '
          'FROM good_receipts gr '
          'JOIN delivery_orders dord ON dord.id = gr.do_id '
          'JOIN purchase_requests pr ON pr.id = dord.pr_id '
          'WHERE gr.id = ? AND gr.deleted_at IS NULL;',
          variables: [Variable<String>(grId)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('branch_id');
  }

  @override
  Future<GoodsReturn?> findByGoodReceipt(String grId) async {
    final row = await _dao.headerByGoodReceipt(grId);
    return row == null ? null : _toGoodsReturn(row);
  }

  @override
  Future<Map<String, GoodsReturn>> returnsByGoodReceipt(
    Iterable<String> grIds,
  ) async {
    final rows = await _dao.returnsByGoodReceipt(grIds);
    return {
      for (final entry in rows.entries) entry.key: _toGoodsReturn(entry.value),
    };
  }

  @override
  Future<Map<String, List<DateTime>>> batchExpiriesFor(
    Iterable<String> goodsReturnIds,
  ) => _dao.batchExpiriesFor(goodsReturnIds);

  @override
  Stream<int> watchOutstandingRejectedGoodReceiptCount() =>
      _dao.watchOutstandingRejectedGoodReceiptCount();

  // --- header -----------------------------------------------------------------

  @override
  Future<GoodsReturn> createFromGoodReceipt({
    required String docNumber,
    required String grId,
    required String branchId,
    required String createdBy,
    required List<GoodsReturnLineDraft> lines,
    String? note,
    DateTime? createdAtUtc,
  }) async {
    // The creation instant comes from the caller's injected clock rather than from the
    // column default (T-7). It is not decoration: the ship transition refuses to stamp
    // `shipped_at` before it, so if the two came from different clocks a test could not
    // pin the ordering — and neither could a device whose clock moved between the two
    // writes.
    final now = (createdAtUtc ?? DateTime.now()).toUtc();

    final header = await _dao.insertHeader(
      GoodsReturnsCompanion.insert(
        docNumber: docNumber,
        grId: grId,
        branchId: branchId,
        createdBy: createdBy,
        note: Value(note),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    // The whole snapshot in one batch, inside the caller's transaction. A header the
    // unique index accepted followed by lines that failed would leave a document
    // claiming to return nothing (§17).
    await _dao.insertLines(
      lines
          .map(
            (line) => GoodsReturnLinesCompanion.insert(
              goodsReturnId: header.id,
              grLineId: line.grLineId,
              itemId: line.itemId,
              batchId: Value(line.batchId),
              qty: line.qty.milliUnits,
              rejectReasonSnapshot: line.rejectReason,
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          )
          .toList(growable: false),
    );

    return _toGoodsReturn(header);
  }

  @override
  Future<GoodsReturn?> getById(String goodsReturnId) async {
    final row = await _dao.headerById(goodsReturnId);
    return row == null ? null : _toGoodsReturn(row);
  }

  @override
  Future<GoodsReturnDetail?> getDetail(String goodsReturnId) => _getDetail(
    goodsReturnId,
    scope: null,
    branchId: null,
    statuses: const {},
  );

  @override
  Future<GoodsReturnDetail?> getForBranch({
    required String goodsReturnId,
    required String branchId,
  }) => _getDetail(
    goodsReturnId,
    scope: GoodsReturnQueryScope.branch,
    branchId: branchId,
    statuses: GoodsReturnAccessPolicy.branchVisibleStatuses,
  );

  @override
  Future<GoodsReturnDetail?> getForWarehouse(String goodsReturnId) =>
      _getDetail(
        goodsReturnId,
        scope: GoodsReturnQueryScope.warehouseInTransitOrReceived,
        branchId: null,
        statuses: GoodsReturnAccessPolicy.warehouseVisibleStatuses,
      );

  Future<GoodsReturnDetail?> _getDetail(
    String goodsReturnId, {
    required GoodsReturnQueryScope? scope,
    required String? branchId,
    required Set<GoodsReturnStatus> statuses,
  }) async {
    final summaryRow = await _dao.summaryById(
      goodsReturnId,
      scope: scope,
      branchId: branchId,
      statuses: statuses,
    );
    if (summaryRow == null) return null;
    final lines = await _dao.detailLines(goodsReturnId);
    return _toDetail(summaryRow, lines);
  }

  @override
  Stream<GoodsReturnDetail?> watchForBranch({
    required String goodsReturnId,
    required String branchId,
  }) => _watchDetail(
    goodsReturnId,
    scope: GoodsReturnQueryScope.branch,
    branchId: branchId,
    statuses: GoodsReturnAccessPolicy.branchVisibleStatuses,
  );

  @override
  Stream<GoodsReturnDetail?> watchForWarehouse(String goodsReturnId) =>
      _watchDetail(
        goodsReturnId,
        scope: GoodsReturnQueryScope.warehouseInTransitOrReceived,
        branchId: null,
        statuses: GoodsReturnAccessPolicy.warehouseVisibleStatuses,
      );

  Stream<GoodsReturnDetail?> _watchDetail(
    String goodsReturnId, {
    required GoodsReturnQueryScope? scope,
    required String? branchId,
    required Set<GoodsReturnStatus> statuses,
  }) async* {
    // The header stream carries the scope, so a document that leaves the scope stops
    // emitting rather than emitting with the wrong fields. The lines are re-read per
    // emission because they are immutable — one read per header change is one read more
    // than strictly needed and far simpler than reasoning about two interleaved
    // streams.
    await for (final summaryRow in _dao.watchSummaryById(
      goodsReturnId,
      scope: scope,
      branchId: branchId,
      statuses: statuses,
    )) {
      if (summaryRow == null) {
        yield null;
        continue;
      }
      yield _toDetail(summaryRow, await _dao.detailLines(goodsReturnId));
    }
  }

  @override
  Future<GoodsReturnAccessScope?> findAccessScope({
    required String goodsReturnId,
    GoodsReturnQueryScope? scope,
    String? branchId,
    Set<GoodsReturnStatus> statuses = const {},
  }) async {
    final row = await _dao.accessScope(
      goodsReturnId: goodsReturnId,
      scope: scope,
      branchId: branchId,
      statuses: statuses,
    );
    if (row == null) return null;
    return GoodsReturnAccessScope(
      goodsReturnId: row.goodsReturnId,
      grId: row.grId,
      branchId: row.branchId,
      createdBy: row.createdBy,
      shippedBy: row.shippedBy,
      receivedBy: row.receivedBy,
      status: row.status,
    );
  }

  @override
  Future<List<GoodsReturnSummary>> listForBranch({
    required String branchId,
    Set<GoodsReturnStatus> statuses = const {},
    String searchQuery = '',
  }) async => _sortNewestFirst(
    await _mapSummaries(
      await _dao.listReturns(
        scope: GoodsReturnQueryScope.branch,
        branchId: branchId,
        statuses: statuses,
        searchQuery: searchQuery,
      ),
    ),
  );

  @override
  Stream<List<GoodsReturnSummary>> watchBranchList({
    required String branchId,
    Set<GoodsReturnStatus> statuses = const {},
    String searchQuery = '',
  }) => _dao
      .watchReturns(
        scope: GoodsReturnQueryScope.branch,
        branchId: branchId,
        statuses: statuses,
        searchQuery: searchQuery,
      )
      .asyncMap((rows) async => _sortNewestFirst(await _mapSummaries(rows)));

  @override
  Future<List<GoodsReturnSummary>> listForWarehouse({
    Set<GoodsReturnStatus> statuses = const {},
    String? filterBranchId,
    String searchQuery = '',
  }) async => _sortNewestFirst(
    await _mapSummaries(
      await _dao.listReturns(
        scope: GoodsReturnQueryScope.warehouseInTransitOrReceived,
        filterBranchId: filterBranchId,
        statuses: statuses,
        searchQuery: searchQuery,
      ),
    ),
  );

  @override
  Stream<List<GoodsReturnSummary>> watchWarehouseList({
    Set<GoodsReturnStatus> statuses = const {},
    String? filterBranchId,
    String searchQuery = '',
  }) => _dao
      .watchReturns(
        scope: GoodsReturnQueryScope.warehouseInTransitOrReceived,
        filterBranchId: filterBranchId,
        statuses: statuses,
        searchQuery: searchQuery,
      )
      .asyncMap((rows) async => _sortNewestFirst(await _mapSummaries(rows)));

  /// Newest first, by **parsed instant** rather than by the TEXT column the SQL sorted
  /// on. Ties break on the document number so two devices holding the same data list it
  /// in the same order.
  List<GoodsReturnSummary> _sortNewestFirst(List<GoodsReturnSummary> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final byInstant = b.goodsReturn.createdAt.toUtc().compareTo(
        a.goodsReturn.createdAt.toUtc(),
      );
      if (byInstant != 0) return byInstant;
      return a.goodsReturn.docNumber.compareTo(b.goodsReturn.docNumber);
    });
    return List.unmodifiable(sorted);
  }

  // --- transitions --------------------------------------------------------------

  @override
  Future<bool> updateDraftNote({
    required String goodsReturnId,
    required String branchId,
    required String? note,
  }) async =>
      await _dao.updateDraftNote(
        goodsReturnId: goodsReturnId,
        branchId: branchId,
        note: note,
      ) >
      0;

  @override
  Future<bool> markShipped({
    required String goodsReturnId,
    required String branchId,
    required DateTime shippedAtUtc,
    required String shippedBy,
  }) async =>
      await _dao.markShipped(
        goodsReturnId: goodsReturnId,
        branchId: branchId,
        shippedAtUtc: shippedAtUtc,
        shippedBy: shippedBy,
      ) >
      0;

  @override
  Future<bool> markReceived({
    required String goodsReturnId,
    required DateTime receivedAtUtc,
    required String receivedBy,
    String? warehouseNote,
  }) async =>
      await _dao.markReceived(
        goodsReturnId: goodsReturnId,
        receivedAtUtc: receivedAtUtc,
        receivedBy: receivedBy,
        warehouseNote: warehouseNote,
      ) >
      0;

  // --- lines ---------------------------------------------------------------------

  @override
  Future<List<GoodsReturnLineReference>> lineReferences(
    String goodsReturnId,
  ) async {
    final rows = await _dao.linesOf(goodsReturnId);
    return rows
        .map(
          (row) => GoodsReturnLineReference(
            id: row.id,
            goodsReturnId: row.goodsReturnId,
            grLineId: row.grLineId,
            itemId: row.itemId,
            batchId: row.batchId,
            qty: Quantity.fromMilliUnits(row.qty),
            rejectReason: row.rejectReasonSnapshot,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<String>> lineIds(String goodsReturnId) =>
      _dao.lineIdsOf(goodsReturnId);

  @override
  Future<List<String>> lineGrLineIds(String goodsReturnId) =>
      _dao.lineGrLineIdsOf(goodsReturnId);

  @override
  Future<List<String>> lineItemIds(String goodsReturnId) =>
      _dao.lineItemIdsOf(goodsReturnId);

  @override
  Future<List<String>> lineBatchIds(String goodsReturnId) =>
      _dao.lineBatchIdsOf(goodsReturnId);

  // --- destination ---------------------------------------------------------------

  @override
  Future<List<MasterLocation>> activeWarehouseLocations({
    bool activeOnly = true,
  }) async {
    final rows = await _dao.warehouseLocations(activeOnly: activeOnly);
    return rows
        .map(
          (row) => MasterLocation(
            id: row.id,
            type: row.type,
            branchId: row.branchId,
            roomId: row.roomId,
            name: row.name,
            isArchived: row.deletedAt != null,
          ),
        )
        .toList(growable: false);
  }

  // --- mapping ---------------------------------------------------------------------

  GoodsReturn _toGoodsReturn(GoodsReturnRow row) => GoodsReturn(
    id: row.id,
    docNumber: row.docNumber,
    grId: row.grId,
    branchId: row.branchId,
    createdBy: row.createdBy,
    status: row.status,
    note: row.note,
    shippedAt: row.shippedAt?.toUtc(),
    shippedBy: row.shippedBy,
    receivedAt: row.receivedAt?.toUtc(),
    receivedBy: row.receivedBy,
    warehouseNote: row.warehouseNote,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    syncStatus: row.syncStatus,
  );

  /// Attaches the per-unit totals to a page of summaries with **one** extra query.
  ///
  /// A second round trip rather than a wider aggregate, because a `GROUP BY` over both
  /// the document and the unit cannot also produce the per-document counts without
  /// either duplicating them or nesting — and the counts are what the list row leads
  /// with.
  Future<List<GoodsReturnSummary>> _mapSummaries(
    List<GoodsReturnWithContext> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final totals = await _dao.totalsByUnitFor(
      rows.map((row) => row.goodsReturn.id),
    );
    return rows
        .map(
          (row) => _toSummary(
            row,
            totalsByUnit: totals[row.goodsReturn.id] ?? const {},
          ),
        )
        .toList(growable: false);
  }

  GoodsReturnSummary _toSummary(
    GoodsReturnWithContext row, {
    Map<String, int> totalsByUnit = const {},
  }) => GoodsReturnSummary(
    goodsReturn: _toGoodsReturn(row.goodsReturn),
    grDocNumber: row.receipt.docNumber,
    doDocNumber: row.order.docNumber,
    prDocNumber: row.request.docNumber,
    branchCode: row.branch.code,
    branchName: row.branch.name,
    createdByName: row.createdBy.fullName,
    shippedByName: row.shippedBy?.fullName,
    receivedByName: row.receivedBy?.fullName,
    lineCount: row.lineCount,
    itemCount: row.itemCount,
    batchCount: row.batchCount,
    totalQty: Quantity.fromMilliUnits(row.totalQtyMilliUnits),
    totalsByUnit: {
      for (final entry in totalsByUnit.entries)
        entry.key: Quantity.fromMilliUnits(entry.value),
    },
    // The join filters neither flag, so a received return whose branch was
    // deactivated afterwards still produces a row — badged rather than hidden
    // (§37).
    branchIsHistorical: !row.branch.isActive || row.branch.deletedAt != null,
  );

  GoodsReturnDetail _toDetail(
    GoodsReturnWithContext summaryRow,
    List<GoodsReturnLineWithDetails> lineRows,
  ) {
    final lines = lineRows
        .map(
          (row) => GoodsReturnLine(
            id: row.line.id,
            goodsReturnId: row.line.goodsReturnId,
            grLineId: row.line.grLineId,
            itemId: row.item.id,
            sku: row.item.sku,
            itemName: row.item.name,
            categoryId: row.item.categoryId,
            unit: row.item.unit,
            hasExpiry: row.item.hasExpiry,
            expiryAlertDays: row.item.expiryAlertDays,
            batchId: row.batch?.id,
            batchNo: row.batch?.batchNo,
            expiryDate: row.batch?.expiryDate,
            qty: Quantity.fromMilliUnits(row.line.qty),
            rejectReason: row.line.rejectReasonSnapshot,
            itemIsHistorical: !row.item.isActive || row.item.deletedAt != null,
            batchIsHistorical:
                row.batch != null && row.batch!.deletedAt != null,
          ),
        )
        .toList(growable: false);

    // The detail already holds every line, so its per-unit totals are derived here
    // rather than fetched again — one fewer query than the list needs, from the data
    // that is already in hand.
    final totalsByUnit = <String, int>{};
    for (final line in lines) {
      totalsByUnit[line.unit] =
          (totalsByUnit[line.unit] ?? 0) + line.qty.milliUnits;
    }

    return GoodsReturnDetail(
      summary: _toSummary(summaryRow, totalsByUnit: totalsByUnit),
      lines: lines,
      progress: buildProgress(lines, nowUtc: _clock().toUtc()),
    );
  }

  /// The per-document aggregate, derived from the lines rather than stored.
  ///
  /// Public and static so the providers can rebuild it from a line list they already
  /// hold without a second query, and so the widget tests can construct one without a
  /// database. Expiry is judged against [nowUtc] because *"expired"* is a question about
  /// today, not a property of the row — and the answer is a badge, never a refusal
  /// (§36).
  static GoodsReturnProgress buildProgress(
    List<GoodsReturnLine> lines, {
    DateTime? nowUtc,
  }) {
    if (lines.isEmpty) return const GoodsReturnProgress.empty();
    final now = (nowUtc ?? DateTime.now()).toUtc();

    final totalsByUnit = <String, Quantity>{};
    final items = <String>{};
    final batches = <String>{};
    var expired = 0;
    var nearExpiry = 0;
    DateTime? nearest;

    for (final line in lines) {
      totalsByUnit[line.unit] =
          (totalsByUnit[line.unit] ?? Quantity.zero()) + line.qty;
      items.add(line.itemId);
      final batchId = line.batchId;
      if (batchId != null) batches.add(batchId);
      if (line.isExpired(now)) expired++;
      if (line.isNearExpiry(now)) nearExpiry++;
      final expiry = line.expiryDate;
      if (expiry != null && (nearest == null || expiry.isBefore(nearest))) {
        nearest = expiry;
      }
    }

    return GoodsReturnProgress(
      lineCount: lines.length,
      itemCount: items.length,
      batchCount: batches.length,
      totalQty: Quantity.sum(lines.map((line) => line.qty)),
      totalQuantityByUnit: Map.unmodifiable(totalsByUnit),
      expiredCount: expired,
      nearExpiryCount: nearExpiry,
      nearestExpiryDate: nearest,
    );
  }
}
