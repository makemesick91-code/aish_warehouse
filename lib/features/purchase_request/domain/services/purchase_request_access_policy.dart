import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/purchase_request_models.dart';

/// Which Purchase Request screen is being asked for.
///
/// Named per screen rather than per URL so the rule reads as a permission question
/// ("may this person process this request?") instead of a routing one.
enum PurchaseRequestRouteKind {
  /// `/purchase-requests` — the branch head's own list.
  branchList,

  /// `/purchase-requests/new` — the create wizard.
  branchCreate,

  /// `/purchase-requests/{id}` — read-only detail of one of their requests.
  branchDocument,

  /// `/purchase-requests/{id}/edit` — the draft editor.
  branchDraft,

  /// `/warehouse/purchase-requests` — the central inbox, across every branch.
  warehouseQueue,

  /// `/warehouse/purchase-requests/{id}` — one request, for processing.
  warehouseDocument,
}

/// Why a screen was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can be precise about which rule fired.
enum PurchaseRequestAccessDenialReason {
  /// No session yet — still loading, or master data has not been seeded.
  noSession,

  /// The acting user's role does not reach this screen at all.
  role,

  /// The acting user holds a branch-scoped role but no branch.
  noBranch,

  /// The document belongs to another branch, or does not exist. These are
  /// deliberately the same answer.
  documentOutOfScope,

  /// The document exists but is not in a status this screen may show — a draft has
  /// nothing for the warehouse to process, and a submitted request has nothing to
  /// edit.
  documentStatus,
}

/// The outcome of an access check.
class PurchaseRequestAccess {
  const PurchaseRequestAccess._(this.reason);

  const PurchaseRequestAccess.granted() : reason = null;

  const PurchaseRequestAccess.denied(PurchaseRequestAccessDenialReason reason)
    : this._(reason);

  /// `null` when access was granted.
  final PurchaseRequestAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// Who may read which Purchase Request screen (spec §3.1, G-R2, G-R3).
///
/// This is a **read** authorization rule, and it is separate from the write guards
/// in `PurchaseRequestGuards` for a reason. The write guards answer "may this
/// action be performed", and they are the last word — every use case re-reads the
/// actor from the database and applies them. But by the time a write is refused, a
/// document from another branch has already been fetched, rendered and read. The
/// rules here run first and decide whether it is fetched at all.
///
/// The policy is a pure function of facts the caller already holds, so it can be
/// exercised without a database, a widget tree or a router — and so the route
/// guard, the providers and the repository queries all agree by construction rather
/// than by three similar-looking `if` statements.
///
/// ### Two scopes, on purpose
///
/// The branch screens are **branch-scoped**: a Kepala Cabang sees their own branch
/// and nothing else (G-R2). The warehouse screens are **not**, because the central
/// warehouse's whole job spans branches (spec §4.2, "daftar PR `submitted` semua
/// cabang"). What replaces the branch predicate there is a status predicate: a
/// `draft` is device-authoritative until it is submitted (G-Y2), so it is invisible
/// to the warehouse however the URL is typed.
///
/// ### Super Admin
///
/// Refused. Spec §3.1 grants Super Admin master data, imports and reports — it does
/// not list "Buat & submit PR" or "Proses PR", both of which are marked for a
/// single role. Widening a workflow permission because an account is powerful is
/// exactly the kind of quiet grant G-R4 (segregation of duties) is about, so it is
/// not done here. If the specification later says otherwise, this is the one place
/// that changes.
abstract final class PurchaseRequestAccessPolicy {
  /// Whether [user] may reach a screen that does not name a document.
  ///
  /// [user] is the *stored* user, not the session's claim about itself: the caller
  /// resolves it, so a tampered session cannot widen anything (O-8).
  static PurchaseRequestAccess forSection({
    required MasterUser? user,
    required PurchaseRequestRouteKind kind,
  }) {
    if (user == null) {
      return const PurchaseRequestAccess.denied(
        PurchaseRequestAccessDenialReason.noSession,
      );
    }
    if (!user.isActive) {
      return const PurchaseRequestAccess.denied(
        PurchaseRequestAccessDenialReason.role,
      );
    }

    final isBranchScreen = _isBranchScreen(kind);
    final allowedRole = isBranchScreen
        ? UserRole.kepalaCabang
        : UserRole.warehouse;

    if (user.role != allowedRole) {
      return const PurchaseRequestAccess.denied(
        PurchaseRequestAccessDenialReason.role,
      );
    }
    // Only the branch screens need a branch. The warehouse deliberately has none
    // (`users.branch_id` is NULL for it), and demanding one here would lock the
    // central inbox out of its own queue.
    if (isBranchScreen && user.branchId == null) {
      return const PurchaseRequestAccess.denied(
        PurchaseRequestAccessDenialReason.noBranch,
      );
    }
    return const PurchaseRequestAccess.granted();
  }

  /// Whether [user] may open one specific document.
  ///
  /// [scope] is `null` when the id resolves to nothing *within the scope the lookup
  /// used* — which, on a branch screen, covers both "no such document" and
  /// "somebody else's branch", because the lookup that produced it was
  /// branch-scoped and can therefore not tell the two apart. That is the intended
  /// design, not a limitation.
  static PurchaseRequestAccess forDocument({
    required MasterUser? user,
    required PurchaseRequestRouteKind kind,
    required PurchaseRequestAccessScope? scope,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null) {
      return const PurchaseRequestAccess.denied(
        PurchaseRequestAccessDenialReason.documentOutOfScope,
      );
    }

    if (_isBranchScreen(kind)) {
      // Belt and braces: the query was already scoped, and this catches a caller
      // that passed an unscoped lookup by mistake.
      if (scope.branchId != user!.branchId) {
        return const PurchaseRequestAccess.denied(
          PurchaseRequestAccessDenialReason.documentOutOfScope,
        );
      }
      // G-P5: there is nothing to edit on a document that has been sent. The
      // read-only detail screen renders every status; the editor renders one.
      if (kind == PurchaseRequestRouteKind.branchDraft &&
          !scope.status.isEditable) {
        return const PurchaseRequestAccess.denied(
          PurchaseRequestAccessDenialReason.documentStatus,
        );
      }
      return const PurchaseRequestAccess.granted();
    }

    // A branch's draft has not been handed over (G-Y2), so the warehouse must not
    // be able to open it by typing its id — the queue never lists it either.
    if (scope.status.isDraft) {
      return const PurchaseRequestAccess.denied(
        PurchaseRequestAccessDenialReason.documentStatus,
      );
    }
    return const PurchaseRequestAccess.granted();
  }

  /// Whether the document lookup behind [kind] must be pinned to the actor's
  /// branch.
  ///
  /// The route guard asks this instead of deciding for itself, so "which screens
  /// are branch-scoped" is stated once. Answering it wrongly in one place is
  /// precisely how an IDOR appears.
  static bool requiresBranchScope(PurchaseRequestRouteKind kind) =>
      _isBranchScreen(kind);

  static bool _isBranchScreen(PurchaseRequestRouteKind kind) => switch (kind) {
    PurchaseRequestRouteKind.branchList ||
    PurchaseRequestRouteKind.branchCreate ||
    PurchaseRequestRouteKind.branchDocument ||
    PurchaseRequestRouteKind.branchDraft => true,
    PurchaseRequestRouteKind.warehouseQueue ||
    PurchaseRequestRouteKind.warehouseDocument => false,
  };
}
