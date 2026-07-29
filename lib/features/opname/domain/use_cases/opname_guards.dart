import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/opname_models.dart';

/// The RBAC and state checks every Stok Opname use case shares (G-R1, G-R2,
/// G-R4, G-S1, G-S2).
///
/// They live in one place because a rule that is re-implemented per use case is
/// a rule that eventually differs per use case. Each guard reads the actor from
/// the database rather than trusting whatever id the caller passed, so a
/// development session (or, later, a token) can never grant a permission the
/// stored user does not have.
class OpnameGuards {
  const OpnameGuards(this._master);

  final MasterDataRepository _master;

  /// Loads the actor and refuses inactive accounts.
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

  /// Loads the actor and additionally requires a specific role and a branch.
  Future<MasterUser> requireActor(String userId, UserRole role) async {
    final user = await requireActiveUser(userId);
    if (user.role != role) {
      throw InvalidReviewerFailure(
        _wrongRoleMessage(user, role),
        actorUserId: userId,
        requiredRole: role,
      );
    }
    if (user.branchId == null) {
      throw ValidationFailure(
        'Pengguna ${user.fullName} belum terhubung ke cabang mana pun.',
      );
    }
    return user;
  }

  String _wrongRoleMessage(MasterUser user, UserRole required) =>
      switch (required) {
        UserRole.perawat =>
          'Hanya Perawat yang dapat mengisi stok opname. '
              '${user.fullName} berperan sebagai ${_roleLabel(user.role)}.',
        UserRole.kepalaCabang =>
          'Hanya Kepala Cabang yang dapat mereview stok opname. '
              '${user.fullName} berperan sebagai ${_roleLabel(user.role)}.',
        _ =>
          'Peran ${_roleLabel(user.role)} tidak berwenang melakukan '
              'tindakan ini.',
      };

  static String _roleLabel(UserRole role) => switch (role) {
    UserRole.perawat => 'Perawat',
    UserRole.kepalaCabang => 'Kepala Cabang',
    UserRole.warehouse => 'Petugas Warehouse',
    UserRole.superAdmin => 'Super Admin',
  };

  /// G-R1 — the room must exist, be active, and belong to the actor's branch.
  ///
  /// This is the **creation** guard: it deliberately refuses inactive and
  /// soft-deleted rooms, because a new count must never start against master
  /// data that is out of service. Completing a document that already exists
  /// goes through [requireHistoricalRoom] instead, which is a different
  /// question with a different answer (§7.2).
  Future<MasterRoom> requireRoomInActorBranch({
    required MasterUser actor,
    required String roomId,
  }) async {
    final room = await _master.activeRoomById(roomId);
    if (room == null) {
      throw EntityNotFoundFailure(
        'Ruangan tidak ditemukan.',
        entity: 'rooms',
        id: roomId,
      );
    }
    if (!room.isActive) {
      throw InactiveEntityFailure(
        'Ruangan ${room.name} sudah dinonaktifkan.',
        entity: 'rooms',
        id: roomId,
      );
    }
    if (room.branchId != actor.branchId) {
      throw UnauthorizedRoomFailure(
        'Ruangan ${room.name} bukan bagian dari cabang Anda.',
        actorUserId: actor.id,
        roomId: roomId,
      );
    }
    return room;
  }

  /// G-R2 — the document must belong to the actor's branch.
  void requireSameBranch({
    required MasterUser actor,
    required StockOpname opname,
  }) {
    if (opname.branchId != actor.branchId) {
      throw UnauthorizedBranchFailure(
        'Dokumen ${opname.docNumber} milik cabang lain.',
        actorUserId: actor.id,
        branchId: opname.branchId,
      );
    }
  }

  /// The room's stock location for a **new** count — the place the count will
  /// be compared against.
  Future<MasterLocation> requireRoomLocation(MasterRoom room) async {
    final location = await _master.activeRoomLocation(room.id);
    if (location == null) {
      throw InvalidLocationFailure(
        'Ruangan ${room.name} belum memiliki lokasi stok, sehingga belum '
        'dapat dihitung.',
      );
    }
    return location;
  }

  // --- historical recovery (§7.2) --------------------------------------------
  //
  // Everything below serves documents that are already `submitted`. They take
  // the opname id so a broken reference can be reported against the document
  // that is stuck, and they never check `is_active`: a branch, room, location
  // or item that was deactivated after the count is still exactly the thing
  // that was counted, and the review has to be able to finish. What they do
  // enforce is that the row is physically *there* — a reference that resolves
  // to nothing cannot be guessed at, substituted or invented (§7.3).

