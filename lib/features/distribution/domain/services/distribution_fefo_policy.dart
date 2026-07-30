import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../models/distribution_models.dart';
import 'distribution_expiry_policy.dart';

/// One batch that was passed over in favour of a younger one.
class DistributionFefoViolation {
  const DistributionFefoViolation({
    required this.itemId,
    required this.selectedBatchId,
    required this.selectedBatchNo,
    required this.selectedExpiryDate,
    required this.skippedBatchId,
    required this.skippedBatchNo,
    required this.skippedExpiryDate,
    required this.skippedAvailableQty,
  });

  /// The item the violation is about. Carried because compliance is judged per item
  /// across the whole document (§16), so a failure message has to be able to name
  /// which item it is talking about.
  final String itemId;

  /// The younger batch the branch head drew from.
  final String selectedBatchId;
  final String selectedBatchNo;
  final DateTime selectedExpiryDate;

  /// The nearest-expiry batch that still had stock and was left on the shelf — the
  /// one fact that makes the warning actionable.
  final String skippedBatchId;
  final String skippedBatchNo;
  final DateTime skippedExpiryDate;
  final Quantity skippedAvailableQty;

  @override
  String toString() =>
      'DistributionFefoViolation(dipilih $selectedBatchNo '
      '(${DateOnly.formatIso(selectedExpiryDate)}), '
      'dilewati $skippedBatchNo '
      '(${DateOnly.formatIso(skippedExpiryDate)}))';
}

/// G-E3 — First-Expired-First-Out for a distribution, both as a suggestion and as a
/// check.
///
/// *"Saat Kepala Cabang membuat distribusi, sistem otomatis menyarankan batch dengan
/// ED terdekat lebih dulu. Memilih batch yang lebih muda dari saran FEFO memunculkan
/// peringatan + catatan wajib."*
///
/// The policy is pure and synchronous: it is handed the batches the **branch store**
/// currently holds and answers questions about them. That is what lets the form, the
/// add path, the manual-override path, the posting path and the tests all ask the
/// *same* question — and, crucially, lets the posting path re-ask it against balances
/// read inside its own transaction rather than trusting what a form computed minutes
/// earlier.
///
/// ### The source is the branch store, not the warehouse
///
/// The same rule the Delivery Order applies, applied to a different shelf. A
/// distribution never reads Warehouse Pusat stock: the goods it moves are already at
/// the branch, and asking the central warehouse what it holds would produce an
/// allocation against quantities the branch does not have.
///
/// ### Compliance is judged per item, across every room (§16)
///
/// This is the one place the distribution rule is genuinely stricter than the
/// shipment's. A Delivery Order allocates one requested position at a time, so
/// "one line's selection" is the natural unit. A distribution targets several rooms
/// at once, and the batches live in one store — so evaluating each room in isolation
/// would let an old batch be skipped simply by splitting the quantity:
///
/// ```
/// store: B-OLD (ED sooner) = 2,  B-NEW (ED later) = 4
/// R1 ← 2 from B-NEW      "only 2, B-OLD has 2 left"   → looks like a violation
/// R2 ← 2 from B-NEW      "only 2, B-OLD has 2 left"   → looks like a violation
/// ```
///
/// Per room, each half is a violation and would be caught. But invert it:
///
/// ```
/// R1 ← 2 from B-OLD  (compliant on its own)
/// R2 ← 2 from B-NEW  (B-OLD is empty *after R1 took it*, so compliant on its own)
/// ```
///
/// …and a per-room check that did not know about R1's draw would call R2's choice a
/// violation, demanding a written reason for a perfectly correct allocation. So
/// [violations] is handed **every allocation of one item on the document** and sums
/// what each batch gives up before deciding. Which room a batch's quantity ends up
/// in is a separate, deterministic assignment; FEFO compliance is an aggregate
/// property of the item.
///
/// ### Why the check is not "compare against the canonical allocation"
///
/// The obvious implementation — build the FEFO answer, diff it against what was
/// chosen, warn on any difference — is wrong in a way that shows up immediately in
/// real stock. Two batches with the **same** expiry date are equally correct FEFO
/// choices, and the canonical allocation has to pick one of them (by batch number,
/// then by id, so it is deterministic). Choosing the other has violated nothing, yet
/// the diff would demand a written reason.
///
/// So the rule is stated directly instead: a selection violates FEFO when it takes
/// from a batch while **passing over stock that expires strictly sooner**.
/// [violations] finds exactly those pairs. Equal expiry dates are never a violation,
/// because neither batch expires sooner than the other — batch numbers and ids are
/// used for *determinism*, never to claim one batch is younger.
abstract final class DistributionFefoPolicy {
  /// The canonical FEFO allocation of [qty] for one room and item.
  ///
  /// Only positive, non-expired balances take part; batches are consumed in ascending
  /// expiry order and the allocation may span several of them. The ordering is
  /// `(expiry_date, batch_no, batch_id)`, so the answer is identical on two devices
  /// holding the same stock.
  ///
  /// [candidates] must already be **net of what the rest of the document takes** from
  /// the same batches — see [remainingCandidates]. The store does not hold a batch
  /// twice, and an allocator that ignored the document's own earlier draws would
  /// happily propose the same 5 ampoules to three rooms.
  ///
  /// Returns `null` when the usable stock is not enough — never a partial allocation.
  /// A half-filled suggestion looks like an answer and is not one: the branch head
  /// would have to notice the shortfall themselves, and the difference between "this
  /// is what FEFO proposes" and "this is as much as there is" is exactly what they
  /// need told (§16.7).
  ///
  /// Integer milli-unit arithmetic throughout: taking `min(remaining, on hand)` from
  /// each batch in turn means the allocations always sum back to exactly [qty], even
  /// when the request splits (`1.5 → 1 + 0.5`).
  static List<DistributionAllocation>? allocate({
    required String roomId,
    required String itemId,
    required List<DistributionBatchCandidate> candidates,
    required Quantity qty,
    required DateTime nowUtc,
  }) {
    if (!qty.isPositive) return const <DistributionAllocation>[];

    final usable = DistributionExpiryPolicy.usableCandidates(
      candidates: candidates,
      nowUtc: nowUtc,
    );
    final available = Quantity.sum(
      usable.map((candidate) => candidate.availableQty),
    );
    if (available < qty) return null;

    final allocations = <DistributionAllocation>[];
    var remaining = qty;
    for (final candidate in usable) {
      if (remaining.isZero) break;
      final take = Quantity.min(remaining, candidate.availableQty);
      allocations.add(
        DistributionAllocation(
          roomId: roomId,
          itemId: itemId,
          batchId: candidate.batchId,
          batchNo: candidate.batchNo,
          expiryDate: candidate.expiryDate,
          qty: take,
        ),
      );
      remaining -= take;
    }
    return List<DistributionAllocation>.unmodifiable(allocations);
  }

