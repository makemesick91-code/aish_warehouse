import '../../../../core/quantity/quantity.dart';
import '../models/distribution_models.dart';

/// G-T2 — how much a distribution may take out of the branch store.
///
/// *"Total qty per item pada satu distribusi ≤ saldo Gudang Cabang saat posting
/// (stok tidak boleh negatif)."*
///
/// Pure and synchronous, and deliberately so: the same arithmetic runs while the form
/// is open — against a snapshot — and again inside the posting transaction against
/// balances read there. The second run is the authority. A form's numbers are a
/// photograph of a shelf somebody else can also reach.
///
/// ### Two grains, and both are needed
///
/// The specification words the ceiling *per item*, and for an item without expiry that
/// is exactly the check: one balance row, one comparison. For a batch-tracked item the
/// **per batch** balance is the authority, because the store holds `B-OLD = 2` and
/// `B-NEW = 4` and not `6` of anything fungible — a document taking `3` from `B-OLD`
/// passes an item-level check against `6` and fails at the shelf. So
/// [totalsBySourcePosition] aggregates at `item|batch`, which is the grain
/// `stock_balances` itself uses, and the item-level total exists for what it is
/// actually good for: telling the branch head how much of a product the whole document
/// moves.
///
/// ### Aggregated across rooms, always
///
/// Every total here sums over **every room on the document** (G-T3). Two rooms each
/// taking `3` from a batch holding `5` must fail, and checking them one line at a time
/// would let both pass — that is the arithmetic G-T2 exists to prevent, and the reason
/// nothing in this file works on a single line.
///
/// All arithmetic is exact fixed-point integer arithmetic on milli-units (Q-2): `0.1 +
/// 0.2` is `0.3`, and splitting `1.5` across three rooms always adds back up to `1.5`
/// with no residue. Nothing here converts to `double`, and [Quantity] offers no way to.
abstract final class DistributionQuantityPolicy {
  /// Whether one line's quantity is a legal distribution quantity.
  ///
  /// Strictly positive: a distribution of nothing is not a line, and the ledger
  /// records changes rather than confirmations (G-A1). The database CHECK says the
  /// same thing, and the guarded UPDATE repeats it as `? > 0` inside the statement.
  static bool isValidLineQty(Quantity qty) => qty.isPositive;

  /// Total quantity per **item**, across every room and batch.
  ///
  /// What a summary shows, and what a failure message quotes when it has to say how
  /// much of a product the document moves.
  static Map<String, Quantity> totalsByItem(
    Iterable<DistributionLineReference> lines,
  ) {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.itemId] = (totals[line.itemId] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  /// Total quantity per **source position** — `item|batch` — across every room.
  ///
  /// This is the map the sufficiency check compares against `stock_balances`, because
  /// that table is keyed the same way. The `batch_id IS NULL` case is a position of
  /// its own, exactly as the partial unique index on the balances table treats it.
  static Map<String, Quantity> totalsBySourcePosition(
    Iterable<DistributionLineReference> lines,
  ) {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.sourceKey] =
          (totals[line.sourceKey] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  /// Total quantity per **room**, so the form can show what each destination receives.
  static Map<String, Quantity> totalsByRoom(
    Iterable<DistributionLineReference> lines,
  ) {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.roomId] = (totals[line.roomId] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  /// The same aggregation over unsaved allocations, keyed `item|batch`.
  ///
  /// The form works in [DistributionAllocation]s and the posting path in
  /// [DistributionLineReference]s; both need the identical sum, so both get it from
  /// here rather than each writing the loop.
  static Map<String, Quantity> allocationTotalsBySourcePosition(
    Iterable<DistributionAllocation> allocations,
  ) {
    final totals = <String, Quantity>{};
    for (final allocation in allocations) {
      final key = '${allocation.itemId}|${allocation.batchId ?? ''}';
      totals[key] = (totals[key] ?? Quantity.zero()) + allocation.qty;
    }
    return totals;
  }

  /// `item|batch`, for a caller that holds the two ids rather than a line.
  ///
  /// One function so every map in this file is keyed identically — two callers
  /// building the key with different separators is a bug that reads as a missing
  /// balance.
  static String sourceKey(String itemId, String? batchId) =>
      '$itemId|${batchId ?? ''}';

  /// Whether [requested] exceeds what the store holds — the comparison G-T2 makes.
  ///
  /// Equality passes: distributing a store's entire holding of a batch is legitimate
  /// and leaves a balance of exactly zero, which `CHECK (qty_on_hand >= 0)` accepts.
  static bool exceedsAvailable({
    required Quantity requested,
    required Quantity available,
  }) => requested > available;

  /// What is left after [requested] is taken. Negative exactly when G-T2 is violated,
  /// which is what lets a message say *how much* short the store is.
  static Quantity shortfall({
    required Quantity requested,
    required Quantity available,
  }) => available - requested;
}
