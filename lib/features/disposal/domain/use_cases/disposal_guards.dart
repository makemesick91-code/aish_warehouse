import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/disposal_models.dart';
import '../services/disposal_expiry_policy.dart';
import '../services/disposal_location_policy.dart';
import '../services/disposal_quantity_policy.dart';
import '../services/disposal_reason_policy.dart';
import '../services/disposal_state_policy.dart';

/// The RBAC, location, expiry, batch, quantity and reason checks every Pemusnahan
/// use case shares (§13 … §19, G-E7).
///
/// They live in one place because a rule that is re-implemented per use case is a
/// rule that eventually differs per use case. Each guard reads the actor from the
/// database rather than trusting whatever id the caller passed, so a development
/// session (or, later, a token) can never grant a permission the stored user does
/// not have (O-8).
///
/// Every method here is a *refusal*: it either returns the value it verified or
/// throws. Nothing substitutes, guesses or repairs — a disposal that cannot be
/// posted as written is refused, never posted differently. That matters more on this
/// document than on any other in the application: `disposal` is the one movement
/// type with no counter-entry, so a quantity destroyed by mistake has nothing in the
/// ledger to find it by.
class DisposalGuards {
  const DisposalGuards(this._master);

  final MasterDataRepository _master;

  // --- actor ----------------------------------------------------------------

  /// Loads the actor and refuses inactive accounts.
  ///
  /// Applies whatever the document's age: unlike the item or batch data a historic
  /// disposal points at, the person destroying stock *right now* has to be a
  /// currently valid account (§14).
  Future<MasterUser> requireActiveUser(String userId) async {
    final user = await _master.userById(userId);
    if (user == null) {
      throw EntityNotFoundFailure(
        'Pengguna tidak ditemukan.',
        entity: 'users',
        id: userId,
      );
    }
    if (!user.isActive) {
      throw InactiveEntityFailure(
        'Akun ${user.fullName} sudah dinonaktifkan.',
        entity: 'users',
        id: userId,
      );
    }
    return user;
  }

  /// An actor with a disposal scope of its own — Petugas Warehouse or Kepala
  /// Cabang (§14).
  ///
  /// Perawat and Super Admin are refused here, not merely unrouted, and each for the
  /// reason `DisposalAccessPolicy` spells out. An account being powerful is not a
  /// reason to hand it somebody else's job (G-R4).
  ///
  /// A branch-scoped role without a branch is refused too, and the two checks are
  /// one on purpose: *"stok cabangnya sendiri"* is meaningless without a branch to
  /// compare, so a `kepala_cabang` row with `branch_id IS NULL` is a data fault
  /// rather than a permission that happens to be wide.
  Future<MasterUser> requireDisposalActor(String userId) async {
    final user = await requireActiveUser(userId);
    if (!DisposalStatePolicy.writeRoles.contains(user.role)) {
      throw InvalidReviewerFailure(
        'Hanya Petugas Warehouse dan Kepala Cabang yang dapat membuat dan '
        'memposting Pemusnahan. ${user.fullName} berperan sebagai '
        '${user.role.label}.',
        actorUserId: userId,
        requiredRole: UserRole.warehouse,
      );
    }
    if (DisposalLocationPolicy.requiresBranchScope(user.role) &&
        user.branchId == null) {
      throw UnauthorizedBranchFailure(
        'Akun ${user.fullName} belum terhubung ke cabang mana pun, sehingga '
        'tidak dapat memusnahkan stok.',
        actorUserId: userId,
        branchId: '',
      );
    }
    return user;
  }

  // --- source location (§15) ------------------------------------------------

