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
import '../models/consumption_models.dart';
import '../repositories/consumption_repository.dart';
import '../services/consumption_stock_plan_builder.dart';
import '../services/consumption_stock_reader.dart';
import 'consumption_guards.dart';

/// What a posted Pemakaian did (§21.6).
class ConsumptionPostingResult {
  const ConsumptionPostingResult({
    required this.consumption,
    required this.movements,
    required this.room,
    required this.roomLocation,
    required this.plan,
    required this.progress,
  });

  final Consumption consumption;

  /// One append-only ledger row per line (G-A1). Every line consumes stock — a zero
  /// quantity cannot exist — so this always has exactly as many entries as the document
  /// has lines.
  final List<InventoryMovement> movements;

  /// The room the goods left, and the stock location whose balance fell. There is no
  /// counterpart field: nothing was credited (§19).
  final MasterRoom room;
  final MasterLocation roomLocation;

  /// The validated plan the posting executed.
  final ConsumptionPostingPlan plan;

  /// The counters the document was posted with.
  final ConsumptionProgress progress;

  int get lineCount => plan.lineCount;

  int get itemCount => plan.itemCount;

  /// Total quantity that left the system.
  Quantity get totalQty => plan.totalQty;
}

/// `draft → posted` — the write this milestone exists for (§20/§21.6).
///
/// Everything happens in **one** database transaction, and the order is chosen so that
/// nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive account or a non-Perawat        (§14)
///  2. load the document, verify ownership and branch                     (§14)
///  3. guard `draft`                                                      (G-S1)
///  4. verify the transition belongs to this role                         (§13)
///  5. read every line without a join                                     (§22)
///  6. refuse an empty document
///  7. verify the plain line set and the joined read agree                (§22)
///  8. verify every item and batch id still resolves                      (§33)
///  9. re-verify the room is active and in the actor's branch             (§15)
/// 10. resolve the room's single stock location                           (§15)
/// 11. verify every quantity is positive                                  (§18)
/// 12. verify item/batch consistency and re-check **expiry**              (§17)
/// 13. build the whole posting plan, aggregated per source position        (§20)
/// 14. verify the room holds every aggregated requirement                 (§18)
/// 15. order `posted_at` against `created_at`                             (§35)
/// 16. write every movement and reduce every room balance                  (G-A1/G-A2)
/// 17. verify no balance came out negative
/// 18. guarded UPDATE to `posted`, refused if the document changed
/// ```
///
/// Steps 2 to 14 re-read from the database **inside** the transaction, and that is the
/// whole point of doing them again: the form's numbers are a snapshot, and between
/// opening it and pressing *Posting Pemakaian* another consumption may have drained the
/// batch, a distribution may have topped it up, an administrator may have closed the
/// room, or the operational day may have rolled over in GMT+8 and taken a batch past its
/// expiry date.
///
/// If any step throws, the transaction rolls back: no movement, no change to any balance,
/// no status change, `posted_at` and `posted_by` stay null, and every line survives so
/// the nurse can fix what was wrong. That is why the ledger work goes through
/// `postConsumptionLinesInTransaction`, which opens no transaction of its own, rather
/// than through a per-line method that would open one each time and commit halfway
/// through a document.
///
/// ### Why the rollback matters as much here as on a disposal
///
/// A shipment's outbound leg is matched by a receipt's inbound one; a distribution debits
/// a store and credits a room. A `consumption` movement has neither — stock leaves and
/// nothing gains it (§19) — so a partially committed consumption would be quantities that
/// simply vanished, with nothing in the ledger to reconcile them against. The transaction
/// boundary is the only thing standing between that and the database.
///
/// ### Concurrency
///
/// Two documents that together over-draw one position: step 14 reads live balances inside
/// the transaction, so whichever commits first wins and the second is refused with a
/// shortfall it can act on. Two devices posting the *same* document: the guarded UPDATE in
/// step 18 carries `status = 'draft'` **and** `created_by = ?`, so exactly one affects a
/// row and the loser rolls back — movements included, which is precisely why they had to
/// be in the same transaction.
class PostConsumptionUseCase {
  PostConsumptionUseCase({
    required this._consumptions,
    required MasterDataRepository master,
    required this._posting,
    required this._stock,
    this._outbox = const NoopSyncOutboxWriter(),
    DateTime Function()? clock,
  }) : _guards = ConsumptionGuards(master),
       _clock = clock ?? _defaultClock;

