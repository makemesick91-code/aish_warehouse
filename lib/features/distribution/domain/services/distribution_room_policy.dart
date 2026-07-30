import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';

/// Why a room or a location may not take part in a distribution.
///
/// One enum rather than a boolean, because every one of these has a different
/// sentence for the branch head and a different consequence: a room in another
/// branch is a permission problem, a room with no stock location is a master-data
/// problem, and a deactivated room is an operational one.
enum DistributionRoomRejection {
  /// The room row is gone entirely.
  missing,

  /// `rooms.branch_id` is not the document's branch — G-T1's core refusal.
  branchMismatch,

  /// `rooms.is_active = 0`, or the row is archived. Refused for new lines *and* at
  /// posting: stock must not be moved into a room that is not operational.
  inactive,

  /// No `room` stock location resolves for it.
  locationMissing,

  /// More than one `room` stock location resolves for it.
  locationAmbiguous,

  /// The resolved location is not of type `room`, is not this room's, or belongs to
  /// another branch — a misfiled location row.
  locationMismatch,
}

/// The outcome of a room or location check.
class DistributionRoomVerdict {
  const DistributionRoomVerdict._(this.rejection);

  const DistributionRoomVerdict.accepted() : rejection = null;

  const DistributionRoomVerdict.rejected(DistributionRoomRejection rejection)
    : this._(rejection);

  /// `null` when the room may be used.
  final DistributionRoomRejection? rejection;

  bool get isAccepted => rejection == null;

  bool get isRejected => rejection != null;
}

/// G-T1 — where a distribution may send goods, and where it may take them from.
///
/// *"Distribusi hanya dari Gudang Cabang ke ruangan dalam cabang yang sama."*
///
/// Pure and synchronous: it is handed rows the caller already loaded and answers
/// questions about them. That is what lets the add path, the update path, the posting
/// path and the tests all ask the *same* question — and it is why the rule can be
/// re-asked inside the posting transaction against rows re-read there, rather than
/// trusted from whatever a form validated minutes earlier.
///
/// ### Why this is a policy and not a foreign key
///
/// The rule that every room on a document belongs to the document's branch is a
/// **cross-table equality** — `rooms.branch_id = distributions.branch_id` — and SQLite
/// cannot express it. A foreign key ties a column to a row, not two rows to each
/// other. So the database happily accepts a line naming another branch's room (the
/// schema test asserts exactly that, so nobody mistakes the gap for coverage), and the
/// rule lives here instead, enforced in four places:
///
/// 1. when a room is chosen for a draft line,
/// 2. in the branch predicate of every read query,
/// 3. again inside the posting transaction, against re-read rows,
/// 4. and in the architecture and security tests, which check that 1–3 exist.
///
/// ### Deactivated rooms: readable, not writable
///
/// A **posted** document whose room was retired afterwards stays fully readable —
/// that is what §32 is about, and the detail query filters neither `is_active` nor
/// `deleted_at`. But a **draft** line pointing at a deactivated room may not post:
/// the physical destination is not operational, and moving stock into it would
/// record an arrival nobody can act on. The branch head removes or replaces the
/// line. Nothing substitutes a room for them.
abstract final class DistributionRoomPolicy {
  /// Whether [room] may receive goods from a distribution of [branchId].
  ///
  /// [room] is `null` when the id resolved to nothing at all.
  static DistributionRoomVerdict verifyRoom({
    required MasterRoom? room,
    required String branchId,
  }) {
    if (room == null) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.missing,
      );
    }
    // Branch before activity: "this room is not yours" must not be distinguishable
    // from "this room is switched off", or the message would tell a branch head
    // something true about another branch's room.
    if (room.branchId != branchId) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.branchMismatch,
      );
    }
    if (!room.isActive || room.isArchived) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.inactive,
      );
    }
    return const DistributionRoomVerdict.accepted();
  }

  /// Whether [locations] resolve to exactly one usable `room` location for [room].
  ///
  /// Both failure modes are kept apart rather than resolved, for the reason §14 gives:
  ///
  /// * **none** — there is nowhere to put the goods, and inventing a location would
  ///   post the ledger against a row that does not exist;
  /// * **more than one** — which location the goods entered is a business fact.
  ///   Picking the first would silently attribute the movement to a location nobody
  ///   chose, and the balance it credited would be the wrong one.
  ///
  /// The type, the room and the branch are all re-checked on the resolved row: a
  /// location table can be misfiled, and a `branch_store` row carrying a `room_id`
  /// would otherwise pass a query that only asked for the room.
  static DistributionRoomVerdict verifyRoomLocation({
    required MasterRoom room,
    required String branchId,
    required List<MasterLocation> locations,
  }) {
    if (locations.isEmpty) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.locationMissing,
      );
    }
    if (locations.length > 1) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.locationAmbiguous,
      );
    }
    final location = locations.single;
    if (location.type != StockLocationType.room ||
        location.roomId != room.id ||
        location.branchId != branchId) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.locationMismatch,
      );
    }
    return const DistributionRoomVerdict.accepted();
  }

  /// Whether [locations] resolve to exactly one usable *Gudang Cabang* for [branchId].
  ///
  /// The source side of G-T1. Same two failure modes, same reasoning — and one extra
  /// check that matters: the resolved row must carry `room_id = null`. A branch's room
  /// locations also carry its `branch_id`, so a query that forgot that predicate would
  /// count a treatment room as a candidate store and a distribution would move stock
  /// from a room into a room.
  static DistributionRoomVerdict verifyBranchStore({
    required String branchId,
    required List<MasterLocation> locations,
  }) {
    if (locations.isEmpty) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.locationMissing,
      );
    }
    if (locations.length > 1) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.locationAmbiguous,
      );
    }
    final location = locations.single;
    if (location.type != StockLocationType.branchStore ||
        location.branchId != branchId ||
        location.roomId != null) {
      return const DistributionRoomVerdict.rejected(
        DistributionRoomRejection.locationMismatch,
      );
    }
    return const DistributionRoomVerdict.accepted();
  }

  /// Whether a movement from [sourceLocationId] to [destinationLocationId] is a
  /// legitimate distribution leg.
  ///
  /// The one check neither side can make alone: a store and a room that both verified
  /// individually could still be the *same* row if the location table were corrupt,
  /// and `stock_movements` has a CHECK against that — but failing there would surface
  /// as a driver error rather than as a business refusal. Asked here, it is a sentence
  /// the branch head can read.
  static bool isDistinctLeg({
    required String sourceLocationId,
    required String destinationLocationId,
  }) => sourceLocationId != destinationLocationId;
}
