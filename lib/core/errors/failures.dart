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

// --- Distribusi (Milestone 6) -----------------------------------------------

/// The distribution document does not exist, or has been soft deleted.
final class DistributionNotFoundFailure extends AppFailure {
  const DistributionNotFoundFailure(
    super.message, {
    required this.distributionId,
  });

  final String distributionId;
}

/// The requested transition is not one the state machine lists (G-S1).
final class InvalidDistributionStateFailure extends AppFailure {
  const InvalidDistributionStateFailure(
    super.message, {
    required this.distributionId,
    required this.currentStatus,
    this.attemptedStatus,
  });

  final String distributionId;
  final DistributionStatus currentStatus;

  /// `null` when the caller only asserted a status rather than a transition.
  final DistributionStatus? attemptedStatus;
}

/// The document is already `posted`, and `posted` is final (G-S2).
///
/// Separate from [InvalidDistributionStateFailure] so the message can say *when* it
/// was posted — the fact that makes "you cannot change this" understandable rather
/// than merely true.
final class DistributionAlreadyPostedFailure extends AppFailure {
  const DistributionAlreadyPostedFailure(
    super.message, {
    required this.distributionId,
    this.postedAt,
  });

  final String distributionId;

  /// UTC instant (T-1).
  final DateTime? postedAt;
}

/// A distribution with no lines cannot be posted: there is nothing to move.
final class DistributionLineRequiredFailure extends AppFailure {
  const DistributionLineRequiredFailure(
    super.message, {
    required this.distributionId,
  });

  final String distributionId;
}

/// The line is not on this distribution, or does not exist. Both answer the same
/// way, so the id cannot be probed.
final class DistributionLineNotFoundFailure extends AppFailure {
  const DistributionLineNotFoundFailure(super.message, {required this.lineId});

  final String lineId;
}

/// The acting branch head's branch is not the document's (G-T1/G-R2).
final class DistributionBranchMismatchFailure extends AppFailure {
  const DistributionBranchMismatchFailure(
    super.message, {
    required this.actorUserId,
    this.actorBranchId,
    required this.documentBranchId,
  });

  final String actorUserId;
  final String? actorBranchId;
  final String documentBranchId;
}

/// The room is in another branch — G-T1's core refusal.
///
/// SQLite cannot express `rooms.branch_id = distributions.branch_id`, so this is
/// where the rule is actually enforced. The message deliberately does not confirm
/// which branch the room *is* in.
final class DistributionRoomBranchMismatchFailure extends AppFailure {
  const DistributionRoomBranchMismatchFailure(
    super.message, {
    required this.roomId,
    required this.documentBranchId,
  });

  final String roomId;
  final String documentBranchId;
}

/// The room exists in this branch but is deactivated or archived.
///
/// Refused for a new line, and refused again at posting: a room that is not
/// operational is not a place stock may be moved to, whatever the draft says
/// (§32).
final class DistributionRoomInactiveFailure extends AppFailure {
  const DistributionRoomInactiveFailure(super.message, {required this.roomId});

  final String roomId;
}

/// No `room` stock location resolves for the destination room (§14).
final class DistributionRoomLocationNotFoundFailure extends AppFailure {
  const DistributionRoomLocationNotFoundFailure(
    super.message, {
    required this.roomId,
  });

  final String roomId;
}

/// More than one `room` stock location resolves for the destination room.
///
/// Refused rather than resolved: which location the goods entered is a business
/// fact, and picking one would credit a balance nobody chose.
final class DistributionRoomLocationAmbiguousFailure extends AppFailure {
  const DistributionRoomLocationAmbiguousFailure(
    super.message, {
    required this.roomId,
    required this.locationIds,
  });

  final String roomId;
  final List<String> locationIds;
}

/// The branch has no *Gudang Cabang* location, so there is no source to draw from
/// (G-T1).
final class DistributionBranchStoreNotFoundFailure extends AppFailure {
  const DistributionBranchStoreNotFoundFailure(
    super.message, {
    required this.branchId,
  });

  final String branchId;
}

