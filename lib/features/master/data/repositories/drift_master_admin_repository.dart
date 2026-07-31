import 'package:drift/drift.dart' show SimpleSelectStatement, Value;

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/master_admin_dao.dart';
import '../../../../core/db/tables/base_columns.dart' show newUuidV4;
import '../../../../core/enums/app_enums.dart';
import '../../domain/models/import_models.dart';
import '../../domain/models/master_admin_models.dart';
import '../../domain/models/master_models.dart';
import '../../domain/repositories/master_admin_repository.dart';
import '../../domain/services/master_import_normalization_policy.dart';

/// Drift implementation of [MasterAdminRepository] (§24).
///
/// Mapping only, plus the list assembly the admin screens need. Not one business
/// rule lives here: the historical policy, the role policy and the access policy
/// are the use cases' to apply, and a repository that also decided them would be
/// a second place to keep them in step.
class DriftMasterAdminRepository implements MasterAdminRepository {
  /// Both sources of non-determinism are injectable, so a test can pin the ids a
  /// commit writes and the instant it stamps ten thousand rows with.
  DriftMasterAdminRepository(
    this._dao, {
    DateTime Function()? clock,
    this.idGenerator,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final MasterAdminDao _dao;
  final DateTime Function() _clock;

  /// `null` in production, where every id is a fresh UUID v4.
  final String Function()? idGenerator;

  DateTime get _now => _clock().toUtc();

  String _newId() => idGenerator?.call() ?? newUuidV4();

  // --- mapping ---------------------------------------------------------------

  static MasterBranch _toBranch(Branch row) => MasterBranch(
    id: row.id,
    code: row.code,
    name: row.name,
    address: row.address,
    isActive: row.isActive,
    isArchived: row.deletedAt != null,
  );

  static MasterRoom _toRoom(Room row) => MasterRoom(
    id: row.id,
    branchId: row.branchId,
    code: row.code,
    name: row.name,
    isActive: row.isActive,
    isArchived: row.deletedAt != null,
  );

  static MasterUser _toUser(AppUser row) => MasterUser(
    id: row.id,
    fullName: row.fullName,
    email: row.email,
    role: row.role,
    branchId: row.branchId,
    isActive: row.isActive,
  );

  static MasterCategory _toCategory(ItemCategory row) =>
      MasterCategory(id: row.id, name: row.name);

  static MasterItem _toItem(Item row) => MasterItem(
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

  static MasterBatch _toBatch(ItemBatch row) => MasterBatch(
    id: row.id,
    itemId: row.itemId,
    batchNo: row.batchNo,
    expiryDate: row.expiryDate,
  );

  static MasterHistoricalUsage _itemUsage(ItemUsageCounts counts) =>
      MasterHistoricalUsage(
        movements: counts.movements,
        balances: counts.balances,
        opnameLines: counts.opnameLines,
        purchaseRequestLines: counts.purchaseRequestLines,
        deliveryOrderLines: counts.deliveryOrderLines,
        goodReceiptLines: counts.goodReceiptLines,
        distributionLines: counts.distributionLines,
        disposalLines: counts.disposalLines,
        consumptionLines: counts.consumptionLines,
        goodsReturnLines: counts.goodsReturnLines,
        batches: counts.batches,
      );

  static MasterHistoricalUsage _batchUsage(BatchUsageCounts counts) =>
      MasterHistoricalUsage(
        movements: counts.movements,
        balances: counts.balances,
        opnameLines: counts.opnameLines,
        deliveryOrderLines: counts.deliveryOrderLines,
        goodReceiptLines: counts.goodReceiptLines,
        distributionLines: counts.distributionLines,
        disposalLines: counts.disposalLines,
        consumptionLines: counts.consumptionLines,
        goodsReturnLines: counts.goodsReturnLines,
      );

  static ImportLog _toImportLog(ImportLogRow row) => ImportLog(
    id: row.id,
    entity: row.entity,
    fileName: row.fileName,
    totalRows: row.totalRows,
    insertedRows: row.insertedRows,
    updatedRows: row.updatedRows,
    failedRows: row.failedRows,
    errorDetail: row.errorDetail,
    status: row.status,
    importedBy: row.importedBy,
    templateVersion: row.templateVersion,
    fileSha256: row.fileSha256,
    fileSizeBytes: row.fileSizeBytes,
    createdAtUtc: row.createdAt,
    updatedAtUtc: row.updatedAt,
    syncStatus: row.syncStatus,
  );

  // --- dashboard --------------------------------------------------------------

  @override
  Future<MasterAdminDashboard> dashboard() async {
    final summaries = <MasterEntitySummary>[];
    for (final entity in const [
      MasterEntityType.items,
      MasterEntityType.itemCategories,
      MasterEntityType.branches,
      MasterEntityType.rooms,
      MasterEntityType.users,
      MasterEntityType.itemBatches,
    ]) {
      summaries.add(await summaryFor(entity));
    }
    return MasterAdminDashboard(summaries: summaries);
  }

  @override
  Future<MasterEntitySummary> summaryFor(MasterEntityType entity) async {
    final table = _dao.attachedDatabase;
    final counts = switch (entity) {
      MasterEntityType.branches => await _dao.lifecycleCounts(
        table: table.branches,
        deletedAt: table.branches.deletedAt,
        updatedAt: table.branches.updatedAt,
        isActive: table.branches.isActive,
      ),
      MasterEntityType.rooms => await _dao.lifecycleCounts(
        table: table.rooms,
        deletedAt: table.rooms.deletedAt,
        updatedAt: table.rooms.updatedAt,
        isActive: table.rooms.isActive,
      ),
      MasterEntityType.users => await _dao.lifecycleCounts(
        table: table.users,
        deletedAt: table.users.deletedAt,
        updatedAt: table.users.updatedAt,
        isActive: table.users.isActive,
      ),
      // Categories and batches carry no `is_active`, so `deleted_at` alone is
      // their lifecycle (§3.6). Passing `isActive: null` is what says so.
      MasterEntityType.itemCategories => await _dao.lifecycleCounts(
        table: table.itemCategories,
        deletedAt: table.itemCategories.deletedAt,
        updatedAt: table.itemCategories.updatedAt,
      ),
      MasterEntityType.items => await _dao.lifecycleCounts(
        table: table.items,
        deletedAt: table.items.deletedAt,
        updatedAt: table.items.updatedAt,
        isActive: table.items.isActive,
      ),
      MasterEntityType.itemBatches => await _dao.lifecycleCounts(
        table: table.itemBatches,
        deletedAt: table.itemBatches.deletedAt,
        updatedAt: table.itemBatches.updatedAt,
      ),
    };
    return MasterEntitySummary(
      entity: entity,
      activeCount: counts.active,
      inactiveCount: counts.inactive,
      lastUpdatedAtUtc: counts.lastUpdated,
    );
  }

  // --- lists ------------------------------------------------------------------
  //
  // Filtering happens in Dart over the full table rather than in SQL, and that is
  // a deliberate trade for this milestone's scale: the six master tables are
  // thousands of rows at most, every list additionally needs per-row counts that
  // come from grouped queries anyway, and doing it here keeps one search
  // definition rather than one per entity in SQL and another in the UI. The
  // grouped counts are the part that would actually be slow, and those *are* one
  // query each (§58).

  bool _matches(String query, Iterable<String?> haystack) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    for (final value in haystack) {
      if (value != null && value.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  @override
  Future<List<MasterBranchAdminView>> listBranches(
    MasterListFilter filter,
  ) async {
    final rows = await _dao.allBranches();
    final roomCounts = await _dao.roomCountsByBranch();
    final userCounts = await _dao.activeUserCountsByBranch();
    final views = <MasterBranchAdminView>[];
    for (final row in rows) {
      final isLive = row.deletedAt == null && row.isActive;
      if (!filter.includeInactive && !isLive) continue;
      if (!_matches(filter.query, [row.code, row.name, row.address])) continue;
      views.add(
        MasterBranchAdminView(
          branch: _toBranch(row),
          roomCount: roomCounts[row.id] ?? 0,
          activeUserCount: userCounts[row.id] ?? 0,
          syncStatus: row.syncStatus,
          usage: MasterHistoricalUsage(
            rooms: roomCounts[row.id] ?? 0,
            users: userCounts[row.id] ?? 0,
          ),
          updatedAtUtc: row.updatedAt,
        ),
      );
    }
    return views;
  }

  @override
  Future<List<MasterRoomAdminView>> listRooms(MasterListFilter filter) async {
    final rows = await _dao.allRooms();
    final branches = {for (final b in await _dao.allBranches()) b.id: b};
    final locations = await _dao.allLocations();
    final locationByRoom = <String, String>{
      for (final location in locations)
        if (location.roomId != null && location.deletedAt == null)
          location.roomId!: location.name,
    };

    final views = <MasterRoomAdminView>[];
    for (final row in rows) {
      final isLive = row.deletedAt == null && row.isActive;
      if (!filter.includeInactive && !isLive) continue;
      if (filter.branchId != null && row.branchId != filter.branchId) continue;
      final branch = branches[row.branchId];
      if (!_matches(filter.query, [
        row.code,
        row.name,
        branch?.code,
        branch?.name,
      ])) {
        continue;
      }
      views.add(
        MasterRoomAdminView(
          room: _toRoom(row),
          branchCode: branch?.code ?? '-',
          branchName: branch?.name ?? '-',
          stockLocationName: locationByRoom[row.id],
          syncStatus: row.syncStatus,
          usage: MasterHistoricalUsage(
            stockLocations: locationByRoom.containsKey(row.id) ? 1 : 0,
          ),
          updatedAtUtc: row.updatedAt,
        ),
      );
    }
    return views;
  }

  @override
  Future<List<MasterUserAdminView>> listUsers(
    MasterListFilter filter, {
    String? actorId,
  }) async {
    final rows = await _dao.allUsers();
    final branches = {for (final b in await _dao.allBranches()) b.id: b};

    final views = <MasterUserAdminView>[];
    for (final row in rows) {
      final isLive = row.deletedAt == null && row.isActive;
      if (!filter.includeInactive && !isLive) continue;
      if (filter.role != null && row.role != filter.role) continue;
      if (filter.branchId != null && row.branchId != filter.branchId) continue;
      final branch = row.branchId == null ? null : branches[row.branchId];
      if (!_matches(filter.query, [
        row.fullName,
        row.email,
        branch?.code,
        branch?.name,
      ])) {
        continue;
      }
      views.add(
        MasterUserAdminView(
          user: _toUser(row),
          branchCode: branch?.code,
          branchName: branch?.name,
          isSelf: actorId != null && actorId == row.id,
          syncStatus: row.syncStatus,
          usage: MasterHistoricalUsage(
            movements: await _dao.documentLinesForUser(row.id),
          ),
          updatedAtUtc: row.updatedAt,
        ),
      );
    }
    return views;
  }

  @override
  Future<List<MasterCategoryAdminView>> listCategories(
    MasterListFilter filter,
  ) async {
    final rows = await _dao.allCategories();
    final itemCounts = await _dao.itemCountsByCategory();

    final views = <MasterCategoryAdminView>[];
    for (final row in rows) {
      final isArchived = row.deletedAt != null;
      if (!filter.includeInactive && isArchived) continue;
      if (!_matches(filter.query, [row.name])) continue;
      views.add(
        MasterCategoryAdminView(
          category: _toCategory(row),
          isArchived: isArchived,
          itemCount: itemCounts[row.id] ?? 0,
          syncStatus: row.syncStatus,
          usage: MasterHistoricalUsage(items: itemCounts[row.id] ?? 0),
          updatedAtUtc: row.updatedAt,
        ),
      );
    }
    return views;
  }

  @override
  Future<List<MasterItemAdminView>> listItems(MasterListFilter filter) async {
    final rows = await _dao.allItems();
    final categories = {for (final c in await _dao.allCategories()) c.id: c};
    final usage = await _dao.itemUsageCountsBulk();
    final batchCounts = await _dao.batchCountsByItem();

    final views = <MasterItemAdminView>[];
    for (final row in rows) {
      final isLive = row.deletedAt == null && row.isActive;
      if (!filter.includeInactive && !isLive) continue;
      if (filter.categoryId != null && row.categoryId != filter.categoryId) {
        continue;
      }
      if (filter.hasExpiry != null && row.hasExpiry != filter.hasExpiry) {
        continue;
      }
      final category = categories[row.categoryId];
      if (!_matches(filter.query, [row.sku, row.name, category?.name])) {
        continue;
      }
      views.add(
        MasterItemAdminView(
          item: _toItem(row),
          categoryName: category?.name ?? '-',
          batchCount: batchCounts[row.id] ?? 0,
          syncStatus: row.syncStatus,
          usage: usage[row.id] == null
              ? const MasterHistoricalUsage.none()
              : _itemUsage(usage[row.id]!),
          updatedAtUtc: row.updatedAt,
          isArchived: row.deletedAt != null,
        ),
      );
    }
    return views;
  }

  @override
  Future<List<MasterBatchAdminView>> listBatches(
    MasterListFilter filter,
  ) async {
    final rows = await _dao.allBatches();
    final items = {for (final i in await _dao.allItems()) i.id: i};
    final usage = await _dao.batchUsageCountsBulk();

    final views = <MasterBatchAdminView>[];
    for (final row in rows) {
      final isArchived = row.deletedAt != null;
      if (!filter.includeInactive && isArchived) continue;
      final item = items[row.itemId];
      if (filter.categoryId != null && item?.categoryId != filter.categoryId) {
        continue;
      }
      if (!_matches(filter.query, [row.batchNo, item?.sku, item?.name])) {
        continue;
      }
      views.add(
        MasterBatchAdminView(
          batch: _toBatch(row),
          itemSku: item?.sku ?? '-',
          itemName: item?.name ?? '-',
          isArchived: isArchived,
          syncStatus: row.syncStatus,
          usage: usage[row.id] == null
              ? const MasterHistoricalUsage.none()
              : _batchUsage(usage[row.id]!),
          updatedAtUtc: row.updatedAt,
        ),
      );
    }
    return views;
  }

  // --- single rows -------------------------------------------------------------

  @override
  Future<MasterBranch?> branchById(String id) async {
    final row = await _dao.branchById(id);
    return row == null ? null : _toBranch(row);
  }

  @override
  Future<MasterRoom?> roomById(String id) async {
    final row = await _dao.roomById(id);
    return row == null ? null : _toRoom(row);
  }

  @override
  Future<MasterUser?> adminUserById(String id) async {
    final row = await _dao.userById(id);
    return row == null ? null : _toUser(row);
  }

  @override
  Future<MasterCategory?> categoryById(String id) async {
    final row = await _dao.categoryById(id);
    return row == null ? null : _toCategory(row);
  }

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

  // --- natural-key lookup ------------------------------------------------------

  @override
  Future<List<MasterBranch>> branchesByCode(String code) async =>
      (await _dao.branchesByCode(code)).map(_toBranch).toList(growable: false);

  @override
  Future<List<MasterRoom>> roomsByBranchAndCode({
    required String branchId,
    required String code,
  }) async => (await _dao.roomsByBranchAndCode(
    branchId: branchId,
    code: code,
  )).map(_toRoom).toList(growable: false);

  @override
  Future<List<MasterUser>> usersByEmail(String email) async =>
      (await _dao.usersByEmail(email)).map(_toUser).toList(growable: false);

  @override
  Future<List<MasterCategory>> categoriesByName(String name) async =>
      (await _dao.categoriesByName(
        name,
      )).map(_toCategory).toList(growable: false);

  @override
  Future<List<MasterItem>> itemsBySku(String sku) async =>
      (await _dao.itemsBySku(sku)).map(_toItem).toList(growable: false);

  @override
  Future<List<MasterBatch>> batchesByItemAndNumber({
    required String itemId,
    required String batchNo,
  }) async => (await _dao.batchesByItemAndNumber(
    itemId: itemId,
    batchNo: batchNo,
  )).map(_toBatch).toList(growable: false);

  /// Groups rows by a case-folded key.
  ///
  /// A `List` per key rather than a single row, deliberately: two rows sharing a
  /// case-insensitive key is the ambiguous state §17 refuses to resolve, and a map
  /// to a single value would silently drop one of them here — turning a refusal
  /// into a wrong answer.
  static Map<String, List<T>> _indexBy<T>(
    Iterable<T> rows,
    String Function(T) keyOf,
  ) {
    final index = <String, List<T>>{};
    for (final row in rows) {
      (index[MasterImportNormalizationPolicy.key(keyOf(row))] ??= <T>[]).add(
        row,
      );
    }
    return index;
  }

  @override
  Future<Map<String, List<MasterBranch>>> branchesByCodeIndex() async =>
      _indexBy(
        (await _dao.allBranches()).map(_toBranch),
        (branch) => branch.code,
      );

  @override
  Future<Map<String, List<MasterCategory>>> categoriesByNameIndex() async =>
      _indexBy(
        (await _dao.allCategories()).map(_toCategory),
        (category) => category.name,
      );

  @override
  Future<Map<String, List<MasterItem>>> itemsBySkuIndex() async =>
      _indexBy((await _dao.allItems()).map(_toItem), (item) => item.sku);

  @override
  Future<Map<String, List<MasterUser>>> usersByEmailIndex() async =>
      _indexBy((await _dao.allUsers()).map(_toUser), (user) => user.email);

  /// Rooms keyed by `branchCode code`, matching
  /// [MasterImportNormalizationPolicy.compositeKey] (§3.1).
  @override
  Future<Map<String, List<MasterRoom>>> roomsByBranchCodeIndex() async {
    final branches = {for (final b in await _dao.allBranches()) b.id: b.code};
    final index = <String, List<MasterRoom>>{};
    for (final row in await _dao.allRooms()) {
      final branchCode = branches[row.branchId];
      if (branchCode == null) continue;
      final key = MasterImportNormalizationPolicy.compositeKey([
        branchCode,
        row.code,
      ]);
      (index[key] ??= <MasterRoom>[]).add(_toRoom(row));
    }
    return index;
  }

  /// Batches keyed by `itemSku batchNo`.
  @override
  Future<Map<String, List<MasterBatch>>> batchesByItemAndNumberIndex() async {
    final items = {for (final i in await _dao.allItems()) i.id: i.sku};
    final index = <String, List<MasterBatch>>{};
    for (final row in await _dao.allBatches()) {
      final sku = items[row.itemId];
      if (sku == null) continue;
      final key = MasterImportNormalizationPolicy.compositeKey([
        sku,
        row.batchNo,
      ]);
      (index[key] ??= <MasterBatch>[]).add(_toBatch(row));
    }
    return index;
  }

  // --- historical usage ---------------------------------------------------------

  @override
  Future<MasterHistoricalUsage> usageForItem(String itemId) async =>
      _itemUsage(await _dao.itemUsageCounts(itemId));

  @override
  Future<MasterHistoricalUsage> usageForBatch(String batchId) async =>
      _batchUsage(await _dao.batchUsageCounts(batchId));

  @override
  Future<MasterHistoricalUsage> usageForRoom(String roomId) async {
    final counts = await _dao.roomUsageCounts(roomId);
    return MasterHistoricalUsage(
      movements: counts.movements,
      balances: counts.balances,
      distributionLines: counts.distributionLines,
      stockLocations: counts.stockLocations,
    );
  }

  @override
  Future<MasterHistoricalUsage> usageForBranch(String branchId) async {
    final counts = await _dao.branchUsageCounts(branchId);
    return MasterHistoricalUsage(
      rooms: counts.rooms,
      users: counts.users,
      stockLocations: counts.stockLocations,
    );
  }

  @override
  Future<MasterHistoricalUsage> usageForUser(String userId) async =>
      MasterHistoricalUsage(movements: await _dao.documentLinesForUser(userId));

  @override
  Future<MasterHistoricalUsage> usageForCategory(String categoryId) async =>
      MasterHistoricalUsage(items: await _dao.itemCountForCategory(categoryId));

  @override
  Future<Map<String, MasterHistoricalUsage>> usageForItems(
    Iterable<String> itemIds,
  ) async {
    final wanted = itemIds.toSet();
    final all = await _dao.itemUsageCountsBulk();
    return {
      for (final id in wanted)
        id: all[id] == null
            ? const MasterHistoricalUsage.none()
            : _itemUsage(all[id]!),
    };
  }

  @override
  Future<Map<String, MasterHistoricalUsage>> usageForBatches(
    Iterable<String> batchIds,
  ) async {
    final wanted = batchIds.toSet();
    final all = await _dao.batchUsageCountsBulk();
    return {
      for (final id in wanted)
        id: all[id] == null
            ? const MasterHistoricalUsage.none()
            : _batchUsage(all[id]!),
    };
  }

  @override
  Future<Map<String, int>> batchCountsForItems(Iterable<String> itemIds) async {
    final wanted = itemIds.toSet();
    final all = await _dao.batchCountsByItem();
    return {for (final id in wanted) id: all[id] ?? 0};
  }

  @override
  Future<int> countOtherActiveSuperAdmins(String excludingUserId) =>
      _dao.countOtherActiveSuperAdmins(excludingUserId);

  // --- writers ------------------------------------------------------------------

  @override
  Future<MasterBranch> insertBranch({
    required String code,
    required String name,
    String? address,
    required bool isActive,
  }) async => _toBranch(
    await _dao.insertBranch(
      id: _newId(),
      code: code,
      name: name,
      address: address,
      isActive: isActive,
      nowUtc: _now,
    ),
  );

  @override
  Future<int> updateBranch({
    required String id,
    required String name,
    String? address,
    required bool isActive,
  }) => _dao.updateBranch(
    id: id,
    name: name,
    address: address,
    isActive: isActive,
    nowUtc: _now,
  );

  @override
  Future<int> setBranchActive({required String id, required bool isActive}) =>
      _dao.setBranchActive(id: id, isActive: isActive, nowUtc: _now);

  @override
  Future<MasterRoom> insertRoom({
    required String branchId,
    required String code,
    required String name,
    required bool isActive,
  }) async => _toRoom(
    await _dao.insertRoom(
      id: _newId(),
      branchId: branchId,
      code: code,
      name: name,
      isActive: isActive,
      nowUtc: _now,
    ),
  );

  @override
  Future<int> updateRoom({
    required String id,
    required String name,
    required bool isActive,
  }) => _dao.updateRoom(id: id, name: name, isActive: isActive, nowUtc: _now);

  @override
  Future<int> setRoomActive({required String id, required bool isActive}) =>
      _dao.setRoomActive(id: id, isActive: isActive, nowUtc: _now);

  @override
  Future<MasterUser> insertUser({
    required String fullName,
    required String email,
    required UserRole role,
    String? branchId,
    required bool isActive,
  }) async => _toUser(
    await _dao.insertUser(
      id: _newId(),
      fullName: fullName,
      email: email,
      role: role,
      branchId: branchId,
      isActive: isActive,
      nowUtc: _now,
    ),
  );

  @override
  Future<int> updateUser({
    required String id,
    required String fullName,
    required UserRole role,
    String? branchId,
    required bool isActive,
  }) => _dao.updateUser(
    id: id,
    fullName: fullName,
    role: role,
    branchId: branchId,
    isActive: isActive,
    nowUtc: _now,
  );

  @override
  Future<int> setUserActive({required String id, required bool isActive}) =>
      _dao.setUserActive(id: id, isActive: isActive, nowUtc: _now);

  @override
  Future<MasterCategory> insertCategory(String name) async => _toCategory(
    await _dao.insertCategory(id: _newId(), name: name, nowUtc: _now),
  );

  @override
  Future<int> updateCategory({required String id, required String name}) =>
      _dao.updateCategory(id: id, name: name, nowUtc: _now);

  @override
  Future<int> archiveCategory(String id) =>
      _dao.archiveCategory(id: id, nowUtc: _now);

  @override
  Future<int> restoreCategory(String id) =>
      _dao.restoreCategory(id: id, nowUtc: _now);

  @override
  Future<MasterItem> insertItem({
    required String sku,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    required int expiryAlertDays,
    required bool isActive,
  }) async => _toItem(
    await _dao.insertItem(
      id: _newId(),
      sku: sku,
      name: name,
      categoryId: categoryId,
      unit: unit,
      minStockRoom: minStockRoom,
      minStockBranch: minStockBranch,
      hasExpiry: hasExpiry,
      expiryAlertDays: expiryAlertDays,
      isActive: isActive,
      nowUtc: _now,
    ),
  );

  @override
  Future<int> updateItem({
    required String id,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    required int expiryAlertDays,
    required bool isActive,
  }) => _dao.updateItem(
    id: id,
    name: name,
    categoryId: categoryId,
    unit: unit,
    minStockRoom: minStockRoom,
    minStockBranch: minStockBranch,
    hasExpiry: hasExpiry,
    expiryAlertDays: expiryAlertDays,
    isActive: isActive,
    nowUtc: _now,
  );

  @override
  Future<int> setItemActive({required String id, required bool isActive}) =>
      _dao.setItemActive(id: id, isActive: isActive, nowUtc: _now);

  @override
  Future<MasterBatch> insertBatch({
    required String itemId,
    required String batchNo,
    required DateTime expiryDate,
  }) async => _toBatch(
    await _dao.insertBatch(
      id: _newId(),
      itemId: itemId,
      batchNo: batchNo,
      expiryDate: expiryDate,
      nowUtc: _now,
    ),
  );

  @override
  Future<int> updateBatch({required String id, required DateTime expiryDate}) =>
      _dao.updateBatch(id: id, expiryDate: expiryDate, nowUtc: _now);

  @override
  Future<int> archiveBatch(String id) =>
      _dao.archiveBatch(id: id, nowUtc: _now);

  @override
  Future<int> restoreBatch(String id) =>
      _dao.restoreBatch(id: id, nowUtc: _now);

  // --- stock locations ------------------------------------------------------------

  @override
  Future<void> ensureBranchStoreLocation({
    required String branchId,
    required String branchName,
  }) => _dao.ensureBranchStoreLocation(
    id: _newId(),
    branchId: branchId,
    name: 'Gudang $branchName',
    nowUtc: _now,
  );

  @override
  Future<void> ensureRoomLocation({
    required String branchId,
    required String roomId,
    required String roomName,
  }) => _dao.ensureRoomLocation(
    id: _newId(),
    branchId: branchId,
    roomId: roomId,
    name: roomName,
    nowUtc: _now,
  );

  @override
  Future<int> renameBranchStoreLocation({
    required String branchId,
    required String branchName,
  }) => _dao.renameBranchStoreLocation(
    branchId: branchId,
    name: 'Gudang $branchName',
    nowUtc: _now,
  );

  @override
  Future<int> renameRoomLocation({
    required String roomId,
    required String roomName,
  }) => _dao.renameRoomLocation(roomId: roomId, name: roomName, nowUtc: _now);

  @override
  Future<int> branchStoreLocationCount(String branchId) async =>
      (await _dao.branchStoreLocations(branchId)).length;

  @override
  Future<int> roomLocationCount(String roomId) async =>
      (await _dao.roomLocations(roomId)).length;

  // --- import audit -----------------------------------------------------------------

  @override
  Future<ImportLog> insertValidatedImportLog({
    required String id,
    required MasterEntityType entity,
    required String fileName,
    required int totalRows,
    required int insertedRows,
    required int updatedRows,
    required int failedRows,
    String? errorDetail,
    required String importedBy,
    required String storedFilePath,
    required String fileSha256,
    required int fileSizeBytes,
    required String templateVersion,
    required DateTime nowUtc,
  }) async => _toImportLog(
    await _dao.insertImportLog(
      ImportLogsCompanion.insert(
        id: Value(id),
        entity: entity,
        fileName: fileName,
        totalRows: totalRows,
        insertedRows: insertedRows,
        updatedRows: updatedRows,
        failedRows: failedRows,
        errorDetail: Value(errorDetail),
        status: ImportStatus.validated,
        importedBy: importedBy,
        storedFilePath: storedFilePath,
        fileSha256: fileSha256,
        fileSizeBytes: fileSizeBytes,
        templateVersion: templateVersion,
        createdAt: Value(nowUtc),
        updatedAt: Value(nowUtc),
        syncStatus: const Value(SyncStatus.pending),
      ),
    ),
  );

  @override
  Future<ImportLog?> importLogById(String id) async {
    final row = await _dao.importLogById(id);
    return row == null ? null : _toImportLog(row);
  }

  @override
  Future<String?> importLogStoredPath(String id) async =>
      (await _dao.importLogById(id))?.storedFilePath;

  @override
  Future<int> transitionImportStatus({
    required String id,
    required ImportStatus from,
    required ImportStatus to,
    int? insertedRows,
    int? updatedRows,
    required DateTime nowUtc,
  }) => _dao.transitionImportStatus(
    id: id,
    from: from,
    to: to,
    insertedRows: insertedRows,
    updatedRows: updatedRows,
    nowUtc: nowUtc,
  );

  @override
  Stream<List<ImportLog>> watchImportHistory(ImportHistoryFilter filter) =>
      _historyQuery(
        filter,
      ).watch().map((rows) => rows.map(_toImportLog).toList(growable: false));

  @override
  Future<List<ImportLog>> importHistory(ImportHistoryFilter filter) async =>
      (await _historyQuery(
        filter,
      ).get()).map(_toImportLog).toList(growable: false);

  /// The typed query both history reads share.
  ///
  /// Typed rather than `dynamic`: a dynamic return would make `.watch()` produce
  /// a `Stream<List<dynamic>>` that only fails when a listener attaches, which is
  /// exactly the kind of error a provider surfaces as an unexplained empty list.
  SimpleSelectStatement<$ImportLogsTable, ImportLogRow> _historyQuery(
    ImportHistoryFilter filter,
  ) => _dao.importHistoryQuery(
    entity: filter.entity,
    status: filter.status,
    importedBy: filter.importedBy,
    fromUtc: filter.fromDateUtc,
    toUtc: filter.toDateUtc,
    fileNameQuery: filter.fileNameQuery,
    syncStatus: filter.syncStatus,
  );

  @override
  Future<ImportLogDetail?> importLogDetail(String id) async {
    final row = await _dao.importLogById(id);
    if (row == null) return null;
    final actor = await _dao.userById(row.importedBy);
    return ImportLogDetail(
      log: _toImportLog(row),
      importedByName: actor?.fullName ?? 'Pengguna tidak dikenal',
      importedByEmail: actor?.email ?? '-',
    );
  }

  // --- transaction ---------------------------------------------------------------------

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      _dao.runInTransaction(action);
}
