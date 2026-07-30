import '../../../../core/enums/app_enums.dart';

/// Who is allowed to trigger a Pemusnahan transition.
///
/// Two values, because this document has two actors — and, unlike every other
/// document in this application, *which* of them applies is decided by the source
/// location rather than by the transition. The Petugas Warehouse posts what leaves
/// Warehouse Pusat; the Kepala Cabang posts what leaves their own branch. Neither
/// can post the other's, and that rule lives in `DisposalAccessPolicy` /
/// `DisposalLocationPolicy` rather than here: a state machine that also had to
/// know about locations would be two rules in one table, and the location half
/// changes far more often than the state half.
enum DisposalTransitionActor {
  /// The Petugas Warehouse, for Warehouse Pusat.
  warehouse,

  /// The Kepala Cabang, for their own *Gudang Cabang* and rooms.
  kepalaCabang,
}

/// The Pemusnahan state machine (G-E7, G-S1/G-S2).
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
/// ### Posting is not approving
///
/// There is no `submitted`, no `approved` and no `rejected` here, and their absence
/// is a decision rather than an omission. The specification defines no Disposal
/// document at all (§2.3 lists none, §3.2 gives it no state machine), so every
/// state this milestone declares is an extension — and the smallest extension that
/// satisfies G-E7 is one that records *who destroyed what, when, and why*. An
/// approval stage would add a second actor to a physical act that has one.
///
/// G-R4 — *"tidak ada satu peran pun yang bisa membuat sekaligus menyetujui
/// dokumen yang sama"* — is sometimes read as requiring one. It does not: it
/// forbids one person doing both halves of a *two-half* workflow, which is a reason
/// not to invent a second half here rather than a licence to. The UI wording
/// follows: *Posting Pemusnahan*, never *Setujui*.
///
/// The use case remains the **authority** — it re-reads the actor and the document
/// from the database and applies this policy there, inside the transaction. What
/// the UI gets from the same policy is only which affordances to offer.
abstract final class DisposalStatePolicy {
  /// Every permitted transition, and who may drive it.
  ///
  /// Written as one table rather than as predicates spread over the enum, because
  /// the question "what can happen to this document next" has exactly one answer
  /// and it should be readable in one place. Everything absent from this map is
  /// refused: `posted → draft` (no un-post), `posted → posted` (no double post),
  /// re-entering `draft`, and anything at all out of `posted`.
  ///
  /// The value is a *set* of actors rather than one, which is the only structural
  /// difference from the Distribusi's table: both roles drive the same transition,
  /// on different documents.
  static const Map<
    DisposalStatus,
    Map<DisposalStatus, Set<DisposalTransitionActor>>
  >
  _transitions = {
    DisposalStatus.draft: {
      DisposalStatus.posted: {
        DisposalTransitionActor.warehouse,
        DisposalTransitionActor.kepalaCabang,
      },
    },
    // Final states have no outgoing transitions at all (G-S2). A mistake in a
    // posted disposal is corrected by a reversal movement against the ledger,
    // never by reopening the document — which is why there is no `cancel`, no
    // `unpost` and no `reopen` anywhere in this milestone.
    DisposalStatus.posted: {},
  };

  /// Whether the state machine permits `from → to` at all, whoever drives it.
  static bool isAllowed(DisposalStatus from, DisposalStatus to) =>
      actorsFor(from, to).isNotEmpty;

  /// Who may drive `from → to`. Empty when the transition is refused.
  static Set<DisposalTransitionActor> actorsFor(
    DisposalStatus from,
    DisposalStatus to,
  ) => _transitions[from]?[to] ?? const <DisposalTransitionActor>{};

  /// Whether `from → to` is something a person triggers. True for the only
  /// transition there is — somebody presses *Posting Pemusnahan*.
  static bool isUserTransition(DisposalStatus from, DisposalStatus to) =>
      actorsFor(from, to).isNotEmpty;

  /// Every status reachable from [from].
  static Set<DisposalStatus> nextStatesOf(DisposalStatus from) =>
      (_transitions[from] ?? const {}).keys.toSet();

  /// The transition actor a role maps to, or `null` for a role that has no part in
  /// this workflow at all.
  ///
  /// `perawat` and `super_admin` both answer `null`, for different reasons the
  /// access policy spells out. Returning `null` rather than throwing keeps this a
  /// pure question; the refusal is the caller's.
  static DisposalTransitionActor? actorOf(UserRole role) => switch (role) {
    UserRole.warehouse => DisposalTransitionActor.warehouse,
    UserRole.kepalaCabang => DisposalTransitionActor.kepalaCabang,
    UserRole.perawat || UserRole.superAdmin => null,
  };

  /// Whether a given role may drive `from → to`.
  ///
  /// The role check and the transition check are one question here so no caller can
  /// accidentally ask only half of it — "may this disposal be posted" is
  /// meaningless without "by whom". It deliberately says nothing about *which*
  /// location: a Kepala Cabang may post a disposal, but only one of their own
  /// branch's, and that is `DisposalLocationPolicy`'s answer.
  static bool isAllowedFor({
    required UserRole role,
    required DisposalStatus from,
    required DisposalStatus to,
  }) {
    final actor = actorOf(role);
    if (actor == null) return false;
    return actorsFor(from, to).contains(actor);
  }

  /// The roles that may create, edit or post a disposal *somewhere*.
  ///
  /// Stated as a constant so the access policy, the guards and the architecture
  /// tests all name the same fact rather than three copies of the pair.
  static const Set<UserRole> writeRoles = {
    UserRole.warehouse,
    UserRole.kepalaCabang,
  };

  /// Whether a document in [status] may still be edited (G-S2).
  static bool isEditable(DisposalStatus status) => status.isEditable;
}
