import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/consumption_models.dart';
import '../repositories/consumption_repository.dart';
import '../services/consumption_note_policy.dart';
import '../services/consumption_stock_reader.dart';
import 'consumption_guards.dart';

/// Adds one consumed position to a `draft` Pemakaian (§21.3).
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive account or a non-Perawat        (§14)
///  2. load the document, verify ownership, branch and `draft`            (§14/G-S1)
///  3. verify the room is still active and still the actor's branch's     (§15)
///  4. resolve the room's single stock location                           (§15)
///  5. verify the item is live and active                                 (§16)
///  6. verify the item's batch rule and that the batch is its own         (G-E2)
///  7. verify the batch has **not** expired right now                     (§17)
///  8. verify the position is not already on the document
///  9. verify the quantity is positive and within the live balance        (§18)
/// 10. insert the line
/// ```
///
/// Step 7 is the rule this document inherits from G-E4 and G-E7 between them: expired
/// stock leaves only through a Pemusnahan, so it may not be recorded as used. It is asked
/// against the clock rather than against whatever the picker showed. A form left open
/// across midnight GMT+8 saw a different set of eligible batches than the one that exists
/// when the button is pressed — in both directions: a batch may have expired in the
/// meantime, and a batch the user selected may still be in date if their device's clock
/// ran ahead.
///
/// Step 9 reads the balance **now**, and it is still not the authority: the posting
/// re-reads it inside its own transaction. What this check buys is that an impossible
/// line is refused while the nurse can still do something about it, rather than at the
/// end when the whole document fails.
///
/// No movement is written and no balance changes. Adding a line to a document is not a
/// stock event; posting it is. In particular a draft **does not reserve stock** — two
/// drafts may both name the same position, and whichever posts first wins (§18).
class AddConsumptionLineUseCase {
  AddConsumptionLineUseCase({
    required this._consumptions,
    required MasterDataRepository master,
    required this._stock,
    DateTime Function()? clock,
  }) : _guards = ConsumptionGuards(master),
       _clock = clock ?? _defaultClock;

  final ConsumptionRepository _consumptions;
  final ConsumptionGuards _guards;
  final RoomConsumptionStockReader _stock;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<ConsumptionLineReference> call({
    required String actorUserId,
    required String consumptionId,
    required String itemId,
    String? batchId,
    required Quantity qty,
    String? note,
  }) async {
    final actor = await _guards.requireNurseActor(actorUserId);
    final nowUtc = _clock().toUtc();

    return _consumptions.runInTransaction(() async {
      final consumption = await _consumptions.getById(consumptionId);
      if (consumption == null) {
        throw ConsumptionNotFoundFailure(
          'Pemakaian tidak ditemukan.',
          consumptionId: consumptionId,
        );
      }
      _guards.requireOwnership(actor: actor, consumption: consumption);
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: consumption.branchId,
      );
      _guards.requireStatus(
        consumption: consumption,
        expected: ConsumptionStatus.draft,
      );

      // Adding a line *is* new work — it commits the nurse to a quantity the posting
      // will take off a shelf — so the room has to be operational, exactly as it does at
      // creation. This is where the Pemakaian rule is stricter than the Pemusnahan's
      // (§15).
      final room = await _guards.requireRoomForConsumption(
        branchId: consumption.branchId,
        roomId: consumption.roomId,
      );
      final location = await _guards.requireRoomLocation(
        room: room,
        branchId: consumption.branchId,
      );

      final item = await _guards.requireActiveItem(itemId);
      final batch = await _guards.requireBatchConsistency(
        consumptionId: consumption.id,
        item: item,
        batchId: batchId,
      );
      _guards.requireNotExpired(batch: batch, nowUtc: nowUtc);

      final existing = await _consumptions.lineReferences(consumption.id);
      _guards.requirePositionFree(
        consumptionId: consumption.id,
        itemId: item.id,
        batchId: batch?.id,
        existing: existing,
      );

      _guards.requirePositiveQty(qty: qty);

      final available = await _stock.balanceOf(
        roomLocationId: location.id,
        itemId: item.id,
        batchId: batch?.id,
      );
      if (!available.isPositive) {
        _guards.positionHasNoStock(
          itemId: item.id,
          itemSku: item.sku,
          batchNo: batch?.batchNo,
          locationId: location.id,
        );
      }
      _guards.requireSufficientStock(
        itemId: item.id,
        itemSku: item.sku,
        unit: item.unit,
        locationId: location.id,
        batchId: batch?.id,
        batchNo: batch?.batchNo,
        requested: qty,
        available: available,
      );

      return _consumptions.addDraftLine(
        consumptionId: consumption.id,
        actorUserId: actor.id,
        itemId: item.id,
        batchId: batch?.id,
        qty: qty,
        note: ConsumptionNotePolicy.normalize(note),
      );
    });
  }
}
