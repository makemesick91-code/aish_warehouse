import '../../../../core/enums/app_enums.dart';
import '../../../inventory/domain/models/inventory_models.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/goods_return_models.dart';
import '../repositories/goods_return_repository.dart';
import 'goods_return_guards.dart';

/// `shipped → received` — the Warehouse counts the goods back in and the ledger moves
/// (§21/§22).
///
/// The only use case in this milestone that writes to the ledger, and everything it
/// does happens inside **one** transaction: the movements, the Warehouse balances, the
/// status, the timestamp, the receiving actor and the Warehouse note. A failure
/// anywhere rolls all of them back, so the outcomes are exactly two — the whole return
/// is counted in, or nothing happened and the document is still `shipped`.
///
/// ### The order of operations is the design
///
/// Everything that can refuse runs **before** the first movement is written. That is
/// not merely tidy: a rollback undoes database work, but a partially-validated document
/// that got half way through posting and then hit a missing batch would have written
/// ledger rows for the positions before it — and while the transaction does remove
/// them, the *reason* to validate first is that the failure message should name the
/// real problem rather than whichever position happened to be next.
///
/// ### Segregation of duties is asked three times
///
/// Here, in `GoodsReturnAccessPolicy` where the button reads it, and inside the SQL
/// predicate of `markReceived`. Three times because a Kepala Cabang who raised a return
/// and has since moved to the Warehouse team passes every *role* check in the
/// application — G-R4 is about the person, not the job title, and only the id
/// comparison catches that (§15).
///
/// ### There is no partial receive
///
/// No quantity parameter, no per-line confirmation, no "received 3 of 5". §16.16 is the
/// decision and the reasoning is physical: this document is a manifest of goods that
/// were rejected as a set, and a Warehouse user who opens the box and finds it does not
/// match should **not** be able to quietly write down what they actually found. That
/// would replace the branch's account with the Warehouse's, silently, with no record of
/// the disagreement. So a mismatch blocks the confirmation and stays a residual
/// operational issue for people to resolve — which is the honest outcome, because the
/// goods really are wrong and the ledger should not pretend otherwise.
class ReceiveGoodsReturnUseCase {
  ReceiveGoodsReturnUseCase({
    required this._returns,
    required MasterDataRepository master,
    required this._posting,
    DateTime Function()? clock,
  }) : _guards = GoodsReturnGuards(master),
       _clock = clock ?? _defaultClock;

