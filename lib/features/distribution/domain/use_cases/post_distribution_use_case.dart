import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../../../inventory/domain/models/inventory_models.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/distribution_models.dart';
import '../repositories/distribution_repository.dart';
import '../services/distribution_allocation_planner.dart';
import '../services/distribution_branch_stock_reader.dart';
import '../services/distribution_stock_plan_builder.dart';
import 'distribution_guards.dart';

/// What a posted Distribusi did (§21.6).
class DistributionPostingResult {
  const DistributionPostingResult({
    required this.distribution,
    required this.movements,
    required this.branchStore,
    required this.roomLocations,
    required this.plan,
    required this.progress,
  });

  final Distribution distribution;

  /// One append-only ledger row per line (G-A1). Every line moves stock — a zero
  /// quantity cannot exist — so this always has exactly as many entries as the
  /// document has lines.
  final List<InventoryMovement> movements;

  /// The *Gudang Cabang* that was reduced.
  final MasterLocation branchStore;

  /// The room location each targeted room resolved to, keyed by room id.
  final Map<String, MasterLocation> roomLocations;

  /// The validated plan the posting executed.
  final DistributionPostingPlan plan;

  /// The counters the document was posted with.
  final DistributionProgress progress;

  int get roomCount => plan.roomCount;

  int get lineCount => plan.lineCount;

  /// Total quantity that left the store — equal, by construction, to the total that
  /// arrived in the rooms.
  Quantity get totalQty => plan.totalQty;

  bool get hasFefoOverride => progress.hasFefoOverride;
}

/// `draft → posted` — the write this milestone exists for (§21.6, G-T1 … G-T4).
///
/// Everything happens in **one** database transaction, and the order is chosen so that
/// nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive or non-branch-head account   (spec §3.1)
///  2. load the document, guard `draft`                                (G-S1)
///  3. verify the actor's branch is the document's                     (G-T1/G-R2)
///  4. read every line without a join                                  (§22)
///  5. refuse an empty document
///  6. verify the plain line set and the joined read agree              (§22)
///  7. verify every room, item and batch id still resolves              (§32)
///  8. verify every room: this branch, active, one live location        (G-T1/§14)
///  9. verify every quantity is strictly positive                     (G-T2)
/// 10. verify item/batch consistency and re-check expiry               (G-E2/G-E4)
/// 11. re-evaluate FEFO per item against live balances                 (G-E3/§16)
/// 12. resolve exactly one active Gudang Cabang                        (G-T1/§14)
/// 13. build the whole posting plan, aggregated per source position     (§20)
/// 14. verify the store holds every aggregated requirement             (G-T2)
/// 15. order `posted_at` against `created_at`                          (§34)
/// 16. write every movement and move every balance                     (G-A1/G-A2)
/// 17. verify the destination balances rose by exactly what was sent
/// 18. guarded UPDATE to `posted`, refused if the document changed
/// ```
///
/// Steps 2 to 14 re-read from the database **inside** the transaction, and that is the
/// whole point of doing them again: the form's numbers are a snapshot, and between
/// opening it and pressing *Posting Distribusi* a batch may have crossed its expiry
/// threshold, another distribution may have drained the store, an older batch may have
/// been restocked — making a previously compliant allocation a FEFO override — or an
/// administrator may have deactivated a room.
///
/// If any step throws, the transaction rolls back: no movement, no change to the store
/// balance, no change to any room balance, no status change, and `posted_at` stays
/// null. That is G-T4 — *"semua baris berhasil atau semua batal"* — and it is why the
/// ledger work goes through `postDistributionInTransaction`, which opens no transaction
/// of its own, rather than through a per-line `postTransfer` that would open one each
/// time.
///
/// ### Concurrency
///
/// Two branch heads posting two documents that together over-draw the store: step 14
/// reads live balances inside the transaction, so whichever commits first wins and the
/// second is refused with a shortfall it can act on. Two devices posting the *same*
/// document: the guarded UPDATE in step 18 carries `status = 'draft'`, so exactly one
/// affects a row and the loser rolls back — movements included, which is precisely why
/// they had to be in the same transaction.
class PostDistributionUseCase {
  PostDistributionUseCase({
    required this._distributions,
    required MasterDataRepository master,
    required this._posting,
    required this._stock,
    this._outbox = const NoopSyncOutboxWriter(),
    DateTime Function()? clock,
  }) : _guards = DistributionGuards(master),
       _clock = clock ?? _defaultClock;

