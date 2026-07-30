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

// --- Delivery Order (Milestone 4) -------------------------------------------

/// The Delivery Order does not exist, or has been soft deleted.
final class DeliveryOrderNotFoundFailure extends AppFailure {
  const DeliveryOrderNotFoundFailure(super.message, {required this.doId});

  final String doId;
}

/// The line does not exist on this document.
final class DeliveryOrderLineNotFoundFailure extends AppFailure {
  const DeliveryOrderLineNotFoundFailure(super.message, {required this.lineId});

  final String lineId;
}

/// G-S1/G-S2: the requested transition or edit is not allowed from the status the
/// document is actually in.
final class InvalidDeliveryOrderStateFailure extends AppFailure {
  const InvalidDeliveryOrderStateFailure(
    super.message, {
    required this.doId,
    required this.currentStatus,
    this.attemptedStatus,
  });

  final String doId;
  final DeliveryOrderStatus currentStatus;
  final DeliveryOrderStatus? attemptedStatus;
}

/// The document has already been posted to the ledger.
///
/// Separate from [InvalidDeliveryOrderStateFailure] because the situation has its
/// own remedy: nothing is wrong with the shipment, it simply already happened, and
/// the officer needs the shipped document rather than a corrected draft.
final class DeliveryOrderAlreadyShippedFailure extends AppFailure {
  const DeliveryOrderAlreadyShippedFailure(
    super.message, {
    required this.doId,
    this.shippedAt,
  });

  final String doId;

  /// UTC instant (T-1).
  final DateTime? shippedAt;
}

/// G-D1: the Purchase Request is not one a shipment may be raised against —
/// still a draft, already shipped, closed, rejected or cancelled.
final class InvalidPurchaseRequestForDeliveryFailure extends AppFailure {
  const InvalidPurchaseRequestForDeliveryFailure(
    super.message, {
    required this.prId,
    required this.currentStatus,
  });

  final String prId;
  final PurchaseRequestStatus currentStatus;
}

/// A shipment with no allocations cannot be posted — there would be nothing to
/// move and nothing to print.
final class DeliveryOrderLineRequiredFailure extends AppFailure {
  const DeliveryOrderLineRequiredFailure(super.message, {required this.doId});

  final String doId;
}

/// G-D4: the item is not on the Purchase Request at all.
final class DeliveryItemNotInPurchaseRequestFailure extends AppFailure {
  const DeliveryItemNotInPurchaseRequestFailure(
    super.message, {
    required this.doId,
    required this.itemId,
  });

  final String doId;
  final String itemId;
}

/// G-D4: the allocation cites a Purchase Request line that belongs to another
/// request, or names an item the line does not ask for.
final class DeliveryPrLineMismatchFailure extends AppFailure {
  const DeliveryPrLineMismatchFailure(
    super.message, {
    required this.doId,
    required this.prLineId,
    this.itemId,
  });

  final String doId;
  final String prLineId;
  final String? itemId;
}

/// The same `(PR line, batch)` position was allocated twice on one document.
final class DuplicateDeliveryAllocationFailure extends AppFailure {
  const DuplicateDeliveryAllocationFailure(
    super.message, {
    required this.doId,
    required this.prLineId,
    this.batchId,
  });

  final String doId;
  final String prLineId;
  final String? batchId;
}

/// G-D2: the cumulative shipped quantity of a requested position would exceed
/// what the branch asked for.
final class DeliveryQuantityExceedsRequestedFailure extends AppFailure {
  const DeliveryQuantityExceedsRequestedFailure(
    super.message, {
    required this.prLineId,
    required this.requested,
    required this.alreadyShipped,
    required this.attempted,
  });

  final String prLineId;
  final Quantity requested;

  /// Cumulative quantity of every `shipped`/`received` Delivery Order, read
  /// inside the transaction that is about to post.
  final Quantity alreadyShipped;

  /// What this document adds on top.
  final Quantity attempted;

  Quantity get remaining => requested - alreadyShipped;
}

/// G-D3: the central warehouse does not hold enough of this item or batch.
///
/// Distinct from the generic [InsufficientStockFailure] so the Delivery Order UI
/// can point at the allocation that is short rather than at the document.
final class InsufficientWarehouseStockFailure extends AppFailure {
  const InsufficientWarehouseStockFailure(
    super.message, {
    required this.itemId,
    this.batchId,
    required this.available,
    required this.requested,
  });

