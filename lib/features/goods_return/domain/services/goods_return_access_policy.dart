import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/goods_return_models.dart';
import 'goods_return_state_policy.dart';

/// Which Retur screen is being asked for (§15/§27).
///
/// Named per screen rather than per URL so the rule reads as a permission question
/// ("may this person send goods back from here?") instead of a routing one. There are
/// two families because there are two audiences, and keeping them as separate values —
/// rather than one set plus an `isWarehouse` boolean — is what makes [requiredScope] a
/// total function with nothing to get wrong.
enum GoodsReturnRouteKind {
  /// `/returns` — the Kepala Cabang's Retur section: the eligible receipts, their
  /// drafts, what is in transit and what has been received.
  branchList,

  /// `/returns/new/{goodReceiptId}` — raise a return from one posted Good Receipt.
  /// Names a **receipt**, not a return: the return does not exist yet.
  branchCreate,

  /// `/returns/{id}` — the document, in any status. Branch-scoped.
  branchDocument,

  /// `/returns/{id}/edit` — the note editor. Additionally requires the document to
  /// still be a draft (§19).
  branchDraft,

  /// `/warehouse/returns` — the Petugas Warehouse's queue and history, across every
  /// branch.
  warehouseList,

  /// `/warehouse/returns/{id}` — one shipped or received document. **Never a draft.**
  warehouseDocument,
}

/// Why a screen was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can be precise about which rule fired.
enum GoodsReturnAccessDenialReason {
  /// No session yet — still loading, or master data has not been seeded.
  noSession,

  /// The acting user's role does not reach this screen at all.
  role,

  /// The acting user holds a branch-scoped role but no branch.
  noBranch,

  /// The document is outside the actor's scope, or it does not exist. These are
  /// deliberately the same answer.
  documentOutOfScope,

  /// The document exists but is not in a status this screen may show — the note editor
  /// refuses anything but a draft, and the Warehouse screens refuse a draft outright.
  documentStatus,

  /// G-R4: the actor raised or shipped this document, so they may not be the one who
  /// confirms it. Distinct from [role] because the role *is* right — it is the person
  /// that is wrong.
  segregationOfDuties,
}

/// The outcome of an access check.
class GoodsReturnAccess {
  const GoodsReturnAccess._(this.reason);

  const GoodsReturnAccess.granted() : reason = null;

  const GoodsReturnAccess.denied(GoodsReturnAccessDenialReason reason)
    : this._(reason);

  /// `null` when access was granted.
  final GoodsReturnAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// Who may read which Retur screen (§15, G-R1/G-R2/G-R4).
///
/// This is a **read** authorization rule, separate from the write guards in
/// `GoodsReturnGuards` for the reason the other feature policies spell out: the write
/// guards are the last word, but by the time a write is refused a foreign document has
/// already been fetched, rendered and read. The rules here run first and decide whether
/// it is fetched at all.
///
/// The policy is a pure function of facts the caller already holds, so it can be
/// exercised without a database, a widget tree or a router — and so the route guard,
/// the providers and the repository queries all agree by construction rather than by
/// three similar-looking `if` statements.
///
/// ### The two audiences never overlap
///
/// A Kepala Cabang sees their own branch's returns in every status, including drafts.
/// A Petugas Warehouse sees every branch's returns in exactly two statuses — `shipped`
/// and `received` — and never a draft. The `shipped` boundary is not cosmetic: a draft
/// is a branch head part way through deciding what to send, and a Warehouse queue
/// showing one would be a queue of goods nobody has handed over.
///
/// ### Why the Warehouse cannot create or ship
///
/// The goods are physically at the branch. A Warehouse user pressing *Kirim Retur*
/// would be asserting that a box left a building they are not in. G-G5 also puts the
/// rejection decision at the branch — it is the branch head who refused the goods
/// (G-G4) — so the document that carries that decision home is theirs to raise.
///
/// ### Why the Kepala Cabang cannot receive
///
/// The mirror image, and G-R4 on top of it. The Warehouse balance is credited by the
/// receive transaction, and letting the sender confirm their own delivery would make
/// the two halves of this workflow one person's word. [checkSegregation] is where that
/// is stated, and it is asked again in the guards *and* in the SQL predicate of the
/// guarded write — three times, because a role that changed after the document was
/// raised would satisfy any one of them alone.
///
/// ### Perawat and Super Admin
///
/// Both refused, and each for its own reason:
///
/// * **Perawat** works room stock (§3.1). A Good Receipt rejection is a branch-level
///   act two locations away from anything they touch.
/// * **Super Admin** is granted master data, imports and reports. Widening a workflow
///   permission because an account is powerful is exactly the quiet grant G-R4 is
///   about, so it is not done here. Their cross-branch visibility waits for the
///   reporting module.
///
/// If the specification later says otherwise, this is the one place that changes.
abstract final class GoodsReturnAccessPolicy {
  /// The statuses a branch may see of its own returns: all three (§15).
  static const Set<GoodsReturnStatus> branchVisibleStatuses = {
    GoodsReturnStatus.draft,
    GoodsReturnStatus.shipped,
    GoodsReturnStatus.received,
  };

