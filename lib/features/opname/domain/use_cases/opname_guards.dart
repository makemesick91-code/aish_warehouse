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
  Future<MasterRoom> requireRoomInActorBranch({
    required MasterUser actor,
    required String roomId,
  }) async {
    final room = await _master.roomById(roomId);
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

  /// The room's stock location — the place a count is compared against.
  Future<MasterLocation> requireRoomLocation(MasterRoom room) async {
    final location = await _master.roomLocation(room.id);
    if (location == null) {
      throw InvalidLocationFailure(
        'Ruangan ${room.name} belum memiliki lokasi stok, sehingga belum '
        'dapat dihitung.',
      );
    }
    return location;
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
  }) async {
    if (item.hasExpiry && batchId == null) {
      throw BatchRequiredFailure(
        'Barang ${item.sku} dilacak per batch, sehingga wajib dihitung '
        'per batch.',
        itemId: item.id,
      );
    }
    if (!item.hasExpiry && batchId != null) {
      throw BatchNotAllowedFailure(
        'Barang ${item.sku} tidak memiliki tanggal kedaluwarsa, sehingga '
        'tidak boleh dihitung per batch.',
        itemId: item.id,
      );
    }
    if (batchId == null) return null;

    final batch = await _master.batchById(batchId);
    if (batch == null) {
      throw EntityNotFoundFailure(
        'Batch tidak ditemukan.',
        entity: 'item_batches',
        id: batchId,
      );
    }
    if (batch.itemId != item.id) {
      throw ValidationFailure(
        'Batch ${batch.batchNo} bukan milik barang ${item.sku}.',
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
