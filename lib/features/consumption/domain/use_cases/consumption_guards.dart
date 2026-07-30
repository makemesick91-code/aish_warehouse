import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/consumption_models.dart';
import '../services/consumption_expiry_policy.dart';
import '../services/consumption_quantity_policy.dart';
import '../services/consumption_room_policy.dart';
import '../services/consumption_state_policy.dart';

/// The RBAC, ownership, branch, room, location, expiry, batch and quantity checks every
/// Pemakaian use case shares (§13 … §18).
///
/// They live in one place because a rule that is re-implemented per use case is a rule
/// that eventually differs per use case. Each guard reads the actor from the database
/// rather than trusting whatever id the caller passed, so a development session (or,
/// later, a token) can never grant a permission the stored user does not have (O-8).
///
/// Every method here is a *refusal*: it either returns the value it verified or throws.
/// Nothing substitutes, guesses or repairs — a consumption that cannot be posted as
/// written is refused, never posted differently.
///
/// ### The one guard no earlier document needed
///
/// [requireOwnership] is new in this milestone. Every earlier document is authorised by
/// *place* — a Kepala Cabang may act on any of their branch's Purchase Requests — and a
/// Pemakaian draft is authorised by *person*: it is one nurse's record of what they used
/// during a shift nobody else worked. It is checked here, in the SQL predicate of every
/// guarded write, and in the read queries, because it is the rule that has three
/// independent chances to be forgotten.
class ConsumptionGuards {
  const ConsumptionGuards(this._master);

  final MasterDataRepository _master;

  // --- actor (§14) ----------------------------------------------------------

  /// Loads the actor and refuses inactive accounts.
  ///
  /// Applies whatever the document's age: unlike the room or item data a historic
  /// consumption points at, the person recording usage *right now* has to be a currently
  /// valid account.
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

  /// The only actor a Pemakaian has (§14).
  ///
  /// Requires a branch as well as the role, and the two are one check on purpose: *"room
  /// in their own branch"* is meaningless without a branch to compare, and a
  /// branch-scoped account without one is a data fault rather than a permission that
  /// happens to be wide.
  ///
  /// Kepala Cabang, Warehouse and Super Admin are refused here, not merely unrouted, and
  /// each for the reason `ConsumptionAccessPolicy` spells out. An account being senior is
  /// not a reason to hand it somebody else's account of their shift (G-R4).
  Future<MasterUser> requireNurseActor(String userId) async {
    final user = await requireActiveUser(userId);
    if (user.role != ConsumptionStatePolicy.writeRole) {
      throw InvalidReviewerFailure(
        'Hanya Perawat yang dapat mencatat dan memposting Pemakaian. '
        '${user.fullName} berperan sebagai ${user.role.label}.',
        actorUserId: userId,
        requiredRole: ConsumptionStatePolicy.writeRole,
      );
    }
    if (user.branchId == null) {
      throw UnauthorizedBranchFailure(
        'Akun ${user.fullName} belum terhubung ke cabang mana pun, sehingga '
        'tidak dapat mencatat pemakaian.',
        actorUserId: userId,
        branchId: '',
      );
    }
    return user;
  }

  /// §14 — the acting nurse must be the one who created the document.
  ///
  /// Asked in addition to the guarded SQL predicates rather than instead of them: the
  /// predicate is what stops a foreign draft being *written*, and this is what produces
  /// the sentence a user can read instead of a silent zero-rows failure.
  void requireOwnership({
    required MasterUser actor,
    required Consumption consumption,
  }) {
    if (consumption.isOwnedBy(actor.id)) return;
    throw ConsumptionNotOwnedFailure(
      'Pemakaian ini dicatat oleh perawat lain, sehingga tidak dapat diubah '
      'atau diposting dari akun ini.',
      consumptionId: consumption.id,
      actorUserId: actor.id,
    );
  }

