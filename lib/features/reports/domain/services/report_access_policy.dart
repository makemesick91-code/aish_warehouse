import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/reporting_models.dart';

/// Which reporting screen is being asked for.
enum ReportRouteKind {
  /// `/reports` — the module itself. Every role reaches it; what they find inside
  /// differs entirely.
  reports,

  /// `/reports/export-history` — the audit trail. Super Admin only (§43).
  exportHistory,
}

/// Who may run which report, over which scope (G-L1).
///
/// ### One table, four roles, and nothing derived twice
///
/// G-L1 states the rule in one sentence — *"Perawat hanya ruangannya; Kepala Cabang
/// hanya gudang cabang + ruangan cabangnya; Warehouse hanya warehouse pusat + rekap
/// lintas cabang; Super Admin semua"* — and this class is that sentence, expanded
/// into three questions the rest of the module asks instead of deciding for itself:
/// [allowedReportTypes], [allowedScopesFor] and [forRequest]. The route guard, the
/// provider that fills the dropdowns, the preview use case and the export use case
/// all call the same three, so a scope the UI never offers is also a scope the
/// export refuses — which is what makes the dropdown a convenience rather than the
/// security boundary.
///
/// ### The Perawat interpretation, stated rather than assumed (§3.12)
///
/// G-R1 scopes a nurse to *"ruangan di cabangnya sendiri"*, and §4.2 gives them a
/// *Stok Ruangan* screen. The schema has no `user_room_assignment` table, so there
/// is no stored fact saying *which* rooms a given nurse works in. Two readings were
/// possible and one had to be chosen:
///
/// * refuse every room until such a table exists — which would ship a *Laporan* menu
///   entry that does nothing for the role the specification most explicitly gives
///   room reports to; or
/// * allow **any room of the actor's own branch**, which is exactly the reach every
///   existing nurse workflow already has: `CreateStockOpnameUseCase` and
///   `CreateConsumptionUseCase` both accept any room in the branch.
///
/// The second is chosen, and it is a *documented operational interpretation*, not a
/// rule the specification states. It grants a nurse no reach their existing write
/// paths do not already have. What it never grants is a Gudang Cabang, a Warehouse
/// Pusat, another branch, or any scope wider than one room.
///
/// Ownership is narrower still, and that part is not an interpretation: a nurse's
/// `rekap_opname` and `rekap_pemakaian` are scoped to documents **they created**,
/// because §14 already made a Pemakaian one nurse's record rather than the branch's.
///
/// ### Why Warehouse cannot read a room's current stock
///
/// [ReportType.supportsCrossBranch] is false for the three ledger-primary reports,
/// and that asymmetry is deliberate. A Petugas Warehouse reports on *documents*
/// across every branch — that is what *"rekap lintas cabang"* means — but *"hanya
/// warehouse pusat"* is the other half of the same sentence. A cross-branch current
/// stock report would hand them every room balance in the clinic group, which is the
/// Kepala Cabang's and the Super Admin's to see.
abstract final class ReportAccessPolicy {
  // --- report types ---------------------------------------------------------

  /// Every report a Perawat may run.
  ///
  /// The five that describe a room or the work done in one. Notably absent: PR, DO,
  /// GR, Distribusi, Retur and Pemusnahan — a nurse raises none of them and §3.1
  /// gives them no view of any.
  static const Set<ReportType> perawatReports = {
    ReportType.stokLokasi,
    ReportType.kartuStok,
    ReportType.rekapOpname,
    ReportType.rekapPemakaian,
    ReportType.kadaluarsa,
  };

  /// Every report a Kepala Cabang may run: all eleven, within their own branch.
  static const Set<ReportType> kepalaCabangReports = {
    ReportType.stokLokasi,
    ReportType.kartuStok,
    ReportType.rekapOpname,
    ReportType.rekapPr,
    ReportType.rekapDo,
    ReportType.rekapGr,
    ReportType.rekapDistribusi,
    ReportType.rekapPemakaian,
    ReportType.rekapPemusnahan,
    ReportType.rekapRetur,
    ReportType.kadaluarsa,
  };

  /// Every report a Petugas Warehouse may run — the same eleven, but see
  /// [allowedScopesFor]: the three stock reports are pinned to Warehouse Pusat and
  /// the eight recaps to cross-branch.
  static const Set<ReportType> warehouseReports = kepalaCabangReports;

  /// Super Admin: every report, at every scope.
  static const Set<ReportType> superAdminReports = kepalaCabangReports;

