import '../../../../core/enums/app_enums.dart';

/// Who is allowed to trigger a Pemakaian transition.
///
/// **One value**, and that is the whole shape of this document. Every other workflow in
/// this application has at least two actors — a nurse counts and a branch head
/// reviews, a branch head requests and the warehouse fulfils — because each of them
/// has a second half somebody else performs. A consumption has one half: the person
/// who used the goods records that they did. The Kepala Cabang reads the result
/// (`ConsumptionAccessPolicy`) and drives nothing.
enum ConsumptionTransitionActor {
  /// The Perawat who recorded the usage. Not "any Perawat" — the *creator*, which is
  /// `ConsumptionAccessPolicy`'s and `ConsumptionGuards`' answer rather than this
  /// enum's: a state machine that also had to know about ownership would be two rules
  /// in one table.
  perawat,
}

/// The Pemakaian state machine (§13, G-S1/G-S2).
///
/// ```
/// draft ──▶ posted   (final)
/// ```
///
/// A pure function of two statuses, with no repository, no clock and no Flutter in
/// sight, so the same table answers the router, the buttons on the form and the use
/// case that performs the write. That is the point: a state rule duplicated across
/// those three places is a rule that eventually differs between them, and the
/// disagreement always shows up as a button that exists for a transition the use case
/// refuses.
///
/// ### Posting is not approving
///
/// There is no `submitted`, no `approved` and no `rejected` here, and their absence is
/// a decision rather than an omission. **The specification defines no Consumption
/// document at all** — §2.3 lists no such table and §3.2 no such state machine — so
/// every state this milestone declares is an extension. The smallest extension that
/// makes the `consumption` movement §2.2 names auditable is one that records *who used
/// what, where and when*. An approval stage would add a second actor to a physical act
/// that has one, and would leave a nurse unable to record this morning's usage until
/// somebody else signed it off.
///
/// G-R4 — *"tidak ada satu peran pun yang bisa membuat sekaligus menyetujui dokumen
/// yang sama"* — is sometimes read as requiring one. It does not: it forbids one person
/// doing both halves of a *two-half* workflow, which is a reason not to invent a second
/// half here rather than a licence to. The UI wording follows: *Posting Pemakaian*,
/// never *Setujui*, never *Ajukan*.
///
/// The use case remains the **authority** — it re-reads the actor and the document from
/// the database and applies this policy there, inside the transaction. What the UI gets
/// from the same policy is only which affordances to offer.
abstract final class ConsumptionStatePolicy {
  /// Every permitted transition, and who may drive it.
  ///
  /// Written as one table rather than as predicates spread over the enum, because the
  /// question "what can happen to this document next" has exactly one answer and it
  /// should be readable in one place. Everything absent from this map is refused:
  /// `posted → draft` (no un-post), `posted → posted` (no double post), re-entering
  /// `draft`, and anything at all out of `posted`.
  static const Map<
    ConsumptionStatus,
    Map<ConsumptionStatus, Set<ConsumptionTransitionActor>>
  >
  _transitions = {
    ConsumptionStatus.draft: {
      ConsumptionStatus.posted: {ConsumptionTransitionActor.perawat},
    },
    // Final states have no outgoing transitions at all (G-S2). A mistake in a posted
    // consumption is corrected by a reversal movement against the ledger, never by
    // reopening the document — which is why there is no `cancel`, no `unpost` and no
    // `reopen` anywhere in this milestone.
    ConsumptionStatus.posted: {},
  };

  /// Whether the state machine permits `from → to` at all, whoever drives it.
  static bool isAllowed(ConsumptionStatus from, ConsumptionStatus to) =>
      actorsFor(from, to).isNotEmpty;

  /// Who may drive `from → to`. Empty when the transition is refused.
  static Set<ConsumptionTransitionActor> actorsFor(
    ConsumptionStatus from,
    ConsumptionStatus to,
  ) => _transitions[from]?[to] ?? const <ConsumptionTransitionActor>{};

  /// Whether `from → to` is something a person triggers. True for the only transition
  /// there is — somebody presses *Posting Pemakaian*.
  static bool isUserTransition(ConsumptionStatus from, ConsumptionStatus to) =>
      actorsFor(from, to).isNotEmpty;

  /// Every status reachable from [from].
  static Set<ConsumptionStatus> nextStatesOf(ConsumptionStatus from) =>
      (_transitions[from] ?? const {}).keys.toSet();

  /// The transition actor a role maps to, or `null` for a role that has no part in this
  /// workflow at all.
  ///
  /// `kepala_cabang`, `warehouse` and `super_admin` all answer `null`, for the reasons
  /// `ConsumptionAccessPolicy` spells out. Returning `null` rather than throwing keeps
  /// this a pure question; the refusal is the caller's.
  static ConsumptionTransitionActor? actorOf(UserRole role) => switch (role) {
    UserRole.perawat => ConsumptionTransitionActor.perawat,
    UserRole.kepalaCabang || UserRole.warehouse || UserRole.superAdmin => null,
  };

  /// Whether a given role may drive `from → to`.
  ///
  /// The role check and the transition check are one question here so no caller can
  /// accidentally ask only half of it — "may this consumption be posted" is meaningless
  /// without "by whom". It deliberately says nothing about *which* document: a Perawat
  /// may post a consumption, but only one they created themselves, and that is
  /// `ConsumptionAccessPolicy`'s and `ConsumptionGuards`' answer.
  static bool isAllowedFor({
    required UserRole role,
    required ConsumptionStatus from,
    required ConsumptionStatus to,
  }) {
    final actor = actorOf(role);
    if (actor == null) return false;
    return actorsFor(from, to).contains(actor);
  }

  /// The one role that may create, edit or post a consumption.
  ///
  /// Stated as a constant so the access policy, the guards and the architecture tests
  /// all name the same fact rather than three copies of `UserRole.perawat`.
  static const UserRole writeRole = UserRole.perawat;

  /// The write roles, as a set, for callers that compare against a collection.
  static const Set<UserRole> writeRoles = {writeRole};

  /// Whether a document in [status] may still be edited (G-S2).
  static bool isEditable(ConsumptionStatus status) => status.isEditable;
}
