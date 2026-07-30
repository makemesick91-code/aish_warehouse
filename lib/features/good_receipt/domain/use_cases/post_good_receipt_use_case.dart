import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../delivery/domain/repositories/delivery_order_repository.dart';
import '../../../inventory/domain/models/inventory_models.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../../../purchase_request/domain/repositories/purchase_request_repository.dart';
import '../models/good_receipt_models.dart';
import '../repositories/good_receipt_repository.dart';
import '../services/good_receipt_closure_policy.dart';
import 'good_receipt_guards.dart';

/// What a posted Good Receipt did (§24.5).
class GoodReceiptPostingResult {
  const GoodReceiptPostingResult({
    required this.receipt,
    required this.movements,
    required this.branchStore,
    required this.deliveryOrderReceived,
    required this.purchaseRequestClosed,
    required this.outstandingShipments,
    required this.progress,
  });

  final GoodReceipt receipt;

  /// One append-only ledger row per accepted position with a positive quantity
  /// (G-A1/G-G5). A `checked` zero and every `rejected` line contribute none.
  final List<InventoryMovement> movements;

  /// The *Gudang Cabang* location that was credited.
  final MasterLocation branchStore;

  /// Always `true` on success — the shipment moves `shipped → received` in the same
  /// transaction. Carried so the screen can state it rather than assume it.
  final bool deliveryOrderReceived;

  /// Whether this receipt was the last shipment outstanding and therefore closed the
  /// Purchase Request (§23).
  final bool purchaseRequestClosed;

  /// Shipments of the same request still waiting to be received.
  final int outstandingShipments;

  /// The decision counts the receipt was posted with.
  final GoodReceiptProgress progress;

  bool get hasDiscrepancy => progress.rejected > 0 || progress.shortage > 0;

  bool get creditedStock => movements.isNotEmpty;
}

/// `checking → posted` — the one write in this milestone that moves stock
/// (§24.5, G-G2/G-G3/G-G5, and the two foreign transitions that follow).
///
/// Everything happens in **one** database transaction, and the order is chosen so that
/// nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive or non-branch-head account
///  2. load the receipt, guard `checking`                          (G-S1)
///  3. load the shipment, guard `shipped`                          (G-G1)
///  4. load the request, guard it still stands                     (§23)
///  5. verify the actor's branch is the destination                (G-G1)
///  6. read every receipt line without a join                      (§34)
///  7. verify the line set still mirrors the shipment              (§11)
///  8. verify no line loaded is missing from the joined read        (§34)
///  9. verify every line is decided                                (G-G2)
/// 10. verify every quantity and reject reason                      (G-G3/G-G4)
/// 11. verify item and batch references, and re-check expiry        (G-E1/2, G-E5)
/// 12. resolve exactly one branch store                            (G-G5)
/// 13. order `posted_at` against the events before it               (§36)
/// 14. append a movement and credit the branch per accepted position (G-A1/G-A2)
/// 15. guarded UPDATE to `posted`, refused if any line is pending    (G-G2)
/// 16. guarded UPDATE shipment `shipped → received`
/// 17. close the Purchase Request when nothing is outstanding        (§23)
/// ```
///
/// Steps 3 to 11 re-read from the database **inside** the transaction, and that is the
/// whole point of doing them again: the checklist's numbers are a snapshot, and between
/// opening it and pressing *Posting* a batch may have crossed its expiry threshold,
/// another device may have decided a line, or master data may have been tidied away.
///
/// If any step throws, the transaction rolls back: no movement, no balance change, no
/// status change on the receipt, on the shipment or on the request, and `posted_at`
/// stays null.
///
/// ### What rejected positions do
///
/// Nothing, to any balance. They write no movement, they do not credit the branch and
/// they do **not** return stock to the warehouse — the goods are physically on the
/// branch's counter and no one has counted them back in. What they produce is a row on
/// the warehouse's selisih/retur queue, which is a derived read of the receipt itself.
/// A `return` movement here would invent stock the warehouse does not have; the
/// physical return is a later milestone's document.
class PostGoodReceiptUseCase {
  PostGoodReceiptUseCase({
    required this._receipts,
    required this._deliveries,
    required this._requests,
    required MasterDataRepository master,
    required this._posting,
    DateTime Function()? clock,
  }) : _guards = GoodReceiptGuards(master),
       _clock = clock ?? _defaultClock;

