import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';

/// The reasons the checklist offers for refusing a position (G-G4, spec §4.2).
///
/// Presets rather than free text alone, because a reason that is typed differently
/// on every receipt cannot be counted, and the warehouse's return list is exactly a
/// count of *why*. The stored value is still plain text — see [composeReason] — so
/// the audit trail survives a preset being renamed and the sync backend never has
/// to know this enum exists.
enum GoodReceiptRejectReasonPreset {
  damaged('Rusak'),
  wrongItem('Salah barang'),
  expired('Kedaluwarsa / terlalu dekat ED'),
  notOrdered('Tidak dipesan'),
  other('Lainnya');

  const GoodReceiptRejectReasonPreset(this.label);

  /// The Indonesian sentence shown on the sheet and stored as the reason.
  final String label;

  /// *Lainnya* explains nothing on its own, so it demands a written detail
  /// (§15). Every other preset is already a reason.
  bool get requiresDetail => this == other;

  /// The preset G-E5 forces on an expired or nearly expired batch.
  static const GoodReceiptRejectReasonPreset expiryPreset = expired;
}

/// What a decision on one position may and may not say (G-G2/G-G3/G-G4).
///
/// A pure, synchronous policy so the checklist, the use cases and the tests all ask
/// the same question. Every comparison is exact fixed-point integer arithmetic on
/// milli-units (Q-2): a shipment of `2.375` received as `1.5` is short by exactly
/// `0.875`, with no residue to accumulate over a hundred receipts.
///
/// It is deliberately **not** the authority. The numbers a form holds are a
/// snapshot; what decides a write is this policy applied inside the posting
/// transaction, plus the CHECK constraints underneath it.
abstract final class GoodReceiptLineDecisionPolicy {
  /// G-G3 — `0 ≤ received_qty ≤ shipped_qty`.
  ///
  /// Zero is valid and that is not an oversight: a position may arrive empty —
  /// the box was on the manifest and not in the van — and the honest record is
  /// `checked` with nothing received, which produces a full-shipment discrepancy
  /// and no ledger movement at all. Refusing it would push the branch head towards
  /// `rejected`, which claims the goods are on their counter waiting to go back.
  static bool isValidReceivedQty({
    required Quantity shippedQty,
    required Quantity receivedQty,
  }) => !receivedQty.isNegative && receivedQty <= shippedQty;

  static bool isNegative(Quantity receivedQty) => receivedQty.isNegative;

  static bool exceedsShipped({
    required Quantity shippedQty,
    required Quantity receivedQty,
  }) => receivedQty > shippedQty;

  /// What did not arrive. Never negative for a valid decision.
  static Quantity discrepancyOf({
    required Quantity shippedQty,
    required Quantity receivedQty,
  }) => shippedQty - receivedQty;

  /// Whether an accepted position arrived short (G-G3).
  static bool hasShortage({
    required Quantity shippedQty,
    required Quantity receivedQty,
  }) => discrepancyOf(
    shippedQty: shippedQty,
    receivedQty: receivedQty,
  ).isPositive;

  /// The quantity a refused position accepts: nothing (G-G4/G-G5).
  ///
  /// Named rather than written as a literal `0` at each call site, because "a
  /// rejected line receives nothing" is a rule and the three writers that apply it
  /// should be reading it from one place.
  static Quantity get rejectedReceivedQty => Quantity.zero();

  /// Whether a position may add stock to the branch store when the receipt posts
  /// (G-G5).
  ///
  /// Both halves matter: only `checked` counts, and only a positive quantity has
  /// anything to record. A `checked` zero writes no movement — the ledger records
  /// changes, not confirmations (G-A1).
  static bool addsStock({
    required GoodReceiptLineStatus lineStatus,
    required Quantity receivedQty,
  }) => lineStatus.addsStock && receivedQty.isPositive;

  /// A non-blank reason, or `null` when there was nothing but whitespace.
  static String? normalizeReason(String? reason) {
    final trimmed = (reason ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// G-G4 — whether [reason] is something an audit could act on.
  static bool isValidRejectReason(String? reason) =>
      normalizeReason(reason) != null;

  /// The text stored for a refusal: the preset, plus the written detail when there
  /// is one.
  ///
  /// *Lainnya* stores only the detail, because *"Lainnya — kemasan penyok"* reads
  /// as a category nobody chose; every other preset keeps its label and appends the
  /// detail after an en dash so both survive into the warehouse's queue.
  ///
  /// Returns `null` when the result would be blank, which is what
  /// [isValidRejectReason] then refuses — a preset that demands a detail cannot be
  /// stored without one.
  static String? composeReason({
    required GoodReceiptRejectReasonPreset preset,
    String? detail,
  }) {
    final trimmed = normalizeReason(detail);
    if (preset.requiresDetail) return trimmed;
    return trimmed == null ? preset.label : '${preset.label} — $trimmed';
  }

  /// G-G2 — whether every position has been decided.
  ///
  /// An empty receipt answers `false`: there is nothing to have decided, and
  /// treating that as "all decided" would let a corrupt document post.
  static bool allDecided(Iterable<GoodReceiptLineStatus> statuses) {
    var any = false;
    for (final status in statuses) {
      any = true;
      if (!status.isDecided) return false;
    }
    return any;
  }

  static int pendingCount(Iterable<GoodReceiptLineStatus> statuses) =>
      statuses.where((status) => status.isPending).length;

  /// Whether the decision `from → to` is one the checklist may make.
  ///
  /// Every combination is allowed while the parent receipt is `checking`, including
  /// back to `pending`: a branch head who ticked the wrong row must be able to
  /// undo it, and G-G2 is about the state at *posting* time rather than about the
  /// order the rows were touched in. What freezes a decision is the parent's
  /// status, which this policy deliberately does not see — the caller checks that
  /// separately so the two rules stay one each.
  static bool canRevise({
    required GoodReceiptLineStatus from,
    required GoodReceiptLineStatus to,
  }) => from != to || to.isChecked;
}