  /// The one location a disposal draws from, verified against [actor].
  ///
  /// [requireOperational] is `true` for **new** work — creating a document, adding a
  /// line — and `false` when posting one that already exists. §15 explains the
  /// asymmetry: a disposal *out of* an archived location removes goods that are
  /// already unusable from a shelf that still physically holds them, which lowers
  /// risk rather than raising it. So an existing draft may still be posted against
  /// an archived source, provided the exact row is still there.
  ///
  /// The lookup is `locationById`, which returns archived rows too — that is what
  /// makes the distinction expressible at all. Nothing here falls back to another
  /// location when the exact row is gone: a missing source is an explicit failure,
  /// because posting against a substitute would reduce a balance nobody chose.
  Future<MasterLocation> requireSourceLocation({
    required MasterUser actor,
    required String locationId,
    bool requireOperational = true,
    String? disposalId,
  }) async {
    final location = await _master.locationById(locationId);
    final verdict = DisposalLocationPolicy.verifySource(
      actor: actor,
      location: location,
      requireOperational: requireOperational,
    );
    if (verdict.isAccepted) return location!;

    switch (verdict.rejection!) {
      case DisposalSourceRejection.missing:
        // On an existing document this is a broken historical reference rather
        // than a bad choice, and the two need different messages: one asks the
        // user to pick again, the other asks an administrator to repair data.
        if (disposalId != null) {
          throw HistoricalDisposalReferenceMissingFailure(
            'Pemusnahan tidak dapat diproses karena lokasi sumber historis '
            'tidak ditemukan. Hubungi administrator.',
            entity: 'stock_locations',
            id: locationId,
            disposalId: disposalId,
          );
        }
        throw DisposalSourceLocationNotFoundFailure(
          'Lokasi sumber tidak ditemukan.',
          locationId: locationId,
        );
      case DisposalSourceRejection.archived:
        throw DisposalSourceLocationInactiveFailure(
          'Lokasi "${location!.name}" sudah tidak aktif, sehingga tidak dapat '
          'dipakai untuk pemusnahan baru.',
          locationId: locationId,
        );
      case DisposalSourceRejection.branchMismatch:
        throw DisposalBranchMismatchFailure(
          'Lokasi ini bukan milik cabang Anda, sehingga stoknya tidak dapat '
          'dimusnahkan dari akun ini.',
          actorUserId: actor.id,
          actorBranchId: actor.branchId,
          locationId: locationId,
        );
      case DisposalSourceRejection.locationShapeInvalid:
        throw DisposalRoomMismatchFailure(
          'Lokasi stok ini tidak valid untuk pemusnahan. Hubungi administrator.',
          locationId: locationId,
          roomId: location!.roomId,
        );
      case DisposalSourceRejection.actorHasNoBranch:
        throw UnauthorizedBranchFailure(
          'Akun ${actor.fullName} belum terhubung ke cabang mana pun, sehingga '
          'tidak dapat memusnahkan stok.',
          actorUserId: actor.id,
          branchId: '',
        );
      case DisposalSourceRejection.roleHasNoScope:
      case DisposalSourceRejection.notWarehouse:
      case DisposalSourceRejection.warehouseNotAllowed:
        // One message for three refusals on purpose: telling "you may not use a
        // room" apart from "that room is not yours" would let the location table be
        // probed from the address bar.
        throw DisposalSourceLocationAccessDeniedFailure(
          'Anda tidak berwenang memusnahkan stok dari lokasi ini.',
          actorUserId: actor.id,
          locationId: locationId,
        );
    }
  }

  /// The room behind a `room` source, verified against the actor's branch.
  ///
  /// Asked in addition to [requireSourceLocation] rather than instead of it: that
  /// one compares `stock_locations.branch_id`, and this compares `rooms.branch_id`.
  /// They can disagree — a room moved between branches while a location row kept the
  /// old value would pass one and fail the other — and a disposal posting against
  /// that inconsistency would reduce a balance attributed to the wrong branch.
  ///
  /// A no-op for a warehouse or branch-store source, which have no room.
  Future<MasterRoom?> requireSourceRoom({
    required MasterUser actor,
    required MasterLocation location,
  }) async {
    final roomId = location.roomId;
    if (roomId == null) return null;

    // `historicalRoomById`, not `activeRoomById`: a deactivated room still
    // physically holds the expired stock, and refusing here would leave it
    // unremovable (§15/§34).
    final room = await _master.historicalRoomById(roomId);
    if (room == null) {
      throw DisposalRoomMismatchFailure(
        'Ruangan sumber tidak ditemukan. Hubungi administrator.',
        locationId: location.id,
        roomId: roomId,
      );
    }
    if (room.branchId != actor.branchId) {
      throw DisposalBranchMismatchFailure(
        'Ruangan ini bukan milik cabang Anda, sehingga stoknya tidak dapat '
        'dimusnahkan dari akun ini.',
        actorUserId: actor.id,
        actorBranchId: actor.branchId,
        locationId: location.id,
      );
    }
    return room;
  }

