import '../../../../core/enums/app_enums.dart';

/// Who is allowed to drive a Retur transition (§14).
///
/// **Two values, and they are two different people in two different places.** That is
/// the whole shape of this document, and the reason it is the first one in this schema
/// where G-R4 — *"tidak ada satu peran pun yang bisa membuat sekaligus menyetujui
/// dokumen yang sama"* — is enforceable structurally rather than by convention: the
/// branch that raised the return cannot be the party that confirms it, because
/// confirming is a Warehouse action and the branch has no Warehouse account.
enum GoodsReturnTransitionActor {
  /// The Kepala Cabang of the document's branch. Not "any Kepala Cabang" — the branch
  /// match is `GoodsReturnAccessPolicy`'s and `GoodsReturnGuards`' answer rather than
  /// this enum's: a state machine that also had to know about branches would be two
  /// rules in one table.
  kepalaCabang,

  /// A Petugas Warehouse — any of them, across every branch, **except** the document's
  /// creator or shipper. That exception is G-R4 and is checked in the guards *and* in
  /// the SQL predicate of the guarded write, because a user whose role changed after
  /// the document was raised would otherwise satisfy this one.
  warehouse,
}

/// The Retur Barang state machine (§14, G-S1/G-S2).
///
/// ```
/// draft ──▶ shipped ──▶ received   (final)
/// ```
///
/// A pure function of two statuses, with no repository, no clock and no Flutter in
/// sight, so the same table answers the router, the buttons on both screens and the
/// two use cases that perform the writes. That is the point: a state rule duplicated
/// across those places is a rule that eventually differs between them, and the
/// disagreement always shows up as a button that exists for a transition the use case
/// refuses.
///
/// ### Every state here is an extension decision
///
/// **The specification defines no Return document** — §2.3 lists no table and §3.2 no
/// state machine. What it states is that `movement_type` has a `return` value (§2.2),
/// that rejected Good Receipt lines *"masuk daftar retur ke Warehouse"* (G-G5), and
/// that the Warehouse screen lists them *"untuk ditindaklanjuti"* (§4.2). The three
/// states below are the smallest extension that makes those sentences into an
/// auditable workflow, and they are documented as decisions rather than presented as
/// rules the specification states.
///
/// ### Shipping is not approving, and receiving is not approving either
///
/// There is no `submitted`, no `approved` and no `rejected` here. `shipped` records a
/// physical act — a person put goods in a box and handed them over — and posts nothing
/// to the ledger (§20). `received` records the other physical act and posts everything
/// (§21). Neither is a sign-off on the *other party's* judgment: the decision to reject
/// was made and audited on the Good Receipt (G-G4), and this document only moves the
/// goods that decision produced. The UI wording follows: *Kirim Retur* and *Terima
/// Retur*, never *Setujui*.
///
/// ### Why `received` is final
///
/// The same rule `reviewed`, `received` and every `posted` in this schema follow
/// (G-S1/G-S2). Once the Warehouse balance has been credited, undoing the document
/// would mean either deleting ledger rows — which G-A1 forbids outright — or writing a
/// reversal, which is a *new* document rather than a change to this one. So there is no
/// cancel, no reopen, no un-ship and no un-receive anywhere in this milestone, and no
/// method on the DAO that could express one.
///
/// The use cases remain the **authority** — they re-read the actor and the document
/// from the database and apply this policy there, inside the transaction. What the UI
/// gets from the same policy is only which affordances to offer.
abstract final class GoodsReturnStatePolicy {
  /// Every permitted transition, and who may drive it.
  ///
  /// Written as one table rather than as predicates spread over the enum, because the
  /// question "what can happen to this document next" has exactly one answer and it
  /// should be readable in one place. Everything absent from this map is refused:
  /// `draft → received` (skipping the transit leg would credit the Warehouse for goods
  /// nobody has sent), `shipped → draft` (no un-ship), anything at all out of
  /// `received`, and re-entering the current state (no double ship, no double
  /// receive).
  static const Map<
    GoodsReturnStatus,
    Map<GoodsReturnStatus, Set<GoodsReturnTransitionActor>>
  >
  _transitions = {
    GoodsReturnStatus.draft: {
      GoodsReturnStatus.shipped: {GoodsReturnTransitionActor.kepalaCabang},
    },
    GoodsReturnStatus.shipped: {
      GoodsReturnStatus.received: {GoodsReturnTransitionActor.warehouse},
    },
    // Final states have no outgoing transitions at all (G-S2).
    GoodsReturnStatus.received: {},
  };

