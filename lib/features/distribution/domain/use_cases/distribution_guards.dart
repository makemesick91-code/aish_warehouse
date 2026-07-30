import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/distribution_models.dart';
import '../services/distribution_expiry_policy.dart';
import '../services/distribution_fefo_policy.dart';
import '../services/distribution_quantity_policy.dart';
import '../services/distribution_room_policy.dart';
import '../services/distribution_state_policy.dart';

/// The RBAC, branch, room, location, quantity, batch and FEFO checks every
/// Distribusi use case shares (G-T1 … G-T4, G-E2/G-E3/G-E4).
///
/// They live in one place because a rule that is re-implemented per use case is a
/// rule that eventually differs per use case. Each guard reads the actor from the
/// database rather than trusting whatever id the caller passed, so a development
/// session (or, later, a token) can never grant a permission the stored user does
/// not have (O-8).
///
/// Every method here is a *refusal*: it either returns the value it verified or
/// throws. Nothing substitutes, guesses or repairs — a distribution that cannot be
/// posted as written is refused, never posted differently.
class DistributionGuards {
  const DistributionGuards(this._master);

  final MasterDataRepository _master;

  // --- actor ----------------------------------------------------------------

  /// Loads the actor and refuses inactive accounts.
  ///
  /// Applies whatever the document's age: unlike the branch, room or item data a
  /// historic distribution points at, the person moving stock *right now* has to be a
  /// currently valid account (§13.1).
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

  /// The only actor a Distribusi has (spec §3.1).
  ///
  /// Requires a branch as well as the role, and the two are one check on purpose:
  /// *"dari Gudang Cabang ke ruangan dalam cabang yang sama"* is meaningless without a
  /// branch to compare, and a branch-scoped account without one is a data fault rather
  /// than a permission that happens to be wide.
  ///
  /// Warehouse, Perawat and Super Admin are refused here, not merely unrouted. Spec
  /// §3.1 gives *"Distribusi ke ruangan"* to `kepala_cabang` alone, and an account
  /// being powerful is not a reason to hand it somebody else's job (G-R4).
  Future<MasterUser> requireBranchHeadActor(String userId) async {
    final user = await requireActiveUser(userId);
    if (user.role != DistributionStatePolicy.writeRole) {
      throw InvalidReviewerFailure(
        'Hanya Kepala Cabang yang dapat membuat dan memposting Distribusi. '
        '${user.fullName} berperan sebagai ${user.role.label}.',
        actorUserId: userId,
        requiredRole: DistributionStatePolicy.writeRole,
      );
    }
    if (user.branchId == null) {
      throw UnauthorizedBranchFailure(
        'Akun ${user.fullName} belum terhubung ke cabang mana pun, sehingga '
        'tidak dapat mendistribusikan barang.',
        actorUserId: userId,
        branchId: '',
      );
    }
    return user;
  }

  /// G-T1/G-R2 — the actor's branch must be the document's.
  ///
  /// Asked in addition to the scoped queries rather than instead of them: a scoped
  /// read is what stops a foreign document being *fetched*, and this is what stops one
  /// being *written* if a caller ever passes an unscoped read by mistake.
  void requireBranchMatches({
    required MasterUser actor,
    required String documentBranchId,
  }) {
    if (actor.branchId == documentBranchId) return;
    throw DistributionBranchMismatchFailure(
      'Distribusi ini milik cabang lain, sehingga tidak dapat diakses dari '
      'akun ini.',
      actorUserId: actor.id,
      actorBranchId: actor.branchId,
      documentBranchId: documentBranchId,
    );
  }

  /// The branch a new distribution is raised for must be live and active.
  ///
  /// Only asked when *creating*: an existing document whose branch was retired
  /// afterwards stays readable and — because the goods are physically at that branch —
  /// its posting is refused by the branch store check rather than by this one, which
  /// produces the message about the store nobody can distribute from.
  Future<MasterBranch> requireActiveBranch(String branchId) async {
    final branches = await _master.activeBranches();
    for (final branch in branches) {
      if (branch.id == branchId) return branch;
    }
    throw InactiveEntityFailure(
      'Cabang tidak aktif atau tidak ditemukan, sehingga distribusi tidak '
      'dapat dibuat.',
      entity: 'branches',
      id: branchId,
    );
  }

