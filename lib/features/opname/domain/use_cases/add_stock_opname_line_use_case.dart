import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../inventory/domain/repositories/inventory_repository.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/opname_models.dart';
import '../repositories/opname_repository.dart';
import 'opname_guards.dart';

/// Adds a position that was found on the shelf but was not in the snapshot.
///
/// This is how an opname reports stock the system did not know about. Its
/// `system_qty` is the balance the room actually has for that position at the
/// time of the snapshot — normally zero, which is why it was missing — and the
/// resulting difference is what the review will post.
///
/// The batch must already exist in master data: inventing one here would let a
/// counting sheet create inventory identities that never passed through goods
/// receipt (G-E1).
class AddStockOpnameLineUseCase {
  AddStockOpnameLineUseCase({
    required this._opnames,
    required MasterDataRepository master,
    required this._inventory,
  }) : _master = master,
       _guards = OpnameGuards(master);

  final OpnameRepository _opnames;
  final MasterDataRepository _master;
  final InventoryRepository _inventory;
  final OpnameGuards _guards;

  Future<StockOpnameLine> call({
    required String actorUserId,
    required String opnameId,
    required String itemId,
    String? batchId,
    required Quantity countedQty,
    String? note,
  }) async {
    if (countedQty.isNegative) {
      throw const ValidationFailure('Hasil hitung fisik tidak boleh negatif.');
    }

    final actor = await _guards.requireActor(actorUserId, UserRole.perawat);

    // The status check, the duplicate check, the balance read and the insert
    // run as one unit. Otherwise a second add of the same position — or a
    // submit — landing between the check and the insert would escape the
    // friendly failure and surface as a raw UNIQUE constraint error.
    return _opnames.runInTransaction(
      () => _addLine(
        actor: actor,
        opnameId: opnameId,
        itemId: itemId,
        batchId: batchId,
        countedQty: countedQty,
        note: note,
      ),
    );
  }

  Future<StockOpnameLine> _addLine({
    required MasterUser actor,
    required String opnameId,
    required String itemId,
    String? batchId,
    required Quantity countedQty,
    String? note,
  }) async {
    final opname = await _opnames.getById(opnameId);
    if (opname == null) {
      throw StockOpnameNotFoundFailure(
        'Dokumen opname tidak ditemukan.',
        opnameId: opnameId,
      );
    }
    _guards.requireSameBranch(actor: actor, opname: opname);
    _guards.requireStatus(opname: opname, expected: StockOpnameStatus.draft);

    final room = await _guards.requireRoomInActorBranch(
      actor: actor,
      roomId: opname.roomId,
    );
    final location = await _guards.requireRoomLocation(room);

    // Only items that are still on the catalogue may be added (G-A4). Expired
    // *batches* remain addable on purpose: expired stock on a shelf is exactly
    // what an opname needs to surface (G-E7).
    final item = await _guards.requireActiveItem(itemId);
    await _guards.requireValidItemBatch(item: item, batchId: batchId);

    final existing = await _opnames.findLine(
      opnameId: opnameId,
      itemId: itemId,
      batchId: batchId,
    );
    if (existing != null) {
      throw DuplicateStockOpnameLineFailure(
        '${item.name}${batchId == null ? '' : ' (batch ini)'} sudah ada '
        'pada dokumen ini.',
        opnameId: opnameId,
        itemId: itemId,
        batchId: batchId,
      );
    }

    // The system quantity of a late addition is whatever the room holds now —
    // usually zero. Reading it rather than assuming zero keeps the invariant
    // "system_qty is the balance at snapshot time" true for every line.
    final systemQty = await _inventory.balanceQty(
      locationId: location.id,
      itemId: itemId,
      batchId: batchId,
    );

    final trimmed = note?.trim();
    final line = await _opnames.addDraftLine(
      opnameId: opnameId,
      itemId: itemId,
      batchId: batchId,
      systemQty: systemQty,
      countedQty: countedQty,
      note: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
    if (line == null) _guards.concurrentUpdate(opname);

    return line;
  }

  /// Batches a nurse may pick for an expiry-tracked item, nearest expiry first.
  /// Expired batches are included — they can still be sitting in the room.
  Future<List<MasterBatchOption>> batchOptions(String itemId) async {
    final batches = await _master.batchesOfItem(itemId);
    return batches
        .map(
          (batch) => MasterBatchOption(
            batchId: batch.id,
            batchNo: batch.batchNo,
            expiryDate: batch.expiryDate,
          ),
        )
        .toList(growable: false);
  }
}

/// One selectable batch in the add-line sheet.
class MasterBatchOption {
  const MasterBatchOption({
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
  });

  final String batchId;
  final String batchNo;

  /// Civil date, shown verbatim (T-9).
  final DateTime expiryDate;
}