  final String itemId;
  final String? batchId;
  final Quantity available;
  final Quantity requested;
}

/// There is no central-warehouse stock location at all, so a shipment has no
/// source to leave from (G-D3).
final class WarehouseLocationNotFoundFailure extends AppFailure {
  const WarehouseLocationNotFoundFailure(super.message);
}

/// There is more than one central-warehouse stock location.
///
/// Refused rather than resolved: which of two warehouses the goods left is a
/// business fact, and picking one would post the ledger against a location
/// nobody chose.
final class AmbiguousWarehouseLocationFailure extends AppFailure {
  const AmbiguousWarehouseLocationFailure(
    super.message, {
    required this.locationIds,
  });

  final List<String> locationIds;
}

/// G-E4: the batch is past its expiry date and is blocked from shipping
/// outright. No confirmation and no note can let it through.
final class ExpiredBatchForDeliveryFailure extends AppFailure {
  const ExpiredBatchForDeliveryFailure(
    super.message, {
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
  });

  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;
}

/// G-E4: the batch has less than `expiry_alert_days` of shelf life left and the
/// officer has not confirmed it explicitly.
final class NearExpiryConfirmationRequiredFailure extends AppFailure {
  const NearExpiryConfirmationRequiredFailure(
    super.message, {
    required this.batchId,
    required this.batchNo,
    required this.remainingDays,
    required this.expiryAlertDays,
  });

  final String batchId;
  final String batchNo;

  /// Whole operational days until the expiry date, GMT+8 (T-3/T-10).
  final int remainingDays;
  final int expiryAlertDays;
}

/// G-E3: a batch younger than the FEFO suggestion was picked without a reason.
final class FefoOverrideReasonRequiredFailure extends AppFailure {
  const FefoOverrideReasonRequiredFailure(
    super.message, {
    required this.batchId,
    required this.batchNo,
    required this.skippedBatchNo,
  });

  final String batchId;
  final String batchNo;

  /// The nearest-expiry batch that still has stock and was passed over — the one
  /// fact that makes the warning actionable.
  final String skippedBatchNo;
}

/// The batch does not belong to the item, or the item's expiry tracking and the
/// allocation disagree (G-E1/G-E2).
final class InvalidDeliveryBatchFailure extends AppFailure {
  const InvalidDeliveryBatchFailure(
    super.message, {
    required this.itemId,
    this.batchId,
  });

  final String itemId;
  final String? batchId;
}

/// A guarded write affected no rows: somebody else changed the document between
/// reading it and writing it. The caller must reload rather than retry blindly.
final class ConcurrentDeliveryOrderUpdateFailure extends AppFailure {
  const ConcurrentDeliveryOrderUpdateFailure(
    super.message, {
    required this.doId,
  });

  final String doId;
}

/// A master or Purchase Request row a Delivery Order depends on is physically
/// gone.
///
/// The same distinction [HistoricalReferenceMissingFailure] draws for Stok
/// Opname: a deactivated or soft-deleted row is still there and the shipment may
/// still be posted against it, but a row that cannot be found at all means the
/// reference is broken. Nothing may be invented, substituted or guessed to paper
/// over it.
final class HistoricalDeliveryReferenceMissingFailure extends AppFailure {
  const HistoricalDeliveryReferenceMissingFailure(
    super.message, {
    required this.entity,
    required this.id,
    required this.doId,
  });

  /// The table whose row is missing: `items`, `item_batches`,
  /// `purchase_request_lines`, `stock_locations`…
  final String entity;

  /// The id the document still points at.
  final String id;

  final String doId;
}

// --- Good Receipt (Milestone 5) ----------------------------------------------

/// The Good Receipt does not exist, or has been soft deleted.
final class GoodReceiptNotFoundFailure extends AppFailure {
  const GoodReceiptNotFoundFailure(super.message, {required this.grId});

  final String grId;
}

/// G-G1: the shipment already has a Good Receipt. One DO, one GR.
///
/// Also the failure a losing concurrent create sees: the unique index on
/// `good_receipts.do_id` is the final guard, and the repository translates it into
/// this rather than letting a driver error surface.
final class GoodReceiptAlreadyExistsFailure extends AppFailure {
  const GoodReceiptAlreadyExistsFailure(
    super.message, {
    required this.doId,
    this.grId,
  });