  // --- source: the Gudang Cabang (G-T1/§14) ---------------------------------

  /// The single *Gudang Cabang* a distribution draws from.
  ///
  /// Both failure modes are explicit rather than resolved:
  ///
  /// * **none** — there is nothing to distribute from, and inventing a location would
  ///   post the ledger against a row that does not exist;
  /// * **more than one** — which store the goods left is a business fact. Picking the
  ///   first would silently take the movement out of a location nobody chose, and the
  ///   balance it reduced would be the wrong one.
  ///
  /// No seed id is hard-coded anywhere on this path: the location is looked up by type
  /// and branch every time.
  ///
  /// ### No historical fallback, unlike Good Receipt
  ///
  /// A Good Receipt completes work that already exists — the goods are physically at
  /// the branch and must be booked in — so it falls back to the *exact* archived store
  /// row when no live one is left. A distribution is the opposite: it is new work, and
  /// an archived store is one an administrator has taken out of service. Taking stock
  /// out of it would record a movement from a location the clinic no longer operates.
  /// So this refuses, and §32 says the same thing: *"Branch-store nonaktif harus
  /// memblokir posting."*
  Future<MasterLocation> requireBranchStore(String branchId) async {
    final locations = await _master.activeBranchStoreLocations(branchId);
    final verdict = DistributionRoomPolicy.verifyBranchStore(
      branchId: branchId,
      locations: locations,
    );
    if (verdict.isAccepted) return locations.single;

    switch (verdict.rejection!) {
      case DistributionRoomRejection.locationMissing:
        throw DistributionBranchStoreNotFoundFailure(
          'Lokasi Gudang Cabang belum tersedia atau sudah tidak aktif, '
          'sehingga distribusi tidak dapat dilakukan. Hubungi administrator.',
          branchId: branchId,
        );
      case DistributionRoomRejection.locationAmbiguous:
        throw DistributionBranchStoreAmbiguousFailure(
          'Terdapat lebih dari satu lokasi Gudang Cabang untuk cabang ini, '
          'sehingga sistem tidak dapat menentukan sumber distribusi. Hubungi '
          'administrator.',
          branchId: branchId,
          locationIds: locations
              .map((location) => location.id)
              .toList(growable: false),
        );
      case DistributionRoomRejection.locationMismatch:
      case DistributionRoomRejection.missing:
      case DistributionRoomRejection.branchMismatch:
      case DistributionRoomRejection.inactive:
        throw DistributionBranchStoreNotFoundFailure(
          'Lokasi Gudang Cabang cabang ini tidak valid, sehingga distribusi '
          'tidak dapat dilakukan. Hubungi administrator.',
          branchId: branchId,
        );
    }
  }

  // --- destination: the room and its location (G-T1/§14) --------------------

  /// The room a line targets, verified against [branchId].
  ///
  /// Used for **new** work and again at posting, and the same rules apply both times:
  /// a room in another branch is refused (G-T1) and a deactivated one is refused too,
  /// because stock must not be moved into a destination that is not operational (§32).
  /// The branch check runs first so the message never confirms anything about another
  /// branch's room.
  Future<MasterRoom> requireRoomForDistribution({
    required String branchId,
    required String roomId,
  }) async {
    final room = await _master.historicalRoomById(roomId);
    final verdict = DistributionRoomPolicy.verifyRoom(
      room: room,
      branchId: branchId,
    );
    if (verdict.isAccepted) return room!;

    switch (verdict.rejection!) {
      case DistributionRoomRejection.missing:
        throw EntityNotFoundFailure(
          'Ruangan tujuan tidak ditemukan.',
          entity: 'rooms',
          id: roomId,
        );
      case DistributionRoomRejection.branchMismatch:
        throw DistributionRoomBranchMismatchFailure(
          'Ruangan tujuan bukan milik cabang ini, sehingga tidak dapat menjadi '
          'tujuan distribusi.',
          roomId: roomId,
          documentBranchId: branchId,
        );
      case DistributionRoomRejection.inactive:
        throw DistributionRoomInactiveFailure(
          'Ruangan "${room!.name}" sudah dinonaktifkan, sehingga stok tidak '
          'dapat dipindahkan ke ruangan tersebut. Hapus atau ganti barisnya.',
          roomId: roomId,
        );
      case DistributionRoomRejection.locationMissing:
      case DistributionRoomRejection.locationAmbiguous:
      case DistributionRoomRejection.locationMismatch:
        // `verifyRoom` cannot produce these; they belong to
        // [requireRoomLocation]. Listed so a new rejection value cannot be added
        // without this switch failing to compile.
        throw DistributionRoomLocationNotFoundFailure(
          'Lokasi stok ruangan tidak valid. Hubungi administrator.',
          roomId: roomId,
        );
    }
  }

