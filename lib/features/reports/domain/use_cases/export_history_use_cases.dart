import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/reporting_models.dart';
import '../repositories/reporting_repository.dart';
import '../services/report_access_policy.dart';

/// The Super Admin's audit trail (§42, §48).
///
/// ### Read-only, structurally
///
/// There is no update use case, no delete use case and no "regenerate" — the
/// repository offers none, the DAO offers none, and the table has no writer beyond
/// the insert [ExportReportUseCase] performs. An audit trail somebody can edit is
/// not one.
///
/// ### Only a Super Admin, and the check is here rather than only on the route
///
/// The route guard refuses `/reports/export-history` to everyone else, but a guard
/// is a first line: this stream is what a provider subscribes to, and a provider can
/// be read from anywhere. So the role is checked against a **re-read** actor before
/// the stream is opened, and a refusal emits an empty list rather than throwing —
/// a screen that is being torn down mid-session-switch should render nothing, not
/// an error (§43).
class WatchExportHistoryUseCase {
  const WatchExportHistoryUseCase({required this._reporting});

  final ReportingRepository _reporting;

  /// Every export ever recorded, newest first, filtered in Dart.
  ///
  /// [actor] is the **stored** row, resolved by the caller. A `null` or non-Super
  /// Admin actor yields an empty stream — never a partial list, which would tell
  /// the reader that rows exist without showing them.
  Stream<List<ExportLog>> call({
    required MasterUser? actor,
    ExportHistoryFilter filter = const ExportHistoryFilter(),
  }) {
    if (actor == null ||
        !actor.isActive ||
        !ReportAccessPolicy.canReadExportHistory(actor.role)) {
      return Stream<List<ExportLog>>.value(const <ExportLog>[]);
    }
    return _reporting.watchExportHistory().map(
      (logs) => applyFilter(logs, filter),
    );
  }

  /// One person's own exports — what a branch dashboard shows under *"ekspor
  /// terbaru"*.
  ///
  /// Scoped to the actor by id rather than by branch, so a Kepala Cabang sees what
  /// **they** exported and not what a colleague did. It needs no role check for
  /// that reason: the only rows it can ever return are the caller's own.
  ///
  /// A one-shot read rather than a stream: a dashboard card wants an answer, and a
  /// live subscription behind one would stay open on every screen that shows the
  /// home page (§49).
  Future<List<ExportLog>> own({
    required MasterUser? actor,
    int limit = 5,
  }) async {
    if (actor == null || !actor.isActive) return const <ExportLog>[];
    return _reporting.recentExportsOf(actor.id, limit: limit);
  }

  /// Every export, read once — the counters on the Super Admin dashboard.
  ///
  /// Refused for every other role exactly as [call] is, and for the same reason:
  /// *"14 ekspor hari ini"* is as revealing as the list itself.
  Future<List<ExportLog>> snapshot({
    required MasterUser? actor,
    ExportHistoryFilter filter = const ExportHistoryFilter(),
  }) async {
    if (actor == null ||
        !actor.isActive ||
        !ReportAccessPolicy.canReadExportHistory(actor.role)) {
      return const <ExportLog>[];
    }
    return applyFilter(await _reporting.listExportHistory(), filter);
  }

  /// Applies [filter] to an already-sorted list.
  ///
  /// In Dart rather than in SQL for the date, and that is deliberate: *"exported on
  /// 30 Jul"* means the **operational** day in GMT+8, and `created_at` is ISO-8601
  /// TEXT, so a SQL `LIKE '2026-07-30%'` would match the UTC day — which starts
  /// eight hours late and ends eight hours early (§15).
  ///
  /// Public so the audit screen's tests can assert the rules without a database.
  static List<ExportLog> applyFilter(
    List<ExportLog> logs,
    ExportHistoryFilter filter,
  ) {
    if (filter.isEmpty) return logs;
    final needle = filter.searchText?.trim().toLowerCase();
    return List.unmodifiable(
      logs.where((log) {
        if (filter.reportType != null && log.reportType != filter.reportType) {
          return false;
        }
        if (filter.format != null && log.format != filter.format) return false;
        if (filter.branchId != null && log.branchId != filter.branchId) {
          return false;
        }
        if (filter.exportedBy != null && log.exportedBy != filter.exportedBy) {
          return false;
        }
        if (filter.onOperationalDate != null &&
            !DateOnly.isSameDate(
              AppTimeZone.operationalDate(log.exportedAtUtc),
              filter.onOperationalDate!,
            )) {
          return false;
        }
        if (needle != null && needle.isNotEmpty) {
          final haystack = [
            log.fileName,
            log.reportType.label,
            log.format.label,
            log.scopeType.label,
            log.syncSummary,
          ].join(' ').toLowerCase();
          if (!haystack.contains(needle)) return false;
        }
        return true;
      }),
    );
  }
}

/// One audit row with every id resolved to a label (§48).
///
/// Labels come from the `historical…` lookups, so a log naming a branch that was
/// closed last year still says which branch it was — an audit row that degraded to a
/// UUID the moment master data was tidied would be an audit row nobody can read.
class GetExportLogDetailUseCase {
  const GetExportLogDetailUseCase({required this._reporting});

  final ReportingRepository _reporting;

  /// `null` when the log does not exist **or** the actor may not read the audit —
  /// deliberately the same answer, so an id typed into the address bar cannot
  /// confirm that an export happened (§43).
  Future<ExportLogDetail?> call({
    required MasterUser? actor,
    required String exportLogId,
  }) async {
    if (actor == null ||
        !actor.isActive ||
        !ReportAccessPolicy.canReadExportHistory(actor.role)) {
      return null;
    }
    return _reporting.getExportLogDetail(exportLogId);
  }

  /// Labels for a whole list, in one pass rather than N round trips.
  Future<List<ExportLogDetail>> resolveAll({
    required MasterUser? actor,
    required List<ExportLog> logs,
  }) async {
    if (actor == null || !actor.isActive) return const <ExportLogDetail>[];
    // The own-exports dashboard card resolves labels for the caller's own rows, so
    // this accepts any active actor and simply refuses to resolve rows that are
    // neither theirs nor readable by their role.
    final readable = ReportAccessPolicy.canReadExportHistory(actor.role)
        ? logs
        : logs.where((log) => log.exportedBy == actor.id).toList();
    if (readable.isEmpty) return const <ExportLogDetail>[];
    return _reporting.resolveExportLogDetails(readable);
  }
}

/// Whether [role] sees the audit entry point at all — asked by the dashboard so
/// it does not render a card that leads to a refusal.
bool canOpenExportHistory(UserRole? role) =>
    ReportAccessPolicy.canReadExportHistory(role);
