import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/goods_return_models.dart';
import '../repositories/goods_return_repository.dart';
import 'goods_return_guards.dart';

/// Raises a Retur from one posted Good Receipt, snapshotting **every** rejected line
/// (§17).
///
/// One transaction, and the whole document inside it: a header without its lines is a
/// document that claims to return nothing, and a header the unique index accepted
/// followed by lines that failed would leave exactly that behind.
///
/// ### What this use case does not take
///
/// There is no `lines` parameter, no quantity, no item, no batch and no way to select
/// a subset. A branch head raising a return chooses *which receipt*, and nothing else.
/// The document's content is a function of the receipt's rejections — read here,
/// verified here, written here — which is what makes the snapshot evidence rather than
/// a claim (§18).
///
/// ### The concurrency story
///
/// Two devices pressing *Buat Retur* on the same receipt is the expected race, not an
/// exotic one: the *Perlu Dibuat* queue is a shared work list. The eligibility check at
/// step 7 will let both through if they interleave, and what makes exactly one win is
/// the **unqualified unique index on `goods_returns.gr_id`** (§10). The loser's insert
/// throws, this catches it, re-reads the winner and reports
/// [GoodsReturnAlreadyExistsFailure] carrying the winning document's id — so the UI can
/// offer *"Lihat Retur"* instead of a dead end. Nothing partial survives, because the
/// insert and the lines share one transaction.
class CreateGoodsReturnUseCase {
  CreateGoodsReturnUseCase({
    required this._returns,
    required MasterDataRepository master,
    DateTime Function()? clock,
    String Function()? idGenerator,
    // `master` is consumed by the guards rather than stored, and that is the point: no
    // use case in this feature holds a master repository it could read around the
    // guards with.
  }) : _guards = GoodsReturnGuards(master),
       _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final GoodsReturnRepository _returns;
  final GoodsReturnGuards _guards;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  Future<GoodsReturn> call({
    required String actorUserId,
    required String goodReceiptId,
    String? note,
  }) {
    return _returns.runInTransaction(() async {
      // 1–3. The actor, read from the database rather than trusted from the session
      // (O-8). Role and branch are one check: "their own branch's receipt" is
      // meaningless without a branch.
      final actor = await _guards.requireBranchActor(actorUserId);
      final actorBranchId = actor.branchId!;
      await _guards.requireActiveBranch(actorBranchId);

      final trimmedNote = _guards.requireMeaningfulNote(note);

      // 4–7. Eligibility, re-asked inside the transaction against the state the write
      // will see. The branch check runs first, inside the policy, so a refusal never
      // confirms anything about another branch's receipt.
      final receiptStatus = await _returns.goodReceiptStatusOf(goodReceiptId);
      final receiptBranchId = await _returns.goodReceiptBranchOf(goodReceiptId);
      final existing = await _returns.findByGoodReceipt(goodReceiptId);

      // 9. The plain, join-free id list — the authority on which positions exist. Read
      // *before* the joined details so the count the eligibility check uses cannot have
      // been reduced by a join (§26).
      final rejectedIds = await _returns.rejectedGoodReceiptLineIds(
        goodReceiptId,
      );

      _guards.requireEligibleGoodReceipt(
        grId: goodReceiptId,
        receiptStatus: receiptStatus,
        receiptBranchId: receiptBranchId,
        actorBranchId: actorBranchId,
        rejectedLineCount: rejectedIds.length,
        existingReturn: existing,
      );

      // 10–11. The joined details, then the set check. If an `INNER JOIN items` dropped
      // a position because its item row is physically gone, the two lists disagree and
      // this refuses — rather than writing a document silently one line short (§26).
      final positions = await _returns.rejectedPositionsOf(goodReceiptId);
      _guards.requireLoadedSetMatches(
        goodsReturnId: '',
        expected: rejectedIds,
        actual: positions.map((position) => position.grLineId),
        entity: 'good_receipt_lines',
      );

      // 12–21. Every position, checked before any of them is written: rejected status,
      // nothing accepted, a positive shipped quantity, a non-blank reason, and G-E2's
      // batch consistency in both directions.
      //
      // Expiry is deliberately **not** checked. G-E5 makes an expired or near-expiry
      // batch a legitimate reason to reject a delivery, so refusing to return one would
      // leave the branch holding goods it may not use, may not distribute and has no
      // document for (§36).
      for (final position in positions) {
        _guards.requireReturnablePosition(position);
      }

      // 22–26. The document. `TMP-RET-{uuid}` until the sync backend assigns the real
      // number (G-Y4); minting a server-shaped one offline would collide across
      // devices, and every branch returns on its own.
      final id = _newId();
      final createdAt = _clock().toUtc();
      try {
        return await _returns.createFromGoodReceipt(
          docNumber: 'TMP-RET-$id',
          grId: goodReceiptId,
          branchId: actorBranchId,
          createdBy: actor.id,
          note: trimmedNote,
          createdAtUtc: createdAt,
          // 23–25. The snapshot: the quantity is the source line's `shipped_qty`,
          // because a rejection accepted nothing and everything that was sent is
          // coming back; the reason is the one G-G4 made mandatory (§18).
          lines: positions
              .map(
                (position) => GoodsReturnLineDraft(
                  grLineId: position.grLineId,
                  itemId: position.itemId,
                  batchId: position.batchId,
                  qty: position.returnQty,
                  rejectReason: position.rejectReason.trim(),
                ),
              )
              .toList(growable: false),
        );
      } on AppFailure {
        rethrow;
      } catch (_) {
        // The unique index on `gr_id` fired: another device won the race between the
        // eligibility check above and this insert. Re-read the winner so the failure
        // can name it — a branch head who pressed the button wants that document, not
        // an apology.
        final winner = await _returns.findByGoodReceipt(goodReceiptId);
        if (winner != null) {
          throw GoodsReturnAlreadyExistsFailure(
            'Penerimaan Barang ini sudah memiliki dokumen Retur '
            '${winner.docNumber}.',
            grId: goodReceiptId,
            existingGoodsReturnId: winner.id,
          );
        }
        rethrow;
      }
      // 27–29. Nothing else happened. No movement was written, no balance moved, and
      // the Good Receipt, Delivery Order and Purchase Request were not touched — a
      // return is raised *from* a posted receipt, and a posted receipt is final (G-S2).
    });
  }
}
