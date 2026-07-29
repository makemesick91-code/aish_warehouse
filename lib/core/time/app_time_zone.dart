import 'date_only.dart';

/// The single place where the operational timezone is applied (spec T-5).
///
/// The application stores every persistent timestamp in **UTC** and displays /
/// reasons about them in **operational time**, which is fixed at UTC+08:00
/// (GMT+8) — see spec §6.1.
///
/// Two rules make this deterministic on every device:
///
/// * The term used throughout the code is *operational time*, never *local
///   time*: `DateTime.toLocal()` follows the device timezone and is therefore
///   banned on display and calculation paths (T-4, T-6).
/// * Operational values are returned as UTC-flagged `DateTime`s whose fields
///   carry the GMT+8 wall clock. They are wall-clock values, not instants, so
///   Dart can never re-interpret them against the device offset.
abstract final class AppTimeZone {
  /// UTC+08:00.
  static const Duration offset = Duration(hours: 8);

  /// Suffix for timestamps that need the zone spelled out, e.g.
  /// `29 Jul 2026, 22:30 GMT+8`.
  static const String label = 'GMT+8';

  /// ISO-8601 form of [offset], for document headers and exports.
  static const String isoOffset = '+08:00';

  /// Persisted UTC instant → operational wall clock.
  static DateTime utcToOperational(DateTime utc) => _asInstant(utc).add(offset);

  /// Operational wall clock → the UTC instant to persist.
  ///
  /// The calendar fields of [operational] are read verbatim; whether the value
  /// happens to be flagged UTC or local is irrelevant, which is what keeps user
  /// input independent of the device timezone.
  static DateTime operationalToUtc(DateTime operational) =>
      _asWallClock(operational).subtract(offset);

  /// "Now" in operational time. The UTC clock is injected rather than read here
  /// so services and tests stay deterministic (T-7).
  static DateTime operationalNow(DateTime utcNow) => utcToOperational(utcNow);

  /// The operational calendar date a UTC instant falls on — this is what
  /// "today" means everywhere in the app.
  static DateTime operationalDate(DateTime utc) =>
      DateOnly.from(utcToOperational(utc));

  /// First UTC instant belonging to an operational day.
  ///
  /// `2026-07-29` GMT+8 starts at `2026-07-28T16:00:00Z`.
  static DateTime startOfOperationalDayUtc(DateTime operationalDate) =>
      operationalToUtc(DateOnly.from(operationalDate));

  /// Last UTC instant belonging to an operational day, inclusive.
  ///
  /// `2026-07-29` GMT+8 ends at `2026-07-29T15:59:59.999999Z`.
  static DateTime endOfOperationalDayUtc(DateTime operationalDate) =>
      startOfOperationalDayUtc(
        DateOnly.addDays(DateOnly.from(operationalDate), 1),
      ).subtract(const Duration(microseconds: 1));

  /// Whether two UTC instants fall on the same operational day.
  static bool isSameOperationalDay(DateTime aUtc, DateTime bUtc) =>
      DateOnly.isSameDate(operationalDate(aUtc), operationalDate(bUtc));

  /// ISO-8601 week number (1–53) of an operational date — the period key of
  /// Stok Opname (G-O1).
  static int isoWeekNumber(DateTime operationalDate) {
    final thursday = _isoWeekThursday(operationalDate);
    final firstDayOfYear = DateTime.utc(thursday.year, 1, 1);
    return thursday.difference(firstDayOfYear).inDays ~/ 7 + 1;
  }

  /// Week-numbering year of an operational date. Differs from the calendar year
  /// around new year, e.g. 2027-01-01 belongs to week 53 of 2026.
  static int isoWeekYear(DateTime operationalDate) =>
      _isoWeekThursday(operationalDate).year;

  // --- internals ------------------------------------------------------------

  /// The Thursday of the ISO week [date] belongs to — the day that decides both
  /// the week number and the week-numbering year.
  static DateTime _isoWeekThursday(DateTime date) {
    final day = DateOnly.from(date);
    return DateOnly.addDays(day, 4 - day.weekday);
  }

  /// Normalises to a UTC instant. Persisted timestamps are already UTC-flagged;
  /// anything else is converted so the instant is preserved.
  static DateTime _asInstant(DateTime value) =>
      value.isUtc ? value : value.toUtc();

  /// Re-reads the calendar fields of [value] as a wall-clock reading, dropping
  /// whatever zone flag it carried.
  static DateTime _asWallClock(DateTime value) => DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}
