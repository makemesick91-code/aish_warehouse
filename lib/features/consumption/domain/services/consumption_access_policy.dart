import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/consumption_models.dart';
import 'consumption_state_policy.dart';

/// Which Pemakaian screen is being asked for.
///
/// Named per screen rather than per URL so the rule reads as a permission question
/// ("may this person record usage here?") instead of a routing one. There are two
/// families of them because there are two audiences, and keeping them as separate
/// values — rather than one set plus an `isBranchHead` boolean — is what makes
/// [requiredScope] a total function with nothing to get wrong.
enum ConsumptionRouteKind {
  /// `/consumptions` — the Perawat's own Pemakaian section.
  nurseList,

  /// `/consumptions/new` — start a new draft against one of their branch's rooms.
  nurseCreate,

  /// `/consumptions/{id}` — the document, draft or posted. **Own documents only.**
  nurseDocument,

  /// `/consumptions/{id}/edit` — the form. Additionally requires the document to still
  /// be a draft (G-S2), and their own.
  nurseDraft,

  /// `/branch-consumptions` — the Kepala Cabang's read-only history.
  branchList,

  /// `/branch-consumptions/{id}` — one posted document, read-only.
  branchDocument,
}

/// Why a screen was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can be precise about which rule fired.
enum ConsumptionAccessDenialReason {
  /// No session yet — still loading, or master data has not been seeded.
  noSession,

  /// The acting user's role does not reach this screen at all.
  role,

  /// The acting user holds a branch-scoped role but no branch.
  noBranch,

  /// The document is outside the actor's scope, or it does not exist. These are
  /// deliberately the same answer.
  documentOutOfScope,

  /// The document exists but is not in a status this screen may show — the editor
  /// refuses a posted document, because `posted` is read-only permanently (G-S2), and
  /// the branch history refuses a draft.
  documentStatus,
}

/// The outcome of an access check.
class ConsumptionAccess {
  const ConsumptionAccess._(this.reason);

  const ConsumptionAccess.granted() : reason = null;

  const ConsumptionAccess.denied(ConsumptionAccessDenialReason reason)
    : this._(reason);

  /// `null` when access was granted.
  final ConsumptionAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// Who may read which Pemakaian screen (§14, G-R1/G-R2).
///
/// This is a **read** authorization rule, separate from the write guards in
/// `ConsumptionGuards` for the reason the other feature policies spell out: the write
/// guards are the last word, but by the time a write is refused a foreign document has
/// already been fetched, rendered and read. The rules here run first and decide whether
/// it is fetched at all.
///
/// The policy is a pure function of facts the caller already holds, so it can be
/// exercised without a database, a widget tree or a router — and so the route guard, the
/// providers and the repository queries all agree by construction rather than by three
/// similar-looking `if` statements.
///
/// ### Ownership, not just branch
///
/// This is the first document in the application whose read scope is a **person** rather
/// than a place. Every earlier one is branch-scoped or warehouse-scoped: any Kepala
/// Cabang of a branch may open any of its Purchase Requests. A Pemakaian draft is
/// different, and §14 says so: it is one nurse's record of what they used, unposted,
/// and a second nurse editing it would be changing somebody else's account of a shift
/// they did not work. So [ConsumptionQueryScope.ownDocuments] pins the lookup to
/// `created_by`, and the guards re-check it inside the write transaction.
///
/// Posted documents follow the same rule for the nurse — they see their own history —
/// and open up to the branch head, who sees every posted consumption of their branch
/// read-only. The asymmetry is deliberate: a draft is work in progress, a posted
/// document is a fact about the branch's stock.
///
/// ### Why the Kepala Cabang cannot write
///
/// Spec §3.1 gives the branch head *"Review/lock Stok Opname"*, *"Buat & submit PR"*,
/// *"Good Receipt"* and *"Distribusi ke ruangan"* — every one of them a *branch-level*
/// act. Recording what was physically used in a treatment room is not on that list, and
/// it is not a gap to be filled by seniority: the person who opened the packet is the
/// only one who knows how much came out of it. What the branch head legitimately needs
/// is oversight, and that is exactly what the read-only history gives them.
///
/// ### Warehouse and Super Admin
///
/// Both refused, and each for its own reason:
///
/// * **Warehouse** operates Warehouse Pusat (§3.1). A treatment room's stock is three
///   locations away from anything they touch, and the cross-branch *view* they might
///   want is a reporting question (G-L1), not a workflow permission.
/// * **Super Admin** is granted master data, imports and reports. Widening a workflow
///   permission because an account is powerful is exactly the quiet grant G-R4 is
///   about, so it is not done here. Their cross-branch visibility waits for the
///   reporting module.
///
/// If the specification later says otherwise, this is the one place that changes.
abstract final class ConsumptionAccessPolicy {
  /// The statuses a nurse may see of their own documents: both.
  static const Set<ConsumptionStatus> ownVisibleStatuses =
      visibleConsumptionStatuses;

  /// The statuses a branch head may see: `posted` only (§14).
  static const Set<ConsumptionStatus> branchVisibleStatuses =
      branchVisibleConsumptionStatuses;

  /// The statuses the **editor** may open. Draft only — a posted document is read-only
  /// permanently (G-S2), and the detail screen is what shows it.
  static const Set<ConsumptionStatus> editableStatuses = {
    ConsumptionStatus.draft,
  };