  /// The actor's branch must be the document's source branch.
  ///
  /// Asked in addition to the scoped queries rather than instead of them: a scoped
  /// read is what stops a foreign document being *fetched*, and this is what stops
  /// one being *written* if a caller ever passes an unscoped read by mistake.
  void requireScopeMatches({
    required MasterUser actor,
    required MasterLocation source,
  }) {
    final verdict = DisposalLocationPolicy.verifySource(
      actor: actor,
      location: source,
      // A *scope* question, not an operational one: whether the shelf is still in
      // service is [requireSourceLocation]'s call, and asking it twice with
      // different answers is how a posting comes to be refused for the wrong
      // reason.
      requireOperational: false,
    );
    if (verdict.isAccepted) return;
    throw DisposalSourceLocationAccessDeniedFailure(
      'Pemusnahan ini berada di luar cakupan akun Anda.',
      actorUserId: actor.id,
      locationId: source.id,
    );
  }

  // --- document state -------------------------------------------------------

  /// G-S1/G-S2 — the document must currently be in [expected].
  void requireStatus({
    required Disposal disposal,
    required DisposalStatus expected,
    DisposalStatus? attempted,
  }) {
    if (disposal.status == expected) return;
    if (disposal.isPosted) {
      throw DisposalAlreadyPostedFailure(
        'Pemusnahan ${disposal.docNumber} sudah diposting, sehingga tidak dapat '
        'diubah lagi.',
        disposalId: disposal.id,
        postedAt: disposal.postedAt,
      );
    }
    throw InvalidDisposalStateFailure(
      _stateMessage(disposal),
      disposalId: disposal.id,
      currentStatus: disposal.status,
      attemptedStatus: attempted,
    );
  }

  /// G-S1 — the transition must exist in the state machine and belong to this role.
  ///
  /// Asked in addition to [requireStatus] rather than instead of it: the status
  /// check produces the message a user needs ("already posted"), while this one is
  /// the structural check that no code path invents a transition the policy does not
  /// list.
  void requireTransition({
    required MasterUser actor,
    required Disposal disposal,
    required DisposalStatus to,
  }) {
    if (DisposalStatePolicy.isAllowedFor(
      role: actor.role,
      from: disposal.status,
      to: to,
    )) {
      return;
    }
    throw InvalidDisposalStateFailure(
      _stateMessage(disposal),
      disposalId: disposal.id,
      currentStatus: disposal.status,
      attemptedStatus: to,
    );
  }

  String _stateMessage(Disposal disposal) => switch (disposal.status) {
    DisposalStatus.draft => 'Pemusnahan ${disposal.docNumber} masih draft.',
    DisposalStatus.posted =>
      'Pemusnahan ${disposal.docNumber} sudah diposting dan bersifat final.',
  };

  /// Turns "the guarded write matched no rows" into the right failure. Reached when
  /// another device changed the document between the read and the write.
  Never concurrentUpdate(Disposal disposal) {
    throw ConcurrentDisposalUpdateFailure(
      'Pemusnahan ${disposal.docNumber} baru saja diubah dari perangkat lain. '
      'Muat ulang halaman lalu coba lagi.',
      disposalId: disposal.id,
    );
  }

  /// A document with nothing on it destroys nothing, so it cannot be posted.
  void requireNotEmpty({
    required String disposalId,
    required String docNumber,
    required List<DisposalLineReference> lines,
  }) {
    if (lines.isNotEmpty) return;
    throw DisposalLineRequiredFailure(
      'Pemusnahan $docNumber belum memuat barang, sehingga tidak dapat '
      'diposting.',
      disposalId: disposalId,
    );
  }

  // --- reason (G-E7/§19) ----------------------------------------------------

  /// G-E7's mandatory note, validated in Dart.
  ///
  /// The database CHECK is the floor: it refuses NULL and it refuses a string
  /// SQLite's `trim()` empties. This is the authority, and it is strictly
  /// stricter — `String.trim()` also strips tabs and newlines, so a reason of
  /// `"\n\t"` reaches the CHECK intact and is refused here.
  String requireReason({required String disposalId, required String? reason}) {
    final normalized = DisposalReasonPolicy.normalize(reason);
    if (normalized != null) return normalized;
    throw DisposalReasonRequiredFailure(
      'Catatan pemusnahan wajib diisi sebelum dokumen dapat diposting.',
      disposalId: disposalId,
    );
  }

  // --- lines ----------------------------------------------------------------

  /// The line, checked to belong to [disposalId].
  ///
  /// Both failures answer the same way — the line is not on this document — because
  /// telling "no such line" from "somebody else's line" apart would let the id be
  /// probed.
  DisposalLineReference requireLineOf({
    required String disposalId,
    required String lineId,
    required DisposalLineReference? line,
  }) {
    if (line != null && line.disposalId == disposalId) return line;
    throw DisposalLineNotFoundFailure(
      'Baris pemusnahan tidak ditemukan pada dokumen ini.',
      lineId: lineId,
    );
  }

