import '../../../../core/enums/app_enums.dart';

/// Who is allowed to trigger a Delivery Order transition.
///
/// The distinction that matters in Milestone 4 is [goodReceipt]:
/// `shipped → received` is a real, permitted transition of the state machine, but
/// it is a consequence of a Good Receipt document rather than something anybody
/// presses a button for. Naming it keeps the state machine complete without
/// giving this milestone a way to reach it.
enum DeliveryOrderTransitionActor {
  /// The central warehouse, which prepares and ships.
  warehouse,

  /// Driven by the branch's Good Receipt document, not by a Delivery Order
  /// screen. No use case, no provider and no button in this milestone produces
  /// one.
  goodReceipt,
}

/// The Delivery Order state machine (spec §3.2, G-S1/G-S2).
///
/// ```
/// preparing ──▶ shipped ──▶ received   (final)
/// ```
///
/// A pure function of two statuses, with no repository, no clock and no Flutter
/// in sight, so the same table answers the router, the buttons on a detail screen
/// and the use case that performs the write. That is the point: a state rule
/// duplicated across those three places is a rule that eventually differs between
/// them, and the disagreement always shows up as a button that exists for a
/// transition the use case refuses.
///
/// The use case remains the **authority** — it re-reads the actor and the
/// document from the database and applies this policy there, inside the
/// transaction. What the UI gets from the same policy is only which affordances
/// to offer.
abstract final class DeliveryOrderStatePolicy {
  /// Every permitted transition, and who drives it.
  ///
  /// Written as one table rather than as predicates spread over the enum, because
  /// the question "what can happen to this document next" has exactly one answer
  /// and it should be readable in one place. Everything absent from this map is
  /// refused: `shipped → preparing`, `received → shipped`,
  /// `received → preparing`, `preparing → received`, re-entering the current
  /// state, and anything at all out of `received`.
  static const Map<
    DeliveryOrderStatus,
    Map<DeliveryOrderStatus, DeliveryOrderTransitionActor>
  >
  _transitions = {
    DeliveryOrderStatus.preparing: {
      DeliveryOrderStatus.shipped: DeliveryOrderTransitionActor.warehouse,
    },
    DeliveryOrderStatus.shipped: {
      // Driven by Good Receipt: the branch checks the goods in (G-G1).
      // Milestone 4 has no GR, so nothing here can reach it.
      DeliveryOrderStatus.received: DeliveryOrderTransitionActor.goodReceipt,
    },
    // Final states have no outgoing transitions at all (G-S2). A mistake in a
    // final document is corrected with a new document, never by moving the old
    // one.
    DeliveryOrderStatus.received: {},
  };

  /// Whether the state machine permits `from → to` at all, whoever drives it.
  static bool isAllowed(DeliveryOrderStatus from, DeliveryOrderStatus to) =>
      actorFor(from, to) != null;

  /// Who drives `from → to`, or `null` when the transition is refused.
  static DeliveryOrderTransitionActor? actorFor(
    DeliveryOrderStatus from,
    DeliveryOrderStatus to,
  ) => _transitions[from]?[to];

  /// Whether `from → to` is something a person triggers in this milestone.
  ///
  /// This is the predicate the UI asks. It is `false` for `shipped → received`,
  /// which is what keeps a "Terima" button from appearing before the document
  /// that justifies it exists.
  static bool isUserTransition(
    DeliveryOrderStatus from,
    DeliveryOrderStatus to,
  ) {
    final actor = actorFor(from, to);
    return actor != null && actor == DeliveryOrderTransitionActor.warehouse;
  }

  /// Whether `from → to` is a permitted transition that only another document may
  /// perform — `shipped → received`.
  static bool isGoodReceiptTransition(
    DeliveryOrderStatus from,
    DeliveryOrderStatus to,
  ) => actorFor(from, to) == DeliveryOrderTransitionActor.goodReceipt;

  /// Every status reachable from [from], Good Receipt's transition included.
  static Set<DeliveryOrderStatus> nextStatesOf(DeliveryOrderStatus from) =>
      (_transitions[from] ?? const {}).keys.toSet();

  /// The statuses a person may move [from] to in this milestone.
  static Set<DeliveryOrderStatus> userNextStatesOf(DeliveryOrderStatus from) =>
      nextStatesOf(from).where((to) => isUserTransition(from, to)).toSet();

  /// Whether a given role may drive `from → to`.
  ///
  /// The role check and the transition check are one question here so no caller
  /// can accidentally ask only half of it. `shipped → received` answers `false`
  /// for **every** role, including `kepala_cabang`: the transition exists, but
  /// only the Good Receipt document performs it, and that document does not exist
  /// yet.
  static bool isAllowedFor({
    required UserRole role,
    required DeliveryOrderStatus from,
    required DeliveryOrderStatus to,
  }) {
    final actor = actorFor(from, to);
    return switch (actor) {
      null || DeliveryOrderTransitionActor.goodReceipt => false,
      DeliveryOrderTransitionActor.warehouse => role == UserRole.warehouse,
    };
  }

  /// G-D1 — the Purchase Request statuses a Delivery Order may be raised
  /// against.
  ///
  /// `submitted` is included because the first shipment is what starts the
  /// warehouse working on an order: creating the document transitions the request
  /// to `processing` in the same breath.
  static const Set<PurchaseRequestStatus> eligiblePurchaseRequestStatuses = {
    PurchaseRequestStatus.submitted,
    PurchaseRequestStatus.processing,
  };

  static bool canCreateFrom(PurchaseRequestStatus status) =>
      eligiblePurchaseRequestStatuses.contains(status);

  /// Whether a request in [status] may still have a shipment **posted** against
  /// it.
  ///
  /// Narrower than [canCreateFrom] on purpose: a document may be created from a
  /// `submitted` request only because creation moves it to `processing` first, so
  /// by the time anything ships the request must already be there.
  static bool canShipAgainst(PurchaseRequestStatus status) =>
      status == PurchaseRequestStatus.processing;
}
