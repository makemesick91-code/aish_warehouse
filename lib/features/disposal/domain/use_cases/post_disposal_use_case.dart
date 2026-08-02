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
import '../models/disposal_models.dart';
import '../repositories/disposal_repository.dart';
import '../services/disposal_stock_plan_builder.dart';
import '../services/disposal_stock_reader.dart';
import 'disposal_guards.dart';

/// What a posted Pemusnahan did (§22.6).
class DisposalPostingResult {
  const DisposalPostingResult({
    required this.disposal,
    required this.movements,
    required this.source,
    required this.plan,
    required this.progress,
  });

  final Disposal disposal;

  /// One append-only ledger row per line (G-A1). Every line destroys stock — a zero
  /// quantity cannot exist — so this always has exactly as many entries as the
  /// document has lines.
  final List<InventoryMovement> movements;

  /// The location that was reduced. There is no counterpart field: nothing was
  /// credited (§20).
  final MasterLocation source;

  /// The validated plan the posting executed.
  final DisposalPostingPlan plan;

  /// The counters the document was posted with.
  final DisposalProgress progress;

  int get lineCount => plan.lineCount;

  int get itemCount => plan.itemCount;

  /// Total quantity that left the system.
  Quantity get totalQty => plan.totalQty;
}

/// `draft → posted` — the write this milestone exists for (§21/§22.6, G-E7).
///
/// Everything happens in **one** database transaction, and the order is chosen so
/// that nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive account or one with no scope   (§14)
///  2. load the document, guard `draft`                                  (G-S1)
///  3. verify the transition belongs to this role                        (§13)
///  4. read every line without a join                                    (§23)
///  5. refuse an empty document
///  6. verify the plain line set and the joined read agree                (§23)
///  7. verify every item and batch id still resolves                      (§34)
///  8. resolve the source location and verify it is still in scope        (§15)
///  9. verify the reason G-E7 demands                                     (§19)
/// 10. verify every quantity is positive                                  (§18)
/// 11. verify item/batch consistency and re-check **expiry**              (G-E7)
/// 12. build the whole posting plan, aggregated per source position        (§21)
/// 13. verify the shelf holds every aggregated requirement                (§18)
/// 14. order `posted_at` against `created_at`                             (§36)
/// 15. write every movement and reduce every balance                      (G-A1/G-A2)
/// 16. verify no balance came out negative
/// 17. guarded UPDATE to `posted`, refused if the document changed
/// ```
///
/// Steps 2 to 13 re-read from the database **inside** the transaction, and that is
/// the whole point of doing them again: the form's numbers are a snapshot, and
/// between opening it and pressing *Posting Pemusnahan* another disposal may have
/// drained the batch, an opname may have adjusted it, or the operational day may
/// have rolled over in GMT+8.
///
/// If any step throws, the transaction rolls back: no movement, no change to any
/// balance, no status change, `posted_at` and `posted_by` stay null, and every line
/// survives so the user can fix what was wrong. That is why the ledger work goes
/// through `postDisposalLinesInTransaction`, which opens no transaction of its own,
/// rather than through a per-line `postDisposal` that would open one each time and
/// commit halfway through a document.
///
/// ### Why the rollback matters more here than anywhere else
///
/// Every other posting in this application has a counter-entry: a shipment's
/// outbound leg is matched by a receipt's inbound one, a distribution debits a store
/// and credits a room. A `disposal` movement has none — stock leaves and nothing
/// gains it (§20) — so a partially committed disposal would be quantities that
/// simply vanished, with nothing in the ledger to reconcile them against. The
/// transaction boundary is the only thing standing between that and the database.
///
/// ### Concurrency
///
/// Two documents that together over-draw one expired batch: step 13 reads live
/// balances inside the transaction, so whichever commits first wins and the second
/// is refused with a shortfall it can act on. Two devices posting the *same*
/// document: the guarded UPDATE in step 17 carries `status = 'draft'`, so exactly
/// one affects a row and the loser rolls back — movements included, which is
/// precisely why they had to be in the same transaction.
class PostDisposalUseCase {
  PostDisposalUseCase({
    required this._disposals,
    required MasterDataRepository master,
    required this._posting,
    required this._stock,
    this._outbox = const NoopSyncOutboxWriter(),
    DateTime Function()? clock,
  }) : _guards = DisposalGuards(master),
       _clock = clock ?? _defaultClock;

