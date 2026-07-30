import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';

import '../helpers/test_context.dart';

/// A branch, a warehouse and a ledger with something on every shelf.
///
/// ### Why the ledger is posted rather than the documents run
///
/// The three ledger-primary reports — Stok Saat Ini, Kartu Stok, Kedaluwarsa — read
/// `stock_movements` and nothing else (G-L4), so a fixture that ran the whole PR →
/// DO → GR → Distribusi chain would spend most of its time producing document rows
/// none of those reports look at. What they need is movements with known quantities,
/// known timestamps and known references, which is exactly what
/// [StockPostingService] writes. The recap reports do need documents, and their
/// tests use the workflow fixtures that already exist.
///
/// ### The expired batch is reached by waiting, not by faking one
///
/// G-E4 refuses to transfer an expired batch, so a shelf cannot be *given* one.
/// [nearBatch] expires ten days after [postedAtUtc]; a report run at [asOfNearUtc]
/// sees it as *Segera kedaluwarsa* and one run at [asOfExpiredUtc] sees it as
/// *Kedaluwarsa*. That is the real sequence rather than a hand-written row.
class ReportingFixture {
  const ReportingFixture({
    required this.branch,
    required this.otherBranch,
    required this.room,
    required this.otherRoom,
    required this.warehouse,
    required this.branchStore,
    required this.roomLocation,
    required this.otherBranchStore,
    required this.otherRoomLocation,
    required this.nurse,
    required this.secondNurse,
    required this.branchHead,
    required this.otherBranchHead,
    required this.warehouseUser,
    required this.superAdmin,
    required this.obatCategory,
    required this.alatCategory,
    required this.obatItem,
    required this.alatItem,
    required this.nearBatch,
    required this.safeBatch,
    required this.postedAtUtc,
  });

  final MasterBranch branch;
  final MasterBranch otherBranch;
  final MasterRoom room;
  final MasterRoom otherRoom;

  final MasterLocation warehouse;
  final MasterLocation branchStore;
  final MasterLocation roomLocation;
  final MasterLocation otherBranchStore;
  final MasterLocation otherRoomLocation;

  final MasterUser nurse;

  /// A second nurse in the same branch. Every ownership assertion needs two people
  /// in one place — a nurse from another branch would be refused by the branch rule
  /// before the ownership rule was ever reached.
  final MasterUser secondNurse;

  final MasterUser branchHead;
  final MasterUser otherBranchHead;
  final MasterUser warehouseUser;
  final MasterUser superAdmin;

  final MasterCategory obatCategory;
  final MasterCategory alatCategory;

  /// `ampul`, tracks expiry. Two categories and two **different units** are the
  /// whole point: G-L6's totals must never add them together.
  final MasterItem obatItem;

  /// `box`, no expiry.
  final MasterItem alatItem;

  final MasterBatch nearBatch;
  final MasterBatch safeBatch;

  /// The instant every movement in this fixture was posted at.
  final DateTime postedAtUtc;

  /// Two days on: [nearBatch] has eight days left, inside its 30-day alert window.
  DateTime get asOfNearUtc => postedAtUtc.add(const Duration(days: 2));

  /// Thirty days on: [nearBatch] has expired.
  DateTime get asOfExpiredUtc => postedAtUtc.add(const Duration(days: 30));

  /// The operational date of [asOfNearUtc] — what a report is run *as of*.
  DateTime get asOfNearDate => AppTimeZone.operationalDate(asOfNearUtc);

  DateTime get asOfExpiredDate => AppTimeZone.operationalDate(asOfExpiredUtc);

  /// The operational date the movements were posted on.
  DateTime get postedDate => AppTimeZone.operationalDate(postedAtUtc);

  // The balances this fixture leaves behind, stated once so a test asserts against
  // a named expectation rather than a literal it derived from the same arithmetic
  // the code under test uses.

  /// Warehouse: 100 in, 30 shipped out.
  Quantity get warehouseNearBatchQty => Quantity.fromWhole(70);

  Quantity get warehouseSafeBatchQty => Quantity.fromWhole(50);

