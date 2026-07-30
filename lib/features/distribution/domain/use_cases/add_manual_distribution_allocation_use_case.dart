import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/distribution_models.dart';
import '../repositories/distribution_repository.dart';
import '../services/distribution_allocation_planner.dart';
import 'distribution_guards.dart';

/// Adds one **hand-picked** batch allocation to a draft (§21.3).
///
/// The other half of G-E3. [AddDistributionItemUseCase] lets the system choose batches
/// by FEFO; this is the path for a branch head who has a reason to choose differently —
/// a dentist who asked for the longer-dated stock, a batch whose packaging is damaged.
/// The specification allows it and attaches one condition: *"Memilih batch yang lebih
/// muda dari saran FEFO memunculkan peringatan + catatan wajib."*
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive or non-branch-head account  (spec §3.1)
///  2. load the document, guard `draft`                               (G-S1)
///  3. verify the actor's branch is the document's                    (G-T1/G-R2)
///  4. verify the room: this branch, active, with one live location   (G-T1/§14)
///  5. verify the item is live and active                             (G-A4)
///  6. verify item and batch agree, and the batch exists              (G-E2)
///  7. refuse an expired batch outright                               (G-E4)
///  8. refuse a quantity that is not strictly positive                (G-T2)
///  9. resolve exactly one active Gudang Cabang                       (G-T1/§14)
/// 10. refuse a position the document already holds                   (partial index)
/// 11. refuse more than this batch has left after the other rooms     (G-T2/§16)
/// 12. evaluate FEFO over the item's *whole* selection, demand a reason (G-E3/§16)
/// 13. store the line
/// ```
///
/// Step 11 is netted against the rest of the document, not against the raw shelf: two
/// rooms cannot each be given the same 2 ampoules of one batch. Step 12 is judged over
/// every room, which is what makes the reason requirement impossible to dodge by
/// splitting a quantity.
///
/// ### What this deliberately cannot do
///
/// It offers no way to distribute an item the store does not hold: the batch has to be
/// one of the store's own positive balances, so there is no "free text item" path and
/// no way to invent stock. And a reason is *dropped* rather than stored when the
/// selection turns out to be compliant — a note explaining a decision nobody made is
/// worse than no note (§9: *reason null jika tidak override*).
///
/// Nothing here writes a movement or changes a balance; the ledger moves at posting
/// (spec §2.5), and the FEFO evaluation is re-run there against live balances.
class AddManualDistributionAllocationUseCase {
  AddManualDistributionAllocationUseCase({
    required this._distributions,
    required MasterDataRepository master,
    DateTime Function()? clock,
  }) : _guards = DistributionGuards(master),
       _clock = clock ?? _defaultClock;

  final DistributionRepository _distributions;
  final DistributionGuards _guards;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<DistributionAllocation> call({
    required String actorUserId,
    required String distributionId,
    required String roomId,
    required String itemId,
    String? batchId,
    required Quantity qty,
    String? fefoOverrideReason,
  }) async {
    final actor = await _guards.requireBranchHeadActor(actorUserId);
    final nowUtc = _clock().toUtc();

    return _distributions.runInTransaction(() async {
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
        roomId: roomId,
      );
      final destination = await _guards.requireRoomLocation(
        room: room,
        branchId: distribution.branchId,
      );

      final item = await _guards.requireActiveItem(itemId);
      // G-E2 both ways: an expiry-tracked item must name a batch, one without expiry
      // must not.
      final batch = await _guards.requireBatchConsistency(
        distributionId: distribution.id,
        item: item,
        batchId: batchId,
      );
      // G-E4. No note and no confirmation passes this — the stock leaves through
      // disposal instead (G-E7).
      _guards.requireNotExpired(batch: batch, nowUtc: nowUtc);
      _guards.requirePositiveQty(qty: qty);

      final source = await _guards.requireBranchStore(distribution.branchId);
      _guards.requireDistinctLeg(source: source, destination: destination);

      final stock = await _distributions.branchStockFor(
        branchStoreLocationId: source.id,
        itemId: item.id,
        nowUtc: nowUtc,
      );
      if (stock == null) {
        _guards.itemHasNoStock(
          itemId: item.id,
          itemSku: item.sku,
          locationId: source.id,
        );
      }

      final existing = await _distributions.lineReferences(distribution.id);
      final planner = DistributionAllocationPlanner(
        existingLines: existing,
        stock: stock,
      );
      if (planner.hasNoUsableStock) {
        _guards.itemHasNoStock(
          itemId: item.id,
          itemSku: item.sku,
          locationId: source.id,
          onlyExpired: planner.hasOnlyExpiredStock,
        );
      }

      // 10. The exact position, batch included — unlike the automatic path, adding a
      // *second* batch of the same item to the same room is a legitimate manual split.
      _guards.requirePositionFree(
        distributionId: distribution.id,
        roomId: roomId,
        itemId: item.id,
        batchId: batchId,
        existing: existing,
      );

      // 11. Netted against the rest of the document (§16/§18).
      final available = batchId == null
          ? planner.remainingUnbatched()
          : planner.remainingForBatch(batchId);
      _guards.requireSufficientStock(
        itemId: item.id,
        itemSku: item.sku,
        unit: item.unit,
        locationId: source.id,
        batchId: batchId,
        batchNo: batch?.batchNo,
        requested: qty,
        available: available,
      );

      final proposed = DistributionAllocation(
        roomId: roomId,
        itemId: item.id,
        batchId: batchId,
        batchNo: batch?.batchNo,
        expiryDate: batch?.expiryDate,
        qty: qty,
        fefoOverrideReason: fefoOverrideReason,
      );

      // 12. Judged over the item's whole selection, against the store's gross
      // holdings — which is what makes "split it across two rooms" no escape.
      final reasons = _guards.requireFefoCompliance(
        itemId: item.id,
        itemSku: item.sku,
        candidates: stock.candidates,
        selection: planner.selectionWith([proposed]),
        reasonByBatchId: planner.reasonsWith([proposed]),
        nowUtc: nowUtc,
      );

      final stored = proposed.copyWith(
        fefoOverrideReason: batchId == null ? null : reasons[batchId],
      );
      await _distributions.addAllocations(
        distributionId: distribution.id,
        allocations: [stored],
      );
      return stored;
    });
  }
}
