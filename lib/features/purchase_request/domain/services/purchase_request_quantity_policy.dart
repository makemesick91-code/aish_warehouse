import '../../../../core/quantity/quantity.dart';

/// G-P3, stated once: when does a requested quantity need a written reason?
///
/// The rule the specification gives is *"kenaikan > 150% dari saran menampilkan
/// peringatan & wajib catatan"*, and it has two halves that are easy to conflate:
///
/// * **Above the threshold.** With a suggestion to compare against, "more than
///   150 %" is a ratio, and it is compared exactly in fixed point —
///   `requested × 2 > suggested × 3`, never `requested > suggested * 1.5` on
///   `double`s. Exactly 150 % is *not* above the threshold, because the rule says
///   `>` and a branch head who asks for precisely one and a half times the
///   suggestion has not exceeded anything.
/// * **A manual request.** When the suggestion is zero there is no ratio to
///   exceed: `150 % of 0` is `0`, so every positive request would trip a
///   percentage test and the "150 %" wording would be doing no work. That case is
///   named for what it is — the branch head is asking for something the counts did
///   not ask for — and it needs a reason for exactly that reason.
///
/// Centralised so the form's warning, the submit validation and the database's
/// idea of a justified line are the same predicate rather than three that have to
/// be kept in step by hand.
abstract final class PurchaseRequestQuantityPolicy {
  /// The threshold, as an exact fraction. `3/2` is 150 %.
  static const int thresholdNumerator = 3;
  static const int thresholdDenominator = 2;

  /// A percentage, for the warning text only. Never used in a comparison.
  static const int thresholdPercent = 150;

  /// Whether [requested] is strictly more than 150 % of [suggested].
  ///
  /// Always `false` when there is no positive suggestion: that situation is
  /// [isManualRequest]'s, and answering "yes, it exceeds the suggestion" about a
  /// suggestion of nothing would make the two rules report the same line twice.
  static bool isAboveSuggestionThreshold({
    required Quantity suggested,
    required Quantity requested,
  }) {
    if (!suggested.isPositive) return false;
    return requested.exceedsRatioOf(
      suggested,
      numerator: thresholdNumerator,
      denominator: thresholdDenominator,
    );
  }

  /// Whether this line has no system suggestion behind it — an item the branch
  /// head added by hand, or one whose rooms were all at or above par level.
  static bool isManualRequest(Quantity suggested) => !suggested.isPositive;

  /// Whether the line needs a reason before the document may be submitted.
  static bool requiresJustification({
    required Quantity suggested,
    required Quantity requested,
  }) {
    if (!requested.isPositive) return false;
    return isManualRequest(suggested) ||
        isAboveSuggestionThreshold(suggested: suggested, requested: requested);
  }

  /// Whether a note counts as a reason. Whitespace does not.
  static bool hasJustification(String? note) => (note ?? '').trim().isNotEmpty;

  /// The largest quantity that needs no justification, for the helper text under
  /// the input. `null` when there is no suggestion to derive one from.
  ///
  /// This is the *inclusive* bound — exactly 150 % is allowed — so it is the
  /// suggestion times 3 divided by 2, computed in milli-units by
  /// [Quantity.scaledBy] so no rounding happens on the way.
  static Quantity? justificationFreeCeiling(Quantity suggested) {
    if (!suggested.isPositive) return null;
    return suggested.scaledBy(
      numerator: thresholdNumerator,
      denominator: thresholdDenominator,
    );
  }

  /// The warning shown above a line that asks for more than 150 % of the
  /// suggestion (§24.3).
  static const String aboveThresholdWarning =
      'Jumlah yang diminta lebih dari 150% saran sistem. '
      'Catatan alasan wajib diisi.';

  /// The warning shown on a line the system did not suggest at all (§24.3).
  static const String manualRequestWarning =
      'Permintaan manual tanpa saran stok opname. '
      'Catatan alasan wajib diisi.';

  /// Which sentence a line should show, or `null` when it needs none.
  static String? warningFor({
    required Quantity suggested,
    required Quantity requested,
  }) {
    if (!requiresJustification(suggested: suggested, requested: requested)) {
      return null;
    }
    return isManualRequest(suggested)
        ? manualRequestWarning
        : aboveThresholdWarning;
  }
}
