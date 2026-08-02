import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../../../inventory/domain/models/inventory_models.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../../../purchase_request/domain/repositories/purchase_request_repository.dart';
import '../models/delivery_models.dart';
import '../repositories/delivery_order_repository.dart';
import '../services/delivery_quantity_policy.dart';
import '../services/delivery_warehouse_stock_reader.dart';
import 'delivery_order_guards.dart';

/// What a posted shipment did (§20.5).
class ShipmentResult {
  const ShipmentResult({
    required this.order,
    required this.movements,
    required this.progress,
    required this.purchaseRequestCompleted,
  });

  final DeliveryOrder order;

  /// One append-only ledger row per allocation (G-A1).
  final List<InventoryMovement> movements;

  /// The parent request's per-position picture *after* this shipment.
  final List<ShipmentProgress> progress;

  /// Whether this shipment completed every requested position and therefore moved
  /// the Purchase Request to `shipped` (G-D5).
  final bool purchaseRequestCompleted;

  bool get isPartialShipment => !purchaseRequestCompleted;
}

/// `preparing → shipped` — the one write in this milestone that moves stock
/// (§20.5, G-D2/G-D3/G-D5).
///
/// Everything happens in **one** database transaction, and the order is chosen so
/// that nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive or non-warehouse account
///  2. resolve exactly one central-warehouse location            (G-D3)
///  3. load the document, guard `preparing`                      (G-S1)
///  4. load the request, guard `processing`                      (G-D1)
///  5. verify every allocation loaded — no join swallowed a row
///  6. verify PR line / item / batch integrity                   (G-D4, G-E1/2)
///  7. verify the cumulative shipped total                       (G-D2)
///  8. verify expiry and the FEFO justification                  (G-E3/G-E4)
///  9. verify the warehouse balance of every position            (G-D3)
/// 10. append every movement, decrease every balance             (G-A1/G-A2)
/// 11. re-read the balances and refuse a negative one            (G-A2)
/// 12. guarded UPDATE to `shipped`, with `shipped_at`/`shipped_by`
/// 13. if every position is now complete, PR `processing → shipped` (G-D5)
/// ```
///
/// Steps 7 to 9 re-read from the database **inside** the transaction, and that is
/// the whole point of doing them again: the form's numbers are a snapshot, and
/// between opening it and pressing *Kirim* another officer may have shipped the
/// remaining quantity or another document may have taken the batch. Two shipments
/// racing for the same last unit therefore produce one commit and one rollback —
/// never two half-shipments, never a negative balance.
///
/// If any step throws, the transaction rolls back: no movement, no balance change,
/// no status change, no timestamp, and the Purchase Request stays exactly where it
/// was.
///
/// **The branch gains nothing here.** `to_location_id` is NULL on every movement:
/// the goods are in transit until Good Receipt checks them in (spec §2.5). And the
/// request never becomes `closed` — that happens when every shipment has been
/// received, which is the next milestone's document to write.
class ShipDeliveryOrderUseCase {
  ShipDeliveryOrderUseCase({
    required this._deliveries,
    required this._requests,
    required MasterDataRepository master,
    required this._posting,
    required this._stock,
    this._outbox = const NoopSyncOutboxWriter(),
    DateTime Function()? clock,
  }) : _guards = DeliveryOrderGuards(master),
       _clock = clock ?? _defaultClock;

