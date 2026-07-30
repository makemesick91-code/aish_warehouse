import '../../../../core/quantity/quantity.dart';
import '../../../inventory/domain/repositories/inventory_repository.dart';
import '../models/delivery_models.dart';

/// Reads what the central warehouse currently holds, in the shape the Delivery
/// Order rules want it.
///
/// Three use cases and one provider all need the same two answers — the batch
/// candidates of an expiry-tracked item, and the single balance of an item without
/// expiry — and each of them needs them at a slightly different moment: while a
/// form is open, and again inside the posting transaction. Written once here, both
/// callers get the same numbers from the same query rather than from two
/// hand-rolled reads that could drift apart.
///
/// It deliberately offers **no write path**. Stock changes only through
/// `StockPostingService`, and a reader that could also decrement a balance would be
/// a second way into the ledger.
class DeliveryWarehouseStockReader {
  const DeliveryWarehouseStockReader(this._inventory);

  final InventoryRepository _inventory;

  /// Batch candidates of one expiry-tracked item at [warehouseLocationId],
  /// nearest expiry first.
  ///
  /// The underlying query returns positive balances only and orders by
  /// `(expiry_date, batch_no, id)`, which is the canonical FEFO order. Expired
  /// batches are **not** filtered out here: the form has to be able to show *why* a
  /// batch cannot be picked, and `DeliveryExpiryPolicy.usableCandidates` is the one
  /// place that decides usability.
  ///
  /// Archived batch rows survive the query too, because the stock they hold is
  /// real — a document allocated against a batch that was archived afterwards must
  /// still be shippable (§7.2).
  Future<List<DeliveryBatchCandidate>> batchCandidates({
    required String warehouseLocationId,
    required String itemId,
  }) async {
    final stocks = await _inventory.batchStocksForFefo(
      locationId: warehouseLocationId,
      itemId: itemId,
    );
    return stocks
        .map(
          (stock) => DeliveryBatchCandidate(
            batchId: stock.batchId,
            batchNo: stock.batchNo,
            expiryDate: stock.expiryDate,
            availableQty: stock.qtyOnHand,
          ),
        )
        .toList(growable: false);
  }

  /// The non-batch balance of one item at [warehouseLocationId] — what an item
  /// without expiry ships from (G-E2).
  Future<Quantity> unbatchedBalance({
    required String warehouseLocationId,
    required String itemId,
  }) => _inventory.balanceQty(
    locationId: warehouseLocationId,
    itemId: itemId,
    batchId: null,
  );

  /// The balance of one exact position, batch or not.
  ///
  /// The ship path re-reads this **inside its transaction**: whatever the form saw
  /// is a snapshot, and this is the number G-D3 is actually decided on.
  Future<Quantity> balanceOf({
    required String warehouseLocationId,
    required String itemId,
    String? batchId,
  }) => _inventory.balanceQty(
    locationId: warehouseLocationId,
    itemId: itemId,
    batchId: batchId,
  );
}
