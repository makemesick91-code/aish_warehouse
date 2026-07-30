/// Why a parse attempt failed, so the UI can pick the right Indonesian message.
enum QuantityFormatReason {
  /// Nothing was entered.
  empty,

  /// Not a number at all (`abc`, `NaN`, `Infinity`, `1.2.3`, `1.`).
  notANumber,

  /// A negative amount was entered where quantities must be positive.
  negative,

  /// More than [Quantity.decimalDigits] digits after the separator.
  tooManyDecimals,
}

/// Thrown by [Quantity.parse] when the text is not a valid quantity.
///
/// Rounding silently would hide a counting mistake from the user, so an invalid
/// input is always an error and never a rounded value (spec Q-5).
final class QuantityFormatException implements Exception {
  const QuantityFormatException(this.reason, this.input);

  final QuantityFormatReason reason;
  final String input;

  String get message => switch (reason) {
    QuantityFormatReason.empty => 'Jumlah tidak boleh kosong.',
    QuantityFormatReason.notANumber => 'Masukkan jumlah yang valid.',
    QuantityFormatReason.negative => 'Jumlah tidak boleh negatif.',
    QuantityFormatReason.tooManyDecimals =>
      'Maksimal ${Quantity.decimalDigits} angka di belakang koma.',
  };

  @override
  String toString() => 'QuantityFormatException($message, input: "$input")';
}

/// An item quantity, held as a fixed-point integer (spec Q-2).
///
/// Stock quantities support up to three decimals (`0.5`, `1.25`, `2.375`) and
/// are stored as **milli-units**: the value times [scale]. Binary floating point
/// is not used anywhere on the ledger path, because `0.1 + 0.2` must be exactly
/// `0.3` and never `0.30000000000000004`.
///
/// The class carries no `double` conversion on purpose — offering one would
/// invite exactly the rounding drift this type exists to prevent.
///
/// Values may be negative internally (an opname difference is
/// `counted - system`), but the business rules on movements and balances still
/// demand `qty > 0` and `qty_on_hand >= 0` (Q-7).
final class Quantity implements Comparable<Quantity> {
  /// Wraps a raw milli-unit value. This is the database boundary constructor;
  /// application code should prefer [Quantity.fromWhole] or [Quantity.parse].
  const Quantity.fromMilliUnits(this.milliUnits);

  factory Quantity.zero() => const Quantity.fromMilliUnits(0);

  /// `Quantity.fromWhole(10)` is ten whole units.
  factory Quantity.fromWhole(int value) =>
      Quantity.fromMilliUnits(value * scale);

  /// Parses user input, accepting both decimal separators — `"0.5"` and
  /// `"0,5"` are the same quantity (Q-5).
  ///
  /// Throws [QuantityFormatException] for empty input, negatives, non-numbers
  /// and anything with more than [decimalDigits] decimals.
  factory Quantity.parse(String input) {
    final normalized = input.trim().replaceAll(',', '.');

    if (normalized.isEmpty) {
      throw QuantityFormatException(QuantityFormatReason.empty, input);
    }
    if (_negative.hasMatch(normalized)) {
      throw QuantityFormatException(QuantityFormatReason.negative, input);
    }
    if (_tooManyDecimals.hasMatch(normalized)) {
      throw QuantityFormatException(
        QuantityFormatReason.tooManyDecimals,
        input,
      );
    }

    final match = _decimal.firstMatch(normalized);
    final whole = match?.group(1) ?? '';
    final fraction = match?.group(2);
    if (match == null || (whole.isEmpty && fraction == null)) {
      throw QuantityFormatException(QuantityFormatReason.notANumber, input);
    }

    final wholeUnits = whole.isEmpty ? 0 : int.parse(whole);
    final milliFraction = fraction == null
        ? 0
        : int.parse(fraction.padRight(decimalDigits, '0'));
    return Quantity.fromMilliUnits(wholeUnits * scale + milliFraction);
  }

  /// Like [Quantity.parse] but returns `null` instead of throwing — used while
  /// the user is still typing.
  static Quantity? tryParse(String input) {
    try {
      return Quantity.parse(input);
    } on QuantityFormatException {
      return null;
    }
  }

  /// Milli-units per whole unit: `1 unit = 1000 milli-units`.
  static const int scale = 1000;

  /// Digits accepted after the decimal separator.
  static const int decimalDigits = 3;

  /// `1` or `1.25`; the fractional part is capped at three digits.
  static final RegExp _decimal = RegExp(r'^(\d*)(?:\.(\d{1,3}))?$');
  static final RegExp _negative = RegExp(r'^-\d*\.?\d*$');
  static final RegExp _tooManyDecimals = RegExp(r'^\d*\.\d{4,}$');

  /// The quantity in milli-units. Only the database boundary should read this;
  /// it is never shown to a user (Q-6).
  final int milliUnits;

