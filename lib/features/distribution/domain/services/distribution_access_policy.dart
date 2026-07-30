import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/distribution_models.dart';
import 'distribution_state_policy.dart';

/// Which Distribusi screen is being asked for.
///
/// Named per screen rather than per URL so the rule reads as a permission question
/// ("may this person distribute this document?") instead of a routing one.
enum DistributionRouteKind {
  /// `/distributions` — the branch head's Distribusi list.
  branchList,

  /// `/distributions/new` — start a new draft.
  branchCreate,

  /// `/distributions/{id}` — the document, draft or posted.
  branchDocument,

  /// `/distributions/{id}/edit` — the multi-room form. Additionally requires the
  /// document to still be a draft (G-S2).
  branchDraft,
}

/// Why a screen was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can be precise about which rule fired.
enum DistributionAccessDenialReason {
  /// No session yet — still loading, or master data has not been seeded.
  noSession,

  /// The acting user's role does not reach this screen at all.
  role,

  /// The acting user holds a branch-scoped role but no branch.
  noBranch,

  /// The document belongs to another branch, or does not exist. These are
  /// deliberately the same answer.
  documentOutOfScope,

  /// The document exists but is not in a status this screen may show — the editor
  /// refuses a posted document, because `posted` is read-only permanently (G-S2).
  documentStatus,
}

/// The outcome of an access check.
class DistributionAccess {
  const DistributionAccess._(this.reason);

  const DistributionAccess.granted() : reason = null;

  const DistributionAccess.denied(DistributionAccessDenialReason reason)
    : this._(reason);

  /// `null` when access was granted.
  final DistributionAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// Who may read which Distribusi screen (spec §3.1, G-T1, G-R2).
///
/// This is a **read** authorization rule, separate from the write guards in
/// `DistributionGuards` for the reason the Delivery Order and Good Receipt policies
/// spell out: the write guards are the last word, but by the time a write is refused
/// a foreign document has already been fetched, rendered and read. The rules here
/// run first and decide whether it is fetched at all.
///
/// The policy is a pure function of facts the caller already holds, so it can be
/// exercised without a database, a widget tree or a router — and so the route guard,
/// the providers and the repository queries all agree by construction rather than by
/// three similar-looking `if` statements.
///
/// ### One scope, and no exceptions to it
///
/// Unlike Good Receipt, this document has **no warehouse side at all**. Every screen
/// is branch-scoped, and [requiresBranchScope] answers `true` for every kind, because
/// there is no kind that could answer otherwise. Spec §3.1 marks *"Distribusi ke
/// ruangan"* for `kepala_cabang` alone, and §2.5 makes the movement branch-internal:
/// the store the goods leave and the room they enter are both inside one branch
/// (G-T1). A cross-branch view of distributions is a *reporting* question
/// (`rekap_distribusi`, spec §4.2), and the reporting module is not this milestone.
///
/// ### Warehouse, Perawat and Super Admin
///
/// All three refused, and each for its own reason:
///
/// * **Warehouse** has no Distribusi row in spec §3.1's table. Its job ends when the
///   Delivery Order ships; what a branch then does with its own store is the branch
///   head's. It will read the recap through the reports module.
/// * **Perawat** counts stock in a room (G-R1) and reads its balances through the
///   stock module. Nothing in the specification gives a nurse a distribution
///   document, so none is granted here.
/// * **Super Admin** is granted master data, imports and reports. Widening a workflow
///   permission because an account is powerful is exactly the quiet grant G-R4
///   (segregation of duties) is about, so it is not done here.
///
/// If the specification later says otherwise, this is the one place that changes.
abstract final class DistributionAccessPolicy {
  /// The statuses a branch head may see: everything their branch has.
  static const Set<DistributionStatus> branchVisibleStatuses =
      branchDistributionStatuses;

  /// The statuses the **editor** may open. Draft only — a posted document is
  /// read-only permanently (G-S2), and the detail screen is what shows it.
  static const Set<DistributionStatus> editableStatuses = {
    DistributionStatus.draft,
  };

  /// Whether [user] may reach a screen that does not name a document.
  ///
  /// [user] is the *stored* user, not the session's claim about itself: the caller
  /// resolves it, so a tampered session cannot widen anything (O-8).
  static DistributionAccess forSection({
    required MasterUser? user,
    required DistributionRouteKind kind,
  }) {
    if (user == null) {
      return const DistributionAccess.denied(
        DistributionAccessDenialReason.noSession,
      );
    }
    if (!user.isActive) {
      return const DistributionAccess.denied(
        DistributionAccessDenialReason.role,
      );
    }
    // One role, for every kind. See the class note on why there is no second branch
    // here: this document has no warehouse side.
    if (user.role != DistributionStatePolicy.writeRole) {
      return const DistributionAccess.denied(
        DistributionAccessDenialReason.role,
      );
    }
    if (user.branchId == null) {
      return const DistributionAccess.denied(
        DistributionAccessDenialReason.noBranch,
      );
    }
    return const DistributionAccess.granted();
  }

  /// Whether [user] may open one specific distribution.
  ///
  /// [scope] is `null` when the id resolves to nothing *within the scope the lookup
  /// used* — which covers "no such distribution", "somebody else's branch" and, on
  /// the editor, "already posted", because the lookup that produced it carried all of
  /// those predicates and can therefore not tell them apart. That is the intended
  /// design, not a limitation: distinguishing them would let anyone with the app work
  /// out which document ids are real.
  static DistributionAccess forDocument({
    required MasterUser? user,
    required DistributionRouteKind kind,
    required DistributionAccessScope? scope,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null) {
      return const DistributionAccess.denied(
        DistributionAccessDenialReason.documentOutOfScope,
      );
    }

    // Belt and braces: the query was already scoped, and this catches a caller that
    // passed an unscoped lookup by mistake.
    if (scope.branchId != user!.branchId) {
      return const DistributionAccess.denied(
        DistributionAccessDenialReason.documentOutOfScope,
      );
    }
    if (!visibleStatuses(kind).contains(scope.status)) {
      return const DistributionAccess.denied(
        DistributionAccessDenialReason.documentStatus,
      );
    }
    return const DistributionAccess.granted();
  }

  /// Whether the document lookup behind [kind] must be pinned to the actor's branch.
  ///
  /// The route guard asks this instead of deciding for itself, so "which screens are
  /// branch-scoped" is stated once. Answering it wrongly in one place is precisely how
  /// an IDOR appears — and here the answer is `true` for every kind, with no way to
  /// express anything else.
  static bool requiresBranchScope(DistributionRouteKind kind) => true;

  /// The statuses the lookup behind [kind] may return.
  static Set<DistributionStatus> visibleStatuses(DistributionRouteKind kind) =>
      switch (kind) {
        DistributionRouteKind.branchDraft => editableStatuses,
        DistributionRouteKind.branchList ||
        DistributionRouteKind.branchCreate ||
        DistributionRouteKind.branchDocument => branchVisibleStatuses,
      };

  /// Whether [kind] is a screen that may change something.
  ///
  /// Asked by the UI so a read-only screen never renders an action, and by the tests
  /// so "the posted detail has no write affordance" is an assertion rather than an
  /// inspection.
  static bool isWriteScreen(DistributionRouteKind kind) =>
      kind == DistributionRouteKind.branchCreate ||
      kind == DistributionRouteKind.branchDraft;

  /// Whether [role] may write distributions at all — the predicate every provider
  /// asks before it opens a stream, so the route guard is never the only defence.
  static bool canWrite(UserRole? role) =>
      role == DistributionStatePolicy.writeRole;
}
