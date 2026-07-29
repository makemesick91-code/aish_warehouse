import '../errors/failures.dart';

/// Where the ordering of document timestamps is decided (spec §8, T-1).
///
/// Until schema v4 the database also held
/// `CHECK (reviewed_at IS NULL OR submitted_at IS NULL OR reviewed_at >= submitted_at)`.
/// That constraint was wrong in a way that only shows up in production data:
/// timestamps are stored as ISO-8601 **TEXT**, so `>=` is a lexical string
/// comparison. Two instants written in different but equally valid ISO forms —
/// `2026-07-29T02:00:00.000Z` against `2026-07-29T02:00:00.000000Z`, or a
/// `+08:00` suffix against a `Z` one — compare by their characters rather than
/// by the moments they denote. The constraint could therefore both accept an
/// out-of-order pair and reject a correct one, depending on nothing more than
/// how the value happened to be serialised.
///
/// Ordering is a domain rule, so it is decided here, on UTC [DateTime]s, by
/// [DateTime.isBefore] — an instant comparison down to the microsecond that no
/// serialisation format can influence. The database keeps enforcing what it can
/// state without ambiguity: which timestamps must be present or absent for each
/// status.
///
/// Nothing here reads a clock. Callers pass the instants they are about to
/// persist, which keeps the rule testable and keeps the injected clock
/// (`ReviewStockOpnameUseCase({clock})`, T-7) the single source of "now".
abstract final class DocumentTimestampPolicy {
  /// Asserts that [laterUtc] does not precede [earlierUtc].
  ///
  /// Equal instants are accepted: a submit and a review really can land on the
  /// same microsecond on a fast device, and there is nothing wrong with that
  /// document. Only a [laterUtc] that is genuinely earlier — by as little as one
  /// microsecond — is rejected.
  ///
  /// Throws [InvalidDocumentTimestampFailure] so the caller aborts *before*
  /// writing the final status; inside a review that rolls the whole transaction
  /// back, movements included.
  static void requireOrdered({
    required String opnameId,
    required String earlierLabel,
    required DateTime earlierUtc,
    required String laterLabel,
    required DateTime laterUtc,
    required String message,
  }) {
    final earlier = _requireUtc(earlierUtc, earlierLabel);
    final later = _requireUtc(laterUtc, laterLabel);

    if (later.isBefore(earlier)) {
      throw InvalidDocumentTimestampFailure(
        message,
        opnameId: opnameId,
        earlierLabel: earlierLabel,
        earlierUtc: earlier,
        laterLabel: laterLabel,
        laterUtc: later,
      );
    }
  }

  /// The sentence shown when a device clock is behind the submission (§8.3).
  static const String deviceClockBehindMessage =
      'Waktu perangkat lebih awal dari waktu pengiriman dokumen. '
      'Periksa pengaturan waktu perangkat.';

  /// Guards the review half of the workflow.
  ///
  /// [submittedAtUtc] is null only for a document that is not `submitted`,
  /// which the status guard has already rejected by the time this runs; the
  /// null case is therefore a no-op rather than a second error message about
  /// the same problem.
  static void requireReviewNotBeforeSubmit({
    required String opnameId,
    required DateTime? submittedAtUtc,
    required DateTime reviewedAtUtc,
  }) {
    if (submittedAtUtc == null) return;
    requireOrdered(
      opnameId: opnameId,
      earlierLabel: 'submitted_at',
      earlierUtc: submittedAtUtc,
      laterLabel: 'reviewed_at',
      laterUtc: reviewedAtUtc,
      message: deviceClockBehindMessage,
    );
  }

  /// Persisted instants are UTC (T-1). A non-UTC value here would mean a caller
  /// forgot `.toUtc()`, and comparing it as-is would silently compare wall
  /// clocks from two different zones — exactly the class of bug this policy
  /// exists to remove. Converting preserves the instant.
  static DateTime _requireUtc(DateTime value, String label) {
    assert(value.isUtc, '$label must be a UTC instant (T-1), got $value');
    return value.isUtc ? value : value.toUtc();
  }
}
