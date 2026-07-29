/// Civil dates — calendar dates with no time and no timezone.
///
/// `expiry_date` is the canonical example (spec T-8): it is not an instant, it
/// is a date printed on a package. It must therefore never be shifted by a
/// timezone conversion — `2026-07-29` stays `2026-07-29` in storage, in
/// comparisons and on screen.
///
/// A civil date is represented as a `DateTime` at UTC midnight. UTC is used as
/// the carrier (not as a timezone claim) precisely because it has no DST and no
/// device dependency, so the year/month/day fields can never drift.
abstract final class DateOnly {
  /// Builds a civil date from its calendar parts.
  static DateTime of(int year, int month, int day) =>
      DateTime.utc(year, month, day);

  /// Strips the time from [value], keeping its calendar fields verbatim.
  ///
  /// The fields are read as-is: no `toUtc()` and no `toLocal()`, because
  /// converting a civil date is exactly the bug this class prevents.
  static DateTime from(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  /// Parses `yyyy-MM-dd`. Throws [FormatException] on anything else.
  static DateTime parseIso(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Tanggal harus berformat yyyy-MM-dd.', value);
    }
    return DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Renders `yyyy-MM-dd` — the storage and log representation.
  static String formatIso(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  static DateTime addDays(DateTime date, int days) =>
      DateTime.utc(date.year, date.month, date.day + days);

  static bool isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Negative when [a] is earlier, zero on the same date, positive when later.
  static int compare(DateTime a, DateTime b) => from(a).compareTo(from(b));

  static bool isBeforeDate(DateTime a, DateTime b) => compare(a, b) < 0;

  static bool isAfterDate(DateTime a, DateTime b) => compare(a, b) > 0;

  /// Whole days from [from_] to [to]. Exact, because both sides are UTC
  /// midnights and UTC has no daylight-saving jumps.
  static int daysBetween(DateTime from_, DateTime to) =>
      from(to).difference(from(from_)).inDays;
}
