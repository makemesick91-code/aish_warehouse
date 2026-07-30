import '../../../../core/quantity/quantity.dart';
import '../models/distribution_models.dart';
import 'distribution_fefo_policy.dart';

/// What one item's allocations look like across a whole distribution — the view
/// every write path needs before it can decide anything (§16/§18).
///
/// Three use cases ask the same four questions, and each of them is wrong if it looks
/// at one room only:
///
/// * how much of each batch does this document **already** take?
/// * what is therefore still **available** to a new or edited position?
/// * what would the item's **whole selection** be if this change were applied?
/// * which batch carries which override **reason** afterwards?
///
/// Written once here rather than three times, because the answers have to agree: the
/// quantity check, the FEFO evaluation and the stored reasons are three views of one
/// set of allocations, and a use case that netted the batches slightly differently
/// from the one next to it would produce a document that passes on entry and fails at
/// posting.
///
/// Pure and synchronous. It is handed the document's stored lines and one snapshot of
/// the store, and it holds no repository, so the posting path can build the same
/// object from rows re-read inside its transaction.
class DistributionAllocationPlanner {
  DistributionAllocationPlanner({
    required List<DistributionLineReference> existingLines,
    required this.stock,
  }) : _itemLines = existingLines
           .where((line) => line.itemId == stock.itemId)
           .toList(growable: false);

  /// The branch store's holdings of this item, gross — expired batches already split
  /// out by the repository (G-E4), nothing netted.
  final DistributionStockItem stock;

  /// Only this item's lines matter: batches of one product never compete with another
  /// product's, and mixing them would compare shelves that have nothing to do with
  /// each other.
  final List<DistributionLineReference> _itemLines;

  String get itemId => stock.itemId;

  List<DistributionLineReference> get itemLines => _itemLines;

  /// Every stored allocation of this item, as the FEFO policy sees them.
  ///
  /// [excludeLineId] drops one line, which is what an *edit* needs: the line being
  /// changed must not be netted against itself, or raising its quantity by one would
  /// look like asking for the whole amount twice.
  List<DistributionAllocation> storedAllocations({String? excludeLineId}) =>
      _itemLines
          .where((line) => line.id != excludeLineId)
          .map(
            (line) => DistributionAllocation(
              lineId: line.id,
              roomId: line.roomId,
              itemId: line.itemId,
              batchId: line.batchId,
              qty: line.qty,
              fefoOverrideReason: line.fefoOverrideReason,
            ),
          )
          .toList(growable: false);

  /// How much of each batch this document already takes, keyed by batch id.
  Map<String, Quantity> takenByBatch({String? excludeLineId}) =>
      DistributionFefoPolicy.takenByBatch(
        storedAllocations(excludeLineId: excludeLineId),
      );

  /// How much of the **non-batch** position this document already takes.
  ///
  /// An item without expiry has one balance row and no batches, so its "already taken"
  /// is a single number rather than a map (G-E2).
  Quantity takenUnbatched({String? excludeLineId}) => Quantity.sum(
    _itemLines
        .where((line) => line.id != excludeLineId && line.batchId == null)
        .map((line) => line.qty),
  );

  /// The store's usable batches, reduced by what this document already draws.
  ///
  /// What a new position may actually be allocated from: the store does not hold a
  /// batch twice, so a second room may only take what the first left behind. Batches
  /// that end up empty disappear, and the order stays canonical FEFO.
  List<DistributionBatchCandidate> remainingCandidates({
    String? excludeLineId,
  }) => DistributionFefoPolicy.remainingCandidates(
    candidates: stock.candidates,
    alreadyTaken: takenByBatch(excludeLineId: excludeLineId),
  );

  /// What is left of the **non-batch** balance for a new or edited position.
  ///
  /// Floored at zero: a document that already over-draws is refused by the quantity
  /// check with its own message, and reporting a negative "available" here would only
  /// make that message confusing.
  Quantity remainingUnbatched({String? excludeLineId}) {
    final remaining =
        stock.availableQty - takenUnbatched(excludeLineId: excludeLineId);
    return remaining.isNegative ? Quantity.zero() : remaining;
  }

  /// What is left of one specific batch for a new or edited position.
  Quantity remainingForBatch(String batchId, {String? excludeLineId}) {
    final candidate = stock.candidates
        .where((entry) => entry.batchId == batchId)
        .firstOrNull;
    if (candidate == null) return Quantity.zero();
    final remaining =
        candidate.availableQty -
        (takenByBatch(excludeLineId: excludeLineId)[batchId] ??
            Quantity.zero());
    return remaining.isNegative ? Quantity.zero() : remaining;
  }

  /// The item's whole selection once [proposed] is applied.
  ///
  /// This is the list FEFO compliance is judged on (§16): the stored allocations of
  /// every *other* room, plus whatever this change contributes. Judging [proposed]
  /// alone is exactly the per-room evaluation that lets an old batch be skipped by
  /// splitting a quantity.
  List<DistributionAllocation> selectionWith(
    List<DistributionAllocation> proposed, {
    String? excludeLineId,
  }) => List<DistributionAllocation>.unmodifiable([
    ...storedAllocations(excludeLineId: excludeLineId),
    ...proposed,
  ]);

  /// Which reason each batch would carry once [proposed] is applied.
  ///
  /// Existing lines contribute the reason they already store, [proposed] overrides it
  /// for the batches it names. Handed to the FEFO guard, which decides whether each is
  /// required — and returns the normalized value to persist.
  Map<String, String?> reasonsWith(
    List<DistributionAllocation> proposed, {
    String? excludeLineId,
  }) {
    final reasons = <String, String?>{};
    for (final allocation in storedAllocations(excludeLineId: excludeLineId)) {
      final batchId = allocation.batchId;
      if (batchId == null) continue;
      reasons[batchId] = allocation.fefoOverrideReason;
    }
    for (final allocation in proposed) {
      final batchId = allocation.batchId;
      if (batchId == null) continue;
      reasons[batchId] = allocation.fefoOverrideReason;
    }
    return reasons;
  }

  /// Whether the store holds nothing distributable for this item at all.
  bool get hasNoUsableStock => !stock.availableQty.isPositive;

  /// Whether every gram the store holds of this item has expired (G-E4/G-E7).
  ///
  /// Distinguished from "no stock" because the sentence a branch head needs is
  /// different: the goods are physically there and have to be disposed of, not
  /// reordered.
  bool get hasOnlyExpiredStock =>
      hasNoUsableStock && stock.expiredCandidates.isNotEmpty;
}
