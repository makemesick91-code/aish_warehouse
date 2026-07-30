import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../repositories/disposal_repository.dart';
import 'disposal_guards.dart';

/// Removes one line from a `draft` Pemusnahan (§22.5).
///
/// A **soft** delete (G-A5): the row keeps its id and its history and stops being
/// live. That is what lets the same `(item, batch)` position be added back
/// afterwards — the partial unique index is qualified `WHERE deleted_at IS NULL`, so
/// a removed line frees the position it occupied rather than blocking it forever.
///
/// The status guard travels into the SQL. A line cannot be removed from a document
/// that has already posted, which would leave the ledger describing a destruction
/// the document no longer admits to — and, unlike every other document in this
/// application, there would be no counter-entry anywhere to reconcile against.
///
/// Nothing about the item or the batch is re-validated here, and that is deliberate:
/// removing a line is the correct response to a reference that has gone bad, so a
/// check that refused on a broken reference would trap the user with a document they
/// can neither post nor repair.
class RemoveDisposalLineUseCase {
  RemoveDisposalLineUseCase({
    required this._disposals,
    required MasterDataRepository master,
  }) : _guards = DisposalGuards(master);

  final DisposalRepository _disposals;
  final DisposalGuards _guards;

  Future<void> call({
    required String actorUserId,
    required String disposalId,
    required String lineId,
  }) async {
    final actor = await _guards.requireDisposalActor(actorUserId);

    await _disposals.runInTransaction(() async {
      final disposal = await _disposals.getById(disposalId);
      if (disposal == null) {
        throw DisposalNotFoundFailure(
          'Pemusnahan tidak ditemukan.',
          disposalId: disposalId,
        );
      }
      _guards.requireStatus(disposal: disposal, expected: DisposalStatus.draft);

      final source = await _guards.requireSourceLocation(
        actor: actor,
        locationId: disposal.sourceLocationId,
        requireOperational: false,
        disposalId: disposal.id,
      );
      await _guards.requireSourceRoom(actor: actor, location: source);
      _guards.requireScopeMatches(actor: actor, source: source);

      final line = _guards.requireLineOf(
        disposalId: disposal.id,
        lineId: lineId,
        line: await _disposals.lineReferenceById(lineId),
      );

      final removed = await _disposals.removeDraftLine(
        disposalId: disposal.id,
        lineId: line.id,
      );
      if (!removed) _guards.concurrentUpdate(disposal);
    });
  }
}
