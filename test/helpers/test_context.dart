import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/db/seed/development_seed.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/inventory/data/repositories/drift_inventory_repository.dart';
import 'package:aish_warehouse/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:aish_warehouse/features/inventory/domain/services/stock_posting_service.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/master/domain/repositories/master_data_repository.dart';
import 'package:aish_warehouse/features/opname/data/repositories/drift_opname_repository.dart';
import 'package:aish_warehouse/features/opname/domain/repositories/opname_repository.dart';
import 'package:aish_warehouse/features/opname/domain/use_cases/add_stock_opname_line_use_case.dart';
import 'package:aish_warehouse/features/opname/domain/use_cases/create_stock_opname_use_case.dart';
import 'package:aish_warehouse/features/opname/domain/use_cases/review_stock_opname_use_case.dart';
import 'package:aish_warehouse/features/opname/domain/use_cases/submit_stock_opname_use_case.dart';
import 'package:aish_warehouse/features/opname/domain/use_cases/update_stock_opname_line_use_case.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';

/// In-memory wiring of the whole inventory stack. Tests never touch a device
/// database file.
class TestContext {
  TestContext._({
    required this.database,
    required this.master,
    required this.inventory,
    required this.opnames,
    required this.posting,
    required this.clock,
  });

  factory TestContext.create({
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) {
    final database = AppDatabase(NativeDatabase.memory());
    final master = DriftMasterDataRepository(database.masterDataDao);
    final inventory = DriftInventoryRepository(database.inventoryDao);
    final opnames = DriftOpnameRepository(database.opnameDao);
    return TestContext._(
      database: database,
      master: master,
      inventory: inventory,
      opnames: opnames,
      clock: clock,
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
  final OpnameRepository opnames;
  final StockPostingService posting;

  /// The injected UTC clock, or `null` when the real one is in use.
  final DateTime Function()? clock;

  CreateStockOpnameUseCase createOpname({
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => CreateStockOpnameUseCase(
    opnames: opnames,
    master: master,
    inventory: inventory,
    clock: clock ?? this.clock,
    idGenerator: idGenerator,
  );

  UpdateStockOpnameLineUseCase get updateOpnameLine =>
      UpdateStockOpnameLineUseCase(opnames: opnames, master: master);

  AddStockOpnameLineUseCase get addOpnameLine => AddStockOpnameLineUseCase(
    opnames: opnames,
    master: master,
    inventory: inventory,
  );

  SubmitStockOpnameUseCase submitOpname({DateTime Function()? clock}) =>
      SubmitStockOpnameUseCase(
        opnames: opnames,
        master: master,
        clock: clock ?? this.clock,
      );

  ReviewStockOpnameUseCase reviewOpname({
    DateTime Function()? clock,
    StockPostingService? posting,
  }) => ReviewStockOpnameUseCase(
    opnames: opnames,
    master: master,
    posting: posting ?? this.posting,
    clock: clock ?? this.clock,
  );

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

  // --- master data lifecycle, for recovery tests ----------------------------
  //
  // Deliberately raw SQL rather than repository calls. The production API has
  // no deactivate, no archive and no hard delete: master data is only ever
  // written through the idempotent `ensure…` methods (G-A4/G-A5), and adding
  // writers so a test could reach a state would mean shipping the very API the
  // guardrails exist to withhold. These helpers reproduce what an
  // administrator's back-office (or a future sync payload) would do to the
  // rows, without giving the app a way to do it.

  /// `is_active = 0` — deactivation (G-A4).
  Future<void> deactivate(String table, String id) => database.customStatement(
    'UPDATE $table SET is_active = 0 WHERE id = ?;',
    [id],
  );

  /// `deleted_at = <now>` — soft delete (G-A5).
  Future<void> archive(String table, String id) => database.customStatement(
    'UPDATE $table SET deleted_at = ? WHERE id = ?;',
    [DateTime.utc(2026, 7, 30).toIso8601String(), id],
  );

  /// Physically removes a row, simulating corruption rather than any supported
  /// operation.
  ///
  /// Foreign keys are switched off for the statement, because the whole point
  /// is to produce a state the constraints normally prevent: a document
  /// pointing at a row that is gone. Nothing in `lib/` can reach this — it
  /// exists so §7.3 ("what happens when the reference is genuinely broken")
  /// can be tested rather than assumed.
  Future<void> corruptByDeleting(String table, String id) async {
    await database.customStatement('PRAGMA foreign_keys = OFF;');
    await database.customStatement('DELETE FROM $table WHERE id = ?;', [id]);
    await database.customStatement('PRAGMA foreign_keys = ON;');
  }

  /// Ledger rows written against one opname, read straight from the database
  /// so a rollback assertion cannot be fooled by a cached repository read.
  Future<int> movementCountFor(String opnameId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM stock_movements WHERE ref_doc_id = ?;',
          variables: [Variable<String>(opnameId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// The stored status of one document, bypassing every Dart layer.
  Future<String> statusOf(String opnameId) async {
    final row = await database
        .customSelect(
          'SELECT status FROM stock_opnames WHERE id = ?;',
          variables: [Variable<String>(opnameId)],
        )
        .getSingle();
    return row.read<String>('status');
  }
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

/// A branch fully set up for Stok Opname: a nurse, a branch head, three rooms
/// with stock locations, and a room that already holds decimal stock — one
/// non-expiry item and one expiry item split across a valid and an expired
/// batch.
class OpnameFixture {
  const OpnameFixture({
    required this.branch,
    required this.otherBranch,
    required this.room,
    required this.secondRoom,
    required this.otherBranchRoom,
    required this.roomLocation,
    required this.warehouse,
    required this.nurse,
    required this.secondNurse,
    required this.branchHead,
    required this.otherBranchHead,
    required this.warehouseUser,
    required this.category,
    required this.simpleItem,
    required this.expiryItem,
    required this.validBatch,
    required this.expiredBatch,
  });

  final MasterBranch branch;
  final MasterBranch otherBranch;
  final MasterRoom room;
  final MasterRoom secondRoom;
  final MasterRoom otherBranchRoom;
  final MasterLocation roomLocation;
  final MasterLocation warehouse;
  final MasterUser nurse;
  final MasterUser secondNurse;
  final MasterUser branchHead;
  final MasterUser otherBranchHead;
  final MasterUser warehouseUser;
  final MasterCategory category;
  final MasterItem simpleItem;
  final MasterItem expiryItem;
  final MasterBatch validBatch;
  final MasterBatch expiredBatch;
}

/// Builds [OpnameFixture] and seeds the room's opening balances **through the
/// ledger**, never by writing `stock_balances` directly — the same rule the
/// production code follows (G-A1).
///
/// [now] is the UTC instant used for expiry maths, so a fixture built with an
/// injected clock stays consistent with the service under test.
Future<OpnameFixture> buildOpnameFixture(
  TestContext context, {
  DateTime? now,
  String simpleQty = '10.5',
  String validBatchQty = '2.375',
  String expiredBatchQty = '0.5',
}) async {
  final master = context.master;
  final reference = now ?? DateTime.now().toUtc();
  final today = AppTimeZone.operationalDate(reference);

  final branch = await master.ensureBranch(code: 'CAB-01', name: 'Cabang Uji');
  final otherBranch = await master.ensureBranch(
    code: 'CAB-02',
    name: 'Cabang Lain',
  );

  final room = await master.ensureRoom(
    branchId: branch.id,
    code: 'R1',
    name: 'Ruang Dental 1',
  );
  final secondRoom = await master.ensureRoom(
    branchId: branch.id,
    code: 'R2',
    name: 'Ruang Dental 2',
  );
  final otherBranchRoom = await master.ensureRoom(
    branchId: otherBranch.id,
    code: 'R1',
    name: 'Ruang Dental 1 Cabang Lain',
  );

  final warehouse = await master.ensureLocation(
    type: StockLocationType.warehouse,
    name: 'Warehouse Pusat',
  );
  final roomLocation = await master.ensureLocation(
    type: StockLocationType.room,
    name: room.name,
    branchId: branch.id,
    roomId: room.id,
  );
  await master.ensureLocation(
    type: StockLocationType.room,
    name: secondRoom.name,
    branchId: branch.id,
    roomId: secondRoom.id,
  );
  await master.ensureLocation(
    type: StockLocationType.room,
    name: otherBranchRoom.name,
    branchId: otherBranch.id,
    roomId: otherBranchRoom.id,
  );

  final nurse = await master.ensureUser(
    email: 'perawat@test.local',
    fullName: 'Perawat Uji',
    role: UserRole.perawat,
    branchId: branch.id,
  );
  final secondNurse = await master.ensureUser(
    email: 'perawat2@test.local',
    fullName: 'Perawat Kedua',
    role: UserRole.perawat,
    branchId: branch.id,
  );
  final branchHead = await master.ensureUser(
    email: 'kacab@test.local',
    fullName: 'Kepala Cabang Uji',
    role: UserRole.kepalaCabang,
    branchId: branch.id,
  );
  final otherBranchHead = await master.ensureUser(
    email: 'kacab2@test.local',
    fullName: 'Kepala Cabang Lain',
    role: UserRole.kepalaCabang,
    branchId: otherBranch.id,
  );
  final warehouseUser = await master.ensureUser(
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

  final validBatch = await master.ensureBatch(
    itemId: expiryItem.id,
    batchNo: 'BATCH-OK',
    expiryDate: DateOnly.addDays(today, 120),
  );
  final expiredBatch = await master.ensureBatch(
    itemId: expiryItem.id,
    batchNo: 'BATCH-EXP',
    expiryDate: DateOnly.addDays(today, -5),
  );

  // Stock reaches the room the way it does in production: inbound to the
  // warehouse, then transferred. The expired batch is placed while it is still
  // valid, because a transfer of expired stock is rejected (G-E4) — which is
  // exactly the situation an opname has to be able to report.
  DateTime placementClock() => reference;
  final earlyPosting = context.postingWithClock(
    () => DateOnly.addDays(AppTimeZone.operationalDate(reference), -10),
  );

  Future<void> place(
    StockPostingService posting,
    String itemId,
    String? batchId,
    String qty,
  ) async {
    final amount = Quantity.parse(qty);
    if (!amount.isPositive) return;
    await posting.postInboundWarehouse(
      itemId: itemId,
      batchId: batchId,
      toLocationId: warehouse.id,
      qty: amount,
      actorUserId: warehouseUser.id,
    );
    await posting.postTransfer(
      itemId: itemId,
      batchId: batchId,
      fromLocationId: warehouse.id,
      toLocationId: roomLocation.id,
      qty: amount,
      movementType: StockMovementType.distribution,
      actorUserId: warehouseUser.id,
    );
  }

  final posting = context.postingWithClock(placementClock);
  await place(posting, simpleItem.id, null, simpleQty);
  await place(posting, expiryItem.id, validBatch.id, validBatchQty);
  await place(earlyPosting, expiryItem.id, expiredBatch.id, expiredBatchQty);

  return OpnameFixture(
    branch: branch,
    otherBranch: otherBranch,
    room: room,
    secondRoom: secondRoom,
    otherBranchRoom: otherBranchRoom,
    roomLocation: roomLocation,
    warehouse: warehouse,
    nurse: nurse,
    secondNurse: secondNurse,
    branchHead: branchHead,
    otherBranchHead: otherBranchHead,
    warehouseUser: warehouseUser,
    category: category,
    simpleItem: simpleItem,
    expiryItem: expiryItem,
    validBatch: validBatch,
    expiredBatch: expiredBatch,
  );
}

/// Creates a document, counts one position short, and submits it.
///
/// The `create → find the plain item's line → count it low → submit` sequence
/// is what almost every review-side test needs before it can begin, and it was
/// being re-written in each file that needed it. The parameters are exactly the
/// axes those copies actually varied along.
///
/// [countedQty] is deliberately below the fixture's opening `10.5 box`, so the
/// document carries a real difference for a review to post; [note] satisfies
/// G-O3 for it. [clock] stamps `submitted_at`, for tests that must pin the
/// instant rather than take the wall clock (T-7).
Future<String> submitOpnameFor(
  TestContext context,
  OpnameFixture fixture, {
  String? roomId,
  String countedQty = '8',
  String note = 'Terpakai',
  DateTime Function()? clock,
}) async {
  final opname = await context.createOpname().call(
    actorUserId: fixture.nurse.id,
    roomId: roomId ?? fixture.room.id,
  );
  final detail = await context.opnames.getDetail(opname.id);
  final line = detail!.lines.firstWhere(
    (line) => line.itemId == fixture.simpleItem.id,
  );
  await context.updateOpnameLine(
    actorUserId: fixture.nurse.id,
    lineId: line.id,
    countedQty: Quantity.parse(countedQty),
    note: note,
  );
  await context
      .submitOpname(clock: clock)
      .call(actorUserId: fixture.nurse.id, opnameId: opname.id);
  return opname.id;
}

/// The room's balance of the fixture's non-expiry item — the quantity a review
/// of [submitOpnameFor]'s document is expected to move.
Future<Quantity> roomBalanceOf(TestContext context, OpnameFixture fixture) =>
    context.inventory.balanceQty(
      locationId: fixture.roomLocation.id,
      itemId: fixture.simpleItem.id,
    );

/// A fixed UTC instant that always lands mid-week in operational time, so a
/// test that adds or subtracts days stays inside one ISO week unless it means
/// not to. 2026-07-29 is a Wednesday (ISO week 31).
DateTime fixedWednesdayUtc() => DateTime.utc(2026, 7, 29, 3, 0);

/// An expiry date [days] away from the current *operational* day.
///
/// Counting from the GMT+8 date rather than the UTC one matters between 16:00
/// and 24:00 UTC, when the operational day has already rolled over: using the
/// UTC date there would place the batch a day earlier than intended and make
/// the expiry assertions flaky depending on when the suite runs.
DateTime expiryDateInDays(int days) =>
    DateOnly.addDays(AppTimeZone.operationalDate(DateTime.now().toUtc()), days);

/// A fixed UTC instant, for tests that must not depend on the wall clock.
DateTime utcInstant(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
]) => DateTime.utc(year, month, day, hour, minute);
