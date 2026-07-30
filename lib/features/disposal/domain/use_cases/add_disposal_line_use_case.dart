import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/disposal_models.dart';
import '../repositories/disposal_repository.dart';
import '../services/disposal_reason_policy.dart';
import '../services/disposal_stock_reader.dart';
import 'disposal_guards.dart';

/// Adds one expired position to a `draft` Pemusnahan (§22.3).
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive account or one with no scope   (§14)
///  2. load the document, guard `draft`                                  (G-S1)
///  3. verify the source is still within the actor's scope               (§15)
///  4. verify the item resolves — deactivated rows included              (§17)
///  5. verify the item is batch-tracked and the batch is its own         (§16)
///  6. verify the batch has **actually expired** right now               (G-E7)
///  7. verify the position is not already on the document
///  8. verify the quantity is positive and within the live balance       (§18)
///  9. insert the line
/// ```
///
/// Step 6 is the one this milestone exists for, and it is asked against the clock
/// rather than against whatever the picker showed. A form left open across midnight
/// GMT+8 saw a different set of eligible batches than the one that exists when the
/// button is pressed — in both directions: a batch may have become eligible, and a
/// batch the user selected may still be in date if their device's clock ran ahead.
///
/// Step 8 reads the balance **now**, and it is still not the authority: the posting
/// re-reads it inside its own transaction. What this check buys is that an
/// impossible line is refused while the user can still do something about it,
/// rather than at the end when the whole document fails.
///
/// No movement is written and no balance changes. Adding a line to a document is not
/// a stock event; posting it is. In particular a draft **does not reserve stock** —
/// two drafts may both name the same expired batch, and whichever posts first wins
/// (§18).
class AddDisposalLineUseCase {
  AddDisposalLineUseCase({
    required this._disposals,
    required MasterDataRepository master,
    required this._stock,
    DateTime Function()? clock,
  }) : _guards = DisposalGuards(master),
       _clock = clock ?? _defaultClock;

  final DisposalRepository _disposals;
  final DisposalGuards _guards;
  final DisposalStockReader _stock;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<DisposalLineReference> call({
    required String actorUserId,
    required String disposalId,
    required String itemId,
    required String batchId,
    required Quantity qty,
    String? note,
  }) async {
    final actor = await _guards.requireDisposalActor(actorUserId);
    final nowUtc = _clock().toUtc();

    return _disposals.runInTransaction(() async {
      final disposal = await _disposals.getById(disposalId);
      if (disposal == null) {
        throw DisposalNotFoundFailure(
          'Pemusnahan tidak ditemukan.',
          disposalId: disposalId,
        );
      }
      _guards.requireStatus(disposal: disposal, expected: DisposalStatus.draft);

      final source = await _guards.requireSourceLocation(
        actor: actor,
        locationId: disposal.sourceLocationId,
        // Adding to an existing draft completes work already begun; a shelf
        // archived in the meantime still physically holds the expired goods (§15).
        requireOperational: false,
        disposalId: disposal.id,
      );
      await _guards.requireSourceRoom(actor: actor, location: source);
      _guards.requireScopeMatches(actor: actor, source: source);

      final item = await _guards.requireItem(
        disposalId: disposal.id,
        itemId: itemId,
      );
      final batch = await _guards.requireBatchConsistency(
        disposalId: disposal.id,
        item: item,
        batchId: batchId,
      );
      _guards.requireExpired(batch: batch, nowUtc: nowUtc);

      final existing = await _disposals.lineReferences(disposal.id);
      _guards.requirePositionFree(
        disposalId: disposal.id,
        itemId: item.id,
        batchId: batch.id,
        existing: existing,
      );

      _guards.requirePositiveQty(qty: qty);

      final available = await _stock.balanceOf(
        sourceLocationId: source.id,
        itemId: item.id,
        batchId: batch.id,
      );
      if (!available.isPositive) {
        _guards.positionHasNoStock(
          itemId: item.id,
          itemSku: item.sku,
          batchNo: batch.batchNo,
          locationId: source.id,
        );
      }
      _guards.requireSufficientStock(
        itemId: item.id,
        itemSku: item.sku,
        unit: item.unit,
        locationId: source.id,
        batchId: batch.id,
        batchNo: batch.batchNo,
        requested: qty,
        available: available,
      );

      return _disposals.addLine(
        disposalId: disposal.id,
        itemId: item.id,
        batchId: batch.id,
        qty: qty,
        note: DisposalReasonPolicy.normalize(note),
      );
    });
  }
}
