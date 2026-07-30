import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';

/// One balance row enriched with the data the UI needs to render it.
class StockBalanceView {
  const StockBalanceView({
    required this.locationId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.qtyOnHand,
    required this.updatedAt,
    this.batchId,
    this.batchNo,
    this.expiryDate,
  });

  final String locationId;
  final String itemId;
  final String sku;
  final String itemName;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;
  final Quantity qtyOnHand;

  /// UTC instant of the last balance write; convert before displaying.
  final DateTime updatedAt;
  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  /// Expiry is judged against the *operational* date (T-10), so a batch stays
  /// usable for the whole of its expiry day in GMT+8 regardless of where the
  /// device thinks it is.
  bool isExpiredOn(DateTime referenceUtc) {
    final expiry = expiryDate;
    if (expiry == null) return false;
    return DateOnly.isBeforeDate(
      expiry,
      AppTimeZone.operationalDate(referenceUtc),
    );
  }

  /// Days left until expiry, negative when already expired.
  int? daysUntilExpiry(DateTime referenceUtc) {
    final expiry = expiryDate;
    if (expiry == null) return null;
    return DateOnly.daysBetween(
      AppTimeZone.operationalDate(referenceUtc),
      expiry,
    );
  }
}

/// A batch with available quantity at a location, used by the FEFO allocator.
class BatchStock {
  const BatchStock({
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    required this.qtyOnHand,
  });

  final String batchId;
  final String batchNo;
  final DateTime expiryDate;
  final Quantity qtyOnHand;
}

/// Result of a FEFO allocation: how much to take from which batch.
class FefoAllocation {
  const FefoAllocation({
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    required this.qty,
  });

  final String batchId;
  final String batchNo;
  final DateTime expiryDate;
  final Quantity qty;

  @override
  String toString() => 'FefoAllocation($batchNo, qty: ${qty.format()})';
}

/// Input for a new ledger row. There is no update counterpart on purpose:
/// `stock_movements` is append-only (G-A1).
class MovementDraft {
  const MovementDraft({
    required this.id,
    required this.itemId,
    this.batchId,
    this.fromLocationId,
    this.toLocationId,
    required this.qty,
    required this.movementType,
    required this.actorUserId,
    this.refDocType,
    this.refDocId,
    this.note,
    this.reversalOfMovementId,
  });

  final String id;
  final String itemId;
  final String? batchId;
  final String? fromLocationId;
  final String? toLocationId;
  final Quantity qty;
  final StockMovementType movementType;
  final String actorUserId;
  final String? refDocType;
  final String? refDocId;
  final String? note;
  final String? reversalOfMovementId;
}

/// One position to align during a Stok Opname review (G-O5).
///
/// Carries only what the posting needs: which physical position, what was
/// counted, and why. The difference is *not* passed in — it is recomputed
/// against the live balance at posting time.
class OpnameAdjustmentLine {
  const OpnameAdjustmentLine({
    required this.lineId,
    required this.itemId,
    this.batchId,
    required this.countedQty,
    this.note,
  });

  /// The opname line this adjustment came from, so a failure can name it.
  final String lineId;

  final String itemId;
  final String? batchId;
  final Quantity countedQty;
  final String? note;
}

/// One allocation to post when a Delivery Order ships (G-D3).
///
/// Carries only what the ledger needs: which physical position leaves the
/// warehouse, how much, and a note the movement records. The document, the
/// requested position it satisfies and the expiry audit behind it are the
/// Delivery Order's business — the ledger records that stock moved, not why the
/// batch was chosen.
class ShipmentPostingLine {
  const ShipmentPostingLine({
    required this.lineId,
    required this.itemId,
    this.batchId,
    required this.qty,
    this.note,
  });

  /// The Delivery Order line this allocation came from, so a failure can name it.
  final String lineId;

  final String itemId;
  final String? batchId;
  final Quantity qty;
  final String? note;
}

/// One accepted position to post when a Good Receipt is posted (G-G5).
///
/// Carries only what the ledger needs: which physical position entered the branch
/// store, how much, and a note the movement records. The decision behind it —
/// `checked` rather than `rejected`, and why — is the Good Receipt's business; the
/// ledger records that stock arrived, not what the branch head thought of the rest
/// of the delivery.
///
/// **Rejected positions never become one of these.** A refused line moves no stock
/// anywhere: not into the branch, and not back into the warehouse either. It goes on
/// the return list and waits for a physical-return document that does not exist yet.
class GoodReceiptPostingLine {
  const GoodReceiptPostingLine({
    required this.lineId,
    required this.itemId,
    this.batchId,
    required this.qty,
    this.note,
  });

