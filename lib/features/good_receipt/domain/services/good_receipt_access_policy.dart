import '../../../../core/enums/app_enums.dart';
import '../../../delivery/domain/models/delivery_models.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/good_receipt_models.dart';
import 'good_receipt_state_policy.dart';

/// Which Good Receipt screen is being asked for.
///
/// Named per screen rather than per URL so the rule reads as a permission question
/// ("may this person check this shipment in?") instead of a routing one.
enum GoodReceiptRouteKind {
  /// `/receipts` — the branch head's Penerimaan list.
  branchList,

  /// `/receipts/new/{deliveryOrderId}` — start checking one shipment in. Names a
  /// **Delivery Order**, not a receipt, because the receipt does not exist yet.
  branchCreate,

  /// `/receipts/{id}` — the checklist, or the posted result once it is final.
  branchDocument,

  /// `/warehouse/good-receipts` — posted receipts across every branch, read-only.
  warehouseList,

  /// `/warehouse/good-receipts/{id}` — one posted receipt, read-only.
  warehouseDocument,

  /// `/warehouse/good-receipt-discrepancies` — the selisih/retur queue.
  warehouseDiscrepancies,
}

/// Why a screen was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can be precise about which rule fired.
enum GoodReceiptAccessDenialReason {
  /// No session yet — still loading, or master data has not been seeded.
  noSession,

  /// The acting user's role does not reach this screen at all.
  role,

  /// The acting user holds a branch-scoped role but no branch.
  noBranch,

  /// The document belongs to another branch, or does not exist. These are
  /// deliberately the same answer.
  documentOutOfScope,

  /// The document exists but is not in a status this screen may show — a
  /// `checking` receipt is the branch's working checklist and the warehouse has no
  /// business reading it, and a shipment that is not `shipped` has nothing to
  /// receive.
  documentStatus,
}

/// The outcome of an access check.
class GoodReceiptAccess {
  const GoodReceiptAccess._(this.reason);

  const GoodReceiptAccess.granted() : reason = null;

  const GoodReceiptAccess.denied(GoodReceiptAccessDenialReason reason)
    : this._(reason);

  /// `null` when access was granted.
  final GoodReceiptAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// Who may read which Good Receipt screen (spec §3.1, G-G1, G-R2).
///
/// This is a **read** authorization rule, separate from the write guards in
/// `GoodReceiptGuards` for the reason the Delivery Order policy spells out: the
/// write guards are the last word, but by the time a write is refused a foreign
/// document has already been fetched, rendered and read. The rules here run first
/// and decide whether it is fetched at all.
///
/// The policy is a pure function of facts the caller already holds, so it can be
/// exercised without a database, a widget tree or a router — and so the route
/// guard, the providers and the repository queries all agree by construction rather
/// than by three similar-looking `if` statements.
///
/// ### Two scopes, and an asymmetry the shipment did not have
///
/// The branch screens are branch-scoped and may see **both** statuses: the
/// checklist in progress and the posted result are the same branch's work.
///
/// The warehouse screens are *not* branch-scoped — the central warehouse ships to
/// every branch and its selisih report spans all of them (spec §4.2) — but they are
/// restricted to `posted` receipts. That restriction is a rule rather than a
/// courtesy: a `checking` receipt is a branch head part way through a decision, and
/// showing the warehouse an intermediate state would raise a return for goods that
/// have not been refused yet.
///
/// ### Warehouse is read-only, structurally
///
/// [isWriteScreen] answers `false` for every warehouse kind, and there is no
/// warehouse kind that could answer otherwise: the create, decide and post routes
/// simply do not exist for them. Spec §3.1 marks *"Good Receipt (ceklis/tolak)"*
/// for `kepala_cabang` alone.
///
/// ### Perawat and Super Admin
///
/// Both refused. A nurse has no Good Receipt row in spec §3.1 at all. Super Admin
/// is granted master data, imports and reports — widening a workflow permission
/// because an account is powerful is exactly the quiet grant G-R4 (segregation of
/// duties) is about, so it is not done here. If the specification later says
/// otherwise, this is the one place that changes.
abstract final class GoodReceiptAccessPolicy {
  /// The receipt statuses a branch head may see: everything their branch has.
  static const Set<GoodReceiptStatus> branchVisibleStatuses = {
    GoodReceiptStatus.checking,
    GoodReceiptStatus.posted,
  };

  /// The receipt statuses the warehouse may see. Posted only — see the class note.
  static const Set<GoodReceiptStatus> warehouseVisibleStatuses = {
    GoodReceiptStatus.posted,
  };

  /// Whether [user] may reach a screen that does not name a document.
  ///
  /// [user] is the *stored* user, not the session's claim about itself: the caller
  /// resolves it, so a tampered session cannot widen anything (O-8).
  static GoodReceiptAccess forSection({
    required MasterUser? user,
    required GoodReceiptRouteKind kind,
  }) {
    if (user == null) {
      return const GoodReceiptAccess.denied(
        GoodReceiptAccessDenialReason.noSession,
      );
    }
    if (!user.isActive) {
      return const GoodReceiptAccess.denied(GoodReceiptAccessDenialReason.role);
    }

    final isBranchScreen = _isBranchScreen(kind);
    final allowedRole = isBranchScreen
        ? UserRole.kepalaCabang
        : UserRole.warehouse;

    if (user.role != allowedRole) {
      return const GoodReceiptAccess.denied(GoodReceiptAccessDenialReason.role);
    }
    // Only the branch screens need a branch. The warehouse deliberately has none
    // (`users.branch_id` is NULL for it), and demanding one here would lock the
    // central warehouse out of its own selisih queue.
    if (isBranchScreen && user.branchId == null) {
      return const GoodReceiptAccess.denied(
        GoodReceiptAccessDenialReason.noBranch,
      );
    }
    return const GoodReceiptAccess.granted();
  }

