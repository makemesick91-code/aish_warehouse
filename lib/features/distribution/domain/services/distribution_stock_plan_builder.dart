import '../../../../core/quantity/quantity.dart';
import '../models/distribution_models.dart';

/// Why a posting plan could not be built.
enum DistributionPlanRejection {
  /// The document carries no live line at all.
  noLines,

  /// A line's room has no resolved destination location. Reached only when the
  /// caller forgot to resolve one, which is why it is a distinct failure rather
  /// than a silent skip.
  missingDestination,

  /// A destination resolved to the source itself, which would be a movement from a
  /// location to itself.
  destinationIsSource,

  /// A line's quantity is not strictly positive.
  invalidQty,
}

/// Thrown by [DistributionStockPlanBuilder.build]. Carried as an exception rather
/// than a nullable return because every one of these is a bug or a corrupt document
/// rather than a user mistake, and swallowing it would post a shrunken document.
class DistributionPlanException implements Exception {
  const DistributionPlanException(this.rejection, {this.lineId, this.roomId});

  final DistributionPlanRejection rejection;
  final String? lineId;
  final String? roomId;

  @override
  String toString() =>
      'DistributionPlanException($rejection, line: $lineId, room: $roomId)';
}

/// Turns stored lines plus resolved locations into the one thing a posting needs:
/// a complete, validated plan (§20).
///
/// Building the whole plan **before the first movement** is what makes G-T4
/// achievable. Every location is resolved, every position aggregated and every
/// balance requirement known up front, so a failure cannot land halfway through a
/// document and leave three rooms credited and two not.
///
/// It is pure: no repository, no clock, no transaction. The caller resolves the
/// source store and the room locations — by type, never from a screen (§14) — and
/// hands them in. That separation is what lets the posting path re-resolve
/// everything inside its transaction and rebuild the plan from *those* rows, rather
/// than from whatever a form assembled earlier.
abstract final class DistributionStockPlanBuilder {
  /// Builds the plan, or throws [DistributionPlanException].
  ///
  /// [destinationLocationsByRoom] must cover every room the lines name. A missing
  /// entry is an explicit failure rather than a skipped line, because a plan that
  /// quietly dropped a room would move less stock than the document says it did —
  /// and every per-line check would still pass.
  static DistributionPostingPlan build({
    required String distributionId,
    required String branchId,
    required String sourceLocationId,
    required List<DistributionLineReference> lines,
    required Map<String, String> destinationLocationsByRoom,
  }) {
    if (lines.isEmpty) {
      throw const DistributionPlanException(DistributionPlanRejection.noLines);
    }

    final entries = <DistributionPostingEntry>[];
    for (final line in lines) {
      if (!line.qty.isPositive) {
        throw DistributionPlanException(
          DistributionPlanRejection.invalidQty,
          lineId: line.id,
          roomId: line.roomId,
        );
      }
      final destination = destinationLocationsByRoom[line.roomId];
      if (destination == null) {
        throw DistributionPlanException(
          DistributionPlanRejection.missingDestination,
          lineId: line.id,
          roomId: line.roomId,
        );
      }
      if (destination == sourceLocationId) {
        throw DistributionPlanException(
          DistributionPlanRejection.destinationIsSource,
          lineId: line.id,
          roomId: line.roomId,
        );
      }
      entries.add(
        DistributionPostingEntry(
          lineId: line.id,
          roomId: line.roomId,
          destinationLocationId: destination,
          itemId: line.itemId,
          batchId: line.batchId,
          qty: line.qty,
        ),
      );
    }

    // Deterministic order: room, then item, then batch. Two devices posting the same
    // document write their movements in the same sequence, which is what makes the
    // ledger comparable in a test and in a report.
    entries.sort((a, b) {
      final byRoom = a.roomId.compareTo(b.roomId);
      if (byRoom != 0) return byRoom;
      final byItem = a.itemId.compareTo(b.itemId);
      if (byItem != 0) return byItem;
      final byBatch = (a.batchId ?? '').compareTo(b.batchId ?? '');
      if (byBatch != 0) return byBatch;
      return a.lineId.compareTo(b.lineId);
    });

    return DistributionPostingPlan(
      distributionId: distributionId,
      branchId: branchId,
      sourceLocationId: sourceLocationId,
      entries: List<DistributionPostingEntry>.unmodifiable(entries),
    );
  }

  /// What each room will receive, per unit-less position, so a caller can verify the
  /// destination balances after posting without re-deriving the sums.
  ///
  /// Keyed `room|item|batch`, which is the grain `stock_balances` holds a room's
  /// stock at.
  static Map<String, Quantity> destinationRequirements(
    DistributionPostingPlan plan,
  ) {
    final totals = <String, Quantity>{};
    for (final entry in plan.entries) {
      final key = '${entry.roomId}|${entry.itemId}|${entry.batchId ?? ''}';
      totals[key] = (totals[key] ?? Quantity.zero()) + entry.qty;
    }
    return totals;
  }
}
