import '../../../../core/enums/app_enums.dart';

/// Who is allowed to trigger a transition.
///
/// The distinction that matters in Milestone 3 is [system]: `processing →
/// shipped` and `shipped → closed` are real, permitted transitions of the state
/// machine, but they are consequences of Delivery Order and Good Receipt
/// documents rather than something anybody presses a button for. Naming them
/// keeps the state machine complete without giving this milestone a way to reach
/// them.
enum PurchaseRequestTransitionActor {
  /// The branch head who raised the request.
  kepalaCabang,

  /// The central warehouse.
  warehouse,

  /// Driven by another document, not by a person. No use case and no button in
  /// this milestone produces one.
  system,
}

/// The Purchase Request state machine (spec §3.2, G-S1/G-S3/G-P5).
///
/// ```
/// draft ──▶ submitted ──▶ processing ──▶ shipped ──▶ closed
///       └─▶ cancelled  └─▶ cancelled   └─▶ rejected
/// ```
///
/// A pure function of two statuses, with no repository, no clock and no Flutter
/// in sight, so the same table answers the router, the buttons on a detail screen
/// and the use case that performs the write. That is the point: a state rule
/// duplicated across those three places is a rule that eventually differs between
/// them, and the disagreement always shows up as a button that exists for a
/// transition the use case refuses.
///
/// The use case remains the **authority** — it re-reads the actor and the document
/// from the database and applies this policy there. What the UI gets from the same
/// policy is only which affordances to offer.
abstract final class PurchaseRequestStatePolicy {
  /// Every permitted transition, and who drives it.
  ///
  /// Written as one table rather than as predicates spread over the enum, because
  /// the question "what can happen to this document next" has exactly one answer
  /// and it should be readable in one place. Everything absent from this map is
  /// refused: `submitted → draft`, `processing → submitted`, `processing →
  /// cancelled`, `rejected → processing`, `cancelled → draft`, `shipped →
  /// processing`, and anything at all out of `closed`.
  static const Map<
    PurchaseRequestStatus,
    Map<PurchaseRequestStatus, PurchaseRequestTransitionActor>
  >
  _transitions = {
    PurchaseRequestStatus.draft: {
      PurchaseRequestStatus.submitted:
          PurchaseRequestTransitionActor.kepalaCabang,
      PurchaseRequestStatus.cancelled:
          PurchaseRequestTransitionActor.kepalaCabang,
    },
    PurchaseRequestStatus.submitted: {
      PurchaseRequestStatus.processing:
          PurchaseRequestTransitionActor.warehouse,
      // G-S3: withdrawal is possible right up to the moment the warehouse
      // starts work, and not one step further.
      PurchaseRequestStatus.cancelled:
          PurchaseRequestTransitionActor.kepalaCabang,
    },
    PurchaseRequestStatus.processing: {
      PurchaseRequestStatus.rejected: PurchaseRequestTransitionActor.warehouse,
      // Driven by Delivery Order: the request becomes `shipped` when every
      // line has been fully sent (G-D5). Milestone 3 has no DO, so nothing
      // here can reach it.
      PurchaseRequestStatus.shipped: PurchaseRequestTransitionActor.system,
    },
    PurchaseRequestStatus.shipped: {
      // Driven by Good Receipt: `closed` once every DO has been received.
      PurchaseRequestStatus.closed: PurchaseRequestTransitionActor.system,
    },
    // Final states have no outgoing transitions at all (G-S2). A mistake in
    // a final document is corrected with a new document, never by moving the
    // old one.
    PurchaseRequestStatus.closed: {},
    PurchaseRequestStatus.rejected: {},
    PurchaseRequestStatus.cancelled: {},
  };

  /// Whether the state machine permits `from → to` at all, whoever drives it.
  static bool isAllowed(PurchaseRequestStatus from, PurchaseRequestStatus to) =>
      actorFor(from, to) != null;

  /// Who drives `from → to`, or `null` when the transition is refused.
  static PurchaseRequestTransitionActor? actorFor(
    PurchaseRequestStatus from,
    PurchaseRequestStatus to,
  ) => _transitions[from]?[to];

  /// Whether `from → to` is something a person triggers in this milestone.
  ///
  /// This is the predicate the UI asks. It is `false` for the two `system`
  /// transitions, which is what keeps "Kirim" and "Tutup" buttons from appearing
  /// before the documents that justify them exist.
  static bool isUserTransition(
    PurchaseRequestStatus from,
    PurchaseRequestStatus to,
  ) {
    final actor = actorFor(from, to);
    return actor != null && actor != PurchaseRequestTransitionActor.system;
  }

  /// Whether `from → to` is a permitted transition that only another document may
  /// perform — `processing → shipped` and `shipped → closed`.
  static bool isSystemTransition(
    PurchaseRequestStatus from,
    PurchaseRequestStatus to,
  ) => actorFor(from, to) == PurchaseRequestTransitionActor.system;

  /// Every status reachable from [from], system transitions included.
  static Set<PurchaseRequestStatus> nextStatesOf(PurchaseRequestStatus from) =>
      (_transitions[from] ?? const {}).keys.toSet();

  /// The statuses a person may move [from] to in this milestone.
  static Set<PurchaseRequestStatus> userNextStatesOf(
    PurchaseRequestStatus from,
  ) => nextStatesOf(from).where((to) => isUserTransition(from, to)).toSet();

  /// Whether a given role may drive `from → to`.
  ///
  /// The role check and the transition check are one question here so no caller
  /// can accidentally ask only half of it — "may this document be processed" is
  /// meaningless without "by whom" (G-R3: the warehouse processes and rejects; it
  /// never cancels somebody else's order).
  static bool isAllowedFor({
    required UserRole role,
    required PurchaseRequestStatus from,
    required PurchaseRequestStatus to,
  }) {
    final actor = actorFor(from, to);
    return switch (actor) {
      null || PurchaseRequestTransitionActor.system => false,
      PurchaseRequestTransitionActor.kepalaCabang =>
        role == UserRole.kepalaCabang,
      PurchaseRequestTransitionActor.warehouse => role == UserRole.warehouse,
    };
  }
}
