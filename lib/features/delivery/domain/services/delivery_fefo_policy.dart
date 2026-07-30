import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../models/delivery_models.dart';
import 'delivery_expiry_policy.dart';

/// One batch that was passed over in favour of a younger one.
class FefoViolation {
  const FefoViolation({
    required this.selectedBatchId,
    required this.selectedBatchNo,
    required this.selectedExpiryDate,
    required this.skippedBatchId,
    required this.skippedBatchNo,
    required this.skippedExpiryDate,
    required this.skippedAvailableQty,
  });

  /// The younger batch the officer picked from.
  final String selectedBatchId;
  final String selectedBatchNo;
  final DateTime selectedExpiryDate;

  /// The nearest-expiry batch that still had stock and was left on the shelf —
  /// the one fact that makes the warning actionable.
  final String skippedBatchId;
  final String skippedBatchNo;
  final DateTime skippedExpiryDate;
  final Quantity skippedAvailableQty;

  @override
  String toString() =>
      'FefoViolation(dipilih $selectedBatchNo '
      '(${DateOnly.formatIso(selectedExpiryDate)}), '
      'dilewati $skippedBatchNo '
      '(${DateOnly.formatIso(skippedExpiryDate)}))';
}

/// G-E3 — First-Expired-First-Out, both as a suggestion and as a check.
///
/// *"Sistem otomatis menyarankan batch dengan ED terdekat lebih dulu. Memilih
/// batch yang lebih muda dari saran FEFO memunculkan peringatan + catatan
/// wajib."*
///
/// The policy is pure and synchronous: it is handed the batches the warehouse
/// currently holds and answers two questions about them. That is what lets the
/// form, the allocation use case, the ship path and the tests all ask the *same*
/// question — and, crucially, lets the ship path re-ask it against balances read
/// inside its own transaction rather than trusting what a form computed minutes
/// earlier.
///
/// ### Why the check is not "compare against the canonical allocation"
///
/// The obvious implementation — build the FEFO answer, diff it against what the
/// officer chose, warn on any difference — is wrong in a way that shows up
/// immediately in real stock. Two batches with the **same** expiry date are
/// equally correct FEFO choices, and the canonical allocation has to pick one of
/// them (by batch number, then by id, so it is deterministic). An officer who
/// picks the other has violated nothing, yet the diff would demand a written
/// reason. The same applies whenever a request can be satisfied several equally
/// compliant ways.
///
/// So the rule is stated directly instead: a selection violates FEFO when it
/// takes from a batch while **passing over stock that expires strictly sooner**.
/// [violations] finds exactly those pairs. Equal expiry dates are never a
/// violation, because neither batch expires sooner than the other.
abstract final class DeliveryFefoPolicy {
  /// The canonical FEFO allocation of [qty] across [candidates].
  ///
  /// Only positive, non-expired balances take part; batches are consumed in
  /// ascending expiry order and the allocation may span several of them. The
  /// ordering is `(expiry_date, batch_no, batch_id)`, so the answer is identical
  /// on two devices holding the same stock.
  ///
  /// Returns `null` when the usable stock is not enough — never a partial
  /// allocation. A half-filled suggestion looks like an answer and is not one:
  /// the officer would have to notice the shortfall themselves, and the
  /// difference between "this is what FEFO proposes" and "this is as much as
  /// there is" is exactly what they need told.
  ///
  /// Integer milli-unit arithmetic throughout: taking `min(remaining, on hand)`
  /// from each batch in turn means the allocations always sum back to exactly
  /// [qty], even when the request splits (`1.5 → 1 + 0.5`).
  static List<DeliveryAllocation>? allocate({
    required String prLineId,
    required String itemId,
    required List<DeliveryBatchCandidate> candidates,
    required Quantity qty,
    required DateTime nowUtc,
  }) {
    if (!qty.isPositive) return const <DeliveryAllocation>[];

    final usable = DeliveryExpiryPolicy.usableCandidates(
      candidates: candidates,
      nowUtc: nowUtc,
    );
    final available = Quantity.sum(
      usable.map((candidate) => candidate.availableQty),
    );
    if (available < qty) return null;

    final allocations = <DeliveryAllocation>[];
    var remaining = qty;
    for (final candidate in usable) {
      if (remaining.isZero) break;
      final take = Quantity.min(remaining, candidate.availableQty);
      allocations.add(
        DeliveryAllocation(
          prLineId: prLineId,
          itemId: itemId,
          batchId: candidate.batchId,
          batchNo: candidate.batchNo,
          expiryDate: candidate.expiryDate,
          qty: take,
          nearExpiryConfirmed: false,
        ),
      );
      remaining -= take;
    }
    return List<DeliveryAllocation>.unmodifiable(allocations);
  }