  final String doId;

  /// The receipt that already holds the shipment, when it is known. `null` when
  /// the unique index refused an insert and the winner's id was never read.
  final String? grId;
}

/// G-S1/G-S2: the requested transition or edit is not allowed from the status the
/// receipt is actually in.
final class InvalidGoodReceiptStateFailure extends AppFailure {
  const InvalidGoodReceiptStateFailure(
    super.message, {
    required this.grId,
    required this.currentStatus,
    this.attemptedStatus,
  });

  final String grId;
  final GoodReceiptStatus currentStatus;
  final GoodReceiptStatus? attemptedStatus;
}

/// The receipt has already been posted to the ledger.
///
/// Separate from [InvalidGoodReceiptStateFailure] because the situation has its
/// own remedy: nothing is wrong with the receipt, it simply already happened, and
/// the branch head needs the posted document rather than a corrected checklist.
final class GoodReceiptAlreadyPostedFailure extends AppFailure {
  const GoodReceiptAlreadyPostedFailure(
    super.message, {
    required this.grId,
    this.postedAt,
  });

  final String grId;

  /// UTC instant (T-1).
  final DateTime? postedAt;
}

/// G-G1: the Delivery Order is not one a Good Receipt may be raised against —
/// still `preparing`, or already `received`.
final class InvalidDeliveryOrderForReceiptFailure extends AppFailure {
  const InvalidDeliveryOrderForReceiptFailure(
    super.message, {
    required this.doId,
    required this.currentStatus,
  });

  final String doId;
  final DeliveryOrderStatus currentStatus;
}

/// A shipment with no allocations has nothing to check in.
final class GoodReceiptLineRequiredFailure extends AppFailure {
  const GoodReceiptLineRequiredFailure(super.message, {required this.doId});

  final String doId;
}

/// The line does not exist on this receipt.
final class GoodReceiptLineNotFoundFailure extends AppFailure {
  const GoodReceiptLineNotFoundFailure(super.message, {required this.lineId});

  final String lineId;
}

/// G-G2: the receipt cannot be posted while any position is still `pending`.
final class GoodReceiptLinesPendingFailure extends AppFailure {
  const GoodReceiptLinesPendingFailure(
    super.message, {
    required this.grId,
    required this.pendingLineIds,
  });

  final String grId;

  /// Every position still waiting for a decision, so the screen can point at the
  /// first one rather than at the document.
  final List<String> pendingLineIds;

  int get pendingCount => pendingLineIds.length;
}

/// G-G3: the received quantity is negative, or otherwise not a quantity a
/// position may accept.
final class InvalidReceivedQuantityFailure extends AppFailure {
  const InvalidReceivedQuantityFailure(
    super.message, {
    required this.lineId,
    required this.received,
  });

  final String lineId;
  final Quantity received;
}

/// G-G3: the received quantity is larger than what was shipped.
///
/// Distinct from [InvalidReceivedQuantityFailure] so the UI can say *how much* was
/// sent rather than only that the number is wrong.
final class ReceivedQuantityExceedsShippedFailure extends AppFailure {
  const ReceivedQuantityExceedsShippedFailure(
    super.message, {
    required this.lineId,
    required this.shipped,
    required this.received,
  });

  final String lineId;
  final Quantity shipped;
  final Quantity received;

  Quantity get excess => received - shipped;
}

/// G-G4: a refused position was stored without a reason, or with whitespace.
final class GoodReceiptRejectReasonRequiredFailure extends AppFailure {
  const GoodReceiptRejectReasonRequiredFailure(
    super.message, {
    required this.lineId,
  });

  final String lineId;
}

/// G-E5: the batch is past its expiry date, so the position must be **rejected**
/// rather than accepted.
///
/// Deliberately not a variant of the Delivery Order's expiry failure: on a
/// shipment an expired batch simply cannot be sent, while here the goods are
/// physically on the branch's counter and the only correct answer is to refuse
/// them with `kedaluwarsa` and put them on the return list.
final class GoodReceiptExpiredBatchMustBeRejectedFailure extends AppFailure {
  const GoodReceiptExpiredBatchMustBeRejectedFailure(
    super.message, {
    required this.lineId,
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
  });

