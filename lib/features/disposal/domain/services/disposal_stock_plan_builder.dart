import '../models/disposal_models.dart';
import 'disposal_reason_policy.dart';

/// Why a posting plan could not be built.
enum DisposalPlanRejection {
  /// The document carries no live line at all.
  noLines,

  /// A line's quantity is not strictly positive.
  invalidQty,

  /// The header carries no reason a reader could act on (G-E7).
  missingReason,
}

/// Thrown by [DisposalStockPlanBuilder.build]. Carried as an exception rather than
/// a nullable return because every one of these is a bug or a corrupt document
/// rather than a user mistake, and swallowing it would post a shrunken or
/// unexplained document.
class DisposalPlanException implements Exception {
  const DisposalPlanException(this.rejection, {this.lineId});

  final DisposalPlanRejection rejection;
  final String? lineId;

  @override
  String toString() => 'DisposalPlanException($rejection, line: $lineId)';
}

/// Turns stored lines plus the resolved source into the one thing a posting needs:
/// a complete, validated plan (§21).
///
/// Building the whole plan **before the first movement** is what makes the
/// atomicity rule achievable. The source is resolved, every position aggregated,
/// every balance requirement known and every movement note composed up front, so a
/// failure cannot land halfway through a document and leave three batches gone and
/// two not.
///
/// It is pure: no repository, no clock, no transaction. The caller resolves and
/// authorises the source location (§15) and hands its id in. That separation is what
/// lets the posting path re-resolve everything inside its transaction and rebuild
/// the plan from *those* rows, rather than from whatever a form assembled earlier.
///
/// There is no destination parameter and no destination field on anything it
/// produces. A disposal has one leg (§20).
abstract final class DisposalStockPlanBuilder {
  /// Builds the plan, or throws [DisposalPlanException].
  static DisposalPostingPlan build({
    required String disposalId,
    required String sourceLocationId,
    required String? reason,
    required List<DisposalLineReference> lines,
  }) {
    if (lines.isEmpty) {
      throw const DisposalPlanException(DisposalPlanRejection.noLines);
    }
    final normalizedReason = DisposalReasonPolicy.normalize(reason);
    if (normalizedReason == null) {
      throw const DisposalPlanException(DisposalPlanRejection.missingReason);
    }

    final entries = <DisposalPostingEntry>[];
    for (final line in lines) {
      if (!line.qty.isPositive) {
        throw DisposalPlanException(
          DisposalPlanRejection.invalidQty,
          lineId: line.id,
        );
      }
      entries.add(
        DisposalPostingEntry(
          lineId: line.id,
          itemId: line.itemId,
          batchId: line.batchId,
          qty: line.qty,
          // Composed here rather than at the movement site, so every row of one
          // document carries text built the same way and a test can assert the
          // whole ledger's notes from the plan alone (§19/§20).
          note: DisposalReasonPolicy.movementNote(
            reason: normalizedReason,
            lineNote: line.note,
          ),
        ),
      );
    }

    // Deterministic order: item, then batch, then line. Two devices posting the
    // same document write their movements in the same sequence, which is what makes
    // the ledger comparable in a test and in a report.
    entries.sort((a, b) {
      final byItem = a.itemId.compareTo(b.itemId);
      if (byItem != 0) return byItem;
      final byBatch = a.batchId.compareTo(b.batchId);
      if (byBatch != 0) return byBatch;
      return a.lineId.compareTo(b.lineId);
    });

    return DisposalPostingPlan(
      disposalId: disposalId,
      sourceLocationId: sourceLocationId,
      reason: normalizedReason,
      entries: List<DisposalPostingEntry>.unmodifiable(entries),
    );
  }
}
