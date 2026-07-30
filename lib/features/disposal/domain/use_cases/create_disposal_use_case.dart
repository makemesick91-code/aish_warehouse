import 'package:uuid/uuid.dart';

import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/disposal_models.dart';
import '../repositories/disposal_repository.dart';
import '../services/disposal_reason_policy.dart';
import 'disposal_guards.dart';

/// Creates an empty `draft` Pemusnahan against one source location (§22.1).
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
/// 1. load the actor, refuse an inactive account or one with no scope   (§14)
/// 2. refuse a branch-scoped account with no branch                     (§14)
/// 3. verify the source location is one this actor may destroy from     (§15)
/// 4. verify the room behind a room source belongs to the same branch   (§15)
/// 5. insert the header as `draft`
/// ```
///
/// Step 3 uses the **operational** form of the location check: creating a document
/// is new work, so an archived shelf may not be chosen. An existing draft against a
/// shelf that was archived afterwards may still be posted — see
/// `PostDisposalUseCase` — because taking expired goods off a decommissioned shelf
/// still lowers risk.
///
/// ### The source is fixed here, for good
///
/// There is no `updateSourceLocation` anywhere: not on the repository, not on the
/// DAO, not in SQL. §22.1 asks for the source to be immutable once the document has
/// lines; making it immutable from creation is strictly stronger and costs nothing,
/// because a document with the wrong source has no work in it worth keeping. What
/// it buys is that the answer to *"who may post this"* — which is entirely a
/// function of the source — cannot change under a document that somebody has
/// already been cleared to edit.
///
/// ### An empty draft is a legitimate document
///
/// The form opens on a document that exists, which is what lets expired positions be
/// added one at a time with each addition validated and stored. Nothing about an
/// empty draft can post — the guarded UPDATE requires at least one live line *and* a
/// non-blank reason — so there is no half-state here that needs defending against.
///
/// ### The document number
///
/// `TMP-DSP-{uuid}` until the sync backend assigns the real number (G-Y4). Minting a
/// server-shaped sequence offline would collide across devices: every branch
/// destroys stock on its own, and two tablets in one clinic would both believe they
/// held `seq = 1`.
///
/// No movement is written and no balance changes. Creating a document is not a stock
/// event; posting it is.
class CreateDisposalUseCase {
  CreateDisposalUseCase({
    required this._disposals,
    required MasterDataRepository master,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _guards = DisposalGuards(master),
       _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final DisposalRepository _disposals;
  final DisposalGuards _guards;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  Future<Disposal> call({
    required String actorUserId,
    required String sourceLocationId,
    String? reason,
  }) async {
    final actor = await _guards.requireDisposalActor(actorUserId);

    final source = await _guards.requireSourceLocation(
      actor: actor,
      locationId: sourceLocationId,
    );
    await _guards.requireSourceRoom(actor: actor, location: source);

    return _disposals.createDraft(
      docNumber: 'TMP-DSP-${_newId()}',
      sourceLocationId: source.id,
      createdBy: actor.id,
      // Normalised rather than trusted: the same function every other writer uses,
      // so a reason stored here and one stored by the edit path are byte-identical
      // for the same input (§19).
      reason: DisposalReasonPolicy.normalize(reason),
      createdAtUtc: _clock().toUtc(),
    );
  }
}
