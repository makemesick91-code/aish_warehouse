import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import 'disposal_state_policy.dart';

/// Why a location may not be a disposal's source.
///
/// Distinct values rather than one boolean, because the guards turn each into a
/// different sentence and the tests assert which rule fired. They are deliberately
/// *not* all surfaced to the user with different wording: telling "another branch's
/// room" apart from "no such location" would let the ids be probed, so the guards
/// collapse several of these into one message while keeping the distinction here.
enum DisposalSourceRejection {
  /// No such location row at all.
  missing,

  /// The location row is soft-deleted, and the document is a *new* one.
  archived,

  /// The acting role has no disposal scope of its own (`perawat`, `super_admin`).
  roleHasNoScope,

  /// A `warehouse` actor named something that is not Warehouse Pusat.
  notWarehouse,

  /// A `kepala_cabang` actor named Warehouse Pusat, or a location with no branch.
  warehouseNotAllowed,

  /// The location belongs to another branch.
  branchMismatch,

  /// A `room` location whose `room_id` is null, or a `branch_store` carrying one —
  /// the location table's own CHECK already refuses these, so reaching one means
  /// the row is corrupt rather than that the user chose badly.
  locationShapeInvalid,

  /// The acting user holds a branch-scoped role but no branch.
  actorHasNoBranch,
}

/// The outcome of a source-location check.
class DisposalSourceVerdict {
  const DisposalSourceVerdict._(this.rejection);

  const DisposalSourceVerdict.accepted() : rejection = null;

  const DisposalSourceVerdict.rejected(DisposalSourceRejection rejection)
    : this._(rejection);

  /// `null` when the location was accepted.
  final DisposalSourceRejection? rejection;

  bool get isAccepted => rejection == null;

  bool get isRejected => rejection != null;
}

