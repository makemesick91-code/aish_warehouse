import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/reporting_models.dart';

/// What a report's filters must satisfy before anything is read (§17).
///
/// ### Where this sits relative to [ReportAccessPolicy]
///
/// The access policy answers *"may this person ask this question?"*. This one
/// answers *"is the question well formed?"* — a Kartu Stok with no item, a
/// `branch_all` Kartu Stok, a category id that names nothing. The two are separate
/// because they fail differently: an access refusal must say as little as possible
/// (§52), while a malformed filter should say exactly what is wrong so the user can
/// fix it.
///
/// One consequence is deliberate and worth stating: **the access check runs first**.
/// A nurse asking for a Gudang Cabang gets "akses ditolak", not "lokasi bukan
/// ruangan" — the second sentence would confirm that the location exists and what
/// type it is.
///
/// ### Everything is revalidated, nothing is trusted
///
/// Each method takes the master rows **as the database currently has them**, resolved
/// by the caller. The UI already filtered its dropdowns through the same policy, and
/// that is exactly why these checks exist: a request can be assembled without the
/// UI, and the dropdown is a convenience rather than a boundary (§16).
abstract final class ReportFilterPolicy {
  /// Validates a request whose scope and master references have been resolved.
  ///
  /// Throws the specific failure for the first problem it finds. Ordered so the
  /// most structural question is asked first: a Kartu Stok at `branch_all` is
  /// wrong regardless of which item was chosen.
  static void validate({
    required ReportType reportType,
    required ReportScopeType scopeType,
    required ReportFilter filter,
    required String? locationId,
    MasterLocation? location,
    MasterCategory? category,
    MasterItem? item,
  }) {
    _validateScopeShape(reportType: reportType, scopeType: scopeType);
    _validateLocation(
      reportType: reportType,
      scopeType: scopeType,
      locationId: locationId,
      location: location,
    );
    _validateItem(reportType: reportType, filter: filter, item: item);
    _validateCategory(filter: filter, category: category);
  }

  /// Whether [reportType] can be run at [scopeType] at all, ignoring who is
  /// asking.
  ///
  /// Role-independent on purpose: the fact that a Kartu Stok needs one shelf is a
  /// property of the report, not of the person. [ReportAccessPolicy] narrows this
  /// further per role, and the two are intersected rather than one standing in for
  /// the other.
  static bool supportsScope({
    required ReportType reportType,
    required ReportScopeType scopeType,
  }) {
    if (reportType.requiresExactLocation) return scopeType.requiresLocation;
    if (reportType.isLedgerPrimary) {
      // Current stock and expiry describe shelves, so `cross_branch` — which is not
      // a place — is meaningless for them.
      return scopeType != ReportScopeType.crossBranch;
    }
    // A recap is filed by document, so pinning it to one shelf is meaningless —
    // with one exception that the access matrix forces.
    //
    // §16 gives a Perawat exactly one scope, `room`, and two recaps: their own
    // Stok Opname and their own Pemakaian. Refusing `room` for every recap made
    // both unreachable — [ReportAccessPolicy] offered them and this refused them,
    // so a nurse opening either got *"tidak dapat dijalankan pada cakupan
    // Ruangan"*. The two are allowed here, and the reads behind them are narrowed
    // to that room as well as to the actor's own documents, so the heading and the
    // rows agree.
    //
    // No other role is ever granted `room` for a recap — a Kepala Cabang's recap
    // scopes are `branch_all` alone — so this widens nothing: the access policy is
    // still the gate, and this only stops it contradicting itself.
    if (scopeType == ReportScopeType.room) {
      return reportType == ReportType.rekapOpname ||
          reportType == ReportType.rekapPemakaian;
    }
    return scopeType == ReportScopeType.branchAll ||
        scopeType == ReportScopeType.crossBranch ||
        scopeType == ReportScopeType.allLocations;
  }

  static void _validateScopeShape({
    required ReportType reportType,
    required ReportScopeType scopeType,
  }) {
    if (supportsScope(reportType: reportType, scopeType: scopeType)) return;
    throw InvalidReportScopeFailure(
      reportType.requiresExactLocation
          ? '${reportType.label} membutuhkan tepat satu lokasi.'
          : '${reportType.label} tidak dapat dijalankan pada cakupan '
                '${scopeType.label}.',
      reportType: reportType,
      scopeType: scopeType,
    );
  }

  static void _validateLocation({
    required ReportType reportType,
    required ReportScopeType scopeType,
    required String? locationId,
    required MasterLocation? location,
  }) {
    if (!scopeType.requiresLocation) return;
    if (locationId == null) {
      throw ReportLocationRequiredFailure(
        'Pilih lokasi terlebih dahulu.',
        reportType: reportType,
        scopeType: scopeType,
      );
    }
    if (location == null) {
      throw ReportLocationNotFoundFailure(
        'Lokasi tidak ditemukan.',
        locationId: locationId,
      );
    }
    if (location.type != scopeType.requiredLocationType) {
      // Reached only when the access policy already granted the scope, i.e. the
      // actor may see this location — so naming the mismatch leaks nothing.
      throw ReportLocationAccessDeniedFailure(
        'Lokasi yang dipilih bukan ${scopeType.label}.',
        locationId: locationId,
      );
    }
  }