  /// §18's floor: every quantity is strictly positive.
  void requirePositiveQty({required Quantity qty, String? lineId}) {
    if (DisposalQuantityPolicy.isValidLineQty(qty)) return;
    throw InvalidDisposalQuantityFailure(
      'Jumlah pemusnahan harus lebih besar dari 0 (diterima ${qty.format()}).',
      lineId: lineId,
      qty: qty,
    );
  }

  /// The `(item, batch)` position must not already exist on the document.
  ///
  /// The domain half of the partial unique index. Checked here so the user gets
  /// *"ubah baris yang ada"* rather than a driver error — and checked by the index
  /// too, so two devices racing produce exactly one line.
  void requirePositionFree({
    required String disposalId,
    required String itemId,
    required String batchId,
    required Iterable<DisposalLineReference> existing,
  }) {
    final key = DisposalQuantityPolicy.sourceKey(itemId, batchId);
    for (final line in existing) {
      if (line.positionKey == key) {
        throw DuplicateDisposalLineFailure(
          'Batch ini sudah ada pada dokumen pemusnahan ini. Ubah jumlah baris '
          'yang ada, bukan menambah baris baru.',
          disposalId: disposalId,
          itemId: itemId,
          batchId: batchId,
        );
      }
    }
  }

  // --- items and batches (§16) ----------------------------------------------

