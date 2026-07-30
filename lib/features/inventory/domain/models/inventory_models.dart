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
