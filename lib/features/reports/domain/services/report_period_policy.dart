import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../../../../core/time/operational_iso_week.dart';
import '../models/reporting_models.dart';

/// The single place a report's date range becomes a UTC window (§15).
///
/// ### Why this is a policy rather than two lines at each call site
///
/// A period is stated in **operational civil dates** — the GMT+8 calendar the clinic
/// works in (T-5) — and the ledger is stamped in **UTC instants**. Converting
/// between them is three decisions, and getting any one of them wrong produces a
/// report that is subtly, unfalsifiably wrong:
///
/// 1. `2026-07-30` GMT+8 *starts* at `2026-07-29T16:00Z`, not at midnight UTC. A
///    report that used midnight UTC would silently pull in eight hours of the
///    previous operational day and push out eight hours of its own.
/// 2. The window is **half-open**: `start <= t < endExclusive`. A closed window
///    built with `endOfDay` has to pick a last representable microsecond, and a
///    movement stamped on the boundary then belongs to two periods or to none.
/// 3. An *as-of* report has no start at all. Rather than leave `period_start` NULL
///    and make every reader guess, §3.9 normalises it to equal `period_end` — so
///    "as of one day" and "a range whose start was lost" can never look alike in
///    the audit.
///
/// Deriving that once here is what makes the boundary the same for the builder, the
/// sync snapshot, the file name and the export log.
///
/// ### What this policy never does
///
/// * It never calls `DateTime.toLocal()`. The device timezone has no say in what a
///   clinic day is (T-4/T-6).
/// * It never compares timestamps as strings. Both ends come out as `DateTime`s, and
///   every caller filters with [ReportPeriod.contains] on parsed instants — never
///   with a SQL predicate over the ISO-8601 TEXT column.
abstract final class ReportPeriodPolicy {
  /// Builds the window for a **range** report.
  ///
  /// Both bounds are read as civil dates: whatever time-of-day or zone flag they
  /// arrive with is discarded by [DateOnly.from], which is the whole point — a
  /// `DateTime.now()` picked off a device in another timezone must still name the
  /// day the user tapped.
  ///
  /// Throws [InvalidReportPeriodFailure] when the range runs backwards.
  static ReportPeriod range({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final start = DateOnly.from(periodStart);
    final end = DateOnly.from(periodEnd);
    if (DateOnly.isAfterDate(start, end)) {
      throw InvalidReportPeriodFailure(
        'Tanggal mulai tidak boleh setelah tanggal akhir.',
        periodStart: start,
        periodEnd: end,
      );
    }
    return ReportPeriod(
      periodStart: start,
      periodEnd: end,
      startUtc: AppTimeZone.startOfOperationalDayUtc(start),
      // The first instant of the day *after* the last day in range — half-open,
      // see decision 2 in the class note.
      endExclusiveUtc: AppTimeZone.startOfOperationalDayUtc(
        DateOnly.addDays(end, 1),
      ),
    );
  }

  /// Builds the window for an **as-of** report: one date, [ReportPeriod.startUtc]
  /// pinned to the same day so a caller cannot accidentally read a range out of it.
  ///
  /// `startUtc` is deliberately the *start of that same day* rather than the epoch,
  /// even though a balance-as-of read needs everything before the cutoff. The
  /// engine asks [ReportPeriod.isAtOrBeforeCutoff] for that, and leaving `startUtc`
  /// meaningful keeps the object honest: it describes the period the header prints
  /// and the audit stores, not the query's reach.
  static ReportPeriod asOf(DateTime date) {
    final day = DateOnly.from(date);
    return range(periodStart: day, periodEnd: day);
  }

  /// The window for [reportType], normalising an as-of report's start (§3.9).
  ///
  /// The one entry point the use cases call, so no screen has to remember which
  /// reports collapse to a single date — [ReportType.isAsOfReport] already knows.
  static ReportPeriod forReport({
    required ReportType reportType,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    if (reportType.isAsOfReport) return asOf(periodEnd);
    return range(periodStart: periodStart, periodEnd: periodEnd);
  }

  /// The operational date "now" falls on — what the default filter opens at.
  static DateTime operationalToday(DateTime utcNow) =>
      AppTimeZone.operationalDate(utcNow);

  /// Whether [period] is exactly one ISO week, Monday through Sunday.
  ///
  /// G-L5's example file name is `kartu_stok_R1_2026-W31.pdf`, so the week form is
  /// used **only** when the range really is that week — a Monday-to-Saturday range
  /// that rendered as `2026-W31` would name a file for data it does not contain.
  static bool isExactIsoWeek(ReportPeriod period) {
    final week = OperationalIsoWeek.ofOperationalDate(period.periodStart);
    return DateOnly.isSameDate(period.periodStart, week.mondayDate) &&
        DateOnly.isSameDate(
          period.periodEnd,
          DateOnly.addDays(week.mondayDate, 6),
        );
  }

  /// The ISO week [period] spans, valid only when [isExactIsoWeek] is true.
  static OperationalIsoWeek isoWeekOf(ReportPeriod period) =>
      OperationalIsoWeek.ofOperationalDate(period.periodStart);

  /// `30 Jul 2026` for an as-of report, `1 Jul 2026 – 30 Jul 2026` for a range.
  ///
  /// Used verbatim in every header, so the screen, the workbook and the PDF print
  /// the same sentence.
  static String describe(ReportPeriod period, {required bool isAsOf}) {
    if (isAsOf || period.isSingleDay) {
      return 'Per ${_civil(period.periodEnd)} ${AppTimeZone.label}';
    }
    return '${_civil(period.periodStart)} – ${_civil(period.periodEnd)} '
        '${AppTimeZone.label}';
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

  /// Civil rendering with **no** timezone conversion (T-9): the calendar fields are
  /// printed exactly as stored, which is the whole contract of a [DateOnly] value.
  static String _civil(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')} '
      '${_monthsShort[date.month - 1]} ${date.year}';
}
