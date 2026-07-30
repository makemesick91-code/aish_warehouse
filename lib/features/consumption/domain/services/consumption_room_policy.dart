import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';

/// Why a room or a location may not be a consumption's source.
///
/// One enum rather than a boolean, because every one of these has a different sentence
/// for the nurse and a different consequence: a room in another branch is a permission
/// problem, a room with no stock location is a master-data problem, and a deactivated
/// room is an operational one.
enum ConsumptionRoomRejection {
  /// The room row is gone entirely.
  missing,

  /// `rooms.branch_id` is not the document's branch — the core refusal (§15).
  branchMismatch,

  /// `rooms.is_active = 0`, or the row is archived. Refused for a new document *and* at
  /// posting: goods must not be recorded as used out of a room the clinic is no longer
  /// operating.
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
class ConsumptionRoomVerdict {
  const ConsumptionRoomVerdict._(this.rejection);

  const ConsumptionRoomVerdict.accepted() : rejection = null;

  const ConsumptionRoomVerdict.rejected(ConsumptionRoomRejection rejection)
    : this._(rejection);

  /// `null` when the room may be used.
  final ConsumptionRoomRejection? rejection;

  bool get isAccepted => rejection == null;

  bool get isRejected => rejection != null;
}

/// Where a consumption may take goods from (§15).
///
/// ```
/// Perawat  → StockLocationType.room, rooms.branch_id = actor.branchId
/// everyone else → nothing
/// ```
///
/// Pure and synchronous: it is handed rows the caller already loaded and answers
/// questions about them. That is what lets the create path, the add path, the update
/// path, the posting path and the tests all ask the *same* question — and it is why the
/// rule can be re-asked inside the posting transaction against rows re-read there,
/// rather than trusted from whatever a form validated minutes earlier.
///
/// ### Why the source is a room and only a room
///
/// §2.5 puts room stock at the end of the chain: Warehouse Pusat ships to a Gudang
/// Cabang, which distributes to a room, and the room is where goods are used. A
/// consumption out of a branch store would be recording usage in a place nobody treats
/// patients; a consumption out of Warehouse Pusat would be recording it in a building
/// with no treatment rooms at all. Both of those are *losses* of some other kind — a
/// write-off, a transfer, a disposal — each with its own document and its own audit
/// requirements, and letting one in here would give it none of them. So this milestone
/// implements exactly one source type, and the location is resolved by type from the
/// room rather than named by the caller: there is no parameter anywhere that could
/// carry an arbitrary location id.
///
/// ### Why this is a policy and not a foreign key
///
/// The rule that a document's room belongs to the document's branch is a **cross-table
/// equality** — `rooms.branch_id = consumptions.branch_id` — and SQLite cannot express
/// it. A foreign key ties a column to a row, not two rows to each other. So the
/// database happily accepts a header naming another branch's room (the schema test
/// asserts exactly that, so nobody mistakes the gap for coverage), and the rule lives
/// here instead, enforced in four places:
///
/// 1. when a room is chosen for a new document,
/// 2. in the branch predicate of every read query,
/// 3. again inside the posting transaction, against re-read rows,
/// 4. and in the architecture and security tests, which check that 1–3 exist.
///
/// ### Deactivated rooms: readable, not postable
///
/// A **posted** document whose room was retired afterwards stays fully readable — that
/// is what §33 is about, and the detail query filters neither `is_active` nor
/// `deleted_at`. But a **draft** against a deactivated room may not post, and this is
/// the one place where the Pemakaian rule is *stricter* than the Pemusnahan's. §15 says
/// so directly, and the reason is the direction of the physical act: taking expired
/// goods off a decommissioned shelf lowers risk, whereas recording that goods were used
/// in a room the clinic has closed asserts clinical activity in a place nobody is
/// working. The nurse's draft stays readable so they can see what was on it; posting is
/// what is refused.
abstract final class ConsumptionRoomPolicy {
  /// Whether [role] may consume stock at all.
  ///
  /// `perawat` only. Stated here as well as in `ConsumptionStatePolicy` because a
  /// selector asks *this* question — "is there a room list to build for this person" —
  /// and answering it by reaching for the state machine's actor map would be a screen
  /// depending on a transition table.
  static bool canConsume(UserRole role) => role == UserRole.perawat;

