import 'package:uuid/uuid.dart';

import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/distribution_models.dart';
import '../repositories/distribution_repository.dart';
import 'distribution_guards.dart';

/// Creates an empty `draft` Distribusi for the acting branch head (§21.1).
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
/// 1. load the actor, refuse an inactive or non-branch-head account   (spec §3.1)
/// 2. refuse an account with no branch                                (G-T1)
/// 3. refuse an inactive branch
/// 4. resolve exactly one active Gudang Cabang                        (G-T1/§14)
/// 5. insert the header as `draft`
/// ```
///
/// Step 4 happens *before* the insert on purpose. A branch with no store — or with
/// two — cannot distribute at all, and finding that out when the branch head has
/// already filled in three rooms would waste their work. Nothing is guessed: the
/// location is looked up by type and branch, never hard-coded and never taken from a
/// screen.
///
/// ### An empty draft is a legitimate document
///
/// The form opens on a document that exists, which is what lets rooms and items be
/// added one at a time with each addition validated and stored. Nothing about an
/// empty draft can post — the guarded UPDATE requires at least one live line — so
/// there is no half-state here that needs defending against.
///
/// ### The document number
///
/// `TMP-DIST-{uuid}` until the sync backend assigns the real
/// `DIST-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped sequence offline
/// would collide across devices: every branch distributes on its own, and two
/// tablets in one clinic would both believe they held `seq = 1`.
///
/// No movement is written and no balance changes. Creating a document is not a stock
/// event; posting it is (spec §2.5).
class CreateDistributionUseCase {
  CreateDistributionUseCase({
    required this._distributions,
    required MasterDataRepository master,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _guards = DistributionGuards(master),
       _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final DistributionRepository _distributions;
  final DistributionGuards _guards;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  Future<Distribution> call({required String actorUserId, String? note}) async {
    final actor = await _guards.requireBranchHeadActor(actorUserId);
    final branchId = actor.branchId!;

    await _guards.requireActiveBranch(branchId);
    // Refused now rather than at posting: a branch that cannot supply goods cannot
    // start a distribution either, and saying so up front is the honest answer.
    await _guards.requireBranchStore(branchId);

    final trimmedNote = note?.trim();
    return _distributions.createDraft(
      docNumber: 'TMP-DIST-${_newId()}',
      branchId: branchId,
      distributedBy: actor.id,
      note: (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
      createdAtUtc: _clock().toUtc(),
    );
  }
}