  /// The single `room` stock location goods enter for [room].
  ///
  /// Same two failure modes as the branch store, same reasoning — and, like it, no
  /// historical fallback: an archived room location is one that is out of service, and
  /// crediting it would put stock somewhere nobody is working.
  Future<MasterLocation> requireRoomLocation({
    required MasterRoom room,
    required String branchId,
  }) async {
    final locations = await _master.activeRoomLocations(room.id);
    final verdict = DistributionRoomPolicy.verifyRoomLocation(
      room: room,
      branchId: branchId,
      locations: locations,
    );
    if (verdict.isAccepted) return locations.single;

    switch (verdict.rejection!) {
      case DistributionRoomRejection.locationAmbiguous:
        throw DistributionRoomLocationAmbiguousFailure(
          'Terdapat lebih dari satu lokasi stok untuk ruangan '
          '"${room.name}", sehingga sistem tidak dapat menentukan tujuan '
          'distribusi. Hubungi administrator.',
          roomId: room.id,
          locationIds: locations
              .map((location) => location.id)
              .toList(growable: false),
        );
      case DistributionRoomRejection.locationMissing:
      case DistributionRoomRejection.locationMismatch:
      case DistributionRoomRejection.missing:
      case DistributionRoomRejection.branchMismatch:
      case DistributionRoomRejection.inactive:
        throw DistributionRoomLocationNotFoundFailure(
          'Ruangan "${room.name}" belum memiliki lokasi stok yang valid, '
          'sehingga tidak dapat menerima distribusi. Hubungi administrator.',
          roomId: room.id,
        );
    }
  }

  /// The source and the destination must be two different locations.
  ///
  /// `stock_movements` has a CHECK against a movement to itself, but failing there
  /// would surface as a driver error. Asked here, it is a sentence a branch head can
  /// read — and it catches a corrupt location table before any movement is written.
  void requireDistinctLeg({
    required MasterLocation source,
    required MasterLocation destination,
  }) {
    if (DistributionRoomPolicy.isDistinctLeg(
      sourceLocationId: source.id,
      destinationLocationId: destination.id,
    )) {
      return;
    }
    throw const InvalidLocationFailure(
      'Lokasi sumber dan lokasi tujuan distribusi tidak boleh sama.',
    );
  }

  // --- document state -------------------------------------------------------

  /// G-S1/G-S2 — the document must currently be in [expected].
  void requireStatus({
    required Distribution distribution,
    required DistributionStatus expected,
    DistributionStatus? attempted,
  }) {
    if (distribution.status == expected) return;
    if (distribution.isPosted) {
      throw DistributionAlreadyPostedFailure(
        'Distribusi ${distribution.docNumber} sudah diposting, sehingga tidak '
        'dapat diubah lagi.',
        distributionId: distribution.id,
        postedAt: distribution.postedAt,
      );
    }
    throw InvalidDistributionStateFailure(
      _stateMessage(distribution),
      distributionId: distribution.id,
      currentStatus: distribution.status,
      attemptedStatus: attempted,
    );
  }

  /// G-S1 — the transition must exist in the state machine and belong to this role.
  ///
  /// Asked in addition to [requireStatus] rather than instead of it: the status check
  /// produces the message a user needs ("already posted"), while this one is the
  /// structural check that no code path invents a transition the policy does not list.
  void requireTransition({
    required MasterUser actor,
    required Distribution distribution,
    required DistributionStatus to,
  }) {
    if (DistributionStatePolicy.isAllowedFor(
      role: actor.role,
      from: distribution.status,
      to: to,
    )) {
      return;
    }
    throw InvalidDistributionStateFailure(
      _stateMessage(distribution),
      distributionId: distribution.id,
      currentStatus: distribution.status,
      attemptedStatus: to,
    );
  }

