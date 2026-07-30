import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/distribution_models.dart';
import '../repositories/distribution_repository.dart';
import '../services/distribution_allocation_planner.dart';
import 'distribution_guards.dart';

/// Changes the quantity, the batch or the FEFO reason of one draft line (§21.4).
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive or non-branch-head account  (spec §3.1)
///  2. load the line without any join, and check it is on this document
///  3. load the document, guard `draft`                               (G-S1)
///  4. verify the actor's branch is the document's                    (G-T1/G-R2)
///  5. verify the room still qualifies                                (G-T1)
///  6. load the item — deactivated ones included                      (G-A4/§32)
///  7. verify item and the *target* batch agree                       (G-E2)
///  8. refuse an expired target batch                                 (G-E4)
///  9. refuse a quantity that is not strictly positive                (G-T2)
/// 10. resolve exactly one active Gudang Cabang                       (G-T1/§14)
/// 11. refuse a position another line already holds                   (partial index)
/// 12. refuse more than the batch has left, excluding this line        (G-T2/§16)
/// 13. evaluate FEFO over the item's whole selection with this change  (G-E3/§16)
/// 14. guarded UPDATE, refused if the parent is no longer a draft
/// ```
///
/// ### What cannot be changed here, and why
///
/// `room_id` and `item_id` are out of reach — the repository offers no writer that
/// touches them. A position for another room or another item is a *different*
/// position: moving one in place would slip past the room/branch validation G-T1
/// depends on and past the duplicate check the partial unique indexes enforce. Moving
/// an item between rooms is remove-then-add, and both halves are validated.
///
/// ### Why the item may be deactivated
///
/// Step 6 uses the historical lookup deliberately. An item withdrawn from the
/// catalogue after it was added to a draft is still sitting in the store, and the
/// branch head must be able to *correct* the line — usually to reduce it, sometimes to
/// remove it. Refusing the edit would leave the document stuck with a quantity nobody
/// can adjust. What a deactivated item may not do is appear on a **new** line, which
/// is [DistributionGuards.requireActiveItem]'s job on the add paths.
///
/// Step 12 excludes this line from the netting, and that is load-bearing: netting a
/// line against itself would make raising `2` to `3` look like a request for `5`.
///
/// Nothing here writes a movement or changes a balance; the ledger moves at posting
/// (spec §2.5), and every check above is re-run there against live balances.
class UpdateDistributionLineUseCase {
  UpdateDistributionLineUseCase({
    required this._distributions,
    required MasterDataRepository master,
    DateTime Function()? clock,
  }) : _guards = DistributionGuards(master),
       _clock = clock ?? _defaultClock;