  /// The statuses the Warehouse may see: the two that mean the goods have left a
  /// branch (§15). A draft is deliberately absent, and its absence is enforced in the
  /// SQL scope predicate as well as here.
  static const Set<GoodsReturnStatus> warehouseVisibleStatuses = {
    GoodsReturnStatus.shipped,
    GoodsReturnStatus.received,
  };

  /// The statuses the **note editor** may open. Draft only (§19).
  static const Set<GoodsReturnStatus> editableStatuses = {
    GoodsReturnStatus.draft,
  };

  /// Which query scope the lookup behind [kind] must carry.
  ///
  /// Never `null`: no Retur screen spans both audiences, and having no way to express
  /// one is what stops an unscoped lookup being introduced by a screen that "just needs
  /// to show a bit more".
  static GoodsReturnQueryScope requiredScope(GoodsReturnRouteKind kind) =>
      switch (kind) {
        GoodsReturnRouteKind.branchList ||
        GoodsReturnRouteKind.branchCreate ||
        GoodsReturnRouteKind.branchDocument ||
        GoodsReturnRouteKind.branchDraft => GoodsReturnQueryScope.branch,
        GoodsReturnRouteKind.warehouseList ||
        GoodsReturnRouteKind.warehouseDocument =>
          GoodsReturnQueryScope.warehouseInTransitOrReceived,
      };

  /// The role that reaches [kind]. One role per screen family, no overlap.
  static UserRole requiredRole(GoodsReturnRouteKind kind) =>
      switch (requiredScope(kind)) {
        GoodsReturnQueryScope.branch => GoodsReturnStatePolicy.branchRole,
        GoodsReturnQueryScope.warehouseInTransitOrReceived =>
          GoodsReturnStatePolicy.warehouseRole,
      };

  /// Whether the document lookup behind [kind] must be pinned to the actor's branch.
  ///
  /// True for the branch family and **false** for the Warehouse one — that asymmetry is
  /// the whole point of this document. A Warehouse user works one queue across every
  /// branch (§15), so pinning them to a branch would break the feature; what keeps them
  /// out of a branch's private work is the *status* scope, not a branch scope.
  static bool requiresBranch(GoodsReturnRouteKind kind) =>
      requiredScope(kind) == GoodsReturnQueryScope.branch;

  /// The statuses the lookup behind [kind] may return.
  static Set<GoodsReturnStatus> visibleStatusesFor(GoodsReturnRouteKind kind) =>
      switch (kind) {
        GoodsReturnRouteKind.branchDraft => editableStatuses,
        GoodsReturnRouteKind.branchList ||
        GoodsReturnRouteKind.branchCreate ||
        GoodsReturnRouteKind.branchDocument => branchVisibleStatuses,
        GoodsReturnRouteKind.warehouseList ||
        GoodsReturnRouteKind.warehouseDocument => warehouseVisibleStatuses,
      };

  /// Whether [kind] is a screen that may change something.
  ///
  /// Asked by the UI so a read-only screen never renders an action, and by the tests so
  /// "the shipped detail has no write affordance" is an assertion rather than an
  /// inspection. The Warehouse document screen counts: it carries *Terima Retur*.
  static bool isWriteScreen(GoodsReturnRouteKind kind) =>
      kind == GoodsReturnRouteKind.branchCreate ||
      kind == GoodsReturnRouteKind.branchDraft ||
      kind == GoodsReturnRouteKind.warehouseDocument;

