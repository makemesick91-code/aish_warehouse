/// Wiring and screen state for the reporting module.
///
/// ### Nothing here is an enforcement point
///
/// The dropdowns below are filtered by [ReportAccessPolicy], and the preview and
/// export use cases apply the *same* policy against an actor they re-read from the
/// database. That duplication is deliberate: the filtering makes the screen honest,
/// and the re-check makes it irrelevant whether the screen was honest (§16). A
/// request assembled outside the UI is refused by the same rule that shaped the UI.
///
/// ### Everything the screen owns is `autoDispose`
///
/// A report is a question somebody asked once. Keeping the answer cached past the
/// screen would mean a preview built under one session surviving into the next — a
/// stale cache entry is the one way a correct scope still leaks (§44). The draft,
/// the preview, the export controller and the search results all dispose with the
/// route.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../data/exporters/excel_report_exporter.dart';
import '../../data/exporters/pdf_report_exporter.dart';
import '../../data/files/local_report_file_store.dart';
import '../../data/files/share_plus_report_share_gateway.dart';
import '../../data/repositories/drift_reporting_repository.dart';
import '../../domain/gateways/report_gateways.dart';
import '../../domain/models/reporting_models.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../domain/services/report_access_policy.dart';
import '../../domain/services/report_filter_policy.dart';
import '../../domain/services/report_period_policy.dart';
import '../../domain/use_cases/build_report_preview_use_case.dart';
import '../../domain/use_cases/export_history_use_cases.dart';
import '../../domain/use_cases/export_report_use_case.dart';

// --- clock ------------------------------------------------------------------

/// The UTC clock the whole module reads "now" from.
///
/// A provider rather than a bare `DateTime.now()` because the cutoff decides which
/// movements a report counts, which batches read as expired, and what
/// `export_logs.data_cutoff_at` claims the data is as of. Overriding this one value
/// moves the preview, the export and the audit row together (T-7).
final reportClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

// --- wiring -----------------------------------------------------------------

final reportingRepositoryProvider = Provider<ReportingRepository>(
  (ref) => DriftReportingRepository(ref.watch(reportingDaoProvider)),
);

final reportExcelExporterProvider = Provider<ReportExcelExporter>(
  (ref) => const ExcelReportExporter(),
);

final reportPdfExporterProvider = Provider<ReportPdfExporter>(
  (ref) => const PdfReportExporter(),
);

final reportFileStoreProvider = Provider<ReportFileStore>(
  (ref) => const LocalReportFileStore(),
);

final reportShareGatewayProvider = Provider<ReportShareGateway>(
  (ref) => const SharePlusReportShareGateway(),
);