  /// The room a submitted document names, deactivated or archived included.
  Future<MasterRoom> requireHistoricalRoom({
    required String opnameId,
    required String roomId,
  }) async {
    final room = await _master.historicalRoomById(roomId);
    if (room == null) {
      throw HistoricalReferenceMissingFailure(
        'Dokumen tidak dapat diselesaikan karena ruangan historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'rooms',
        id: roomId,
        opnameId: opnameId,
      );
    }
    return room;
  }

  /// The stock location a submitted document counted against, archived rows
  /// included.
  ///
  /// Refusing an archived location here would be the difference between a
  /// document a branch head can still close and one that is stuck forever
  /// because somebody tidied up master data on a Friday afternoon.
  Future<MasterLocation> requireHistoricalRoomLocation({
    required String opnameId,
    required MasterRoom room,
  }) async {
    final location = await _master.historicalRoomLocation(room.id);
    if (location == null) {
      throw HistoricalReferenceMissingFailure(
        'Dokumen tidak dapat diselesaikan karena lokasi stok historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'stock_locations',
        id: room.id,
        opnameId: opnameId,
      );
    }
    return location;
  }

  /// The item a submitted line names. Deactivated items pass; missing ones do
  /// not.
  Future<MasterItem> requireHistoricalItem({
    required String opnameId,
    required String itemId,
  }) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw HistoricalReferenceMissingFailure(
        'Dokumen tidak dapat diselesaikan karena barang historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'items',
        id: itemId,
        opnameId: opnameId,
      );
    }
    return item;
  }

  /// The batch/item pairing of a line on a submitted document.
  ///
  /// The pairing rules of G-E2 hold exactly as they do for a draft — an expiry
  /// item is counted per batch, a non-expiry item never is, and the batch
  /// belongs to its item — because a line that breaks them cannot be posted to
  /// the ledger at all. Only the *existence* question is answered differently,
  /// which is the one argument [_requireItemBatch] takes: on a draft a missing
  /// batch is a validation error the nurse can fix, on a submitted document it
  /// is a broken reference nobody can edit their way out of.
  ///
  /// Takes the line rather than a [MasterItem] because the line already carries
  /// everything the rule needs. `StockOpnameLine` is built from a query that
  /// inner-joins `items`, so its `sku` and `hasExpiry` *are* the item row,
  /// already loaded — re-fetching it would be one `items` SELECT per line
  /// inside the review transaction to learn what the caller was handed.
  Future<MasterBatch?> requireHistoricalLineBatch({
    required String opnameId,
    required StockOpnameLine line,
  }) {
    return _requireItemBatch(
      itemId: line.itemId,
      sku: line.sku,
      hasExpiry: line.hasExpiry,
      batchId: line.batchId,
      onMissingBatch: (batchId) => HistoricalReferenceMissingFailure(
        'Dokumen tidak dapat diselesaikan karena batch historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'item_batches',
        id: batchId,
        opnameId: opnameId,
      ),
    );
  }

  /// Refuses a document whose stored lines and loaded lines disagree.
  ///
  /// [StockOpnameDetail] is built from a query that inner-joins `items`, so a
  /// line whose item row is physically gone is absent from it rather than
  /// reported. Posting or submitting on that basis would treat the document as
  /// complete while one counted position was never seen — no note demanded of
  /// it at submit, no adjustment posted for it at review.
  ///
  /// [storedItemIds] comes from a plain select that no join can filter. The
  /// comparison is a set difference in memory, so the healthy case — every
  /// line loaded — costs no query at all; only a genuine gap is worth a
  /// lookup, and then only to name the row an administrator has to repair.
  Future<void> requireEveryLineLoaded({
    required String opnameId,
    required List<String> storedItemIds,
    required Iterable<String> loadedItemIds,
  }) async {
    final missing = storedItemIds.toSet().difference(loadedItemIds.toSet());
    if (missing.isEmpty) return;

    // The overwhelmingly likely cause, and the one worth a precise message.
    for (final itemId in missing) {
      await requireHistoricalItem(opnameId: opnameId, itemId: itemId);
    }

    // Every id still resolves, so the join dropped the line for a reason this
    // code cannot name. Refusing is still right: a document that does not
    // agree with itself must not be posted on the strength of the half we can
    // see.
    throw HistoricalReferenceMissingFailure(
      'Dokumen tidak dapat diselesaikan karena sebagian baris historis tidak '
      'dapat dimuat. Hubungi administrator.',
      entity: 'stock_opname_lines',
      id: missing.first,
      opnameId: opnameId,
    );
  }

  /// G-S1/G-S2 — the document must currently be in [expected].
  void requireStatus({
    required StockOpname opname,
    required StockOpnameStatus expected,
    StockOpnameStatus? attempted,
  }) {
    if (opname.status == expected) return;
    throw InvalidStockOpnameStateFailure(
      _stateMessage(opname, expected),
      opnameId: opname.id,
      currentStatus: opname.status,
      attemptedStatus: attempted,
    );
  }

  String _stateMessage(StockOpname opname, StockOpnameStatus expected) {
    return switch (opname.status) {
      StockOpnameStatus.draft when expected == StockOpnameStatus.submitted =>
        'Dokumen ${opname.docNumber} masih draft dan belum dikirim.',
      StockOpnameStatus.submitted =>
        'Dokumen ${opname.docNumber} sudah dikirim dan menunggu review '
            'Kepala Cabang, sehingga tidak dapat diubah lagi.',
      StockOpnameStatus.reviewed =>
        'Dokumen ${opname.docNumber} sudah direview dan bersifat final. '
            'Koreksi hanya bisa dilakukan lewat dokumen penyesuaian baru.',
      _ =>
        'Dokumen ${opname.docNumber} berstatus ${opname.status.label} dan '
            'tidak dapat diproses.',
    };
  }

  /// Turns "the guarded write matched no rows" into the right failure. Reached
  /// when another device changed the document between the read and the write.
  Never concurrentUpdate(StockOpname opname) {
    throw ConcurrentStockOpnameUpdateFailure(
      'Dokumen ${opname.docNumber} baru saja diubah dari perangkat lain. '
      'Muat ulang halaman lalu coba lagi.',
      opnameId: opname.id,
    );
  }

  /// Validates the item/batch pairing of a line (G-E2).
  ///
  /// Expiry-tracked items are always counted per batch and non-expiry items
  /// never carry one; the batch must belong to the item. Expired batches are
  /// deliberately allowed — a physical count has to be able to report expired
  /// stock that is still on the shelf (G-E7).
  Future<MasterBatch?> requireValidItemBatch({
    required MasterItem item,
    required String? batchId,
  }) {
    return _requireItemBatch(
      itemId: item.id,
      sku: item.sku,
      hasExpiry: item.hasExpiry,
      batchId: batchId,
      onMissingBatch: (batchId) => EntityNotFoundFailure(
        'Batch tidak ditemukan.',
        entity: 'item_batches',
        id: batchId,
      ),
    );
  }

  /// The G-E2 pairing rule itself, stated once.
  ///
  /// The rule does not change between a draft and a submitted document, and
  /// writing it out twice is how the two copies eventually stop agreeing. What
  /// genuinely differs is only [onMissingBatch]: the same missing row is a
  /// fixable validation error on a draft and a broken historic reference on a
  /// document nobody can edit.
  ///
  /// Takes the three item fields rather than a [MasterItem] so a caller that
  /// already holds them — every opname line does, through the join — does not
  /// have to re-read the row to satisfy a signature.
  Future<MasterBatch?> _requireItemBatch({
    required String itemId,
    required String sku,
    required bool hasExpiry,
    required String? batchId,
    required AppFailure Function(String batchId) onMissingBatch,
  }) async {
    if (hasExpiry && batchId == null) {
      throw BatchRequiredFailure(
        'Barang $sku dilacak per batch, sehingga wajib dihitung per batch.',
        itemId: itemId,
      );
    }
    if (!hasExpiry && batchId != null) {
      throw BatchNotAllowedFailure(
        'Barang $sku tidak memiliki tanggal kedaluwarsa, sehingga tidak boleh '
        'dihitung per batch.',
        itemId: itemId,
      );
    }
    if (batchId == null) return null;

    final batch = await _master.batchById(batchId);
    if (batch == null) throw onMissingBatch(batchId);
    if (batch.itemId != itemId) {
      throw ValidationFailure(
        'Batch ${batch.batchNo} bukan milik barang $sku.',
      );
    }
    return batch;
  }

  Future<MasterItem> requireItem(String itemId) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw EntityNotFoundFailure(
        'Barang tidak ditemukan.',
        entity: 'items',
        id: itemId,
      );
    }
    return item;
  }

  /// Only active items may be *added* to a draft. Items already snapshotted
  /// stay countable even if they were deactivated afterwards, so the sheet
  /// still reflects what is physically in the room.
  Future<MasterItem> requireActiveItem(String itemId) async {
    final item = await requireItem(itemId);
    if (!item.isActive) {
      throw InactiveEntityFailure(
        'Barang ${item.name} sudah dinonaktifkan dan tidak dapat ditambahkan.',
        entity: 'items',
        id: itemId,
      );
    }
    return item;
  }
}