/// There is more than one *Gudang Cabang* location for the branch.
final class DistributionBranchStoreAmbiguousFailure extends AppFailure {
  const DistributionBranchStoreAmbiguousFailure(
    super.message, {
    required this.branchId,
    required this.locationIds,
  });

  final String branchId;
  final List<String> locationIds;
}

/// A distributed quantity is zero, negative, or otherwise not a legal quantity.
final class InvalidDistributionQuantityFailure extends AppFailure {
  const InvalidDistributionQuantityFailure(
    super.message, {
    this.lineId,
    required this.qty,
  });

  /// `null` while the line does not exist yet — an add that was asked for zero.
  final String? lineId;
  final Quantity qty;
}

/// The branch store does not hold enough of one position for the whole document
/// (G-T2).
///
/// The quantities are the **aggregate** across every room, which is the number the
/// rule is about: two rooms each taking `3` from a batch holding `5` fails here
/// even though neither line exceeds the balance on its own.
final class InsufficientBranchStockFailure extends AppFailure {
  const InsufficientBranchStockFailure(
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

  /// What the store holds for this exact position.
  final Quantity available;

  /// What the whole document asks of it, summed over every room.
  final Quantity requested;
}

/// The item has no distributable stock in the branch store at all (§15).
///
/// Distinct from [InsufficientBranchStockFailure] because the answer is different:
/// there is nothing to reduce a quantity *to*, and the item should not have been
/// offered by the picker in the first place.
final class DistributionItemHasNoStockFailure extends AppFailure {
  const DistributionItemHasNoStockFailure(
    super.message, {
    required this.itemId,
    required this.locationId,
  });

  final String itemId;
  final String locationId;
}

/// Batch and item disagree: an expiry-tracked item without a batch, an item without
/// expiry carrying one, or a batch that belongs to a different item (G-E2).
final class InvalidDistributionBatchFailure extends AppFailure {
  const InvalidDistributionBatchFailure(
    super.message, {
    required this.itemId,
    this.batchId,
  });

  final String itemId;
  final String? batchId;
}

/// The batch has expired and is blocked from distribution outright (G-E4).
///
/// No note, no confirmation and no override reason can pass this. The stock stays
/// on the shelf and leaves through disposal instead (G-E7).
final class ExpiredBatchForDistributionFailure extends AppFailure {
  const ExpiredBatchForDistributionFailure(
    super.message, {
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    this.lineId,
  });

  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;

  final String? lineId;
}

/// A batch younger than the FEFO suggestion was chosen without a written reason
/// (G-E3).
///
/// The skipped batch is carried so the message can name what should have been taken
/// — the one fact that makes the warning actionable.
final class DistributionFefoOverrideReasonRequiredFailure extends AppFailure {
  const DistributionFefoOverrideReasonRequiredFailure(
    super.message, {
    required this.itemId,
    required this.selectedBatchId,
    required this.selectedBatchNo,
    required this.skippedBatchId,
    required this.skippedBatchNo,
    required this.skippedExpiryDate,
    this.lineId,
  });

  final String itemId;
  final String selectedBatchId;
  final String selectedBatchNo;
  final String skippedBatchId;
  final String skippedBatchNo;

  /// Civil date of the batch that was passed over (T-8).
  final DateTime skippedExpiryDate;

  final String? lineId;
}

/// The same `(room, item, batch)` position already exists on this document.
///
/// The domain half of the two partial unique indexes: the database refuses it too,
/// but as a driver error, and a branch head needs a sentence.
final class DuplicateDistributionLineFailure extends AppFailure {
  const DuplicateDistributionLineFailure(
    super.message, {
    required this.distributionId,
    required this.roomId,
    required this.itemId,
    this.batchId,
  });

  final String distributionId;
  final String roomId;
  final String itemId;
  final String? batchId;
}

/// The document's own lines and what the joined read produced no longer agree: a
/// line is missing from one side, or one is present that the other cannot account
/// for (§22).
final class DistributionLineIntegrityFailure extends AppFailure {
  const DistributionLineIntegrityFailure(
    super.message, {
    required this.distributionId,
    this.missingLineIds = const <String>[],
    this.extraLineIds = const <String>[],
  });

  final String distributionId;

