import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/date_only.dart';

/// What a cell means, decided once (§16).
///
/// ### Trim everything, canonicalize almost nothing
///
/// Every value is trimmed, because trailing whitespace in a spreadsheet is an
/// accident every time. Beyond that the policy is deliberately conservative:
/// nothing is upper-cased, nothing is title-cased, and no code is "tidied". A
/// specification that does not say `code` is uppercase does not authorise this
/// module to rewrite what an operator typed — and a SKU silently upper-cased on
/// import is a SKU that no longer matches the label on the box.
///
/// Two exceptions, and both are stated by rules rather than chosen for tidiness:
///
/// * **Email is lower-cased.** It is the natural key of a user (G-M4), and
///   `Budi@klinik.id` and `budi@klinik.id` are one account. Storing whichever
///   spelling arrived first would let the same person be created twice.
/// * **Role is lower-cased** before it is matched, because the enum's `dbValue`s
///   are lowercase and `Super_Admin` in a spreadsheet is a capitalisation, not a
///   different role.
///
/// Display values — names, addresses, units, batch numbers, category names — are
/// preserved verbatim. Only their *comparison* keys are case-folded.
///
/// ### Booleans accept exactly four spellings
///
/// `TRUE`, `FALSE`, `true`, `false` — and, because case-folding a boolean cannot
/// mean two things, any casing of those two words. Nothing else. Not `yes`, not
/// `Y`, not `1`, not `ya`, not an empty cell meaning false.
///
/// That refusal is the point. `1` and `0` look obvious until a spreadsheet stores
/// them as floats and `1.0` arrives; `ya`/`tidak` invites `y`/`t` and then `Y`;
/// and a blank cell read as `false` would silently deactivate every row an
/// operator forgot to fill. Four spellings, documented in the template's
/// *Petunjuk* sheet, and a clear error otherwise.
///
/// ### Integers are parsed exactly
///
/// `int.parse` on digits only — no `double`, no scientific notation, no thousands
/// separator. A spreadsheet that hands back `1000.0` for a stock minimum is
/// handing back a float, and accepting it here is how `3` becomes `2` somewhere
/// downstream. The one accommodation is a trailing `.0`, because Excel writes
/// integers that way often enough that refusing it would fail files that are
/// unambiguously correct.
abstract final class MasterImportNormalizationPolicy {
  // --- text ------------------------------------------------------------------

  /// Trims, and collapses nothing else.
  static String text(String? raw) => raw?.trim() ?? '';