  /// The location types a consumption may ever draw from.
  ///
  /// A single-element set rather than a bare value, so a caller filtering a location
  /// list has the same shape the other policies offer — and so a future workflow that
  /// legitimately adds one changes this constant rather than a `==` at every call site.
  static const Set<StockLocationType> allowedSourceTypes = {
    StockLocationType.room,
  };

  /// Whether [room] may be the source of a consumption of [branchId].
  ///
  /// [room] is `null` when the id resolved to nothing at all.
  static ConsumptionRoomVerdict verifyRoom({
    required MasterRoom? room,
    required String branchId,
  }) {
    if (room == null) {
      return const ConsumptionRoomVerdict.rejected(
        ConsumptionRoomRejection.missing,
      );
    }
    // Branch before activity: "this room is not yours" must not be distinguishable
    // from "this room is switched off", or the message would tell a nurse something
    // true about another branch's room.
    if (room.branchId != branchId) {
      return const ConsumptionRoomVerdict.rejected(
        ConsumptionRoomRejection.branchMismatch,
      );
    }
    if (!room.isActive || room.isArchived) {
      return const ConsumptionRoomVerdict.rejected(
        ConsumptionRoomRejection.inactive,
      );
    }
    return const ConsumptionRoomVerdict.accepted();
  }

  /// Whether [room] may be *read* as the source of an existing document.
  ///
  /// The historical counterpart of [verifyRoom]: branch scope still applies — a
  /// document is never readable from another branch — but a retired room is accepted,
  /// because a posted consumption whose room was closed afterwards is exactly the
  /// history §33 keeps readable.
  static ConsumptionRoomVerdict verifyHistoricalRoom({
    required MasterRoom? room,
    required String branchId,
  }) {
    if (room == null) {
      return const ConsumptionRoomVerdict.rejected(
        ConsumptionRoomRejection.missing,
      );
    }
    if (room.branchId != branchId) {
      return const ConsumptionRoomVerdict.rejected(
        ConsumptionRoomRejection.branchMismatch,
      );
    }
    return const ConsumptionRoomVerdict.accepted();
  }

  /// Whether [locations] resolve to exactly one usable `room` location for [room].
  ///
  /// Both failure modes are kept apart rather than resolved:
  ///
  /// * **none** — there is nowhere the goods came from, and inventing a location would
  ///   post the ledger against a row that does not exist;
  /// * **more than one** — which location the goods left is a business fact. Picking
  ///   the first would silently reduce a balance nobody chose, and the room's real
  ///   shelf would still hold the stock.
  ///
  /// The type, the room and the branch are all re-checked on the resolved row: a
  /// location table can be misfiled, and a `branch_store` row carrying a `room_id`
  /// would otherwise pass a query that only asked for the room.
  static ConsumptionRoomVerdict verifyRoomLocation({
    required MasterRoom room,
    required String branchId,
    required List<MasterLocation> locations,
  }) {
    if (locations.isEmpty) {
      return const ConsumptionRoomVerdict.rejected(
        ConsumptionRoomRejection.locationMissing,
      );
    }
    if (locations.length > 1) {
      return const ConsumptionRoomVerdict.rejected(
        ConsumptionRoomRejection.locationAmbiguous,
      );
    }
    final location = locations.single;
    if (location.type != StockLocationType.room ||
        location.roomId != room.id ||
        location.branchId != branchId) {
      return const ConsumptionRoomVerdict.rejected(
        ConsumptionRoomRejection.locationMismatch,
      );
    }
    return const ConsumptionRoomVerdict.accepted();
  }

  /// Filters a list of rooms down to those a consumption may be raised against.
  ///
  /// Used by the room selector. It applies [verifyRoom] rather than re-deriving the
  /// rule, so a room that would be refused at creation is never offered in the first
  /// place.
  static List<MasterRoom> allowedRooms({
    required String branchId,
    required List<MasterRoom> rooms,
  }) => rooms
      .where((room) => verifyRoom(room: room, branchId: branchId).isAccepted)
      .toList(growable: false);
}