  /// Lines the plain select found and the joined read dropped — posting on that
  /// basis would move less stock than the document says.
  final List<String> missingLineIds;

  /// Lines the joined read produced that no live row accounts for.
  final List<String> extraLineIds;
}

/// A master row a distribution depends on is physically gone.
///
/// The same distinction [HistoricalReferenceMissingFailure] draws for Stok Opname: a
/// deactivated or soft-deleted row is still there and a posted document may still be
/// read against it, but a row that cannot be found at all means the reference is
/// broken. Nothing may be invented, substituted or guessed to paper over it (§32).
final class HistoricalDistributionReferenceMissingFailure extends AppFailure {
  const HistoricalDistributionReferenceMissingFailure(
    super.message, {
    required this.entity,
    required this.id,
    required this.distributionId,
  });

  /// The table whose row is missing: `rooms`, `items`, `item_batches`,
  /// `stock_locations`…
  final String entity;

  /// The id the document still points at.
  final String id;

  final String distributionId;
}

/// A guarded write affected no rows: somebody else changed the distribution between
/// reading it and writing it. The caller must reload rather than retry blindly.
final class ConcurrentDistributionUpdateFailure extends AppFailure {
  const ConcurrentDistributionUpdateFailure(
    super.message, {
    required this.distributionId,
  });

  final String distributionId;
}

/// `posted_at` would land before `created_at` — a device clock behind the document
/// it is stamping (§34).
final class InvalidDistributionTimestampFailure extends AppFailure {
  const InvalidDistributionTimestampFailure(
    super.message, {
    required this.distributionId,
    required this.createdAtUtc,
    required this.postedAtUtc,
  });

  final String distributionId;
  final DateTime createdAtUtc;
  final DateTime postedAtUtc;
}

// --- Pemusnahan / Disposal (Milestone 7) ------------------------------------

/// The disposal document does not exist, or has been soft deleted.
final class DisposalNotFoundFailure extends AppFailure {
  const DisposalNotFoundFailure(super.message, {required this.disposalId});

  final String disposalId;
}

/// The requested transition is not one the state machine lists (G-S1).
final class InvalidDisposalStateFailure extends AppFailure {
  const InvalidDisposalStateFailure(
    super.message, {
    required this.disposalId,
    required this.currentStatus,
    this.attemptedStatus,
  });

  final String disposalId;
  final DisposalStatus currentStatus;

  /// `null` when the caller only asserted a status rather than a transition.
  final DisposalStatus? attemptedStatus;
}

/// The document is already `posted`, and `posted` is final (G-S2).
///
/// Separate from [InvalidDisposalStateFailure] so the message can say *when* it was
/// posted — the fact that makes "you cannot change this" understandable rather than
/// merely true.
final class DisposalAlreadyPostedFailure extends AppFailure {
  const DisposalAlreadyPostedFailure(
    super.message, {
    required this.disposalId,
    this.postedAt,
  });

  final String disposalId;

  /// UTC instant (T-1).
  final DateTime? postedAt;
}

/// A disposal with no lines cannot be posted: there is nothing to destroy.
final class DisposalLineRequiredFailure extends AppFailure {
  const DisposalLineRequiredFailure(super.message, {required this.disposalId});

  final String disposalId;
}

/// The line is not on this disposal, or does not exist. Both answer the same way,
/// so the id cannot be probed.
final class DisposalLineNotFoundFailure extends AppFailure {
  const DisposalLineNotFoundFailure(super.message, {required this.lineId});

  final String lineId;
}

/// G-E7's mandatory note is missing or blank.
///
/// Raised by the domain rather than by the database CHECK, and the difference
/// matters: `String.trim()` in Dart strips tabs and newlines, SQLite's `trim()`
/// strips spaces only, so a reason of `"\n\n"` satisfies the CHECK and is refused
/// here (§19).
final class DisposalReasonRequiredFailure extends AppFailure {
  const DisposalReasonRequiredFailure(
    super.message, {
    required this.disposalId,
  });

  final String disposalId;
}

/// The nominated source location does not exist.
final class DisposalSourceLocationNotFoundFailure extends AppFailure {
  const DisposalSourceLocationNotFoundFailure(
    super.message, {
    required this.locationId,
  });

