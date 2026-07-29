import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../repositories/opname_repository.dart';
import 'opname_guards.dart';

/// Removes a line that was added to a draft by mistake.
///
/// This exists so that *no* opname write reaches the repository without the
/// same guard triple as every other one: active perawat, same branch, document
/// still a draft. The DAO's SQL guard only knows about the document's status —
/// it cannot tell whose branch the caller belongs to — so leaving deletion to
/// the repository would have made it the one write anybody could perform on
/// somebody else's count.
///
/// The line is soft-deleted, never removed: the audit trail keeps it (G-A5).
class RemoveStockOpnameLineUseCase {
  RemoveStockOpnameLineUseCase({
    required this._opnames,
    required MasterDataRepository master,
  }) : _guards = OpnameGuards(master);

  final OpnameRepository _opnames;
  final OpnameGuards _guards;

  Future<void> call({
    required String actorUserId,
    required String lineId,
  }) async {
    final actor = await _guards.requireActor(actorUserId, UserRole.perawat);

    final line = await _opnames.lineById(lineId);
    if (line == null) {
      throw StockOpnameLineNotFoundFailure(
        'Baris opname tidak ditemukan.',
        lineId: lineId,
      );
    }

    final opname = await _opnames.getById(line.opnameId);
    if (opname == null) {
      throw StockOpnameNotFoundFailure(
        'Dokumen opname tidak ditemukan.',
        opnameId: line.opnameId,
      );
    }

    _guards.requireSameBranch(actor: actor, opname: opname);
    _guards.requireStatus(opname: opname, expected: StockOpnameStatus.draft);

    final removed = await _opnames.removeDraftLine(lineId);
    // Reached when the document was submitted between the check above and the
    // write. Reporting success here would tell the nurse a line is gone while
    // it is still on the document.
    if (!removed) _guards.concurrentUpdate(opname);
  }
}