  final GoodsReturnRepository _returns;
  final GoodsReturnGuards _guards;
  final StockPostingService _posting;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<GoodsReturnDetail> call({
    required String actorUserId,
    required String goodsReturnId,
    String? warehouseNote,
  }) {
    return _returns.runInTransaction(() async {
      // 1–3. The actor, re-read from the database (O-8). No branch is required: a
      // Petugas Warehouse operates Warehouse Pusat, which belongs to no branch.
      final actor = await _guards.requireWarehouseActor(actorUserId);

      // 4–5. The document and its status.
      final goodsReturn = _guards.requireDocument(
        goodsReturn: await _returns.getById(goodsReturnId),
        goodsReturnId: goodsReturnId,
      );
      _guards.requireStatus(
        goodsReturn: goodsReturn,
        expected: GoodsReturnStatus.shipped,
        attempted: GoodsReturnStatus.received,
      );
      _guards.requireTransition(
        actor: actor,
        goodsReturn: goodsReturn,
        to: GoodsReturnStatus.received,
      );

      // 6–7. G-R4. Deliberately **not** a branch check: this is the one document where
      // a Warehouse user legitimately reads across every branch, and what protects the
      // workflow is that they may not have been either of the first two actors (§15).
      _guards.requireSegregationOfDuties(
        actor: actor,
        goodsReturn: goodsReturn,
      );

      // 8. The Good Receipt must still exist and still be posted (§37). Note what this
      // does *not* demand: the branch may since have been deactivated, and the return
      // is still received — the goods are physically at the Warehouse door, and
      // refusing them because the sender closed would leave a box with no document.
      _guards.requireHistoricalGoodReceipt(
        goodsReturn: goodsReturn,
        receiptStatus: await _returns.goodReceiptStatusOf(goodsReturn.grId),
      );

      // 9–15. The snapshot, verified against the receipt's rejections one last time:
      // the plain id list first, then the joined read checked against it, then every
      // line's item, batch, quantity and reason. An inner-join data loss is reported
      // rather than quietly reducing what gets credited (§26).
      //
      // Expiry is not among the checks, and its absence is the rule: G-E5 makes an
      // expired batch a legitimate rejection, and §36 lets it come home.
      final positions = await _returns.rejectedPositionsOf(goodsReturn.grId);
      final lines = await _guards.loadVerifiedLines(
        repository: _returns,
        goodsReturn: goodsReturn,
        positions: positions,
      );

      // 16. The item and batch id sets, compared against what the lines claim. A third
      // plain-id comparison, because a batch row that was physically deleted would
      // otherwise surface as a posting failure naming the wrong thing (§26).
      _guards.requireLoadedSetMatches(
        goodsReturnId: goodsReturn.id,
        expected: await _returns.lineItemIds(goodsReturn.id),
        actual: lines.map((line) => line.itemId).toSet(),
        entity: 'items',
      );
      _guards.requireLoadedSetMatches(
        goodsReturnId: goodsReturn.id,
        expected: await _returns.lineBatchIds(goodsReturn.id),
        actual: lines.map((line) => line.batchId).whereType<String>().toSet(),
        entity: 'item_batches',
      );

      // 17–20. The destination: exactly one active `warehouse` location, resolved by
      // *type*. Zero is an explicit failure and more than one is an explicit failure —
      // which warehouse the goods arrived at is a business fact the system may not
      // guess, and picking the first would credit a balance nobody chose (§21).
      final warehouse = _guards.requireWarehouseLocation(
        await _returns.activeWarehouseLocations(),
      );

      final note = _guards.requireMeaningfulNote(warehouseNote);

      // 21–22. The instant, ordered against `shipped_at` on UTC instants and never as
      // text (§39). Equal instants are accepted; one microsecond earlier is not.
      final nowUtc = _clock().toUtc();
      _guards.requireReceiveInstant(goodsReturn: goodsReturn, nowUtc: nowUtc);

      // The plan. Assembling it as a value rather than as loose arguments is what makes
      // "the destination was resolved by type, once" a fact the posting call carries
      // rather than a step somebody could reorder (§22).
      final plan = GoodsReturnPostingPlan(
        goodsReturnId: goodsReturn.id,
        warehouseLocationId: warehouse.id,
        warehouseLocationName: warehouse.name,
        branchNote: goodsReturn.note,
        warehouseNote: note,
        lines: lines
            .map(
              (line) => GoodsReturnPostingLine(
                lineId: line.id,
                itemId: line.itemId,
                batchId: line.batchId,
                qty: line.qty,
                rejectReason: line.rejectReason,
              ),
            )
            .toList(growable: false),
      );

      // 23–24. The ledger. One `return` movement per line, `from_location_id` NULL and
      // `to_location_id` the Warehouse, and the Warehouse balance up by exactly the
      // quantity that was rejected. `postGoodsReturnLinesInTransaction` opens no
      // transaction of its own (§23).
      await _posting.postGoodsReturnLinesInTransaction(
        warehouseLocationId: plan.warehouseLocationId,
        actorUserId: actor.id,
        goodsReturnId: goodsReturn.id,
        lines: plan.lines
            .map(
              (line) => GoodsReturnPostingEntry(
                lineId: line.lineId,
                itemId: line.itemId,
                batchId: line.batchId,
                qty: line.qty,
                // Deterministic and never empty: the reject reason is mandatory all
                // the way down (G-G4), so the ledger note has something to say without
                // anything being invented (§22).
                note: plan.noteFor(line),
              ),
            )
            .toList(growable: false),
      );

      // 25–27. The document. The guarded UPDATE re-checks `shipped`, that this actor is
      // neither the creator nor the shipper, **and** that at least one line remains — so
      // a second device confirming between step 4 and here yields zero rows, which
      // rolls the movements above back. The Warehouse note is written by the same
      // statement, so a rolled-back receive leaves it exactly as it was.
      final received = await _returns.markReceived(
        goodsReturnId: goodsReturn.id,
        receivedAtUtc: nowUtc,
        receivedBy: actor.id,
        warehouseNote: note,
      );
      if (!received) {
        _guards.concurrentUpdate(
          goodsReturn.id,
          'Retur ${goodsReturn.docNumber} sudah diterima atau diubah di '
          'perangkat lain. Muat ulang dokumen lalu coba lagi.',
        );
      }

      // 28. Read back through the *unscoped* detail, because the caller is a use case
      // and has already authorised itself. The screens use the scoped reads.
      final detail = await _returns.getDetail(goodsReturn.id);
      if (detail == null) {
        // Unreachable on a healthy database — the row was just written inside this
        // transaction — so this is the honest way to fail rather than an assertion that
        // would be compiled out.
        _guards.concurrentUpdate(
          goodsReturn.id,
          'Retur ${goodsReturn.docNumber} tidak dapat dibaca ulang setelah '
          'diterima. Muat ulang dokumen lalu coba lagi.',
        );
      }
      return detail;
    });
  }
}
