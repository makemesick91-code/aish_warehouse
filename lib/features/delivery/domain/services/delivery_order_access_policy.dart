import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/delivery_models.dart';

/// Which Delivery Order screen is being asked for.
///
/// Named per screen rather than per URL so the rule reads as a permission
/// question ("may this person ship this document?") instead of a routing one.
enum DeliveryRouteKind {
  /// `/warehouse/delivery-orders` — the warehouse's list, across every branch.
  warehouseList,

  /// `/warehouse/delivery-orders/new/{prId}` — raise a shipment from a request.
  warehouseCreate,

  /// `/warehouse/delivery-orders/{id}` — read-only detail, any status.
  warehouseDocument,

  /// `/warehouse/delivery-orders/{id}/edit` — the allocation editor.
  warehouseDraft,

  /// `/warehouse/delivery-orders/{id}/waybill` — the Surat Jalan, draft included.
  warehouseWaybill,

  /// `/deliveries` — the branch head's read-only list.
  branchList,

  /// `/deliveries/{id}` — read-only detail of one incoming shipment.
  branchDocument,

  /// `/deliveries/{id}/waybill` — the Surat Jalan of an incoming shipment.
  branchWaybill,
}

/// Why a screen was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can be precise about which rule fired.
enum DeliveryAccessDenialReason {
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
  /// `preparing` shipment has not been handed over, and a shipped one has nothing
  /// to edit.
  documentStatus,
}

/// The outcome of an access check.
class DeliveryAccess {
  const DeliveryAccess._(this.reason);

  const DeliveryAccess.granted() : reason = null;

  const DeliveryAccess.denied(DeliveryAccessDenialReason reason)
    : this._(reason);

  /// `null` when access was granted.
  final DeliveryAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// Who may read which Delivery Order screen (spec §3.1, G-R2, G-R3).
///
/// This is a **read** authorization rule, separate from the write guards in
/// `DeliveryOrderGuards` for the reason the Purchase Request policy spells out:
/// the write guards are the last word, but by the time a write is refused a
/// foreign document has already been fetched, rendered and read. The rules here
/// run first and decide whether it is fetched at all.
///
/// The policy is a pure function of facts the caller already holds, so it can be
/// exercised without a database, a widget tree or a router — and so the route
/// guard, the providers and the repository queries all agree by construction
/// rather than by three similar-looking `if` statements.
///
/// ### Two scopes, on purpose
///
/// The warehouse screens are **not** branch-scoped: the central warehouse ships to
/// every branch and its queue spans all of them (spec §4.2). The branch screens
/// are, and they carry a second predicate the warehouse ones do not need — a
/// status filter. A `preparing` document is the warehouse's working draft; the
/// branch it is addressed to has not been handed anything yet, so it is invisible
/// to them however the URL is typed. What a branch head may see is `shipped` and
/// `received`, which is also exactly the set Good Receipt will work from.
///
/// ### Perawat and Super Admin
///
/// Both refused. Spec §3.1 marks *"Proses PR & buat DO/Surat Jalan"* for
/// `warehouse` alone and gives a nurse no delivery row at all. Super Admin is
/// granted master data, imports and reports — widening a workflow permission
/// because an account is powerful is exactly the quiet grant G-R4 (segregation of
/// duties) is about, so it is not done here. If the specification later says
/// otherwise, this is the one place that changes.
abstract final class DeliveryOrderAccessPolicy {
  /// The statuses a branch head may see. Anything else is invisible to them.
  static const Set<DeliveryOrderStatus> branchVisibleStatuses = {
    DeliveryOrderStatus.shipped,
    DeliveryOrderStatus.received,
  };

