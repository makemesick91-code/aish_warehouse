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
/// Raised when the instant a transition is being performed at lies **before**
/// the instant of the transition it must follow — a review before its submit, a
/// rejection before the warehouse started processing — which in practice means a
/// device whose clock is set wrong. Both instants are UTC [DateTime]s and are
/// compared as instants, never as text (§8.2/§8.3).
///
/// [documentId] is deliberately not named after one document type: the same rule
/// and the same failure serve Stok Opname and Purchase Request, and every
/// workflow after them.
final class InvalidDocumentTimestampFailure extends AppFailure {
  const InvalidDocumentTimestampFailure(
    super.message, {
    required this.documentId,
    required this.earlierLabel,
    required this.earlierUtc,
    required this.laterLabel,
    required this.laterUtc,
  });

  final String documentId;

  /// Name of the timestamp that must not be later, e.g. `submitted_at`.
  final String earlierLabel;
  final DateTime earlierUtc;

  /// Name of the timestamp that must not be earlier, e.g. `reviewed_at`.
  final String laterLabel;
  final DateTime laterUtc;

  /// How far the clock is behind. Always positive when this failure is thrown.
  Duration get skew => earlierUtc.difference(laterUtc);
}

// --- Purchase Request (Milestone 3) -----------------------------------------

/// The Purchase Request does not exist, or has been soft deleted.
final class PurchaseRequestNotFoundFailure extends AppFailure {
  const PurchaseRequestNotFoundFailure(super.message, {required this.prId});

  final String prId;
}

/// The line does not exist on this document.
final class PurchaseRequestLineNotFoundFailure extends AppFailure {
  const PurchaseRequestLineNotFoundFailure(
    super.message, {
    required this.lineId,
  });

  final String lineId;
}

/// G-P4: the branch already has a `submitted`/`processing` request.
///
/// Raised by the use case when it finds one, and again by the repository when the
/// partial unique index rejects a concurrent submit — the two paths produce the
/// same failure because they are the same rule, checked at different moments.
final class PurchaseRequestAlreadyActiveFailure extends AppFailure {
  const PurchaseRequestAlreadyActiveFailure(
    super.message, {
    required this.branchId,
    this.activePrId,
  });

  final String branchId;

  /// Lets the UI jump straight to the request that is already in flight.
  final String? activePrId;
}

/// G-P5/G-S1: the requested transition or edit is not allowed from the status the
/// document is actually in.
final class InvalidPurchaseRequestStateFailure extends AppFailure {
  const InvalidPurchaseRequestStateFailure(
    super.message, {
    required this.prId,
    required this.currentStatus,
    this.attemptedStatus,
  });

  final String prId;
  final PurchaseRequestStatus currentStatus;
  final PurchaseRequestStatus? attemptedStatus;
}

/// G-P1: no stock opname was cited at all.
final class PurchaseRequestOpnameRequiredFailure extends AppFailure {
  const PurchaseRequestOpnameRequiredFailure(
    super.message, {
    required this.prId,
  });

  /// Empty while the document is still being created and has no id yet.
  final String prId;
}

/// G-P1: the cited opname is not one this request may rest on — wrong branch,
/// still a draft, or older than the previous operational week.
final class IneligibleStockOpnameFailure extends AppFailure {
  const IneligibleStockOpnameFailure(
    super.message, {
    required this.opnameId,
    required this.reason,
  });

  final String opnameId;
  final StockOpnameEligibilityDenial reason;
}

/// Why an opname may not back a Purchase Request. Separate values so tests and
/// logs can name the rule that fired; the UI shows one sentence per case.
enum StockOpnameEligibilityDenial {
  /// No opname with this id, or it has been soft deleted.
  missing,

  /// The count belongs to another branch (G-R2).
  otherBranch,

  /// Still a `draft` — it has not left the nurse's hands (G-O4).
  notSubmitted,

  /// Older than the previous operational week (G-P1).
  periodTooOld,

  /// Filed under a week that has not started yet — a device clock problem.
  periodInFuture,
}