  static void _validateItem({
    required ReportType reportType,
    required ReportFilter filter,
    required MasterItem? item,
  }) {
    if (reportType.requiresItem && filter.itemId == null) {
      throw ReportItemRequiredFailure(
        '${reportType.label} membutuhkan satu barang.',
        reportType: reportType,
      );
    }
    if (filter.itemId != null && item == null) {
      throw ReportItemNotFoundFailure(
        'Barang tidak ditemukan.',
        itemId: filter.itemId!,
      );
    }
  }

  static void _validateCategory({
    required ReportFilter filter,
    required MasterCategory? category,
  }) {
    if (filter.categoryId != null && category == null) {
      throw ReportCategoryNotFoundFailure(
        'Kategori tidak ditemukan.',
        categoryId: filter.categoryId!,
      );
    }
  }

  /// Whether [reportType] offers a document-status filter, and which values.
  ///
  /// Returned as `dbValue` strings so the filter object stays independent of eight
  /// different status enums — the recap builders compare against the same strings
  /// their rows carry.
  static List<({String value, String label})> statusOptionsFor(
    ReportType reportType,
  ) => switch (reportType) {
    ReportType.rekapOpname => [
      for (final status in StockOpnameStatus.values)
        (value: status.dbValue, label: status.label),
    ],
    ReportType.rekapPr => [
      for (final status in PurchaseRequestStatus.values)
        (value: status.dbValue, label: status.label),
    ],
    ReportType.rekapDo => [
      for (final status in DeliveryOrderStatus.values)
        (value: status.dbValue, label: status.label),
    ],
    ReportType.rekapGr => [
      for (final status in GoodReceiptStatus.values)
        (value: status.dbValue, label: status.label),
    ],
    ReportType.rekapDistribusi => [
      for (final status in DistributionStatus.values)
        (value: status.dbValue, label: status.label),
    ],
    ReportType.rekapPemakaian => [
      for (final status in ConsumptionStatus.values)
        (value: status.dbValue, label: status.label),
    ],
    ReportType.rekapPemusnahan => [
      for (final status in DisposalStatus.values)
        (value: status.dbValue, label: status.label),
    ],
    ReportType.rekapRetur => [
      for (final status in GoodsReturnStatus.values)
        (value: status.dbValue, label: status.label),
    ],
    // The three ledger reports describe positions, not documents. A status filter
    // on them would be filtering shelves by a property shelves do not have.
    ReportType.stokLokasi ||
    ReportType.kartuStok ||
    ReportType.kadaluarsa => const [],
  };

  /// Whether the report offers the discrepancy lens (§27).
  static bool supportsDiscrepancyFilter(ReportType reportType) =>
      reportType == ReportType.rekapGr;

  /// Whether the report offers an item filter at all.
  ///
  /// Mandatory on a Kartu Stok, optional on the two other stock reports, and absent
  /// from the recaps — a recap is filed by document, and an item filter there would
  /// silently drop whole documents rather than narrow them.
  static bool supportsItemFilter(ReportType reportType) =>
      reportType.isLedgerPrimary;

  /// Whether the screen must ask an unscoped role **which branch**.
  ///
  /// True for `branch_all` and nothing else. `branch_all` is not a filter — it is a
  /// scope that names a branch, and [ReportAccessPolicy.forRequest] refuses one
  /// without it. `cross_branch` and `all_locations` name no branch at all, and
  /// offering a branch control on them would be offering a narrowing the audit row
  /// could not record: §12 pins both scopes to a NULL `branch_id`.
  ///
  /// A branch-scoped role is excluded because their branch is already enforced —
  /// showing them the control would imply there is another value to choose.
  static bool supportsBranchFilter({
    required UserRole? role,
    required ReportType reportType,
    required ReportScopeType scopeType,
  }) =>
      (role == UserRole.warehouse || role == UserRole.superAdmin) &&
      scopeType == ReportScopeType.branchAll;

  /// Whether the report offers free-text search (§17).
  static bool supportsSearchText(ReportType reportType) =>
      !reportType.isLedgerPrimary;

  /// Whether [haystack] matches [query], case-insensitively.
  ///
  /// An empty or whitespace-only query matches **everything**, and that is the safe
  /// direction: the alternative — treating blank as a wildcard that widens the
  /// scope — is not expressible here at all, because the scope was already applied
  /// in SQL before any of these rows existed. Search only ever removes rows.
  static bool matchesSearch(String? query, Iterable<String?> haystack) {
    final needle = query?.trim().toLowerCase();
    if (needle == null || needle.isEmpty) return true;
    for (final field in haystack) {
      if (field != null && field.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  /// Whether a document with [status] passes [filter].
  ///
  /// An empty status set means "every status" — see [ReportFilter.statuses].
  static bool matchesStatus(ReportFilter filter, String status) =>
      filter.statuses.isEmpty || filter.statuses.contains(status);
}
