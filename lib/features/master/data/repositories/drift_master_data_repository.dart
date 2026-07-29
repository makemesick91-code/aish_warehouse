import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/master_data_dao.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/date_only.dart';
import '../../domain/models/master_models.dart';
import '../../domain/repositories/master_data_repository.dart';

class DriftMasterDataRepository implements MasterDataRepository {
  DriftMasterDataRepository(this._dao);

  final MasterDataDao _dao;

  @override
  Future<MasterBranch> ensureBranch({
    required String code,
    required String name,
    String? address,
  }) async {
    _requireText(code, 'Kode cabang');
    _requireText(name, 'Nama cabang');
    return _toBranch(
      await _dao.ensureBranch(code: code, name: name, address: address),
    );
  }

  @override
  Future<MasterRoom> ensureRoom({
    required String branchId,
    required String code,
    required String name,
  }) async {
    _requireText(code, 'Kode ruangan');
    _requireText(name, 'Nama ruangan');
    return _toRoom(
      await _dao.ensureRoom(branchId: branchId, code: code, name: name),
    );
  }

  @override
  Future<MasterUser> ensureUser({
    required String email,
    required String fullName,
    required UserRole role,
    String? branchId,
  }) async {
    _requireText(email, 'Email');
    _requireText(fullName, 'Nama lengkap');
    // Cross-column rule from the specification: perawat and kepala cabang are
    // always scoped to a branch, warehouse and super admin never are.
    if (role.requiresBranch && branchId == null) {
      throw ValidationFailure(
        'Peran ${role.dbValue} wajib memiliki cabang (branch_id).',
      );
    }
    if (!role.requiresBranch && branchId != null) {
      throw ValidationFailure(
        'Peran ${role.dbValue} tidak boleh terikat pada cabang.',
      );
    }

    return _toUser(
      await _dao.ensureUser(
        email: email,
        fullName: fullName,
        role: role,
        branchId: branchId,
      ),
    );
  }

  @override
  Future<MasterCategory> ensureCategory(String name) async {
    _requireText(name, 'Nama kategori');
    return _toCategory(await _dao.ensureCategory(name));
  }

  @override
  Future<MasterItem> ensureItem({
    required String sku,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    int expiryAlertDays = 30,
  }) async {
    _requireText(sku, 'SKU');
    _requireText(name, 'Nama barang');
    _requireText(unit, 'Satuan');
    if (minStockRoom < 0 || minStockBranch < 0) {
      throw const ValidationFailure('Stok minimum tidak boleh negatif.');
    }
    if (expiryAlertDays < 0) {
      throw const ValidationFailure(
        'Ambang peringatan kedaluwarsa tidak boleh negatif.',
      );
    }

    return _toItem(
      await _dao.ensureItem(
        sku: sku,
        name: name,
        categoryId: categoryId,
        unit: unit,
        minStockRoom: minStockRoom,
        minStockBranch: minStockBranch,
        hasExpiry: hasExpiry,
        expiryAlertDays: expiryAlertDays,
      ),
    );
  }

  @override
  Future<MasterBatch> ensureBatch({
    required String itemId,
    required String batchNo,
    required DateTime expiryDate,
  }) async {
    _requireText(batchNo, 'Nomor batch');

    final item = await _dao.itemById(itemId);
    if (item == null) {
      throw EntityNotFoundFailure(
        'Barang tidak ditemukan.',
        entity: 'items',
        id: itemId,
      );
    }
    // Only expiry-tracked items may own batches.
    if (!item.hasExpiry) {
      throw BatchNotAllowedFailure(
        'Barang ${item.sku} tidak memiliki tanggal kedaluwarsa, '
        'sehingga tidak boleh memiliki batch.',
        itemId: itemId,
      );
    }

    return _toBatch(
      await _dao.ensureBatch(
        itemId: itemId,
        batchNo: batchNo,
        expiryDate: _asCivilDate(expiryDate),
      ),
    );
  }

  @override
  Future<MasterLocation> ensureLocation({
    required StockLocationType type,
    required String name,
    String? branchId,
    String? roomId,
  }) async {
    _requireText(name, 'Nama lokasi');
    switch (type) {
      case StockLocationType.warehouse:
        if (branchId != null || roomId != null) {
          throw const InvalidLocationFailure(
            'Lokasi warehouse pusat tidak boleh memiliki cabang atau ruangan.',
          );
        }
      case StockLocationType.branchStore:
        if (branchId == null || roomId != null) {
          throw const InvalidLocationFailure(
            'Lokasi gudang cabang wajib memiliki cabang dan tanpa ruangan.',
          );
        }
      case StockLocationType.room:
        if (branchId == null || roomId == null) {
          throw const InvalidLocationFailure(
            'Lokasi ruangan wajib memiliki cabang dan ruangan.',
          );
        }
    }

    return _toLocation(
      await _dao.ensureLocation(
        type: type,
        name: name,
        branchId: branchId,
        roomId: roomId,
      ),
    );
  }