  final DisposalRepository _disposals;
  final DisposalGuards _guards;
  final StockPostingService _posting;
  final DisposalStockReader _stock;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<DisposalPostingResult> call({
    required String actorUserId,
    required String disposalId,
  }) async {
    // 1. Outside the transaction: an inactive account is not a concurrency question,
    // and refusing early keeps the message precise.
    final actor = await _guards.requireDisposalActor(actorUserId);

    return _disposals.runInTransaction(() async {
      // 2. The document.
      final disposal = await _disposals.getById(disposalId);
      if (disposal == null) {
        throw DisposalNotFoundFailure(
          'Pemusnahan tidak ditemukan.',
          disposalId: disposalId,
        );
      }
      _guards.requireStatus(
        disposal: disposal,
        expected: DisposalStatus.draft,
        attempted: DisposalStatus.posted,
      );
      // 3. The structural check that no code path invents a transition the policy
      // does not list, and that this role is one of the two that may drive it.
      _guards.requireTransition(
        actor: actor,
        disposal: disposal,
        to: DisposalStatus.posted,
      );

      // 4–5. Every line, read without a join so a broken reference is reported rather
      // than silently dropped.
      final storedLines = await _disposals.lineReferences(disposal.id);
      _guards.requireNotEmpty(
        disposalId: disposal.id,
        docNumber: disposal.docNumber,
        lines: storedLines,
      );

      // 6. And the joined read must not have swallowed one either — an inner join on
      // an item or batch row that is physically gone makes the detail one line
      // shorter, silently, and posting on that basis would destroy less stock than
      // the document says it did.
      final detail = await _disposals.getDetail(disposal.id);
      if (detail == null) {
        throw DisposalNotFoundFailure(
          'Pemusnahan tidak ditemukan.',
          disposalId: disposalId,
        );
      }
      _guards.requireLineSetIntegrity(
        disposalId: disposal.id,
        expectedLineIds: storedLines.map((line) => line.id),
        loadedLineIds: detail.lines.map((line) => line.id),
      );

      // 7. The plain id sets, compared against what resolves. Read as sets so a
      // document with twelve batches of one product costs two comparisons rather
      // than twenty-four lookups.
      _guards.requireReferencesResolve(
        disposalId: disposal.id,
        lines: storedLines,
        resolvedItemIds: detail.lines.map((line) => line.itemId).toSet(),
        resolvedBatchIds: detail.lines.map((line) => line.batchId).toSet(),
      );

      final nowUtc = _clock().toUtc();

      // 8. The source, re-resolved and re-authorised. `requireOperational: false`
      // is the historical-completion rule §15 states: a shelf archived while the
      // draft sat open still physically holds the expired goods, and taking them
      // off it lowers risk rather than moving stock somewhere nobody is working.
      // What is *not* relaxed is that the exact row must still exist — a missing
      // source is an explicit failure, never a substitution.
      final source = await _guards.requireSourceLocation(
        actor: actor,
        locationId: disposal.sourceLocationId,
        requireOperational: false,
        disposalId: disposal.id,
      );
      await _guards.requireSourceRoom(actor: actor, location: source);
      _guards.requireScopeMatches(actor: actor, source: source);

      // 9. G-E7's note, validated in Dart rather than left to the database CHECK.
      final reason = _guards.requireReason(
        disposalId: disposal.id,
        reason: disposal.reason,
      );

      // 10–11. Quantities, items, batches and expiry. Loaded once per item so a
      // document with twelve batches of one product costs one item lookup, not
      // twelve.
      final itemsById = <String, MasterItem>{};
      final batchesById = <String, MasterBatch>{};
      for (final line in storedLines) {
        _guards.requirePositiveQty(qty: line.qty, lineId: line.id);
        final item = itemsById[line.itemId] ??= await _guards.requireItem(
          disposalId: disposal.id,
          itemId: line.itemId,
        );
        final batch = batchesById[line.batchId] ??= await _guards
            .requireBatchConsistency(
              disposalId: disposal.id,
              item: item,
              batchId: line.batchId,
            );
        // G-E7 revalidated at posting time, and this is the run that matters — in
        // both directions. A batch that expired while the draft sat open is now
        // legitimately disposable; a batch a stale form put on the document while
        // it was still in date is refused, whatever reason was typed.
        _guards.requireExpired(batch: batch, nowUtc: nowUtc, lineId: line.id);
      }

      // 12. The whole plan, before the first movement. Every position aggregated and
      // every movement note composed — which is what makes a failure land before
      // anything is written rather than halfway through (§21).
      final plan = DisposalStockPlanBuilder.build(
        disposalId: disposal.id,
        sourceLocationId: source.id,
        reason: reason,
        lines: storedLines,
      );

      // 13. §18 against live balances, per **aggregated** source position. The
      // partial unique index already stops one document holding a position twice,
      // but an index is not the authority on a document two devices assembled
      // concurrently, and summing before comparing costs nothing.
      final requirements = plan.sourceRequirements;
      for (final position in plan.sourcePositions) {
        final item = itemsById[position.itemId]!;
        final batch = batchesById[position.batchId]!;
        final available = await _stock.balanceOf(
          sourceLocationId: source.id,
          itemId: position.itemId,
          batchId: position.batchId,
        );
        _guards.requireSufficientStock(
          itemId: position.itemId,
          itemSku: item.sku,
          unit: item.unit,
          locationId: source.id,
          batchId: position.batchId,
          batchNo: batch.batchNo,
          requested:
              requirements['${position.itemId}|${position.batchId}'] ??
              Quantity.zero(),
          available: available,
        );
      }

      // 14. Ordered against its own creation, on UTC instants and never as text
      // (§36) — a device whose clock is behind must not stamp a document before it
      // existed. Equal instants are accepted: two events really can land on the same
      // microsecond.
      DocumentTimestampPolicy.requireOrdered(
        documentId: disposal.id,
        earlierLabel: 'created_at',
        earlierUtc: disposal.createdAt,
        laterLabel: 'posted_at',
        laterUtc: nowUtc,
        message: DocumentTimestampPolicy.deviceClockBehindMessage,
      );

      // 15–16. The ledger. `postDisposalLinesInTransaction` opens no transaction of
      // its own: it validates every position, then posts them all, then re-reads the
      // balances and refuses to let a negative one commit.
      final movements = await _posting.postDisposalLinesInTransaction(
        fromLocationId: source.id,
        actorUserId: actor.id,
        disposalId: disposal.id,
        lines: plan.entries
            .map(
              (entry) => DisposalPostingLine(
                lineId: entry.lineId,
                itemId: entry.itemId,
                batchId: entry.batchId,
                qty: entry.qty,
                // Non-null by construction: the plan builder refuses to produce an
                // entry without one, because G-E7 requires every disposal movement
                // to carry a note.
                note: entry.note!,
              ),
            )
            .toList(growable: false),
      );

      // 17. The document. The guarded UPDATE re-checks `draft`, that at least one
      // live line remains **and** that the reason is still there, so a second device
      // posting — or removing the last line, or clearing the reason — between step 4
      // and here yields zero rows, which rolls the movements above back.
      final posted = await _disposals.markPosted(
        disposalId: disposal.id,
        postedAtUtc: nowUtc,
        postedBy: actor.id,
      );
      if (!posted) _guards.concurrentUpdate(disposal);

      await _outbox.enqueueCurrentAggregate(
        operation: SyncOperationType.postDisposal,
        aggregateType: SyncAggregateType.disposal,
        aggregateId: disposal.id,
        actorUserId: actor.id,
        occurredAtUtc: nowUtc,
      );

      final updated = await _disposals.getById(disposal.id);
      if (updated == null) {
        throw DisposalNotFoundFailure(
          'Pemusnahan tidak ditemukan setelah posting.',
          disposalId: disposal.id,
        );
      }

      return DisposalPostingResult(
        disposal: updated,
        movements: movements,
        source: source,
        plan: plan,
        progress: detail.progressOn(nowUtc),
      );
    });
  }
}
