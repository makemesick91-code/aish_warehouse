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