  @override
  Future<List<MasterBranch>> activeBranches() async =>
      (await _dao.activeBranches()).map(_toBranch).toList(growable: false);

  @override
  Future<List<MasterRoom>> activeRooms({String? branchId}) async =>
      (await _dao.activeRooms(
        branchId: branchId,
      )).map(_toRoom).toList(growable: false);

  @override
  Future<List<MasterCategory>> categories() async =>
      (await _dao.categories()).map(_toCategory).toList(growable: false);

  @override
  Future<List<MasterItem>> activeItems() async =>
      (await _dao.activeItems()).map(_toItem).toList(growable: false);

  @override
  Future<List<MasterLocation>> stockLocations() async =>
      (await _dao.allStockLocations()).map(_toLocation).toList(growable: false);

  @override
  Future<List<MasterUser>> activeUsers() async =>
      (await _dao.activeUsers()).map(_toUser).toList(growable: false);

  @override
  Future<List<MasterItem>> searchItems(
    String query, {
    String? categoryId,
    int limit = 8,
  }) async => (await _dao.searchItems(
    query,
    categoryId: categoryId,
    limit: limit,
  )).map(_toItem).toList(growable: false);

  @override
  Future<MasterItem?> itemById(String id) async {
    final row = await _dao.itemById(id);
    return row == null ? null : _toItem(row);
  }

  @override
  Future<MasterBatch?> batchById(String id) async {
    final row = await _dao.batchById(id);
    return row == null ? null : _toBatch(row);
  }

  @override
  Future<List<MasterBatch>> batchesOfItem(String itemId) async =>
      (await _dao.batchesOfItem(itemId)).map(_toBatch).toList(growable: false);

  @override
  Future<MasterLocation?> locationById(String id) async {
    final row = await _dao.locationById(id);
    return row == null ? null : _toLocation(row);
  }

  @override
  Future<MasterLocation?> roomLocation(String roomId) async {
    final row = await _dao.locationForRoom(roomId);
    return row == null ? null : _toLocation(row);
  }

  @override
  Future<MasterRoom?> roomById(String id) async {
    final row = await _dao.roomById(id);
    return row == null ? null : _toRoom(row);
  }

  @override
  Future<MasterUser?> userById(String id) async {
    final row = await _dao.userById(id);
    return row == null ? null : _toUser(row);
  }

  @override
  Future<MasterLocation?> warehouseLocation() async {
    final row = await _dao.warehouseLocation();
    return row == null ? null : _toLocation(row);
  }

  @override
  Future<MasterSummary> summary() async {
    final counts = await _dao.counts();
    return MasterSummary(
      branches: counts.branches,
      rooms: counts.rooms,
      categories: counts.categories,
      items: counts.items,
      locations: counts.locations,
      users: counts.users,
    );
  }

  void _requireText(String value, String label) {
    if (value.trim().isEmpty) {
      throw ValidationFailure('$label tidak boleh kosong.');
    }
  }
}

/// `expiry_date` is a civil date, not an instant: its calendar fields are kept
/// verbatim (T-8/T-9). Converting through `toUtc()` here would move a date
/// entered on a GMT+8 device back to the previous day.
DateTime _asCivilDate(DateTime value) => DateOnly.from(value);

MasterBranch _toBranch(Branch row) => MasterBranch(
  id: row.id,
  code: row.code,
  name: row.name,
  address: row.address,
  isActive: row.isActive,
);

MasterRoom _toRoom(Room row) => MasterRoom(
  id: row.id,
  branchId: row.branchId,
  code: row.code,
  name: row.name,
  isActive: row.isActive,
);

MasterUser _toUser(AppUser row) => MasterUser(
  id: row.id,
  fullName: row.fullName,
  email: row.email,
  role: row.role,
  branchId: row.branchId,
  isActive: row.isActive,
);

MasterCategory _toCategory(ItemCategory row) =>
    MasterCategory(id: row.id, name: row.name);

MasterItem _toItem(Item row) => MasterItem(
  id: row.id,
  sku: row.sku,
  name: row.name,
  categoryId: row.categoryId,
  unit: row.unit,
  minStockRoom: row.minStockRoom,
  minStockBranch: row.minStockBranch,
  hasExpiry: row.hasExpiry,
  expiryAlertDays: row.expiryAlertDays,
  isActive: row.isActive,
);

MasterBatch _toBatch(ItemBatch row) => MasterBatch(
  id: row.id,
  itemId: row.itemId,
  batchNo: row.batchNo,
  expiryDate: _asCivilDate(row.expiryDate),
);

MasterLocation _toLocation(StockLocation row) => MasterLocation(
  id: row.id,
  type: row.type,
  branchId: row.branchId,
  roomId: row.roomId,
  name: row.name,
);