  /// [candidates] with each batch reduced by what [alreadyTaken] draws from it.
  ///
  /// The bridge between a per-position allocator and a per-document rule: a second
  /// room may only be offered what the first left behind (§16/§18). Batches that end
  /// up empty are dropped, and the result keeps the canonical FEFO order.
  ///
  /// [alreadyTaken] is keyed by batch id. A `null` batch — an item without expiry —
  /// has no entry here by construction: there is no batch to net out.
  static List<DistributionBatchCandidate> remainingCandidates({
    required List<DistributionBatchCandidate> candidates,
    required Map<String, Quantity> alreadyTaken,
  }) {
    final remaining = candidates
        .map(
          (candidate) => candidate.minus(
            alreadyTaken[candidate.batchId] ?? Quantity.zero(),
          ),
        )
        .where((candidate) => candidate.availableQty.isPositive)
        .toList();
    DistributionExpiryPolicy.sortForFefo(remaining);
    return List<DistributionBatchCandidate>.unmodifiable(remaining);
  }

  /// How much [allocations] draws from each batch, keyed by batch id.
  ///
  /// Allocations without a batch contribute nothing: an item without expiry has one
  /// balance and no FEFO order to violate.
  static Map<String, Quantity> takenByBatch(
    Iterable<DistributionAllocation> allocations,
  ) {
    final totals = <String, Quantity>{};
    for (final allocation in allocations) {
      final batchId = allocation.batchId;
      if (batchId == null || !allocation.qty.isPositive) continue;
      totals[batchId] = (totals[batchId] ?? Quantity.zero()) + allocation.qty;
    }
    return totals;
  }