  final String locationId;
}

/// The source location exists but has been archived, and the document is a *new*
/// one (§15).
///
/// An existing draft against an archived source may still be posted: a disposal
/// takes goods *out of* a shelf that still physically holds them, which lowers risk
/// rather than moving stock somewhere nobody is working.
final class DisposalSourceLocationInactiveFailure extends AppFailure {
  const DisposalSourceLocationInactiveFailure(
    super.message, {
    required this.locationId,
  });

  final String locationId;
}

/// The acting user's role and the source location do not go together (§15).
///
/// A warehouse account naming a branch store or a room, a branch head naming
/// Warehouse Pusat, or a role with no disposal scope at all. The message
/// deliberately does not confirm which of those it was.
final class DisposalSourceLocationAccessDeniedFailure extends AppFailure {
  const DisposalSourceLocationAccessDeniedFailure(
    super.message, {
    required this.actorUserId,
    required this.locationId,
  });

  final String actorUserId;
  final String locationId;
}

/// The source location belongs to another branch — the core scope refusal.
///
/// SQLite cannot express `stock_locations.branch_id = users.branch_id`, so this is
/// where the rule is actually enforced. The message deliberately does not confirm
/// which branch the location *is* in.
final class DisposalBranchMismatchFailure extends AppFailure {
  const DisposalBranchMismatchFailure(
    super.message, {
    required this.actorUserId,
    this.actorBranchId,
    required this.locationId,
  });

  final String actorUserId;
  final String? actorBranchId;
  final String locationId;
}

/// A `room` source whose room row does not belong to the actor's branch, or whose
/// location row carries no room at all.
///
/// Distinct from [DisposalBranchMismatchFailure] because the broken relationship is
/// a different one: the location's branch may be right while the room it names is
/// not, which is a corrupt row rather than a permission question.
final class DisposalRoomMismatchFailure extends AppFailure {
  const DisposalRoomMismatchFailure(
    super.message, {
    required this.locationId,
    this.roomId,
  });

  final String locationId;
  final String? roomId;
}

/// The item is not tracked per batch, so nothing about it can be expired (§9).
///
/// Disposal of goods that are damaged, recalled or rejected on arrival is a
/// different workflow with different eligibility rules, and this milestone does not
/// open it.
final class DisposalItemMustHaveExpiryFailure extends AppFailure {
  const DisposalItemMustHaveExpiryFailure(
    super.message, {
    required this.itemId,
  });

  final String itemId;
}

/// A disposal position was submitted without a batch.
final class DisposalBatchRequiredFailure extends AppFailure {
  const DisposalBatchRequiredFailure(super.message, {required this.itemId});

  final String itemId;
}

/// The batch does not belong to the item, or the two disagree in some other way.
final class InvalidDisposalBatchFailure extends AppFailure {
  const InvalidDisposalBatchFailure(
    super.message, {
    required this.itemId,
    required this.batchId,
  });

  final String itemId;
  final String batchId;
}

/// The batch has **not** expired, and only expired stock may be destroyed (G-E7).
///
/// No note, no confirmation and no preset reason can pass this. A batch is usable
/// for the whole of its expiry day and becomes disposable from the next operational
/// day onwards (T-10).
final class BatchNotExpiredForDisposalFailure extends AppFailure {
  const BatchNotExpiredForDisposalFailure(
    super.message, {
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    this.lineId,
  });

  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;

  final String? lineId;
}

/// A destroyed quantity is zero, negative, or otherwise not a legal quantity.
final class InvalidDisposalQuantityFailure extends AppFailure {
  const InvalidDisposalQuantityFailure(
    super.message, {
    this.lineId,
    required this.qty,
  });

  /// `null` while the line does not exist yet — an add that was asked for zero.
  final String? lineId;
  final Quantity qty;
}

/// The source location does not hold enough of one position (§18).
final class InsufficientDisposalStockFailure extends AppFailure {
  const InsufficientDisposalStockFailure(
    super.message, {
    required this.itemId,
    required this.locationId,
    required this.batchId,
    required this.available,
    required this.requested,
  });

  final String itemId;
  final String locationId;
  final String batchId;

