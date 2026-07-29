// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_data_dao.dart';

// ignore_for_file: type=lint
mixin _$MasterDataDaoMixin on DatabaseAccessor<AppDatabase> {
  $BranchesTable get branches => attachedDatabase.branches;
  $RoomsTable get rooms => attachedDatabase.rooms;
  $UsersTable get users => attachedDatabase.users;
  $ItemCategoriesTable get itemCategories => attachedDatabase.itemCategories;
  $ItemsTable get items => attachedDatabase.items;
  $ItemBatchesTable get itemBatches => attachedDatabase.itemBatches;
  $StockLocationsTable get stockLocations => attachedDatabase.stockLocations;
  MasterDataDaoManager get managers => MasterDataDaoManager(this);
}

class MasterDataDaoManager {
  final _$MasterDataDaoMixin _db;
  MasterDataDaoManager(this._db);
  $$BranchesTableTableManager get branches =>
      $$BranchesTableTableManager(_db.attachedDatabase, _db.branches);
  $$RoomsTableTableManager get rooms =>
      $$RoomsTableTableManager(_db.attachedDatabase, _db.rooms);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$ItemCategoriesTableTableManager get itemCategories =>
      $$ItemCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.itemCategories,
      );
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db.attachedDatabase, _db.items);
  $$ItemBatchesTableTableManager get itemBatches =>
      $$ItemBatchesTableTableManager(_db.attachedDatabase, _db.itemBatches);
  $$StockLocationsTableTableManager get stockLocations =>
      $$StockLocationsTableTableManager(
        _db.attachedDatabase,
        _db.stockLocations,
      );
}
