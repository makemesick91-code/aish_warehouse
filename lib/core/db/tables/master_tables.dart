import 'package:drift/drift.dart';

import '../converters/enum_converters.dart';
import 'base_columns.dart';

@DataClassName('Branch')
class Branches extends Table with BusinessColumns {
  TextColumn get code => text().withLength(min: 1, max: 32).unique()();

  TextColumn get name => text().withLength(min: 1, max: 128)();

  TextColumn get address => text().nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('Room')
class Rooms extends Table with BusinessColumns {
  TextColumn get branchId => text().references(Branches, #id)();

  TextColumn get code => text().withLength(min: 1, max: 32)();

  TextColumn get name => text().withLength(min: 1, max: 128)();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {branchId, code},
  ];
}

@DataClassName('AppUser')
class Users extends Table with BusinessColumns {
  TextColumn get fullName => text().withLength(min: 1, max: 128)();

  TextColumn get email => text().withLength(min: 3, max: 190).unique()();

  TextColumn get role => text().map(const UserRoleConverter())();

  /// Mandatory for `perawat` and `kepala_cabang`, NULL for warehouse and super
  /// admin. The cross-column rule is enforced in the master data repository
  /// because it depends on the role enum mapping.
  TextColumn get branchId => text().nullable().references(Branches, #id)();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('ItemCategory')
class ItemCategories extends Table with BusinessColumns {
  TextColumn get name => text().withLength(min: 1, max: 128).unique()();
}

@DataClassName('Item')
class Items extends Table with BusinessColumns {
  TextColumn get sku => text().withLength(min: 1, max: 64).unique()();

  TextColumn get name => text().withLength(min: 1, max: 190)();

  TextColumn get categoryId => text().references(ItemCategories, #id)();

  TextColumn get unit => text().withLength(min: 1, max: 32)();

  IntColumn get minStockRoom => integer().withDefault(const Constant(0))();

  IntColumn get minStockBranch => integer().withDefault(const Constant(0))();

  BoolColumn get hasExpiry => boolean().withDefault(const Constant(false))();

  IntColumn get expiryAlertDays => integer().withDefault(const Constant(30))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  List<String> get customConstraints => [
    'CHECK (min_stock_room >= 0)',
    'CHECK (min_stock_branch >= 0)',
    'CHECK (expiry_alert_days >= 0)',
  ];
}

@DataClassName('ItemBatch')
class ItemBatches extends Table with BusinessColumns {
  TextColumn get itemId => text().references(Items, #id)();

  TextColumn get batchNo => text().withLength(min: 1, max: 64)();

  DateTimeColumn get expiryDate => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {itemId, batchNo},
  ];
}

@DataClassName('StockLocation')
class StockLocations extends Table with BusinessColumns {
  TextColumn get type => text().map(const StockLocationTypeConverter())();

  TextColumn get branchId => text().nullable().references(Branches, #id)();

  TextColumn get roomId => text().nullable().references(Rooms, #id)();

  TextColumn get name => text().withLength(min: 1, max: 190)();

  @override
  List<String> get customConstraints => [
    // warehouse  -> no branch, no room
    // branch_store -> branch only
    // room       -> branch and room
    "CHECK ((type = 'warehouse' AND branch_id IS NULL AND room_id IS NULL) "
        "OR (type = 'branch_store' AND branch_id IS NOT NULL AND room_id IS NULL) "
        "OR (type = 'room' AND branch_id IS NOT NULL AND room_id IS NOT NULL))",
  ];
}