  final DistributionRepository _distributions;
  final DistributionGuards _guards;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  /// [batchId] defaults to the line's current batch when omitted, so a caller that only
  /// wants to change a quantity does not have to restate the allocation. Passing it
  /// explicitly moves the line to another batch — still within the same item, because
  /// the batch has to belong to it (G-E2).
  Future<DistributionAllocation> call({
    required String actorUserId,
    required String distributionId,
    required String lineId,
    required Quantity qty,
    Object? batchId = _keepBatch,
    String? fefoOverrideReason,
  }) async {
    final actor = await _guards.requireBranchHeadActor(actorUserId);
    final nowUtc = _clock().toUtc();

    return _distributions.runInTransaction(() async {
      // 2. Read without a join, so a broken reference is reported rather than making
      // the line silently invisible (§22).
      final line = _guards.requireLineOf(
        distributionId: distributionId,
        lineId: lineId,
        line: await _distributions.lineReferenceById(lineId),
      );

      final distribution = await _distributions.getById(distributionId);
      if (distribution == null) {
        throw DistributionNotFoundFailure(
          'Distribusi tidak ditemukan.',
          distributionId: distributionId,
        );
      }
      _guards.requireStatus(
        distribution: distribution,
        expected: DistributionStatus.draft,
      );
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: distribution.branchId,
      );

      final room = await _guards.requireRoomForDistribution(
        branchId: distribution.branchId,
        roomId: line.roomId,
      );
      final destination = await _guards.requireRoomLocation(
        room: room,
        branchId: distribution.branchId,
      );

      // 6. Deactivated items pass; see the class note.
      final item = await _guards.requireHistoricalItem(
        distributionId: distribution.id,
        itemId: line.itemId,
      );

      final targetBatchId = batchId == _keepBatch
          ? line.batchId
          : batchId as String?;
      final batch = await _guards.requireBatchConsistency(
        distributionId: distribution.id,
        item: item,
        batchId: targetBatchId,
      );
      _guards.requireNotExpired(batch: batch, nowUtc: nowUtc, lineId: line.id);
      _guards.requirePositiveQty(qty: qty, lineId: line.id);

      final source = await _guards.requireBranchStore(distribution.branchId);
      _guards.requireDistinctLeg(source: source, destination: destination);

      final stock = await _distributions.branchStockFor(
        branchStoreLocationId: source.id,
        itemId: item.id,
        nowUtc: nowUtc,
        // The item may have been deactivated after the line was added; the store still
        // holds its stock, and this edit is a correction rather than new work.
        activeItemsOnly: false,
      );
      if (stock == null) {
        _guards.itemHasNoStock(
          itemId: item.id,
          itemSku: item.sku,
          locationId: source.id,
        );
      }

      final existing = await _distributions.lineReferences(distribution.id);
      // 11. Another *different* line already on this position would collide with the
      // partial unique index. Excluding this line is what lets an unchanged batch be
      // re-saved with a new quantity.
      _guards.requirePositionFree(
        distributionId: distribution.id,
        roomId: line.roomId,
        itemId: item.id,
        batchId: targetBatchId,
        existing: existing.where((entry) => entry.id != line.id),
      );

      final planner = DistributionAllocationPlanner(
        existingLines: existing,
        stock: stock,
      );
      // 12. Excluding this line from the netting: otherwise raising `2` to `3` would be
      // read as asking for `5`.
      final available = targetBatchId == null
          ? planner.remainingUnbatched(excludeLineId: line.id)
          : planner.remainingForBatch(targetBatchId, excludeLineId: line.id);
      _guards.requireSufficientStock(
        itemId: item.id,
        itemSku: item.sku,
        unit: item.unit,
        locationId: source.id,
        batchId: targetBatchId,
        batchNo: batch?.batchNo,
        requested: qty,
        available: available,
      );

      final proposed = DistributionAllocation(
        lineId: line.id,
        roomId: line.roomId,
        itemId: item.id,
        batchId: targetBatchId,
        batchNo: batch?.batchNo,
        expiryDate: batch?.expiryDate,
        qty: qty,
        fefoOverrideReason: fefoOverrideReason,
      );

      // 13. Judged over the item's whole selection with this line replaced.
      final reasons = _guards.requireFefoCompliance(
        itemId: item.id,
        itemSku: item.sku,
        candidates: stock.candidates,
        selection: planner.selectionWith([proposed], excludeLineId: line.id),
        reasonByBatchId: planner.reasonsWith([
          proposed,
        ], excludeLineId: line.id),
        nowUtc: nowUtc,
        lineId: line.id,
      );

      final storedReason = targetBatchId == null
          ? null
          : reasons[targetBatchId];
      final updated = await _distributions.updateDraftLine(
        distributionId: distribution.id,
        lineId: line.id,
        qty: qty,
        batchId: targetBatchId,
        fefoOverrideReason: storedReason,
      );
      // 14. Zero rows means the parent left `draft` between the read and the write, or
      // the line was removed from another device.
      if (!updated) _guards.concurrentUpdate(distribution);

      return proposed.copyWith(fefoOverrideReason: storedReason);
    });
  }

  /// Sentinel so `batchId: null` can mean "clear the batch" — which only an item
  /// without expiry may do — rather than "keep the current one".
  static const Object _keepBatch = Object();
}
