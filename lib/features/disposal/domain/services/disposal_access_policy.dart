import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/disposal_models.dart';
import 'disposal_state_policy.dart';

/// Which Pemusnahan screen is being asked for.
///
/// Named per screen rather than per URL so the rule reads as a permission question
/// ("may this person destroy stock here?") instead of a routing one. There are two
/// families of them because there are two scopes, and keeping them as separate
/// values — rather than one set plus a `isWarehouse` boolean — is what makes
/// [requiredScope] a total function with nothing to get wrong.
enum DisposalRouteKind {
  /// `/warehouse/disposals` — the Petugas Warehouse's Pemusnahan section.
  warehouseList,

  /// `/warehouse/disposals/new` — start a new draft against Warehouse Pusat.
  warehouseCreate,

  /// `/warehouse/disposals/{id}` — the document, draft or posted.
  warehouseDocument,

  /// `/warehouse/disposals/{id}/edit` — the form. Additionally requires the
  /// document to still be a draft (G-S2).
  warehouseDraft,

  /// `/disposals` — the Kepala Cabang's Pemusnahan section.
  branchList,

  /// `/disposals/new` — start a new draft against one of their own locations.
  branchCreate,

  /// `/disposals/{id}` — the document, draft or posted.
  branchDocument,

  /// `/disposals/{id}/edit` — the form, draft only.
  branchDraft,
}

/// Why a screen was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can be precise about which rule fired.
enum DisposalAccessDenialReason {
  /// No session yet — still loading, or master data has not been seeded.
  noSession,

  /// The acting user's role does not reach this screen at all.
  role,

  /// The acting user holds a branch-scoped role but no branch.
  noBranch,

  /// The document's source is outside the actor's scope, or it does not exist.
  /// These are deliberately the same answer.
  documentOutOfScope,

  /// The document exists but is not in a status this screen may show — the editor
  /// refuses a posted document, because `posted` is read-only permanently (G-S2).
  documentStatus,
}

/// The outcome of an access check.
class DisposalAccess {
  const DisposalAccess._(this.reason);

  const DisposalAccess.granted() : reason = null;

  const DisposalAccess.denied(DisposalAccessDenialReason reason)
    : this._(reason);

  /// `null` when access was granted.
  final DisposalAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// Who may read which Pemusnahan screen (§14, G-E7, G-R2).
///
/// This is a **read** authorization rule, separate from the write guards in
/// `DisposalGuards` for the reason the other feature policies spell out: the write
/// guards are the last word, but by the time a write is refused a foreign document
/// has already been fetched, rendered and read. The rules here run first and decide
/// whether it is fetched at all.
///
/// The policy is a pure function of facts the caller already holds, so it can be
/// exercised without a database, a widget tree or a router — and so the route
/// guard, the providers and the repository queries all agree by construction rather
/// than by three similar-looking `if` statements.
///
/// ### Two scopes, and neither can reach the other
///
/// This is the first document in the application with a *warehouse* side and a
/// *branch* side that are genuinely symmetric. A Delivery Order's warehouse list
/// spans every branch by design; a Good Receipt's warehouse view is read-only over
/// posted branch documents. Here the two sides are disjoint: the Petugas Warehouse
/// writes and reads exactly what leaves Warehouse Pusat, the Kepala Cabang exactly
/// what leaves their own branch, and neither list ever contains one of the other's
/// documents. [requiredScope] is what states that once, and the DAO carries it into
/// the SQL so a document outside the scope is not fetched rather than fetched and
/// then withheld.
///
/// ### Perawat and Super Admin
///
/// Both refused, and each for its own reason:
///
/// * **Perawat** counts stock in a room (G-R1) and reads its balances through the
///   stock module — where an expiry badge still shows them what is wrong, which is
///   exactly what G-E6 asks for. What they do not get is the write path: destroying
///   stock is an irreversible act with no counter-entry, and spec §3.1 gives a
///   nurse no document that removes inventory.
/// * **Super Admin** is granted master data, imports and reports. Widening a
///   workflow permission because an account is powerful is exactly the quiet grant
///   G-R4 (segregation of duties) is about, so it is not done here. The
///   cross-location *view* a Super Admin legitimately needs is a reporting
///   question (G-E8), and the reporting module is a later milestone.
///
/// If the specification later says otherwise, this is the one place that changes.
abstract final class DisposalAccessPolicy {
  /// The statuses either side may see: everything within its own scope.
  static const Set<DisposalStatus> visibleStatuses = visibleDisposalStatuses;

  /// The statuses the **editor** may open. Draft only — a posted document is
  /// read-only permanently (G-S2), and the detail screen is what shows it.
  static const Set<DisposalStatus> editableStatuses = {DisposalStatus.draft};

