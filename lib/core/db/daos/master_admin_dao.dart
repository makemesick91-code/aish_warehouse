import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/consumption_tables.dart';
import '../tables/delivery_tables.dart';
import '../tables/disposal_tables.dart';
import '../tables/distribution_tables.dart';
import '../tables/good_receipt_tables.dart';
import '../tables/goods_return_tables.dart';
import '../tables/import_tables.dart';
import '../tables/inventory_tables.dart';
import '../tables/master_tables.dart';
import '../tables/opname_tables.dart';
import '../tables/purchase_request_tables.dart';

part 'master_admin_dao.g.dart';

/// The unrestricted master-administration accessor (§24).
///
/// ### What this DAO may do that [MasterDataDao] may not
///
/// Read archived rows, count historical references across ten tables, write
/// typed updates, and move an `import_logs` row from `validated` to its end
/// state. Every one of those is Super Admin-only, and keeping them out of the
/// operational DAO is what stops the sixteen existing features from being one
/// method call away from an unrestricted read.
///
/// ### What this DAO deliberately does not offer (§24)
///
/// * No `delete`, of anything — soft or hard.
/// * No generic `update(table, Map<String, dynamic>)`. Every writer names its
///   columns, so a caller cannot assemble an update the policies never inspected.
/// * No `stock_balances` or `stock_movements` writer. An import creates no stock
///   (§30) and the ledger is append-only (G-A1); the only stock table touched
///   here is `stock_locations`, through two named methods that create exactly one
///   row each (§22).
/// * No writer that opens its own transaction. Every method below participates in
///   whatever transaction the caller opened, which is what makes §33's *"one outer
///   transaction, 10,000 rows"* true rather than aspirational — a row writer with
///   its own `transaction()` would commit a partial import behind the caller's
///   back.
/// * No `import_logs` delete, and no transition out of `committed` or
///   `discarded` — [transitionImportStatus] is guarded on the current status and
///   the two end states match nothing (§3.4).
///
/// ### Timestamps
///
/// Every writer takes an explicit `nowUtc`. The tables' `clientDefault` covers
/// inserts, but an update has to state its own `updated_at`, and taking it as a
/// parameter is what lets a test pin it and lets a commit stamp ten thousand rows
/// with one instant rather than ten thousand slightly different ones.
@DriftAccessor(
  tables: [
    Branches,
    Rooms,
    Users,
    ItemCategories,
    Items,
    ItemBatches,
    StockLocations,
    StockBalances,
    StockMovements,
    StockOpnameLines,
    PurchaseRequestLines,
    DeliveryOrderLines,
    GoodReceiptLines,
    DistributionLines,
    DisposalLines,
    ConsumptionLines,
    GoodsReturnLines,
    ImportLogs,
  ],
)
class MasterAdminDao extends DatabaseAccessor<AppDatabase>
    with _$MasterAdminDaoMixin {
  MasterAdminDao(super.db);

  // --- reads: single rows, archived included ---------------------------------
  //
  // `deleted_at` is deliberately not filtered. An administration screen that
  // could not open an archived row could not restore one, and §3.6 makes
  // `deleted_at` the *only* lifecycle signal categories and batches have.

  Future<Branch?> branchById(String id) =>
      (select(branches)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Room?> roomById(String id) =>
      (select(rooms)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<AppUser?> userById(String id) =>
      (select(users)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ItemCategory?> categoryById(String id) =>
      (select(itemCategories)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Item?> itemById(String id) =>
      (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ItemBatch?> batchById(String id) =>
      (select(itemBatches)..where((t) => t.id.equals(id))).getSingleOrNull();

  // --- reads: whole tables ----------------------------------------------------
  //
  // The lists an administration screen filters in Dart and the indexes an import
  // resolves foreign keys against. Both want *everything*, archived included, and
  // both want it in one query rather than one per row (§58).

  Future<List<Branch>> allBranches() =>
      (select(branches)..orderBy([(t) => OrderingTerm.asc(t.code)])).get();

  Future<List<Room>> allRooms() =>
      (select(rooms)..orderBy([
            (t) => OrderingTerm.asc(t.branchId),
            (t) => OrderingTerm.asc(t.code),
          ]))
          .get();

  Future<List<AppUser>> allUsers() =>
      (select(users)..orderBy([(t) => OrderingTerm.asc(t.fullName)])).get();

  Future<List<ItemCategory>> allCategories() => (select(
    itemCategories,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<List<Item>> allItems() =>
      (select(items)..orderBy([(t) => OrderingTerm.asc(t.sku)])).get();

  Future<List<ItemBatch>> allBatches() =>
      (select(itemBatches)..orderBy([
            (t) => OrderingTerm.asc(t.itemId),
            (t) => OrderingTerm.asc(t.batchNo),
          ]))
          .get();

  Future<List<StockLocation>> allLocations() => select(stockLocations).get();

  // --- natural-key lookup -----------------------------------------------------
  //
  // Case-insensitive, and each returns a **list**. Two stored rows matching one
  // key case-insensitively is a state a sync payload or a hand-edited database
  // can produce, and §17 says the import must *report* it rather than pick one —
  // `getSingleOrNull` would throw a driver error instead.

  Future<List<Branch>> branchesByCode(String code) {
    final needle = code.trim().toLowerCase();
    return (select(branches)
          ..where((t) => t.code.lower().equals(needle))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<Room>> roomsByBranchAndCode({
    required String branchId,
    required String code,
  }) {
    final needle = code.trim().toLowerCase();
    return (select(rooms)
          ..where(
            (t) => t.branchId.equals(branchId) & t.code.lower().equals(needle),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<AppUser>> usersByEmail(String email) {
    final needle = email.trim().toLowerCase();
    return (select(users)
          ..where((t) => t.email.lower().equals(needle))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<ItemCategory>> categoriesByName(String name) {
    final needle = name.trim().toLowerCase();
    return (select(itemCategories)
          ..where((t) => t.name.lower().equals(needle))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<Item>> itemsBySku(String sku) {
    final needle = sku.trim().toLowerCase();
    return (select(items)
          ..where((t) => t.sku.lower().equals(needle))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<ItemBatch>> batchesByItemAndNumber({
    required String itemId,
    required String batchNo,
  }) {
    final needle = batchNo.trim().toLowerCase();
    return (select(itemBatches)
          ..where(
            (t) => t.itemId.equals(itemId) & t.batchNo.lower().equals(needle),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  // --- historical usage --------------------------------------------------------
  //
  // Ten counts per entity, each a `COUNT(*)` over one indexed column. They are
  // separate queries rather than one join because a join across ten line tables
  // multiplies rows and would have to be de-duplicated per table anyway — and
  // because the bulk forms below need per-table grouping, not a flattened total.

  Future<int> _countWhere(Expression<bool> predicate, TableInfo table) async {
    final expr = countAll();
    final row =
        await (selectOnly(table)
              ..addColumns([expr])
              ..where(predicate))
            .getSingle();
    return row.read(expr) ?? 0;
  }

  /// Rows of one line table grouped by a master column, for the bulk usage reads.
  ///
  /// One query per table for the whole import, rather than one per row: a
  /// 3,000-row item file would otherwise issue 30,000 counts (§58).
  Future<Map<String, int>> _countGrouped({
    required TableInfo table,
    required GeneratedColumn<String> groupColumn,
    Expression<bool>? extra,
  }) async {
    final expr = countAll();
    final query = selectOnly(table)
      ..addColumns([groupColumn, expr])
      ..groupBy([groupColumn]);
    if (extra != null) query.where(extra);
    final rows = await query.get();
    return {
      for (final row in rows)
        if (row.read(groupColumn) != null)
          row.read(groupColumn)!: row.read(expr) ?? 0,
    };
  }

  Future<({int movements, int balances})> _stockUsageForItem(
    String itemId,
  ) async => (
    movements: await _countWhere(
      stockMovements.itemId.equals(itemId),
      stockMovements,
    ),
    balances: await _countWhere(
      stockBalances.itemId.equals(itemId),
      stockBalances,
    ),
  );

  /// Every reference count for one item, in one record.
  Future<ItemUsageCounts> itemUsageCounts(String itemId) async {
    final stock = await _stockUsageForItem(itemId);
    return ItemUsageCounts(
      movements: stock.movements,
      balances: stock.balances,
      opnameLines: await _countWhere(
        stockOpnameLines.itemId.equals(itemId),
        stockOpnameLines,
      ),
      purchaseRequestLines: await _countWhere(
        purchaseRequestLines.itemId.equals(itemId),
        purchaseRequestLines,
      ),
      deliveryOrderLines: await _countWhere(
        deliveryOrderLines.itemId.equals(itemId),
        deliveryOrderLines,
      ),
      goodReceiptLines: await _countWhere(
        goodReceiptLines.itemId.equals(itemId),
        goodReceiptLines,
      ),
      distributionLines: await _countWhere(
        distributionLines.itemId.equals(itemId),
        distributionLines,
      ),
      disposalLines: await _countWhere(
        disposalLines.itemId.equals(itemId),
        disposalLines,
      ),
      consumptionLines: await _countWhere(
        consumptionLines.itemId.equals(itemId),
        consumptionLines,
      ),
      goodsReturnLines: await _countWhere(
        goodsReturnLines.itemId.equals(itemId),
        goodsReturnLines,
      ),
      batches: await _countWhere(
        itemBatches.itemId.equals(itemId) & itemBatches.deletedAt.isNull(),
        itemBatches,
      ),
    );
  }

  /// The same counts for many items at once, keyed by item id.
  Future<Map<String, ItemUsageCounts>> itemUsageCountsBulk() async {
    final movements = await _countGrouped(
      table: stockMovements,
      groupColumn: stockMovements.itemId,
    );
    final balances = await _countGrouped(
      table: stockBalances,
      groupColumn: stockBalances.itemId,
    );
    final opname = await _countGrouped(
      table: stockOpnameLines,
      groupColumn: stockOpnameLines.itemId,
    );
    final pr = await _countGrouped(
      table: purchaseRequestLines,
      groupColumn: purchaseRequestLines.itemId,
    );
    final orders = await _countGrouped(
      table: deliveryOrderLines,
      groupColumn: deliveryOrderLines.itemId,
    );
    final receipts = await _countGrouped(
      table: goodReceiptLines,
      groupColumn: goodReceiptLines.itemId,
    );
    final dist = await _countGrouped(
      table: distributionLines,
      groupColumn: distributionLines.itemId,
    );
    final disposal = await _countGrouped(
      table: disposalLines,
      groupColumn: disposalLines.itemId,
    );
    final consumption = await _countGrouped(
      table: consumptionLines,
      groupColumn: consumptionLines.itemId,
    );
    final returns = await _countGrouped(
      table: goodsReturnLines,
      groupColumn: goodsReturnLines.itemId,
    );
    final batchCounts = await _countGrouped(
      table: itemBatches,
      groupColumn: itemBatches.itemId,
      extra: itemBatches.deletedAt.isNull(),
    );

    final ids = <String>{
      ...movements.keys,
      ...balances.keys,
      ...opname.keys,
      ...pr.keys,
      ...orders.keys,
      ...receipts.keys,
      ...dist.keys,
      ...disposal.keys,
      ...consumption.keys,
      ...returns.keys,
      ...batchCounts.keys,
    };
    return {
      for (final id in ids)
        id: ItemUsageCounts(
          movements: movements[id] ?? 0,
          balances: balances[id] ?? 0,
          opnameLines: opname[id] ?? 0,
          purchaseRequestLines: pr[id] ?? 0,
          deliveryOrderLines: orders[id] ?? 0,
          goodReceiptLines: receipts[id] ?? 0,
          distributionLines: dist[id] ?? 0,
          disposalLines: disposal[id] ?? 0,
          consumptionLines: consumption[id] ?? 0,
          goodsReturnLines: returns[id] ?? 0,
          batches: batchCounts[id] ?? 0,
        ),
    };
  }

  Future<Map<String, int>> batchCountsByItem() => _countGrouped(
    table: itemBatches,
    groupColumn: itemBatches.itemId,
    extra: itemBatches.deletedAt.isNull(),
  );

  Future<BatchUsageCounts> batchUsageCounts(String batchId) async =>
      BatchUsageCounts(
        movements: await _countWhere(
          stockMovements.batchId.equals(batchId),
          stockMovements,
        ),
        balances: await _countWhere(
          stockBalances.batchId.equals(batchId),
          stockBalances,
        ),
        opnameLines: await _countWhere(
          stockOpnameLines.batchId.equals(batchId),
          stockOpnameLines,
        ),
        deliveryOrderLines: await _countWhere(
          deliveryOrderLines.batchId.equals(batchId),
          deliveryOrderLines,
        ),
        goodReceiptLines: await _countWhere(
          goodReceiptLines.batchId.equals(batchId),
          goodReceiptLines,
        ),
        distributionLines: await _countWhere(
          distributionLines.batchId.equals(batchId),
          distributionLines,
        ),
        disposalLines: await _countWhere(
          disposalLines.batchId.equals(batchId),
          disposalLines,
        ),
        consumptionLines: await _countWhere(
          consumptionLines.batchId.equals(batchId),
          consumptionLines,
        ),
        goodsReturnLines: await _countWhere(
          goodsReturnLines.batchId.equals(batchId),
          goodsReturnLines,
        ),
      );

  Future<Map<String, BatchUsageCounts>> batchUsageCountsBulk() async {
    final movements = await _countGrouped(
      table: stockMovements,
      groupColumn: stockMovements.batchId,
    );
    final balances = await _countGrouped(
      table: stockBalances,
      groupColumn: stockBalances.batchId,
    );
    final opname = await _countGrouped(
      table: stockOpnameLines,
      groupColumn: stockOpnameLines.batchId,
    );
    final orders = await _countGrouped(
      table: deliveryOrderLines,
      groupColumn: deliveryOrderLines.batchId,
    );
    final receipts = await _countGrouped(
      table: goodReceiptLines,
      groupColumn: goodReceiptLines.batchId,
    );
    final dist = await _countGrouped(
      table: distributionLines,
      groupColumn: distributionLines.batchId,
    );
    final disposal = await _countGrouped(
      table: disposalLines,
      groupColumn: disposalLines.batchId,
    );
    final consumption = await _countGrouped(
      table: consumptionLines,
      groupColumn: consumptionLines.batchId,
    );
    final returns = await _countGrouped(
      table: goodsReturnLines,
      groupColumn: goodsReturnLines.batchId,
    );

    final ids = <String>{
      ...movements.keys,
      ...balances.keys,
      ...opname.keys,
      ...orders.keys,
      ...receipts.keys,
      ...dist.keys,
      ...disposal.keys,
      ...consumption.keys,
      ...returns.keys,
    };
    return {
      for (final id in ids)
        id: BatchUsageCounts(
          movements: movements[id] ?? 0,
          balances: balances[id] ?? 0,
          opnameLines: opname[id] ?? 0,
          deliveryOrderLines: orders[id] ?? 0,
          goodReceiptLines: receipts[id] ?? 0,
          distributionLines: dist[id] ?? 0,
          disposalLines: disposal[id] ?? 0,
          consumptionLines: consumption[id] ?? 0,
          goodsReturnLines: returns[id] ?? 0,
        ),
    };
  }

  /// How many rows point at one room — its stock location and every document
  /// line filed against it.
  Future<RoomUsageCounts> roomUsageCounts(String roomId) async {
    final locationIds = await _locationIdsForRoom(roomId);
    return RoomUsageCounts(
      stockLocations: locationIds.length,
      movements: locationIds.isEmpty
          ? 0
          : await _countWhere(
              stockMovements.fromLocationId.isIn(locationIds) |
                  stockMovements.toLocationId.isIn(locationIds),
              stockMovements,
            ),
      balances: locationIds.isEmpty
          ? 0
          : await _countWhere(
              stockBalances.locationId.isIn(locationIds),
              stockBalances,
            ),
      distributionLines: await _countWhere(
        distributionLines.roomId.equals(roomId),
        distributionLines,
      ),
    );
  }

  Future<List<String>> _locationIdsForRoom(String roomId) async {
    final rows = await (select(
      stockLocations,
    )..where((t) => t.roomId.equals(roomId))).get();
    return rows.map((row) => row.id).toList(growable: false);
  }

  Future<BranchUsageCounts> branchUsageCounts(String branchId) async =>
      BranchUsageCounts(
        rooms: await _countWhere(
          rooms.branchId.equals(branchId) & rooms.deletedAt.isNull(),
          rooms,
        ),
        activeUsers: await _countWhere(
          users.branchId.equals(branchId) &
              users.deletedAt.isNull() &
              users.isActive.equals(true),
          users,
        ),
        users: await _countWhere(
          users.branchId.equals(branchId) & users.deletedAt.isNull(),
          users,
        ),
        stockLocations: await _countWhere(
          stockLocations.branchId.equals(branchId),
          stockLocations,
        ),
      );

  Future<int> documentLinesForUser(String userId) async => await _countWhere(
    stockMovements.actorUserId.equals(userId),
    stockMovements,
  );

  Future<int> itemCountForCategory(String categoryId) => _countWhere(
    items.categoryId.equals(categoryId) & items.deletedAt.isNull(),
    items,
  );

  Future<Map<String, int>> itemCountsByCategory() => _countGrouped(
    table: items,
    groupColumn: items.categoryId,
    extra: items.deletedAt.isNull(),
  );

  Future<Map<String, int>> roomCountsByBranch() => _countGrouped(
    table: rooms,
    groupColumn: rooms.branchId,
    extra: rooms.deletedAt.isNull(),
  );

  Future<Map<String, int>> activeUserCountsByBranch() => _countGrouped(
    table: users,
    groupColumn: users.branchId,
    extra: users.deletedAt.isNull() & users.isActive.equals(true),
  );

  /// Active, non-archived Super Admins other than [excludingUserId] (§21).
  ///
  /// Read inside the write transaction by its callers: a count taken before the
  /// transaction is a fact about a moment that has passed, and two devices
  /// demoting the last two administrators concurrently is exactly the race this
  /// serves.
  Future<int> countOtherActiveSuperAdmins(String excludingUserId) =>
      _countWhere(
        users.role.equalsValue(UserRole.superAdmin) &
            users.isActive.equals(true) &
            users.deletedAt.isNull() &
            users.id.equals(excludingUserId).not(),
        users,
      );

  // --- counts for the dashboard ------------------------------------------------

  Future<({int active, int inactive, DateTime? lastUpdated})> lifecycleCounts({
    required TableInfo table,
    required GeneratedColumn<DateTime> deletedAt,
    required GeneratedColumn<DateTime> updatedAt,
    GeneratedColumn<bool>? isActive,
  }) async {
    final liveOnly = deletedAt.isNull();
    final active = isActive == null
        ? await _countWhere(liveOnly, table)
        : await _countWhere(liveOnly & isActive.equals(true), table);
    final total = await _countWhere(const Constant(true), table);
    final maxUpdated = updatedAt.max();
    final row = await (selectOnly(table)..addColumns([maxUpdated])).getSingle();
    return (
      active: active,
      inactive: total - active,
      lastUpdated: row.read(maxUpdated),
    );
  }

  // --- writers: branches --------------------------------------------------------
  //
  // Every writer below participates in the caller's transaction and opens none of
  // its own — see the class note.

  Future<Branch> insertBranch({
    required String id,
    required String code,
    required String name,
    String? address,
    required bool isActive,
    required DateTime nowUtc,
  }) => into(branches).insertReturning(
    BranchesCompanion.insert(
      id: Value(id),
      code: code,
      name: name,
      address: Value(address),
      isActive: Value(isActive),
      createdAt: Value(nowUtc),
      updatedAt: Value(nowUtc),
      // Every master write this milestone performs is a local change awaiting the
      // server that will revalidate it (G-M7/G-Y). Nothing here ever writes
      // `synced`.
      syncStatus: Value(SyncStatus.pending),
    ),
  );

  /// `code` is deliberately absent from the parameter list, not merely unwritten.
  ///
  /// A natural key that cannot be passed is a natural key that cannot be changed
  /// by a caller who forgot the rule (§20.1). The same shape repeats on every
  /// update below.
  Future<int> updateBranch({
    required String id,
    required String name,
    String? address,
    required bool isActive,
    required DateTime nowUtc,
  }) => (update(branches)..where((t) => t.id.equals(id))).write(
    BranchesCompanion(
      name: Value(name),
      address: Value(address),
      isActive: Value(isActive),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  Future<int> setBranchActive({
    required String id,
    required bool isActive,
    required DateTime nowUtc,
  }) => (update(branches)..where((t) => t.id.equals(id))).write(
    BranchesCompanion(
      isActive: Value(isActive),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  // --- writers: rooms ------------------------------------------------------------

  Future<Room> insertRoom({
    required String id,
    required String branchId,
    required String code,
    required String name,
    required bool isActive,
    required DateTime nowUtc,
  }) => into(rooms).insertReturning(
    RoomsCompanion.insert(
      id: Value(id),
      branchId: branchId,
      code: code,
      name: name,
      isActive: Value(isActive),
      createdAt: Value(nowUtc),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  Future<int> updateRoom({
    required String id,
    required String name,
    required bool isActive,
    required DateTime nowUtc,
  }) => (update(rooms)..where((t) => t.id.equals(id))).write(
    RoomsCompanion(
      name: Value(name),
      isActive: Value(isActive),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  Future<int> setRoomActive({
    required String id,
    required bool isActive,
    required DateTime nowUtc,
  }) => (update(rooms)..where((t) => t.id.equals(id))).write(
    RoomsCompanion(
      isActive: Value(isActive),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  // --- writers: users -------------------------------------------------------------

  Future<AppUser> insertUser({
    required String id,
    required String fullName,
    required String email,
    required UserRole role,
    String? branchId,
    required bool isActive,
    required DateTime nowUtc,
  }) => into(users).insertReturning(
    UsersCompanion.insert(
      id: Value(id),
      fullName: fullName,
      email: email,
      role: role,
      branchId: Value(branchId),
      isActive: Value(isActive),
      createdAt: Value(nowUtc),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  /// No password, no credential, no reset token — this schema stores none and
  /// this build has no authentication backend to reset against (§3.5).
  Future<int> updateUser({
    required String id,
    required String fullName,
    required UserRole role,
    String? branchId,
    required bool isActive,
    required DateTime nowUtc,
  }) => (update(users)..where((t) => t.id.equals(id))).write(
    UsersCompanion(
      fullName: Value(fullName),
      role: Value(role),
      branchId: Value(branchId),
      isActive: Value(isActive),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  Future<int> setUserActive({
    required String id,
    required bool isActive,
    required DateTime nowUtc,
  }) => (update(users)..where((t) => t.id.equals(id))).write(
    UsersCompanion(
      isActive: Value(isActive),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  // --- writers: categories ---------------------------------------------------------

  Future<ItemCategory> insertCategory({
    required String id,
    required String name,
    required DateTime nowUtc,
  }) => into(itemCategories).insertReturning(
    ItemCategoriesCompanion.insert(
      id: Value(id),
      name: name,
      createdAt: Value(nowUtc),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  /// Exists for the *restore* path and for nothing else.
  ///
  /// A category's name is its natural key (G-M4), so this can only ever be called
  /// with the name the row already has — [MasterHistoricalIntegrityPolicy] refuses
  /// anything else. It is here so a restore can refresh `updated_at` and the sync
  /// status in one statement.
  Future<int> updateCategory({
    required String id,
    required String name,
    required DateTime nowUtc,
  }) => (update(itemCategories)..where((t) => t.id.equals(id))).write(
    ItemCategoriesCompanion(
      name: Value(name),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  /// `deleted_at = now` — the archive half of §3.6, and **not** a delete. Every
  /// row it hides is still readable by every historical query.
  Future<int> archiveCategory({required String id, required DateTime nowUtc}) =>
      (update(
        itemCategories,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        ItemCategoriesCompanion(
          deletedAt: Value(nowUtc),
          updatedAt: Value(nowUtc),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

  Future<int> restoreCategory({required String id, required DateTime nowUtc}) =>
      (update(
        itemCategories,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNotNull())).write(
        ItemCategoriesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(nowUtc),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

  // --- writers: items ----------------------------------------------------------------

  Future<Item> insertItem({
    required String id,
    required String sku,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    required int expiryAlertDays,
    required bool isActive,
    required DateTime nowUtc,
  }) => into(items).insertReturning(
    ItemsCompanion.insert(
      id: Value(id),
      sku: sku,
      name: name,
      categoryId: categoryId,
      unit: unit,
      minStockRoom: Value(minStockRoom),
      minStockBranch: Value(minStockBranch),
      hasExpiry: Value(hasExpiry),
      expiryAlertDays: Value(expiryAlertDays),
      isActive: Value(isActive),
      createdAt: Value(nowUtc),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

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
    required DateTime nowUtc,
  }) => (update(items)..where((t) => t.id.equals(id))).write(
    ItemsCompanion(
      name: Value(name),
      categoryId: Value(categoryId),
      unit: Value(unit),
      minStockRoom: Value(minStockRoom),
      minStockBranch: Value(minStockBranch),
      hasExpiry: Value(hasExpiry),
      expiryAlertDays: Value(expiryAlertDays),
      isActive: Value(isActive),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  Future<int> setItemActive({
    required String id,
    required bool isActive,
    required DateTime nowUtc,
  }) => (update(items)..where((t) => t.id.equals(id))).write(
    ItemsCompanion(
      isActive: Value(isActive),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  // --- writers: batches ----------------------------------------------------------------

  Future<ItemBatch> insertBatch({
    required String id,
    required String itemId,
    required String batchNo,
    required DateTime expiryDate,
    required DateTime nowUtc,
  }) => into(itemBatches).insertReturning(
    ItemBatchesCompanion.insert(
      id: Value(id),
      itemId: itemId,
      batchNo: batchNo,
      expiryDate: expiryDate,
      createdAt: Value(nowUtc),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  /// Only `expiry_date` — `item_id` and `batch_no` are the natural key (§20.3).
  Future<int> updateBatch({
    required String id,
    required DateTime expiryDate,
    required DateTime nowUtc,
  }) => (update(itemBatches)..where((t) => t.id.equals(id))).write(
    ItemBatchesCompanion(
      expiryDate: Value(expiryDate),
      updatedAt: Value(nowUtc),
      syncStatus: const Value(SyncStatus.pending),
    ),
  );

  Future<int> archiveBatch({required String id, required DateTime nowUtc}) =>
      (update(
        itemBatches,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
        ItemBatchesCompanion(
          deletedAt: Value(nowUtc),
          updatedAt: Value(nowUtc),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

  Future<int> restoreBatch({required String id, required DateTime nowUtc}) =>
      (update(
        itemBatches,
      )..where((t) => t.id.equals(id) & t.deletedAt.isNotNull())).write(
        ItemBatchesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(nowUtc),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

  // --- stock locations (§22) -------------------------------------------------------------

  /// Live `branch_store` locations of one branch. 1 is the only healthy answer.
  Future<List<StockLocation>> branchStoreLocations(String branchId) =>
      (select(stockLocations)..where(
            (t) =>
                t.type.equalsValue(StockLocationType.branchStore) &
                t.branchId.equals(branchId) &
                t.roomId.isNull() &
                t.deletedAt.isNull(),
          ))
          .get();

  Future<List<StockLocation>> roomLocations(String roomId) =>
      (select(stockLocations)..where(
            (t) =>
                t.type.equalsValue(StockLocationType.room) &
                t.roomId.equals(roomId) &
                t.deletedAt.isNull(),
          ))
          .get();

  /// Creates the branch's store **only when it has none**.
  ///
  /// Idempotent rather than unconditional, and that is the §22 invariant: a
  /// re-run — an import that updates a branch that already exists, a retried
  /// commit — must not produce a second store. Two stores make every posting
  /// ambiguous, and §14 already established that a posting may not guess.
  Future<StockLocation?> ensureBranchStoreLocation({
    required String id,
    required String branchId,
    required String name,
    required DateTime nowUtc,
  }) async {
    final existing = await branchStoreLocations(branchId);
    if (existing.isNotEmpty) return null;
    return into(stockLocations).insertReturning(
      StockLocationsCompanion.insert(
        id: Value(id),
        type: StockLocationType.branchStore,
        branchId: Value(branchId),
        name: name,
        createdAt: Value(nowUtc),
        updatedAt: Value(nowUtc),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
  }

  Future<StockLocation?> ensureRoomLocation({
    required String id,
    required String branchId,
    required String roomId,
    required String name,
    required DateTime nowUtc,
  }) async {
    final existing = await roomLocations(roomId);
    if (existing.isNotEmpty) return null;
    return into(stockLocations).insertReturning(
      StockLocationsCompanion.insert(
        id: Value(id),
        type: StockLocationType.room,
        branchId: Value(branchId),
        roomId: Value(roomId),
        name: name,
        createdAt: Value(nowUtc),
        updatedAt: Value(nowUtc),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
  }

  /// Renames a branch's store location to follow the branch (§22).
  ///
  /// **Only `name`.** No id moves, so every balance and every movement keeps
  /// pointing at the same row — which is what makes a rename safe on a branch with
  /// a year of history.
  Future<int> renameBranchStoreLocation({
    required String branchId,
    required String name,
    required DateTime nowUtc,
  }) =>
      (update(stockLocations)..where(
            (t) =>
                t.type.equalsValue(StockLocationType.branchStore) &
                t.branchId.equals(branchId) &
                t.roomId.isNull() &
                t.deletedAt.isNull(),
          ))
          .write(
            StockLocationsCompanion(
              name: Value(name),
              updatedAt: Value(nowUtc),
              syncStatus: const Value(SyncStatus.pending),
            ),
          );

  Future<int> renameRoomLocation({
    required String roomId,
    required String name,
    required DateTime nowUtc,
  }) =>
      (update(stockLocations)..where(
            (t) =>
                t.type.equalsValue(StockLocationType.room) &
                t.roomId.equals(roomId) &
                t.deletedAt.isNull(),
          ))
          .write(
            StockLocationsCompanion(
              name: Value(name),
              updatedAt: Value(nowUtc),
              syncStatus: const Value(SyncStatus.pending),
            ),
          );

  // --- import audit ------------------------------------------------------------------------

  Future<ImportLogRow> insertImportLog(ImportLogsCompanion companion) =>
      into(importLogs).insertReturning(companion);

  Future<ImportLogRow?> importLogById(String id) =>
      (select(importLogs)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The guarded transition (§3.4, §33).
  ///
  /// `WHERE id = ? AND status = ?` is the whole concurrency control: two devices
  /// committing the same preview both run this, one matches one row and one
  /// matches none, and the loser's caller turns 0 into
  /// [ImportConcurrentUpdateFailure] — inside its transaction, so its master
  /// writes go back with it.
  ///
  /// There is deliberately no path out of `committed` or `discarded`: `from` would
  /// have to be one of them, and no caller passes that because
  /// [ImportStatus.isFinal] is checked first and this predicate would match
  /// nothing anyway.
  Future<int> transitionImportStatus({
    required String id,
    required ImportStatus from,
    required ImportStatus to,
    int? insertedRows,
    int? updatedRows,
    required DateTime nowUtc,
  }) =>
      (update(
        importLogs,
      )..where((t) => t.id.equals(id) & t.status.equalsValue(from))).write(
        ImportLogsCompanion(
          status: Value(to),
          insertedRows: insertedRows == null
              ? const Value.absent()
              : Value(insertedRows),
          updatedRows: updatedRows == null
              ? const Value.absent()
              : Value(updatedRows),
          updatedAt: Value(nowUtc),
          // A status transition is itself a change the server has not seen
          // (G-M7).
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

  /// The history query.
  ///
  /// Ordered by `created_at DESC, id DESC` on the **DateTime** column, never on
  /// rendered text: drift stores these as ISO-8601 UTC strings, and while that
  /// particular format happens to sort lexically, relying on it is the trap schema
  /// v4 removed from `stock_opnames`. The ordering here is expressed over the
  /// typed column so the comparison is the column's, not a string's.
  SimpleSelectStatement<$ImportLogsTable, ImportLogRow> importHistoryQuery({
    ImportEntity? entity,
    ImportStatus? status,
    String? importedBy,
    DateTime? fromUtc,
    DateTime? toUtc,
    String fileNameQuery = '',
    SyncStatus? syncStatus,
  }) {
    final needle = fileNameQuery.trim().toLowerCase();
    return select(importLogs)
      ..where((t) {
        var predicate = const Constant(true) as Expression<bool>;
        if (entity != null) {
          predicate = predicate & t.entity.equalsValue(entity);
        }
        if (status != null) {
          predicate = predicate & t.status.equalsValue(status);
        }
        if (importedBy != null) {
          predicate = predicate & t.importedBy.equals(importedBy);
        }
        if (fromUtc != null) {
          predicate = predicate & t.createdAt.isBiggerOrEqualValue(fromUtc);
        }
        if (toUtc != null) {
          predicate = predicate & t.createdAt.isSmallerOrEqualValue(toUtc);
        }
        if (needle.isNotEmpty) {
          predicate = predicate & t.fileName.lower().like('%$needle%');
        }
        if (syncStatus != null) {
          predicate = predicate & t.syncStatus.equalsValue(syncStatus);
        }
        return predicate;
      })
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
  }

  /// Runs [action] in one transaction.
  ///
  /// The **only** transaction opener in this DAO. Every writer above deliberately
  /// has none of its own, so a caller composing five hundred of them gets one
  /// transaction rather than five hundred (§33).
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      transaction(action);
}

/// Reference counts for one item, as raw numbers.
///
/// A record-shaped class rather than the domain's `MasterHistoricalUsage`,
/// because a DAO returning a domain model would make `core/db` depend on a
/// feature's domain — the direction the architecture tests refuse. The repository
/// maps it.
class ItemUsageCounts {
  const ItemUsageCounts({
    required this.movements,
    required this.balances,
    required this.opnameLines,
    required this.purchaseRequestLines,
    required this.deliveryOrderLines,
    required this.goodReceiptLines,
    required this.distributionLines,
    required this.disposalLines,
    required this.consumptionLines,
    required this.goodsReturnLines,
    required this.batches,
  });

  final int movements;
  final int balances;
  final int opnameLines;
  final int purchaseRequestLines;
  final int deliveryOrderLines;
  final int goodReceiptLines;
  final int distributionLines;
  final int disposalLines;
  final int consumptionLines;
  final int goodsReturnLines;
  final int batches;
}

class BatchUsageCounts {
  const BatchUsageCounts({
    required this.movements,
    required this.balances,
    required this.opnameLines,
    required this.deliveryOrderLines,
    required this.goodReceiptLines,
    required this.distributionLines,
    required this.disposalLines,
    required this.consumptionLines,
    required this.goodsReturnLines,
  });

  final int movements;
  final int balances;
  final int opnameLines;
  final int deliveryOrderLines;
  final int goodReceiptLines;
  final int distributionLines;
  final int disposalLines;
  final int consumptionLines;
  final int goodsReturnLines;
}

class RoomUsageCounts {
  const RoomUsageCounts({
    required this.stockLocations,
    required this.movements,
    required this.balances,
    required this.distributionLines,
  });

  final int stockLocations;
  final int movements;
  final int balances;
  final int distributionLines;
}

class BranchUsageCounts {
  const BranchUsageCounts({
    required this.rooms,
    required this.activeUsers,
    required this.users,
    required this.stockLocations,
  });

  final int rooms;
  final int activeUsers;
  final int users;
  final int stockLocations;
}
