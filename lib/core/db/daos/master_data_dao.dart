import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/master_tables.dart';

part 'master_data_dao.g.dart';

/// Counts used by the development home page.
class MasterDataCounts {
  const MasterDataCounts({
    required this.branches,
    required this.rooms,
    required this.categories,
    required this.items,
    required this.locations,
    required this.users,
  });

  final int branches;
  final int rooms;
  final int categories;
  final int items;
  final int locations;
  final int users;
}

/// Master data access. Every read filters soft-deleted rows and there is no
/// hard-delete API (G-A4 / G-A5).
@DriftAccessor(
  tables: [
    Branches,
    Rooms,
    Users,
    ItemCategories,
    Items,
    ItemBatches,
    StockLocations,
  ],
)
class MasterDataDao extends DatabaseAccessor<AppDatabase>
    with _$MasterDataDaoMixin {
  MasterDataDao(super.db);

  // --- idempotent writers (used by the development seed) --------------------

  Future<Branch> ensureBranch({
    required String code,
    required String name,
    String? address,
  }) async {
    final existing = await (select(
      branches,
    )..where((t) => t.code.equals(code))).getSingleOrNull();
    if (existing != null) return existing;

    return into(branches).insertReturning(
      BranchesCompanion.insert(code: code, name: name, address: Value(address)),
    );
  }

  Future<Room> ensureRoom({
    required String branchId,
    required String code,
    required String name,
  }) async {
    final existing =
        await (select(rooms)
              ..where((t) => t.branchId.equals(branchId) & t.code.equals(code)))
            .getSingleOrNull();
    if (existing != null) return existing;

    return into(rooms).insertReturning(
      RoomsCompanion.insert(branchId: branchId, code: code, name: name),
    );
  }

  Future<AppUser> ensureUser({
    required String email,
    required String fullName,
    required UserRole role,
    String? branchId,
  }) async {
    final existing = await (select(
      users,
    )..where((t) => t.email.equals(email))).getSingleOrNull();
    if (existing != null) return existing;

    return into(users).insertReturning(
      UsersCompanion.insert(
        fullName: fullName,
        email: email,
        role: role,
        branchId: Value(branchId),
      ),
    );
  }

  Future<ItemCategory> ensureCategory(String name) async {
    final existing = await (select(
      itemCategories,
    )..where((t) => t.name.equals(name))).getSingleOrNull();
    if (existing != null) return existing;

    return into(
      itemCategories,
    ).insertReturning(ItemCategoriesCompanion.insert(name: name));
  }

  Future<Item> ensureItem({
    required String sku,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    int expiryAlertDays = 30,
  }) async {
    final existing = await (select(
      items,
    )..where((t) => t.sku.equals(sku))).getSingleOrNull();
    if (existing != null) return existing;

    return into(items).insertReturning(
      ItemsCompanion.insert(
        sku: sku,
        name: name,
        categoryId: categoryId,
        unit: unit,
        minStockRoom: Value(minStockRoom),
        minStockBranch: Value(minStockBranch),
        hasExpiry: Value(hasExpiry),
        expiryAlertDays: Value(expiryAlertDays),
      ),
    );
  }

  Future<ItemBatch> ensureBatch({
    required String itemId,
    required String batchNo,
    required DateTime expiryDate,
  }) async {
    final existing =
        await (select(itemBatches)..where(
              (t) => t.itemId.equals(itemId) & t.batchNo.equals(batchNo),
            ))
            .getSingleOrNull();
    if (existing != null) return existing;

    return into(itemBatches).insertReturning(
      ItemBatchesCompanion.insert(
        itemId: itemId,
        batchNo: batchNo,
        expiryDate: expiryDate,
      ),
    );
  }

  Future<StockLocation> ensureLocation({
    required StockLocationType type,
    required String name,
    String? branchId,
    String? roomId,
  }) async {
    final existing =
        await (select(stockLocations)..where(
              (t) =>
                  t.type.equalsValue(type) &
                  (branchId == null
                      ? t.branchId.isNull()
                      : t.branchId.equals(branchId)) &
                  (roomId == null
                      ? t.roomId.isNull()
                      : t.roomId.equals(roomId)),
            ))
            .getSingleOrNull();
    if (existing != null) return existing;

    return into(stockLocations).insertReturning(
      StockLocationsCompanion.insert(
        type: type,
        name: name,
        branchId: Value(branchId),
        roomId: Value(roomId),
      ),
    );
  }

  // --- reads ----------------------------------------------------------------

  Future<List<Branch>> activeBranches() =>
      (select(branches)
            ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .get();

  Future<List<Room>> activeRooms({String? branchId}) =>
      (select(rooms)
            ..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.isActive.equals(true) &
                  (branchId == null
                      ? const Constant(true)
                      : t.branchId.equals(branchId)),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .get();

  Future<List<ItemCategory>> categories() =>
      (select(itemCategories)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<List<Item>> activeItems() =>
      (select(items)
            ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<List<StockLocation>> allStockLocations() =>
      (select(stockLocations)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<List<AppUser>> activeUsers() =>
      (select(users)
            ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
          .get();

  /// Case-insensitive search on item name and SKU (used by SearchableDropdown).
  Future<List<Item>> searchItems(
    String query, {
    String? categoryId,
    int limit = 8,
  }) {
    final pattern = '%${query.trim().toLowerCase()}%';
    return (select(items)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.isActive.equals(true) &
                (t.name.lower().like(pattern) | t.sku.lower().like(pattern)) &
                (categoryId == null
                    ? const Constant(true)
                    : t.categoryId.equals(categoryId)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(limit))
        .get();
  }

  Future<Item?> itemById(String id) =>
      (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ItemBatch?> batchById(String id) =>
      (select(itemBatches)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<ItemBatch>> batchesOfItem(String itemId) =>
      (select(itemBatches)
            ..where((t) => t.itemId.equals(itemId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.expiryDate)]))
          .get();

  Future<StockLocation?> locationById(String id) =>
      (select(stockLocations)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The stock location of one room, for **new** operations. Every room has
  /// exactly one, created alongside it; a room without one cannot hold stock
  /// and therefore cannot be counted.
  Future<StockLocation?> activeLocationForRoom(String roomId) =>
      (select(stockLocations)..where(
            (t) =>
                t.roomId.equals(roomId) &
                t.type.equalsValue(StockLocationType.room) &
                t.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// The stock location of one room **including archived ones**.
  ///
  /// Used only to complete documents that already reference it. A soft-deleted
  /// row is history, not absence: the balances it holds are real and a
  /// submitted count posted against it must still be reviewable (§7.2). Hiding
  /// it here would strand the document with no way forward, since `submitted`
  /// has no transition back to `draft`.
  /// A live location still wins when both exist: a room that was archived and
  /// re-created has two rows, and the balances a review must adjust are the
  /// ones on the live location. `getSingleOrNull` would throw on that pair,
  /// which is why this orders and takes one instead.
  Future<StockLocation?> historicalLocationForRoom(String roomId) =>
      (select(stockLocations)
            ..where(
              (t) =>
                  t.roomId.equals(roomId) &
                  t.type.equalsValue(StockLocationType.room),
            )
            ..orderBy([
              // `deleted_at IS NULL` is 1 for a live row, so descending puts
              // the live one first; `created_at` keeps the rest deterministic.
              (t) => OrderingTerm.desc(t.deletedAt.isNull()),
              (t) => OrderingTerm.asc(t.createdAt),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// A room for **new** operations: soft-deleted rows are invisible.
  Future<Room?> activeRoomById(String id) => (select(
    rooms,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// A room a historic document points at, soft-deleted rows included.
  Future<Room?> historicalRoomById(String id) =>
      (select(rooms)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<AppUser?> userById(String id) => (select(
    users,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<StockLocation?> warehouseLocation() =>
      (select(stockLocations)..where(
            (t) =>
                t.type.equalsValue(StockLocationType.warehouse) &
                t.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<MasterDataCounts> counts() async {
    Future<int> countLive(
      TableInfo<Table, Object?> table,
      GeneratedColumn<DateTime> deletedAt,
    ) async {
      final expr = countAll();
      final row =
          await (selectOnly(table)
                ..addColumns([expr])
                ..where(deletedAt.isNull()))
              .getSingle();
      return row.read(expr) ?? 0;
    }

    return MasterDataCounts(
      branches: await countLive(branches, branches.deletedAt),
      rooms: await countLive(rooms, rooms.deletedAt),
      categories: await countLive(itemCategories, itemCategories.deletedAt),
      items: await countLive(items, items.deletedAt),
      locations: await countLive(stockLocations, stockLocations.deletedAt),
      users: await countLive(users, users.deletedAt),
    );
  }
}
