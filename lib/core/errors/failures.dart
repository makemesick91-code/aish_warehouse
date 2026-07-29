import '../enums/app_enums.dart';
import '../quantity/quantity.dart';

/// Business-rule failures for Aish Warehouse.
///
/// Every guardrail violation throws a specific subtype so the UI can present a
/// meaningful Indonesian message instead of a raw stack trace.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Generic input validation (qty, empty text, illegal combination…).
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message);
}

/// The source location does not hold enough stock for the requested posting.
final class InsufficientStockFailure extends AppFailure {
  const InsufficientStockFailure(
    super.message, {
    required this.itemId,
    required this.locationId,
    this.batchId,
    required this.available,
    required this.requested,
  });

  final String itemId;
  final String locationId;
  final String? batchId;
  final Quantity available;
  final Quantity requested;
}

/// Item is tracked per batch (`has_expiry = true`) but no batch was supplied.
final class BatchRequiredFailure extends AppFailure {
  const BatchRequiredFailure(super.message, {required this.itemId});

  final String itemId;
}

/// Item is not tracked per batch but a batch was supplied.
final class BatchNotAllowedFailure extends AppFailure {
  const BatchNotAllowedFailure(super.message, {required this.itemId});

  final String itemId;
}

/// The batch is past its expiry date and cannot be used for this movement.
final class ExpiredBatchFailure extends AppFailure {
  const ExpiredBatchFailure(
    super.message, {
    required this.batchId,
    required this.expiryDate,
  });

  final String batchId;
  final DateTime expiryDate;
}

/// Location is missing, of the wrong type, or source equals destination.
final class InvalidLocationFailure extends AppFailure {
  const InvalidLocationFailure(super.message);
}

/// Attempt to mutate the append-only ledger.
final class MovementImmutableFailure extends AppFailure {
  const MovementImmutableFailure(super.message, {required this.movementId});

  final String movementId;
}

/// A referenced row (item, batch, location, user…) does not exist.
final class EntityNotFoundFailure extends AppFailure {
  const EntityNotFoundFailure(
    super.message, {
    required this.entity,
    required this.id,
  });

  final String entity;
  final String id;
}

/// A referenced row exists but has been deactivated (`is_active = false`).
/// Historic documents keep pointing at it; new ones may not (G-A4).
final class InactiveEntityFailure extends AppFailure {
  const InactiveEntityFailure(
    super.message, {
    required this.entity,
    required this.id,
  });

  final String entity;
  final String id;
}

// --- Stok Opname (Milestone 2) ----------------------------------------------

/// The Stok Opname document does not exist, or has been soft deleted.
final class StockOpnameNotFoundFailure extends AppFailure {
  const StockOpnameNotFoundFailure(super.message, {required this.opnameId});

  final String opnameId;
}

/// The line does not exist on this document.
final class StockOpnameLineNotFoundFailure extends AppFailure {
  const StockOpnameLineNotFoundFailure(super.message, {required this.lineId});

  final String lineId;
}

/// G-O1: this room already has an opname for this ISO week.
final class StockOpnameAlreadyExistsFailure extends AppFailure {
  const StockOpnameAlreadyExistsFailure(
    super.message, {
    required this.roomId,
    required this.periodYear,
    required this.periodWeek,
    this.existingOpnameId,
  });

  final String roomId;
  final int periodYear;
  final int periodWeek;

  /// Lets the UI jump straight to the document that is already there.
  final String? existingOpnameId;
}

/// G-S1/G-S2: the requested transition or edit is not allowed from the status
/// the document is actually in.
final class InvalidStockOpnameStateFailure extends AppFailure {
  const InvalidStockOpnameStateFailure(
    super.message, {
    required this.opnameId,
    required this.currentStatus,
    this.attemptedStatus,
  });

  final String opnameId;
  final StockOpnameStatus currentStatus;
  final StockOpnameStatus? attemptedStatus;
}

/// G-O3: a line whose difference is not zero was submitted without a reason.
final class DifferenceNoteRequiredFailure extends AppFailure {
  const DifferenceNoteRequiredFailure(super.message, {required this.lineIds});