  /// The item a line names, **deactivated rows included**.
  ///
  /// The opposite default to every other document's add path, and deliberately: an
  /// item withdrawn from the catalogue can still be rotting on a shelf, and refusing
  /// to let it be destroyed would leave stock nobody can ever remove (§17/§34). What
  /// is still enforced is that the row is physically *there*.
  Future<MasterItem> requireItem({
    required String disposalId,
    required String itemId,
  }) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw HistoricalDisposalReferenceMissingFailure(
        'Pemusnahan tidak dapat diproses karena barang historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'items',
        id: itemId,
        disposalId: disposalId,
      );
    }
    return item;
  }

  /// §9/§16 — the item must be batch-tracked, and the batch must be its own.
  ///
  /// The `has_expiry` check is what keeps this milestone honest. An item without an
  /// expiry date has nothing that can be past it, so a disposal line naming one
  /// would be a disposal for some *other* reason — damaged, recalled, rejected on
  /// arrival — and each of those is a workflow with its own eligibility rules and
  /// its own audit requirements. Letting one in here would give it none of them.
  Future<MasterBatch> requireBatchConsistency({
    required String disposalId,
    required MasterItem item,
    required String batchId,
  }) async {
    if (!item.hasExpiry) {
      throw DisposalItemMustHaveExpiryFailure(
        'Barang ${item.sku} tidak dilacak per batch, sehingga tidak dapat '
        'dimusnahkan melalui dokumen ini. Pemusnahan pada milestone ini hanya '
        'untuk barang kedaluwarsa.',
        itemId: item.id,
      );
    }

    final batch = await _master.batchById(batchId);
    if (batch == null) {
      throw HistoricalDisposalReferenceMissingFailure(
        'Pemusnahan tidak dapat diproses karena batch historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'item_batches',
        id: batchId,
        disposalId: disposalId,
      );
    }
    if (batch.itemId != item.id) {
      throw InvalidDisposalBatchFailure(
        'Batch ${batch.batchNo} bukan milik barang ${item.sku}.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    return batch;
  }

  /// G-E7 — only a batch that has already expired may be destroyed.
  ///
  /// Applied when a line is added, when it is edited, and again when the document is
  /// posted; the last one is the one that matters, and it matters in **both**
  /// directions. A batch that expired while the draft sat open legitimately becomes
  /// eligible — which is why the draft is revalidated rather than frozen — and a
  /// batch chosen by a stale form that is still in date is refused however certain
  /// the user is.
  ///
  /// There is no confirmation and no reason that passes this. A `disposal` movement
  /// has no counter-entry, so stock removed by mistake has nothing in the ledger to
  /// find it by.
  void requireExpired({
    required MasterBatch batch,
    required DateTime nowUtc,
    String? lineId,
  }) {
    if (DisposalExpiryPolicy.isDisposable(
      expiryDate: batch.expiryDate,
      nowUtc: nowUtc,
    )) {
      return;
    }
    throw BatchNotExpiredForDisposalFailure(
      'Batch ${batch.batchNo} belum kedaluwarsa '
      '(ED ${DateOnly.formatIso(batch.expiryDate)}), sehingga tidak dapat '
      'dimusnahkan. Hanya barang yang sudah melewati tanggal kedaluwarsa yang '
      'boleh dimusnahkan.',
      batchId: batch.id,
      batchNo: batch.batchNo,
      expiryDate: batch.expiryDate,
      lineId: lineId,
    );
  }

  // --- stock (§18) ----------------------------------------------------------

  /// The shelf must hold at least [requested] of one exact position.
  void requireSufficientStock({
    required String itemId,
    required String itemSku,
    required String unit,
    required String locationId,
    required String batchId,
    required String batchNo,
    required Quantity requested,
    required Quantity available,
  }) {
    if (!DisposalQuantityPolicy.exceedsAvailable(
      requested: requested,
      available: available,
    )) {
      return;
    }
    throw InsufficientDisposalStockFailure(
      'Saldo $itemSku batch $batchNo di lokasi ini tidak mencukupi: tersedia '
      '${available.formatWithUnit(unit)}, diminta '
      '${requested.formatWithUnit(unit)}.',
      itemId: itemId,
      locationId: locationId,
      batchId: batchId,
      available: available,
      requested: requested,
    );
  }

  /// The position must have something on the shelf at all (§17).
  ///
  /// Distinct from [requireSufficientStock] because the answer is different: there is
  /// nothing to reduce a quantity *to*, and the picker should not have offered it.
  Never positionHasNoStock({
    required String itemId,
    required String itemSku,
    required String batchNo,
    required String locationId,
  }) {
    throw InsufficientDisposalStockFailure(
      'Batch $batchNo dari $itemSku tidak memiliki saldo di lokasi ini, '
      'sehingga tidak dapat dimusnahkan.',
      itemId: itemId,
      locationId: locationId,
      batchId: '',
      available: Quantity.zero(),
      requested: Quantity.zero(),
    );
  }

  // --- set integrity (§23) --------------------------------------------------

  /// Refuses a document whose plain line set and joined read disagree.
  ///
  /// Both directions matter, and they fail in opposite ways:
  ///
  /// * a **missing** line means the joined read dropped one — an inner join on an
  ///   item or batch row that is physically gone — so posting would destroy less
  ///   stock than the document says, and every per-line check would still pass;
  /// * an **extra** line means the joined read produced one the plain select does
  ///   not know about, which should be impossible and therefore must not be posted
  ///   on.
  ///
  /// [expectedLineIds] comes from a plain select that no join can filter;
  /// [loadedLineIds] is what the joined detail produced. The comparison is a set
  /// difference in memory, so the healthy case costs no query at all.
  void requireLineSetIntegrity({
    required String disposalId,
    required Iterable<String> expectedLineIds,
    required Iterable<String> loadedLineIds,
  }) {
    final expected = expectedLineIds.toSet();
    final loaded = loadedLineIds.toSet();
    final missing = expected.difference(loaded).toList(growable: false);
    final extra = loaded.difference(expected).toList(growable: false);
    if (missing.isEmpty && extra.isEmpty) return;

    throw DisposalLineIntegrityFailure(
      'Daftar barang pemusnahan tidak dapat dimuat sepenuhnya, sehingga posting '
      'dibatalkan. Hubungi administrator.',
      disposalId: disposalId,
      missingLineIds: missing,
      extraLineIds: extra,
    );
  }

  /// Every id a document's lines point at must still resolve.
  ///
  /// Items and batches, checked as **sets** rather than per line, so a document with
  /// twelve batches of one product costs two comparisons rather than twenty-four
  /// lookups. A missing reference is an explicit failure that names the table and
  /// the id an administrator has to repair — never a skipped line and never a
  /// substitution (§34).
  void requireReferencesResolve({
    required String disposalId,
    required List<DisposalLineReference> lines,
    required Set<String> resolvedItemIds,
    required Set<String> resolvedBatchIds,
  }) {
    for (final line in lines) {
      if (!resolvedItemIds.contains(line.itemId)) {
        throw HistoricalDisposalReferenceMissingFailure(
          'Pemusnahan tidak dapat diproses karena barang historis tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'items',
          id: line.itemId,
          disposalId: disposalId,
        );
      }
      if (!resolvedBatchIds.contains(line.batchId)) {
        throw HistoricalDisposalReferenceMissingFailure(
          'Pemusnahan tidak dapat diproses karena batch historis tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'item_batches',
          id: line.batchId,
          disposalId: disposalId,
        );
      }
    }
  }
}