  /// Whether [user] may open one specific receipt.
  ///
  /// [scope] is `null` when the id resolves to nothing *within the scope the lookup
  /// used* — which, on a branch screen, covers "no such receipt" and "somebody
  /// else's branch", and on a warehouse screen also "not posted yet", because the
  /// lookup that produced it carried all of those predicates and can therefore not
  /// tell them apart. That is the intended design, not a limitation: distinguishing
  /// them would let anyone with the app work out which document ids are real.
  static GoodReceiptAccess forDocument({
    required MasterUser? user,
    required GoodReceiptRouteKind kind,
    required GoodReceiptAccessScope? scope,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null) {
      return const GoodReceiptAccess.denied(
        GoodReceiptAccessDenialReason.documentOutOfScope,
      );
    }

    if (_isBranchScreen(kind)) {
      // Belt and braces: the query was already scoped, and this catches a caller
      // that passed an unscoped lookup by mistake.
      if (scope.branchId != user!.branchId) {
        return const GoodReceiptAccess.denied(
          GoodReceiptAccessDenialReason.documentOutOfScope,
        );
      }
      if (!branchVisibleStatuses.contains(scope.status)) {
        return const GoodReceiptAccess.denied(
          GoodReceiptAccessDenialReason.documentStatus,
        );
      }
      return const GoodReceiptAccess.granted();
    }

    if (!warehouseVisibleStatuses.contains(scope.status)) {
      return const GoodReceiptAccess.denied(
        GoodReceiptAccessDenialReason.documentStatus,
      );
    }
    return const GoodReceiptAccess.granted();
  }

  /// Whether [user] may start a receipt for one specific **shipment**.
  ///
  /// The create route names a Delivery Order, so its lookup is the shipment's
  /// access scope rather than a receipt's — and the extra predicate is G-G1's: the
  /// shipment must be `shipped`. A `preparing` one has not been handed over, and a
  /// `received` one already has a receipt.
  ///
  /// Whether a receipt *already exists* is deliberately not decided here: that is a
  /// second row's existence rather than an authorization fact, and the page answers
  /// it by resuming the checklist instead of refusing the route.
  static GoodReceiptAccess forDeliveryOrder({
    required MasterUser? user,
    required GoodReceiptRouteKind kind,
    required DeliveryOrderAccessScope? scope,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null) {
      return const GoodReceiptAccess.denied(
        GoodReceiptAccessDenialReason.documentOutOfScope,
      );
    }
    if (scope.branchId != user!.branchId) {
      return const GoodReceiptAccess.denied(
        GoodReceiptAccessDenialReason.documentOutOfScope,
      );
    }
    if (!GoodReceiptStatePolicy.canCreateFrom(scope.status)) {
      return const GoodReceiptAccess.denied(
        GoodReceiptAccessDenialReason.documentStatus,
      );
    }
    return const GoodReceiptAccess.granted();
  }

  /// Whether the document lookup behind [kind] must be pinned to the actor's
  /// branch.
  ///
  /// The route guard asks this instead of deciding for itself, so "which screens are
  /// branch-scoped" is stated once. Answering it wrongly in one place is precisely
  /// how an IDOR appears.
  static bool requiresBranchScope(GoodReceiptRouteKind kind) =>
      _isBranchScreen(kind);

  /// The receipt statuses the lookup behind [kind] may return.
  static Set<GoodReceiptStatus> visibleStatuses(GoodReceiptRouteKind kind) =>
      _isBranchScreen(kind) ? branchVisibleStatuses : warehouseVisibleStatuses;

  /// The shipment statuses the create route's lookup may return (G-G1).
  static Set<DeliveryOrderStatus> visibleDeliveryOrderStatuses(
    GoodReceiptRouteKind kind,
  ) => kind == GoodReceiptRouteKind.branchCreate
      ? GoodReceiptStatePolicy.eligibleDeliveryOrderStatuses
      : const <DeliveryOrderStatus>{};

  /// Whether [kind] is a screen that may change something.
  ///
  /// Asked by the UI so a read-only screen never renders an action, and by the tests
  /// so "the warehouse view has no write affordance" is an assertion rather than an
  /// inspection. Every warehouse kind answers `false`, and none can answer
  /// otherwise.
  static bool isWriteScreen(GoodReceiptRouteKind kind) =>
      kind == GoodReceiptRouteKind.branchCreate ||
      kind == GoodReceiptRouteKind.branchDocument;

  static bool _isBranchScreen(GoodReceiptRouteKind kind) => switch (kind) {
    GoodReceiptRouteKind.branchList ||
    GoodReceiptRouteKind.branchCreate ||
    GoodReceiptRouteKind.branchDocument => true,
    GoodReceiptRouteKind.warehouseList ||
    GoodReceiptRouteKind.warehouseDocument ||
    GoodReceiptRouteKind.warehouseDiscrepancies => false,
  };
}