final buildReportPreviewUseCaseProvider = Provider<BuildReportPreviewUseCase>(
  (ref) => BuildReportPreviewUseCase(
    reporting: ref.watch(reportingRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(reportClockProvider),
  ),
);

final exportReportUseCaseProvider = Provider<ExportReportUseCase>(
  (ref) => ExportReportUseCase(
    reporting: ref.watch(reportingRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    excelExporter: ref.watch(reportExcelExporterProvider),
    pdfExporter: ref.watch(reportPdfExporterProvider),
    fileStore: ref.watch(reportFileStoreProvider),
    shareGateway: ref.watch(reportShareGatewayProvider),
    clock: ref.watch(reportClockProvider),
  ),
);

final watchExportHistoryUseCaseProvider = Provider<WatchExportHistoryUseCase>(
  (ref) => WatchExportHistoryUseCase(
    reporting: ref.watch(reportingRepositoryProvider),
  ),
);

final getExportLogDetailUseCaseProvider = Provider<GetExportLogDetailUseCase>(
  (ref) => GetExportLogDetailUseCase(
    reporting: ref.watch(reportingRepositoryProvider),
  ),
);

// --- what this actor may ask for --------------------------------------------

/// Report types the acting user may run, in menu order.
///
/// Empty while the session loads or when the role reaches nothing. Unauthorized
/// entries are **absent**, never disabled: a greyed-out *Rekap Distribusi* tells a
/// nurse that such a report exists and that somebody else can run it (§45).
final allowedReportTypesProvider = Provider.autoDispose<List<ReportType>>((
  ref,
) {
  final role = ref.watch(actingRoleProvider);
  final allowed = ReportAccessPolicy.allowedReportTypes(role);
  return [
    for (final type in ReportType.values)
      if (allowed.contains(type)) type,
  ];
});

/// Scopes the acting user may run [reportType] at.
final allowedReportScopesProvider = Provider.autoDispose
    .family<List<ReportScopeType>, ReportType>((ref, reportType) {
      final role = ref.watch(actingRoleProvider);
      final allowed = ReportAccessPolicy.allowedScopesFor(
        role: role,
        reportType: reportType,
      );
      return [
        for (final scope in ReportScopeType.values)
          if (allowed.contains(scope)) scope,
      ];
    });

/// The stock locations offered for one scope.
///
/// Filtered by **type and branch**, from the acting user's own branch for a
/// branch-scoped role. Archived locations are excluded here — this list is for
/// choosing new work, and `activeRoomLocation`-style reads are the pattern the rest
/// of the application already follows for that distinction (§7.4). A report *over* an
/// archived location is still produced correctly; it simply is not offered as a new
/// choice.
final reportLocationOptionsProvider = FutureProvider.autoDispose
    .family<List<MasterLocation>, ReportScopeType>((ref, scopeType) async {
      final user = await ref.watch(actingUserProvider.future);
      final requiredType = scopeType.requiredLocationType;
      if (user == null || requiredType == null) return const <MasterLocation>[];

      final all = await ref
          .watch(masterDataRepositoryProvider)
          .stockLocations();
      final ownBranchOnly = ReportAccessPolicy.requiresOwnBranch(user.role);
      return [
        for (final location in all)
          if (!location.isArchived &&
              location.type == requiredType &&
              (!ownBranchOnly || location.branchId == user.branchId))
            location,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });

/// Branches offered as a *filter* on a cross-branch recap.
///
/// Only for the two unscoped roles. A branch-scoped role has exactly one branch and
/// it is already enforced, so offering the control would imply there is a choice.
final reportBranchOptionsProvider =
    FutureProvider.autoDispose<List<MasterBranch>>((ref) async {
      final role = ref.watch(actingRoleProvider);
      if (role != UserRole.warehouse && role != UserRole.superAdmin) {
        return const <MasterBranch>[];
      }
      return ref.watch(masterDataRepositoryProvider).activeBranches();
    });

final reportCategoryOptionsProvider =
    FutureProvider.autoDispose<List<MasterCategory>>(
      (ref) => ref.watch(masterDataRepositoryProvider).categories(),
    );

// --- the draft the screen edits ---------------------------------------------

/// The filter form's state.
///
/// A notifier rather than a pile of separate providers, because the fields
/// constrain one another: changing the report type can invalidate the scope, and
/// changing the scope invalidates the location. Keeping them in one object is what
/// lets [ReportDraftController] re-establish those invariants in one place instead
/// of leaving each setter to remember.
class ReportDraftController extends Notifier<ReportRequestDraft> {
  @override
  ReportRequestDraft build() {
    // Rebuilds on session change, so switching user never leaves the previous
    // actor's report type and location on screen.
    ref.watch(currentSessionValueProvider);
    final role = ref.watch(actingRoleProvider);
    final today = AppTimeZone.operationalDate(ref.watch(reportClockProvider)());
    final reportType =
        ReportAccessPolicy.allowedReportTypes(role).firstOrNull ??
        ReportType.stokLokasi;
    return ReportRequestDraft(
      reportType: reportType,
      scopeType: _defaultScopeFor(role: role, reportType: reportType),
      periodStart: today,
      periodEnd: today,
    );
  }

  static ReportScopeType _defaultScopeFor({
    required UserRole? role,
    required ReportType reportType,
  }) =>
      ReportAccessPolicy.allowedScopesFor(
        role: role,
        reportType: reportType,
      ).firstOrNull ??
      ReportScopeType.room;

  /// Switching report type re-establishes every invariant it can break: the scope
  /// may no longer be legal, the location may no longer fit the scope, and an item
  /// filter is meaningless on a recap.
  void setReportType(ReportType reportType) {
    final role = ref.read(actingRoleProvider);
    final scope = ReportAccessPolicy.allowedScopesFor(
      role: role,
      reportType: reportType,
    );
    final nextScope = scope.contains(state.scopeType)
        ? state.scopeType
        : (scope.firstOrNull ?? state.scopeType);
    state = state.copyWith(
      reportType: reportType,
      scopeType: nextScope,
      clearLocation: !nextScope.requiresLocation,
      filter: ReportFilterPolicy.supportsItemFilter(reportType)
          ? state.filter
          : state.filter.copyWith(clearItem: true),
    );
  }

  void setScopeType(ReportScopeType scopeType) => state = state.copyWith(
    scopeType: scopeType,
    clearLocation: !scopeType.requiresLocation,
  );

  void setLocation(String? locationId) => state = locationId == null
      ? state.copyWith(clearLocation: true)
      : state.copyWith(locationId: locationId);

  void setBranch(String? branchId) => state = branchId == null
      ? state.copyWith(clearBranch: true)
      : state.copyWith(branchId: branchId);

  void setCategory(String? categoryId) => state = state.copyWith(
    filter: categoryId == null
        ? state.filter.copyWith(clearCategory: true)
        : state.filter.copyWith(categoryId: categoryId),
  );

  void setItem(String? itemId) => state = state.copyWith(
    filter: itemId == null
        ? state.filter.copyWith(clearItem: true)
        : state.filter.copyWith(itemId: itemId),
  );

  void setSearchText(String? text) => state = state.copyWith(
    filter: (text == null || text.trim().isEmpty)
        ? state.filter.copyWith(clearSearch: true)
        : state.filter.copyWith(searchText: text),
  );

  void toggleStatus(String status) {
    final statuses = Set<String>.from(state.filter.statuses);
    if (!statuses.remove(status)) statuses.add(status);
    state = state.copyWith(filter: state.filter.copyWith(statuses: statuses));
  }

  void setDiscrepancy(GoodReceiptDiscrepancyFilter discrepancy) => state = state
      .copyWith(filter: state.filter.copyWith(discrepancy: discrepancy));

  /// An as-of report has one date; a range report has two. The normalisation is
  /// [ReportPeriodPolicy]'s, and this only keeps the form from offering a start
  /// date on a report that has none.
  void setPeriod({DateTime? start, DateTime? end}) {
    final nextEnd = end ?? state.periodEnd;
    final nextStart = state.reportType.isAsOfReport
        ? nextEnd
        : (start ?? state.periodStart);
    state = state.copyWith(periodStart: nextStart, periodEnd: nextEnd);
  }
}

final reportDraftProvider =
    NotifierProvider.autoDispose<ReportDraftController, ReportRequestDraft>(
      ReportDraftController.new,
    );

// --- item search -------------------------------------------------------------

/// Typeahead over items, for the Kartu Stok picker (§4.3).
///
/// Debounced by ~200 ms and capped at 8 results, exactly as the specification's
/// SearchableDropdown behaviour describes. The debounce is a `Timer` on the
/// provider's own lifetime rather than a widget's, so a rebuild mid-typing does not
/// fire a query the user has already superseded.
final reportItemSearchProvider = FutureProvider.autoDispose
    .family<List<MasterItem>, String>((ref, query) async {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return const <MasterItem>[];

      final completer = Completer<void>();
      final timer = Timer(searchDebounce, completer.complete);
      ref.onDispose(() {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;

      final categoryId = ref.watch(reportDraftProvider).filter.categoryId;
      return ref
          .watch(masterDataRepositoryProvider)
          .searchItems(
            trimmed,
            categoryId: categoryId,
            limit: maxSearchResults,
          );
    });

/// §4.3: *"debounce ±200 ms"*.
const Duration searchDebounce = Duration(milliseconds: 200);

/// §4.3: *"maksimal ±8 hasil dengan scroll"*.
const int maxSearchResults = 8;

// --- preview -----------------------------------------------------------------

/// The report currently on screen.
///
/// Watches the draft **and** the session, so it is rebuilt when the report type,
/// scope, location, period, category, item or acting user changes (§44) — and
/// `autoDispose`, so it is not still cached under the next session.
final reportPreviewProvider = FutureProvider.autoDispose<ReportPreview?>((
  ref,
) async {
  final session = ref.watch(currentSessionValueProvider);
  if (session == null) return null;
  final draft = ref.watch(reportDraftProvider);
  if (!_isDraftReady(draft)) return null;

  return ref
      .watch(buildReportPreviewUseCaseProvider)
      .call(actorUserId: session.userId, draft: draft);
});

/// Whether the form holds enough to ask a question at all.
///
/// A cheap, purely structural check — the real validation is
/// [ReportFilterPolicy]'s and runs against the database. This only stops the screen
/// firing a query it knows will be refused, which is what keeps the *Tampilkan
/// Preview* button honest rather than a source of error banners while typing.
bool _isDraftReady(ReportRequestDraft draft) {
  if (draft.scopeType.requiresLocation && draft.locationId == null) {
    return false;
  }
  if (draft.reportType.requiresItem && draft.filter.itemId == null) {
    return false;
  }
  if (draft.periodStart.isAfter(draft.periodEnd)) return false;
  return true;
}

/// Public form of [_isDraftReady] — what enables the export buttons (§47).
bool isReportDraftReady(ReportRequestDraft draft) => _isDraftReady(draft);

// --- export ------------------------------------------------------------------

/// The outcome of the last export, or `null` before the first one.
class ReportExportState {
  const ReportExportState({
    this.isExporting = false,
    this.artifact,
    this.errorMessage,
  });

  /// Both buttons are disabled while this is true (§47) — a second tap during an
  /// export would produce a second file and a second audit row for one intention.
  final bool isExporting;

  final GeneratedReportArtifact? artifact;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

/// Runs an export and reports what happened.
///
/// It never decides anything: the ordering, the failure behaviour and the audit
/// row are all [ExportReportUseCase]'s (§36). This turns the outcome into
/// something a screen can render, and holds the *is one running* flag the buttons
/// read.
class ReportExportController extends Notifier<ReportExportState> {
  @override
  ReportExportState build() {
    ref.watch(currentSessionValueProvider);
    return const ReportExportState();
  }

  Future<void> export(ReportFormat format) async {
    if (state.isExporting) return;
    final session = ref.read(currentSessionValueProvider);
    if (session == null) return;
    final draft = ref.read(reportDraftProvider);

    state = const ReportExportState(isExporting: true);
    try {
      final artifact = await ref
          .read(exportReportUseCaseProvider)
          .call(actorUserId: session.userId, draft: draft, format: format);
      state = ReportExportState(artifact: artifact);
      // The audit list is a stream, so it refreshes itself — but the *own exports*
      // dashboard card is a one-shot read, and this is what makes it current.
      ref
        ..invalidate(recentOwnExportsProvider)
        ..invalidate(_exportHistorySnapshotProvider);
    } catch (error) {
      state = ReportExportState(errorMessage: describeReportFailure(error));
    }
  }

  void clearMessage() => state = ReportExportState(artifact: state.artifact);
}

final reportExportControllerProvider =
    NotifierProvider.autoDispose<ReportExportController, ReportExportState>(
      ReportExportController.new,
    );

/// One Indonesian sentence for any failure, with no path and no stack trace (§52).
///
/// A thin alias over [describeFailure], which already turns an `AppFailure` into its
/// own Indonesian message and everything else into one generic sentence. It exists so
/// a reporting screen imports one reporting symbol rather than reaching across into
/// `core/errors` for a presentation concern it shares with every other module.
String describeReportFailure(Object error) => describeFailure(error);

// --- export history ----------------------------------------------------------

final exportHistoryFilterProvider =
    NotifierProvider.autoDispose<
      ExportHistoryFilterController,
      ExportHistoryFilter
    >(ExportHistoryFilterController.new);

class ExportHistoryFilterController extends Notifier<ExportHistoryFilter> {
  @override
  ExportHistoryFilter build() {
    ref.watch(currentSessionValueProvider);
    return const ExportHistoryFilter();
  }

  void setReportType(ReportType? value) => state = value == null
      ? state.copyWith(clearReportType: true)
      : state.copyWith(reportType: value);

  void setFormat(ReportFormat? value) => state = value == null
      ? state.copyWith(clearFormat: true)
      : state.copyWith(format: value);

  void setBranch(String? value) => state = value == null
      ? state.copyWith(clearBranch: true)
      : state.copyWith(branchId: value);

  void setDate(DateTime? value) => state = value == null
      ? state.copyWith(clearDate: true)
      : state.copyWith(onOperationalDate: value);

  void setSearchText(String? value) =>
      state = (value == null || value.trim().isEmpty)
      ? state.copyWith(clearSearch: true)
      : state.copyWith(searchText: value);
}

/// The Super Admin's audit trail, newest first.
///
/// Emits an empty list for every other role — the use case decides that against a
/// re-read actor, so the route guard is not the only thing standing between an
/// account and this stream (§43).
final exportHistoryProvider = StreamProvider.autoDispose<List<ExportLog>>((
  ref,
) async* {
  final actor = await ref.watch(actingUserProvider.future);
  final filter = ref.watch(exportHistoryFilterProvider);
  yield* ref
      .watch(watchExportHistoryUseCaseProvider)
      .call(actor: actor, filter: filter);
});

/// The same rows with every id resolved to a label.
final exportHistoryDetailsProvider =
    FutureProvider.autoDispose<List<ExportLogDetail>>((ref) async {
      final actor = await ref.watch(actingUserProvider.future);
      final logs = await ref.watch(exportHistoryProvider.future);
      return ref
          .watch(getExportLogDetailUseCaseProvider)
          .resolveAll(actor: actor, logs: logs);
    });

/// The acting user's own recent exports — the branch dashboard card (§49).
///
/// A one-shot read. The audit *page* watches a live stream because it is the
/// screen somebody opens to look at the trail; a dashboard card is glanced at, and
/// a subscription behind it would be open on every screen that shows the home page.
final recentOwnExportsProvider = FutureProvider.autoDispose<List<ExportLog>>((
  ref,
) async {
  final actor = await ref.watch(actingUserProvider.future);
  return ref.watch(watchExportHistoryUseCaseProvider).own(actor: actor);
});

/// How many exports were recorded **today**, in operational time (§49).
///
/// GMT+8 rather than the device's day, and rather than SQL's — `created_at` is
/// ISO-8601 TEXT, so a `LIKE '2026-07-30%'` would count the UTC day, which starts
/// eight hours late (§15).
final exportsTodayCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final logs = await ref.watch(_exportHistorySnapshotProvider.future);
  final today = AppTimeZone.operationalDate(ref.watch(reportClockProvider)());
  return logs
      .where(
        (log) => DateOnly.isSameDate(
          AppTimeZone.operationalDate(log.exportedAtUtc),
          today,
        ),
      )
      .length;
});

/// The audit trail read **once**, for the dashboard counters.
///
/// Separate from [exportHistoryProvider] on purpose: that one is a live stream for
/// the screen that shows the trail, and a card that only needs two numbers should
/// not hold a subscription open behind it.
final _exportHistorySnapshotProvider =
    FutureProvider.autoDispose<List<ExportLog>>((ref) async {
      final actor = await ref.watch(actingUserProvider.future);
      return ref
          .watch(watchExportHistoryUseCaseProvider)
          .snapshot(actor: actor);
    });

/// Exports whose audit row has not reached the server yet (§49).
final pendingExportCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final logs = await ref.watch(_exportHistorySnapshotProvider.future);
  return logs.where((log) => log.syncStatus != SyncStatus.synced).length;
});
