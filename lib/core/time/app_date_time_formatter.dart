import 'package:intl/intl.dart';

import 'app_time_zone.dart';

/// Indonesian date and time rendering for the whole app (spec §6.1).
///
/// Every method that takes an instant follows the same three steps: make sure
/// the value is UTC → convert through [AppTimeZone] → format. `toLocal()` is
/// never called, because its result would follow the device timezone instead of
/// the operational one (T-4).
///
/// Only numeric `intl` patterns are used, so no locale data has to be
/// initialised at startup; the month names come from [_monthsShort] and are
/// Indonesian by definition (Mei / Agu / Okt / Des).
abstract final class AppDateTimeFormatter {
  static const String timeZoneLabel = AppTimeZone.label;

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

  static final DateFormat _time = DateFormat('HH:mm');

  /// `29 Jul 2026` — the operational date of a UTC instant.
  static String date(DateTime utc) => _civil(AppTimeZone.utcToOperational(utc));

  /// `29 Jul 2026, 22:30` — operational date and time of a UTC instant.
  static String dateTime(DateTime utc) {
    final operational = AppTimeZone.utcToOperational(utc);
    return '${_civil(operational)}, ${_time.format(operational)}';
  }

  /// `22:30` — operational time of a UTC instant.
  static String time(DateTime utc) =>
      _time.format(AppTimeZone.utcToOperational(utc));

  /// `29 Jul 2026, 22:30 GMT+8` — for screens where the zone must be explicit.
  static String dateTimeWithZone(DateTime utc) =>
      '${dateTime(utc)} $timeZoneLabel';

  /// `22:30 GMT+8`.
  static String timeWithZone(DateTime utc) => '${time(utc)} $timeZoneLabel';

  /// `29 Jul 2026` for a civil date such as `expiry_date`.
  ///
  /// Deliberately performs **no** timezone conversion (T-9): the calendar
  /// fields are printed exactly as stored.
  static String civilDate(DateTime date) => _civil(date);

  static String _civil(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    return '$day ${_monthsShort[value.month - 1]} ${value.year}';
  }
}