  /// G-R2 — the actor's branch must be the document's.
  ///
  /// Asked in addition to the scoped queries rather than instead of them: a scoped read
  /// is what stops a foreign document being *fetched*, and this is what stops one being
  /// *written* if a caller ever passes an unscoped read by mistake. It also catches the
  /// case ownership alone would miss — a nurse whose branch was changed while a draft of
  /// theirs sat open in the old one.
  void requireBranchMatches({
    required MasterUser actor,
    required String documentBranchId,
  }) {
    if (actor.branchId == documentBranchId) return;
    throw ConsumptionBranchMismatchFailure(
      'Pemakaian ini milik cabang lain, sehingga tidak dapat diakses dari akun '
      'ini.',
      actorUserId: actor.id,
      actorBranchId: actor.branchId,
      documentBranchId: documentBranchId,
    );
  }

  /// The branch a new consumption is raised for must be live and active.
  ///
  /// Only asked when *creating*: an existing document whose branch was retired
  /// afterwards stays readable, and its posting is refused by the room check rather than
  /// by this one — which produces the message about the room nobody is working in.
  Future<MasterBranch> requireActiveBranch(String branchId) async {
    final branches = await _master.activeBranches();
    for (final branch in branches) {
      if (branch.id == branchId) return branch;
    }
    throw InactiveEntityFailure(
      'Cabang tidak aktif atau tidak ditemukan, sehingga pemakaian tidak dapat '
      'dicatat.',
      entity: 'branches',
      id: branchId,
    );
  }

  // --- room and its location (§15) ------------------------------------------

  /// The room a consumption draws from, verified against [branchId].
  ///
  /// Used for **new** work and again at posting, and the same rules apply both times: a
  /// room in another branch is refused and a deactivated one is refused too, because
  /// goods must not be recorded as used in a room the clinic is no longer operating
  /// (§15). The branch check runs first so the message never confirms anything about
  /// another branch's room.
  ///
  /// The lookup is `historicalRoomById`, which returns retired rows too — that is what
  /// makes the *inactive* refusal expressible at all rather than collapsing into "not
  /// found".
  Future<MasterRoom> requireRoomForConsumption({
    required String branchId,
    required String roomId,
  }) async {
    final room = await _master.historicalRoomById(roomId);
    final verdict = ConsumptionRoomPolicy.verifyRoom(
      room: room,
      branchId: branchId,
    );
    if (verdict.isAccepted) return room!;

    switch (verdict.rejection!) {
      case ConsumptionRoomRejection.missing:
        throw EntityNotFoundFailure(
          'Ruangan tidak ditemukan.',
          entity: 'rooms',
          id: roomId,
        );
      case ConsumptionRoomRejection.branchMismatch:
        throw ConsumptionRoomBranchMismatchFailure(
          'Ruangan ini bukan milik cabang Anda, sehingga pemakaiannya tidak '
          'dapat dicatat dari akun ini.',
          roomId: roomId,
          documentBranchId: branchId,
        );
      case ConsumptionRoomRejection.inactive:
        throw ConsumptionRoomInactiveFailure(
          'Ruangan "${room!.name}" sudah dinonaktifkan, sehingga pemakaian di '
          'ruangan tersebut tidak dapat dicatat atau diposting.',
          roomId: roomId,
        );
      case ConsumptionRoomRejection.locationMissing:
      case ConsumptionRoomRejection.locationAmbiguous:
      case ConsumptionRoomRejection.locationMismatch:
        // `verifyRoom` cannot produce these; they belong to [requireRoomLocation].
        // Listed so a new rejection value cannot be added without this switch failing
        // to compile.
        throw ConsumptionRoomLocationNotFoundFailure(
          'Lokasi stok ruangan tidak valid. Hubungi administrator.',
          roomId: roomId,
        );
    }
  }

