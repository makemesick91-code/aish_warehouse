import '../models/consumption_models.dart';
import 'consumption_note_policy.dart';

/// Why a posting plan could not be built.
enum ConsumptionPlanRejection {
  /// The document carries no live line at all.
  noLines,

  /// A line's quantity is not strictly positive.
  invalidQty,
}

/// Thrown by [ConsumptionStockPlanBuilder.build]. Carried as an exception rather than a
/// nullable return because both of these are a bug or a corrupt document rather than a
/// user mistake, and swallowing one would post a shrunken document.
class ConsumptionPlanException implements Exception {
  const ConsumptionPlanException(this.rejection, {this.lineId});

  final ConsumptionPlanRejection rejection;
  final String? lineId;

  @override
  String toString() => 'ConsumptionPlanException($rejection, line: $lineId)';
}

/// Turns stored lines plus the resolved room into the one thing a posting needs: a
/// complete, validated plan (§20).
///
/// Building the whole plan **before the first movement** is what makes the atomicity
/// rule achievable. The room location is resolved, every position aggregated, every
/// balance requirement known and every movement note composed up front, so a failure
/// cannot land halfway through a document and leave three positions gone and two not.
///
/// It is pure: no repository, no clock, no transaction. The caller resolves and
/// authorises the room and its stock location (§15) and hands the ids in. That
/// separation is what lets the posting path re-resolve everything inside its transaction
/// and rebuild the plan from *those* rows, rather than from whatever a form assembled
/// earlier.
///
/// There is no destination parameter and no destination field on anything it produces. A
/// consumption has one leg (§19).
///
/// Unlike `DisposalStockPlanBuilder` there is no rejection for a missing note: a
/// consumption note is optional (§8), so a plan whose entries all carry `note: null` is a
/// valid plan.
abstract final class ConsumptionStockPlanBuilder {
  /// Builds the plan, or throws [ConsumptionPlanException].
  static ConsumptionPostingPlan build({
    required String consumptionId,
    required String roomId,
    required String roomLocationId,
    required String? note,
    required List<ConsumptionLineReference> lines,
  }) {
    if (lines.isEmpty) {
      throw const ConsumptionPlanException(ConsumptionPlanRejection.noLines);
    }
    final headerNote = ConsumptionNotePolicy.normalize(note);

    final entries = <ConsumptionPostingEntry>[];
    for (final line in lines) {
      if (!line.qty.isPositive) {
        throw ConsumptionPlanException(
          ConsumptionPlanRejection.invalidQty,
          lineId: line.id,
        );
      }
      entries.add(
        ConsumptionPostingEntry(
          lineId: line.id,
          itemId: line.itemId,
          batchId: line.batchId,
          qty: line.qty,
          // Composed here rather than at the movement site, so every row of one
          // document carries text built the same way and a test can assert the whole
          // ledger's notes from the plan alone (§19).
          note: ConsumptionNotePolicy.movementNote(
            headerNote: headerNote,
            lineNote: line.note,
          ),
        ),
      );
    }

    // Deterministic order: item, then batch, then line. Two devices posting the same
    // document write their movements in the same sequence, which is what makes the
    // ledger comparable in a test and in a report. An unbatched position sorts before
    // a batched one of the same item, because `''` precedes every batch id.
    entries.sort((a, b) {
      final byItem = a.itemId.compareTo(b.itemId);
      if (byItem != 0) return byItem;
      final byBatch = (a.batchId ?? '').compareTo(b.batchId ?? '');
      if (byBatch != 0) return byBatch;
      return a.lineId.compareTo(b.lineId);
    });

    return ConsumptionPostingPlan(
      consumptionId: consumptionId,
      roomId: roomId,
      roomLocationId: roomLocationId,
      note: headerNote,
      entries: List<ConsumptionPostingEntry>.unmodifiable(entries),
    );
  }
}