  /// What the shelf holds for this exact position.
  final Quantity available;

  /// What the document asks of it.
  final Quantity requested;
}

/// The same `(item, batch)` position already exists on this document.
///
/// The domain half of the partial unique index: the database refuses it too, but as
/// a driver error, and a user needs a sentence.
final class DuplicateDisposalLineFailure extends AppFailure {
  const DuplicateDisposalLineFailure(
    super.message, {
    required this.disposalId,
    required this.itemId,
    required this.batchId,
  });

  final String disposalId;
  final String itemId;
  final String batchId;
}

/// The document's own lines and what the joined read produced no longer agree: a
/// line is missing from one side, or one is present that the other cannot account
/// for (§23).
final class DisposalLineIntegrityFailure extends AppFailure {
  const DisposalLineIntegrityFailure(
    super.message, {
    required this.disposalId,
    this.missingLineIds = const <String>[],
    this.extraLineIds = const <String>[],
  });

  final String disposalId;

  /// Lines the plain select found and the joined read dropped — posting on that
  /// basis would destroy less stock than the document says.
  final List<String> missingLineIds;

  /// Lines the joined read produced that no live row accounts for.
  final List<String> extraLineIds;
}

/// A master row a disposal depends on is physically gone.
///
/// The same distinction [HistoricalReferenceMissingFailure] draws for Stok Opname: a
/// deactivated or soft-deleted row is still there and a document may still be posted
/// against it, but a row that cannot be found at all means the reference is broken.
/// Nothing may be invented, substituted or guessed to paper over it (§34).
final class HistoricalDisposalReferenceMissingFailure extends AppFailure {
  const HistoricalDisposalReferenceMissingFailure(
    super.message, {
    required this.entity,
    required this.id,
    required this.disposalId,
  });

  /// The table whose row is missing: `items`, `item_batches`, `stock_locations`…
  final String entity;

  /// The id the document still points at.
  final String id;

  final String disposalId;
}

/// A guarded write affected no rows: somebody else changed the disposal between
/// reading it and writing it. The caller must reload rather than retry blindly.
final class ConcurrentDisposalUpdateFailure extends AppFailure {
  const ConcurrentDisposalUpdateFailure(
    super.message, {
    required this.disposalId,
  });

  final String disposalId;
}

/// `posted_at` would land before `created_at` — a device clock behind the document
/// it is stamping (§36).
final class InvalidDisposalTimestampFailure extends AppFailure {
  const InvalidDisposalTimestampFailure(
    super.message, {
    required this.disposalId,
    required this.createdAtUtc,
    required this.postedAtUtc,
  });

  final String disposalId;
  final DateTime createdAtUtc;
  final DateTime postedAtUtc;
}

// --- Pemakaian / Consumption (Milestone 8) ----------------------------------

/// The consumption document does not exist, or has been soft deleted.
final class ConsumptionNotFoundFailure extends AppFailure {
  const ConsumptionNotFoundFailure(
    super.message, {
    required this.consumptionId,
  });

  final String consumptionId;
}

/// The requested transition is not one the state machine lists (G-S1).
final class InvalidConsumptionStateFailure extends AppFailure {
  const InvalidConsumptionStateFailure(
    super.message, {
    required this.consumptionId,
    required this.currentStatus,
    this.attemptedStatus,
  });

  final String consumptionId;
  final ConsumptionStatus currentStatus;

  /// `null` when the caller only asserted a status rather than a transition.
  final ConsumptionStatus? attemptedStatus;
}

/// The document is already `posted`, and `posted` is final (G-S2).
///
/// Separate from [InvalidConsumptionStateFailure] so the message can say *when* it
/// was posted — the fact that makes "you cannot change this" understandable rather
/// than merely true.
final class ConsumptionAlreadyPostedFailure extends AppFailure {
  const ConsumptionAlreadyPostedFailure(
    super.message, {
    required this.consumptionId,
    this.postedAt,
  });

  final String consumptionId;

  /// UTC instant (T-1).
  final DateTime? postedAt;
}

/// A consumption with no lines cannot be posted: nothing was used.
final class ConsumptionLineRequiredFailure extends AppFailure {
  const ConsumptionLineRequiredFailure(
    super.message, {
    required this.consumptionId,
  });