/// Which locations an actor may destroy stock at (§15).
///
/// ```
/// Warehouse      → StockLocationType.warehouse   (branch_id NULL, room_id NULL)
/// Kepala Cabang  → StockLocationType.branchStore (branch_id = actor.branchId)
///                → StockLocationType.room        (branch_id = actor.branchId)
/// Perawat        → nothing
/// Super Admin    → nothing
/// ```
///
/// Pure and synchronous: it takes the actor and the location row and returns a
/// verdict, so the route guard, the source selector, the create path and the
/// posting transaction all reach the same answer from the same function rather than
/// from four similar-looking `if` statements. The caller supplies the rows; nothing
/// here reads a database, and nothing here hard-codes a seed id — *"Warehouse
/// Pusat"* is a **type**, not an identifier, which is the only definition that
/// survives a second warehouse being opened or a different installation being
/// seeded.
///
/// ### Why the warehouse's scope is a type and the branch's is an id
///
/// They are different shapes of fact. There is one central warehouse in the model
/// (spec §1.1), and it is identified by `type = 'warehouse'` with no branch to
/// compare against — so "may this actor use it" reduces to "is this actor the
/// warehouse role". A branch head's scope is the opposite: several branches exist,
/// each with a store and rooms, so the question is entirely about *which* branch,
/// and `stock_locations.branch_id = users.branch_id` is the comparison. Writing
/// both as one rule would mean either hard-coding a warehouse id or pretending the
/// warehouse has a branch.
///
/// ### One source per document
///
/// This policy answers "may this actor use this location", never "which locations
/// may this document use" — because a document uses exactly one, fixed when it is
/// created and never updated (there is no DAO statement that could change it). The
/// invariant is therefore structural rather than checked: a second source cannot be
/// expressed.
abstract final class DisposalLocationPolicy {
  /// Whether [location] may be the source of a disposal by [actor].
  ///
  /// [requireOperational] is `true` for **new** work — creating a document, adding
  /// a line — and `false` when *completing* work that already exists. §15 spells
  /// the difference out, and it is the opposite of the Distribusi's: a distribution
  /// into an archived room would put goods somewhere nobody is working, so it is
  /// refused; a disposal *out of* an archived location removes goods that are
  /// already unusable from a shelf that still physically holds them, which lowers
  /// risk rather than raising it. So an existing draft may still be posted against
  /// an archived source, provided the exact row is still there and every other
  /// check passes.
  static DisposalSourceVerdict verifySource({
    required MasterUser actor,
    required MasterLocation? location,
    bool requireOperational = true,
  }) {
    if (location == null) {
      return const DisposalSourceVerdict.rejected(
        DisposalSourceRejection.missing,
      );
    }
    final transitionActor = DisposalStatePolicy.actorOf(actor.role);
    if (transitionActor == null) {
      return const DisposalSourceVerdict.rejected(
        DisposalSourceRejection.roleHasNoScope,
      );
    }
    if (requireOperational && location.isArchived) {
      return const DisposalSourceVerdict.rejected(
        DisposalSourceRejection.archived,
      );
    }

    switch (transitionActor) {
      case DisposalTransitionActor.warehouse:
        if (location.type != StockLocationType.warehouse) {
          return const DisposalSourceVerdict.rejected(
            DisposalSourceRejection.notWarehouse,
          );
        }
        // The location table's CHECK already guarantees this for a `warehouse`
        // row. Asserted anyway, because a corrupt row reaching the ledger would
        // reduce a balance nobody can attribute to a place.
        if (location.branchId != null || location.roomId != null) {
          return const DisposalSourceVerdict.rejected(
            DisposalSourceRejection.locationShapeInvalid,
          );
        }
        return const DisposalSourceVerdict.accepted();

      case DisposalTransitionActor.kepalaCabang:
        final actorBranchId = actor.branchId;
        if (actorBranchId == null) {
          return const DisposalSourceVerdict.rejected(
            DisposalSourceRejection.actorHasNoBranch,
          );
        }
        if (location.type == StockLocationType.warehouse) {
          return const DisposalSourceVerdict.rejected(
            DisposalSourceRejection.warehouseNotAllowed,
          );
        }
        // The branch check runs **before** the shape check, so a refusal never
        // confirms anything about another branch's room.
        if (location.branchId != actorBranchId) {
          return const DisposalSourceVerdict.rejected(
            DisposalSourceRejection.branchMismatch,
          );
        }
        return switch (location.type) {
          StockLocationType.branchStore =>
            location.roomId == null
                ? const DisposalSourceVerdict.accepted()
                : const DisposalSourceVerdict.rejected(
                    DisposalSourceRejection.locationShapeInvalid,
                  ),
          StockLocationType.room =>
            location.roomId == null
                ? const DisposalSourceVerdict.rejected(
                    DisposalSourceRejection.locationShapeInvalid,
                  )
                : const DisposalSourceVerdict.accepted(),
          // Unreachable — handled above — but stated so a new location type
          // cannot be added without this switch failing to compile.
          StockLocationType.warehouse => const DisposalSourceVerdict.rejected(
            DisposalSourceRejection.warehouseNotAllowed,
          ),
        };
    }
  }

  /// The location types [role] may ever name, for a screen building a selector.
  ///
  /// Empty for a role with no disposal scope, which is what makes *"Perawat has no
  /// source to choose"* a fact the UI reads rather than a branch it writes.
  static Set<StockLocationType> allowedTypesFor(UserRole role) =>
      switch (DisposalStatePolicy.actorOf(role)) {
        null => const <StockLocationType>{},
        DisposalTransitionActor.warehouse => const {
          StockLocationType.warehouse,
        },
        DisposalTransitionActor.kepalaCabang => const {
          StockLocationType.branchStore,
          StockLocationType.room,
        },
      };

  /// Whether [role] scopes its locations by branch.
  ///
  /// `true` for the Kepala Cabang and `false` for the warehouse, and asking it here
  /// rather than deciding per caller is what keeps the two provider families from
  /// disagreeing about which one needs a branch id.
  static bool requiresBranchScope(UserRole role) =>
      DisposalStatePolicy.actorOf(role) == DisposalTransitionActor.kepalaCabang;

  /// Filters a list of locations down to those [actor] may use as a source.
  ///
  /// Used by the selector on both screens. It applies [verifySource] rather than
  /// re-deriving the rule, so a location that would be refused at posting is never
  /// offered in the first place.
  static List<MasterLocation> allowedSources({
    required MasterUser actor,
    required List<MasterLocation> locations,
  }) => locations
      .where(
        (location) => verifySource(actor: actor, location: location).isAccepted,
      )
      .toList(growable: false);
}
