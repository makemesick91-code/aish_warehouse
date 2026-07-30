import '../../../../core/enums/app_enums.dart';

/// Who is allowed to trigger a Good Receipt transition.
///
/// One value, and that is the whole story: the branch head who received the goods
/// is the only actor this document has (G-G1, spec §3.1). Naming the enum anyway
/// keeps the table below the same shape as the Purchase Request and Delivery Order
/// ones, so a later state — should the specification grow one — has somewhere to
/// declare its driver instead of becoming an untyped exception.
enum GoodReceiptTransitionActor {
  /// The Kepala Cabang of the destination branch.
  kepalaCabang,
}

/// The Good Receipt state machine (spec §3.2, G-S1/G-S2).
///
/// ```
/// checking ──▶ posted   (final)
/// ```
///
/// A pure function of two statuses, with no repository, no clock and no Flutter in
/// sight, so the same table answers the router, the buttons on a checklist and the
/// use case that performs the write. That is the point: a state rule duplicated
/// across those three places is a rule that eventually differs between them, and
/// the disagreement always shows up as a button that exists for a transition the
/// use case refuses.
///
/// The use case remains the **authority** — it re-reads the actor and the document
/// from the database and applies this policy there, inside the transaction. What
/// the UI gets from the same policy is only which affordances to offer.
abstract final class GoodReceiptStatePolicy {
  /// Every permitted transition, and who drives it.
  ///
  /// Written as one table rather than as predicates spread over the enum, because
  /// the question "what can happen to this document next" has exactly one answer
  /// and it should be readable in one place. Everything absent from this map is
  /// refused: `posted → checking` (no un-post), `posted → posted` (no double
  /// post), re-entering `checking`, and anything at all out of `posted`.
  static const Map<
    GoodReceiptStatus,
    Map<GoodReceiptStatus, GoodReceiptTransitionActor>
  >
  _transitions = {
    GoodReceiptStatus.checking: {
      GoodReceiptStatus.posted: GoodReceiptTransitionActor.kepalaCabang,
    },
    // Final states have no outgoing transitions at all (G-S2). A mistake in a
    // posted receipt is corrected with a new document, never by reopening the old
    // one — which is why there is no `cancel`, no `unpost` and no `reopen`
    // anywhere in this milestone.
    GoodReceiptStatus.posted: {},
  };

  /// Whether the state machine permits `from → to` at all, whoever drives it.
  static bool isAllowed(GoodReceiptStatus from, GoodReceiptStatus to) =>
      actorFor(from, to) != null;

  /// Who drives `from → to`, or `null` when the transition is refused.
  static GoodReceiptTransitionActor? actorFor(
    GoodReceiptStatus from,
    GoodReceiptStatus to,
  ) => _transitions[from]?[to];

  /// Whether `from → to` is something a person triggers. True for the only
  /// transition there is — the branch head presses *Posting Good Receipt*.
  static bool isUserTransition(GoodReceiptStatus from, GoodReceiptStatus to) =>
      actorFor(from, to) == GoodReceiptTransitionActor.kepalaCabang;

  /// Every status reachable from [from].
  static Set<GoodReceiptStatus> nextStatesOf(GoodReceiptStatus from) =>
      (_transitions[from] ?? const {}).keys.toSet();

  /// The statuses a person may move [from] to.
  static Set<GoodReceiptStatus> userNextStatesOf(GoodReceiptStatus from) =>
      nextStatesOf(from).where((to) => isUserTransition(from, to)).toSet();

  /// Whether a given role may drive `from → to`.
  ///
  /// The role check and the transition check are one question here so no caller can
  /// accidentally ask only half of it — "may this receipt be posted" is meaningless
  /// without "by whom" (spec §3.1: the warehouse ships, the branch receives, and
  /// neither does the other's job).
  static bool isAllowedFor({
    required UserRole role,
    required GoodReceiptStatus from,
    required GoodReceiptStatus to,
  }) {
    final actor = actorFor(from, to);
    return switch (actor) {
      null => false,
      GoodReceiptTransitionActor.kepalaCabang => role == UserRole.kepalaCabang,
    };
  }

  /// G-G1 — the Delivery Order statuses a Good Receipt may be raised against.
  ///
  /// Exactly one. A `preparing` shipment has not left the warehouse — nothing has
  /// arrived to check — and a `received` one already has its receipt, which the
  /// unique index on `good_receipts.do_id` enforces independently.
  static const Set<DeliveryOrderStatus> eligibleDeliveryOrderStatuses = {
    DeliveryOrderStatus.shipped,
  };

  static bool canCreateFrom(DeliveryOrderStatus status) =>
      eligibleDeliveryOrderStatuses.contains(status);

  /// Whether a shipment in [status] may still have its receipt **posted**.
  ///
  /// The same set, and deliberately so rather than a widened one: posting is what
  /// moves the shipment to `received`, so a shipment that is already there has
  /// nothing left for this document to do.
  static bool canPostAgainst(DeliveryOrderStatus status) =>
      canCreateFrom(status);

  /// The Purchase Request statuses under which a receipt may be posted.
  ///
  /// Both, and the pair is the point. A request is `shipped` only once **every**
  /// requested position has been fully sent (G-D5); a partial shipment leaves it
  /// `processing`. Requiring `shipped` here would therefore make the first partial
  /// delivery impossible to receive, which is exactly the workflow §23 describes.
  ///
  /// What is refused is a request that no longer stands — `draft`, `submitted`
  /// (nothing has been prepared), `closed` (already finished), `rejected` and
  /// `cancelled`.
  static const Set<PurchaseRequestStatus> receivablePurchaseRequestStatuses = {
    PurchaseRequestStatus.processing,
    PurchaseRequestStatus.shipped,
  };

  static bool canReceiveAgainst(PurchaseRequestStatus status) =>
      receivablePurchaseRequestStatuses.contains(status);

  /// Whether a request in [status] is one that closure could apply to at all.
  ///
  /// Only `shipped`. A `processing` request still has positions the warehouse has
  /// not sent, so "every shipment received" says nothing about the order being
  /// finished.
  static bool canClose(PurchaseRequestStatus status) =>
      status == PurchaseRequestStatus.shipped;

  /// The Delivery Order statuses that count as a shipment the branch has to
  /// receive before its Purchase Request may close (§23).
  ///
  /// `preparing` is deliberately absent: a draft allocation has no shipment ledger
  /// behind it (spec §2.5 posts on `shipped`), so it is not something anybody is
  /// waiting to receive. Leaving it in would make a request with a forgotten draft
  /// impossible to close, for ever.
  static const Set<DeliveryOrderStatus> shipmentStatuses = {
    DeliveryOrderStatus.shipped,
    DeliveryOrderStatus.received,
  };

  static bool countsAsShipment(DeliveryOrderStatus status) =>
      shipmentStatuses.contains(status);
}