  /// Whether the state machine permits `from → to` at all, whoever drives it.
  static bool isAllowed(GoodsReturnStatus from, GoodsReturnStatus to) =>
      actorsFor(from, to).isNotEmpty;

  /// Who may drive `from → to`. Empty when the transition is refused.
  static Set<GoodsReturnTransitionActor> actorsFor(
    GoodsReturnStatus from,
    GoodsReturnStatus to,
  ) => _transitions[from]?[to] ?? const <GoodsReturnTransitionActor>{};

  /// Whether `from → to` is something a person triggers. True for both transitions
  /// there are — somebody presses *Kirim Retur* or *Terima Retur*.
  static bool isUserTransition(GoodsReturnStatus from, GoodsReturnStatus to) =>
      actorsFor(from, to).isNotEmpty;

  /// Every status reachable from [from].
  static Set<GoodsReturnStatus> nextStatesOf(GoodsReturnStatus from) =>
      (_transitions[from] ?? const {}).keys.toSet();

  /// The transition actor a role maps to, or `null` for a role that has no part in
  /// this workflow at all.
  ///
  /// `perawat` and `super_admin` both answer `null`, for the reasons
  /// [GoodsReturnAccessPolicy] spells out. Returning `null` rather than throwing keeps
  /// this a pure question; the refusal is the caller's.
  static GoodsReturnTransitionActor? actorOf(UserRole role) => switch (role) {
    UserRole.kepalaCabang => GoodsReturnTransitionActor.kepalaCabang,
    UserRole.warehouse => GoodsReturnTransitionActor.warehouse,
    UserRole.perawat || UserRole.superAdmin => null,
  };

  /// Whether a given role may drive `from → to`.
  ///
  /// The role check and the transition check are one question here so no caller can
  /// accidentally ask only half of it — "may this return be received" is meaningless
  /// without "by whom". It deliberately says nothing about *which* document, nor about
  /// segregation of duties: a Petugas Warehouse may receive a return, but not one they
  /// created or shipped, and that is `GoodsReturnAccessPolicy`'s and
  /// `GoodsReturnGuards`' answer.
  static bool isAllowedFor({
    required UserRole role,
    required GoodsReturnStatus from,
    required GoodsReturnStatus to,
  }) {
    final actor = actorOf(role);
    if (actor == null) return false;
    return actorsFor(from, to).contains(actor);
  }

  /// The one role that may create, edit or ship a return.
  ///
  /// Stated as a constant so the access policy, the guards and the architecture tests
  /// all name the same fact rather than three copies of `UserRole.kepalaCabang`.
  static const UserRole branchRole = UserRole.kepalaCabang;

  /// The one role that may confirm arrival.
  static const UserRole warehouseRole = UserRole.warehouse;

  /// Every role that may write anything at all on this document.
  static const Set<UserRole> writeRoles = {branchRole, warehouseRole};

  /// Whether a document in [status] may still have its note changed (§19).
  ///
  /// Named `isNoteEditable` rather than `isEditable` deliberately: on this document
  /// *nothing else* is editable in any status, so a general-sounding name would
  /// suggest a latitude that does not exist. The lines are frozen the moment they are
  /// snapshotted (§18).
  static bool isNoteEditable(GoodsReturnStatus status) => status.isEditable;
}