  /// Which location scope the lookup behind [kind] must carry.
  ///
  /// Never `null`: there is no Pemusnahan screen in this milestone that spans both
  /// sides, and having no way to express one is what stops an unscoped lookup being
  /// introduced by a screen that "just needs to show a bit more".
  static DisposalLocationScope requiredScope(DisposalRouteKind kind) =>
      switch (kind) {
        DisposalRouteKind.warehouseList ||
        DisposalRouteKind.warehouseCreate ||
        DisposalRouteKind.warehouseDocument ||
        DisposalRouteKind.warehouseDraft => DisposalLocationScope.warehouse,
        DisposalRouteKind.branchList ||
        DisposalRouteKind.branchCreate ||
        DisposalRouteKind.branchDocument ||
        DisposalRouteKind.branchDraft => DisposalLocationScope.branch,
      };

  /// The role that reaches [kind]. One role per screen family, no overlap.
  static UserRole requiredRole(DisposalRouteKind kind) =>
      switch (requiredScope(kind)) {
        DisposalLocationScope.warehouse => UserRole.warehouse,
        DisposalLocationScope.branch => UserRole.kepalaCabang,
      };

  /// Whether the document lookup behind [kind] must be pinned to the actor's own
  /// branch.
  ///
  /// The route guard asks this instead of deciding for itself, so "which screens
  /// are branch-scoped" is stated once. Answering it wrongly in one place is
  /// precisely how an IDOR appears.
  static bool requiresBranchScope(DisposalRouteKind kind) =>
      requiredScope(kind) == DisposalLocationScope.branch;

  /// The statuses the lookup behind [kind] may return.
  static Set<DisposalStatus> visibleStatusesFor(DisposalRouteKind kind) =>
      switch (kind) {
        DisposalRouteKind.warehouseDraft ||
        DisposalRouteKind.branchDraft => editableStatuses,
        DisposalRouteKind.warehouseList ||
        DisposalRouteKind.warehouseCreate ||
        DisposalRouteKind.warehouseDocument ||
        DisposalRouteKind.branchList ||
        DisposalRouteKind.branchCreate ||
        DisposalRouteKind.branchDocument => visibleStatuses,
      };

  /// Whether [kind] is a screen that may change something.
  ///
  /// Asked by the UI so a read-only screen never renders an action, and by the
  /// tests so "the posted detail has no write affordance" is an assertion rather
  /// than an inspection.
  static bool isWriteScreen(DisposalRouteKind kind) =>
      kind == DisposalRouteKind.warehouseCreate ||
      kind == DisposalRouteKind.warehouseDraft ||
      kind == DisposalRouteKind.branchCreate ||
      kind == DisposalRouteKind.branchDraft;

  /// Whether [role] may write disposals at all — the predicate every provider asks
  /// before it opens a stream, so the route guard is never the only defence.
  static bool canWrite(UserRole? role) =>
      role != null && DisposalStatePolicy.writeRoles.contains(role);

  /// Whether [user] may reach a screen that does not name a document.
  ///
  /// [user] is the *stored* user, not the session's claim about itself: the caller
  /// resolves it, so a tampered session cannot widen anything (O-8).
  static DisposalAccess forSection({
    required MasterUser? user,
    required DisposalRouteKind kind,
  }) {
    if (user == null) {
      return const DisposalAccess.denied(DisposalAccessDenialReason.noSession);
    }
    if (!user.isActive) {
      return const DisposalAccess.denied(DisposalAccessDenialReason.role);
    }
    if (user.role != requiredRole(kind)) {
      return const DisposalAccess.denied(DisposalAccessDenialReason.role);
    }
    if (requiresBranchScope(kind) && user.branchId == null) {
      return const DisposalAccess.denied(DisposalAccessDenialReason.noBranch);
    }
    return const DisposalAccess.granted();
  }

  /// Whether [user] may open one specific disposal.
  ///
  /// [scope] is `null` when the id resolves to nothing *within the scope the lookup
  /// used* — which covers "no such disposal", "somebody else's branch", "the
  /// warehouse's, seen from a branch account" and, on the editor, "already posted",
  /// because the lookup that produced it carried all of those predicates and can
  /// therefore not tell them apart. That is the intended design, not a limitation:
  /// distinguishing them would let anyone with the app work out which document ids
  /// are real.
  ///
  /// [sourceBranchId] is the branch of the document's source location, which the
  /// caller resolves alongside the scope. It is the belt to the SQL predicate's
  /// braces: the query was already scoped, and this catches a caller that passed an
  /// unscoped lookup by mistake.
  static DisposalAccess forDocument({
    required MasterUser? user,
    required DisposalRouteKind kind,
    required DisposalAccessScope? scope,
    String? sourceBranchId,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null) {
      return const DisposalAccess.denied(
        DisposalAccessDenialReason.documentOutOfScope,
      );
    }
    if (requiresBranchScope(kind) && sourceBranchId != user!.branchId) {
      return const DisposalAccess.denied(
        DisposalAccessDenialReason.documentOutOfScope,
      );
    }
    if (!visibleStatusesFor(kind).contains(scope.status)) {
      return const DisposalAccess.denied(
        DisposalAccessDenialReason.documentStatus,
      );
    }
    return const DisposalAccess.granted();
  }
}
