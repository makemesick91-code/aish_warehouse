import '../../../../core/quantity/quantity.dart';
import '../../../inventory/domain/repositories/inventory_repository.dart';
import '../models/distribution_models.dart';

/// Reads what one **branch store** currently holds, in the shape the Distribusi
/// rules want it.
///
/// Four callers need the same two answers — the batch candidates of an
/// expiry-tracked item, and the single balance of an item without expiry — and each
/// needs them at a different moment: while the form is open, when a line is added,
/// when one is edited, and again inside the posting transaction. Written once here,
/// every caller gets the same numbers from the same query rather than from four
/// hand-rolled reads that could drift apart.
///
/// ### The store, never the warehouse
///
/// This is the whole difference between a distribution and a shipment. `Delivery
/// Order` reads Warehouse Pusat; a distribution reads the *Gudang Cabang* of the
/// document's own branch, because the goods it moves are already at the branch.
/// The location id is a parameter rather than a field so no caller can accidentally
/// hold on to another branch's store — and the id itself is always resolved by type
/// and branch (§14), never passed in from a screen.
///
/// It deliberately offers **no write path**. Stock changes only through
/// `StockPostingService`, and a reader that could also decrement a balance would be
/// a second way into the ledger.
class DistributionBranchStockReader {
  const DistributionBranchStockReader(this._inventory);

  final InventoryRepository _inventory;

  /// Batch candidates of one expiry-tracked item at [branchStoreLocationId],
  /// nearest expiry first.
  ///
  /// The underlying query returns positive balances only and orders by
  /// `(expiry_date, batch_no, id)`, which is the canonical FEFO order. Expired
  /// batches are **not** filtered out here: the form has to be able to show *why* a
  /// batch cannot be picked, and `DistributionExpiryPolicy.usableCandidates` is the
  /// one place that decides usability (G-E4).
  ///
  /// Archived batch rows survive the query too, because the stock they hold is
  /// real — a draft allocated against a batch that was archived afterwards must
  /// still be postable (§32).
  Future<List<DistributionBatchCandidate>> batchCandidates({
    required String branchStoreLocationId,
    required String itemId,
  }) async {
    final stocks = await _inventory.batchStocksForFefo(
      locationId: branchStoreLocationId,
      itemId: itemId,
    );
    return stocks
        .map(
          (stock) => DistributionBatchCandidate(
            batchId: stock.batchId,
            batchNo: stock.batchNo,
            expiryDate: stock.expiryDate,
            availableQty: stock.qtyOnHand,
          ),
        )
        .toList(growable: false);
  }

  /// The non-batch balance of one item at [branchStoreLocationId] — what an item
  /// without expiry is distributed from (G-E2).
  Future<Quantity> unbatchedBalance({
    required String branchStoreLocationId,
    required String itemId,
  }) => _inventory.balanceQty(
    locationId: branchStoreLocationId,
    itemId: itemId,
    batchId: null,
  );

  /// The balance of one exact position, batch or not.
  ///
  /// The posting path re-reads this **inside its transaction**: whatever the form saw
  /// is a snapshot, and this is the number G-T2 is actually decided on.
  Future<Quantity> balanceOf({
    required String branchStoreLocationId,
    required String itemId,
    String? batchId,
  }) => _inventory.balanceQty(
    locationId: branchStoreLocationId,
    itemId: itemId,
    batchId: batchId,
  );
}
