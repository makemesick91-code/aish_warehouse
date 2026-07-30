import '../../../../core/enums/app_enums.dart';

/// Who is allowed to trigger a Distribusi transition.
///
/// One value, and that is the whole story: the Kepala Cabang who distributes is the
/// only actor this document has (spec §3.1 marks *"Distribusi ke ruangan"* for
/// `kepala_cabang` alone). Naming the enum anyway keeps the table below the same
/// shape as the Purchase Request, Delivery Order and Good Receipt ones, so a later
/// state — should the specification grow one — has somewhere to declare its driver
/// instead of becoming an untyped exception.
enum DistributionTransitionActor {
  /// The Kepala Cabang of the distributing branch.
  kepalaCabang,
}

/// The Distribusi state machine (spec §3.2, G-S1/G-S2).
///
/// ```
/// draft ──▶ posted   (final)
/// ```
///
/// A pure function of two statuses, with no repository, no clock and no Flutter in
/// sight, so the same table answers the router, the buttons on the form and the use
/// case that performs the write. That is the point: a state rule duplicated across
/// those three places is a rule that eventually differs between them, and the
/// disagreement always shows up as a button that exists for a transition the use
/// case refuses.
///
/// The use case remains the **authority** — it re-reads the actor and the document
/// from the database and applies this policy there, inside the transaction. What the
/// UI gets from the same policy is only which affordances to offer.
abstract final class DistributionStatePolicy {
  /// Every permitted transition, and who drives it.
  ///
  /// Written as one table rather than as predicates spread over the enum, because
  /// the question "what can happen to this document next" has exactly one answer
  /// and it should be readable in one place. Everything absent from this map is
  /// refused: `posted → draft` (no un-post), `posted → posted` (no double post),
  /// re-entering `draft`, and anything at all out of `posted`.
  static const Map<
    DistributionStatus,
    Map<DistributionStatus, DistributionTransitionActor>
  >
  _transitions = {
    DistributionStatus.draft: {
      DistributionStatus.posted: DistributionTransitionActor.kepalaCabang,
    },
    // Final states have no outgoing transitions at all (G-S2). A mistake in a
    // posted distribution is corrected with a new document, never by reopening the
    // old one — which is why there is no `cancel`, no `unpost` and no `reopen`
    // anywhere in this milestone.
    DistributionStatus.posted: {},
  };

  /// Whether the state machine permits `from → to` at all, whoever drives it.
  static bool isAllowed(DistributionStatus from, DistributionStatus to) =>
      actorFor(from, to) != null;

  /// Who drives `from → to`, or `null` when the transition is refused.
  static DistributionTransitionActor? actorFor(
    DistributionStatus from,
    DistributionStatus to,
  ) => _transitions[from]?[to];

  /// Whether `from → to` is something a person triggers. True for the only
  /// transition there is — the branch head presses *Posting Distribusi*.
  static bool isUserTransition(
    DistributionStatus from,
    DistributionStatus to,
  ) => actorFor(from, to) == DistributionTransitionActor.kepalaCabang;

  /// Every status reachable from [from].
  static Set<DistributionStatus> nextStatesOf(DistributionStatus from) =>
      (_transitions[from] ?? const {}).keys.toSet();

  /// The statuses a person may move [from] to.
  static Set<DistributionStatus> userNextStatesOf(DistributionStatus from) =>
      nextStatesOf(from).where((to) => isUserTransition(from, to)).toSet();

  /// Whether a given role may drive `from → to`.
  ///
  /// The role check and the transition check are one question here so no caller can
  /// accidentally ask only half of it — "may this distribution be posted" is
  /// meaningless without "by whom" (spec §3.1: the warehouse ships, the branch head
  /// distributes, the nurse counts, and none does another's job).
  static bool isAllowedFor({
    required UserRole role,
    required DistributionStatus from,
    required DistributionStatus to,
  }) {
    final actor = actorFor(from, to);
    return switch (actor) {
      null => false,
      DistributionTransitionActor.kepalaCabang => role == UserRole.kepalaCabang,
    };
  }

  /// The one role that may create, edit or post a distribution (spec §3.1).
  ///
  /// Stated as a constant so the access policy, the guards and the architecture
  /// tests all name the same fact rather than three copies of the word.
  static const UserRole writeRole = UserRole.kepalaCabang;

  /// Whether a document in [status] may still be edited (G-S2).
  static bool isEditable(DistributionStatus status) => status.isEditable;
}
