import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/db/seed/development_seed.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/features/inventory/data/repositories/drift_inventory_repository.dart';
import 'package:aish_warehouse/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:aish_warehouse/features/inventory/domain/services/stock_posting_service.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/master/domain/repositories/master_data_repository.dart';
import 'package:drift/native.dart';

/// In-memory wiring of the whole inventory stack. Tests never touch a device
/// database file.
class TestContext {
  TestContext._({
    required this.database,
    required this.master,
    required this.inventory,
    required this.posting,
  });

  factory TestContext.create({
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) {
    final database = AppDatabase(NativeDatabase.memory());
    final master = DriftMasterDataRepository(database.masterDataDao);
    final inventory = DriftInventoryRepository(database.inventoryDao);
    return TestContext._(
      database: database,
      master: master,
      inventory: inventory,
      posting: StockPostingService(
        inventory: inventory,
        master: master,
        clock: clock,
        idGenerator: idGenerator,
      ),
    );
  }

  final AppDatabase database;
  final MasterDataRepository master;
  final InventoryRepository inventory;
  final StockPostingService posting;

  /// A posting service on the same database but with a different notion of
  /// "now", used to test expiry rules without waiting.
  StockPostingService postingWithClock(DateTime Function() clock) =>
      StockPostingService(inventory: inventory, master: master, clock: clock);

  DevelopmentSeed get seed => DevelopmentSeed(
    master: master,
    inventory: inventory,
    posting: posting,
    isDevelopmentBuild: true,
  );

  /// Same wiring, but flagged as a release build so the guard can be tested.
  DevelopmentSeed get productionSeed => DevelopmentSeed(
    master: master,
    inventory: inventory,
    posting: posting,
    isDevelopmentBuild: false,
  );

  Future<void> dispose() => database.close();
}

/// A minimal but complete fixture: one warehouse, one branch store, one room,
/// a warehouse user, one non-expiry item and one expiry item.
class InventoryFixture {
  const InventoryFixture({
    required this.warehouse,
    required this.branchStore,
    required this.room,
    required this.actor,
    required this.simpleItem,
    required this.expiryItem,
  });

  final MasterLocation warehouse;
  final MasterLocation branchStore;
  final MasterLocation room;
  final MasterUser actor;
  final MasterItem simpleItem;
  final MasterItem expiryItem;
}

Future<InventoryFixture> buildFixture(TestContext context) async {
  final master = context.master;

  final branch = await master.ensureBranch(code: 'CAB-01', name: 'Cabang Uji');
  final room = await master.ensureRoom(
    branchId: branch.id,
    code: 'R1',
    name: 'Ruang Dental 1',
  );

  final warehouse = await master.ensureLocation(
    type: StockLocationType.warehouse,
    name: 'Warehouse Pusat',
  );
  final branchStore = await master.ensureLocation(
    type: StockLocationType.branchStore,
    name: 'Gudang Cabang Uji',
    branchId: branch.id,
  );
  final roomLocation = await master.ensureLocation(
    type: StockLocationType.room,
    name: room.name,
    branchId: branch.id,
    roomId: room.id,
  );

  final actor = await master.ensureUser(
    email: 'warehouse@test.local',
    fullName: 'Petugas Uji',
    role: UserRole.warehouse,
  );

  final category = await master.ensureCategory('Alat Sekali Pakai');
  final simpleItem = await master.ensureItem(
    sku: 'TEST-0001',
    name: 'Masker Bedah',
    categoryId: category.id,
    unit: 'box',
    minStockRoom: 1,
    minStockBranch: 5,
    hasExpiry: false,
  );
  final expiryItem = await master.ensureItem(
    sku: 'TEST-0002',
    name: 'Anestesi Lokal',
    categoryId: category.id,
    unit: 'ampul',
    minStockRoom: 5,
    minStockBranch: 20,
    hasExpiry: true,
  );

  return InventoryFixture(
    warehouse: warehouse,
    branchStore: branchStore,
    room: roomLocation,
    actor: actor,
    simpleItem: simpleItem,
    expiryItem: expiryItem,
  );
}

/// Helper for expiry dates relative to "today" in UTC.
DateTime utcDaysFromNow(int days) {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day + days);
}