  static Set<ReportType> allowedReportTypes(UserRole? role) => switch (role) {
    UserRole.perawat => perawatReports,
    UserRole.kepalaCabang => kepalaCabangReports,
    UserRole.warehouse => warehouseReports,
    UserRole.superAdmin => superAdminReports,
    null => const <ReportType>{},
  };

  // --- scopes ---------------------------------------------------------------

  /// Which scopes [role] may run [reportType] at, in the order a picker should
  /// offer them.
  ///
  /// Returns an **empty set** when the role may not run the report at all, so a
  /// caller cannot accidentally treat "no scopes" as "any scope". Unauthorized
  /// scopes are never returned as disabled entries either — §45 says they must not
  /// appear in the list, because a greyed-out *Gudang Cabang CAB-02* tells a nurse
  /// that CAB-02 exists.
  static Set<ReportScopeType> allowedScopesFor({
    required UserRole? role,
    required ReportType reportType,
  }) {
    if (!allowedReportTypes(role).contains(reportType)) {
      return const <ReportScopeType>{};
    }
    return switch (role!) {
      // One room at a time, always — see the class note on the Perawat reading.
      UserRole.perawat => const {ReportScopeType.room},
      UserRole.kepalaCabang => _branchScopesFor(reportType),
      UserRole.warehouse => _warehouseScopesFor(reportType),
      UserRole.superAdmin => _superAdminScopesFor(reportType),
    };
  }

  static Set<ReportScopeType> _branchScopesFor(ReportType reportType) {
    if (reportType.requiresExactLocation) {
      // A Kartu Stok is one shelf (§17).
      return const {ReportScopeType.branchStore, ReportScopeType.room};
    }
    if (reportType.isLedgerPrimary) {
      return const {
        ReportScopeType.branchStore,
        ReportScopeType.room,
        ReportScopeType.branchAll,
      };
    }
    // A recap covers the branch's documents. `branch_all` is the scope that says
    // "this branch", and it is the only one offered: a recap pinned to one room
    // would be a location filter on a document set that is not filed by location.
    return const {ReportScopeType.branchAll};
  }

  static Set<ReportScopeType> _warehouseScopesFor(ReportType reportType) {
    if (reportType.isLedgerPrimary) return const {ReportScopeType.warehouse};
    // `branch_all` alongside `cross_branch` because §4.2 asks the Warehouse screen
    // for *"rekap PR/DO **per cabang** & per periode"* as well as the cross-branch
    // view. It is a narrowing of a scope they already have — never a widening —
    // and it is a *scope* rather than a filter so the audit row can record which
    // branch was exported: §12 pins `cross_branch` to a NULL `branch_id`, so a
    // branch narrowing expressed as a filter would vanish from the trail.
    return const {ReportScopeType.crossBranch, ReportScopeType.branchAll};
  }

  static Set<ReportScopeType> _superAdminScopesFor(ReportType reportType) {
    if (reportType.requiresExactLocation) {
      return const {
        ReportScopeType.warehouse,
        ReportScopeType.branchStore,
        ReportScopeType.room,
      };
    }
    if (reportType.isLedgerPrimary) {
      return const {
        ReportScopeType.warehouse,
        ReportScopeType.branchStore,
        ReportScopeType.room,
        ReportScopeType.branchAll,
        ReportScopeType.allLocations,
      };
    }
    return const {
      ReportScopeType.branchAll,
      ReportScopeType.crossBranch,
      ReportScopeType.allLocations,
    };
  }

  // --- ownership ------------------------------------------------------------

  /// Whether [role]'s view of [reportType] is limited to documents **they
  /// created**.
  ///
  /// True only for a Perawat's two document recaps. A nurse counting a room does
  /// not thereby get to read a colleague's count of the same room — the ownership
  /// scope §14 established for Pemakaian, applied to the report that lists them.
  static bool requiresOwnDocuments({
    required UserRole? role,
    required ReportType reportType,
  }) =>
      role == UserRole.perawat &&
      (reportType == ReportType.rekapOpname ||
          reportType == ReportType.rekapPemakaian);

  /// Whether the report must be pinned to the actor's own branch.
  ///
  /// True for Perawat and Kepala Cabang, false for the two unscoped roles — which
  /// is not a widening: a Warehouse account's *reach* is decided by
  /// [allowedScopesFor], and this only says "there is no single branch to pin to".
  static bool requiresOwnBranch(UserRole? role) =>
      role == UserRole.perawat || role == UserRole.kepalaCabang;

  /// Whether [role] may read the export audit at all (§43).
  static bool canReadExportHistory(UserRole? role) =>
      role == UserRole.superAdmin;