  /// Whether [user] may reach a screen that does not name a document.
  ///
  /// [user] is the *stored* user, not the session's claim about itself: the caller
  /// resolves it, so a tampered session cannot widen anything (O-8).
  static DeliveryAccess forSection({
    required MasterUser? user,
    required DeliveryRouteKind kind,
  }) {
    if (user == null) {
      return const DeliveryAccess.denied(DeliveryAccessDenialReason.noSession);
    }
    if (!user.isActive) {
      return const DeliveryAccess.denied(DeliveryAccessDenialReason.role);
    }

    final isBranchScreen = _isBranchScreen(kind);
    final allowedRole = isBranchScreen
        ? UserRole.kepalaCabang
        : UserRole.warehouse;

    if (user.role != allowedRole) {
      return const DeliveryAccess.denied(DeliveryAccessDenialReason.role);
    }
    // Only the branch screens need a branch. The warehouse deliberately has none
    // (`users.branch_id` is NULL for it), and demanding one here would lock the
    // central warehouse out of its own list.
    if (isBranchScreen && user.branchId == null) {
      return const DeliveryAccess.denied(DeliveryAccessDenialReason.noBranch);
    }
    return const DeliveryAccess.granted();
  }

  /// Whether [user] may open one specific document.
  ///
  /// [scope] is `null` when the id resolves to nothing *within the scope the
  /// lookup used* — which, on a branch screen, covers "no such document",
  /// "somebody else's branch" **and** "not shipped yet", because the lookup that
  /// produced it carried all three predicates and can therefore not tell them
  /// apart. That is the intended design, not a limitation: distinguishing them
  /// would let anyone with the app work out which document ids are real.
  static DeliveryAccess forDocument({
    required MasterUser? user,
    required DeliveryRouteKind kind,
    required DeliveryOrderAccessScope? scope,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null) {
      return const DeliveryAccess.denied(
        DeliveryAccessDenialReason.documentOutOfScope,
      );
    }

    if (_isBranchScreen(kind)) {
      // Belt and braces: the query was already scoped, and this catches a caller
      // that passed an unscoped lookup by mistake.
      if (scope.branchId != user!.branchId) {
        return const DeliveryAccess.denied(
          DeliveryAccessDenialReason.documentOutOfScope,
        );
      }
      if (!branchVisibleStatuses.contains(scope.status)) {
        return const DeliveryAccess.denied(
          DeliveryAccessDenialReason.documentStatus,
        );
      }
      return const DeliveryAccess.granted();
    }

    // The editor additionally requires the document to still be editable: a
    // shipped document's allocations are what the ledger was posted from (G-S2).
    if (kind == DeliveryRouteKind.warehouseDraft && !scope.status.isEditable) {
      return const DeliveryAccess.denied(
        DeliveryAccessDenialReason.documentStatus,
      );
    }
    return const DeliveryAccess.granted();
  }

  /// Whether the document lookup behind [kind] must be pinned to the actor's
  /// branch.
  ///
  /// The route guard asks this instead of deciding for itself, so "which screens
  /// are branch-scoped" is stated once. Answering it wrongly in one place is
  /// precisely how an IDOR appears.
  static bool requiresBranchScope(DeliveryRouteKind kind) =>
      _isBranchScreen(kind);

  /// The statuses the lookup behind [kind] may return. Empty means "any".
  static Set<DeliveryOrderStatus> visibleStatuses(DeliveryRouteKind kind) =>
      _isBranchScreen(kind)
      ? branchVisibleStatuses
      : const <DeliveryOrderStatus>{};

  /// Whether [kind] is a screen that may change something.
  ///
  /// Asked by the UI so a read-only screen never renders an action, and by the
  /// tests so "the branch view has no write affordance" is an assertion rather
  /// than an inspection.
  static bool isWriteScreen(DeliveryRouteKind kind) =>
      kind == DeliveryRouteKind.warehouseCreate ||
      kind == DeliveryRouteKind.warehouseDraft;

  static bool _isBranchScreen(DeliveryRouteKind kind) => switch (kind) {
    DeliveryRouteKind.branchList ||
    DeliveryRouteKind.branchDocument ||
    DeliveryRouteKind.branchWaybill => true,
    DeliveryRouteKind.warehouseList ||
    DeliveryRouteKind.warehouseCreate ||
    DeliveryRouteKind.warehouseDocument ||
    DeliveryRouteKind.warehouseDraft ||
    DeliveryRouteKind.warehouseWaybill => false,
  };
}