  /// Warehouse: 40 in, 10 shipped out.
  Quantity get warehouseAlatQty => Quantity.fromWhole(30);

  /// Branch store: 30 received, 12 distributed on.
  Quantity get branchStoreNearBatchQty => Quantity.fromWhole(18);

  Quantity get branchStoreAlatQty => Quantity.fromWhole(6);

  Quantity get roomNearBatchQty => Quantity.fromWhole(12);

  Quantity get roomAlatQty => Quantity.fromWhole(4);
}

/// Builds [ReportingFixture] against [context].
///
/// [postedAtUtc] pins every movement, so a test can place the report's cutoff
/// before, between or after them and get a boundary it chose rather than one the
/// wall clock handed it (T-7).
Future<ReportingFixture> buildReportingFixture(
  TestContext context, {
  required DateTime postedAtUtc,
}) async {
  final master = context.master;
  final postedDate = AppTimeZone.operationalDate(postedAtUtc);

  final branch = await master.ensureBranch(code: 'CAB-01', name: 'Cabang Satu');
  final otherBranch = await master.ensureBranch(
    code: 'CAB-02',
    name: 'Cabang Dua',
  );
  final room = await master.ensureRoom(
    branchId: branch.id,
    code: 'R1',
    name: 'Ruang Dental 1',
  );
  final otherRoom = await master.ensureRoom(
    branchId: otherBranch.id,
    code: 'R9',
    name: 'Ruang Dua',
  );

  final warehouse = await master.ensureLocation(
    type: StockLocationType.warehouse,
    name: 'Warehouse Pusat',
  );
  final branchStore = await master.ensureLocation(
    type: StockLocationType.branchStore,
    name: 'Gudang Cabang Satu',
    branchId: branch.id,
  );
  final roomLocation = await master.ensureLocation(
    type: StockLocationType.room,
    name: room.name,
    branchId: branch.id,
    roomId: room.id,
  );
  final otherBranchStore = await master.ensureLocation(
    type: StockLocationType.branchStore,
    name: 'Gudang Cabang Dua',
    branchId: otherBranch.id,
  );
  final otherRoomLocation = await master.ensureLocation(
    type: StockLocationType.room,
    name: otherRoom.name,
    branchId: otherBranch.id,
    roomId: otherRoom.id,
  );

  final nurse = await master.ensureUser(
    email: 'perawat-rpt@test.local',
    fullName: 'Perawat Satu',
    role: UserRole.perawat,
    branchId: branch.id,
  );
  final secondNurse = await master.ensureUser(
    email: 'perawat2-rpt@test.local',
    fullName: 'Perawat Dua',
    role: UserRole.perawat,
    branchId: branch.id,
  );
  final branchHead = await master.ensureUser(
    email: 'kacab-rpt@test.local',
    fullName: 'Kepala Cabang Satu',
    role: UserRole.kepalaCabang,
    branchId: branch.id,
  );
  final otherBranchHead = await master.ensureUser(
    email: 'kacab2-rpt@test.local',
    fullName: 'Kepala Cabang Dua',
    role: UserRole.kepalaCabang,
    branchId: otherBranch.id,
  );
  final warehouseUser = await master.ensureUser(
    email: 'wh-rpt@test.local',
    fullName: 'Petugas Warehouse',
    role: UserRole.warehouse,
  );
  final superAdmin = await master.ensureUser(
    email: 'super-rpt@test.local',
    fullName: 'Super Admin',
    role: UserRole.superAdmin,
  );

  final obatCategory = await master.ensureCategory('Obat');
  final alatCategory = await master.ensureCategory('Alat Sekali Pakai');

  final obatItem = await master.ensureItem(
    sku: 'OBT-0001',
    name: 'Anestesi Lokal',
    categoryId: obatCategory.id,
    unit: 'ampul',
    minStockRoom: 5,
    minStockBranch: 20,
    hasExpiry: true,
  );
  final alatItem = await master.ensureItem(
    sku: 'ALT-0001',
    name: 'Masker Bedah',
    categoryId: alatCategory.id,
    unit: 'box',
    minStockRoom: 1,
    minStockBranch: 5,
    hasExpiry: false,
  );

  final nearBatch = await master.ensureBatch(
    itemId: obatItem.id,
    batchNo: 'B-NEAR',
    expiryDate: DateOnly.addDays(postedDate, 10),
  );
  final safeBatch = await master.ensureBatch(
    itemId: obatItem.id,
    batchNo: 'B-SAFE',
    expiryDate: DateOnly.addDays(postedDate, 200),
  );

  final posting = context.postingWithClock(() => postedAtUtc);

  // Inbound — the only movement with no source (§2.2).
  await posting.postInboundWarehouse(
    itemId: obatItem.id,
    batchId: nearBatch.id,
    toLocationId: warehouse.id,
    qty: Quantity.fromWhole(100),
    actorUserId: warehouseUser.id,
  );
  await posting.postInboundWarehouse(
    itemId: obatItem.id,
    batchId: safeBatch.id,
    toLocationId: warehouse.id,
    qty: Quantity.fromWhole(50),
    actorUserId: warehouseUser.id,
  );
  await posting.postInboundWarehouse(
    itemId: alatItem.id,
    toLocationId: warehouse.id,
    qty: Quantity.fromWhole(40),
    actorUserId: warehouseUser.id,
  );

  // Warehouse → Gudang Cabang.
  await posting.postTransfer(
    itemId: obatItem.id,
    batchId: nearBatch.id,
    fromLocationId: warehouse.id,
    toLocationId: branchStore.id,
    qty: Quantity.fromWhole(30),
    movementType: StockMovementType.shipment,
    actorUserId: warehouseUser.id,
    refDocType: RefDocType.deliveryOrder,
    refDocId: 'do-fixture',
  );
  await posting.postTransfer(
    itemId: alatItem.id,
    fromLocationId: warehouse.id,
    toLocationId: branchStore.id,
    qty: Quantity.fromWhole(10),
    movementType: StockMovementType.shipment,
    actorUserId: warehouseUser.id,
    refDocType: RefDocType.deliveryOrder,
    refDocId: 'do-fixture',
  );

  // Gudang Cabang → Ruangan. The movement that must **not** be netted away by a
  // `branch_all` report (§21).
  await posting.postTransfer(
    itemId: obatItem.id,
    batchId: nearBatch.id,
    fromLocationId: branchStore.id,
    toLocationId: roomLocation.id,
    qty: Quantity.fromWhole(12),
    movementType: StockMovementType.distribution,
    actorUserId: branchHead.id,
    refDocType: RefDocType.distribution,
    refDocId: 'dist-fixture',
  );
  await posting.postTransfer(
    itemId: alatItem.id,
    fromLocationId: branchStore.id,
    toLocationId: roomLocation.id,
    qty: Quantity.fromWhole(4),
    movementType: StockMovementType.distribution,
    actorUserId: branchHead.id,
    refDocType: RefDocType.distribution,
    refDocId: 'dist-fixture',
  );

  // `stock_movements.created_at` comes from the table's `clientDefault`, not from
  // the posting service's clock, so the ledger has to be back-dated after the fact
  // for the period boundary to be testable at all — see
  // [TestContext.backdateMovements].
  await context.backdateMovements(postedAtUtc);

  return ReportingFixture(
    branch: branch,
    otherBranch: otherBranch,
    room: room,
    otherRoom: otherRoom,
    warehouse: warehouse,
    branchStore: branchStore,
    roomLocation: roomLocation,
    otherBranchStore: otherBranchStore,
    otherRoomLocation: otherRoomLocation,
    nurse: nurse,
    secondNurse: secondNurse,
    branchHead: branchHead,
    otherBranchHead: otherBranchHead,
    warehouseUser: warehouseUser,
    superAdmin: superAdmin,
    obatCategory: obatCategory,
    alatCategory: alatCategory,
    obatItem: obatItem,
    alatItem: alatItem,
    nearBatch: nearBatch,
    safeBatch: safeBatch,
    postedAtUtc: postedAtUtc,
  );
}