  /// Whether [role] may raise, edit or ship returns — the predicate every branch
  /// provider asks before it opens a stream, so the route guard is never the only
  /// defence.
  static bool canWriteBranch(UserRole? role) =>
      role == GoodsReturnStatePolicy.branchRole;

  /// Whether [role] may confirm arrival. Says nothing about *which* document — see
  /// [checkSegregation].
  static bool canReceive(UserRole? role) =>
      role == GoodsReturnStatePolicy.warehouseRole;

  /// G-R4, as a pure question (§15).
  ///
  /// A Petugas Warehouse may not confirm a document they raised or shipped, **whatever
  /// their role is now**. That last clause is the reason this takes ids rather than
  /// roles: a Kepala Cabang who raised a return last month and has since been moved to
  /// the Warehouse team would otherwise pass every role check in the application.
  ///
  /// Asked here so a screen can hide the button, again in `GoodsReturnGuards` so the
  /// user gets a sentence instead of a silent no-op, and a third time in the SQL
  /// predicate of `markReceived` so a role change between the check and the write
  /// cannot slip past.
  static GoodsReturnAccess checkSegregation({
    required String actorUserId,
    required String createdBy,
    required String? shippedBy,
  }) {
    if (actorUserId == createdBy || actorUserId == shippedBy) {
      return const GoodsReturnAccess.denied(
        GoodsReturnAccessDenialReason.segregationOfDuties,
      );
    }
    return const GoodsReturnAccess.granted();
  }

  /// Whether [user] may reach a screen that does not name a document.
  ///
  /// [user] is the *stored* user, not the session's claim about itself: the caller
  /// resolves it, so a tampered session cannot widen anything (O-8).
  static GoodsReturnAccess forSection({
    required MasterUser? user,
    required GoodsReturnRouteKind kind,
  }) {
    if (user == null) {
      return const GoodsReturnAccess.denied(
        GoodsReturnAccessDenialReason.noSession,
      );
    }
    if (!user.isActive) {
      return const GoodsReturnAccess.denied(GoodsReturnAccessDenialReason.role);
    }
    if (user.role != requiredRole(kind)) {
      return const GoodsReturnAccess.denied(GoodsReturnAccessDenialReason.role);
    }
    // Only the branch family needs a branch. A Petugas Warehouse legitimately has none
    // — they work Warehouse Pusat, which belongs to no branch — so demanding one here
    // would lock the queue to nobody.
    if (requiresBranch(kind) && user.branchId == null) {
      return const GoodsReturnAccess.denied(
        GoodsReturnAccessDenialReason.noBranch,
      );
    }
    return const GoodsReturnAccess.granted();
  }

  /// Whether [user] may open one specific return.
  ///
  /// [scope] is `null` when the id resolves to nothing *within the scope the lookup
  /// used* — which covers "no such return", "another branch's", "a draft, seen from the
  /// Warehouse queue" and, on the note editor, "already shipped", because the lookup
  /// that produced it carried all of those predicates and can therefore not tell them
  /// apart. That is the intended design, not a limitation: distinguishing them would
  /// let anyone with the app work out which document ids are real (§27).
  ///
  /// The checks after the null test are belts to the SQL predicate's braces. The query
  /// was already scoped; these catch a caller that passed an unscoped lookup by
  /// mistake.
  ///
  /// Segregation is deliberately **not** checked here. Being the creator does not stop
  /// a Warehouse user *reading* the document — they should be able to see what they
  /// raised — it stops them confirming it, and that is [checkSegregation]'s question,
  /// asked by the button and by the use case rather than by the router.
  static GoodsReturnAccess forDocument({
    required MasterUser? user,
    required GoodsReturnRouteKind kind,
    required GoodsReturnAccessScope? scope,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null) {
      return const GoodsReturnAccess.denied(
        GoodsReturnAccessDenialReason.documentOutOfScope,
      );
    }
    if (requiresBranch(kind) && scope.branchId != user!.branchId) {
      return const GoodsReturnAccess.denied(
        GoodsReturnAccessDenialReason.documentOutOfScope,
      );
    }
    if (!visibleStatusesFor(kind).contains(scope.status)) {
      return const GoodsReturnAccess.denied(
        GoodsReturnAccessDenialReason.documentStatus,
      );
    }
    return const GoodsReturnAccess.granted();
  }
}