  /// The room a **historic** document names, for reading rather than posting.
  ///
  /// Branch scope still applies — a document is never readable from another branch — but
  /// a retired room is accepted, because a posted consumption whose room was closed
  /// afterwards is exactly the history §33 keeps readable.
  Future<MasterRoom> requireHistoricalRoom({
    required String consumptionId,
    required String branchId,
    required String roomId,
  }) async {
    final room = await _master.historicalRoomById(roomId);
    final verdict = ConsumptionRoomPolicy.verifyHistoricalRoom(
      room: room,
      branchId: branchId,
    );
    if (verdict.isAccepted) return room!;

    switch (verdict.rejection!) {
      case ConsumptionRoomRejection.missing:
        throw HistoricalConsumptionReferenceMissingFailure(
          'Pemakaian tidak dapat diproses karena ruangan historis tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'rooms',
          id: roomId,
          consumptionId: consumptionId,
        );
      case ConsumptionRoomRejection.branchMismatch:
        throw ConsumptionRoomBranchMismatchFailure(
          'Ruangan pada dokumen ini bukan milik cabang Anda.',
          roomId: roomId,
          documentBranchId: branchId,
        );
      case ConsumptionRoomRejection.inactive:
      case ConsumptionRoomRejection.locationMissing:
      case ConsumptionRoomRejection.locationAmbiguous:
      case ConsumptionRoomRejection.locationMismatch:
        // `verifyHistoricalRoom` cannot produce these. Listed for exhaustiveness.
        throw ConsumptionRoomLocationNotFoundFailure(
          'Lokasi stok ruangan tidak valid. Hubungi administrator.',
          roomId: roomId,
        );
    }
  }

  /// The single `room` stock location a consumption draws from.
  ///
  /// Both failure modes are explicit rather than resolved:
  ///
  /// * **none** — there is nowhere the goods came from, and inventing a location would
  ///   post the ledger against a row that does not exist;
  /// * **more than one** — which location the goods left is a business fact. Picking the
  ///   first would silently reduce a balance nobody chose, and the room's real shelf
  ///   would still hold the stock.
  ///
  /// No seed id is hard-coded anywhere on this path: the location is looked up by type
  /// and room every time.
  ///
  /// ### No historical fallback
  ///
  /// A Good Receipt falls back to the *exact* archived store row when no live one is
  /// left, because the goods are physically at the branch and must be booked in. A
  /// consumption is the opposite: an archived room location is one an administrator has
  /// taken out of service, and recording usage out of it would assert clinical activity
  /// in a place nobody is working. So this refuses, and §15 says the same thing.
  Future<MasterLocation> requireRoomLocation({
    required MasterRoom room,
    required String branchId,
  }) async {
    final locations = await _master.activeRoomLocations(room.id);
    final verdict = ConsumptionRoomPolicy.verifyRoomLocation(
      room: room,
      branchId: branchId,
      locations: locations,
    );
    if (verdict.isAccepted) return locations.single;

    switch (verdict.rejection!) {
      case ConsumptionRoomRejection.locationAmbiguous:
        throw ConsumptionRoomLocationAmbiguousFailure(
          'Terdapat lebih dari satu lokasi stok untuk ruangan "${room.name}", '
          'sehingga sistem tidak dapat menentukan sumber pemakaian. Hubungi '
          'administrator.',
          roomId: room.id,
          locationIds: locations
              .map((location) => location.id)
              .toList(growable: false),
        );
      case ConsumptionRoomRejection.locationMissing:
      case ConsumptionRoomRejection.locationMismatch:
      case ConsumptionRoomRejection.missing:
      case ConsumptionRoomRejection.branchMismatch:
      case ConsumptionRoomRejection.inactive:
        throw ConsumptionRoomLocationNotFoundFailure(
          'Ruangan "${room.name}" belum memiliki lokasi stok yang valid, '
          'sehingga pemakaiannya tidak dapat dicatat. Hubungi administrator.',
          roomId: room.id,
        );
    }
  }

  // --- document state -------------------------------------------------------

  /// G-S1/G-S2 — the document must currently be in [expected].
  void requireStatus({
    required Consumption consumption,
    required ConsumptionStatus expected,
    ConsumptionStatus? attempted,
  }) {
    if (consumption.status == expected) return;
    if (consumption.isPosted) {
      throw ConsumptionAlreadyPostedFailure(
        'Pemakaian ${consumption.docNumber} sudah diposting, sehingga tidak '
        'dapat diubah lagi.',
        consumptionId: consumption.id,
        postedAt: consumption.postedAt,
      );
    }
    throw InvalidConsumptionStateFailure(
      _stateMessage(consumption),
      consumptionId: consumption.id,
      currentStatus: consumption.status,
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
    required Consumption consumption,
    required ConsumptionStatus to,
  }) {
    if (ConsumptionStatePolicy.isAllowedFor(
      role: actor.role,
      from: consumption.status,
      to: to,
    )) {
      return;
    }
    throw InvalidConsumptionStateFailure(
      _stateMessage(consumption),
      consumptionId: consumption.id,
      currentStatus: consumption.status,
      attemptedStatus: to,
    );
  }

