import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/consumption_models.dart';
import '../repositories/consumption_repository.dart';
import '../services/consumption_note_policy.dart';
import '../services/consumption_stock_reader.dart';
import 'consumption_guards.dart';

/// Changes the quantity or the note of one line on a `draft` Pemakaian (§21.4).
///
/// What it cannot change is the point: `consumption_id`, `item_id` and `batch_id` are out
/// of reach here and in the SQL beneath. Another batch is a *different* position, with its
/// own expiry date and its own balance, and editing one in place would slip past both of
/// those checks — a line pointing at an expired batch, sitting on a document that was
/// validated when it named a different one. Swapping a position is remove-then-add, and
/// both halves are validated.
///
/// Everything that made the line legal in the first place is asked again:
///
/// ```
/// 1. actor, ownership, branch and `draft`                               (§14/G-S1)
/// 2. the room is still active and its location still resolves           (§15)
/// 3. the line is still on this document
/// 4. the item and batch still resolve                                   (§16)
/// 5. the batch is **still unexpired** right now                         (§17)
/// 6. the new quantity is positive and within the live balance           (§18)
/// ```
///
/// Step 5 is not redundant with the add path. Expiry is a function of the operational
/// date, and a draft can sit open across a midnight in GMT+8 — so a position that was
/// eligible when it was added may have stopped being so, and a nurse editing the quantity
/// is exactly the moment to say so rather than letting the posting be the first thing to
/// notice.
///
/// Step 4 uses the **historical** item lookup rather than the active one, and the
/// asymmetry with the add path is deliberate: the line already exists, so a product
/// withdrawn from the catalogue afterwards must not trap the nurse with a quantity they
/// cannot correct. What is still enforced is that the row is physically there (§33).
class UpdateConsumptionLineUseCase {
  UpdateConsumptionLineUseCase({
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
    required String lineId,
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

      final room = await _guards.requireRoomForConsumption(
        branchId: consumption.branchId,
        roomId: consumption.roomId,
      );
      final location = await _guards.requireRoomLocation(
        room: room,
        branchId: consumption.branchId,
      );

      final line = _guards.requireLineOf(
        consumptionId: consumption.id,
        lineId: lineId,
        line: await _consumptions.lineReferenceById(lineId),
      );

      final item = await _guards.requireHistoricalItem(
        consumptionId: consumption.id,
        itemId: line.itemId,
      );
      final batch = await _guards.requireBatchConsistency(
        consumptionId: consumption.id,
        item: item,
        batchId: line.batchId,
      );
      _guards.requireNotExpired(batch: batch, nowUtc: nowUtc, lineId: line.id);

      _guards.requirePositiveQty(qty: qty, lineId: line.id);

      final available = await _stock.balanceOf(
        roomLocationId: location.id,
        itemId: item.id,
        batchId: batch?.id,
      );
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

      final updated = await _consumptions.updateDraftLine(
        consumptionId: consumption.id,
        actorUserId: actor.id,
        lineId: line.id,
        qty: qty,
        note: ConsumptionNotePolicy.normalize(note),
      );
      if (!updated) _guards.concurrentUpdate(consumption);

      final result = await _consumptions.lineReferenceById(line.id);
      if (result == null) {
        throw ConsumptionLineNotFoundFailure(
          'Baris pemakaian tidak ditemukan setelah pembaruan.',
          lineId: line.id,
        );
      }
      return result;
    });
  }
}