  final String consumptionId;
}

/// The line is not on this consumption, or does not exist. Both answer the same way,
/// so the id cannot be probed.
final class ConsumptionLineNotFoundFailure extends AppFailure {
  const ConsumptionLineNotFoundFailure(super.message, {required this.lineId});

  final String lineId;
}

/// The acting nurse is not the one who created this draft (§14).
///
/// The core ownership refusal of this milestone, and the one that has no analogue on
/// any earlier document: a Purchase Request belongs to a *branch*, but a Pemakaian
/// draft belongs to the person who recorded it, because the quantities on it are
/// their memory of a shift nobody else witnessed. The message deliberately does not
/// say whose draft it is.
final class ConsumptionNotOwnedFailure extends AppFailure {
  const ConsumptionNotOwnedFailure(
    super.message, {
    required this.consumptionId,
    required this.actorUserId,
  });

  final String consumptionId;
  final String actorUserId;
}

/// The document belongs to another branch — the core scope refusal (G-R2).
final class ConsumptionBranchMismatchFailure extends AppFailure {
  const ConsumptionBranchMismatchFailure(
    super.message, {
    required this.actorUserId,
    this.actorBranchId,
    required this.documentBranchId,
  });

  final String actorUserId;
  final String? actorBranchId;
  final String documentBranchId;
}

/// `rooms.branch_id` is not the document's branch (§15).
///
/// Distinct from [ConsumptionBranchMismatchFailure] because the broken relationship
/// is a different one: the document's branch may be the actor's while the room it
/// names belongs to somebody else. SQLite cannot express
/// `rooms.branch_id = consumptions.branch_id`, so this is where the rule is actually
/// enforced.
final class ConsumptionRoomBranchMismatchFailure extends AppFailure {
  const ConsumptionRoomBranchMismatchFailure(
    super.message, {
    required this.roomId,
    required this.documentBranchId,
  });

  final String roomId;
  final String documentBranchId;
}

/// The room exists but is deactivated or archived (§15).
///
/// Refused for a new document *and* at posting: goods must not be recorded as used
/// out of a room the clinic is no longer operating. A **posted** document whose room
/// was retired afterwards stays fully readable (§33).
final class ConsumptionRoomInactiveFailure extends AppFailure {
  const ConsumptionRoomInactiveFailure(super.message, {required this.roomId});

  final String roomId;
}

/// No `room` stock location resolves for the document's room (§15).
final class ConsumptionRoomLocationNotFoundFailure extends AppFailure {
  const ConsumptionRoomLocationNotFoundFailure(
    super.message, {
    required this.roomId,
  });

  final String roomId;
}

/// More than one `room` stock location resolves for the document's room.
///
/// Kept apart from [ConsumptionRoomLocationNotFoundFailure] rather than resolved:
/// which location the goods left is a business fact, and picking the first would
/// silently reduce a balance nobody chose.
final class ConsumptionRoomLocationAmbiguousFailure extends AppFailure {
  const ConsumptionRoomLocationAmbiguousFailure(
    super.message, {
    required this.roomId,
    required this.locationIds,
  });

  final String roomId;
  final List<String> locationIds;
}

/// The room holds nothing of this item at all (§16).
///
/// Distinct from [InsufficientRoomStockFailure] because the answer is different:
/// there is nothing to reduce a quantity *to*, and the picker should not have offered
/// it.
final class ConsumptionItemHasNoStockFailure extends AppFailure {
  const ConsumptionItemHasNoStockFailure(
    super.message, {
    required this.itemId,
    required this.locationId,
  });

  final String itemId;
  final String locationId;
}

/// The item is batch-tracked but no batch was supplied (G-E2).
final class ConsumptionBatchRequiredFailure extends AppFailure {
  const ConsumptionBatchRequiredFailure(super.message, {required this.itemId});

  final String itemId;
}

/// The item is not batch-tracked but a batch was supplied (G-E2).
final class ConsumptionBatchNotAllowedFailure extends AppFailure {
  const ConsumptionBatchNotAllowedFailure(
    super.message, {
    required this.itemId,
    required this.batchId,
  });

