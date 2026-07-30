import '../../../../core/quantity/quantity.dart';
import '../models/consumption_models.dart';

/// How much a consumption may take off a room's shelf (§18).
///
/// *"Total qty per posisi pada satu pemakaian ≤ saldo ruangan saat posting (stok tidak
/// boleh negatif)"* — the same arithmetic G-T2 states for a Distribusi and G-D3 for a
/// Delivery Order, applied to the last leg of the chain.
///
/// Pure and synchronous, and deliberately so: the same arithmetic runs while the form
/// is open — against a snapshot — and again inside the posting transaction against
/// balances read there. The second run is the authority. A form's numbers are a
/// photograph of a shelf a second nurse can also reach.
///
/// ### One grain, and it is `item|batch`
///
/// Exactly how `stock_balances` is keyed and exactly how `consumption_lines` is
/// uniquely indexed — including the unbatched case, where the batch segment of the key
/// is empty. Unlike the Distribusi's quantity policy there is no per-item rule to
/// reconcile against per-batch balances: a nurse records the batch they took, so the
/// document's grain and the balance's grain are the same thing.
///
/// The aggregation still happens. The partial unique indexes already stop one document
/// holding the same position twice, but an index is not the authority on a document two
/// devices assembled concurrently, and summing before comparing costs nothing.
///
/// ### Drafts reserve nothing
///
/// Two drafts may both name the same position, and whichever posts first wins. That is
/// not a gap: a reservation would have to be released by something, and nothing in this
/// milestone can — a draft has no expiry, no cancel and no owner but the nurse who may
/// simply never come back to it. The consequence is that the *second* posting is
/// refused with a shortfall it can act on, which is the honest outcome: the goods are
/// no longer on the shelf.
///
/// All arithmetic is exact fixed-point integer arithmetic on milli-units (Q-2):
/// `0.1 + 0.2` is `0.3`, and consuming `2.375` from `5.5` leaves exactly `3.125` with no
/// residue. Nothing here converts to `double`, and [Quantity] offers no way to.
abstract final class ConsumptionQuantityPolicy {
  /// Whether one line's quantity is a legal consumption quantity.
  ///
  /// Strictly positive: a consumption of nothing is not a line, and the ledger records
  /// changes rather than confirmations (G-A1). The database CHECK says the same thing,
  /// and the guarded UPDATE repeats it as `? > 0` inside the statement.
  static bool isValidLineQty(Quantity qty) => qty.isPositive;

  /// `item|batch`, with an empty batch segment for an item without expiry.
  ///
  /// One function so every map in this file is keyed identically — two callers building
  /// the key with different separators, or one of them omitting the empty segment, is a
  /// bug that reads as a missing balance.
  static String sourceKey(String itemId, String? batchId) =>
      '$itemId|${batchId ?? ''}';

  /// Total quantity per **source position** — `item|batch`.
  ///
  /// This is the map the sufficiency check compares against `stock_balances`, because
  /// that table is keyed the same way.
  static Map<String, Quantity> totalsBySourcePosition(
    Iterable<ConsumptionLineReference> lines,
  ) {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.positionKey] =
          (totals[line.positionKey] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  /// Total quantity per **item**, across every batch.
  ///
  /// Not a rule — no check compares against this — but what a summary shows and what a
  /// message quotes when it has to say how much of a product a document used.
  static Map<String, Quantity> totalsByItem(
    Iterable<ConsumptionLineReference> lines,
  ) {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.itemId] = (totals[line.itemId] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  /// Whether [requested] exceeds what the room holds — the comparison §18 makes.
  ///
  /// Equality passes: using the whole of what a room holds is the *normal* case, not an
  /// edge one, and it leaves a balance of exactly zero, which `CHECK (qty_on_hand >= 0)`
  /// accepts.
  static bool exceedsAvailable({
    required Quantity requested,
    required Quantity available,
  }) => requested > available;

  /// What is left after [requested] is taken. Negative exactly when §18 is violated,
  /// which is what lets a message say *how much* short the shelf is.
  static Quantity shortfall({
    required Quantity requested,
    required Quantity available,
  }) => available - requested;

  /// Whether only part of a position was used.
  ///
  /// Stated as its own predicate so a screen can label it rather than deriving the
  /// comparison itself: *"sisa 3.125 box tetap di ruangan"* is a fact a nurse acts on,
  /// and getting the boundary wrong in a widget would show a reassuring number that the
  /// ledger then contradicts.
  static bool isPartial({
    required Quantity requested,
    required Quantity available,
  }) =>
      requested.isPositive &&
      !exceedsAvailable(requested: requested, available: available) &&
      requested < available;
}