  /// Every FEFO violation in [selection], one per younger batch that was taken while
  /// older stock was left behind.
  ///
  /// [selection] must be **every allocation of one item on the document**, across all
  /// rooms — see the class note. Mixing two items' choices together would compare
  /// batches that never competed; splitting one item's choices per room is the hole
  /// §16 closes.
  ///
  /// [candidates] must be the batches and balances as they are *now*, **gross** — the
  /// store's actual holdings, not netted by this document. The same selection can be
  /// compliant at 09:00 and a violation at 11:00 — an older batch that was empty when
  /// the form opened may have been restocked since — which is precisely why the
  /// posting path calls this again with fresh numbers instead of trusting the reason
  /// (or the absence of one) the draft stored.
  ///
  /// Expired batches take no part on either side: they cannot be selected at all
  /// (G-E4 refuses them first), and stock that may not legally move is not stock that
  /// was "passed over".
  ///
  /// For each violation the *nearest-expiry* skipped batch is reported, because that
  /// is the one that should have been taken and the one a warning should name.
  static List<DistributionFefoViolation> violations({
    required String itemId,
    required List<DistributionBatchCandidate> candidates,
    required List<DistributionAllocation> selection,
    required DateTime nowUtc,
  }) {
    final usable = DistributionExpiryPolicy.usableCandidates(
      candidates: candidates,
      nowUtc: nowUtc,
    );
    if (usable.isEmpty) return const <DistributionFefoViolation>[];

    // Summed across every room the item goes to — the aggregate §16 requires.
    final taken = takenByBatch(selection);
    if (taken.isEmpty) return const <DistributionFefoViolation>[];

    final result = <DistributionFefoViolation>[];
    for (final younger in usable) {
      final drawn = taken[younger.batchId] ?? Quantity.zero();
      if (!drawn.isPositive) continue;

      // `usable` is already ordered nearest expiry first, so the first older batch
      // with stock left is the nearest-expiry one — exactly the batch the warning
      // should name.
      for (final older in usable) {
        if (!DateOnly.isBeforeDate(older.expiryDate, younger.expiryDate)) {
          // Same expiry date, or later: neither is "sooner", so passing it over is
          // not a FEFO violation. This is the tie case a naive diff against the
          // canonical allocation gets wrong.
          continue;
        }
        final olderTaken = taken[older.batchId] ?? Quantity.zero();
        final untouched = older.availableQty - olderTaken;
        if (!untouched.isPositive) continue;

        result.add(
          DistributionFefoViolation(
            itemId: itemId,
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
    return List<DistributionFefoViolation>.unmodifiable(result);
  }

  /// Whether [selection] violates FEFO at all.
  static bool isOverride({
    required String itemId,
    required List<DistributionBatchCandidate> candidates,
    required List<DistributionAllocation> selection,
    required DateTime nowUtc,
  }) => violations(
    itemId: itemId,
    candidates: candidates,
    selection: selection,
    nowUtc: nowUtc,
  ).isNotEmpty;

  /// The batch ids in [selection] that a violation names as the *younger* side —
  /// the allocations that need a written reason.
  ///
  /// Returned rather than derived by each caller, because "which lines does the
  /// reason belong on" and "is there a violation" have to agree: a document that
  /// stores the reason on the wrong line has an audit trail pointing at a decision
  /// nobody made.
  static Set<String> overriddenBatchIds({
    required String itemId,
    required List<DistributionBatchCandidate> candidates,
    required List<DistributionAllocation> selection,
    required DateTime nowUtc,
  }) => violations(
    itemId: itemId,
    candidates: candidates,
    selection: selection,
    nowUtc: nowUtc,
  ).map((violation) => violation.selectedBatchId).toSet();

  /// Whether a stored override reason is acceptable.
  ///
  /// Whitespace is not a reason. Dart's `String.trim()` strips every kind of Unicode
  /// whitespace; the database CHECK says the same thing with `trim(...) <> ''`, which
  /// in SQLite strips **spaces only** — so this is the authority and the CHECK is the
  /// floor underneath it, not the other way round.
  static bool hasValidReason(String? reason) =>
      (reason ?? '').trim().isNotEmpty;

  /// The stored form of [reason]: trimmed, or `null` when it says nothing.
  ///
  /// One place decides what an empty reason is, so a line can never carry `"  "` and
  /// look like it has a justification.
  static String? normalizeReason(String? reason) {
    final trimmed = (reason ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
