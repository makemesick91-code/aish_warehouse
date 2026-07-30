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
import 'package:aish_warehouse/features/purchase_request/data/repositories/drift_purchase_request_repository.dart';
import 'package:aish_warehouse/features/purchase_request/domain/models/purchase_request_models.dart';
import 'package:aish_warehouse/features/purchase_request/domain/repositories/purchase_request_repository.dart';
import 'package:aish_warehouse/features/purchase_request/domain/services/purchase_request_opname_eligibility_policy.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/add_purchase_request_line_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/cancel_purchase_request_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/create_purchase_request_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/mark_purchase_request_processing_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/reject_purchase_request_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/remove_purchase_request_line_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/replace_purchase_request_opnames_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/submit_purchase_request_use_case.dart';
import 'package:aish_warehouse/features/purchase_request/domain/use_cases/update_purchase_request_use_case.dart';
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
    required this.requests,
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
    final requests = DriftPurchaseRequestRepository(
      database.purchaseRequestDao,
    );
    return TestContext._(
      database: database,
      master: master,
      inventory: inventory,
      opnames: opnames,
      requests: requests,
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
  final PurchaseRequestRepository requests;
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

  // --- Purchase Request use cases -------------------------------------------
  //
  // Each takes an optional clock so a test can sit anywhere in the operational
  // calendar — on a year boundary for G-P1, or behind the document's own
  // timestamps for the clock-skew rules (T-7). Omitting it falls back to the
  // context's clock, and omitting that too uses the real one.

  CreatePurchaseRequestUseCase createPurchaseRequest({
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => CreatePurchaseRequestUseCase(
    requests: requests,
    master: master,
    clock: clock ?? this.clock,
    idGenerator: idGenerator,
  );

  UpdatePurchaseRequestUseCase get updatePurchaseRequest =>
      UpdatePurchaseRequestUseCase(requests: requests, master: master);

  ReplacePurchaseRequestOpnamesUseCase replacePurchaseRequestOpnames({
    DateTime Function()? clock,
  }) => ReplacePurchaseRequestOpnamesUseCase(
    requests: requests,
    master: master,
    clock: clock ?? this.clock,
  );

  AddPurchaseRequestLineUseCase get addPurchaseRequestLine =>
      AddPurchaseRequestLineUseCase(requests: requests, master: master);

  RemovePurchaseRequestLineUseCase get removePurchaseRequestLine =>
      RemovePurchaseRequestLineUseCase(requests: requests, master: master);

  SubmitPurchaseRequestUseCase submitPurchaseRequest({
    DateTime Function()? clock,
  }) => SubmitPurchaseRequestUseCase(
    requests: requests,
    master: master,
    clock: clock ?? this.clock,
  );

  CancelPurchaseRequestUseCase cancelPurchaseRequest({
    DateTime Function()? clock,
  }) => CancelPurchaseRequestUseCase(
    requests: requests,
    master: master,
    clock: clock ?? this.clock,
  );

  MarkPurchaseRequestProcessingUseCase markPurchaseRequestProcessing({
    DateTime Function()? clock,
  }) => MarkPurchaseRequestProcessingUseCase(
    requests: requests,
    master: master,
    clock: clock ?? this.clock,
  );

  RejectPurchaseRequestUseCase rejectPurchaseRequest({
    DateTime Function()? clock,
  }) => RejectPurchaseRequestUseCase(
    requests: requests,
    master: master,
    clock: clock ?? this.clock,
  );

  /// The `(year, week)` pairs a request created at [utcNow] may cite (G-P1).
  List<({int year, int week})> eligiblePeriods(DateTime utcNow) =>
      PurchaseRequestOpnameEligibilityPolicy.eligiblePeriods(utcNow)
          .map((week) => (year: week.year, week: week.week))
          .toList(growable: false);

  /// Every citation the branch may choose at [utcNow].
  Future<List<PurchaseRequestOpnameReference>> eligibleOpnamesFor({
    required String branchId,
    required DateTime utcNow,
  }) => requests.eligibleOpnames(
    branchId: branchId,
    periods: eligiblePeriods(utcNow),
  );

  /// A posting service on the same database but with a different notion of
  /// "now", used to test expiry rules without waiting.
  StockPostingService postingWithClock(DateTime Function() clock) =>
      StockPostingService(inventory: inventory, master: master, clock: clock);

  DevelopmentSeed get seed => DevelopmentSeed(
    master: master,
    inventory: inventory,
    posting: posting,
    opnames: opnames,
    requests: requests,
    isDevelopmentBuild: true,
  );

  /// Same wiring, but flagged as a release build so the guard can be tested.
  DevelopmentSeed get productionSeed => DevelopmentSeed(
    master: master,
    inventory: inventory,
    posting: posting,
    opnames: opnames,
    requests: requests,
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

  /// The stored status of one Purchase Request, bypassing every Dart layer.
  ///
  /// Reads the column directly, so an assertion about a rolled-back transition
  /// cannot be fooled by a cached repository read.
  Future<String> purchaseRequestStatusOf(String prId) async {
    final row = await database
        .customSelect(
          'SELECT status FROM purchase_requests WHERE id = ?;',
          variables: [Variable<String>(prId)],
        )
        .getSingle();
    return row.read<String>('status');
  }

  /// One raw column of a Purchase Request, for assertions about audit metadata.
  Future<String?> purchaseRequestColumn(String prId, String column) async {
    final row = await database
        .customSelect(
          'SELECT $column AS value FROM purchase_requests WHERE id = ?;',
          variables: [Variable<String>(prId)],
        )
        .getSingle();
    return row.read<String?>('value');
  }

  /// How many live `submitted`/`processing` requests a branch holds.
  ///
  /// Counted in SQL rather than through the repository, because the assertion this
  /// serves — "a concurrent submit produced at most one active order" — is about
  /// what the database contains, not about what a query object chose to return.
  Future<int> activePurchaseRequestCount(String branchId) async {
    final row = await database
        .customSelect(
          "SELECT COUNT(*) AS c FROM purchase_requests WHERE branch_id = ? "
          "AND deleted_at IS NULL AND status IN ('submitted', 'processing');",
          variables: [Variable<String>(branchId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Live line count of one request, read without any join.
  Future<int> purchaseRequestLineCount(String prId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM purchase_request_lines '
          'WHERE pr_id = ? AND deleted_at IS NULL;',
          variables: [Variable<String>(prId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Live citation count of one request, read without any join.
  Future<int> purchaseRequestOpnameLinkCount(String prId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM purchase_request_opnames '
          'WHERE pr_id = ? AND deleted_at IS NULL;',
          variables: [Variable<String>(prId)],
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

/// A branch fully set up for Purchase Request: three rooms with stock locations
/// and opening balances chosen so every branch of the suggestion formula (§14) is
/// exercised, plus the four roles the workflow needs and a second branch to prove
/// the scope rules against.
///
/// The par levels and room balances are the interesting part:
///
/// | item            | par | R1    | R2          | R3 | deficiency          |
/// |-----------------|-----|-------|-------------|----|---------------------|
/// | `simpleItem`    | 5   | `2.5` | `1`         | `5`| `2.5 + 4 + 0 = 6.5` |
/// | `batchItem`     | 10  | —     | `2 + 2 = 4` | —  | `6`                 |
/// | `abundantItem`  | 0   | `120` | —           | —  | `0`                 |
/// | `unstockedItem` | 3   | —     | —           | —  | not counted at all  |
/// | `spareItem`     | 4   | `1`   | —           | —  | `3`                 |
///
/// `simpleItem` gives a **decimal** suggestion across **two rooms**; `batchItem`
/// proves the batches are summed **per room before** the par comparison (`4` against
/// `10` is `6`, not `8 + 8`); `abundantItem` is at or above par and must not appear;
/// `unstockedItem` appears on no count at all and is therefore what a manual line is
/// added for; `spareItem` is the one tests deactivate to check that a withdrawn item
/// is never proposed.
class PurchaseRequestFixture {
  const PurchaseRequestFixture({
    required this.branch,
    required this.otherBranch,
    required this.roomOne,
    required this.roomTwo,
    required this.roomThree,
    required this.otherBranchRoom,
    required this.locationOne,
    required this.locationTwo,
    required this.locationThree,
    required this.nurse,
    required this.otherBranchNurse,
    required this.branchHead,
    required this.otherBranchHead,
    required this.warehouseUser,
    required this.secondWarehouseUser,
    required this.category,
    required this.simpleItem,
    required this.batchItem,
    required this.abundantItem,
    required this.unstockedItem,
    required this.spareItem,
    required this.batchOne,
    required this.batchTwo,
  });

  final MasterBranch branch;
  final MasterBranch otherBranch;
  final MasterRoom roomOne;
  final MasterRoom roomTwo;
  final MasterRoom roomThree;
  final MasterRoom otherBranchRoom;
  final MasterLocation locationOne;
  final MasterLocation locationTwo;
  final MasterLocation locationThree;
  final MasterUser nurse;
  final MasterUser otherBranchNurse;
  final MasterUser branchHead;
  final MasterUser otherBranchHead;
  final MasterUser warehouseUser;

  /// A second warehouse account, for the segregation checks that need two.
  final MasterUser secondWarehouseUser;

  final MasterCategory category;
  final MasterItem simpleItem;
  final MasterItem batchItem;
  final MasterItem abundantItem;
  final MasterItem unstockedItem;
  final MasterItem spareItem;
  final MasterBatch batchOne;
  final MasterBatch batchTwo;
}

/// Builds [PurchaseRequestFixture] and seeds the room balances **through the
/// ledger**, never by writing `stock_balances` directly — the same rule the
/// production code follows (G-A1).
///
/// Balances are placed with `postOpnameAdjustment` rather than a transfer from the
/// warehouse, because a transfer refuses an expired batch (G-E4) and needs warehouse
/// stock to exist first; the adjustment path writes a real movement either way and
/// keeps the fixture about the quantities the suggestion has to read.
Future<PurchaseRequestFixture> buildPurchaseRequestFixture(
  TestContext context, {
  DateTime? now,
}) async {
  final master = context.master;
  final reference = now ?? DateTime.now().toUtc();
  final today = AppTimeZone.operationalDate(reference);

  final branch = await master.ensureBranch(code: 'CAB-01', name: 'Cabang Uji');
  final otherBranch = await master.ensureBranch(
    code: 'CAB-02',
    name: 'Cabang Lain',
  );

  final roomOne = await master.ensureRoom(
    branchId: branch.id,
    code: 'R1',
    name: 'Ruang Dental 1',
  );
  final roomTwo = await master.ensureRoom(
    branchId: branch.id,
    code: 'R2',
    name: 'Ruang Dental 2',
  );
  final roomThree = await master.ensureRoom(
    branchId: branch.id,
    code: 'R3',
    name: 'Ruang Dental 3',
  );
  final otherBranchRoom = await master.ensureRoom(
    branchId: otherBranch.id,
    code: 'R1',
    name: 'Ruang Dental 1 Cabang Lain',
  );

  await master.ensureLocation(
    type: StockLocationType.warehouse,
    name: 'Warehouse Pusat',
  );
  final locationOne = await master.ensureLocation(
    type: StockLocationType.room,
    name: roomOne.name,
    branchId: branch.id,
    roomId: roomOne.id,
  );
  final locationTwo = await master.ensureLocation(
    type: StockLocationType.room,
    name: roomTwo.name,
    branchId: branch.id,
    roomId: roomTwo.id,
  );
  final locationThree = await master.ensureLocation(
    type: StockLocationType.room,
    name: roomThree.name,
    branchId: branch.id,
    roomId: roomThree.id,
  );
  final otherBranchLocation = await master.ensureLocation(
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
  final otherBranchNurse = await master.ensureUser(
    email: 'perawat2@test.local',
    fullName: 'Perawat Cabang Lain',
    role: UserRole.perawat,
    branchId: otherBranch.id,
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
    fullName: 'Petugas Warehouse Uji',
    role: UserRole.warehouse,
  );
  final secondWarehouseUser = await master.ensureUser(
    email: 'warehouse2@test.local',
    fullName: 'Petugas Warehouse Kedua',
    role: UserRole.warehouse,
  );

  final category = await master.ensureCategory('Alat Sekali Pakai');
  final otherCategory = await master.ensureCategory('Obat');

  final simpleItem = await master.ensureItem(
    sku: 'PR-0001',
    name: 'Masker Bedah',
    categoryId: category.id,
    unit: 'box',
    minStockRoom: 5,
    minStockBranch: 20,
    hasExpiry: false,
  );
  final batchItem = await master.ensureItem(
    sku: 'PR-0002',
    name: 'Anestesi Lokal',
    categoryId: otherCategory.id,
    unit: 'ampul',
    minStockRoom: 10,
    minStockBranch: 40,
    hasExpiry: true,
  );
  final abundantItem = await master.ensureItem(
    sku: 'PR-0003',
    name: 'Suction Tip',
    categoryId: category.id,
    unit: 'pcs',
    minStockRoom: 0,
    minStockBranch: 100,
    hasExpiry: false,
  );
  final unstockedItem = await master.ensureItem(
    sku: 'PR-0004',
    name: 'Bonding Agent',
    categoryId: otherCategory.id,
    unit: 'botol',
    minStockRoom: 3,
    minStockBranch: 9,
    hasExpiry: false,
  );
  final spareItem = await master.ensureItem(
    sku: 'PR-0005',
    name: 'Face Shield',
    categoryId: category.id,
    unit: 'pcs',
    minStockRoom: 4,
    minStockBranch: 10,
    hasExpiry: false,
  );

  final batchOne = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'BATCH-A',
    expiryDate: DateOnly.addDays(today, 120),
  );
  final batchTwo = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'BATCH-B',
    expiryDate: DateOnly.addDays(today, 240),
  );

  final posting = context.postingWithClock(() => reference);
  var sequence = 0;
  Future<void> place({
    required String locationId,
    required String itemId,
    String? batchId,
    required String qty,
  }) async {
    sequence += 1;
    await posting.postOpnameAdjustment(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
      countedQty: Quantity.parse(qty),
      actorUserId: warehouseUser.id,
      refDocType: RefDocType.seed,
      refDocId: 'fixture-$sequence',
      note: 'Saldo awal fixture',
    );
  }

  await place(locationId: locationOne.id, itemId: simpleItem.id, qty: '2.5');
  await place(locationId: locationOne.id, itemId: abundantItem.id, qty: '120');
  await place(locationId: locationOne.id, itemId: spareItem.id, qty: '1');
  await place(locationId: locationTwo.id, itemId: simpleItem.id, qty: '1');
  await place(
    locationId: locationTwo.id,
    itemId: batchItem.id,
    batchId: batchOne.id,
    qty: '2',
  );
  await place(
    locationId: locationTwo.id,
    itemId: batchItem.id,
    batchId: batchTwo.id,
    qty: '2',
  );
  await place(locationId: locationThree.id, itemId: simpleItem.id, qty: '5');
  // The other branch gets stock too, so a count filed there has lines and can be
  // offered to the wrong branch head in the scope tests.
  await place(
    locationId: otherBranchLocation.id,
    itemId: simpleItem.id,
    qty: '1',
  );

  return PurchaseRequestFixture(
    branch: branch,
    otherBranch: otherBranch,
    roomOne: roomOne,
    roomTwo: roomTwo,
    roomThree: roomThree,
    otherBranchRoom: otherBranchRoom,
    locationOne: locationOne,
    locationTwo: locationTwo,
    locationThree: locationThree,
    nurse: nurse,
    otherBranchNurse: otherBranchNurse,
    branchHead: branchHead,
    otherBranchHead: otherBranchHead,
    warehouseUser: warehouseUser,
    secondWarehouseUser: secondWarehouseUser,
    category: category,
    simpleItem: simpleItem,
    batchItem: batchItem,
    abundantItem: abundantItem,
    unstockedItem: unstockedItem,
    spareItem: spareItem,
    batchOne: batchOne,
    batchTwo: batchTwo,
  );
}

/// Files one Stok Opname for [room] at [utcNow] and hands it over.
///
/// The clock is injected into both the create and the submit, so the document lands
/// in the operational ISO week of [utcNow] rather than of the wall clock — which is
/// the whole mechanism behind the G-P1 tests.
///
/// `counted_qty` is left equal to the snapshotted `system_qty`, so every line is
/// difference-free and G-O3 demands no notes. [status] decides whether the count is
/// also reviewed; `submitted` and `reviewed` are equally citable (G-O4), and tests
/// assert both.
Future<String> fileOpnameForRoom(
  TestContext context, {
  required String roomId,
  required String nurseId,
  required DateTime utcNow,
  String? reviewedByUserId,
}) async {
  DateTime clock() => utcNow;

  final opname = await context
      .createOpname(clock: clock)
      .call(actorUserId: nurseId, roomId: roomId);
  await context
      .submitOpname(clock: clock)
      .call(actorUserId: nurseId, opnameId: opname.id);

  if (reviewedByUserId != null) {
    await context
        .reviewOpname(clock: clock, posting: context.postingWithClock(clock))
        .call(actorUserId: reviewedByUserId, opnameId: opname.id);
  }
  return opname.id;
}

/// Creates a Stok Opname for [room] at [utcNow] and leaves it as a **draft**.
///
/// A draft has not been handed over, so G-O4/G-P1 must refuse it as a citation —
/// which is the one thing this helper exists to set up.
Future<String> fileDraftOpnameForRoom(
  TestContext context, {
  required String roomId,
  required String nurseId,
  required DateTime utcNow,
}) async {
  final opname = await context
      .createOpname(clock: () => utcNow)
      .call(actorUserId: nurseId, roomId: roomId);
  return opname.id;
}

/// A fixed UTC instant that lands mid-week in operational time: 2026-07-29 is a
/// Wednesday, ISO week 31 of 2026.
DateTime prWednesdayUtc() => DateTime.utc(2026, 7, 29, 3, 0);

/// The same weekday one or more operational weeks earlier.
DateTime prWeeksBefore(int weeks) =>
    prWednesdayUtc().subtract(Duration(days: 7 * weeks));