/// G-P1 at submit time: a reference that was eligible when the draft was created
/// has since fallen out of the two-week window.
///
/// A separate failure from [IneligibleStockOpnameFailure] because the situation
/// is different and so is the way out: nothing is wrong with the choice the
/// branch head made, the draft simply sat too long, and the fix is to re-pick
/// this week's counts rather than to correct a mistake.
final class ExpiredStockOpnameReferenceFailure extends AppFailure {
  const ExpiredStockOpnameReferenceFailure(
    super.message, {
    required this.prId,
    required this.opnameIds,
  });

  final String prId;

  /// Every reference that has aged out, so the form can mark them together.
  final List<String> opnameIds;
}

/// G-P2: the same item appears on the request more than once.
final class DuplicatePurchaseRequestItemFailure extends AppFailure {
  const DuplicatePurchaseRequestItemFailure(
    super.message, {
    required this.prId,
    required this.itemId,
  });

  final String prId;
  final String itemId;
}

/// G-P2: `requested_qty` must be strictly positive.
final class InvalidRequestedQuantityFailure extends AppFailure {
  const InvalidRequestedQuantityFailure(
    super.message, {
    required this.itemId,
    required this.requested,
  });

  final String itemId;
  final Quantity requested;
}

/// G-P3: the request exceeds 150 % of the suggestion — or has no suggestion at
/// all — and carries no reason.
final class PurchaseRequestJustificationRequiredFailure extends AppFailure {
  const PurchaseRequestJustificationRequiredFailure(
    super.message, {
    required this.lineIds,
  });

  /// Every offending line, so the form can mark them all at once instead of
  /// making the branch head submit repeatedly.
  final List<String> lineIds;
}

/// G-R2: the request belongs to a different branch than the actor.
final class UnauthorizedPurchaseRequestBranchFailure extends AppFailure {
  const UnauthorizedPurchaseRequestBranchFailure(
    super.message, {
    required this.actorUserId,
    required this.branchId,
  });

  final String actorUserId;
  final String branchId;
}

/// G-R3: the warehouse may fulfil or refuse a request, never change what it
/// asks for.
final class WarehouseCannotEditPurchaseRequestFailure extends AppFailure {
  const WarehouseCannotEditPurchaseRequestFailure(
    super.message, {
    required this.actorUserId,
    required this.prId,
  });

  final String actorUserId;
  final String prId;
}

/// A rejection was attempted without a reason (spec §3.2).
final class PurchaseRequestRejectReasonRequiredFailure extends AppFailure {
  const PurchaseRequestRejectReasonRequiredFailure(
    super.message, {
    required this.prId,
  });

  final String prId;
}

/// A cancellation was attempted without a reason (§24.4 — the detail screen has
/// to be able to say why).
final class PurchaseRequestCancelReasonRequiredFailure extends AppFailure {
  const PurchaseRequestCancelReasonRequiredFailure(
    super.message, {
    required this.prId,
  });

  final String prId;
}

/// A guarded write affected no rows: somebody else changed the document between
/// reading it and writing it. The caller must reload rather than retry blindly.
final class ConcurrentPurchaseRequestUpdateFailure extends AppFailure {
  const ConcurrentPurchaseRequestUpdateFailure(
    super.message, {
    required this.prId,
  });

  final String prId;
}

/// A master or opname row a **submitted** Purchase Request depends on is
/// physically gone.
///
/// The same distinction [HistoricalReferenceMissingFailure] draws for Stok
/// Opname: a deactivated or soft-deleted row is still there and the document may
/// still be processed against it, but a row that cannot be found at all means the
/// reference is broken. Nothing may be invented to paper over it.
final class HistoricalPurchaseRequestReferenceMissingFailure
    extends AppFailure {
  const HistoricalPurchaseRequestReferenceMissingFailure(
    super.message, {
    required this.entity,
    required this.id,
    required this.prId,
  });

  /// The table whose row is missing: `items`, `stock_opnames`, `users`…
  final String entity;

  /// The id the document still points at.
  final String id;

  final String prId;
}