  /// Every offending line, so the form can mark them all at once instead of
  /// making the nurse submit repeatedly.
  final List<String> lineIds;
}

/// G-R1: the room does not belong to the actor's branch.
final class UnauthorizedRoomFailure extends AppFailure {
  const UnauthorizedRoomFailure(
    super.message, {
    required this.actorUserId,
    required this.roomId,
  });

  final String actorUserId;
  final String roomId;
}

/// G-R2: the document belongs to a different branch than the actor.
final class UnauthorizedBranchFailure extends AppFailure {
  const UnauthorizedBranchFailure(
    super.message, {
    required this.actorUserId,
    required this.branchId,
  });

  final String actorUserId;
  final String branchId;
}

/// The actor does not hold the role this action requires.
final class InvalidReviewerFailure extends AppFailure {
  const InvalidReviewerFailure(
    super.message, {
    required this.actorUserId,
    required this.requiredRole,
  });

  final String actorUserId;
  final UserRole requiredRole;
}

/// G-R4: whoever counted the stock may not also approve it.
final class SelfReviewNotAllowedFailure extends AppFailure {
  const SelfReviewNotAllowedFailure(
    super.message, {
    required this.opnameId,
    required this.actorUserId,
  });

  final String opnameId;
  final String actorUserId;
}

/// A document with no lines cannot be submitted — there would be nothing to
/// review and nothing to post.
final class EmptyStockOpnameFailure extends AppFailure {
  const EmptyStockOpnameFailure(super.message, {required this.opnameId});

  final String opnameId;
}

/// The same item/batch position was added to the document twice.
final class DuplicateStockOpnameLineFailure extends AppFailure {
  const DuplicateStockOpnameLineFailure(
    super.message, {
    required this.opnameId,
    required this.itemId,
    this.batchId,
  });

  final String opnameId;
  final String itemId;
  final String? batchId;
}

/// A guarded write affected no rows: somebody else changed the document
/// between reading it and writing it. The caller must reload rather than
/// retry blindly.
final class ConcurrentStockOpnameUpdateFailure extends AppFailure {
  const ConcurrentStockOpnameUpdateFailure(
    super.message, {
    required this.opnameId,
  });

  final String opnameId;
}

// --- Stok Opname hardening (Milestone 2.1) ----------------------------------

/// A master row a **submitted** document depends on is physically gone.
///
/// This is not the same thing as deactivation or soft deletion: a deactivated
/// or soft-deleted row is still there and a historic document may still be
/// completed against it (§7.2). This failure means the row cannot be found at
/// all — the reference is broken, the review cannot be posted honestly, and
/// nothing may be invented to paper over it (§7.3).
final class HistoricalReferenceMissingFailure extends AppFailure {
  const HistoricalReferenceMissingFailure(
    super.message, {
    required this.entity,
    required this.id,
    required this.opnameId,
  });

  /// The table whose row is missing: `rooms`, `stock_locations`, `items`…
  final String entity;

  /// The id the document still points at.
  final String id;

  final String opnameId;
}

/// The document timestamps would end up out of order.
///
/// Raised when the instant a review is being performed at lies **before** the
/// instant the document was submitted — a device whose clock is set wrong.
/// Both instants are UTC [DateTime]s and are compared as instants, never as
/// text (§8.2/§8.3).
final class InvalidDocumentTimestampFailure extends AppFailure {
  const InvalidDocumentTimestampFailure(
    super.message, {
    required this.opnameId,
    required this.earlierLabel,
    required this.earlierUtc,
    required this.laterLabel,
    required this.laterUtc,
  });

  final String opnameId;

  /// Name of the timestamp that must not be later, e.g. `submitted_at`.
  final String earlierLabel;
  final DateTime earlierUtc;

  /// Name of the timestamp that must not be earlier, e.g. `reviewed_at`.
  final String laterLabel;
  final DateTime laterUtc;

  /// How far the clock is behind. Always positive when this failure is thrown.
  Duration get skew => earlierUtc.difference(laterUtc);
}
