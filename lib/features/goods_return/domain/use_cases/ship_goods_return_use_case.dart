import '../../../../core/enums/app_enums.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/goods_return_models.dart';
import '../repositories/goods_return_repository.dart';
import 'goods_return_guards.dart';

/// `draft → shipped` — the branch hands the goods to the carrier (§20).
///
/// ### This use case writes nothing to the ledger, and that is the rule
///
/// There is no `StockPostingService` in this class, no `posting` parameter, and no way
/// to add one without the architecture test failing. Two facts make it correct:
///
/// * **The goods were never in the branch's balance.** G-G5 credits the branch store
///   only for `checked` lines, so a rejected position never entered it — there is no
///   balance to take them out of, and writing one would create a negative.
/// * **The Warehouse must not be credited yet.** The box is on a road. G-A2 forbids a
///   negative balance and G-A1 makes the ledger append-only, so stock the Warehouse
///   could distribute before it arrives is stock that could go negative the moment
///   somebody does. The credit happens at `received`, once (§21).
///
/// So the physical event is recorded and nothing moves. The confirmation dialog says
/// exactly that (§30), because a branch head who believes the Warehouse balance has
/// gone up is a branch head who will be surprised later.
///
/// ### Why the snapshot is re-verified here
///
/// A draft can sit open. Between creation and shipping, the Good Receipt is still
/// there, its lines are still there, and something could have happened to any of them.
/// Shipping a document whose lines no longer match the receipt would put a box on a
/// road with a manifest that has stopped being true — and the Warehouse would then
/// receive it against that manifest. The check reads plain, join-free ids (§26).
class ShipGoodsReturnUseCase {
  ShipGoodsReturnUseCase({
    required this._returns,
    required MasterDataRepository master,
    this._outbox = const NoopSyncOutboxWriter(),
    DateTime Function()? clock,
  }) : _guards = GoodsReturnGuards(master),
       _clock = clock ?? _defaultClock;

  final GoodsReturnRepository _returns;
  final GoodsReturnGuards _guards;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<GoodsReturn> call({
    required String actorUserId,
    required String goodsReturnId,
  }) {
    return _returns.runInTransaction(() async {
      // 1–3. The actor, re-read from the database (O-8).
      final actor = await _guards.requireBranchActor(actorUserId);

      // 4–6. The document, its branch and its status.
      final goodsReturn = _guards.requireDocument(
        goodsReturn: await _returns.getById(goodsReturnId),
        goodsReturnId: goodsReturnId,
      );
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: goodsReturn.branchId,
      );
      _guards.requireStatus(
        goodsReturn: goodsReturn,
        expected: GoodsReturnStatus.draft,
        attempted: GoodsReturnStatus.shipped,
      );
      _guards.requireTransition(
        actor: actor,
        goodsReturn: goodsReturn,
        to: GoodsReturnStatus.shipped,
      );

      // The branch must still be live (§37). Shipping is *new* physical work — a branch
      // the clinic group has closed is not handing anything to a carrier — and a draft
      // left open across a closure should not be completable afterwards.
      //
      // Note the asymmetry with `ReceiveGoodsReturnUseCase`, which deliberately does
      // **not** ask this: by then the box is already at the Warehouse door, and refusing
      // it because the sender has since closed would leave goods with no document at
      // all. Reading the document is unaffected either way.
      await _guards.requireActiveBranch(goodsReturn.branchId);

      // 7. The receipt must still exist and still be posted. A receipt that vanished is
      // a historical-reference failure rather than a silently smaller document (§37).
      _guards.requireHistoricalGoodReceipt(
        goodsReturn: goodsReturn,
        receiptStatus: await _returns.goodReceiptStatusOf(goodsReturn.grId),
      );

      // 8–13. The snapshot, verified against the receipt's rejections: the set first,
      // then every line's item, batch, quantity and reason. `loadVerifiedLines` reads
      // the plain id list *before* the joined one and compares them, so an inner-join
      // data loss is reported rather than silently shrinking the manifest (§26).
      await _guards.loadVerifiedLines(
        repository: _returns,
        goodsReturn: goodsReturn,
        positions: await _returns.rejectedPositionsOf(goodsReturn.grId),
      );

      // 14–15. The instant, ordered against the document's own creation on UTC
      // instants and never as text (§39). Equal instants are accepted: two events
      // really can land on the same microsecond on a fast device.
      final nowUtc = _clock().toUtc();
      _guards.requireShipInstant(goodsReturn: goodsReturn, nowUtc: nowUtc);

      // 16–19. The guarded write. `status = 'draft'`, `branch_id = ?` and an `EXISTS`
      // on the lines all travel into the statement, so a second device shipping between
      // step 4 and here yields zero rows rather than a second transition.
      final shipped = await _returns.markShipped(
        goodsReturnId: goodsReturn.id,
        branchId: actor.branchId!,
        shippedAtUtc: nowUtc,
        shippedBy: actor.id,
      );
      if (!shipped) {
        _guards.concurrentUpdate(
          goodsReturn.id,
          'Retur ${goodsReturn.docNumber} sudah dikirim atau diubah di '
          'perangkat lain. Muat ulang dokumen lalu coba lagi.',
        );
      }

      await _outbox.enqueueCurrentAggregate(
        operation: SyncOperationType.shipGoodsReturn,
        aggregateType: SyncAggregateType.goodsReturn,
        aggregateId: goodsReturn.id,
        actorUserId: actor.id,
        occurredAtUtc: nowUtc,
      );

      return _guards.requireDocument(
        goodsReturn: await _returns.getById(goodsReturn.id),
        goodsReturnId: goodsReturn.id,
      );
    });
  }
}