  /// Trims and maps empty to `null` — for the columns where blank is legal.
  static String? optionalText(String? raw) {
    final trimmed = text(raw);
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The comparison key for a case-insensitive natural key.
  ///
  /// Lower-cased so `DEN-0001` and `den-0001` collide, which is what makes the
  /// duplicate and ambiguity rules of §17 able to see them. The *stored* value is
  /// never this string.
  static String key(String? raw) => text(raw).toLowerCase();

  /// The separator between the parts of a composite key.
  ///
  /// NUL, written explicitly, because it is the one character no branch code,
  /// room code, SKU or batch number can contain — a spreadsheet cannot produce
  /// one and the schema's text columns never hold one.
  ///
  /// A visible separator would not be safe. With a space, `('A B', 'C')` and
  /// `('A', 'B C')` both fold to `a b c`, so two genuinely different rooms would
  /// share a key and the second would silently update the first. `|` and `/` have
  /// the same problem the moment a code contains one, and the whole point of a
  /// composite key is that two different pairs are two keys.
  static const String keySeparator = '\u0000';

  /// Joins several key parts into one composite comparison key.
  static String compositeKey(Iterable<String?> parts) =>
      parts.map(key).join(keySeparator);

  // --- email -----------------------------------------------------------------

  static String email(String? raw) => text(raw).toLowerCase();

  /// A deliberately permissive shape check.
  ///
  /// One `@`, something before it, something with a dot after it, no whitespace.
  /// This is not RFC 5322 and does not try to be: the address is a login name in
  /// a clinic group, not a routing decision, and a validator strict enough to be
  /// "correct" reliably rejects real addresses.
  static bool isValidEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  // --- role ------------------------------------------------------------------

  /// The role, or `null` when the text is not one of the four.
  static UserRole? role(String? raw) {
    final normalized = text(raw).toLowerCase();
    if (normalized.isEmpty) return null;
    for (final role in UserRole.values) {
      if (role.dbValue == normalized) return role;
    }
    return null;
  }

  /// The four `dbValue`s, for the template's *Petunjuk* sheet and error text.
  static List<String> get allowedRoles =>
      UserRole.values.map((role) => role.dbValue).toList(growable: false);

  // --- boolean ---------------------------------------------------------------

  static const List<String> canonicalBooleans = ['TRUE', 'FALSE'];

  /// `TRUE`/`FALSE` in any casing, and nothing else. `null` means *invalid*, and
  /// so does an empty cell — see the class note on why blank is not `false`.
  static bool? boolean(String? raw) => switch (text(raw).toUpperCase()) {
    'TRUE' => true,
    'FALSE' => false,
    _ => null,
  };

  static String formatBoolean(bool value) => value ? 'TRUE' : 'FALSE';

  // --- integer ---------------------------------------------------------------

  /// A non-negative integer, or `null` when the text is not one.
  ///
  /// Accepts `12` and `12.0`; refuses `12.5`, `1e3`, `1,000`, `-1` and ` 12 ` is
  /// fine only because it was trimmed first.
  static int? nonNegativeInteger(String? raw) {
    var value = text(raw);
    if (value.isEmpty) return null;
    // Excel routinely writes an integer cell back as `12.0`. A trailing `.0` is
    // unambiguously the same number, so it is accepted; a non-zero fraction is
    // not a stock minimum and is refused.
    if (value.endsWith('.0')) value = value.substring(0, value.length - 2);
    if (!RegExp(r'^\d+$').hasMatch(value)) return null;
    return int.tryParse(value);
  }

  // --- date ------------------------------------------------------------------

  /// `YYYY-MM-DD` as a civil date at UTC midnight (T-8), or `null`.
  ///
  /// No `toLocal()` anywhere on this path, and none possible: [DateOnly.parseIso]
  /// builds the value from the calendar fields directly. An expiry date printed
  /// on a box is not an instant, and a timezone conversion is exactly how
  /// `2026-07-29` becomes `2026-07-28` on a device west of GMT.
  static DateTime? isoDate(String? raw) {
    final value = text(raw);
    if (value.isEmpty) return null;
    final DateTime parsed;
    try {
      parsed = DateOnly.parseIso(value);
    } on FormatException {
      return null;
    }
    // `DateTime.utc(2026, 13, 1)` is not an error in Dart — it is January 2027.
    // So `2026-13-01` parses, and an expiry date the operator never typed lands
    // in the database a year later than the box says. The round trip is what
    // catches it: a date that does not render back to the text it came from was
    // not that date.
    if (DateOnly.formatIso(parsed) != value) return null;
    return parsed;
  }

  static String formatDate(DateTime date) => DateOnly.formatIso(date);

  // --- identifiers -----------------------------------------------------------

  /// Whether a value looks like a number a spreadsheet mangled.
  ///
  /// Identifier columns — SKU, codes, batch numbers, emails — are written as text
  /// cells by the generator so `007` survives. A file an operator rebuilt by hand
  /// may still hand back `7` or `1.0E+3`, and the parser refuses those rather than
  /// importing a code the operator never typed. This is the shape check behind
  /// that refusal.
  static bool looksLikeMangledNumber(String value) =>
      RegExp(r'^-?\d+(\.\d+)?[eE][+-]?\d+$').hasMatch(value.trim());

  static const String booleanFormatLabel = 'TRUE atau FALSE';

  static const String dateFormatLabel = 'YYYY-MM-DD, contoh 2026-12-31';

  static const String integerFormatLabel = 'bilangan bulat, minimal 0';
}

/// The hard limits every import is bounded by (§15).
///
/// Central and named, because three of them are the difference between a slow
/// import and an unresponsive device, and a limit spread across the parser, the
/// validator and the UI is three limits that will disagree.
///
/// The values are chosen, not derived, and the reasoning is here so a later change
/// is a decision rather than a tweak:
///
/// * **10 MiB** — an `.xlsx` is compressed, and a 10,000-row master sheet of the
///   widest entity is well under 1 MiB. Ten times that is generous for a file a
///   human assembled and small enough to hold in memory twice (the bytes and the
///   parsed workbook) on a low-end tablet.
/// * **10,000 rows** — larger than any single master entity this clinic group
///   plausibly has, and the point at which a preview table stops being something a
///   person reviews and starts being something they scroll past. §42 renders it
///   lazily; this is the ceiling that keeps validation bounded.
/// * **4,000 characters per cell** — longer than any name, address or note the
///   schema stores (the widest column is 255), so nothing legitimate is cut, and
///   short enough that a workbook cannot carry a megabyte in one cell.
abstract final class MasterImportLimits {
  static const int maxFileBytes = 10 * 1024 * 1024;

  static const int maxDataRows = 10000;

  static const int maxCellCharacters = 4000;

  /// The only extension accepted (§15).
  static const String allowedExtension = '.xlsx';

  /// Extensions named in the refusal message, so a user who picked one of these
  /// is told what to do rather than only what went wrong.
  static const List<String> knownRefusedExtensions = [
    '.xls',
    '.xlsm',
    '.xlsb',
    '.csv',
  ];

  static String get maxFileSizeLabel =>
      '${(maxFileBytes / (1024 * 1024)).round()} MB';
}
