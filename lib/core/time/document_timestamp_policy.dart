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
/// serialisation format can influence. Schema v5 repeats the decision for
/// `purchase_requests`: it carries four event timestamps and not one CHECK
/// comparing them. The database restricts itself to what it can state without
/// ambiguity — which timestamps a status must and must not carry.
///
/// This policy is **workflow-agnostic**. Every document type that has an ordered
/// pair of events states it here rather than growing its own comparison, which
/// is why the wrappers below read as a list of the transitions the application
/// knows about. Nothing here reads a clock: callers pass the instants they are
/// about to persist, which keeps the rule testable and keeps the injected clock
/// (`ReviewStockOpnameUseCase({clock})`, T-7) the single source of "now".
abstract final class DocumentTimestampPolicy {
  /// Asserts that [laterUtc] does not precede [earlierUtc].
  ///
  /// Equal instants are accepted: two transitions really can land on the same
  /// microsecond on a fast device, and there is nothing wrong with that
  /// document. Only a [laterUtc] that is genuinely earlier — by as little as one
  /// microsecond — is rejected.
  ///
  /// Throws [InvalidDocumentTimestampFailure] so the caller aborts *before*
  /// writing the new status; inside a transaction that rolls the whole thing
  /// back, ledger movements included.
  static void requireOrdered({
    required String documentId,
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
        documentId: documentId,
        earlierLabel: earlierLabel,
        earlierUtc: earlier,
        laterLabel: laterLabel,
        laterUtc: later,
      );
    }
  }

  /// The sentence shown when a device clock is behind the previous event (§8.3).
  static const String deviceClockBehindMessage =
      'Waktu perangkat lebih awal dari waktu pengiriman dokumen. '
      'Periksa pengaturan waktu perangkat.';

  /// Guards the review half of the Stok Opname workflow.
  ///
  /// [submittedAtUtc] is null only for a document that is not `submitted`,
  /// which the status guard has already rejected by the time this runs; the
  /// null case is therefore a no-op rather than a second error message about
  /// the same problem. Every wrapper below follows the same convention.
  static void requireReviewNotBeforeSubmit({
    required String documentId,
    required DateTime? submittedAtUtc,
    required DateTime reviewedAtUtc,
  }) {
    _requireAfter(
      documentId: documentId,
      earlierLabel: 'submitted_at',
      earlierUtc: submittedAtUtc,
      laterLabel: 'reviewed_at',
      laterUtc: reviewedAtUtc,
    );
  }

  /// `submitted → processing` on a Purchase Request.
  static void requireProcessingNotBeforeSubmit({
    required String documentId,
    required DateTime? submittedAtUtc,
    required DateTime processingAtUtc,
  }) {
    _requireAfter(
      documentId: documentId,
      earlierLabel: 'submitted_at',
      earlierUtc: submittedAtUtc,
      laterLabel: 'processing_at',
      laterUtc: processingAtUtc,
    );
  }

  /// `processing → rejected` on a Purchase Request.
  ///
  /// The rejection is ordered against `processing_at` rather than `submitted_at`
  /// because that is the event immediately before it; `processing_at` was itself
  /// already ordered against the submission when it was written, so the chain
  /// holds transitively without comparing every pair.
  static void requireRejectionNotBeforeProcessing({
    required String documentId,
    required DateTime? processingAtUtc,
    required DateTime rejectedAtUtc,
  }) {
    _requireAfter(
      documentId: documentId,
      earlierLabel: 'processing_at',
      earlierUtc: processingAtUtc,
      laterLabel: 'rejected_at',
      laterUtc: rejectedAtUtc,
    );
  }

  /// `draft → cancelled` or `submitted → cancelled` on a Purchase Request.
  ///
  /// A draft has no `submitted_at`, and that is the legitimate null case rather
  /// than a status the guard has ruled out: cancelling a draft is ordered
  /// against nothing, so the check simply does not apply.
  static void requireCancellationNotBeforeSubmit({
    required String documentId,
    required DateTime? submittedAtUtc,
    required DateTime cancelledAtUtc,
  }) {
    _requireAfter(
      documentId: documentId,
      earlierLabel: 'submitted_at',
      earlierUtc: submittedAtUtc,
      laterLabel: 'cancelled_at',
      laterUtc: cancelledAtUtc,
    );
  }

  static void _requireAfter({
    required String documentId,
    required String earlierLabel,
    required DateTime? earlierUtc,
    required String laterLabel,
    required DateTime laterUtc,
  }) {
    if (earlierUtc == null) return;
    requireOrdered(
      documentId: documentId,
      earlierLabel: earlierLabel,
      earlierUtc: earlierUtc,
      laterLabel: laterLabel,
      laterUtc: laterUtc,
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