  bool get isZero => milliUnits == 0;

  bool get isPositive => milliUnits > 0;

  bool get isNegative => milliUnits < 0;

  Quantity get absolute =>
      isNegative ? Quantity.fromMilliUnits(-milliUnits) : this;

  /// Renders the quantity without trailing zeros: `1`, `0.5`, `1.25`, `2.375`.
  String format() {
    final sign = isNegative ? '-' : '';
    final magnitude = milliUnits.abs();
    final whole = magnitude ~/ scale;
    final fraction = magnitude % scale;
    if (fraction == 0) return '$sign$whole';

    var digits = fraction.toString().padLeft(decimalDigits, '0');
    while (digits.endsWith('0')) {
      digits = digits.substring(0, digits.length - 1);
    }
    return '$sign$whole.$digits';
  }

  /// `0.5 box`, `10 pcs`.
  String formatWithUnit(String unit) {
    final trimmed = unit.trim();
    return trimmed.isEmpty ? format() : '${format()} $trimmed';
  }

  Quantity operator +(Quantity other) =>
      Quantity.fromMilliUnits(milliUnits + other.milliUnits);

  Quantity operator -(Quantity other) =>
      Quantity.fromMilliUnits(milliUnits - other.milliUnits);

  Quantity operator -() => Quantity.fromMilliUnits(-milliUnits);

  bool operator <(Quantity other) => milliUnits < other.milliUnits;

  bool operator <=(Quantity other) => milliUnits <= other.milliUnits;

  bool operator >(Quantity other) => milliUnits > other.milliUnits;

  bool operator >=(Quantity other) => milliUnits >= other.milliUnits;

  /// Whether this quantity exceeds [other] scaled by [numerator]/[denominator],
  /// compared **exactly** in fixed point.
  ///
  /// This is how G-P3's "more than 150 % of the suggestion" is asked:
  /// `requested.exceedsRatioOf(suggested, numerator: 3, denominator: 2)`. The
  /// comparison is cross-multiplied to `requested × 2 > suggested × 3`, so it is
  /// integer arithmetic end to end. Written the obvious way instead —
  /// `requested.toDouble() > suggested.toDouble() * 1.5` — a request of exactly
  /// 150 % would land on whichever side of the boundary binary floating point
  /// happened to round it to, and the threshold would be unstable for values
  /// such as `1.5 × 0.7`. Nothing here converts to `double`, which is also why
  /// this type still offers no way to.
  ///
  /// Strictly greater than, deliberately: a request of exactly
  /// [numerator]/[denominator] is *not* above the threshold, because the rule is
  /// worded `> 150%`.
  ///
  /// The comparison stays meaningful for a zero or negative [other] — it simply
  /// reduces to `this > 0` — but "150 % of nothing" is not a business rule, and
  /// the caller that owns that distinction is
  /// `PurchaseRequestQuantityPolicy.isManualRequest`.
  bool exceedsRatioOf(
    Quantity other, {
    required int numerator,
    required int denominator,
  }) => milliUnits * denominator > other.milliUnits * numerator;

  /// This quantity scaled by the exact fraction [numerator]/[denominator].
  ///
  /// Integer arithmetic on milli-units, so `1.5 × 3/2` is exactly `2.25` and not
  /// `2.2500000000000004`. When the result does not land on a whole milli-unit it
  /// is **truncated towards zero** rather than rounded, which keeps the value
  /// inside the fraction it was asked for — the property that matters for the
  /// only current caller, the "highest quantity that still needs no
  /// justification" hint under the input (G-P3).
  ///
  /// Not used to decide the 150 % threshold itself: that is
  /// [exceedsRatioOf], which cross-multiplies and therefore has no division to
  /// truncate at all.
  Quantity scaledBy({required int numerator, required int denominator}) =>
      Quantity.fromMilliUnits(milliUnits * numerator ~/ denominator);

  /// The larger of two quantities — `max(zero, min − counted)` is how a Purchase
  /// Request suggestion clamps a surplus to nothing rather than to a negative
  /// order.
  static Quantity max(Quantity a, Quantity b) => a >= b ? a : b;

  /// The smaller of two quantities — the FEFO allocator takes
  /// `min(remaining, batch on hand)` from each batch.
  static Quantity min(Quantity a, Quantity b) => a <= b ? a : b;

  static Quantity sum(Iterable<Quantity> values) => values.fold(
    const Quantity.fromMilliUnits(0),
    (total, value) => total + value,
  );

  @override
  int compareTo(Quantity other) => milliUnits.compareTo(other.milliUnits);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Quantity && other.milliUnits == milliUnits);

  @override
  int get hashCode => milliUnits.hashCode;

  @override
  String toString() => 'Quantity(${format()})';
}
