import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/purchase_request_models.dart';

/// One cited count, reduced to what the suggestion needs: which room it covers,
/// which operational week it was filed under, and what was physically counted.
///
/// A record of primitives rather than an opname domain model, so the calculator
/// has no dependency on the Stok Opname feature and can be exercised with a
/// literal.
typedef OpnameCountSnapshot = ({
  String opnameId,
  String roomId,
  String roomName,
  int periodYear,
  int periodWeek,

  /// Every live line of the count. Batch-tracked items appear once per batch,
  /// which is exactly why step 2 below sums them before comparing to par.
  List<OpnameCountedPosition> lines,
});

/// One counted position of a cited opname.
typedef OpnameCountedPosition = ({String itemId, Quantity countedQty});

/// G-P3's `suggested_qty`, computed from cited stock opnames (spec §2.3, §14).
///
/// The formula, in the order the steps have to happen:
///
/// ```
/// per room, per item : counted   = Σ counted_qty over that item's batches
/// per room, per item : deficiency = max(0, item.min_stock_room − counted)
/// per item           : suggested  = Σ deficiency over the cited rooms
/// ```
///
/// The **order matters**, and getting it wrong is the classic error here. A
/// batch-tracked item is counted once per batch, so comparing each line to the par
/// level separately would demand the par level several times over: three batches
/// holding 2 each against a par of 5 is a deficiency of nothing, not of three
/// times 3. The batches are therefore summed to a single per-room figure first,
/// and only then measured against par.
///
/// Three things this deliberately does **not** use:
///
/// * **Current stock balances.** The whole point of basing an order on an opname
///   is that the numbers are the ones somebody physically counted. Reading live
///   balances would silently reintroduce the stock movements the count was meant
///   to settle.
/// * **The opname's `difference` column.** That is `counted − system`, a statement
///   about bookkeeping accuracy. The suggestion is about `par − counted`, a
///   statement about how full the room is. They answer different questions and
///   coincide only by accident.
/// * **`double`.** Every quantity is fixed point end to end (Q-2), so a par level
///   of 5 against a count of `2.375` produces exactly `2.625`.
///
/// ### One snapshot per room
///
/// G-P1 admits the current *and* the previous operational week, so a branch head
/// can legitimately cite two counts of the **same room** — last week's and this
/// week's. Summing both rooms' deficiencies would then double-count one shelf: a
/// par of 5 counted at 2 last week and at 4 this week is a deficiency of 1, not of
/// 3 + 1. The calculator therefore keeps **one snapshot per room, the most recent
/// one**, and the superseded citation stays linked to the document as evidence
/// without contributing arithmetic. G-O1 guarantees at most one live count per room
/// per ISO week, so "most recent" is a total order and never a coin flip.
///
/// ### Inactive items
///
/// A deactivated item is dropped from the proposal: a new document must not order
/// something master data has withdrawn (G-A4), and §14 states it as "item nonaktif
/// tidak muncul pada form baru". It remains perfectly readable on a document that
/// already requests it — that is the historical-reference path, not this one.
class SuggestedPurchaseRequestCalculator {
  const SuggestedPurchaseRequestCalculator();

