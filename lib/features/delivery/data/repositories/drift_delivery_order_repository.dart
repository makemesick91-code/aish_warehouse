import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/delivery_order_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../domain/models/delivery_models.dart';
import '../../domain/repositories/delivery_order_repository.dart';
import '../../domain/services/delivery_order_access_policy.dart';
import '../../domain/services/delivery_quantity_policy.dart';

/// Translates between the database boundary (milli-unit integers, drift rows) and
/// the Delivery Order domain.
///
/// This is the only file in the feature allowed to touch `Quantity.milliUnits` or
/// a generated drift class (Q-4) — the use cases, providers and widgets above it
/// see nothing but domain models.
class DriftDeliveryOrderRepository implements DeliveryOrderRepository {
  DriftDeliveryOrderRepository(this._dao);

  final DeliveryOrderDao _dao;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.runInTransaction(action);

  @override
  Future<DeliveryOrder> createPreparing({
    required String docNumber,
    required String prId,
    required String preparedBy,
    String? note,
    required List<DeliveryAllocation> allocations,
    bool markRequestProcessing = false,
    DateTime? createdAtUtc,
    DateTime? processingAtUtc,
  }) {
    // Header, allocations and the Purchase Request transition are written
    // together: a half-created document would either allocate stock against a
    // request nobody has started working on, or start one with nothing to ship.
    return _dao.runInTransaction(() async {
      // The creation instant comes from the caller's injected clock rather than
      // from the column default (T-7). It is not decoration: the shipment refuses
      // to stamp `shipped_at` before it, so if the two came from different clocks a
      // test could not pin the ordering — and neither could a device whose clock
      // moved between the two writes.
      final now = (createdAtUtc ?? DateTime.now()).toUtc();

      if (markRequestProcessing) {
        final moved = await _dao.markPurchaseRequestProcessing(
          prId: prId,
          processedBy: preparedBy,
          processingAtUtc: processingAtUtc ?? now,
        );
        if (moved == 0) {
          // Another officer started on the same request between the read and this
          // write. The whole transaction rolls back, so no orphan header is left.
          throw ConcurrentPurchaseRequestUpdateFailure(
            'Purchase Request ini baru saja mulai diproses dari perangkat lain. '
            'Muat ulang halaman lalu coba lagi.',
            prId: prId,
          );
        }
      }

      final header = await _dao.insertHeader(
        DeliveryOrdersCompanion.insert(
          docNumber: docNumber,
          prId: prId,
          preparedBy: preparedBy,
          note: Value(note),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await _dao.insertLines(
        allocations
            .map((allocation) => _companionOf(header.id, allocation))
            .toList(growable: false),
      );

      return _toOrder(header);
    });
  }

  @override
  Future<DeliveryOrder?> getById(String doId) async {
    final row = await _dao.headerById(doId);
    return row == null ? null : _toOrder(row);
  }

  @override
  Future<DeliveryOrderDetail?> getDetail(String doId) =>
      _getDetail(doId, branchId: null, statuses: const {});

  @override
  Future<DeliveryOrderDetail?> getForWarehouse(String doId) =>
      _getDetail(doId, branchId: null, statuses: const {});

  @override
  Stream<DeliveryOrderDetail?> watchForWarehouse(String doId) =>
      _watchDetail(doId, branchId: null, statuses: const {});

  @override
  Future<DeliveryOrderDetail?> getForBranch({
    required String doId,
    required String branchId,
  }) => _getDetail(
    doId,
    branchId: branchId,
    statuses: DeliveryOrderAccessPolicy.branchVisibleStatuses,
  );

  @override
  Stream<DeliveryOrderDetail?> watchForBranch({
    required String doId,
    required String branchId,
  }) => _watchDetail(
    doId,
    branchId: branchId,
    statuses: DeliveryOrderAccessPolicy.branchVisibleStatuses,
  );

  @override
  Future<DeliveryOrderAccessScope?> findAccessScope({
    required String doId,
    String? branchId,
    Set<DeliveryOrderStatus> statuses = const {},
  }) async {
    final row = await _dao.accessScope(
      doId: doId,
      branchId: branchId,
      statuses: statuses,
    );
    if (row == null) return null;
    return DeliveryOrderAccessScope(
      doId: row.doId,
      prId: row.prId,
      branchId: row.branchId,
      status: row.status,
    );
  }

  Future<DeliveryOrderDetail?> _getDetail(
    String doId, {
    required String? branchId,
    required Set<DeliveryOrderStatus> statuses,
  }) async {
    final context = await _dao.summaryById(
      doId,
      branchId: branchId,
      statuses: statuses,
    );
    if (context == null) return null;
    return _hydrate(context);
  }

  Stream<DeliveryOrderDetail?> _watchDetail(
    String doId, {
    required String? branchId,
    required Set<DeliveryOrderStatus> statuses,
  }) {
    // The header query carries the branch and status scope, and the children are
    // fetched only after it produced a row. A document outside the scope therefore
    // costs one predicate in SQLite and never reaches a second query — its
    // allocations, batches and quantities are not read even to be discarded.
    return _dao
        .watchSummaryById(doId, branchId: branchId, statuses: statuses)
        .asyncMap(
          (context) async => context == null ? null : _hydrate(context),
        );
  }

  Future<DeliveryOrderDetail> _hydrate(DeliveryOrderWithContext context) async {
    final lines = (await _dao.detailLines(
      context.order.id,
    )).map(_toLine).toList(growable: false);

    return DeliveryOrderDetail(
      summary: _toSummary(context),
      lines: lines,
      progress: await shipmentProgress(
        prId: context.order.prId,
        doId: context.order.id,
      ),
    );
  }

  @override
  Stream<List<DeliveryOrderSummary>> watchListForWarehouse(
    DeliveryOrderFilter filter,
  ) => _dao
      .watchOrders(
        branchId: filter.branchId,
        statuses: filter.statuses,
        searchQuery: filter.searchQuery,
      )
      .map((rows) => rows.map(_toSummary).toList(growable: false));

  @override
  Stream<List<DeliveryOrderSummary>> watchListForBranch({
    required String branchId,
    Set<DeliveryOrderStatus> statuses = const {},
  }) {
    // The branch never sees a draft, whatever the caller asks for: intersecting
    // here rather than trusting [statuses] is what makes the restriction a
    // property of the method instead of a convention its callers follow.
    final visible = statuses.isEmpty
        ? DeliveryOrderAccessPolicy.branchVisibleStatuses
        : statuses
              .where(DeliveryOrderAccessPolicy.branchVisibleStatuses.contains)
              .toSet();
    if (visible.isEmpty) return Stream.value(const <DeliveryOrderSummary>[]);

    return _dao
        .watchOrders(branchId: branchId, statuses: visible)
        .map((rows) => rows.map(_toSummary).toList(growable: false));
  }

  @override
  Future<List<DeliveryOrderSummary>> listForWarehouse(
    DeliveryOrderFilter filter,
  ) async {
    final rows = await _dao.listOrders(
      branchId: filter.branchId,
      statuses: filter.statuses,
      searchQuery: filter.searchQuery,
    );
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Future<List<DeliveryOrderSummary>> listByPurchaseRequest(String prId) async {
    final rows = await _dao.ordersOfPurchaseRequest(prId);
    return rows.map(_toSummary).toList(growable: false);
  }

  @override
  Stream<List<DeliveryOrderSummary>> watchByPurchaseRequest(String prId) => _dao
      .watchOrdersOfPurchaseRequest(prId)
      .map((rows) => rows.map(_toSummary).toList(growable: false));

  @override
  Future<Map<String, Quantity>> cumulativeShippedByPrLine({
    required String prId,
    String? excludeDoId,
  }) async {
    final raw = await _dao.cumulativeShippedByPrLine(
      prId: prId,
      excludeDoId: excludeDoId,
    );
    return raw.map(
      (prLineId, milliUnits) =>
          MapEntry(prLineId, Quantity.fromMilliUnits(milliUnits)),
    );
  }

  @override
  Future<Map<String, Quantity>> allocatedByPrLine(String doId) async {
    final raw = await _dao.allocatedByPrLine(doId);
    return raw.map(
      (prLineId, milliUnits) =>
          MapEntry(prLineId, Quantity.fromMilliUnits(milliUnits)),
    );
  }

  @override
  Future<List<ShipmentProgressInput>> purchaseRequestPositions(
    String prId,
  ) async {
    final rows = await _dao.purchaseRequestLineDetails(prId);
    return rows
        .map(
          (row) => ShipmentProgressInput(
            prLineId: row.line.id,
            itemId: row.line.itemId,
            sku: row.item.sku,
            itemName: row.item.name,
            unit: row.item.unit,
            requestedQty: Quantity.fromMilliUnits(row.line.requestedQty),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<String>> purchaseRequestLineIds(String prId) async {
    final rows = await _dao.purchaseRequestLinesOf(prId);
    return rows.map((row) => row.id).toList(growable: false);
  }

  @override
  Future<List<ShipmentProgress>> shipmentProgress({
    required String prId,
    String? doId,
  }) async {
    return PurchaseRequestShipmentProgressCalculator.build(
      lines: await purchaseRequestPositions(prId),
      previouslyShippedByPrLine: await cumulativeShippedByPrLine(
        prId: prId,
        excludeDoId: doId,
      ),
      currentByPrLine: doId == null
          ? const <String, Quantity>{}
          : await allocatedByPrLine(doId),
    );
  }

  @override
  Future<List<DeliveryLineReference>> lineReferences(String doId) async {
    final rows = await _dao.linesOf(doId);
    return rows.map(_toReference).toList(growable: false);
  }

  @override
  Future<DeliveryLineReference?> lineReferenceById(String lineId) async {
    final row = await _dao.lineById(lineId);
    return row == null ? null : _toReference(row);
  }

  @override
  Future<bool> replacePreparingLines({
    required String doId,
    required List<DeliveryAllocation> allocations,
  }) => _dao.replacePreparingLines(
    doId: doId,
    lines: allocations
        .map((allocation) => _companionOf(doId, allocation))
        .toList(growable: false),
  );

  @override
  Future<bool> updatePreparingLine({
    required String lineId,
    required Quantity shippedQty,
    String? batchId,
    String? fefoOverrideReason,
    bool nearExpiryConfirmed = false,
    String? nearExpiryNote,
  }) async {
    final audit = _ExpiryAudit.of(
      batchId: batchId,
      fefoOverrideReason: fefoOverrideReason,
      nearExpiryConfirmed: nearExpiryConfirmed,
      nearExpiryNote: nearExpiryNote,
    );
    final affected = await _dao.updatePreparingLine(
      lineId: lineId,
      shippedQtyMilliUnits: shippedQty.milliUnits,
      batchId: batchId,
      fefoOverrideReason: audit.fefoOverrideReason,
      nearExpiryConfirmed: audit.nearExpiryConfirmed,
      nearExpiryNote: audit.nearExpiryNote,
    );
    return affected > 0;
  }

  @override
  Future<DeliveryLineReference?> addPreparingLine({
    required String doId,
    required DeliveryAllocation allocation,
  }) async {
    final row = await _dao.insertPreparingLine(
      doId: doId,
      line: _companionOf(doId, allocation),
    );
    return row == null ? null : _toReference(row);
  }

  @override
  Future<bool> removePreparingLine(String lineId) async =>
      await _dao.softDeletePreparingLine(lineId) > 0;

  @override
  Future<bool> updatePreparingNote({
    required String doId,
    String? note,
  }) async => await _dao.updatePreparingHeader(doId: doId, note: note) > 0;

  @override
  Future<bool> markShipped({
    required String doId,
    required String shippedBy,
    required DateTime shippedAtUtc,
    required String prId,
    required bool completesRequest,
  }) async {
    final moved = await _dao.markShipped(
      doId: doId,
      shippedBy: shippedBy,
      shippedAtUtc: shippedAtUtc,
    );
    if (moved == 0) return false;

    if (completesRequest) {
      // G-D5. The guard is `status = 'processing'` inside the statement, so a
      // request that has moved on in the meantime yields zero — and that is a
      // reason to abort rather than to shrug: the caller decided this shipment
      // completes a request that is no longer waiting for it, and committing the
      // movements against that conclusion would leave the two documents
      // disagreeing.
      final requestMoved = await _dao.markPurchaseRequestShipped(prId);
      if (requestMoved == 0) {
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
  Future<bool> removePreparing(String doId) async =>
      await _dao.softDeletePreparing(doId) > 0;

  @override
  Future<WaybillViewModel?> waybill({
    required String doId,
    String? branchId,
    required String warehouseName,
    required DateTime printedAtUtc,
  }) async {
    final detail = branchId == null
        ? await getForWarehouse(doId)
        : await getForBranch(doId: doId, branchId: branchId);
    if (detail == null) return null;

    return WaybillViewModel(
      detail: detail,
      warehouseName: warehouseName,
      printedAtUtc: printedAtUtc.toUtc(),
    );
  }

  // --- mapping --------------------------------------------------------------

  DeliveryOrderLinesCompanion _companionOf(
    String doId,
    DeliveryAllocation allocation,
  ) {
    final audit = _ExpiryAudit.of(
      batchId: allocation.batchId,
      fefoOverrideReason: allocation.fefoOverrideReason,
      nearExpiryConfirmed: allocation.nearExpiryConfirmed,
      nearExpiryNote: allocation.nearExpiryNote,
    );
    return DeliveryOrderLinesCompanion.insert(
      doId: doId,
      prLineId: allocation.prLineId,
      itemId: allocation.itemId,
      batchId: Value(allocation.batchId),
      shippedQty: allocation.qty.milliUnits,
      fefoOverrideReason: Value(audit.fefoOverrideReason),
      nearExpiryConfirmed: Value(audit.nearExpiryConfirmed),
      nearExpiryNote: Value(audit.nearExpiryNote),
    );
  }
}

/// The expiry audit of one allocation, normalised to what the table will accept.
///
/// Three CHECK constraints govern these columns, and each of them describes a
/// combination that would be *meaningless* rather than merely malformed:
///
/// * a stored reason or note is never blank — whitespace is not an explanation;
/// * a note without a confirmation would explain a decision nobody made;
/// * an item without a batch has no FEFO to override and no shelf life to confirm.
///
/// Normalising here rather than letting the constraint fire is the difference
/// between a user seeing *"Terjadi kesalahan tak terduga"* and the field they typed
/// in simply not being stored. A form legitimately reaches all three states while it
/// is being filled in — a note typed before the box is ticked, a reason left over
/// from a batch that was then cleared — and none of them is an error the officer
/// needs told about; they are just not facts yet.
class _ExpiryAudit {
  const _ExpiryAudit({
    this.fefoOverrideReason,
    this.nearExpiryConfirmed = false,
    this.nearExpiryNote,
  });

  factory _ExpiryAudit.of({
    required String? batchId,
    required String? fefoOverrideReason,
    required bool nearExpiryConfirmed,
    required String? nearExpiryNote,
  }) {
    // An item without expiry carries no batch, and therefore no expiry audit at
    // all (G-E2).
    if (batchId == null) return const _ExpiryAudit();

    final confirmed = nearExpiryConfirmed;
    return _ExpiryAudit(
      fefoOverrideReason: _normalized(fefoOverrideReason),
      nearExpiryConfirmed: confirmed,
      // The note belongs to the confirmation; without one there is nothing for it
      // to annotate.
      nearExpiryNote: confirmed ? _normalized(nearExpiryNote) : null,
    );
  }

  final String? fefoOverrideReason;
  final bool nearExpiryConfirmed;
  final String? nearExpiryNote;

  /// Trims and turns blank text into `null`.
  static String? _normalized(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

DeliveryOrder _toOrder(DeliveryOrderRow row) => DeliveryOrder(
  id: row.id,
  docNumber: row.docNumber,
  prId: row.prId,
  preparedBy: row.preparedBy,
  status: row.status,
  shippedAt: row.shippedAt,
  shippedBy: row.shippedBy,
  note: row.note,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  syncStatus: row.syncStatus,
);

/// The joins behind [DeliveryOrderWithContext] filter neither `is_active` nor
/// `deleted_at`, which is what keeps a shipped document visible after its branch
/// or the officer who prepared it is retired. The flags below turn that fact into
/// something the screens can label, rather than into a document that quietly
/// disappears from the branch's incoming list.
DeliveryOrderSummary _toSummary(DeliveryOrderWithContext row) =>
    DeliveryOrderSummary(
      order: _toOrder(row.order),
      prDocNumber: row.request.docNumber,
      prStatus: row.request.status,
      branchId: row.branch.id,
      branchCode: row.branch.code,
      branchName: row.branch.name,
      branchAddress: row.branch.address,
      preparedByName: row.preparedBy.fullName,
      requestedByName: row.requestedBy.fullName,
      shippedByName: row.shippedBy?.fullName,
      lineCount: row.lineCount,
      branchIsHistorical: _isHistorical(
        row.branch.isActive,
        row.branch.deletedAt,
      ),
      preparedByIsHistorical: _isHistorical(
        row.preparedBy.isActive,
        row.preparedBy.deletedAt,
      ),
    );

/// What "historic" means, in one place.
///
/// Deactivated (G-A4) and soft-deleted (G-A5) are separate states with the same
/// consequence for a document that already references the row: it stays valid,
/// stays readable and stays shippable, but the row can no longer be picked for
/// anything new.
bool _isHistorical(bool isActive, DateTime? deletedAt) =>
    !isActive || deletedAt != null;

DeliveryOrderLine _toLine(DeliveryOrderLineWithDetails row) =>
    DeliveryOrderLine(
      id: row.line.id,
      doId: row.line.doId,
      prLineId: row.line.prLineId,
      itemId: row.line.itemId,
      sku: row.item.sku,
      itemName: row.item.name,
      categoryId: row.item.categoryId,
      unit: row.item.unit,
      hasExpiry: row.item.hasExpiry,
      expiryAlertDays: row.item.expiryAlertDays,
      requestedQty: Quantity.fromMilliUnits(row.prLine.requestedQty),
      shippedQty: Quantity.fromMilliUnits(row.line.shippedQty),
      batchId: row.line.batchId,
      batchNo: row.batch?.batchNo,
      // A civil date is read back verbatim, never timezone converted (T-9).
      expiryDate: row.batch == null
          ? null
          : DateOnly.from(row.batch!.expiryDate),
      fefoOverrideReason: row.line.fefoOverrideReason,
      nearExpiryConfirmed: row.line.nearExpiryConfirmed,
      nearExpiryNote: row.line.nearExpiryNote,
      itemIsHistorical: _isHistorical(row.item.isActive, row.item.deletedAt),
      batchIsHistorical: row.batch != null && row.batch!.deletedAt != null,
    );

DeliveryLineReference _toReference(DeliveryOrderLineRow row) =>
    DeliveryLineReference(
      id: row.id,
      doId: row.doId,
      prLineId: row.prLineId,
      itemId: row.itemId,
      batchId: row.batchId,
      shippedQty: Quantity.fromMilliUnits(row.shippedQty),
      fefoOverrideReason: row.fefoOverrideReason,
      nearExpiryConfirmed: row.nearExpiryConfirmed,
      nearExpiryNote: row.nearExpiryNote,
    );