  // --- decisions ------------------------------------------------------------

  /// Whether [user] may reach a reporting screen that names no report yet.
  ///
  /// [user] is the *stored* row, re-read from the database by the caller, not the
  /// session's claim about itself — role, branch and `is_active` can all change
  /// under a session that is still open (O-8).
  static ReportAccessDecision forSection({
    required MasterUser? user,
    required ReportRouteKind kind,
  }) {
    if (user == null) {
      return const ReportAccessDecision.denied(
        ReportAccessDenialReason.noSession,
      );
    }
    if (!user.isActive) {
      return const ReportAccessDecision.denied(ReportAccessDenialReason.role);
    }
    if (kind == ReportRouteKind.exportHistory) {
      return canReadExportHistory(user.role)
          ? const ReportAccessDecision.granted()
          : const ReportAccessDecision.denied(ReportAccessDenialReason.role);
    }
    if (allowedReportTypes(user.role).isEmpty) {
      return const ReportAccessDecision.denied(ReportAccessDenialReason.role);
    }
    if (requiresOwnBranch(user.role) && user.branchId == null) {
      return const ReportAccessDecision.denied(
        ReportAccessDenialReason.noBranch,
      );
    }
    return const ReportAccessDecision.granted();
  }

  /// Whether [user] may run one specific request.
  ///
  /// [locationType] and [locationBranchId] describe the scope's location as the
  /// **database** currently has it, resolved by the caller. They are the belt to
  /// [allowedScopesFor]'s braces: a scope value can be right while the location id
  /// under it points at another branch's room, and a request assembled outside the
  /// UI is exactly the case that would carry one.
  ///
  /// Every refusal that could distinguish "does not exist" from "belongs to
  /// somebody else" collapses to [ReportAccessDenialReason.location] on purpose —
  /// telling them apart is how the filter form becomes a way to enumerate the
  /// clinic group's rooms.
  static ReportAccessDecision forRequest({
    required MasterUser? user,
    required ReportType reportType,
    required ReportScopeType scopeType,
    StockLocationType? locationType,
    String? locationBranchId,
    String? requestedBranchId,
  }) {
    final section = forSection(user: user, kind: ReportRouteKind.reports);
    if (section.isDenied) return section;

    if (!allowedReportTypes(user!.role).contains(reportType)) {
      return const ReportAccessDecision.denied(ReportAccessDenialReason.role);
    }
    if (!allowedScopesFor(
      role: user.role,
      reportType: reportType,
    ).contains(scopeType)) {
      return const ReportAccessDecision.denied(ReportAccessDenialReason.scope);
    }

    // The scope names a single location: it must exist, be of the type the scope
    // claims, and — for a branch-scoped role — belong to the actor's branch.
    if (scopeType.requiresLocation) {
      if (locationType == null) {
        return const ReportAccessDecision.denied(
          ReportAccessDenialReason.location,
        );
      }
      if (locationType != scopeType.requiredLocationType) {
        return const ReportAccessDecision.denied(
          ReportAccessDenialReason.location,
        );
      }
      if (requiresOwnBranch(user.role) && locationBranchId != user.branchId) {
        return const ReportAccessDecision.denied(
          ReportAccessDenialReason.location,
        );
      }
    }

    // `branch_all` names a branch and no location. A branch-scoped role may only
    // ever name their own.
    if (scopeType == ReportScopeType.branchAll) {
      if (requestedBranchId == null) {
        return const ReportAccessDecision.denied(
          ReportAccessDenialReason.scope,
        );
      }
      if (requiresOwnBranch(user.role) && requestedBranchId != user.branchId) {
        return const ReportAccessDecision.denied(
          ReportAccessDenialReason.location,
        );
      }
    }

    return const ReportAccessDecision.granted();
  }

  /// The branch a report's *data* must be pinned to, or `null` for a report that
  /// legitimately spans branches.
  ///
  /// This is what the repository turns into a SQL predicate, and it is asked of the
  /// policy rather than assembled by the caller so that "which reads are branch
  /// scoped" is stated exactly once. A Warehouse or Super Admin may still pass a
  /// branch as a *filter* — that is a narrowing of a scope they already have, and
  /// it arrives through the request rather than through here.
  static String? enforcedBranchIdFor({
    required MasterUser user,
    required ReportScopeType scopeType,
  }) {
    if (!requiresOwnBranch(user.role)) return null;
    if (scopeType == ReportScopeType.warehouse) return null;
    return user.branchId;
  }
}
