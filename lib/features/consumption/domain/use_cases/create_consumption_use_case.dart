import 'package:uuid/uuid.dart';

import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/consumption_models.dart';
import '../repositories/consumption_repository.dart';
import '../services/consumption_note_policy.dart';
import 'consumption_guards.dart';

/// Creates an empty `draft` Pemakaian against one room (§21.1).
///
/// The order is chosen so nothing is written until everything has been checked:
///
/// ```
/// 1. load the actor, refuse an inactive account or a non-Perawat            (§14)
/// 2. refuse an account with no branch                                       (§14)
/// 3. verify the branch is live and active                                   (§14)
/// 4. verify the room is active and belongs to the actor's branch            (§15)
/// 5. verify exactly one live `room` stock location resolves for it          (§15)
/// 6. insert the header as `draft`, owned by the actor
/// ```
///
/// Step 5 happens at *creation* rather than only at posting, and that is deliberate: a
/// room with no stock location — or with two — is a document that can never be posted,
/// and finding that out after the nurse has typed six lines is finding it out too late.
/// It is checked again inside the posting transaction, because an administrator can
/// break it in between.
///
/// ### The room is fixed here, for good
///
/// There is no `updateRoom` anywhere: not on the repository, not on the DAO, not in SQL.
/// §21.1 asks for the room to be immutable; making it immutable from creation is
/// strictly stronger and costs nothing, because a document with the wrong room has no
/// work in it worth keeping. What it buys is that the answer to *"whose stock does this
/// reduce"* cannot change under a document somebody has already been cleared to edit.
///
/// ### The owner is fixed here too
///
/// `created_by` is the acting nurse, and it is the ownership key every later read and
/// write predicates on (§14). There is no writer that changes it — reassigning a
/// consumption would mean rewriting whose account of a shift it is.
///
/// ### An empty draft is a legitimate document
///
/// The form opens on a document that exists, which is what lets positions be added one
/// at a time with each addition validated and stored. Nothing about an empty draft can
/// post — the guarded UPDATE requires at least one live line — so there is no half-state
/// here that needs defending against.
///
/// ### The document number
///
/// `TMP-CNS-{uuid}` until the sync backend assigns the real number (G-Y4). Minting a
/// server-shaped sequence offline would collide across devices: every room records its
/// own usage, and two tablets in one clinic would both believe they held `seq = 1`.
///
/// No movement is written and no balance changes. Creating a document is not a stock
/// event; posting it is.
class CreateConsumptionUseCase {
  CreateConsumptionUseCase({
    required this._consumptions,
    required MasterDataRepository master,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _guards = ConsumptionGuards(master),
       _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final ConsumptionRepository _consumptions;
  final ConsumptionGuards _guards;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  Future<Consumption> call({
    required String actorUserId,
    required String roomId,
    String? note,
  }) async {
    final actor = await _guards.requireNurseActor(actorUserId);
    // Non-null: `requireNurseActor` refuses a Perawat without a branch.
    final branchId = actor.branchId!;

    await _guards.requireActiveBranch(branchId);
    final room = await _guards.requireRoomForConsumption(
      branchId: branchId,
      roomId: roomId,
    );
    // Resolved and discarded: what matters at creation is that it resolves to exactly
    // one row. The posting resolves it again, inside its transaction, and uses *that*
    // id — a location resolved minutes earlier is a snapshot like any other.
    await _guards.requireRoomLocation(room: room, branchId: branchId);

    return _consumptions.createDraft(
      docNumber: 'TMP-CNS-${_newId()}',
      branchId: branchId,
      roomId: room.id,
      createdBy: actor.id,
      // Normalised rather than trusted: the same function every other writer uses, so a
      // note stored here and one stored by the edit path are byte-identical for the same
      // input (§19).
      note: ConsumptionNotePolicy.normalize(note),
      createdAtUtc: _clock().toUtc(),
    );
  }
}