  String _stateMessage(Distribution distribution) =>
      switch (distribution.status) {
        DistributionStatus.draft =>
          'Distribusi ${distribution.docNumber} masih draft.',
        DistributionStatus.posted =>
          'Distribusi ${distribution.docNumber} sudah diposting dan bersifat '
              'final.',
      };

  /// Turns "the guarded write matched no rows" into the right failure. Reached when
  /// another device changed the document between the read and the write.
  Never concurrentUpdate(Distribution distribution) {
    throw ConcurrentDistributionUpdateFailure(
      'Distribusi ${distribution.docNumber} baru saja diubah dari perangkat '
      'lain. Muat ulang halaman lalu coba lagi.',
      distributionId: distribution.id,
    );
  }

  /// A document with nothing on it moves nothing, so it cannot be posted.
  void requireNotEmpty({
    required String distributionId,
    required String docNumber,
    required List<DistributionLineReference> lines,
  }) {
    if (lines.isNotEmpty) return;
    throw DistributionLineRequiredFailure(
      'Distribusi $docNumber belum memuat barang, sehingga tidak dapat '
      'diposting.',
      distributionId: distributionId,
    );
  }

  // --- lines ----------------------------------------------------------------

  /// The line, checked to belong to [distributionId].
  ///
  /// Both failures answer the same way — the line is not on this document — because
  /// telling "no such line" from "somebody else's line" apart would let the id be
  /// probed.
  DistributionLineReference requireLineOf({
    required String distributionId,
    required String lineId,
    required DistributionLineReference? line,
  }) {
    if (line != null && line.distributionId == distributionId) return line;
    throw DistributionLineNotFoundFailure(
      'Baris distribusi tidak ditemukan pada dokumen ini.',
      lineId: lineId,
    );
  }

  /// G-T2's floor: every quantity is strictly positive.
  void requirePositiveQty({required Quantity qty, String? lineId}) {
    if (DistributionQuantityPolicy.isValidLineQty(qty)) return;
    throw InvalidDistributionQuantityFailure(
      'Jumlah distribusi harus lebih besar dari 0 '
      '(diterima ${qty.format()}).',
      lineId: lineId,
      qty: qty,
    );
  }

  /// The `(room, item, batch)` position must not already exist on the document.
  ///
  /// The domain half of the two partial unique indexes. Checked here so the branch
  /// head gets *"ubah baris yang ada"* rather than a driver error — and checked by the
  /// index too, so two devices racing produce exactly one line.
  void requirePositionFree({
    required String distributionId,
    required String roomId,
    required String itemId,
    String? batchId,
    required Iterable<DistributionLineReference> existing,
  }) {
    final key = '$roomId|$itemId|${batchId ?? ''}';
    for (final line in existing) {
      if (line.positionKey == key) {
        throw DuplicateDistributionLineFailure(
          batchId == null
              ? 'Barang ini sudah ada pada ruangan tersebut. Ubah jumlah baris '
                    'yang ada, bukan menambah baris baru.'
              : 'Alokasi batch ini sudah ada pada ruangan tersebut. Ubah '
                    'jumlah baris yang ada, bukan menambah baris baru.',
          distributionId: distributionId,
          roomId: roomId,
          itemId: itemId,
          batchId: batchId,
        );
      }
    }
  }

  /// No `(room, item)` line at all may exist yet, whatever its batch.
  ///
  /// The check the *automatic* add path makes, and a stricter one than
  /// [requirePositionFree] on purpose: FEFO allocates a position across whichever
  /// batches it needs, so "add this item to this room" is meaningless once the room
  /// already holds part of it. The branch head edits the existing allocation instead —
  /// which is the only way the aggregate FEFO evaluation stays comprehensible.
  void requireItemNotInRoom({
    required String distributionId,
    required String roomId,
    required String itemId,
    required Iterable<DistributionLineReference> existing,
  }) {
    for (final line in existing) {
      if (line.roomId == roomId && line.itemId == itemId) {
        throw DuplicateDistributionLineFailure(
          'Barang ini sudah dialokasikan untuk ruangan tersebut. Ubah jumlah '
          'atau alokasi batch pada baris yang ada.',
          distributionId: distributionId,
          roomId: roomId,
          itemId: itemId,
          batchId: line.batchId,
        );
      }
    }
  }

