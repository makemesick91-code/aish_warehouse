import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/operational_iso_week.dart';

/// The facts G-P1 is decided from, and nothing else.
///
/// A record of primitives rather than a domain model, so the rule can be
/// exercised without a database and so the same call answers "may this be picked"
/// on the form and "is this still valid" at submit.
typedef OpnameEligibilityFacts = ({
  String opnameId,
  String branchId,
  StockOpnameStatus status,
  int periodYear,
  int periodWeek,
});

/// G-P1 — which stock opnames a Purchase Request may rest on.
///
/// > PR **wajib** menautkan ≥ 1 stok opname berstatus `submitted`/`reviewed` dari
/// > **minggu berjalan atau minggu sebelumnya** (acuan tidak boleh kedaluwarsa
/// > > 2 minggu).
///
/// Four independent conditions, each of which is a different mistake:
///
/// * **Branch.** A count from another branch is not evidence about this one
///   (G-R2).
/// * **Status.** A `draft` has not left the nurse's hands, so nothing has been
///   handed over to base an order on (G-O4). `submitted` and `reviewed` are
///   equally acceptable — the branch head does not have to review a count before
///   ordering against it.
/// * **Age.** The current operational week or the one before it. Anything older
///   describes a shelf that has since been used.
/// * **Direction.** A week that has not started yet is not "recent", it is a
///   device with a wrong clock, and accepting it would let a bad clock extend the
///   window indefinitely.
///
/// The age comparison is the part that is easy to get wrong, and it is why this
/// policy speaks [OperationalIsoWeek] rather than two integers. `periodWeek >=
/// currentWeek - 1` looks equivalent and breaks every new year: the week before
/// `2026-W01` is `2025-W52` or `2025-W53`, so the subtraction produces a week
/// number that never existed. Distance is measured in days between the two weeks'
/// Mondays instead, which is exact by construction.
///
/// The clock is always injected — as a UTC instant the caller passes in — so a
/// test can sit on a year boundary without waiting for one (T-7).
abstract final class PurchaseRequestOpnameEligibilityPolicy {
  /// How many weeks back a reference may reach: the current week plus one.
  static const int allowedPreviousWeeks = 1;

  /// The operational ISO weeks a request created at [utcNow] may cite, newest
  /// first.
  ///
  /// This is also what the DAO turns into a SQL predicate: naming the periods
  /// explicitly keeps arithmetic on week numbers out of the database.
  static List<OperationalIsoWeek> eligiblePeriods(DateTime utcNow) =>
      OperationalIsoWeek.ofUtcInstant(
        utcNow,
      ).withPrevious(allowedPreviousWeeks);

  /// Whether [facts] describe a count [prBranchId] may cite at [utcNow].
  static bool isEligible({
    required OpnameEligibilityFacts facts,
    required String prBranchId,
    required DateTime utcNow,
  }) => denialFor(facts: facts, prBranchId: prBranchId, utcNow: utcNow) == null;

  /// Why [facts] may not be cited, or `null` when it may.
  static StockOpnameEligibilityDenial? denialFor({
    required OpnameEligibilityFacts facts,
    required String prBranchId,
    required DateTime utcNow,
  }) {
    if (facts.branchId != prBranchId) {
      return StockOpnameEligibilityDenial.otherBranch;
    }
    if (!facts.status.isPurchaseRequestReference) {
      return StockOpnameEligibilityDenial.notSubmitted;
    }

    final current = OperationalIsoWeek.ofUtcInstant(utcNow);
    final period = OperationalIsoWeek(
      year: facts.periodYear,
      week: facts.periodWeek,
    );
    final weeksAgo = current.weeksAfter(period);

    if (weeksAgo < 0) return StockOpnameEligibilityDenial.periodInFuture;
    if (weeksAgo > allowedPreviousWeeks) {
      return StockOpnameEligibilityDenial.periodTooOld;
    }
    return null;
  }

  /// The sentence shown for one refused reference.
  ///
  /// Deliberately *not* one message for every reason, unlike the read-access
  /// refusals: nothing is being withheld here. The branch head is looking at
  /// their own branch's counts and needs to know which rule to fix — pick a newer
  /// count, or wait for the nurse to send this one.
  static String messageFor({
    required StockOpnameEligibilityDenial reason,
    required String docNumber,
  }) => switch (reason) {
    StockOpnameEligibilityDenial.missing =>
      'Stok opname acuan tidak ditemukan.',
    StockOpnameEligibilityDenial.otherBranch =>
      'Stok opname $docNumber berada di cabang lain.',
    StockOpnameEligibilityDenial.notSubmitted =>
      'Stok opname $docNumber masih draft dan belum dapat dijadikan acuan.',
    StockOpnameEligibilityDenial.periodTooOld =>
      'Stok opname $docNumber sudah lebih dari satu minggu sebelum minggu '
          'berjalan, sehingga tidak dapat dijadikan acuan.',
    StockOpnameEligibilityDenial.periodInFuture =>
      'Stok opname $docNumber tercatat pada minggu yang belum berjalan. '
          'Periksa pengaturan waktu perangkat.',
  };
}
