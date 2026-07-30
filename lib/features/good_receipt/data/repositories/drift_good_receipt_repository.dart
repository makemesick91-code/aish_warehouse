import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/good_receipt_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../domain/models/good_receipt_models.dart';
import '../../domain/repositories/good_receipt_repository.dart';
import '../../domain/services/good_receipt_access_policy.dart';

/// Translates between the database boundary (milli-unit integers, drift rows) and
/// the Good Receipt domain.
///
/// This is the only file in the feature allowed to touch `Quantity.milliUnits` or a
/// generated drift class (Q-4) — the use cases, providers and widgets above it see
/// nothing but domain models.
class DriftGoodReceiptRepository implements GoodReceiptRepository {
  DriftGoodReceiptRepository(this._dao);

  final GoodReceiptDao _dao;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.runInTransaction(action);

  @override
  Future<GoodReceipt> createChecking({
    required String docNumber,
    required String deliveryOrderId,
    required String receivedBy,
    required List<GoodReceiptLineSnapshot> lines,
    DateTime? createdAtUtc,
  }) {
    // Header and snapshot are written together: a receipt with no lines could be
    // posted as an empty document, and one missing a line would check in less than
    // was sent.
    return _dao.runInTransaction(() async {
      // The creation instant comes from the caller's injected clock rather than
      // from the column default (T-7). It is not decoration: the posting refuses to
      // stamp `posted_at` before it, so if the two came from different clocks a
      // test could not pin the ordering — and neither could a device whose clock
      // moved between the two writes.
      final now = (createdAtUtc ?? DateTime.now()).toUtc();

      final GoodReceiptRow header;
      try {
        header = await _dao.insertHeader(
          GoodReceiptsCompanion.insert(
            docNumber: docNumber,
            doId: deliveryOrderId,
            receivedBy: receivedBy,
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      } on Object catch (error) {
        // G-G1's last line of defence. Two devices can both read "no receipt yet"
        // and both insert; the unique index on `do_id` lets exactly one through,
        // and the loser must see the business failure rather than a driver error.
        // The whole transaction rolls back, so the losing attempt leaves no orphan
        // lines behind.
        if (_isDeliveryOrderUniqueViolation(error)) {
          throw GoodReceiptAlreadyExistsFailure(
            'Surat Jalan ini sudah memiliki Good Receipt. Muat ulang halaman '
            'lalu lanjutkan pemeriksaan yang ada.',
            doId: deliveryOrderId,
          );
        }
        rethrow;
      }

      await _dao.insertLines(
        lines
            .map(
              (line) => GoodReceiptLinesCompanion.insert(
                grId: header.id,
                doLineId: line.doLineId,
                itemId: line.itemId,
                batchId: Value(line.batchId),
                shippedQty: line.shippedQty.milliUnits,
                receivedQty: line.receivedQty.milliUnits,
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            )
            .toList(growable: false),
      );

      return _toReceipt(header);
    });
  }

  /// Whether [error] is the unique index on `good_receipts.do_id` firing.
  ///
  /// Matched on the message rather than on an exception type, because the type comes
  /// from the sqlite3 package and importing it here would drag the native driver into
  /// a repository that otherwise only knows drift. The index name is in the message
  /// for a partial index and the column name for a plain one, so both are accepted —
  /// and anything else is rethrown untouched rather than swallowed as "already
  /// exists".
  static bool _isDeliveryOrderUniqueViolation(Object error) {
    final message = error.toString().toLowerCase();
    if (!message.contains('unique')) return false;
    return message.contains('good_receipts.do_id') ||
        message.contains('idx_good_receipts_do');
  }

  @override
  Future<GoodReceipt?> getById(String grId) async {
    final row = await _dao.headerById(grId);
    return row == null ? null : _toReceipt(row);
  }

  @override
  Future<GoodReceipt?> findByDeliveryOrder(String deliveryOrderId) async {
    final row = await _dao.headerByDeliveryOrder(deliveryOrderId);
    return row == null ? null : _toReceipt(row);
  }

  @override
  Future<GoodReceiptDetail?> getDetail(String grId) =>
      _getDetail(grId, branchId: null, statuses: const {});

  @override
  Future<GoodReceiptDetail?> getForBranch({
    required String grId,
    required String branchId,
  }) => _getDetail(
    grId,
    branchId: branchId,
    statuses: GoodReceiptAccessPolicy.branchVisibleStatuses,
  );

  @override
  Stream<GoodReceiptDetail?> watchForBranch({
    required String grId,
    required String branchId,
  }) => _watchDetail(
    grId,
    branchId: branchId,
    statuses: GoodReceiptAccessPolicy.branchVisibleStatuses,
  );

  @override
  Future<GoodReceiptDetail?> getForWarehouse(String grId) => _getDetail(
    grId,
    branchId: null,
    statuses: GoodReceiptAccessPolicy.warehouseVisibleStatuses,
  );

  @override
  Stream<GoodReceiptDetail?> watchForWarehouse(String grId) => _watchDetail(
    grId,
    branchId: null,
    statuses: GoodReceiptAccessPolicy.warehouseVisibleStatuses,
  );

  @override
  Future<GoodReceiptAccessScope?> findAccessScope({
    required String grId,
    String? branchId,
    Set<GoodReceiptStatus> statuses = const {},
  }) async {
    final row = await _dao.accessScope(
      grId: grId,
      branchId: branchId,
      statuses: statuses,
    );
    if (row == null) return null;
    return GoodReceiptAccessScope(
      grId: row.grId,
      doId: row.doId,
      prId: row.prId,
      branchId: row.branchId,
      status: row.status,
    );
  }

  Future<GoodReceiptDetail?> _getDetail(
    String grId, {
    required String? branchId,
    required Set<GoodReceiptStatus> statuses,
  }) async {
    final context = await _dao.summaryById(
      grId,
      branchId: branchId,
      statuses: statuses,
    );
    if (context == null) return null;
    return _hydrate(context);
  }

  Stream<GoodReceiptDetail?> _watchDetail(
    String grId, {
    required String? branchId,
    required Set<GoodReceiptStatus> statuses,
  }) {
    // The header query carries the branch and status scope, and the children are
    // fetched only after it produced a row. A receipt outside the scope therefore
    // costs one predicate in SQLite and never reaches a second query — its lines,
    // batches, quantities and reject reasons are not read even to be discarded.
    return _dao
        .watchSummaryById(grId, branchId: branchId, statuses: statuses)
        .asyncMap(
          (context) async => context == null ? null : _hydrate(context),
        );
  }

  Future<GoodReceiptDetail> _hydrate(GoodReceiptWithContext context) async {
    final lines = (await _dao.detailLines(
      context.receipt.id,
    )).map(_toLine).toList(growable: false);

    return GoodReceiptDetail(summary: _toSummary(context), lines: lines);
  }

  @override
  Stream<List<GoodReceiptSummary>> watchListForBranch({
    required String branchId,
    Set<GoodReceiptStatus> statuses = const {},
  }) {
    final visible = _branchStatuses(statuses);
    if (visible.isEmpty) return Stream.value(const <GoodReceiptSummary>[]);
    return _dao
        .watchReceipts(branchId: branchId, statuses: visible)
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  @override
  Future<List<GoodReceiptSummary>> listForBranch({
    required String branchId,
    Set<GoodReceiptStatus> statuses = const {},
  }) async {
    final visible = _branchStatuses(statuses);
    if (visible.isEmpty) return const <GoodReceiptSummary>[];
    final rows = await _dao.listReceipts(branchId: branchId, statuses: visible);
    return rows.map(_toSummary).toList(growable: false);
  }

  /// Intersecting here rather than trusting [statuses] is what makes the branch
  /// restriction a property of the method instead of a convention its callers
  /// follow.
  Set<GoodReceiptStatus> _branchStatuses(Set<GoodReceiptStatus> statuses) =>
      statuses.isEmpty
      ? GoodReceiptAccessPolicy.branchVisibleStatuses
      : statuses
            .where(GoodReceiptAccessPolicy.branchVisibleStatuses.contains)
            .toSet();

  @override
  Stream<List<GoodReceiptSummary>> watchListForWarehouse(
    GoodReceiptFilter filter,
  ) {
    final visible = _warehouseStatuses(filter.statuses);
    if (visible.isEmpty) return Stream.value(const <GoodReceiptSummary>[]);
    return _dao
        .watchReceipts(
          branchId: filter.branchId,
          statuses: visible,
          searchQuery: filter.searchQuery,
        )
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  @override
  Future<List<GoodReceiptSummary>> listForWarehouse(
    GoodReceiptFilter filter,
  ) async {
    final visible = _warehouseStatuses(filter.statuses);
    if (visible.isEmpty) return const <GoodReceiptSummary>[];
    final rows = await _dao.listReceipts(
      branchId: filter.branchId,
      statuses: visible,
      searchQuery: filter.searchQuery,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  /// The warehouse never sees a `checking` receipt, whatever the caller asks for: a
  /// branch head part way through a decision has not refused anything yet.
  Set<GoodReceiptStatus> _warehouseStatuses(Set<GoodReceiptStatus> statuses) =>
      statuses.isEmpty
      ? GoodReceiptAccessPolicy.warehouseVisibleStatuses
      : statuses
            .where(GoodReceiptAccessPolicy.warehouseVisibleStatuses.contains)
            .toSet();

  @override
  Stream<List<GoodReceiptAwaitingDelivery>> watchAwaitingDeliveryOrders({
    String? branchId,
  }) => _dao
      .watchAwaitingReceipts(branchId: branchId)
      .map((rows) => rows.map(_toAwaiting).toList(growable: false));

  @override
  Future<List<GoodReceiptAwaitingDelivery>> awaitingDeliveryOrders({
    String? branchId,
  }) async => (await _dao.awaitingReceipts(
    branchId: branchId,
  )).map(_toAwaiting).toList(growable: false);

  @override
  Stream<List<GoodReceiptDiscrepancy>> watchWarehouseDiscrepancies(
    GoodReceiptFilter filter,
  ) => _dao
      .watchDiscrepancies(
        branchId: filter.branchId,
        searchQuery: filter.searchQuery,
        rejectedOnly: filter.rejectedOnly,
      )
      .map(
        (rows) => _withinPostedWindow(
          rows.map(_toDiscrepancy).toList(growable: false),
          filter,
        ),
      );

  @override
  Future<List<GoodReceiptDiscrepancy>> warehouseDiscrepancies(
    GoodReceiptFilter filter,
  ) async => _withinPostedWindow(
    (await _dao.discrepancies(
      branchId: filter.branchId,
      searchQuery: filter.searchQuery,
      rejectedOnly: filter.rejectedOnly,
    )).map(_toDiscrepancy).toList(growable: false),
    filter,
  );

  /// Applies the report's posted-date window, on UTC instants.
  ///
  /// **Deliberately not in SQL.** Timestamps are persisted as ISO-8601 TEXT
  /// (`build.yaml`), so `posted_at >= ?` in SQLite compares characters rather than
  /// instants — the trap schema v4 removed from `stock_opnames`. `DateTime.isBefore` is an
  /// instant comparison down to the microsecond that no serialisation format can
  /// influence.
  ///
  /// Moving a *display* filter into Dart is safe in a way moving the **branch** predicate
  /// would not be: a branch row must never be read at all, while a row outside the date
  /// range is this warehouse's own data either way.
  List<GoodReceiptDiscrepancy> _withinPostedWindow(
    List<GoodReceiptDiscrepancy> rows,
    GoodReceiptFilter filter,
  ) {
    final from = filter.postedFromUtc?.toUtc();
    final to = filter.postedToUtc?.toUtc();
    if (from == null && to == null) return rows;

    return rows
        .where(
          (row) =>
              (from == null || !row.postedAtUtc.isBefore(from)) &&
              (to == null || !row.postedAtUtc.isAfter(to)),
        )
        .toList(growable: false);
  }

  @override
  Future<List<GoodReceiptLineReference>> lineReferences(String grId) async =>
      (await _dao.linesOf(grId)).map(_toReference).toList(growable: false);

  @override
  Future<GoodReceiptLineReference?> lineReferenceById(String lineId) async {
    final row = await _dao.lineById(lineId);
    return row == null ? null : _toReference(row);
  }

  @override
  Future<List<String>> deliveryOrderLineIds(String deliveryOrderId) async =>
      (await _dao.deliveryOrderLinesOf(
        deliveryOrderId,
      )).map((row) => row.id).toList(growable: false);

  @override
  Future<bool> decideChecked({
    required String grId,
    required String lineId,
    required Quantity receivedQty,
  }) async =>
      await _dao.markLineChecked(
        grId: grId,
        lineId: lineId,
        receivedQtyMilliUnits: receivedQty.milliUnits,
      ) >
      0;

  @override
  Future<bool> decideRejected({
    required String grId,
    required String lineId,
    required String reason,
  }) async =>
      await _dao.markLineRejected(grId: grId, lineId: lineId, reason: reason) >
      0;

  @override
  Future<bool> resetDecision({
    required String grId,
    required String lineId,
  }) async => await _dao.resetLine(grId: grId, lineId: lineId) > 0;

  @override
  Future<bool> postAtomically({
    required String grId,
    required DateTime postedAtUtc,
    required String deliveryOrderId,
    required String prId,
    required bool closeRequest,
  }) async {
    final posted = await _dao.markPosted(grId: grId, postedAtUtc: postedAtUtc);
    if (posted == 0) return false;

    // `shipped → received`. The guard is `status = 'shipped'` inside the statement,
    // so a shipment that has moved on in the meantime yields zero — and that is a
    // reason to abort rather than to shrug: a receipt posted against a shipment
    // nobody is waiting for would leave the two documents disagreeing, with stock
    // already credited.
    final received = await _dao.markDeliveryOrderReceived(deliveryOrderId);
    if (received == 0) {
      throw ConcurrentDeliveryOrderUpdateFailure(
        'Surat Jalan ini baru saja berubah dari perangkat lain. '
        'Muat ulang halaman lalu coba lagi.',
        doId: deliveryOrderId,
      );
    }

    if (closeRequest) {
      // §23. The guard is `status = 'shipped'` inside the statement, for the same
      // reason: the caller decided this receipt completes a request that is no
      // longer waiting for it.
      final closed = await _dao.markPurchaseRequestClosed(prId);
      if (closed == 0) {
        throw ConcurrentPurchaseRequestUpdateFailure(
          'Purchase Request ini baru saja berubah dari perangkat lain. '
          'Muat ulang halaman lalu coba lagi.',
          prId: prId,
        );
      }
    }
    return true;
  }

  @override
  Future<List<GoodReceiptShipmentStatus>> shipmentDeliveryOrdersOf(
    String prId,
  ) async => (await _dao.shipmentsOfPurchaseRequest(prId))
      .map(
        (row) => GoodReceiptShipmentStatus(doId: row.doId, status: row.status),
      )
      .toList(growable: false);
}

GoodReceipt _toReceipt(GoodReceiptRow row) => GoodReceipt(
  id: row.id,
  docNumber: row.docNumber,
  doId: row.doId,
  receivedBy: row.receivedBy,
  status: row.status,
  postedAt: row.postedAt,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  syncStatus: row.syncStatus,
);

/// What "historic" means, in one place.
///
/// Deactivated (G-A4) and soft-deleted (G-A5) are separate states with the same
/// consequence for a document that already references the row: it stays valid, stays
/// readable and stays postable, but the row can no longer be picked for anything new.
bool _isHistorical(bool isActive, DateTime? deletedAt) =>
    !isActive || deletedAt != null;

/// The joins behind [GoodReceiptWithContext] filter neither `is_active` nor
/// `deleted_at`, which is what keeps a receipt visible — and postable — after its
/// branch or the officer who shipped it is retired. The flags below turn that fact
/// into something the screens can label, rather than into a document that quietly
/// disappears from the branch's Penerimaan list.
GoodReceiptSummary _toSummary(GoodReceiptWithContext row) => GoodReceiptSummary(
  receipt: _toReceipt(row.receipt),
  doDocNumber: row.order.docNumber,
  doStatus: row.order.status,
  doShippedAt: row.order.shippedAt,
  shippedByName: row.shippedBy?.fullName,
  prDocNumber: row.request.docNumber,
  prStatus: row.request.status,
  branchId: row.branch.id,
  branchCode: row.branch.code,
  branchName: row.branch.name,
  branchAddress: row.branch.address,
  receivedByName: row.receivedBy.fullName,
  progress: GoodReceiptProgress(
    total: row.lineCount,
    pending: row.pendingCount,
    checked: row.checkedCount,
    rejected: row.rejectedCount,
    shortage: row.shortageCount,
  ),
  branchIsHistorical: _isHistorical(row.branch.isActive, row.branch.deletedAt),
  receivedByIsHistorical: _isHistorical(
    row.receivedBy.isActive,
    row.receivedBy.deletedAt,
  ),
);

GoodReceiptLine _toLine(GoodReceiptLineWithDetails row) => GoodReceiptLine(
  id: row.line.id,
  grId: row.line.grId,
  doLineId: row.line.doLineId,
  itemId: row.line.itemId,
  sku: row.item.sku,
  itemName: row.item.name,
  categoryId: row.item.categoryId,
  unit: row.item.unit,
  hasExpiry: row.item.hasExpiry,
  expiryAlertDays: row.item.expiryAlertDays,
  shippedQty: Quantity.fromMilliUnits(row.line.shippedQty),
  receivedQty: Quantity.fromMilliUnits(row.line.receivedQty),
  lineStatus: row.line.lineStatus,
  rejectReason: row.line.rejectReason,
  batchId: row.line.batchId,
  batchNo: row.batch?.batchNo,
  // A civil date is read back verbatim, never timezone converted (T-9).
  expiryDate: row.batch == null ? null : DateOnly.from(row.batch!.expiryDate),
  itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
  batchIsHistorical: row.batch != null && row.batch!.deletedAt != null,
);

GoodReceiptLineReference _toReference(GoodReceiptLineRow row) =>
    GoodReceiptLineReference(
      id: row.id,
      grId: row.grId,
      doLineId: row.doLineId,
      itemId: row.itemId,
      batchId: row.batchId,
      shippedQty: Quantity.fromMilliUnits(row.shippedQty),
      receivedQty: Quantity.fromMilliUnits(row.receivedQty),
      lineStatus: row.lineStatus,
      rejectReason: row.rejectReason,
    );

GoodReceiptAwaitingDelivery _toAwaiting(
  AwaitingGoodReceiptRow row,
) => GoodReceiptAwaitingDelivery(
  doId: row.order.id,
  doDocNumber: row.order.docNumber,
  prId: row.request.id,
  prDocNumber: row.request.docNumber,
  branchId: row.branch.id,
  branchCode: row.branch.code,
  branchName: row.branch.name,
  shippedByName: row.shippedBy?.fullName,
  // A `shipped` document always carries `shipped_at` — the table's CHECK says
  // so — but the column is nullable, and falling back to `created_at` keeps a
  // corrupt row visible with an honest deadline rather than crashing the queue.
  shippedAtUtc: row.order.shippedAt ?? row.order.createdAt,
  lineCount: row.lineCount,
  decidedCount: row.decidedCount,
  receiptId: row.receipt?.id,
  receiptDocNumber: row.receipt?.docNumber,
  receiptStatus: row.receipt?.status,
  branchIsHistorical: _isHistorical(row.branch.isActive, row.branch.deletedAt),
);

GoodReceiptDiscrepancy _toDiscrepancy(
  GoodReceiptDiscrepancyRow row,
) => GoodReceiptDiscrepancy(
  lineId: row.line.id,
  grId: row.receipt.id,
  grDocNumber: row.receipt.docNumber,
  doId: row.order.id,
  doDocNumber: row.order.docNumber,
  prId: row.request.id,
  prDocNumber: row.request.docNumber,
  branchId: row.branch.id,
  branchCode: row.branch.code,
  branchName: row.branch.name,
  itemId: row.item.id,
  sku: row.item.sku,
  itemName: row.item.name,
  unit: row.item.unit,
  batchId: row.line.batchId,
  batchNo: row.batch?.batchNo,
  expiryDate: row.batch == null ? null : DateOnly.from(row.batch!.expiryDate),
  shippedQty: Quantity.fromMilliUnits(row.line.shippedQty),
  receivedQty: Quantity.fromMilliUnits(row.line.receivedQty),
  lineStatus: row.line.lineStatus,
  rejectReason: row.line.rejectReason,
  // A posted receipt always carries `posted_at` — the table's CHECK says so —
  // and this query only selects posted ones.
  postedAtUtc: row.receipt.postedAt ?? row.receipt.updatedAt,
  itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
  branchIsHistorical: _isHistorical(row.branch.isActive, row.branch.deletedAt),
);
