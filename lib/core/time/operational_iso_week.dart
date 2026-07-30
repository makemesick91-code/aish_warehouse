import 'app_time_zone.dart';
import 'date_only.dart';

/// An ISO week of the operational calendar — the period key every weekly
/// document is filed under (T-3, G-O1).
///
/// It exists because comparing two periods is not the arithmetic it looks like.
/// A rule such as "the current or the previous week" is tempting to write as
/// `periodWeek >= currentWeek - 1`, and that expression is wrong twice a year:
/// the week before `2026-W01` is `2025-W52` or `2025-W53` depending on how 2025
/// fell, so the subtraction underflows into a week number that does not exist
/// and a perfectly valid reference is rejected. Comparing only the week number
/// while ignoring the year is worse — `2025-W31` would count as this week for a
/// document created in 2026.
///
/// Distance is therefore measured in **days between the two weeks' Mondays**,
/// which is exact by construction: both are civil dates, UTC has no
/// daylight-saving jumps, and every ISO week is exactly seven days long.
///
/// The value is a wall-clock fact, not an instant. Construction from a UTC
/// instant goes through [AppTimeZone], so the week boundary is the operational
/// one (GMT+8) and never the device's.
class OperationalIsoWeek implements Comparable<OperationalIsoWeek> {
  const OperationalIsoWeek({required this.year, required this.week});

  /// The week an operational (GMT+8) calendar date belongs to.
  factory OperationalIsoWeek.ofOperationalDate(DateTime operationalDate) =>
      OperationalIsoWeek(
        year: AppTimeZone.isoWeekYear(operationalDate),
        week: AppTimeZone.isoWeekNumber(operationalDate),
      );

  /// The week a persisted UTC instant falls in, read in operational time.
  ///
  /// This is the constructor callers should reach for: it makes the conversion
  /// explicit instead of leaving a `DateTime` whose zone nobody can tell by
  /// looking.
  factory OperationalIsoWeek.ofUtcInstant(DateTime utcInstant) =>
      OperationalIsoWeek.ofOperationalDate(
        AppTimeZone.operationalDate(utcInstant),
      );

  /// ISO week-numbering year. Differs from the calendar year around new year:
  /// 2027-01-01 belongs to week 53 of 2026.
  final int year;

  /// ISO week number, 1–53.
  final int week;

  /// `2026-W31`.
  String get label => '$year-W${week.toString().padLeft(2, '0')}';

  /// The Monday this ISO week starts on, as a civil date.
  ///
  /// January 4th is by definition always in week 1 of its week-numbering year,
  /// which is what anchors the whole calculation without any special case for
  /// years that begin mid-week.
  DateTime get mondayDate {
    final jan4 = DateOnly.of(year, 1, 4);
    final mondayOfWeek1 = DateOnly.addDays(jan4, 1 - jan4.weekday);
    return DateOnly.addDays(mondayOfWeek1, 7 * (week - 1));
  }

  /// The week immediately before this one — `2025-W52` or `2025-W53` for
  /// `2026-W01`, whichever 2025 actually had.
  OperationalIsoWeek get previous =>
      OperationalIsoWeek.ofOperationalDate(DateOnly.addDays(mondayDate, -7));

  OperationalIsoWeek get next =>
      OperationalIsoWeek.ofOperationalDate(DateOnly.addDays(mondayDate, 7));

  /// How many weeks [other] lies **before** this one.
  ///
  /// Zero for the same week, 1 for the week before, negative when [other] is in
  /// the future relative to this one. Exact across year boundaries, because it
  /// counts days rather than week numbers.
  int weeksAfter(OperationalIsoWeek other) =>
      DateOnly.daysBetween(other.mondayDate, mondayDate) ~/ 7;

  /// This week and the [count] weeks before it, newest first.
  ///
  /// The list the eligibility rule turns into a SQL predicate: naming the periods
  /// explicitly is what keeps the database out of the business of arithmetic on
  /// week numbers.
  List<OperationalIsoWeek> withPrevious(int count) {
    final periods = <OperationalIsoWeek>[this];
    var cursor = this;
    for (var i = 0; i < count; i++) {
      cursor = cursor.previous;
      periods.add(cursor);
    }
    return List.unmodifiable(periods);
  }

  @override
  int compareTo(OperationalIsoWeek other) =>
      mondayDate.compareTo(other.mondayDate);

  bool operator <(OperationalIsoWeek other) => compareTo(other) < 0;

  bool operator >(OperationalIsoWeek other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OperationalIsoWeek && other.year == year && other.week == week);

  @override
  int get hashCode => Object.hash(year, week);

  @override
  String toString() => 'OperationalIsoWeek($label)';
}
