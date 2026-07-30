import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/consumption_models.dart';
import '../repositories/consumption_repository.dart';
import '../services/consumption_note_policy.dart';
import 'consumption_guards.dart';

/// Rewrites the note of a `draft` Pemakaian (§21.2).
///
/// The **only** header field this milestone lets anybody change, and the list of what it
/// cannot reach is the interesting half:
///
/// * `room_id` and `branch_id` — fixed at creation. Moving a document to another room
///   would move it into, or out of, somebody else's scope while its lines still described
///   the old room's stock. There is no SQL statement anywhere that updates either column.
/// * `created_by` — an audit fact (G-A3) and the ownership key (§14), not a setting.
///   Reassigning a consumption would mean rewriting whose account of a shift it is.
/// * `status`, `posted_at`, `posted_by` — only `PostConsumptionUseCase` writes these,
///   through a guarded statement that names the status it expects to move from *and* the
///   creator it expects to belong to.
///
/// The note may legitimately be cleared back to `null` — somebody deleting a remark they
/// typed by mistake — and the document posts perfectly well without one (§8). What may
/// **not** happen is storing whitespace: [ConsumptionNotePolicy.normalize] turns `"  "`
/// into `null` rather than letting a blank sit in the column pretending to be a remark.
///
/// Both guards travel into the SQL: a note cannot be rewritten on a posted document
/// however stale the screen that tried, and cannot be rewritten on another nurse's draft
/// at all.
class UpdateConsumptionHeaderUseCase {
  UpdateConsumptionHeaderUseCase({
    required this._consumptions,
    required MasterDataRepository master,
  }) : _guards = ConsumptionGuards(master);

  final ConsumptionRepository _consumptions;
  final ConsumptionGuards _guards;

  Future<Consumption> call({
    required String actorUserId,
    required String consumptionId,
    required String? note,
  }) async {
    final actor = await _guards.requireNurseActor(actorUserId);

    return _consumptions.runInTransaction(() async {
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

      // Deliberately *not* re-validating the room here. Editing a remark is not a stock
      // event, and refusing it because an administrator deactivated the room in the
      // meantime would leave a draft that can neither be finished nor tidied up. The
      // posting is where an inactive room blocks the document (§15).
      final updated = await _consumptions.updateOwnDraftNote(
        consumptionId: consumption.id,
        actorUserId: actor.id,
        note: ConsumptionNotePolicy.normalize(note),
      );
      if (!updated) _guards.concurrentUpdate(consumption);

      final result = await _consumptions.getById(consumption.id);
      if (result == null) {
        throw ConsumptionNotFoundFailure(
          'Pemakaian tidak ditemukan setelah pembaruan.',
          consumptionId: consumption.id,
        );
      }
      return result;
    });
  }
}
