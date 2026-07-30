import '../../../../core/quantity/quantity.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';

/// One shelf position: a location, an item and — for goods with expiry — a batch.
///
/// The key every ledger-derived figure is bucketed by. A `null` [batchId] is a real
/// key rather than a missing one: an item without expiry has exactly one position
/// per location (G-E2), and collapsing it into the batched case is how a report
/// starts double-counting.
class LedgerPositionKey {
  const LedgerPositionKey({
    required this.locationId,
    required this.itemId,
    required this.batchId,
  });

  final String locationId;
  final String itemId;
  final String? batchId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerPositionKey &&
          other.locationId == locationId &&
          other.itemId == itemId &&
          other.batchId == batchId);

  @override
  int get hashCode => Object.hash(locationId, itemId, batchId);

  @override
  String toString() => 'LedgerPositionKey($locationId/$itemId/$batchId)';
}

/// A running balance that went below zero at some point in history.
///
/// Reported rather than clamped. G-A2 keeps live balances non-negative, so a
/// negative running total means either a corrupt ledger or a reversal posted out of
/// order — both of which an auditor must be told about. Silently flooring it at zero
/// would produce a column of numbers that looks fine and reconciles against nothing
/// (§18).
class LedgerIntegrityWarning {
  const LedgerIntegrityWarning({
    required this.key,
    required this.movementId,
    required this.balance,
  });

  final LedgerPositionKey key;
  final String movementId;
  final Quantity balance;

  String get message =>
      'Saldo historis negatif (${balance.format()}) terdeteksi pada '
      'pergerakan $movementId. Periksa integritas ledger.';
}