  final DeliveryOrderRepository _deliveries;
  final PurchaseRequestRepository _requests;
  final DeliveryOrderGuards _guards;
  final StockPostingService _posting;
  final DeliveryWarehouseStockReader _stock;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<ShipmentResult> call({
    required String actorUserId,
    required String deliveryOrderId,
  }) async {
    // 1–2. Outside the transaction: neither an inactive account nor a missing
    // warehouse is a concurrency question, and refusing early keeps the message
    // precise.
    final actor = await _guards.requireWarehouseActor(actorUserId);
    final warehouse = await _guards.requireWarehouseLocation();

    return _deliveries.runInTransaction(() async {
      // 3. The document.
      final order = await _deliveries.getById(deliveryOrderId);
      if (order == null) {
        throw DeliveryOrderNotFoundFailure(
          'Surat Jalan tidak ditemukan.',
          doId: deliveryOrderId,
        );
      }
      _guards.requireStatus(
        order: order,
        expected: DeliveryOrderStatus.preparing,
        attempted: DeliveryOrderStatus.shipped,
      );
      _guards.requireTransition(
        actor: actor,
        order: order,
        to: DeliveryOrderStatus.shipped,
      );

      // 4. The request. A `preparing` document may have been prepared days ago
      // against an order that has since been rejected or cancelled; stock must not
      // leave the warehouse for it.
      final request = await _requests.getById(order.prId);
      if (request == null) {
        throw HistoricalDeliveryReferenceMissingFailure(
          'Surat Jalan tidak dapat dikirim karena Purchase Request-nya tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'purchase_requests',
          id: order.prId,
          doId: order.id,
        );
      }
      _guards.requirePurchaseRequestShippable(request);

      // 5. Every allocation, read without a join so a broken reference is
      // reported rather than silently dropped.
      final storedLines = await _deliveries.lineReferences(order.id);
      _guards.requireNotEmpty(
        doId: order.id,
        docNumber: order.docNumber,
        lines: storedLines,
      );
      _guards.requirePositiveQuantities(storedLines);
      _guards.requireNoDuplicateAllocations(doId: order.id, lines: storedLines);

      final detail = await _deliveries.getDetail(order.id);
      if (detail == null) {
        throw DeliveryOrderNotFoundFailure(
          'Surat Jalan tidak ditemukan.',
          doId: deliveryOrderId,
        );
      }
      await _guards.requireEveryLineLoaded(
        doId: order.id,
        storedLines: storedLines,
        loadedLineIds: detail.lines.map((line) => line.id),
      );

      // 6. Requested positions. Both directions of the set check matter: a
      // position whose row is gone would shrink the order G-D5 is measured
      // against, and an allocation pointing outside the request would ship
      // something nobody asked for (G-D4).
      final positions = await _deliveries.purchaseRequestPositions(order.prId);
      final positionsByPrLineId = {
        for (final position in positions) position.prLineId: position,
      };
      // The request must still agree with itself. `positions` comes from a join on
      // `items`; the stored ids come from a plain select that no join can filter.
      // A position missing from the first but present in the second means the
      // order has quietly lost a line — and a shipment measured against the
      // remainder could complete it, which G-D5 would read as a fulfilled request.
      _guards.requireEveryPositionLoaded(
        doId: order.id,
        storedPrLineIds: await _deliveries.purchaseRequestLineIds(order.prId),
        loadedPrLineIds: positionsByPrLineId.keys,
      );
      _guards.requireAllocationsBelongToRequest(
        doId: order.id,
        positionsByPrLineId: positionsByPrLineId,
        lines: storedLines,
      );

      // 7. G-D2, against quantities read here rather than in the form.
      final previouslyShipped = await _deliveries.cumulativeShippedByPrLine(
        prId: order.prId,
        excludeDoId: order.id,
      );
      final currentByPrLine = <String, Quantity>{};
      for (final line in storedLines) {
        currentByPrLine[line.prLineId] =
            (currentByPrLine[line.prLineId] ?? Quantity.zero()) +
            line.shippedQty;
      }
      final progress = PurchaseRequestShipmentProgressCalculator.build(
        lines: positions,
        previouslyShippedByPrLine: previouslyShipped,
        currentByPrLine: currentByPrLine,
      );
      _guards.requireWithinRequested(progress);

      // 8. Expiry and FEFO, per position, against the balances as they are now.
      final nowUtc = _clock().toUtc();
      final items = <String, MasterItem>{};
      for (final line in storedLines) {
        items[line.itemId] ??= await _guards.requireHistoricalItem(
          doId: order.id,
          itemId: line.itemId,
        );
      }

      final byPrLine = <String, List<DeliveryLineReference>>{};
      for (final line in storedLines) {
        byPrLine
            .putIfAbsent(line.prLineId, () => <DeliveryLineReference>[])
            .add(line);
      }

      for (final entry in byPrLine.entries) {
        final item = items[entry.value.first.itemId]!;
        for (final line in entry.value) {
          final batch = await _guards.requireBatchConsistency(
            doId: order.id,
            item: item,
            batchId: line.batchId,
          );
          if (batch == null) continue;
          _guards.requireExpiryAcceptable(
            item: item,
            batch: batch,
            nearExpiryConfirmed: line.nearExpiryConfirmed,
            nowUtc: nowUtc,
          );
        }

        if (!item.hasExpiry) continue;
        _guards.requireFefoJustified(
          candidates: await _stock.batchCandidates(
            warehouseLocationId: warehouse.id,
            itemId: item.id,
          ),
          selection: entry.value
              .map(
                (line) => DeliveryAllocation(
                  prLineId: line.prLineId,
                  itemId: line.itemId,
                  batchId: line.batchId,
                  qty: line.shippedQty,
                  fefoOverrideReason: line.fefoOverrideReason,
                  nearExpiryConfirmed: line.nearExpiryConfirmed,
                  nearExpiryNote: line.nearExpiryNote,
                ),
              )
              .toList(growable: false),
          nowUtc: nowUtc,
        );
      }

      // 9–11. The ledger. `postShipmentInTransaction` opens no transaction of its
      // own: it validates every allocation, then posts them all, then re-reads the
      // balances and refuses to let a negative one commit.
      final movements = await _posting.postShipmentInTransaction(
        fromLocationId: warehouse.id,
        actorUserId: actor.id,
        deliveryOrderId: order.id,
        lines: storedLines
            .map(
              (line) => ShipmentPostingLine(
                lineId: line.id,
                itemId: line.itemId,
                batchId: line.batchId,
                qty: line.shippedQty,
                note: line.fefoOverrideReason,
              ),
            )
            .toList(growable: false),
      );

      // 12. The document. Ordered against its own creation on UTC instants, never
      // as text (§8.2) — a device whose clock is behind must not stamp a shipment
      // before the document it belongs to existed.
      DocumentTimestampPolicy.requireOrdered(
        documentId: order.id,
        earlierLabel: 'created_at',
        earlierUtc: order.createdAt,
        laterLabel: 'shipped_at',
        laterUtc: nowUtc,
        message: DocumentTimestampPolicy.deviceClockBehindMessage,
      );
      // And against the moment the warehouse took the order on: a shipment cannot
      // predate the request being processed.
      DocumentTimestampPolicy.requireOrdered(
        documentId: order.id,
        earlierLabel: 'processing_at',
        earlierUtc: request.processingAt ?? order.createdAt,
        laterLabel: 'shipped_at',
        laterUtc: nowUtc,
        message: DocumentTimestampPolicy.deviceClockBehindMessage,
      );

      // 13. G-D5, decided from the quantities verified in step 7 — not from what
      // the form believed. An over-shipped document never reaches here, because
      // step 7 refuses it, so "complete" can only mean exactly complete.
      final completesRequest = DeliveryQuantityPolicy.completesRequest(
        progress,
      );
      if (completesRequest) {
        _guards.requirePurchaseRequestSystemTransition(
          prId: order.prId,
          from: request.status,
          to: PurchaseRequestStatus.shipped,
        );
      }

      final shipped = await _deliveries.markShipped(
        doId: order.id,
        shippedBy: actor.id,
        shippedAtUtc: nowUtc,
        prId: order.prId,
        completesRequest: completesRequest,
      );
      // Zero rows means somebody else shipped this document between the read and
      // the write. Throwing here rolls the movements above back — which is exactly
      // why they had to be in the same transaction.
      if (!shipped) _guards.concurrentUpdate(order);

      await _outbox.enqueueCurrentAggregate(
        operation: SyncOperationType.shipDeliveryOrder,
        aggregateType: SyncAggregateType.deliveryOrder,
        aggregateId: order.id,
        actorUserId: actor.id,
        occurredAtUtc: nowUtc,
      );

      final updated = await _deliveries.getById(order.id);
      if (updated == null) {
        throw DeliveryOrderNotFoundFailure(
          'Surat Jalan tidak ditemukan setelah pengiriman.',
          doId: order.id,
        );
      }

      return ShipmentResult(
        order: updated,
        movements: movements,
        progress: progress,
        purchaseRequestCompleted: completesRequest,
      );
    });
  }
}