  final DistributionRepository _distributions;
  final DistributionGuards _guards;
  final StockPostingService _posting;
  final DistributionBranchStockReader _stock;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<DistributionPostingResult> call({
    required String actorUserId,
    required String distributionId,
  }) async {
    // 1. Outside the transaction: an inactive account is not a concurrency question,
    // and refusing early keeps the message precise.
    final actor = await _guards.requireBranchHeadActor(actorUserId);

    return _distributions.runInTransaction(() async {
      // 2. The document.
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
        attempted: DistributionStatus.posted,
      );
      _guards.requireTransition(
        actor: actor,
        distribution: distribution,
        to: DistributionStatus.posted,
      );

      // 3. G-T1/G-R2.
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: distribution.branchId,
      );

      // 4–5. Every line, read without a join so a broken reference is reported rather
      // than silently dropped.
      final storedLines = await _distributions.lineReferences(distribution.id);
      _guards.requireNotEmpty(
        distributionId: distribution.id,
        docNumber: distribution.docNumber,
        lines: storedLines,
      );

      // 6. And the joined read must not have swallowed one either — an inner join on a
      // room or item row that is physically gone makes the detail one line shorter,
      // silently, and posting on that basis would move less stock than the document
      // says it did.
      final detail = await _distributions.getDetail(distribution.id);
      if (detail == null) {
        throw DistributionNotFoundFailure(
          'Distribusi tidak ditemukan.',
          distributionId: distributionId,
        );
      }
      _guards.requireLineSetIntegrity(
        distributionId: distribution.id,
        expectedLineIds: storedLines.map((line) => line.id),
        loadedLineIds: detail.lines.map((line) => line.id),
      );

      // 7. The plain id sets, compared against what resolves. Read as sets so a
      // document with twelve batches of one product costs three queries rather than
      // thirty-six.
      await _guards.requireReferencesResolve(
        distributionId: distribution.id,
        lines: storedLines,
        resolvedRoomIds: detail.lines.map((line) => line.roomId).toSet(),
        resolvedItemIds: detail.lines.map((line) => line.itemId).toSet(),
        resolvedBatchIds: detail.lines
            .map((line) => line.batchId)
            .whereType<String>()
            .toSet(),
      );

      final nowUtc = _clock().toUtc();

      // 8. Every room, revalidated. A room deactivated while the draft sat open blocks
      // the posting: the physical destination is not operational, and recording an
      // arrival nobody can act on would be worse than refusing (§32). One invalid room
      // cancels the whole document — there is no partial posting.
      final rooms = <String, MasterRoom>{};
      final roomLocations = <String, MasterLocation>{};
      for (final roomId in storedLines.map((line) => line.roomId).toSet()) {
        final room = await _guards.requireRoomForDistribution(
          branchId: distribution.branchId,
          roomId: roomId,
        );
        rooms[roomId] = room;
        roomLocations[roomId] = await _guards.requireRoomLocation(
          room: room,
          branchId: distribution.branchId,
        );
      }

      // 9–10. Quantities, items, batches and expiry. Loaded once per item so a document
      // with twelve batches of one product costs one item lookup, not twelve.
      final itemsById = <String, MasterItem>{};
      final batchesByLineId = <String, MasterBatch?>{};
      for (final line in storedLines) {
        _guards.requirePositiveQty(qty: line.qty, lineId: line.id);
        final item = itemsById[line.itemId] ??= await _guards
            .requireHistoricalItem(
              distributionId: distribution.id,
              itemId: line.itemId,
            );
        final batch = await _guards.requireBatchConsistency(
          distributionId: distribution.id,
          item: item,
          batchId: line.batchId,
        );
        batchesByLineId[line.id] = batch;
        // G-E4 revalidated at posting time, and this is the run that matters: a batch
        // with two days of shelf life left when the form opened may be past its date
        // now, and distributing it would put unusable goods in a treatment room.
        _guards.requireNotExpired(
          batch: batch,
          nowUtc: nowUtc,
          lineId: line.id,
        );
      }

      // 12. Exactly one active branch store, looked up by type and branch — never a
      // hard-coded id, never guessed when there are none or several, and never accepted
      // archived (§32: an out-of-service store cannot supply goods).
      final source = await _guards.requireBranchStore(distribution.branchId);
      for (final destination in roomLocations.values) {
        _guards.requireDistinctLeg(source: source, destination: destination);
      }

      // 11. FEFO re-evaluated per item against **live** balances, over the item's whole
      // selection across every room (§16). An older batch restocked since the draft was
      // built makes a previously compliant allocation an override — and it then needs
      // the reason the draft never stored, which is exactly what this catches.
      for (final entry in itemsById.entries) {
        final item = entry.value;
        if (!item.hasExpiry) continue;

        final candidates = await _stock.batchCandidates(
          branchStoreLocationId: source.id,
          itemId: item.id,
        );
        final planner = DistributionAllocationPlanner(
          existingLines: storedLines,
          stock: DistributionStockItem(
            itemId: item.id,
            sku: item.sku,
            itemName: item.name,
            categoryId: item.categoryId,
            unit: item.unit,
            hasExpiry: item.hasExpiry,
            expiryAlertDays: item.expiryAlertDays,
            // Only the FEFO evaluation runs off this planner — sufficiency is step 14's
            // job, against per-position balances — but the total is filled in honestly
            // rather than left at zero, so a future caller that *does* ask cannot be
            // handed a number that was never meant to be read.
            availableQty: Quantity.sum(
              candidates.map((candidate) => candidate.availableQty),
            ),
            candidates: candidates,
          ),
        );
        _guards.requireFefoCompliance(
          itemId: item.id,
          itemSku: item.sku,
          candidates: candidates,
          selection: planner.storedAllocations(),
          reasonByBatchId: planner.reasonsWith(const []),
          nowUtc: nowUtc,
        );
      }

      // 13. The whole plan, before the first movement. Every destination resolved,
      // every source position aggregated — which is what makes a failure land before
      // anything is written rather than halfway through (§20).
      final plan = DistributionStockPlanBuilder.build(
        distributionId: distribution.id,
        branchId: distribution.branchId,
        sourceLocationId: source.id,
        lines: storedLines,
        destinationLocationsByRoom: {
          for (final entry in roomLocations.entries) entry.key: entry.value.id,
        },
      );

      // 14. G-T2 against live balances, per **aggregated** source position. Two rooms
      // each taking 3 from a batch holding 5 fails here, and checking them one line at
      // a time would let both pass.
      final requirements = plan.sourceRequirements;
      for (final position in plan.sourcePositions) {
        final item = itemsById[position.itemId]!;
        final available = await _stock.balanceOf(
          branchStoreLocationId: source.id,
          itemId: position.itemId,
          batchId: position.batchId,
        );
        final batchNo = position.batchId == null
            ? null
            : batchesByLineId.values
                  .whereType<MasterBatch>()
                  .where((batch) => batch.id == position.batchId)
                  .firstOrNull
                  ?.batchNo;
        _guards.requireSufficientStock(
          itemId: position.itemId,
          itemSku: item.sku,
          unit: item.unit,
          locationId: source.id,
          batchId: position.batchId,
          batchNo: batchNo,
          requested:
              requirements['${position.itemId}|${position.batchId ?? ''}'] ??
              Quantity.zero(),
          available: available,
        );
      }

      // 15. Ordered against its own creation, on UTC instants and never as text
      // (§34) — a device whose clock is behind must not stamp a document before it
      // existed. Equal instants are accepted: two events really can land on the same
      // microsecond.
      DocumentTimestampPolicy.requireOrdered(
        documentId: distribution.id,
        earlierLabel: 'created_at',
        earlierUtc: distribution.createdAt,
        laterLabel: 'posted_at',
        laterUtc: nowUtc,
        message: DocumentTimestampPolicy.deviceClockBehindMessage,
      );

      // 16. The ledger. `postDistributionInTransaction` opens no transaction of its
      // own: it validates every position, then posts them all, then re-reads the
      // balances.
      final movements = await _posting.postDistributionInTransaction(
        fromLocationId: source.id,
        actorUserId: actor.id,
        distributionId: distribution.id,
        lines: plan.entries
            .map(
              (entry) => DistributionPostingLine(
                lineId: entry.lineId,
                toLocationId: entry.destinationLocationId,
                itemId: entry.itemId,
                batchId: entry.batchId,
                qty: entry.qty,
              ),
            )
            .toList(growable: false),
      );

      // 17. Post-condition of spec §2.5, verified rather than assumed: each room's
      // balance must have risen by exactly what the document sent it. `assert` would be
      // compiled out of a release build, and this is exactly the invariant that has to
      // hold in production — a mismatch here rolls the whole transaction back.
      final expected = DistributionStockPlanBuilder.destinationRequirements(
        plan,
      );
      for (final entry in plan.entries) {
        final key = '${entry.roomId}|${entry.itemId}|${entry.batchId ?? ''}';
        final wanted = expected[key];
        if (wanted == null) continue;
        final onHand = await _stock.balanceOf(
          branchStoreLocationId: entry.destinationLocationId,
          itemId: entry.itemId,
          batchId: entry.batchId,
        );
        if (onHand < wanted) {
          throw InsufficientBranchStockFailure(
            'Saldo ruangan setelah distribusi (${onHand.format()}) lebih kecil '
            'dari jumlah yang didistribusikan (${wanted.format()}). Distribusi '
            'dibatalkan.',
            itemId: entry.itemId,
            locationId: entry.destinationLocationId,
            batchId: entry.batchId,
            available: onHand,
            requested: wanted,
          );
        }
        expected.remove(key);
      }

      // 18. The document. The guarded UPDATE re-checks `draft` *and* that at least one
      // live line remains, so a second device posting — or removing the last line —
      // between step 4 and here yields zero rows, which rolls the movements above back.
      final posted = await _distributions.markPosted(
        distributionId: distribution.id,
        postedAtUtc: nowUtc,
      );
      if (!posted) _guards.concurrentUpdate(distribution);

      await _outbox.enqueueCurrentAggregate(
        operation: SyncOperationType.postDistribution,
        aggregateType: SyncAggregateType.distribution,
        aggregateId: distribution.id,
        actorUserId: actor.id,
        occurredAtUtc: nowUtc,
      );

      final updated = await _distributions.getById(distribution.id);
      if (updated == null) {
        throw DistributionNotFoundFailure(
          'Distribusi tidak ditemukan setelah posting.',
          distributionId: distribution.id,
        );
      }

      return DistributionPostingResult(
        distribution: updated,
        movements: movements,
        branchStore: source,
        roomLocations: roomLocations,
        plan: plan,
        progress: detail.progressOn(nowUtc),
      );
    });
  }
}