  String _stateMessage(Consumption consumption) => switch (consumption.status) {
    ConsumptionStatus.draft =>
      'Pemakaian ${consumption.docNumber} masih draft.',
    ConsumptionStatus.posted =>
      'Pemakaian ${consumption.docNumber} sudah diposting dan bersifat final.',
  };

  /// Turns "the guarded write matched no rows" into the right failure. Reached when
  /// another device changed the document between the read and the write.
  Never concurrentUpdate(Consumption consumption) {
    throw ConcurrentConsumptionUpdateFailure(
      'Pemakaian ${consumption.docNumber} baru saja diubah dari perangkat lain. '
      'Muat ulang halaman lalu coba lagi.',
      consumptionId: consumption.id,
    );
  }

  /// A document with nothing on it records no usage, so it cannot be posted.
  void requireNotEmpty({
    required String consumptionId,
    required String docNumber,
    required List<ConsumptionLineReference> lines,
  }) {
    if (lines.isNotEmpty) return;
    throw ConsumptionLineRequiredFailure(
      'Pemakaian $docNumber belum memuat barang, sehingga tidak dapat '
      'diposting.',
      consumptionId: consumptionId,
    );
  }

  // --- lines ----------------------------------------------------------------

  /// The line, checked to belong to [consumptionId].
  ///
  /// Both failures answer the same way — the line is not on this document — because
  /// telling "no such line" from "somebody else's line" apart would let the id be
  /// probed.
  ConsumptionLineReference requireLineOf({
    required String consumptionId,
    required String lineId,
    required ConsumptionLineReference? line,
  }) {
    if (line != null && line.consumptionId == consumptionId) return line;
    throw ConsumptionLineNotFoundFailure(
      'Baris pemakaian tidak ditemukan pada dokumen ini.',
      lineId: lineId,
    );
  }

  /// §18's floor: every quantity is strictly positive.
  void requirePositiveQty({required Quantity qty, String? lineId}) {
    if (ConsumptionQuantityPolicy.isValidLineQty(qty)) return;
    throw InvalidConsumptionQuantityFailure(
      'Jumlah pemakaian harus lebih besar dari 0 (diterima ${qty.format()}).',
      lineId: lineId,
      qty: qty,
    );
  }

  /// The `(item, batch)` position must not already exist on the document.
  ///
  /// The domain half of the two partial unique indexes. Checked here so the nurse gets
  /// *"ubah baris yang ada"* rather than a driver error — and checked by the indexes too,
  /// so two devices racing produce exactly one line.
  void requirePositionFree({
    required String consumptionId,
    required String itemId,
    String? batchId,
    required Iterable<ConsumptionLineReference> existing,
  }) {
    final key = ConsumptionQuantityPolicy.sourceKey(itemId, batchId);
    for (final line in existing) {
      if (line.positionKey == key) {
        throw DuplicateConsumptionLineFailure(
          batchId == null
              ? 'Barang ini sudah ada pada dokumen pemakaian ini. Ubah jumlah '
                    'baris yang ada, bukan menambah baris baru.'
              : 'Batch ini sudah ada pada dokumen pemakaian ini. Ubah jumlah '
                    'baris yang ada, bukan menambah baris baru.',
          consumptionId: consumptionId,
          itemId: itemId,
          batchId: batchId,
        );
      }
    }
  }

  // --- items and batches (§17) ----------------------------------------------

