import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../repositories/distribution_repository.dart';
import 'distribution_guards.dart';

/// Removes one line from a draft (§21.5).
///
/// A **soft** delete (G-A5): the row stays, `deleted_at` is stamped, and the partial
/// unique indexes stop counting it — which is exactly what lets the same position be
/// added back afterwards. Nothing in this milestone hard-deletes a business row.
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
/// 1. load the actor, refuse an inactive or non-branch-head account   (spec §3.1)
/// 2. load the line without any join, and check it is on this document
/// 3. load the document, guard `draft`                                (G-S1/G-S2)
/// 4. verify the actor's branch is the document's                     (G-T1/G-R2)
/// 5. guarded UPDATE, refused if the parent is no longer a draft
/// ```
///
/// ### Why the room and the item are not re-verified
///
/// Removal is the *remedy* for a line that no longer qualifies. A room that was
/// deactivated after the line was added blocks posting (§32), and the branch head's way
/// out is to delete the line — so demanding a valid room here would trap the document
/// in a state with no exit. The same reasoning covers a withdrawn item and an archived
/// batch: taking a position off a draft can never move stock, so nothing about the
/// physical world has to still hold for it to be allowed.
///
/// What *is* still enforced is the parent's status and the actor's branch. A posted
/// document is read-only permanently, and its lines with it — the ledger already
/// describes the movements they caused, and removing one afterwards would leave the
/// document disowning a movement that happened.
///
/// No movement is written and no balance changes.
class RemoveDistributionLineUseCase {
  RemoveDistributionLineUseCase({
    required this._distributions,
    required MasterDataRepository master,
  }) : _guards = DistributionGuards(master);

  final DistributionRepository _distributions;
  final DistributionGuards _guards;

  Future<void> call({
    required String actorUserId,
    required String distributionId,
    required String lineId,
  }) async {
    final actor = await _guards.requireBranchHeadActor(actorUserId);

    return _distributions.runInTransaction(() async {
      final line = _guards.requireLineOf(
        distributionId: distributionId,
        lineId: lineId,
        line: await _distributions.lineReferenceById(lineId),
      );

      final distribution = await _distributions.getById(distributionId);
      if (distribution == null) {
        throw DistributionNotFoundFailure(
          'Distribusi tidak ditemukan.',
          distributionId: distributionId,
        );
      }
      _guards.requireStatus(
        distribution: distribution,
        expected: DistributionStatus.draft,
      );
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: distribution.branchId,
      );

      final removed = await _distributions.removeDraftLine(
        distributionId: distribution.id,
        lineId: line.id,
      );
      if (!removed) _guards.concurrentUpdate(distribution);
    });
  }
}