  /// Every FEFO violation in [selection], one per younger batch that was taken
  /// while older stock was left behind.
  ///
  /// [selection] is the allocations of **one** requested position: the rule is
  /// about how a single line's quantity was sourced, and mixing two items' or two
  /// positions' choices together would compare batches that never competed.
  ///
  /// [candidates] must be the batches and balances as they are *now*. The same
  /// selection can be compliant at 09:00 and a violation at 11:00 — an older batch
  /// that was empty when the form opened may have been restocked since — which is
  /// precisely why the ship path calls this again with fresh numbers instead of
  /// trusting the reason (or the absence of one) the form stored.
  ///
  /// Expired batches take no part on either side: they cannot be selected at all
  /// (G-E4 refuses them first), and stock that may not legally move is not stock
  /// that was "passed over".
  ///
  /// For each violation the *nearest-expiry* skipped batch is reported, because
  /// that is the one the officer should have taken and the one a warning should
  /// name.
  static List<FefoViolation> violations({
    required List<DeliveryBatchCandidate> candidates,
    required List<DeliveryAllocation> selection,
    required DateTime nowUtc,
  }) {
    final usable = DeliveryExpiryPolicy.usableCandidates(
      candidates: candidates,
      nowUtc: nowUtc,
    );
    if (usable.isEmpty) return const <FefoViolation>[];

    final takenByBatch = <String, Quantity>{};
    for (final allocation in selection) {
      final batchId = allocation.batchId;
      if (batchId == null || !allocation.qty.isPositive) continue;
      takenByBatch[batchId] =
          (takenByBatch[batchId] ?? Quantity.zero()) + allocation.qty;
    }
    if (takenByBatch.isEmpty) return const <FefoViolation>[];

    final result = <FefoViolation>[];
    for (final younger in usable) {
      final taken = takenByBatch[younger.batchId] ?? Quantity.zero();
      if (!taken.isPositive) continue;

      // `usable` is already ordered nearest expiry first, so the first older
      // batch with stock left is the nearest-expiry one — exactly the batch the
      // warning should name.
      for (final older in usable) {
        if (!DateOnly.isBeforeDate(older.expiryDate, younger.expiryDate)) {
          // Same expiry date, or later: neither is "sooner", so passing it over
          // is not a FEFO violation. This is the tie case a naive diff against
          // the canonical allocation gets wrong.
          continue;
        }
        final olderTaken = takenByBatch[older.batchId] ?? Quantity.zero();
        final untouched = older.availableQty - olderTaken;
        if (!untouched.isPositive) continue;

        result.add(
          FefoViolation(
            selectedBatchId: younger.batchId,
            selectedBatchNo: younger.batchNo,
            selectedExpiryDate: younger.expiryDate,
            skippedBatchId: older.batchId,
            skippedBatchNo: older.batchNo,
            skippedExpiryDate: older.expiryDate,
            skippedAvailableQty: untouched,
          ),
        );
        break;
      }
    }
    return List<FefoViolation>.unmodifiable(result);
  }

  /// Whether [selection] violates FEFO at all.
  static bool isOverride({
    required List<DeliveryBatchCandidate> candidates,
    required List<DeliveryAllocation> selection,
    required DateTime nowUtc,
  }) => violations(
    candidates: candidates,
    selection: selection,
    nowUtc: nowUtc,
  ).isNotEmpty;

  /// Whether a stored override reason is acceptable.
  ///
  /// Whitespace is not a reason, and the database CHECK says the same thing with
  /// `trim(...) <> ''` so a hand-written UPDATE cannot slip one past either.
  static bool hasValidReason(String? reason) =>
      (reason ?? '').trim().isNotEmpty;
}