  /// Turns cited counts into the lines a fresh draft should start with.
  ///
  /// [items] maps item id to its master row and must cover every item id the
  /// snapshots mention; an id that is absent is skipped here, because deciding
  /// what a missing master row means is the calling use case's job — it can raise
  /// a broken-reference failure, which a pure calculator cannot do honestly.
  ///
  /// With [includeZeroSuggestions] the result also lists items that were counted
  /// but are at or above par, as zero-suggestion candidates. The draft creation
  /// path leaves it `false` — a line whose suggestion and request would both be
  /// zero is not a line — while a screen that wants to show "counted, nothing
  /// needed" can ask for them.
  List<SuggestedPurchaseRequestLine> call({
    required List<OpnameCountSnapshot> snapshots,
    required Map<String, MasterItem> items,
    bool includeZeroSuggestions = false,
  }) {
    final perItem = <String, _ItemAccumulator>{};

    for (final snapshot in _newestPerRoom(snapshots)) {
      // Step 1: collapse every batch of an item into one quantity for this room.
      final countedInRoom = <String, Quantity>{};
      for (final line in snapshot.lines) {
        countedInRoom[line.itemId] =
            (countedInRoom[line.itemId] ?? Quantity.zero()) + line.countedQty;
      }

      countedInRoom.forEach((itemId, counted) {
        final item = items[itemId];
        if (item == null || !item.isActive) return;

        final par = Quantity.fromWhole(item.minStockRoom);
        // Step 2: a room that is at or above par contributes nothing, never a
        // negative that would cancel out another room's genuine shortfall.
        final deficiency = Quantity.max(Quantity.zero(), par - counted);

        final accumulator = perItem.putIfAbsent(
          itemId,
          () => _ItemAccumulator(item: item, parLevelPerRoom: par),
        );
        // Step 3: sum across rooms.
        accumulator.add(
          counted: counted,
          deficiency: deficiency,
          roomName: snapshot.roomName,
        );
      });
    }

    final lines = perItem.values
        .where(
          (accumulator) =>
              includeZeroSuggestions || accumulator.suggested.isPositive,
        )
        .map((accumulator) => accumulator.build())
        .toList();

    // Stable, human order: the review step is a table somebody reads top to
    // bottom, and a map's iteration order is not something to show a user.
    lines.sort((a, b) {
      final byName = a.itemName.toLowerCase().compareTo(
        b.itemName.toLowerCase(),
      );
      return byName != 0 ? byName : a.sku.compareTo(b.sku);
    });
    return List.unmodifiable(lines);
  }

  /// One snapshot per room — the newest by operational ISO week.
  ///
  /// Ties cannot happen for live documents (G-O1 allows one count per room per
  /// week); if one ever did, the first snapshot encountered wins, which at least
  /// makes the outcome deterministic rather than dependent on map ordering.
  Iterable<OpnameCountSnapshot> _newestPerRoom(
    List<OpnameCountSnapshot> snapshots,
  ) {
    final byRoom = <String, OpnameCountSnapshot>{};
    for (final snapshot in snapshots) {
      final current = byRoom[snapshot.roomId];
      if (current == null || _isNewer(snapshot, current)) {
        byRoom[snapshot.roomId] = snapshot;
      }
    }
    return byRoom.values;
  }

  bool _isNewer(OpnameCountSnapshot candidate, OpnameCountSnapshot current) {
    if (candidate.periodYear != current.periodYear) {
      return candidate.periodYear > current.periodYear;
    }
    return candidate.periodWeek > current.periodWeek;
  }
}

/// Running totals for one item while the rooms are walked.
class _ItemAccumulator {
  _ItemAccumulator({required this.item, required this.parLevelPerRoom});

  final MasterItem item;
  final Quantity parLevelPerRoom;

  Quantity counted = Quantity.zero();
  Quantity suggested = Quantity.zero();

  /// Rooms that actually contributed a shortfall. A room counted at par is not
  /// a "source" of the suggestion and listing it would misexplain the number.
  final List<String> sourceRoomNames = <String>[];

  void add({
    required Quantity counted,
    required Quantity deficiency,
    required String roomName,
  }) {
    this.counted += counted;
    if (!deficiency.isPositive) return;
    suggested += deficiency;
    if (!sourceRoomNames.contains(roomName)) sourceRoomNames.add(roomName);
  }

  SuggestedPurchaseRequestLine build() => SuggestedPurchaseRequestLine(
    itemId: item.id,
    sku: item.sku,
    itemName: item.name,
    categoryId: item.categoryId,
    unit: item.unit,
    parLevelPerRoom: parLevelPerRoom,
    countedTotal: counted,
    suggestedQty: suggested,
    sourceRoomNames: List.unmodifiable(sourceRoomNames),
  );
}
