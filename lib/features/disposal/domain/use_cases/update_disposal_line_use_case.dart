import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/disposal_models.dart';
import '../repositories/disposal_repository.dart';
import '../services/disposal_reason_policy.dart';
import '../services/disposal_stock_reader.dart';
import 'disposal_guards.dart';

/// Changes the quantity or the note of one line on a `draft` Pemusnahan (§22.4).
///
/// What it cannot change is the point: `disposal_id`, `item_id` and `batch_id` are
/// out of reach here and in the SQL beneath. Another batch is a *different*
/// position, with its own expiry date and its own balance, and editing one in place
/// would slip past both of those checks — a line pointing at a batch that has not
/// expired, sitting on a document that was validated when it named a different one.
/// Swapping a position is remove-then-add, and both halves are validated.
///
/// Everything that made the line legal in the first place is asked again:
///
/// ```
/// 1. actor, scope and source, exactly as the add path asks them        (§14/§15)
/// 2. the parent is still a draft                                       (G-S1)
/// 3. the line is still on this document
/// 4. the item and batch still resolve                                  (§17)
/// 5. the batch is **still expired** right now                          (G-E7)
/// 6. the new quantity is positive and within the live balance          (§18)
/// ```
///
/// Step 5 is not redundant with the add path. Expiry is a function of the
/// operational date, and a draft can sit open across a midnight in GMT+8 — so a
/// position that was eligible when it was added may still be eligible, may have
/// become *more* obviously so, or, on a device whose clock was ahead, may turn out
/// never to have been. The check is asked wherever a line is touched, and once more
/// inside the posting transaction.
class UpdateDisposalLineUseCase {
  UpdateDisposalLineUseCase({
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
    required String lineId,
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
        requireOperational: false,
        disposalId: disposal.id,
      );
      await _guards.requireSourceRoom(actor: actor, location: source);
      _guards.requireScopeMatches(actor: actor, source: source);

      final line = _guards.requireLineOf(
        disposalId: disposal.id,
        lineId: lineId,
        line: await _disposals.lineReferenceById(lineId),
      );

      final item = await _guards.requireItem(
        disposalId: disposal.id,
        itemId: line.itemId,
      );
      final batch = await _guards.requireBatchConsistency(
        disposalId: disposal.id,
        item: item,
        batchId: line.batchId,
      );
      _guards.requireExpired(batch: batch, nowUtc: nowUtc, lineId: line.id);

      _guards.requirePositiveQty(qty: qty, lineId: line.id);

      final available = await _stock.balanceOf(
        sourceLocationId: source.id,
        itemId: item.id,
        batchId: batch.id,
      );
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

      final updated = await _disposals.updateDraftLine(
        disposalId: disposal.id,
        lineId: line.id,
        qty: qty,
        note: DisposalReasonPolicy.normalize(note),
      );
      if (!updated) _guards.concurrentUpdate(disposal);

      final result = await _disposals.lineReferenceById(line.id);
      if (result == null) {
        throw DisposalLineNotFoundFailure(
          'Baris pemusnahan tidak ditemukan setelah pembaruan.',
          lineId: line.id,
        );
      }
      return result;
    });
  }
}