/// Balances computed **from `stock_movements` and nothing else** (G-L4).
///
/// ### Why a report may not read `stock_balances`
///
/// That table is a cache the posting service maintains (§2.2), and a cached number
/// is one nobody can trace to an event. G-L4 says report figures come from the
/// ledger so that every quantity on an exported page can be reconciled against the
/// rows that produced it — which is the entire point of exporting it. An
/// architecture test asserts that neither this file, the reporting DAO nor the
/// reporting repository so much as mentions `stock_balances` or `qty_on_hand`.
///
/// ### Determinism, and why the tie-break is not decorative
///
/// Every method here sorts `createdAtUtc ASC, id ASC` before folding. The second key
/// is load-bearing: two movements posted inside one transaction share a timestamp to
/// the microsecond, and a sort on time alone leaves their order to whatever the
/// database happened to return. The *final* balance would be identical either way —
/// addition commutes — but a Kartu Stok's **running** balance column would differ
/// between two runs of the same report, which is the one thing an auditor is
/// entitled to assume cannot happen.
///
/// ### Transfers are signed twice, once per side
///
/// A movement with both a source and a destination debits one shelf and credits
/// another. This engine therefore signs it separately for each location
/// ([ReportLedgerMovement.signedDeltaFor]) rather than netting it into one row, which
/// is what lets a `branch_all` report show the Gudang Cabang going down and the room
/// going up instead of a branch total in which the distribution vanished (§21).
///
/// Everything here is a pure function of its inputs: no clock, no database, no I/O.
abstract final class LedgerBalanceEngine {
  /// Sorts a movement list into the canonical order every fold below relies on.
  static List<ReportLedgerMovement> sorted(
    Iterable<ReportLedgerMovement> movements,
  ) {
    final ordered = movements.toList()
      ..sort((a, b) {
        final byTime = a.createdAtUtc.compareTo(b.createdAtUtc);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return List.unmodifiable(ordered);
  }

  /// Balance per position at [cutoffExclusiveUtc], counting every movement stamped
  /// strictly before it.
  ///
  /// Exclusive rather than inclusive because that is what a half-open period window
  /// means (§15): *"as of 30 Jul"* is *"everything up to the first instant of 31
  /// Jul"*, and a movement stamped exactly on the boundary belongs to the next day.
  ///
  /// Positions that net to zero are **kept** in the result. Whether to show them is
  /// the caller's decision — the Stok Saat Ini report drops them (§21), while an
  /// expiry report needs to distinguish "batch is finished" from "batch was never
  /// here".
  static Map<LedgerPositionKey, Quantity> balancesAsOf({
    required Iterable<ReportLedgerMovement> movements,
    required Set<String> locationIds,
    required DateTime cutoffExclusiveUtc,
  }) {
    final balances = <LedgerPositionKey, Quantity>{};
    for (final movement in sorted(movements)) {
      if (!movement.createdAtUtc.isBefore(cutoffExclusiveUtc)) continue;
      for (final locationId in locationIds) {
        if (!movement.touches(locationId)) continue;
        final key = LedgerPositionKey(
          locationId: locationId,
          itemId: movement.itemId,
          batchId: movement.batchId,
        );
        balances[key] =
            (balances[key] ?? Quantity.zero()) +
            movement.signedDeltaFor(locationId);
      }
    }
    return balances;
  }

  /// The balance of one position immediately before [startUtc] — a Kartu Stok's
  /// *saldo awal* (§22).
  ///
  /// Reads the whole ledger before the period rather than a stored opening figure,
  /// because there is no stored opening figure that G-L4 would allow it to read.
  static Quantity openingBalance({
    required Iterable<ReportLedgerMovement> movements,
    required String locationId,
    required String itemId,
    String? batchId,
    required DateTime startUtc,
  }) {
    var balance = Quantity.zero();
    for (final movement in sorted(movements)) {
      if (!movement.createdAtUtc.isBefore(startUtc)) continue;
      if (movement.itemId != itemId) continue;
      if (batchId != null && movement.batchId != batchId) continue;
      if (!movement.touches(locationId)) continue;
      balance += movement.signedDeltaFor(locationId);
    }
    return balance;
  }

  /// The movements of one period, in canonical order.
  ///
  /// Half-open: `startUtc <= createdAt < endExclusiveUtc`. A movement stamped
  /// exactly at `endExclusiveUtc` belongs to the next period and is counted there,
  /// exactly once (§15).
  static List<ReportLedgerMovement> movementsInPeriod({
    required Iterable<ReportLedgerMovement> movements,
    required ReportPeriod period,
    String? locationId,
    String? itemId,
  }) {
    final selected = <ReportLedgerMovement>[];
    for (final movement in sorted(movements)) {
      if (!period.contains(movement.createdAtUtc)) continue;
      if (itemId != null && movement.itemId != itemId) continue;
      if (locationId != null && !movement.touches(locationId)) continue;
      selected.add(movement);
    }
    return List.unmodifiable(selected);
  }

  /// The running balance after each movement, starting from [opening].
  ///
  /// Returns one entry per input movement, in the same order, so a caller can zip it
  /// with the rows it is rendering. [warnings] collects every point at which the
  /// balance went below zero — see [LedgerIntegrityWarning] for why they are
  /// reported rather than clamped.
  static List<Quantity> runningBalance({
    required List<ReportLedgerMovement> movements,
    required String locationId,
    required Quantity opening,
    List<LedgerIntegrityWarning>? warnings,
  }) {
    var balance = opening;
    final running = <Quantity>[];
    for (final movement in movements) {
      balance += movement.signedDeltaFor(locationId);
      running.add(balance);
      if (balance.isNegative) {
        warnings?.add(
          LedgerIntegrityWarning(
            key: LedgerPositionKey(
              locationId: locationId,
              itemId: movement.itemId,
              batchId: movement.batchId,
            ),
            movementId: movement.id,
            balance: balance,
          ),
        );
      }
    }
    return List.unmodifiable(running);
  }

  /// Balances per `(location, item, batch)` as of a cutoff, keeping only positions
  /// with a strictly positive balance.
  ///
  /// The shape both stock reports consume. Zero and negative positions are dropped
  /// here rather than in each builder — a shelf with nothing on it is not a row of
  /// a stock report, and a negative one is an integrity problem the caller surfaces
  /// through [detectNegativeBalances] rather than as a line item.
  static Map<LedgerPositionKey, Quantity> totalsByLocationItemBatch({
    required Iterable<ReportLedgerMovement> movements,
    required Set<String> locationIds,
    required DateTime cutoffExclusiveUtc,
  }) {
    final balances = balancesAsOf(
      movements: movements,
      locationIds: locationIds,
      cutoffExclusiveUtc: cutoffExclusiveUtc,
    );
    return {
      for (final entry in balances.entries)
        if (entry.value.isPositive) entry.key: entry.value,
    };
  }

  /// Positions whose balance is negative as of a cutoff.
  ///
  /// Never silently corrected. G-A2 makes this impossible on a healthy database, so
  /// finding one means the ledger and the balance cache disagree — which is exactly
  /// the condition a report exists to expose.
  static List<LedgerIntegrityWarning> detectNegativeBalances({
    required Iterable<ReportLedgerMovement> movements,
    required Set<String> locationIds,
    required DateTime cutoffExclusiveUtc,
  }) {
    final balances = balancesAsOf(
      movements: movements,
      locationIds: locationIds,
      cutoffExclusiveUtc: cutoffExclusiveUtc,
    );
    final warnings = <LedgerIntegrityWarning>[];
    balances.forEach((key, balance) {
      if (balance.isNegative) {
        warnings.add(
          LedgerIntegrityWarning(key: key, movementId: '-', balance: balance),
        );
      }
    });
    return warnings;
  }

  /// Sums signed deltas per `(document id, item, batch)` for one movement type.
  ///
  /// How every recap gets its *stock effect* column (§3.6): the document tables say
  /// what was intended, and this says what the ledger recorded. [byDestination]
  /// picks which side of a transfer is counted — a Good Receipt credits the branch
  /// store, so its recap counts the destination; a Delivery Order debits the
  /// warehouse, and its recap counts what left.
  ///
  /// The result is always **positive magnitude**: a recap column headed *Qty
  /// Dikirim* holds how much was sent, not a negative number describing the
  /// warehouse's point of view.
  static Map<LedgerDocumentPositionKey, Quantity> totalsByDocumentPosition({
    required Iterable<ReportLedgerMovement> movements,
    ReportPeriod? period,
  }) {
    final totals = <LedgerDocumentPositionKey, Quantity>{};
    for (final movement in sorted(movements)) {
      if (period != null && !period.contains(movement.createdAtUtc)) continue;
      final refDocId = movement.refDocId;
      if (refDocId == null) continue;
      final key = LedgerDocumentPositionKey(
        refDocId: refDocId,
        itemId: movement.itemId,
        batchId: movement.batchId,
      );
      totals[key] = (totals[key] ?? Quantity.zero()) + movement.qty;
    }
    return totals;
  }

  /// The same totals collapsed to `(document, item)`, for recaps whose lines are
  /// not batched — a Purchase Request line names an item and no batch, while the
  /// shipment that fulfils it names one batch per allocation (§25).
  static Map<LedgerDocumentItemKey, Quantity> totalsByDocumentItem({
    required Iterable<ReportLedgerMovement> movements,
    ReportPeriod? period,
  }) {
    final totals = <LedgerDocumentItemKey, Quantity>{};
    for (final movement in sorted(movements)) {
      if (period != null && !period.contains(movement.createdAtUtc)) continue;
      final refDocId = movement.refDocId;
      if (refDocId == null) continue;
      final key = LedgerDocumentItemKey(
        refDocId: refDocId,
        itemId: movement.itemId,
      );
      totals[key] = (totals[key] ?? Quantity.zero()) + movement.qty;
    }
    return totals;
  }
}

/// `(document, item, batch)` — the key a batched recap column is bucketed by.
class LedgerDocumentPositionKey {
  const LedgerDocumentPositionKey({
    required this.refDocId,
    required this.itemId,
    required this.batchId,
  });

  final String refDocId;
  final String itemId;
  final String? batchId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerDocumentPositionKey &&
          other.refDocId == refDocId &&
          other.itemId == itemId &&
          other.batchId == batchId);

  @override
  int get hashCode => Object.hash(refDocId, itemId, batchId);
}

/// `(document, item)` — the key an unbatched recap column is bucketed by.
class LedgerDocumentItemKey {
  const LedgerDocumentItemKey({required this.refDocId, required this.itemId});

  final String refDocId;
  final String itemId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerDocumentItemKey &&
          other.refDocId == refDocId &&
          other.itemId == itemId);

  @override
  int get hashCode => Object.hash(refDocId, itemId);
}
