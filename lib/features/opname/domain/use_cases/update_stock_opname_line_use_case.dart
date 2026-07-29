import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/opname_models.dart';
import '../repositories/opname_repository.dart';
import 'opname_guards.dart';

/// Records what a nurse actually counted on one line (G-O3).
///
/// Only drafts are editable. The write itself is guarded in SQL by the parent's
/// status, so even a screen that has been open since before the document was
/// submitted cannot slip an edit through — it gets a state failure instead.
///
/// `system_qty` is not a parameter and there is no repository method that could
/// change it, so the snapshot survives every edit (G-O2).
class UpdateStockOpnameLineUseCase {
  UpdateStockOpnameLineUseCase({
    required this._opnames,
    required MasterDataRepository master,
  }) : _guards = OpnameGuards(master);

  final OpnameRepository _opnames;
  final OpnameGuards _guards;

  Future<StockOpnameLine> call({
    required String actorUserId,
    required String lineId,
    required Quantity countedQty,
    String? note,
  }) async {
    // A physical count is never negative. `Quantity.parse` already refuses a
    // negative or over-precise input at the UI boundary; this is the guard for
    // every other caller (Q-1/G-O3).
    if (countedQty.isNegative) {
      throw const ValidationFailure('Hasil hitung fisik tidak boleh negatif.');
    }

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

    // The item/batch pairing is re-validated rather than trusted: a line
    // created correctly could still be pointed at the wrong batch by a future
    // caller, and this is the layer that has to notice (G-E2).
    final item = await _guards.requireItem(line.itemId);
    await _guards.requireValidItemBatch(item: item, batchId: line.batchId);

    // An empty note is stored as NULL rather than an empty string, so
    // "no reason given" has exactly one representation.
    final trimmed = note?.trim();
    final storedNote = (trimmed == null || trimmed.isEmpty) ? null : trimmed;

    final updated = await _opnames.updateDraftLine(
      lineId: lineId,
      countedQty: countedQty,
      note: storedNote,
    );
    if (!updated) _guards.concurrentUpdate(opname);

    final result = await _opnames.lineById(lineId);
    if (result == null) {
      throw StockOpnameLineNotFoundFailure(
        'Baris opname tidak ditemukan setelah disimpan.',
        lineId: lineId,
      );
    }
    return result;
  }
}
