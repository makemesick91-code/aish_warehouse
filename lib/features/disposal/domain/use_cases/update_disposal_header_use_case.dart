import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/disposal_models.dart';
import '../repositories/disposal_repository.dart';
import '../services/disposal_reason_policy.dart';
import 'disposal_guards.dart';

/// Rewrites the reason of a `draft` Pemusnahan (§22.2).
///
/// The **only** header field this milestone lets anybody change, and the list of
/// what it cannot reach is the interesting half:
///
/// * `source_location_id` — fixed at creation. Moving a document to another shelf
///   would move it into, or out of, somebody else's scope while its lines still
///   described the old shelf's stock. There is no SQL statement anywhere that
///   updates this column.
/// * `created_by` — an audit fact (G-A3), not a setting.
/// * `status`, `posted_at`, `posted_by` — only `PostDisposalUseCase` writes these,
///   through a guarded statement that names the status it expects to move from.
///
/// The reason may legitimately be cleared back to `null` while the document is a
/// draft — somebody deleting a chip they picked by mistake — and the document simply
/// cannot post until it has one again. What may **not** happen is storing whitespace:
/// [DisposalReasonPolicy.normalize] turns `"  "` into `null` rather than letting a
/// blank sit in the column pretending to be an explanation.
///
/// The status guard travels into the SQL, so a reason cannot be rewritten on a
/// posted document however stale the screen that tried. That matters more here than
/// on any other header field in the application: this text is the audit record of
/// why stock disappeared (G-E7), and a posted document whose explanation could be
/// edited afterwards would be an audit trail that can be rewritten.
class UpdateDisposalHeaderUseCase {
  UpdateDisposalHeaderUseCase({
    required this._disposals,
    required MasterDataRepository master,
  }) : _guards = DisposalGuards(master);

  final DisposalRepository _disposals;
  final DisposalGuards _guards;

  Future<Disposal> call({
    required String actorUserId,
    required String disposalId,
    required String? reason,
  }) async {
    final actor = await _guards.requireDisposalActor(actorUserId);

    return _disposals.runInTransaction(() async {
      final disposal = await _disposals.getById(disposalId);
      if (disposal == null) {
        throw DisposalNotFoundFailure(
          'Pemusnahan tidak ditemukan.',
          disposalId: disposalId,
        );
      }
      _guards.requireStatus(disposal: disposal, expected: DisposalStatus.draft);

      // The scope check reads the *stored* source, never one the caller passed:
      // there is no parameter here that could name a different shelf.
      final source = await _guards.requireSourceLocation(
        actor: actor,
        locationId: disposal.sourceLocationId,
        // Editing a draft is not the same as creating one. A shelf archived after
        // the document was raised does not invalidate the work already on it, and
        // refusing here would leave a draft that can neither be finished nor
        // corrected (§15).
        requireOperational: false,
        disposalId: disposal.id,
      );
      await _guards.requireSourceRoom(actor: actor, location: source);
      _guards.requireScopeMatches(actor: actor, source: source);

      final updated = await _disposals.updateDraftReason(
        disposalId: disposal.id,
        reason: DisposalReasonPolicy.normalize(reason),
      );
      if (!updated) _guards.concurrentUpdate(disposal);

      final result = await _disposals.getById(disposal.id);
      if (result == null) {
        throw DisposalNotFoundFailure(
          'Pemusnahan tidak ditemukan setelah pembaruan.',
          disposalId: disposal.id,
        );
      }
      return result;
    });
  }
}