  final GoodReceiptRepository _receipts;
  final DeliveryOrderRepository _deliveries;
  final PurchaseRequestRepository _requests;
  final GoodReceiptGuards _guards;
  final StockPostingService _posting;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<GoodReceiptPostingResult> call({
    required String actorUserId,
    required String goodReceiptId,
  }) async {
    // 1. Outside the transaction: an inactive account is not a concurrency question,
    // and refusing early keeps the message precise.
    final actor = await _guards.requireBranchHeadActor(actorUserId);

    return _receipts.runInTransaction(() async {
      // 2. The receipt.
      final receipt = await _receipts.getById(goodReceiptId);
      if (receipt == null) {
        throw GoodReceiptNotFoundFailure(
          'Good Receipt tidak ditemukan.',
          grId: goodReceiptId,
        );
      }
      _guards.requireStatus(
        receipt: receipt,
        expected: GoodReceiptStatus.checking,
        attempted: GoodReceiptStatus.posted,
      );
      _guards.requireTransition(
        actor: actor,
        receipt: receipt,
        to: GoodReceiptStatus.posted,
      );

      // 3. The shipment. A `checking` receipt may have been opened hours ago; the
      // shipment must still be one that has not been received.
      final order = await _deliveries.getById(receipt.doId);
      if (order == null) {
        _guards.historicalReferenceMissing(
          grId: receipt.id,
          entity: 'delivery_orders',
          id: receipt.doId,
        );
      }
      _guards.requireDeliveryOrderPostable(order);

      // 4. The request behind it. `processing` and `shipped` both qualify: a partial
      // shipment leaves its request `processing`, and refusing that would make the
      // first partial delivery impossible to receive.
      final request = await _requests.getById(order.prId);
      if (request == null) {
        _guards.historicalReferenceMissing(
          grId: receipt.id,
          entity: 'purchase_requests',
          id: order.prId,
        );
      }
      _guards.requirePurchaseRequestReceivable(request);

      // 5. G-G1 — the destination branch is the request's, and it has to be the
      // actor's.
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: request.branchId,
      );

      // 6. Every receipt line, read without a join so a broken reference is reported
      // rather than silently dropped.
      final storedLines = await _receipts.lineReferences(receipt.id);

      // 7. The snapshot must still mirror the shipment: same allocations, no more and
      // no fewer. A missing line would credit the branch short; an extra one would
      // credit stock that never left the warehouse. Both sides are plain selects that
      // no join can filter.
      _guards.requireLineSetMatchesShipment(
        grId: receipt.id,
        expectedDoLineIds: await _receipts.deliveryOrderLineIds(order.id),
        loadedDoLineIds: storedLines.map((line) => line.doLineId),
      );

      // 8. And the joined read must not have swallowed one either — an item row that
      // is physically gone makes the detail one line shorter, silently.
      final detail = await _receipts.getDetail(receipt.id);
      if (detail == null) {
        throw GoodReceiptNotFoundFailure(
          'Good Receipt tidak ditemukan.',
          grId: goodReceiptId,
        );
      }
      await _guards.requireEveryLineLoaded(
        grId: receipt.id,
        storedLines: storedLines,
        loadedLineIds: detail.lines.map((line) => line.id),
      );

      // 9. G-G2 — the rule this whole screen exists to satisfy.
      _guards.requireAllDecided(grId: receipt.id, lines: storedLines);

      // 10–11. Items, batches, quantities, reasons and expiry. Loaded once per item so
      // a receipt with twelve batches of one product costs one lookup, not twelve.
      final nowUtc = _clock().toUtc();
      final itemsById = <String, MasterItem>{};
      final batchesByLineId = <String, MasterBatch?>{};
      for (final line in storedLines) {
        final item = itemsById[line.itemId] ??= await _guards
            .requireHistoricalItem(grId: receipt.id, itemId: line.itemId);
        batchesByLineId[line.id] = await _guards.requireBatchConsistency(
          grId: receipt.id,
          item: item,
          batchId: line.batchId,
        );
      }
      _guards.requireConsistentDecisions(
        lines: storedLines,
        itemsById: itemsById,
      );
      // G-E5 revalidated at posting time. A batch that was inside its threshold when
      // the checklist opened may be past it now, and accepting it would put goods on
      // the shelf that must not be sold. Only accepted lines are asked: a refusal is
      // already the answer G-E5 wants.
      for (final line in storedLines) {
        if (!line.isChecked) continue;
        _guards.requireAcceptableExpiry(
          lineId: line.id,
          item: itemsById[line.itemId]!,
          batch: batchesByLineId[line.id],
          nowUtc: nowUtc,
        );
      }

      // 12. Exactly one branch store, looked up by type and branch — never a
      // hard-coded id, and never guessed when there are none or several (G-G5).
      final branchStore = await _guards.requireBranchStore(request.branchId);

      // 13. Ordered against its own creation and against the shipment, on UTC instants
      // and never as text (§8.2/§36) — a device whose clock is behind must not stamp a
      // receipt before the document it belongs to existed.
      DocumentTimestampPolicy.requireOrdered(
        documentId: receipt.id,
        earlierLabel: 'created_at',
        earlierUtc: receipt.createdAt,
        laterLabel: 'posted_at',
        laterUtc: nowUtc,
        message: DocumentTimestampPolicy.deviceClockBehindMessage,
      );
      // Goods cannot be received before they were sent. `shipped_at` is non-null for a
      // `shipped` document — the table's CHECK says so — and the request's own
      // `processing_at` stands behind it transitively, so ordering against
      // `shipped_at` covers the chain. A Purchase Request has no `shipped_at` column
      // of its own: its shipping instant *is* the last Delivery Order's, which is the
      // value compared here.
      DocumentTimestampPolicy.requireOrdered(
        documentId: receipt.id,
        earlierLabel: 'shipped_at',
        earlierUtc: order.shippedAt ?? receipt.createdAt,
        laterLabel: 'posted_at',
        laterUtc: nowUtc,
        message: DocumentTimestampPolicy.deviceClockBehindMessage,
      );
      DocumentTimestampPolicy.requireOrdered(
        documentId: receipt.id,
        earlierLabel: 'processing_at',
        earlierUtc: request.processingAt ?? receipt.createdAt,
        laterLabel: 'posted_at',
        laterUtc: nowUtc,
        message: DocumentTimestampPolicy.deviceClockBehindMessage,
      );

      // 14. The ledger. `postGoodReceiptInTransaction` opens no transaction of its
      // own: it validates every position, then posts them all, then re-reads the
      // balances. Only accepted positions with something in them are passed — a
      // `checked` zero writes no movement, and a rejection writes none anywhere.
      final postable = storedLines
          .where((line) => line.addsStock)
          .map(
            (line) => GoodReceiptPostingLine(
              lineId: line.id,
              itemId: line.itemId,
              batchId: line.batchId,
              qty: line.receivedQty,
            ),
          )
          .toList(growable: false);

      final movements = postable.isEmpty
          // A receipt where everything was refused, or accepted as zero, is a real
          // outcome and must still post: the decisions are the record, and the
          // discrepancy queue is what the warehouse acts on. There is simply no stock
          // to move, and the ledger records changes rather than confirmations (G-A1).
          ? const <InventoryMovement>[]
          : await _posting.postGoodReceiptInTransaction(
              toLocationId: branchStore.id,
              actorUserId: actor.id,
              goodReceiptId: receipt.id,
              lines: postable,
            );

      // 15. The receipt. The guarded UPDATE re-checks `checking` *and* that no line is
      // pending, so a second device deciding a line between step 9 and here yields
      // zero rows — which rolls the movements above back, and is exactly why they had
      // to be in the same transaction.
      final shipments = await _receipts.shipmentDeliveryOrdersOf(order.prId);
      final closesRequest =
          GoodReceiptClosurePolicy.isClosable(request.status) &&
          GoodReceiptClosurePolicy.closesRequest(
            shipments: shipments,
            currentDoId: order.id,
          );

      // 16–17. Both foreign transitions are asserted against their *own* state
      // machines before they are written, so this milestone cannot grow a second copy
      // of either by accident.
      _guards.requireDeliveryOrderGoodReceiptTransition(
        doId: order.id,
        from: order.status,
        to: DeliveryOrderStatus.received,
      );
      if (closesRequest) {
        _guards.requirePurchaseRequestSystemTransition(
          prId: request.id,
          from: request.status,
          to: PurchaseRequestStatus.closed,
        );
      }

      final posted = await _receipts.postAtomically(
        grId: receipt.id,
        postedAtUtc: nowUtc,
        deliveryOrderId: order.id,
        prId: request.id,
        closeRequest: closesRequest,
      );
      if (!posted) _guards.concurrentUpdate(receipt);

      final updated = await _receipts.getById(receipt.id);
      if (updated == null) {
        throw GoodReceiptNotFoundFailure(
          'Good Receipt tidak ditemukan setelah posting.',
          grId: receipt.id,
        );
      }

      return GoodReceiptPostingResult(
        receipt: updated,
        movements: movements,
        branchStore: branchStore,
        deliveryOrderReceived: true,
        purchaseRequestClosed: closesRequest,
        outstandingShipments: GoodReceiptClosurePolicy.outstandingAfter(
          shipments: shipments,
          currentDoId: order.id,
        ),
        progress: detail.progress,
      );
    });
  }
}