  final ConsumptionRepository _consumptions;
  final ConsumptionGuards _guards;
  final StockPostingService _posting;
  final RoomConsumptionStockReader _stock;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<ConsumptionPostingResult> call({
    required String actorUserId,
    required String consumptionId,
  }) async {
    // 1. Outside the transaction: an inactive account is not a concurrency question, and
    // refusing early keeps the message precise.
    final actor = await _guards.requireNurseActor(actorUserId);

    return _consumptions.runInTransaction(() async {
      // 2–4. The document, its owner, its branch and its status.
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
        attempted: ConsumptionStatus.posted,
      );
      _guards.requireTransition(
        actor: actor,
        consumption: consumption,
        to: ConsumptionStatus.posted,
      );

      // 5–6. Every line, read without a join so a broken reference is reported rather
      // than silently dropped.
      final storedLines = await _consumptions.lineReferences(consumption.id);
      _guards.requireNotEmpty(
        consumptionId: consumption.id,
        docNumber: consumption.docNumber,
        lines: storedLines,
      );

      // 7. And the joined read must not have swallowed one either — an inner join on an
      // item row that is physically gone makes the detail one line shorter, silently, and
      // posting on that basis would consume less stock than the document says it did.
      final detail = await _consumptions.getDetail(consumption.id);
      if (detail == null) {
        // The header was loaded a few lines ago, so its absence from the *joined* read
        // cannot mean "no such document": it means one of the header's own inner joins
        // dropped it — its branch, its room or the nurse who created it is physically
        // gone. §33 asks for an explicit failure that names the broken reference rather
        // than a generic "not found", because the two need different answers: one asks
        // the user to pick again, the other asks an administrator to repair data.
        //
        // Which of the three it is cannot be told apart here without three more queries,
        // and `rooms` is the one a consumption cannot function without — so that is what
        // the failure names, and the message sends the reader to an administrator either
        // way.
        _guards.historicalReferenceMissing(
          consumptionId: consumption.id,
          entity: 'rooms',
          id: consumption.roomId,
        );
      }
      _guards.requireLineSetIntegrity(
        consumptionId: consumption.id,
        expectedLineIds: storedLines.map((line) => line.id),
        loadedLineIds: detail.lines.map((line) => line.id),
      );

      // 8. The plain id sets, compared against what resolves. Read as sets so a document
      // with twelve batches of one product costs two comparisons rather than twenty-four
      // lookups. Null batch ids contribute nothing, which is what makes an item without
      // expiry pass rather than look like a broken reference.
      _guards.requireReferencesResolve(
        consumptionId: consumption.id,
        lines: storedLines,
        resolvedItemIds: detail.lines.map((line) => line.itemId).toSet(),
        resolvedBatchIds: detail.lines
            .map((line) => line.batchId)
            .whereType<String>()
            .toSet(),
      );

      final nowUtc = _clock().toUtc();

      // 9–10. The room and its location, re-resolved and re-authorised. Unlike a
      // disposal, there is **no** historical relaxation here: a room deactivated while
      // the draft sat open blocks the posting (§15), because recording usage in a room
      // the clinic has closed asserts clinical activity in a place nobody is working. The
      // nurse can still read the draft; what is refused is turning it into a ledger fact.
      final room = await _guards.requireRoomForConsumption(
        branchId: consumption.branchId,
        roomId: consumption.roomId,
      );
      final location = await _guards.requireRoomLocation(
        room: room,
        branchId: consumption.branchId,
      );

      // 11–12. Quantities, items, batches and expiry. Loaded once per item so a document
      // with twelve batches of one product costs one item lookup, not twelve.
      final itemsById = <String, MasterItem>{};
      final batchesById = <String, MasterBatch>{};
      for (final line in storedLines) {
        _guards.requirePositiveQty(qty: line.qty, lineId: line.id);
        final item = itemsById[line.itemId] ??= await _guards
            .requireHistoricalItem(
              consumptionId: consumption.id,
              itemId: line.itemId,
            );
        final batch = await _guards.requireBatchConsistency(
          consumptionId: consumption.id,
          item: item,
          batchId: line.batchId,
        );
        if (batch != null) batchesById[batch.id] = batch;
        // §17 revalidated at posting time, and this is the run that matters. A batch that
        // expired while the draft sat open is refused here however long the line has been
        // on the document — its stock leaves through a Pemusnahan, not through this.
        _guards.requireNotExpired(
          batch: batch,
          nowUtc: nowUtc,
          lineId: line.id,
        );
      }

      // 13. The whole plan, before the first movement. Every position aggregated and
      // every movement note composed — which is what makes a failure land before anything
      // is written rather than halfway through (§20).
      final plan = ConsumptionStockPlanBuilder.build(
        consumptionId: consumption.id,
        roomId: room.id,
        roomLocationId: location.id,
        note: consumption.note,
        lines: storedLines,
      );

      // 14. §18 against live balances, per **aggregated** source position. The partial
      // unique indexes already stop one document holding a position twice, but an index
      // is not the authority on a document two devices assembled concurrently, and
      // summing before comparing costs nothing.
      final requirements = plan.sourceRequirements;
      for (final position in plan.sourcePositions) {
        final item = itemsById[position.itemId]!;
        final batchId = position.batchId;
        final batch = batchId == null ? null : batchesById[batchId];
        final available = await _stock.balanceOf(
          roomLocationId: location.id,
          itemId: position.itemId,
          batchId: batchId,
        );
        _guards.requireSufficientStock(
          itemId: position.itemId,
          itemSku: item.sku,
          unit: item.unit,
          locationId: location.id,
          batchId: batchId,
          batchNo: batch?.batchNo,
          requested:
              requirements['${position.itemId}|${batchId ?? ''}'] ??
              Quantity.zero(),
          available: available,
        );
      }

      // 15. Ordered against its own creation, on UTC instants and never as text (§35) —
      // a device whose clock is behind must not stamp a document before it existed. Equal
      // instants are accepted: two events really can land on the same microsecond.
      DocumentTimestampPolicy.requireOrdered(
        documentId: consumption.id,
        earlierLabel: 'created_at',
        earlierUtc: consumption.createdAt,
        laterLabel: 'posted_at',
        laterUtc: nowUtc,
        message: DocumentTimestampPolicy.deviceClockBehindMessage,
      );

      // 16–17. The ledger. `postConsumptionLinesInTransaction` opens no transaction of
      // its own: it validates every position, then posts them all, then re-reads the
      // balances and refuses to let a negative one commit.
      final movements = await _posting.postConsumptionLinesInTransaction(
        fromLocationId: location.id,
        actorUserId: actor.id,
        consumptionId: consumption.id,
        lines: plan.entries
            .map(
              (entry) => ConsumptionPostingLine(
                lineId: entry.lineId,
                itemId: entry.itemId,
                batchId: entry.batchId,
                qty: entry.qty,
                // Nullable by design: a consumption note is optional (§8), so a movement
                // with no note is a compliant movement.
                note: entry.note,
              ),
            )
            .toList(growable: false),
      );

      // 18. The document. The guarded UPDATE re-checks `draft`, that the acting nurse is
      // still its creator **and** that at least one live line remains, so a second device
      // posting — or removing the last line — between step 5 and here yields zero rows,
      // which rolls the movements above back.
      final posted = await _consumptions.markPosted(
        consumptionId: consumption.id,
        actorUserId: actor.id,
        postedAtUtc: nowUtc,
        postedBy: actor.id,
      );
      if (!posted) _guards.concurrentUpdate(consumption);

      await _outbox.enqueueCurrentAggregate(
        operation: SyncOperationType.postConsumption,
        aggregateType: SyncAggregateType.consumption,
        aggregateId: consumption.id,
        actorUserId: actor.id,
        occurredAtUtc: nowUtc,
      );

      final updated = await _consumptions.getById(consumption.id);
      if (updated == null) {
        throw ConsumptionNotFoundFailure(
          'Pemakaian tidak ditemukan setelah posting.',
          consumptionId: consumption.id,
        );
      }

      return ConsumptionPostingResult(
        consumption: updated,
        movements: movements,
        room: room,
        roomLocation: location,
        plan: plan,
        progress: detail.progressOn(nowUtc),
      );
    });
  }
}