  /// The Good Receipt line this quantity came from, so a failure can name it.
  final String lineId;

  final String itemId;
  final String? batchId;

  /// The **received** quantity, strictly positive. A `checked` line of zero is
  /// filtered out before it reaches here: the ledger records changes, not
  /// confirmations (G-A1).
  final Quantity qty;

  final String? note;
}

/// One position to post when a Distribusi is posted (G-T2/G-T4).
///
/// Carries only what the ledger needs: which physical position leaves the branch
/// store, which room location it enters, how much, and a note the movement records.
/// Which document it came from and why that batch was chosen are the Distribusi's
/// business — the ledger records that stock moved, not the reasoning behind it.
///
/// Unlike [ShipmentPostingLine] and [GoodReceiptPostingLine] this one carries a
/// **destination**, and that is the whole shape of the document: a shipment writes
/// one leg out and a receipt the matching leg in, because goods are in transit
/// between them; a distribution moves stock between two locations that both exist
/// right now, so each line is a single two-sided movement. The source is the same for
/// every line and therefore stays a parameter of the posting call.
class DistributionPostingLine {
  const DistributionPostingLine({
    required this.lineId,
    required this.toLocationId,
    required this.itemId,
    this.batchId,
    required this.qty,
    this.note,
  });

  /// The distribution line this movement came from, so a failure can name it.
  final String lineId;

  /// The `room` stock location the goods enter, resolved by type by the caller
  /// (§14). There is no way to pass a location of any other type here without the
  /// caller having resolved it wrongly, which the posting re-checks.
  final String toLocationId;

  final String itemId;
  final String? batchId;

  /// Strictly positive. A distribution of nothing is not a line, and the ledger
  /// records changes rather than confirmations (G-A1).
  final Quantity qty;

  final String? note;
}

/// One expired position to destroy when a Pemusnahan is posted (G-E7).
///
/// Carries only what the ledger needs: which physical position leaves the shelf,
/// how much, and the note the movement records. Why it was chosen, and which
/// document it came from, are the Pemusnahan's business — the ledger records that
/// stock left, not the paperwork behind it.
///
/// Two things distinguish it from every other posting line in this file:
///
/// * **`batchId` is non-null.** Only an expiry-tracked item has an expiry date to
///   be past, so a disposal position is always a batch. A nullable field here would
///   make "dispose of an item without expiry" expressible, which is a different
///   workflow this milestone does not open.
/// * **`note` is non-null.** G-E7 requires a note on every disposal movement, so it
///   is a required field rather than an optional one — the type states the rule,
///   and a caller cannot forget it.
///
/// There is no destination. A disposal has one leg: stock leaves the source and
/// enters nothing, which is what makes `to_location_id IS NULL` the shape of every
/// movement it writes.
class DisposalPostingLine {
  const DisposalPostingLine({
    required this.lineId,
    required this.itemId,
    required this.batchId,
    required this.qty,
    required this.note,
  });

  /// The disposal line this movement came from, so a failure can name it.
  final String lineId;

  final String itemId;

  /// The batch being destroyed. Never null — see the class note.
  final String batchId;

  /// Strictly positive. A disposal of nothing is not a line, and the ledger records
  /// changes rather than confirmations (G-A1).
  final Quantity qty;

  /// The audit text G-E7 demands: the document's reason, plus this position's own
  /// detail when it has one. Composed by `DisposalStockPlanBuilder` so every row of
  /// one document is worded the same way.
  final String note;
}

/// Outcome of one adjusted position.
class OpnameAdjustmentResult {
  const OpnameAdjustmentResult({
    required this.lineId,
    this.movement,
    required this.countedQty,
  });

  final String lineId;

  /// `null` when the balance already matched the count, in which case no
  /// ledger row is written at all (G-A1: the ledger records changes, not
  /// confirmations).
  final InventoryMovement? movement;

  final Quantity countedQty;

  bool get didAdjust => movement != null;
}

/// A persisted ledger row.
class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.itemId,
    this.batchId,
    this.fromLocationId,
    this.toLocationId,
    required this.qty,
    required this.movementType,
    required this.actorUserId,
    this.refDocType,
    this.refDocId,
    this.note,
    this.reversalOfMovementId,
    required this.createdAt,
  });

  final String id;
  final String itemId;
  final String? batchId;
  final String? fromLocationId;
  final String? toLocationId;
  final Quantity qty;
  final StockMovementType movementType;
  final String actorUserId;
  final String? refDocType;
  final String? refDocId;
  final String? note;
  final String? reversalOfMovementId;

  /// UTC instant (T-1).
  final DateTime createdAt;

  bool get isReversal => movementType == StockMovementType.reversal;
}
