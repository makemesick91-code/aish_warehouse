import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../services/report_period_policy.dart';
import '../services/report_sync_snapshot_builder.dart';

/// Everything a builder needs that is **not** data: who is running the report,
/// when, and what the scope should be called.
///
/// It exists so eleven builders do not each resolve a branch code and a category
/// name for the header. The labels are resolved once by the use case — from
/// historical master rows, so a report over an archived room still names it — and
/// carried in; the builder only counts rows and folds the sync snapshot.
///
/// [generatedAtUtc] comes from an injected clock (T-7). It is the report's cutoff,
/// its *waktu cetak* and its `export_logs.data_cutoff_at`, all three from one value
/// — so a report cannot print one instant and be audited under another.
class ReportBuildContext {
  const ReportBuildContext({
    required this.request,
    required this.generatedAtUtc,
    required this.exportedByLabel,
    required this.scopeLabel,
    required this.locationLabel,
    required this.branchLabel,
    required this.categoryLabel,
    required this.itemLabel,
  });

  final ReportRequest request;
  final DateTime generatedAtUtc;
  final String exportedByLabel;
  final String scopeLabel;
  final String locationLabel;
  final String branchLabel;
  final String categoryLabel;
  final String itemLabel;

  ReportType get reportType => request.reportType;

  ReportScope get scope => request.scope;

  ReportPeriod get period => request.period;

  ReportFilter get filter => request.filter;

  /// The operational (GMT+8) date the report is *as of* — the last day of the
  /// period, whether or not the report is an as-of one.
  DateTime get asOfDate => period.periodEnd;

  ReportHeader header({
    required ReportSyncSnapshot syncSnapshot,
    required int rowCount,
  }) => ReportHeader(
    reportType: reportType,
    title: reportType.label,
    generatedAtUtc: generatedAtUtc,
    period: period,
    scopeLabel: scopeLabel,
    locationLabel: locationLabel,
    branchLabel: branchLabel,
    categoryLabel: categoryLabel,
    itemLabel: itemLabel,
    exportedByLabel: exportedByLabel,
    syncSnapshot: syncSnapshot,
    rowCount: rowCount,
  );

  /// `Per 30 Jul 2026 GMT+8` or `1 Jul 2026 – 30 Jul 2026 GMT+8`.
  String get periodLabel =>
      ReportPeriodPolicy.describe(period, isAsOf: reportType.isAsOfReport);
}

/// Shared row-level helpers every builder needs and none should re-derive.
abstract final class ReportBuilderSupport {
  /// The expiry verdict for one batch, as of an operational date.
  ///
  /// Canonical (§23): **expired when the operational date is past the expiry
  /// date** — a batch is usable *through* the last day printed on the package
  /// (G-E4/T-10), so `expiry == today` is not expired. *Segera kedaluwarsa* uses
  /// the item's own `expiry_alert_days`, which is the same threshold G-E6's badges
  /// and G-E4's shipment confirmation use; inventing a report-specific number here
  /// would make the report disagree with the screen it was printed from.
  static ReportExpiryStatus expiryStatusOf({
    required MasterItem? item,
    required DateTime? expiryDate,
    required DateTime operationalDate,
  }) {
    if (item == null || !item.hasExpiry || expiryDate == null) {
      return ReportExpiryStatus.notTracked;
    }
    if (DateOnly.isAfterDate(operationalDate, expiryDate)) {
      return ReportExpiryStatus.expired;
    }
    final remaining = DateOnly.daysBetween(operationalDate, expiryDate);
    return remaining <= item.expiryAlertDays
        ? ReportExpiryStatus.nearExpiry
        : ReportExpiryStatus.safe;
  }

  /// Whole operational days from [operationalDate] to [expiryDate]; negative once
  /// the date has passed.
  static int daysRemaining({
    required DateTime operationalDate,
    required DateTime expiryDate,
  }) => DateOnly.daysBetween(operationalDate, expiryDate);

  /// The operational date a UTC instant falls on. The one conversion every builder
  /// uses, so none of them reaches for `toLocal()`.
  static DateTime operationalDateOf(DateTime utc) =>
      AppTimeZone.operationalDate(utc);

  /// `30 Jul 2026, 22:15` in operational time, or `—`.
  static String dateTimeLabel(DateTime? utc) =>
      utc == null ? ReportLabels.notApplicable : _formatOperational(utc);

  /// `30 Jul 2026` for a civil date, printed with **no** conversion (T-9).
  static String civilDateLabel(DateTime? date) => date == null
      ? ReportLabels.notApplicable
      : '${date.day.toString().padLeft(2, '0')} '
            '${_monthsShort[date.month - 1]} ${date.year}';

  static String _formatOperational(DateTime utc) {
    final operational = AppTimeZone.utcToOperational(utc);
    final hour = operational.hour.toString().padLeft(2, '0');
    final minute = operational.minute.toString().padLeft(2, '0');
    return '${civilDateLabel(operational)}, $hour:$minute';
  }

  static const List<String> _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  /// The name a stock location should be shown under, resolved through its room or
  /// branch when it has one.
  static String locationLabel(ReportMasterData master, String? locationId) {
    final location = master.location(locationId);
    if (location == null) {
      return locationId == null
          ? ReportLabels.notApplicable
          : ReportLabels.historicalLocation;
    }
    return switch (location.type) {
      StockLocationType.warehouse => location.name,
      StockLocationType.branchStore =>
        '${master.branchLabel(location.branchId)} · ${location.name}',
      StockLocationType.room =>
        '${master.branchLabel(location.branchId)} · ${location.name}',
    };
  }

  /// Whether any of the ids a row names failed to resolve, so the row can be
  /// flagged without each builder re-deriving the condition.
  static bool isHistorical(
    ReportMasterData master, {
    String? itemId,
    String? batchId,
    String? locationId,
    String? userId,
  }) =>
      (itemId != null && master.item(itemId) == null) ||
      (batchId != null && master.batch(batchId) == null) ||
      (locationId != null && master.location(locationId) == null) ||
      (userId != null && master.user(userId) == null);

  /// The sync snapshot for a set of ledger rows.
  static ReportSyncSnapshot ledgerSnapshot(
    Iterable<ReportLedgerMovement> movements,
  ) => ReportSyncSnapshotBuilder.buildDeduplicated([
    for (final movement in movements)
      (
        id: movement.id,
        status: movement.syncStatus,
        updatedAtUtc: movement.updatedAtUtc,
      ),
  ]);

  /// Every warning a document should carry: the source's historical notes plus
  /// whatever the builder found, de-duplicated and in a stable order.
  static List<String> warnings(
    Iterable<String> fromSource, [
    Iterable<String> fromBuilder = const <String>[],
  ]) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final warning in [...fromSource, ...fromBuilder]) {
      if (seen.add(warning)) ordered.add(warning);
    }
    return List.unmodifiable(ordered);
  }
}