  final String lineId;
  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;
}

/// G-E5: the batch has less than `expiry_alert_days` of shelf life left, so the
/// position must be **rejected**.
///
/// Unlike the shipment's near-expiry rule (G-E4), no confirmation can accept this:
/// spec §3.11 says goods too close to their expiry date are refused with
/// `kedaluwarsa` and go on the return list.
final class GoodReceiptNearExpiryBatchMustBeRejectedFailure extends AppFailure {
  const GoodReceiptNearExpiryBatchMustBeRejectedFailure(
    super.message, {
    required this.lineId,
    required this.batchId,
    required this.batchNo,
    required this.remainingDays,
    required this.expiryAlertDays,
  });

  final String lineId;
  final String batchId;
  final String batchNo;

  /// Whole operational days until the expiry date, GMT+8 (T-3/T-10).
  final int remainingDays;
  final int expiryAlertDays;
}

/// The batch does not belong to the item, or the item's expiry tracking and the
/// receipt line disagree (G-E1/G-E2).
final class InvalidGoodReceiptBatchFailure extends AppFailure {
  const InvalidGoodReceiptBatchFailure(
    super.message, {
    required this.itemId,
    this.batchId,
  });

  final String itemId;
  final String? batchId;
}

/// G-G1: the acting Kepala Cabang does not belong to the shipment's destination
/// branch.
final class GoodReceiptBranchMismatchFailure extends AppFailure {
  const GoodReceiptBranchMismatchFailure(
    super.message, {
    required this.actorUserId,
    this.actorBranchId,
    required this.documentBranchId,
  });

  final String actorUserId;
  final String? actorBranchId;
  final String documentBranchId;
}

/// There is no *Gudang Cabang* stock location for the branch, so a receipt has no
/// destination to credit (G-G5).
final class GoodReceiptBranchStoreNotFoundFailure extends AppFailure {
  const GoodReceiptBranchStoreNotFoundFailure(
    super.message, {
    required this.branchId,
  });

  final String branchId;
}

/// There is more than one *Gudang Cabang* location for the branch.
///
/// Refused rather than resolved: which store the goods entered is a business fact,
/// and picking one would post the ledger against a location nobody chose.
final class GoodReceiptBranchStoreAmbiguousFailure extends AppFailure {
  const GoodReceiptBranchStoreAmbiguousFailure(
    super.message, {
    required this.branchId,
    required this.locationIds,
  });

  final String branchId;
  final List<String> locationIds;
}

/// The receipt and the shipment it snapshots no longer agree: a line is missing,
/// or one is present that no allocation accounts for.
final class GoodReceiptLineIntegrityFailure extends AppFailure {
  const GoodReceiptLineIntegrityFailure(
    super.message, {
    required this.grId,
    this.missingDoLineIds = const <String>[],
    this.extraDoLineIds = const <String>[],
  });

  final String grId;

  /// Allocations the shipment has and the receipt does not — checking in less
  /// than was sent, silently.
  final List<String> missingDoLineIds;

  /// Receipt lines that answer no live allocation — checking in something the
  /// shipment never carried.
  final List<String> extraDoLineIds;
}

/// A master, Delivery Order or Purchase Request row a Good Receipt depends on is
/// physically gone.
///
/// The same distinction [HistoricalReferenceMissingFailure] draws for Stok Opname:
/// a deactivated or soft-deleted row is still there and the receipt may still be
/// posted against it, but a row that cannot be found at all means the reference is
/// broken. Nothing may be invented, substituted or guessed to paper over it.
final class GoodReceiptHistoricalReferenceMissingFailure extends AppFailure {
  const GoodReceiptHistoricalReferenceMissingFailure(
    super.message, {
    required this.entity,
    required this.id,
    required this.grId,
  });

  /// The table whose row is missing: `items`, `item_batches`,
  /// `delivery_order_lines`, `stock_locations`…
  final String entity;

  /// The id the document still points at.
  final String id;

  final String grId;
}

/// A guarded write affected no rows: somebody else changed the receipt between
/// reading it and writing it. The caller must reload rather than retry blindly.
final class ConcurrentGoodReceiptUpdateFailure extends AppFailure {
  const ConcurrentGoodReceiptUpdateFailure(super.message, {required this.grId});

  final String grId;
}
