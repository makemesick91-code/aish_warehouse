import '../../../../core/quantity/quantity.dart';
import '../../../inventory/domain/repositories/inventory_repository.dart';

/// Reads what one **source location** currently holds, in the shape the Pemusnahan
/// rules want it.
///
/// Three callers need the same answer at three different moments — when a line is
/// added, when one is edited, and again inside the posting transaction — and the
/// third is the authority. Written once here, every caller gets the same number
/// from the same query rather than from three hand-rolled reads that could drift
/// apart.
///
/// ### Any of the three location kinds
///
/// This is the whole difference from `DistributionBranchStockReader`, which only
/// ever reads a *Gudang Cabang*, and from `DeliveryWarehouseStockReader`, which
/// only ever reads Warehouse Pusat. Expired stock accumulates wherever stock sits,
/// so a disposal reads whichever one location its document names. The id is a
/// parameter rather than a field so no caller can accidentally hold on to another
/// location's shelf — and the id itself is always one `DisposalLocationPolicy` has
/// already accepted for the acting user (§15), never one passed in from a screen.
///
/// It deliberately offers **no write path**. Stock changes only through
/// `StockPostingService`, and a reader that could also decrement a balance would be
/// a second way into the ledger.
class DisposalStockReader {
  const DisposalStockReader(this._inventory);

  final InventoryRepository _inventory;

  /// The balance of one exact position — item plus batch — at [sourceLocationId].
  ///
  /// The posting path re-reads this **inside its transaction**: whatever the form
  /// saw is a snapshot, and this is the number §18 is actually decided on.
  ///
  /// [batchId] is required and non-null, unlike every other stock reader in the
  /// application. A disposal position is always a batch (see `disposal_tables.dart`),
  /// and a nullable parameter here would silently read the *unbatched* balance row —
  /// a different position that, for an expiry-tracked item, should not exist at all.
  Future<Quantity> balanceOf({
    required String sourceLocationId,
    required String itemId,
    required String batchId,
  }) => _inventory.balanceQty(
    locationId: sourceLocationId,
    itemId: itemId,
    batchId: batchId,
  );
}