  final String itemId;
  final String batchId;
}

/// The batch does not belong to the item, or the two disagree in some other way.
final class InvalidConsumptionBatchFailure extends AppFailure {
  const InvalidConsumptionBatchFailure(
    super.message, {
    required this.itemId,
    required this.batchId,
  });

  final String itemId;
  final String batchId;
}

/// The batch has expired, and expired stock may not be consumed (G-E7/§17).
///
/// No note, no confirmation and no preset reason can pass this. A batch is usable for
/// the whole of its expiry day and is blocked from the next operational day onwards
/// (T-10); from then it leaves only through a Pemusnahan.
final class ExpiredBatchForConsumptionFailure extends AppFailure {
  const ExpiredBatchForConsumptionFailure(
    super.message, {
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    this.lineId,
  });

  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;

  final String? lineId;
}

/// A consumed quantity is zero, negative, or otherwise not a legal quantity.
final class InvalidConsumptionQuantityFailure extends AppFailure {
  const InvalidConsumptionQuantityFailure(
    super.message, {
    this.lineId,
    required this.qty,
  });

  /// `null` while the line does not exist yet — an add that was asked for zero.
  final String? lineId;
  final Quantity qty;
}

/// The room does not hold enough of one position (§18).
final class InsufficientRoomStockFailure extends AppFailure {
  const InsufficientRoomStockFailure(
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

  /// What the room holds for this exact position.
  final Quantity available;

  /// What the document asks of it.
  final Quantity requested;
}

/// The same `(item, batch)` position already exists on this document.
///
/// The domain half of the two partial unique indexes: the database refuses it too,
/// but as a driver error, and a user needs a sentence.
final class DuplicateConsumptionLineFailure extends AppFailure {
  const DuplicateConsumptionLineFailure(
    super.message, {
    required this.consumptionId,
    required this.itemId,
    this.batchId,
  });

  final String consumptionId;
  final String itemId;
  final String? batchId;
}

/// The document's own lines and what the joined read produced no longer agree: a line
/// is missing from one side, or one is present that the other cannot account for
/// (§22).
final class ConsumptionLineIntegrityFailure extends AppFailure {
  const ConsumptionLineIntegrityFailure(
    super.message, {
    required this.consumptionId,
    this.missingLineIds = const <String>[],
    this.extraLineIds = const <String>[],
  });

  final String consumptionId;

  /// Lines the plain select found and the joined read dropped — posting on that basis
  /// would consume less stock than the document says.
  final List<String> missingLineIds;

  /// Lines the joined read produced that no live row accounts for.
  final List<String> extraLineIds;
}

/// A master row a consumption depends on is physically gone.
///
/// The same distinction [HistoricalReferenceMissingFailure] draws for Stok Opname: a
/// deactivated or soft-deleted row is still there and a document may still be posted
/// against it, but a row that cannot be found at all means the reference is broken.
/// Nothing may be invented, substituted or guessed to paper over it (§33).
final class HistoricalConsumptionReferenceMissingFailure extends AppFailure {
  const HistoricalConsumptionReferenceMissingFailure(
    super.message, {
    required this.entity,
    required this.id,
    required this.consumptionId,
  });

  /// The table whose row is missing: `items`, `item_batches`, `rooms`,
  /// `stock_locations`…
  final String entity;

  /// The id the document still points at.
  final String id;

  final String consumptionId;
}

/// A guarded write affected no rows: somebody else changed the consumption between
/// reading it and writing it. The caller must reload rather than retry blindly.
final class ConcurrentConsumptionUpdateFailure extends AppFailure {
  const ConcurrentConsumptionUpdateFailure(
    super.message, {
    required this.consumptionId,
  });

  final String consumptionId;
}

/// `posted_at` would land before `created_at` — a device clock behind the document it
/// is stamping (§35).
final class InvalidConsumptionTimestampFailure extends AppFailure {
  const InvalidConsumptionTimestampFailure(
    super.message, {
    required this.consumptionId,
    required this.createdAtUtc,
    required this.postedAtUtc,
  });

  final String consumptionId;
  final DateTime createdAtUtc;
  final DateTime postedAtUtc;
}
