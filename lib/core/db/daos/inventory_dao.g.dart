// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_dao.dart';

// ignore_for_file: type=lint
mixin _$InventoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $BranchesTable get branches => attachedDatabase.branches;
  $RoomsTable get rooms => attachedDatabase.rooms;
  $StockLocationsTable get stockLocations => attachedDatabase.stockLocations;
  $ItemCategoriesTable get itemCategories => attachedDatabase.itemCategories;
  $ItemsTable get items => attachedDatabase.items;
  $ItemBatchesTable get itemBatches => attachedDatabase.itemBatches;
  $StockBalancesTable get stockBalances => attachedDatabase.stockBalances;
  $UsersTable get users => attachedDatabase.users;
  $StockMovementsTable get stockMovements => attachedDatabase.stockMovements;
  InventoryDaoManager get managers => InventoryDaoManager(this);
}

class InventoryDaoManager {
  final _$InventoryDaoMixin _db;
  InventoryDaoManager(this._db);
  $$BranchesTableTableManager get branches =>
      $$BranchesTableTableManager(_db.attachedDatabase, _db.branches);
  $$RoomsTableTableManager get rooms =>
      $$RoomsTableTableManager(_db.attachedDatabase, _db.rooms);
  $$StockLocationsTableTableManager get stockLocations =>
      $$StockLocationsTableTableManager(
        _db.attachedDatabase,
        _db.stockLocations,
      );
  $$ItemCategoriesTableTableManager get itemCategories =>
      $$ItemCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.itemCategories,
      );
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db.attachedDatabase, _db.items);
  $$ItemBatchesTableTableManager get itemBatches =>
      $$ItemBatchesTableTableManager(_db.attachedDatabase, _db.itemBatches);
  $$StockBalancesTableTableManager get stockBalances =>
      $$StockBalancesTableTableManager(_db.attachedDatabase, _db.stockBalances);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$StockMovementsTableTableManager get stockMovements =>
      $$StockMovementsTableTableManager(
        _db.attachedDatabase,
        _db.stockMovements,
      );
}
