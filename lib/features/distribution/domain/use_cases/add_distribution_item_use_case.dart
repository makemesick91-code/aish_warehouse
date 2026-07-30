import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/distribution_models.dart';
import '../repositories/distribution_repository.dart';
import '../services/distribution_allocation_planner.dart';
import '../services/distribution_fefo_policy.dart';
import 'distribution_guards.dart';

/// What one addition produced.
class DistributionAdditionResult {
  const DistributionAdditionResult({
    required this.roomId,
    required this.itemId,
    required this.allocations,
  });

  final String roomId;
  final String itemId;

  /// One entry per batch the quantity was drawn from. A single `1.5` may become two
  /// lines when the nearest-expiry batch only holds `1` (G-E3).
  final List<DistributionAllocation> allocations;

  int get lineCount => allocations.length;

  Quantity get totalQty =>
      Quantity.sum(allocations.map((allocation) => allocation.qty));

  bool get isSplit => allocations.length > 1;
}

/// Adds one item to one room of a draft, with the batches chosen by FEFO (§21.2).
///
/// This is the path the item picker drives: the branch head picks a room, picks a
/// product and types a quantity, and the system decides *which* batches leave the
/// store. Choosing batches by hand is [AddManualDistributionAllocationUseCase]'s job.
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive or non-branch-head account   (spec §3.1)
///  2. load the document, guard `draft`                                (G-S1)
///  3. verify the actor's branch is the document's                     (G-T1/G-R2)
///  4. verify the room: this branch, active, with one live location    (G-T1/§14)
///  5. verify the item is live and active                             (G-A4)
///  6. refuse a quantity that is not strictly positive                (G-T2)
///  7. resolve exactly one active Gudang Cabang                       (G-T1/§14)
///  8. read what the store holds for the item, expiry already split   (G-E4)
///  9. refuse a room that already holds this item                     (partial index)
/// 10. net the store's batches by what the rest of the document takes (§16/§18)
/// 11. allocate FEFO, or refuse the whole request                     (G-E3)
/// 12. evaluate FEFO over the item's *whole* selection                (§16)
/// 13. store every line of the allocation in one statement            (G-T4)
/// ```
///
/// Steps 10 and 12 are what make this correct on a multi-room document, and they are
/// the two a per-room implementation gets wrong in opposite directions: without 10 the
/// same batch is offered to three rooms, and without 12 an old batch can be skipped by
/// splitting a quantity. `DistributionAllocationPlanner` holds both so the add, the
/// manual override and the edit path cannot disagree.
///
/// Nothing here writes a movement or changes a balance. A draft is an intention; the
/// ledger moves when the document is posted (spec §2.5). Nor does a draft *reserve*
/// stock: several drafts may exist for the same branch, and which of them can commit
/// is decided at posting against live balances (§18).
class AddDistributionItemUseCase {
  AddDistributionItemUseCase({
    required this._distributions,
    required MasterDataRepository master,
    DateTime Function()? clock,
  }) : _guards = DistributionGuards(master),
       _clock = clock ?? _defaultClock;

  final DistributionRepository _distributions;
  final DistributionGuards _guards;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<DistributionAdditionResult> call({
    required String actorUserId,
    required String distributionId,
    required String roomId,
    required String itemId,
    required Quantity requestedQty,
  }) async {
    // 1. Outside any transaction: an inactive account is not a concurrency question,
    // and refusing early keeps the message precise.
    final actor = await _guards.requireBranchHeadActor(actorUserId);
    final nowUtc = _clock().toUtc();

    return _distributions.runInTransaction(() async {
      // 2–3. The document.
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

      // 4. G-T1's destination half. The location is resolved too, even though nothing
      // is posted yet: a room with no stock location cannot receive goods, and finding
      // that out at posting time — after three more rooms were filled in — would waste
      // the branch head's work.
      final room = await _guards.requireRoomForDistribution(
        branchId: distribution.branchId,
        roomId: roomId,
      );
      final destination = await _guards.requireRoomLocation(
        room: room,
        branchId: distribution.branchId,
      );

      // 5–6.
      final item = await _guards.requireActiveItem(itemId);
      _guards.requirePositiveQty(qty: requestedQty);

      // 7. Never a hard-coded id, and never guessed when there are none or several.
      final source = await _guards.requireBranchStore(distribution.branchId);
      _guards.requireDistinctLeg(source: source, destination: destination);

      // 8. What the store actually holds. Expired batches are already separated out by
      // the repository, so nothing here can allocate one (G-E4).
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

      // 9. One automatic addition per (room, item). Once the room holds part of the
      // product, "add it again" is meaningless — the branch head edits the allocation
      // that is there, which is also the only way the aggregate FEFO evaluation stays
      // readable.
      _guards.requireItemNotInRoom(
        distributionId: distribution.id,
        roomId: roomId,
        itemId: item.id,
        existing: existing,
      );

      final List<DistributionAllocation> proposed;
      if (item.hasExpiry) {
        // 10–11. FEFO over what is left after the document's other rooms.
        final candidates = planner.remainingCandidates();
        final allocated = DistributionFefoPolicy.allocate(
          roomId: roomId,
          itemId: item.id,
          candidates: candidates,
          qty: requestedQty,
          nowUtc: nowUtc,
        );
        if (allocated == null) {
          // Never a partial allocation: half an answer looks like an answer, and the
          // branch head would have to notice the shortfall themselves.
          final available = Quantity.sum(
            candidates.map((candidate) => candidate.availableQty),
          );
          _guards.requireSufficientStock(
            itemId: item.id,
            itemSku: item.sku,
            unit: item.unit,
            locationId: source.id,
            requested: requestedQty,
            available: available,
          );
          // `requireSufficientStock` throws whenever requested > available, which is
          // the only way `allocate` returns null. Unreachable, and stated so a future
          // change to either side fails loudly instead of silently storing nothing.
          throw StateError('FEFO allocation failed without a shortfall.');
        }
        proposed = allocated;
      } else {
        // An item without expiry has one balance and no batch (G-E2).
        final available = planner.remainingUnbatched();
        _guards.requireSufficientStock(
          itemId: item.id,
          itemSku: item.sku,
          unit: item.unit,
          locationId: source.id,
          requested: requestedQty,
          available: available,
        );
        proposed = [
          DistributionAllocation(
            roomId: roomId,
            itemId: item.id,
            qty: requestedQty,
          ),
        ];
      }

      // 12. FEFO over the item's whole selection, not just this room's share. An
      // automatic allocation cannot violate FEFO by construction — it took the
      // nearest-expiry stock available to it — but asking anyway is what makes that a
      // verified property rather than a belief, and it is what fills in the reasons the
      // *other* rooms' lines already carry.
      final reasons = _guards.requireFefoCompliance(
        itemId: item.id,
        itemSku: item.sku,
        candidates: stock.candidates,
        selection: planner.selectionWith(proposed),
        reasonByBatchId: planner.reasonsWith(proposed),
        nowUtc: nowUtc,
      );

      // 13. One statement for the whole allocation: three batches of one request are
      // one decision, and a partially stored allocation would distribute less than was
      // asked for.
      final stored = proposed
          .map(
            (allocation) => allocation.copyWith(
              fefoOverrideReason: allocation.batchId == null
                  ? null
                  : reasons[allocation.batchId],
            ),
          )
          .toList(growable: false);

      await _distributions.addAllocations(
        distributionId: distribution.id,
        allocations: stored,
      );

      return DistributionAdditionResult(
        roomId: roomId,
        itemId: item.id,
        allocations: stored,
      );
    });
  }
}
