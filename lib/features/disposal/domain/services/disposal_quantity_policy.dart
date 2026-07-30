import '../../../../core/quantity/quantity.dart';
import '../models/disposal_models.dart';

/// How much a disposal may take off the shelf (§18).
///
/// *"Total qty per posisi pada satu pemusnahan ≤ saldo lokasi sumber saat posting
/// (stok tidak boleh negatif)."*
///
/// Pure and synchronous, and deliberately so: the same arithmetic runs while the
/// form is open — against a snapshot — and again inside the posting transaction
/// against balances read there. The second run is the authority. A form's numbers
/// are a photograph of a shelf somebody else can also reach.
///
/// ### One grain, and it is the batch
///
/// Unlike the Distribusi's quantity policy, which has to reconcile a per-item rule
/// with per-batch balances, this one has a single grain throughout: `item|batch`,
/// which is exactly how `stock_balances` is keyed and exactly how
/// `disposal_lines` is uniquely indexed. That is a consequence of the eligibility
/// rule rather than a simplification — expiry is a property of the batch, so a
/// disposal has nothing to say at item level.
///
/// The aggregation still happens. The partial unique index already stops one
/// document holding the same position twice, but an index is not the authority on a
/// document two devices assembled concurrently, and summing before comparing costs
/// nothing.
///
/// All arithmetic is exact fixed-point integer arithmetic on milli-units (Q-2):
/// `0.1 + 0.2` is `0.3`, and a partial disposal of `2.375` from `5.5` leaves exactly
/// `3.125` with no residue. Nothing here converts to `double`, and [Quantity] offers
/// no way to.
abstract final class DisposalQuantityPolicy {
  /// Whether one line's quantity is a legal disposal quantity.
  ///
  /// Strictly positive: a disposal of nothing is not a line, and the ledger records
  /// changes rather than confirmations (G-A1). The database CHECK says the same
  /// thing, and the guarded UPDATE repeats it as `? > 0` inside the statement.
  static bool isValidLineQty(Quantity qty) => qty.isPositive;

  /// `item|batch`, for a caller that holds the two ids rather than a line.
  ///
  /// One function so every map in this file is keyed identically — two callers
  /// building the key with different separators is a bug that reads as a missing
  /// balance.
  static String sourceKey(String itemId, String batchId) => '$itemId|$batchId';

  /// Total quantity per **source position** — `item|batch`.
  ///
  /// This is the map the sufficiency check compares against `stock_balances`,
  /// because that table is keyed the same way.
  static Map<String, Quantity> totalsBySourcePosition(
    Iterable<DisposalLineReference> lines,
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
  /// Not a rule — no check compares against this — but what a summary shows and
  /// what a message quotes when it has to say how much of a product a document
  /// destroys.
  static Map<String, Quantity> totalsByItem(
    Iterable<DisposalLineReference> lines,
  ) {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.itemId] = (totals[line.itemId] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  /// Whether [requested] exceeds what the shelf holds — the comparison §18 makes.
  ///
  /// Equality passes: destroying the whole of an expired batch is the *normal*
  /// case, not an edge one, and it leaves a balance of exactly zero, which
  /// `CHECK (qty_on_hand >= 0)` accepts.
  static bool exceedsAvailable({
    required Quantity requested,
    required Quantity available,
  }) => requested > available;

  /// What is left after [requested] is taken. Negative exactly when §18 is
  /// violated, which is what lets a message say *how much* short the shelf is.
  static Quantity shortfall({
    required Quantity requested,
    required Quantity available,
  }) => available - requested;

  /// Whether only part of a position is being destroyed.
  ///
  /// Allowed, and stated as its own predicate so a screen can label it rather than
  /// deriving the comparison itself: *"sisa 3.125 box tetap di lokasi"* is a fact a
  /// user acts on, and getting the boundary wrong in a widget would show a
  /// reassuring number that the ledger then contradicts.
  static bool isPartial({
    required Quantity requested,
    required Quantity available,
  }) =>
      requested.isPositive &&
      !exceedsAvailable(requested: requested, available: available) &&
      requested < available;
}