  /// The item a **new** line names: live and active (G-A4).
  ///
  /// Adding a line is new work, so master data that has been withdrawn may not be
  /// picked. An item deactivated *after* it was added keeps its line — that read goes
  /// through [requireHistoricalItem].
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
        'Barang ${item.sku} sudah dinonaktifkan, sehingga tidak dapat dicatat '
        'sebagai pemakaian baru.',
        entity: 'items',
        id: itemId,
      );
    }
    return item;
  }

  /// The item a **posted or draft** line names. Deactivated items pass; missing ones do
  /// not.
  ///
  /// The counterpart of [requireActiveItem]: a document that already exists must not
  /// become unpostable because an administrator withdrew a product afterwards — the
  /// goods came off the room's shelf either way. What is still enforced is that the row
  /// is physically *there* (§33).
  Future<MasterItem> requireHistoricalItem({
    required String consumptionId,
    required String itemId,
  }) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw HistoricalConsumptionReferenceMissingFailure(
        'Pemakaian tidak dapat diproses karena barang historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'items',
        id: itemId,
        consumptionId: consumptionId,
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
  ///
  /// Both directions are refused with their own failure type, because the two mistakes
  /// are opposite and the nurse's next action differs: one needs a batch chosen, the
  /// other needs one cleared.
  Future<MasterBatch?> requireBatchConsistency({
    required String consumptionId,
    required MasterItem item,
    required String? batchId,
  }) async {
    if (item.hasExpiry && batchId == null) {
      throw ConsumptionBatchRequiredFailure(
        'Barang ${item.sku} memiliki tanggal kedaluwarsa, sehingga batch wajib '
        'dipilih untuk pemakaian.',
        itemId: item.id,
      );
    }
    if (!item.hasExpiry && batchId != null) {
      throw ConsumptionBatchNotAllowedFailure(
        'Barang ${item.sku} tidak dilacak per batch, sehingga tidak boleh '
        'memiliki batch.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    if (batchId == null) return null;

    final batch = await _master.batchById(batchId);
    if (batch == null) {
      throw HistoricalConsumptionReferenceMissingFailure(
        'Pemakaian tidak dapat diproses karena batch historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'item_batches',
        id: batchId,
        consumptionId: consumptionId,
      );
    }
    if (batch.itemId != item.id) {
      throw InvalidConsumptionBatchFailure(
        'Batch ${batch.batchNo} bukan milik barang ${item.sku}.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    return batch;
  }

  /// §17/G-E7 — an expired batch is blocked from consumption outright.
  ///
  /// Applied when a line is added, when it is edited, and again when the document is
  /// posted; the last one is the one that matters. A batch with a day of shelf life left
  /// when the form opened may be past its date by the time *Posting Pemakaian* is
  /// pressed, and consuming it would take expired stock out of the ledger as though it
  /// had been legitimately used — leaving G-E7's audit trail with nothing to describe.
  ///
  /// There is no confirmation and no note that passes this. Expired stock leaves through
  /// a Pemusnahan, which is a different document with its own reason and its own actor.
  ///
  /// A `null` batch is a no-op: an item without an expiry date has nothing that can be
  /// past it.
  void requireNotExpired({
    required MasterBatch? batch,
    required DateTime nowUtc,
    String? lineId,
  }) {
    if (batch == null) return;
    if (ConsumptionExpiryPolicy.isConsumable(
      expiryDate: batch.expiryDate,
      nowUtc: nowUtc,
    )) {
      return;
    }
    throw ExpiredBatchForConsumptionFailure(
      'Batch ${batch.batchNo} sudah kedaluwarsa '
      '(ED ${DateOnly.formatIso(batch.expiryDate)}), sehingga tidak dapat '
      'dipakai. Barang kedaluwarsa hanya boleh dikeluarkan melalui pemusnahan.',
      batchId: batch.id,
      batchNo: batch.batchNo,
      expiryDate: batch.expiryDate,
      lineId: lineId,
    );
  }

  // --- stock (§18) ----------------------------------------------------------

  /// The room must hold at least [requested] of one exact position.
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
    if (!ConsumptionQuantityPolicy.exceedsAvailable(
      requested: requested,
      available: available,
    )) {
      return;
    }
    final position = batchNo == null ? itemSku : '$itemSku batch $batchNo';
    throw InsufficientRoomStockFailure(
      'Saldo ruangan untuk $position tidak mencukupi: tersedia '
      '${available.formatWithUnit(unit)}, diminta '
      '${requested.formatWithUnit(unit)}.',
      itemId: itemId,
      locationId: locationId,
      batchId: batchId,
      available: available,
      requested: requested,
    );
  }

  /// The position must have something in the room at all (§16).
  ///
  /// Distinct from [requireSufficientStock] because the answer is different: there is
  /// nothing to reduce a quantity *to*, and the picker should not have offered it.
  Never positionHasNoStock({
    required String itemId,
    required String itemSku,
    String? batchNo,
    required String locationId,
  }) {
    throw ConsumptionItemHasNoStockFailure(
      batchNo == null
          ? 'Barang $itemSku tidak memiliki saldo di ruangan ini, sehingga '
                'tidak dapat dicatat sebagai pemakaian.'
          : 'Batch $batchNo dari $itemSku tidak memiliki saldo di ruangan ini, '
                'sehingga tidak dapat dicatat sebagai pemakaian.',
      itemId: itemId,
      locationId: locationId,
    );
  }

  // --- set integrity (§22) --------------------------------------------------

  /// Refuses a document whose plain line set and joined read disagree.
  ///
  /// Both directions matter, and they fail in opposite ways:
  ///
  /// * a **missing** line means the joined read dropped one — an inner join on an item
  ///   row that is physically gone — so posting would consume less stock than the
  ///   document says, and every per-line check would still pass;
  /// * an **extra** line means the joined read produced one the plain select does not
  ///   know about, which should be impossible and therefore must not be posted on.
  ///
  /// [expectedLineIds] comes from a plain select that no join can filter;
  /// [loadedLineIds] is what the joined detail produced. The comparison is a set
  /// difference in memory, so the healthy case costs no query at all.
  void requireLineSetIntegrity({
    required String consumptionId,
    required Iterable<String> expectedLineIds,
    required Iterable<String> loadedLineIds,
  }) {
    final expected = expectedLineIds.toSet();
    final loaded = loadedLineIds.toSet();
    final missing = expected.difference(loaded).toList(growable: false);
    final extra = loaded.difference(expected).toList(growable: false);
    if (missing.isEmpty && extra.isEmpty) return;

    throw ConsumptionLineIntegrityFailure(
      'Daftar barang pemakaian tidak dapat dimuat sepenuhnya, sehingga posting '
      'dibatalkan. Hubungi administrator.',
      consumptionId: consumptionId,
      missingLineIds: missing,
      extraLineIds: extra,
    );
  }

  /// Every id a document's lines point at must still resolve.
  ///
  /// Items and batches, checked as **sets** rather than per line, so a document with
  /// twelve batches of one product costs two comparisons rather than twenty-four
  /// lookups. A missing reference is an explicit failure that names the table and the id
  /// an administrator has to repair — never a skipped line and never a substitution
  /// (§33).
  ///
  /// A line with a null batch contributes nothing to the batch comparison, which is what
  /// makes an item without expiry pass rather than look like a broken reference.
  void requireReferencesResolve({
    required String consumptionId,
    required List<ConsumptionLineReference> lines,
    required Set<String> resolvedItemIds,
    required Set<String> resolvedBatchIds,
  }) {
    for (final line in lines) {
      if (!resolvedItemIds.contains(line.itemId)) {
        throw HistoricalConsumptionReferenceMissingFailure(
          'Pemakaian tidak dapat diproses karena barang historis tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'items',
          id: line.itemId,
          consumptionId: consumptionId,
        );
      }
      final batchId = line.batchId;
      if (batchId != null && !resolvedBatchIds.contains(batchId)) {
        throw HistoricalConsumptionReferenceMissingFailure(
          'Pemakaian tidak dapat diproses karena batch historis tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'item_batches',
          id: batchId,
          consumptionId: consumptionId,
        );
      }
    }
  }

  /// The referenced row a consumption depends on is gone entirely.
  Never historicalReferenceMissing({
    required String consumptionId,
    required String entity,
    required String id,
  }) {
    throw HistoricalConsumptionReferenceMissingFailure(
      'Pemakaian tidak dapat diproses karena referensi historis tidak '
      'ditemukan. Hubungi administrator.',
      entity: entity,
      id: id,
      consumptionId: consumptionId,
    );
  }
}
