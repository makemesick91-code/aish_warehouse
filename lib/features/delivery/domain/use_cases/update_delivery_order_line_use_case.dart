import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/delivery_models.dart';
import '../repositories/delivery_order_repository.dart';
import '../services/delivery_quantity_policy.dart';
import '../services/delivery_warehouse_stock_reader.dart';
import 'delivery_order_guards.dart';

/// Edits one allocation of a `preparing` Delivery Order (§20.3).
///
/// What the warehouse may change: the quantity, the batch, the FEFO override
/// reason, and the near-expiry confirmation and its note. What it may **not**
/// change, and has no argument to express: which requested position the line
/// satisfies and which item it moves. That is G-D4 — *"Warehouse tidak bisa
/// menambahkan item yang tidak ada di PR"* — and the repository offers no writer
/// that could reach either column, so repointing a line is expressed as removing
/// it and allocating another.
///
/// Every check the ship path performs is performed here too, on purpose. Catching
/// an expired batch or a missing reason while the form is open is worth far more
/// than catching it at the moment of posting — and yet none of it is the
/// authority: the balances, the cumulative shipped total and the FEFO order are
/// all re-read inside the shipping transaction, because all three can move while
/// a form sits open. This is the helpful check; that one is the binding one.
class UpdateDeliveryOrderLineUseCase {
  UpdateDeliveryOrderLineUseCase({
    required this._deliveries,
    required MasterDataRepository master,
    required this._stock,
    DateTime Function()? clock,
  }) : _guards = DeliveryOrderGuards(master),
       _clock = clock ?? _defaultClock;

