import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/goods_return_models.dart';
import '../repositories/goods_return_repository.dart';
import 'goods_return_guards.dart';

/// Changes the branch's note on a **draft** Retur (§19).
///
/// The only mutation this document has between creation and shipping, and it reaches
/// exactly one column. Everything else is out of reach by construction rather than by
/// check: `gr_id`, `branch_id`, `created_by`, `status`, every line, every quantity,
/// every reject reason, both shipping fields, both receiving fields and
/// `warehouse_note` have **no writer at all** on the repository (§25), so there is no
/// method here that could be given one by mistake.
///
/// `warehouse_note` deserves its own sentence: it is nullable and it is on the same
/// row, which makes it the one column a careless widening of this use case would
/// reach. It is the Warehouse's word about goods they received, written only inside
/// the receive transaction. A branch being able to edit it would let the sender write
/// the recipient's testimony.
///
/// `null` is a legitimate value — it clears the note. Whitespace is not: the guard
/// refuses it rather than silently storing `null`, so a user who typed spaces is told
/// instead of having their input quietly discarded.
class UpdateGoodsReturnNoteUseCase {
  UpdateGoodsReturnNoteUseCase({
    required this._returns,
    required MasterDataRepository master,
  }) : _guards = GoodsReturnGuards(master);

  final GoodsReturnRepository _returns;
  final GoodsReturnGuards _guards;

  Future<GoodsReturn> call({
    required String actorUserId,
    required String goodsReturnId,
    required String? note,
  }) {
    return _returns.runInTransaction(() async {
      final actor = await _guards.requireBranchActor(actorUserId);

      final goodsReturn = _guards.requireDocument(
        goodsReturn: await _returns.getById(goodsReturnId),
        goodsReturnId: goodsReturnId,
      );
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: goodsReturn.branchId,
      );
      // A shipped document's note is part of what the Warehouse is reading while the
      // box is in transit; a received one is history.
      _guards.requireStatus(
        goodsReturn: goodsReturn,
        expected: GoodsReturnStatus.draft,
      );

      final trimmed = _guards.requireMeaningfulNote(note);

      // Both predicates travel into the statement — `status = 'draft'` and
      // `branch_id = ?` — so a stale screen and a foreign branch are refused at the
      // moment of the write rather than at the moment of the read (§19).
      final updated = await _returns.updateDraftNote(
        goodsReturnId: goodsReturn.id,
        branchId: actor.branchId!,
        note: trimmed,
      );
      if (!updated) {
        _guards.concurrentUpdate(
          goodsReturn.id,
          'Retur ${goodsReturn.docNumber} sudah berubah di perangkat lain. '
          'Muat ulang dokumen lalu coba lagi.',
        );
      }

      return _guards.requireDocument(
        goodsReturn: await _returns.getById(goodsReturn.id),
        goodsReturnId: goodsReturn.id,
      );
    });
  }
}