  /// Which query scope the lookup behind [kind] must carry.
  ///
  /// Never `null`: there is no Pemakaian screen in this milestone that spans both
  /// audiences, and having no way to express one is what stops an unscoped lookup being
  /// introduced by a screen that "just needs to show a bit more".
  static ConsumptionQueryScope requiredScope(ConsumptionRouteKind kind) =>
      switch (kind) {
        ConsumptionRouteKind.nurseList ||
        ConsumptionRouteKind.nurseCreate ||
        ConsumptionRouteKind.nurseDocument ||
        ConsumptionRouteKind.nurseDraft => ConsumptionQueryScope.ownDocuments,
        ConsumptionRouteKind.branchList ||
        ConsumptionRouteKind.branchDocument =>
          ConsumptionQueryScope.branchPosted,
      };

  /// The role that reaches [kind]. One role per screen family, no overlap.
  static UserRole requiredRole(ConsumptionRouteKind kind) =>
      switch (requiredScope(kind)) {
        ConsumptionQueryScope.ownDocuments => ConsumptionStatePolicy.writeRole,
        ConsumptionQueryScope.branchPosted => UserRole.kepalaCabang,
      };

  /// Whether the document lookup behind [kind] must be pinned to the actor's own user
  /// id.
  ///
  /// The route guard asks this instead of deciding for itself, so "which screens are
  /// owner-scoped" is stated once. Answering it wrongly in one place is precisely how
  /// an IDOR appears.
  static bool requiresOwnership(ConsumptionRouteKind kind) =>
      requiredScope(kind) == ConsumptionQueryScope.ownDocuments;

  /// Whether the document lookup behind [kind] must be pinned to the actor's branch.
  ///
  /// True for both families, and for different reasons: the branch head's scope *is*
  /// the branch, and the nurse's own documents are all in their branch anyway — but
  /// asserting it is the belt to the ownership predicate's braces, and it is what
  /// catches a nurse whose branch changed while a draft of theirs sat open in another
  /// one.
  static bool requiresBranch(ConsumptionRouteKind kind) => true;

  /// The statuses the lookup behind [kind] may return.
  static Set<ConsumptionStatus> visibleStatusesFor(ConsumptionRouteKind kind) =>
      switch (kind) {
        ConsumptionRouteKind.nurseDraft => editableStatuses,
        ConsumptionRouteKind.nurseList ||
        ConsumptionRouteKind.nurseCreate ||
        ConsumptionRouteKind.nurseDocument => ownVisibleStatuses,
        ConsumptionRouteKind.branchList ||
        ConsumptionRouteKind.branchDocument => branchVisibleStatuses,
      };

  /// Whether [kind] is a screen that may change something.
  ///
  /// Asked by the UI so a read-only screen never renders an action, and by the tests so
  /// "the branch history has no write affordance" is an assertion rather than an
  /// inspection.
  static bool isWriteScreen(ConsumptionRouteKind kind) =>
      kind == ConsumptionRouteKind.nurseCreate ||
      kind == ConsumptionRouteKind.nurseDraft;

  /// Whether [role] may write consumptions at all — the predicate every provider asks
  /// before it opens a stream, so the route guard is never the only defence.
  static bool canWrite(UserRole? role) =>
      role != null && ConsumptionStatePolicy.writeRoles.contains(role);

  /// Whether [role] may read one branch's posted history.
  static bool canReadBranchHistory(UserRole? role) =>
      role == UserRole.kepalaCabang;

  /// Whether [user] may reach a screen that does not name a document.
  ///
  /// [user] is the *stored* user, not the session's claim about itself: the caller
  /// resolves it, so a tampered session cannot widen anything (O-8).
  static ConsumptionAccess forSection({
    required MasterUser? user,
    required ConsumptionRouteKind kind,
  }) {
    if (user == null) {
      return const ConsumptionAccess.denied(
        ConsumptionAccessDenialReason.noSession,
      );
    }
    if (!user.isActive) {
      return const ConsumptionAccess.denied(ConsumptionAccessDenialReason.role);
    }
    if (user.role != requiredRole(kind)) {
      return const ConsumptionAccess.denied(ConsumptionAccessDenialReason.role);
    }
    // Both families are branch-scoped, and a branch-scoped role without a branch is a
    // data fault rather than a permission that happens to be wide.
    if (user.branchId == null) {
      return const ConsumptionAccess.denied(
        ConsumptionAccessDenialReason.noBranch,
      );
    }
    return const ConsumptionAccess.granted();
  }

  /// Whether [user] may open one specific consumption.
  ///
  /// [scope] is `null` when the id resolves to nothing *within the scope the lookup
  /// used* — which covers "no such consumption", "another nurse's", "another branch's",
  /// "a draft, seen from the branch history" and, on the editor, "already posted",
  /// because the lookup that produced it carried all of those predicates and can
  /// therefore not tell them apart. That is the intended design, not a limitation:
  /// distinguishing them would let anyone with the app work out which document ids are
  /// real.
  ///
  /// The three checks after the null test are belts to the SQL predicate's braces. The
  /// query was already scoped; these catch a caller that passed an unscoped lookup by
  /// mistake.
  static ConsumptionAccess forDocument({
    required MasterUser? user,
    required ConsumptionRouteKind kind,
    required ConsumptionAccessScope? scope,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null) {
      return const ConsumptionAccess.denied(
        ConsumptionAccessDenialReason.documentOutOfScope,
      );
    }
    if (requiresOwnership(kind) && scope.createdBy != user!.id) {
      return const ConsumptionAccess.denied(
        ConsumptionAccessDenialReason.documentOutOfScope,
      );
    }
    if (requiresBranch(kind) && scope.branchId != user!.branchId) {
      return const ConsumptionAccess.denied(
        ConsumptionAccessDenialReason.documentOutOfScope,
      );
    }
    if (!visibleStatusesFor(kind).contains(scope.status)) {
      return const ConsumptionAccess.denied(
        ConsumptionAccessDenialReason.documentStatus,
      );
    }
    return const ConsumptionAccess.granted();
  }
}
