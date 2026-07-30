import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../repositories/consumption_repository.dart';
import 'consumption_guards.dart';

/// Removes one line from a `draft` Pemakaian (§21.5).
///
/// A **soft** delete (G-A5): the row keeps its id and its history and stops being live.
/// That is what lets the same `(item, batch)` position be added back afterwards — both
/// partial unique indexes are qualified `WHERE deleted_at IS NULL`, so a removed line
/// frees the position it occupied rather than blocking it forever.
///
/// Both guards travel into the SQL. A line cannot be removed from a document that has
/// already posted, which would leave the ledger describing usage the document no longer
/// admits to — and, because a `consumption` movement has no counter-entry, there would be
/// nothing anywhere to reconcile against. And it cannot be removed from another nurse's
/// draft.
///
/// Nothing about the item, the batch or the room is re-validated here, and that is
/// deliberate: removing a line is the correct response to a reference that has gone bad —
/// a batch that expired overnight, a product that was withdrawn — so a check that refused
/// on a broken reference would trap the nurse with a document they can neither post nor
/// repair. The room check is skipped for the same reason: a deactivated room blocks
/// *posting*, and tidying up the draft it left behind must stay possible.
class RemoveConsumptionLineUseCase {
  RemoveConsumptionLineUseCase({
    required this._consumptions,
    required MasterDataRepository master,
  }) : _guards = ConsumptionGuards(master);

  final ConsumptionRepository _consumptions;
  final ConsumptionGuards _guards;

  Future<void> call({
    required String actorUserId,
    required String consumptionId,
    required String lineId,
  }) async {
    final actor = await _guards.requireNurseActor(actorUserId);

    await _consumptions.runInTransaction(() async {
      final consumption = await _consumptions.getById(consumptionId);
      if (consumption == null) {
        throw ConsumptionNotFoundFailure(
          'Pemakaian tidak ditemukan.',
          consumptionId: consumptionId,
        );
      }
      _guards.requireOwnership(actor: actor, consumption: consumption);
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: consumption.branchId,
      );
      _guards.requireStatus(
        consumption: consumption,
        expected: ConsumptionStatus.draft,
      );

      final line = _guards.requireLineOf(
        consumptionId: consumption.id,
        lineId: lineId,
        line: await _consumptions.lineReferenceById(lineId),
      );

      final removed = await _consumptions.removeDraftLine(
        consumptionId: consumption.id,
        actorUserId: actor.id,
        lineId: line.id,
      );
      if (!removed) _guards.concurrentUpdate(consumption);
    });
  }
}