  final DeliveryOrderRepository _deliveries;
  final DeliveryWarehouseStockReader _stock;
  final DeliveryOrderGuards _guards;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<void> call({
    required String actorUserId,
    required String lineId,
    required Quantity shippedQty,
    String? batchId,
    String? fefoOverrideReason,
    bool nearExpiryConfirmed = false,
    String? nearExpiryNote,
  }) async {
    final actor = await _guards.requireWarehouseActor(actorUserId);
    final warehouse = await _guards.requireWarehouseLocation();
    final nowUtc = _clock().toUtc();

    await _deliveries.runInTransaction(() async {
      // The line is located through the document rather than looked up on its own,
      // so "which document does this line belong to" is answered by the same read
      // that authorises the edit.
      final reference = await _findLine(lineId);
      final order = await _deliveries.getById(reference.doId);
      if (order == null) {
        throw DeliveryOrderNotFoundFailure(
          'Surat Jalan tidak ditemukan.',
          doId: reference.doId,
        );
      }
      _guards.requireStatus(
        order: order,
        expected: DeliveryOrderStatus.preparing,
      );
      _guards.requireTransition(
        actor: actor,
        order: order,
        to: DeliveryOrderStatus.shipped,
      );

      if (!DeliveryQuantityPolicy.isValidAllocation(shippedQty)) {
        throw ValidationFailure(
          'Jumlah kirim harus lebih dari 0 (diterima ${shippedQty.format()}).',
        );
      }

      // G-D4: the position this line satisfies must still be one of the parent
      // request's, and must still ask for this item.
      final positions = await _deliveries.purchaseRequestPositions(order.prId);
      final byPrLineId = {
        for (final position in positions) position.prLineId: position,
      };
      _guards.requireAllocationsBelongToRequest(
        doId: order.id,
        positionsByPrLineId: byPrLineId,
        lines: [reference],
      );
      final position = byPrLineId[reference.prLineId]!;

      final item = await _guards.requireHistoricalItem(
        doId: order.id,
        itemId: reference.itemId,
      );
      final batch = await _guards.requireBatchConsistency(
        doId: order.id,
        item: item,
        batchId: batchId,
      );

      // The edited state of the whole document, as it *would* be — so the checks
      // below see the change rather than what is still stored.
      final storedLines = await _deliveries.lineReferences(order.id);
      final proposed = storedLines
          .map(
            (line) => line.id == lineId
                ? DeliveryLineReference(
                    id: line.id,
                    doId: line.doId,
                    prLineId: line.prLineId,
                    itemId: line.itemId,
                    batchId: batchId,
                    shippedQty: shippedQty,
                    fefoOverrideReason: fefoOverrideReason,
                    nearExpiryConfirmed: nearExpiryConfirmed,
                    nearExpiryNote: nearExpiryNote,
                  )
                : line,
          )
          .toList(growable: false);

      _guards.requireNoDuplicateAllocations(doId: order.id, lines: proposed);

      // G-D2, against the cumulative total of every *other* document.
      final previouslyShipped = await _deliveries.cumulativeShippedByPrLine(
        prId: order.prId,
        excludeDoId: order.id,
      );
      final proposedForPosition = Quantity.sum(
        proposed
            .where((line) => line.prLineId == reference.prLineId)
            .map((line) => line.shippedQty),
      );
      if (DeliveryQuantityPolicy.exceedsRequested(
        requestedQty: position.requestedQty,
        cumulativeShippedQty:
            previouslyShipped[reference.prLineId] ?? Quantity.zero(),
        additionalQty: proposedForPosition,
      )) {
        final alreadyShipped =
            previouslyShipped[reference.prLineId] ?? Quantity.zero();
        throw DeliveryQuantityExceedsRequestedFailure(
          'Jumlah kirim ${position.itemName} melebihi sisa permintaan cabang '
          '(${DeliveryQuantityPolicy.remaining(requestedQty: position.requestedQty, cumulativeShippedQty: alreadyShipped).formatWithUnit(position.unit)}).',
          prLineId: reference.prLineId,
          requested: position.requestedQty,
          alreadyShipped: alreadyShipped,
          attempted: proposedForPosition,
        );
      }

      // G-E4, in the order that matters: expired is refused whatever the
      // confirmation says.
      if (batch != null) {
        _guards.requireExpiryAcceptable(
          item: item,
          batch: batch,
          nearExpiryConfirmed: nearExpiryConfirmed,
          nowUtc: nowUtc,
        );

        // G-E3, evaluated over the whole position's selection: FEFO is about how
        // one line's demand was sourced, and one allocation of a split cannot be
        // judged alone.
        final candidates = await _stock.batchCandidates(
          warehouseLocationId: warehouse.id,
          itemId: item.id,
        );
        _guards.requireFefoJustified(
          candidates: candidates,
          selection: proposed
              .where((line) => line.prLineId == reference.prLineId)
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

      // G-D3 as an early warning. The binding check happens inside the shipping
      // transaction, against the balance as it is then.
      final available = await _stock.balanceOf(
        warehouseLocationId: warehouse.id,
        itemId: item.id,
        batchId: batchId,
      );
      final drawnFromSamePosition = Quantity.sum(
        proposed
            .where((line) => line.itemId == item.id && line.batchId == batchId)
            .map((line) => line.shippedQty),
      );
      if (drawnFromSamePosition > available) {
        throw InsufficientWarehouseStockFailure(
          'Saldo warehouse untuk ${item.name}'
          '${batch == null ? '' : ' batch ${batch.batchNo}'} hanya '
          '${available.formatWithUnit(item.unit)}, sedangkan Surat Jalan ini '
          'mengalokasikan ${drawnFromSamePosition.formatWithUnit(item.unit)}.',
          itemId: item.id,
          batchId: batchId,
          available: available,
          requested: drawnFromSamePosition,
        );
      }

      final updated = await _deliveries.updatePreparingLine(
        lineId: lineId,
        shippedQty: shippedQty,
        batchId: batchId,
        fefoOverrideReason: DeliveryOrderGuards.normalizeReason(
          fefoOverrideReason,
        ),
        nearExpiryConfirmed: nearExpiryConfirmed,
        nearExpiryNote: DeliveryOrderGuards.normalizeReason(nearExpiryNote),
      );
      if (!updated) _guards.concurrentUpdate(order);
    });
  }

  /// Adds one allocation to a `preparing` document.
  ///
  /// The batch picker uses it when an officer splits a position across an extra
  /// batch. It runs the same checks [call] does, because "add" and "edit" differ
  /// only in whether a row already exists.
  Future<void> add({
    required String actorUserId,
    required String deliveryOrderId,
    required String prLineId,
    required Quantity shippedQty,
    String? batchId,
    String? fefoOverrideReason,
    bool nearExpiryConfirmed = false,
    String? nearExpiryNote,
  }) async {
    final actor = await _guards.requireWarehouseActor(actorUserId);
    final warehouse = await _guards.requireWarehouseLocation();
    final nowUtc = _clock().toUtc();

    await _deliveries.runInTransaction(() async {
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
      );
      _guards.requireTransition(
        actor: actor,
        order: order,
        to: DeliveryOrderStatus.shipped,
      );

      if (!DeliveryQuantityPolicy.isValidAllocation(shippedQty)) {
        throw ValidationFailure(
          'Jumlah kirim harus lebih dari 0 (diterima ${shippedQty.format()}).',
        );
      }

      final positions = await _deliveries.purchaseRequestPositions(order.prId);
      final position = positions
          .where((entry) => entry.prLineId == prLineId)
          .firstOrNull;
      if (position == null) {
        throw DeliveryPrLineMismatchFailure(
          'Baris Purchase Request tersebut bukan milik Purchase Request Surat '
          'Jalan ini.',
          doId: order.id,
          prLineId: prLineId,
        );
      }

      final item = await _guards.requireHistoricalItem(
        doId: order.id,
        itemId: position.itemId,
      );
      final batch = await _guards.requireBatchConsistency(
        doId: order.id,
        item: item,
        batchId: batchId,
      );

      final storedLines = await _deliveries.lineReferences(order.id);
      final proposed = <DeliveryLineReference>[
        ...storedLines,
        DeliveryLineReference(
          id: '',
          doId: order.id,
          prLineId: prLineId,
          itemId: position.itemId,
          batchId: batchId,
          shippedQty: shippedQty,
          fefoOverrideReason: fefoOverrideReason,
          nearExpiryConfirmed: nearExpiryConfirmed,
          nearExpiryNote: nearExpiryNote,
        ),
      ];
      _guards.requireNoDuplicateAllocations(doId: order.id, lines: proposed);

      final previouslyShipped = await _deliveries.cumulativeShippedByPrLine(
        prId: order.prId,
        excludeDoId: order.id,
      );
      final proposedForPosition = Quantity.sum(
        proposed
            .where((line) => line.prLineId == prLineId)
            .map((line) => line.shippedQty),
      );
      final alreadyShipped = previouslyShipped[prLineId] ?? Quantity.zero();
      if (DeliveryQuantityPolicy.exceedsRequested(
        requestedQty: position.requestedQty,
        cumulativeShippedQty: alreadyShipped,
        additionalQty: proposedForPosition,
      )) {
        throw DeliveryQuantityExceedsRequestedFailure(
          'Jumlah kirim ${position.itemName} melebihi sisa permintaan cabang.',
          prLineId: prLineId,
          requested: position.requestedQty,
          alreadyShipped: alreadyShipped,
          attempted: proposedForPosition,
        );
      }

      if (batch != null) {
        _guards.requireExpiryAcceptable(
          item: item,
          batch: batch,
          nearExpiryConfirmed: nearExpiryConfirmed,
          nowUtc: nowUtc,
        );
        _guards.requireFefoJustified(
          candidates: await _stock.batchCandidates(
            warehouseLocationId: warehouse.id,
            itemId: item.id,
          ),
          selection: proposed
              .where((line) => line.prLineId == prLineId)
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

      final added = await _deliveries.addPreparingLine(
        doId: order.id,
        allocation: DeliveryAllocation(
          prLineId: prLineId,
          itemId: position.itemId,
          batchId: batchId,
          qty: shippedQty,
          fefoOverrideReason: DeliveryOrderGuards.normalizeReason(
            fefoOverrideReason,
          ),
          nearExpiryConfirmed: nearExpiryConfirmed,
          nearExpiryNote: DeliveryOrderGuards.normalizeReason(nearExpiryNote),
        ),
      );
      if (added == null) _guards.concurrentUpdate(order);
    });
  }

  /// The header note of a `preparing` document — courier, vehicle, handover.
  Future<void> saveNote({
    required String actorUserId,
    required String deliveryOrderId,
    String? note,
  }) async {
    final actor = await _guards.requireWarehouseActor(actorUserId);

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
    );
    _guards.requireTransition(
      actor: actor,
      order: order,
      to: DeliveryOrderStatus.shipped,
    );

    final saved = await _deliveries.updatePreparingNote(
      doId: deliveryOrderId,
      note: DeliveryOrderGuards.normalizeReason(note),
    );
    if (!saved) _guards.concurrentUpdate(order);
  }

  /// The allocation, or the failure that names it.
  ///
  /// Returns identifiers only — no item name, no unit, no batch number — so a
  /// caller that has not yet been cleared for the document learns nothing from it.
  /// The `do_id` it carries is what the caller then authorises against.
  Future<DeliveryLineReference> _findLine(String lineId) async {
    final reference = await _deliveries.lineReferenceById(lineId);
    if (reference == null) {
      throw DeliveryOrderLineNotFoundFailure(
        'Baris Surat Jalan tidak ditemukan.',
        lineId: lineId,
      );
    }
    return reference;
  }
}