  // --- items and batches (G-E2) ---------------------------------------------

  /// The item a **new** line names: live and active (G-A4).
  ///
  /// Adding a line is new work, so master data that has been withdrawn may not be
  /// distributed. An item deactivated *after* it was added keeps its line — that read
  /// goes through [requireHistoricalItem].
  Future<MasterItem> requireActiveItem(String itemId) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw EntityNotFoundFailure(
        'Barang tidak ditemukan.',
        entity: 'items',
        id: itemId,
      );
    }
    if (!item.isActive) {
      throw InactiveEntityFailure(
        'Barang ${item.sku} sudah dinonaktifkan, sehingga tidak dapat '
        'didistribusikan.',
        entity: 'items',
        id: itemId,
      );
    }
    return item;
  }

  /// G-E1/G-E2 — an expiry-tracked item always carries a batch, an item without expiry
  /// never does.
  ///
  /// Also checks that the batch belongs to the item, and that the row is physically
  /// there. A missing batch is a *historical* failure rather than a validation one: the
  /// line was legitimate when it was added, and what has gone wrong is the reference.
  Future<MasterBatch?> requireBatchConsistency({
    required String distributionId,
    required MasterItem item,
    required String? batchId,
  }) async {
    if (item.hasExpiry && batchId == null) {
      throw InvalidDistributionBatchFailure(
        'Barang ${item.sku} memiliki tanggal kedaluwarsa, sehingga batch wajib '
        'dipilih untuk distribusi.',
        itemId: item.id,
      );
    }
    if (!item.hasExpiry && batchId != null) {
      throw InvalidDistributionBatchFailure(
        'Barang ${item.sku} tidak dilacak per batch, sehingga tidak boleh '
        'memiliki batch.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    if (batchId == null) return null;

    final batch = await _master.batchById(batchId);
    if (batch == null) {
      throw HistoricalDistributionReferenceMissingFailure(
        'Distribusi tidak dapat diproses karena batch historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'item_batches',
        id: batchId,
        distributionId: distributionId,
      );
    }
    if (batch.itemId != item.id) {
      throw InvalidDistributionBatchFailure(
        'Batch ${batch.batchNo} bukan milik barang ${item.sku}.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    return batch;
  }

  /// G-E4 — an expired batch is blocked from distribution outright.
  ///
  /// Applied when a line is added, when it is edited, and again when the document is
  /// posted; the last one is the one that matters. A batch with two days of shelf life
  /// left when the form opened may be past its date by the time *Posting Distribusi* is
  /// pressed, and distributing it would put unusable goods in a treatment room.
  ///
  /// There is no confirmation and no note that passes this. Expired stock leaves
  /// through disposal (G-E7), which is a different document this milestone does not
  /// open.
  void requireNotExpired({
    required MasterBatch? batch,
    required DateTime nowUtc,
    String? lineId,
  }) {
    if (batch == null) return;
    if (!DistributionExpiryPolicy.isExpired(
      expiryDate: batch.expiryDate,
      nowUtc: nowUtc,
    )) {
      return;
    }
    throw ExpiredBatchForDistributionFailure(
      'Batch ${batch.batchNo} sudah kedaluwarsa '
      '(ED ${DateOnly.formatIso(batch.expiryDate)}), sehingga tidak dapat '
      'didistribusikan. Barang kedaluwarsa hanya boleh dikeluarkan melalui '
      'pemusnahan.',
      batchId: batch.id,
      batchNo: batch.batchNo,
      expiryDate: batch.expiryDate,
      lineId: lineId,
    );
  }

  // --- FEFO (G-E3) ----------------------------------------------------------

  /// G-E3 — a batch younger than the FEFO suggestion needs a written reason.
  ///
  /// [selection] must be **every allocation of [itemId] on the document**, across all
  /// rooms, and [candidates] the store's *gross* holdings right now — see
  /// `DistributionFefoPolicy` for why the aggregate is the only grain that answers
  /// this correctly.
  ///
  /// [reasonByBatchId] is the reason each allocation carries, keyed by batch. A
  /// violating batch with no valid reason is refused; a batch that violates nothing
  /// needs none. The returned map is the **normalized** reason to store: trimmed where
  /// it is required, and `null` everywhere else, so a line can never carry a
  /// justification for a decision nobody made.
  Map<String, String?> requireFefoCompliance({
    required String itemId,
    required String itemSku,
    required List<DistributionBatchCandidate> candidates,
    required List<DistributionAllocation> selection,
    required Map<String, String?> reasonByBatchId,
    required DateTime nowUtc,
    String? lineId,
  }) {
    final violations = DistributionFefoPolicy.violations(
      itemId: itemId,
      candidates: candidates,
      selection: selection,
      nowUtc: nowUtc,
    );

    final normalized = <String, String?>{};
    for (final violation in violations) {
      final reason = DistributionFefoPolicy.normalizeReason(
        reasonByBatchId[violation.selectedBatchId],
      );
      if (reason == null) {
        throw DistributionFefoOverrideReasonRequiredFailure(
          'Batch ${violation.selectedBatchNo} dipilih meskipun batch '
          '${violation.skippedBatchNo} (ED '
          '${DateOnly.formatIso(violation.skippedExpiryDate)}) masih tersisa '
          '${violation.skippedAvailableQty.format()}. Untuk $itemSku, '
          'pemilihan di luar urutan FEFO wajib disertai catatan alasan.',
          itemId: itemId,
          selectedBatchId: violation.selectedBatchId,
          selectedBatchNo: violation.selectedBatchNo,
          skippedBatchId: violation.skippedBatchId,
          skippedBatchNo: violation.skippedBatchNo,
          skippedExpiryDate: violation.skippedExpiryDate,
          lineId: lineId,
        );
      }
      normalized[violation.selectedBatchId] = reason;
    }

    // Every batch that violated nothing stores `null`. A reason offered where none is
    // required is dropped rather than refused: it is a UI leftover — the form keeps
    // the field mounted while the branch head shuffles quantities — and an audit trail
    // for a decision that turned out to be compliant would be worse than no note at
    // all. §9 states the resulting invariant directly: *reason null jika tidak
    // override*.
    for (final allocation in selection) {
      final batchId = allocation.batchId;
      if (batchId == null) continue;
      normalized.putIfAbsent(batchId, () => null);
    }
    return normalized;
  }

  // --- stock (G-T2) ---------------------------------------------------------

  /// The store must hold at least [requested] of one exact position.
  ///
  /// [requested] is the **aggregate** across every room the document targets, which is
  /// the number G-T2 is about: two rooms each taking `3` from a batch holding `5` fails
  /// here even though neither line exceeds the balance on its own.
  void requireSufficientStock({
    required String itemId,
    required String itemSku,
    required String unit,
    required String locationId,
    String? batchId,
    String? batchNo,
    required Quantity requested,
    required Quantity available,
  }) {
    if (!DistributionQuantityPolicy.exceedsAvailable(
      requested: requested,
      available: available,
    )) {
      return;
    }
    final position = batchNo == null ? itemSku : '$itemSku batch $batchNo';
    throw InsufficientBranchStockFailure(
      'Saldo Gudang Cabang untuk $position tidak mencukupi: tersedia '
      '${available.formatWithUnit(unit)}, dibutuhkan '
      '${requested.formatWithUnit(unit)} untuk seluruh ruangan pada distribusi '
      'ini.',
      itemId: itemId,
      locationId: locationId,
      batchId: batchId,
      available: available,
      requested: requested,
    );
  }

  /// The item must have something distributable at all (§15).
  ///
  /// Distinct from [requireSufficientStock] because the answer is different: there is
  /// nothing to reduce a quantity *to*, and the picker should not have offered it.
  Never itemHasNoStock({
    required String itemId,
    required String itemSku,
    required String locationId,
    bool onlyExpired = false,
  }) {
    throw DistributionItemHasNoStockFailure(
      onlyExpired
          ? 'Seluruh stok $itemSku di Gudang Cabang sudah kedaluwarsa, '
                'sehingga tidak dapat didistribusikan. Barang kedaluwarsa '
                'hanya boleh dikeluarkan melalui pemusnahan.'
          : 'Barang $itemSku tidak memiliki saldo di Gudang Cabang, sehingga '
                'tidak dapat didistribusikan.',
      itemId: itemId,
      locationId: locationId,
    );
  }

  // --- set integrity (§22) --------------------------------------------------

  /// Refuses a document whose plain line set and joined read disagree.
  ///
  /// Both directions matter, and they fail in opposite ways:
  ///
  /// * a **missing** line means the joined read dropped one — an inner join on a room
  ///   or item row that is physically gone — so posting would move less stock than the
  ///   document says, and every per-line check would still pass;
  /// * an **extra** line means the joined read produced one the plain select does not
  ///   know about, which should be impossible and therefore must not be posted on.
  ///
  /// [expectedLineIds] comes from a plain select that no join can filter;
  /// [loadedLineIds] is what the joined detail produced. The comparison is a set
  /// difference in memory, so the healthy case costs no query at all.
  void requireLineSetIntegrity({
    required String distributionId,
    required Iterable<String> expectedLineIds,
    required Iterable<String> loadedLineIds,
  }) {
    final expected = expectedLineIds.toSet();
    final loaded = loadedLineIds.toSet();
    final missing = expected.difference(loaded).toList(growable: false);
    final extra = loaded.difference(expected).toList(growable: false);
    if (missing.isEmpty && extra.isEmpty) return;

    throw DistributionLineIntegrityFailure(
      'Daftar barang distribusi tidak dapat dimuat sepenuhnya, sehingga '
      'posting dibatalkan. Hubungi administrator.',
      distributionId: distributionId,
      missingLineIds: missing,
      extraLineIds: extra,
    );
  }

  /// Every id a document's lines point at must still resolve.
  ///
  /// Rooms, items and batches, checked as **sets** rather than per line, so a
  /// document with twelve batches of one product costs three comparisons rather than
  /// thirty-six lookups. A missing reference is an explicit failure that names the
  /// table and the id an administrator has to repair — never a skipped line and never
  /// a substitution (§32).
  Future<void> requireReferencesResolve({
    required String distributionId,
    required List<DistributionLineReference> lines,
    required Set<String> resolvedRoomIds,
    required Set<String> resolvedItemIds,
    required Set<String> resolvedBatchIds,
  }) async {
    for (final line in lines) {
      if (!resolvedRoomIds.contains(line.roomId)) {
        throw HistoricalDistributionReferenceMissingFailure(
          'Distribusi tidak dapat diproses karena ruangan historis tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'rooms',
          id: line.roomId,
          distributionId: distributionId,
        );
      }
      if (!resolvedItemIds.contains(line.itemId)) {
        throw HistoricalDistributionReferenceMissingFailure(
          'Distribusi tidak dapat diproses karena barang historis tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'items',
          id: line.itemId,
          distributionId: distributionId,
        );
      }
      final batchId = line.batchId;
      if (batchId != null && !resolvedBatchIds.contains(batchId)) {
        throw HistoricalDistributionReferenceMissingFailure(
          'Distribusi tidak dapat diproses karena batch historis tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'item_batches',
          id: batchId,
          distributionId: distributionId,
        );
      }
    }
  }

  /// The item a **posted or draft** line names. Deactivated items pass; missing ones do
  /// not.
  ///
  /// The counterpart of [requireActiveItem]: a document that already exists must not
  /// become unpostable because an administrator withdrew a product afterwards — the
  /// goods are on the shelf either way. What is still enforced is that the row is
  /// physically *there* (§32).
  Future<MasterItem> requireHistoricalItem({
    required String distributionId,
    required String itemId,
  }) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw HistoricalDistributionReferenceMissingFailure(
        'Distribusi tidak dapat diproses karena barang historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'items',
        id: itemId,
        distributionId: distributionId,
      );
    }
    return item;
  }

  /// The referenced row a distribution depends on is gone entirely.
  Never historicalReferenceMissing({
    required String distributionId,
    required String entity,
    required String id,
  }) {
    throw HistoricalDistributionReferenceMissingFailure(
      'Distribusi tidak dapat diproses karena referensi historis tidak '
      'ditemukan. Hubungi administrator.',
      entity: entity,
      id: id,
      distributionId: distributionId,
    );
  }
}
