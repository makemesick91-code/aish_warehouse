import '../../../../core/quantity/quantity.dart';
import '../../../inventory/domain/repositories/inventory_repository.dart';

/// Reads what one **room** currently holds, in the shape the Pemakaian rules want it.
///
/// Three callers need the same answer at three different moments — when a line is added,
/// when one is edited, and again inside the posting transaction — and the third is the
/// authority. Written once here, every caller gets the same number from the same query
/// rather than from three hand-rolled reads that could drift apart.
///
/// ### One location kind, and the id is still a parameter
///
/// Unlike `DisposalStockReader`, which reads whichever of three location kinds its
/// document names, a consumption only ever reads a `room` location — so this class
/// *could* have taken the room and resolved it. It deliberately does not: resolving a
/// location is a two-failure-mode operation (none, and more than one), and §15 says a
/// consumption must refuse rather than guess which location the goods left. Putting that
/// resolution in a stock *reader* would hide it behind a method whose job is arithmetic.
/// The caller resolves it through `ConsumptionGuards.requireRoomLocation` — which
/// produces the right failure for each mode — and hands the id in, and the id is always
/// one the policy has already accepted for the acting nurse.
///
/// [batchId] is nullable, unlike the disposal reader's. A consumption legitimately
/// covers items without an expiry date (G-E2), and `stock_balances` holds those as a row
/// with `batch_id IS NULL` — a *different* position from any batch of the same item, and
/// exactly the one that must be read for them.
///
/// It deliberately offers **no write path**. Stock changes only through
/// `StockPostingService`, and a reader that could also decrement a balance would be a
/// second way into the ledger.
class RoomConsumptionStockReader {
  const RoomConsumptionStockReader(this._inventory);

  final InventoryRepository _inventory;

  /// The balance of one exact position — item plus batch — at [roomLocationId].
  ///
  /// The posting path re-reads this **inside its transaction**: whatever the form saw is
  /// a snapshot, and this is the number §18 is actually decided on.
  Future<Quantity> balanceOf({
    required String roomLocationId,
    required String itemId,
    String? batchId,
  }) => _inventory.balanceQty(
    locationId: roomLocationId,
    itemId: itemId,
    batchId: batchId,
  );
}
