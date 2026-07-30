import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/db/seed/development_seed.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/delivery/data/repositories/drift_delivery_order_repository.dart';
import 'package:aish_warehouse/features/delivery/domain/models/delivery_models.dart';
import 'package:aish_warehouse/features/delivery/domain/repositories/delivery_order_repository.dart';
import 'package:aish_warehouse/features/delivery/domain/services/delivery_warehouse_stock_reader.dart';
import 'package:aish_warehouse/features/delivery/domain/use_cases/build_fefo_delivery_allocation_use_case.dart';
import 'package:aish_warehouse/features/delivery/domain/use_cases/create_delivery_order_use_case.dart';
import 'package:aish_warehouse/features/delivery/domain/use_cases/remove_delivery_order_line_use_case.dart';
import 'package:aish_warehouse/features/delivery/domain/use_cases/ship_delivery_order_use_case.dart';
import 'package:aish_warehouse/features/delivery/domain/use_cases/update_delivery_order_line_use_case.dart';
import 'package:aish_warehouse/features/distribution/data/repositories/drift_distribution_repository.dart';
import 'package:aish_warehouse/features/distribution/domain/models/distribution_models.dart';
import 'package:aish_warehouse/features/distribution/domain/repositories/distribution_repository.dart';
import 'package:aish_warehouse/features/distribution/domain/services/distribution_branch_stock_reader.dart';
import 'package:aish_warehouse/features/distribution/domain/use_cases/add_distribution_item_use_case.dart';
import 'package:aish_warehouse/features/distribution/domain/use_cases/add_manual_distribution_allocation_use_case.dart';
import 'package:aish_warehouse/features/distribution/domain/use_cases/create_distribution_use_case.dart';
import 'package:aish_warehouse/features/distribution/domain/use_cases/post_distribution_use_case.dart';
import 'package:aish_warehouse/features/distribution/domain/use_cases/remove_distribution_line_use_case.dart';
import 'package:aish_warehouse/features/distribution/domain/use_cases/update_distribution_line_use_case.dart';
import 'package:aish_warehouse/features/good_receipt/data/repositories/drift_good_receipt_repository.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:aish_warehouse/features/good_receipt/domain/repositories/good_receipt_repository.dart';
import 'package:aish_warehouse/features/good_receipt/domain/use_cases/create_good_receipt_use_case.dart';
import 'package:aish_warehouse/features/good_receipt/domain/use_cases/decide_good_receipt_line_use_cases.dart';
import 'package:aish_warehouse/features/good_receipt/domain/use_cases/post_good_receipt_use_case.dart';
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
    required this.deliveries,
    required this.receipts,
    required this.distributions,
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
    final deliveries = DriftDeliveryOrderRepository(database.deliveryOrderDao);
    final receipts = DriftGoodReceiptRepository(database.goodReceiptDao);
    final distributions = DriftDistributionRepository(database.distributionDao);
    return TestContext._(
      database: database,
      master: master,
      inventory: inventory,
      opnames: opnames,
      requests: requests,
      deliveries: deliveries,
      receipts: receipts,
      distributions: distributions,
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
  final DeliveryOrderRepository deliveries;
  final GoodReceiptRepository receipts;
  final DistributionRepository distributions;
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

  // --- Delivery Order use cases ---------------------------------------------
  //
  // Each takes an optional clock so a test can sit on the day a batch expires, one
  // day past it, or behind the document's own timestamps for the clock-skew rules
  // (T-7). Omitting it falls back to the context's clock, and omitting that too
  // uses the real one.

  DeliveryWarehouseStockReader get deliveryStock =>
      DeliveryWarehouseStockReader(inventory);

  CreateDeliveryOrderUseCase createDeliveryOrder({
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => CreateDeliveryOrderUseCase(
    deliveries: deliveries,
    requests: requests,
    master: master,
    clock: clock ?? this.clock,
    idGenerator: idGenerator,
  );

  BuildFefoDeliveryAllocationUseCase allocateFefo({
    DateTime Function()? clock,
  }) => BuildFefoDeliveryAllocationUseCase(
    deliveries: deliveries,
    master: master,
    stock: deliveryStock,
    clock: clock ?? this.clock,
  );

  UpdateDeliveryOrderLineUseCase updateDeliveryLine({
    DateTime Function()? clock,
  }) => UpdateDeliveryOrderLineUseCase(
    deliveries: deliveries,
    master: master,
    stock: deliveryStock,
    clock: clock ?? this.clock,
  );

  RemoveDeliveryOrderLineUseCase get removeDeliveryLine =>
      RemoveDeliveryOrderLineUseCase(deliveries: deliveries, master: master);

  /// The ship use case, with both clocks pointing at the same instant.
  ///
  /// [posting] is injectable so a test can hand it a service that fails on a
  /// chosen line and then assert that *nothing* was written — the rollback
  /// assertion the atomicity rule exists for.
  ShipDeliveryOrderUseCase shipDeliveryOrder({
    DateTime Function()? clock,
    StockPostingService? posting,
  }) {
    final effectiveClock = clock ?? this.clock;
    return ShipDeliveryOrderUseCase(
      deliveries: deliveries,
      requests: requests,
      master: master,
      posting:
          posting ??
          (effectiveClock == null
              ? this.posting
              : postingWithClock(effectiveClock)),
      stock: deliveryStock,
      clock: effectiveClock,
    );
  }

  // --- Good Receipt (Milestone 5) -------------------------------------------
  //
  // Every factory takes an optional clock for the same two reasons the delivery
  // ones do: G-E5 is a function of the current operational day, and G-G6 of how
  // far past a 48-hour deadline a shipment has drifted. Omitting it falls back to
  // the context's clock, and omitting that too uses the real one.

  CreateGoodReceiptUseCase createGoodReceipt({
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => CreateGoodReceiptUseCase(
    receipts: receipts,
    deliveries: deliveries,
    requests: requests,
    master: master,
    clock: clock ?? this.clock,
    idGenerator: idGenerator,
  );

  CheckGoodReceiptLineUseCase checkGoodReceiptLine({
    DateTime Function()? clock,
  }) => CheckGoodReceiptLineUseCase(
    receipts: receipts,
    master: master,
    clock: clock ?? this.clock,
  );

  RejectGoodReceiptLineUseCase rejectGoodReceiptLine({
    DateTime Function()? clock,
  }) => RejectGoodReceiptLineUseCase(
    receipts: receipts,
    master: master,
    clock: clock ?? this.clock,
  );

  ResetGoodReceiptLineUseCase resetGoodReceiptLine({
    DateTime Function()? clock,
  }) => ResetGoodReceiptLineUseCase(
    receipts: receipts,
    master: master,
    clock: clock ?? this.clock,
  );

  /// The post use case, with both clocks pointing at the same instant.
  ///
  /// [posting] is injectable so a test can hand it a service that fails on a
  /// chosen line and then assert that *nothing* was written — the rollback
  /// assertion the atomicity rule exists for.
  PostGoodReceiptUseCase postGoodReceipt({
    DateTime Function()? clock,
    StockPostingService? posting,
  }) {
    final effectiveClock = clock ?? this.clock;
    return PostGoodReceiptUseCase(
      receipts: receipts,
      deliveries: deliveries,
      requests: requests,
      master: master,
      posting:
          posting ??
          (effectiveClock == null
              ? this.posting
              : postingWithClock(effectiveClock)),
      clock: effectiveClock,
    );
  }

  // --- Distribusi (Milestone 6) ---------------------------------------------
  //
  // Every factory takes an optional clock for the same reason the delivery ones do:
  // G-E4 is a function of the current operational day, and a batch that is valid
  // today is refused tomorrow. Omitting it falls back to the context's clock, and
  // omitting that too uses the real one.

  DistributionBranchStockReader get distributionStock =>
      DistributionBranchStockReader(inventory);

  CreateDistributionUseCase createDistribution({
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => CreateDistributionUseCase(
    distributions: distributions,
    master: master,
    clock: clock ?? this.clock,
    idGenerator: idGenerator,
  );

  AddDistributionItemUseCase addDistributionItem({
    DateTime Function()? clock,
  }) => AddDistributionItemUseCase(
    distributions: distributions,
    master: master,
    clock: clock ?? this.clock,
  );

  AddManualDistributionAllocationUseCase addManualDistributionAllocation({
    DateTime Function()? clock,
  }) => AddManualDistributionAllocationUseCase(
    distributions: distributions,
    master: master,
    clock: clock ?? this.clock,
  );

  UpdateDistributionLineUseCase updateDistributionLine({
    DateTime Function()? clock,
  }) => UpdateDistributionLineUseCase(
    distributions: distributions,
    master: master,
    clock: clock ?? this.clock,
  );

  RemoveDistributionLineUseCase get removeDistributionLine =>
      RemoveDistributionLineUseCase(
        distributions: distributions,
        master: master,
      );

  /// The post use case, with both clocks pointing at the same instant.
  ///
  /// [posting] is injectable so an atomicity test can hand it a service that fails on
  /// a chosen line and then assert that *nothing* was written — the rollback
  /// assertion G-T4 exists for.
  PostDistributionUseCase postDistribution({
    DateTime Function()? clock,
    StockPostingService? posting,
  }) {
    final effectiveClock = clock ?? this.clock;
    return PostDistributionUseCase(
      distributions: distributions,
      master: master,
      posting:
          posting ??
          (effectiveClock == null
              ? this.posting
              : postingWithClock(effectiveClock)),
      stock: distributionStock,
      clock: effectiveClock,
    );
  }

  /// A posting service on the same database but with a different notion of
  /// "now", used to test expiry rules without waiting.
  StockPostingService postingWithClock(DateTime Function() clock) =>
      StockPostingService(inventory: inventory, master: master, clock: clock);

  /// A posting service with one dependency swapped.
  ///
  /// Exists so an atomicity test can hand it a [FailingInventoryRepository] and then
  /// assert that *nothing* was written — the rollback assertion the whole "one
  /// transaction per document" rule exists for. Injecting the repository rather than
  /// stubbing the service keeps the real posting logic in the path, so the failure
  /// lands where a real one would.
  StockPostingService postingWith({
    InventoryRepository? inventory,
    DateTime Function()? clock,
  }) => StockPostingService(
    inventory: inventory ?? this.inventory,
    master: master,
    clock: clock ?? this.clock,
  );

  DevelopmentSeed get seed => DevelopmentSeed(
    master: master,
    inventory: inventory,
    posting: posting,
    opnames: opnames,
    requests: requests,
    deliveries: deliveries,
    receipts: receipts,
    distributions: distributions,
    isDevelopmentBuild: true,
  );

  /// Same wiring, but flagged as a release build so the guard can be tested.
  DevelopmentSeed get productionSeed => DevelopmentSeed(
    master: master,
    inventory: inventory,
    posting: posting,
    opnames: opnames,
    requests: requests,
    deliveries: deliveries,
    receipts: receipts,
    distributions: distributions,
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

  /// Inserts a second stock location of the same type for the same branch or room.
  ///
  /// Deliberately raw SQL: `MasterDataRepository.ensureLocation` is idempotent on
  /// `(type, branch_id, room_id)`, so the production API *cannot* produce a duplicate —
  /// which is exactly why the ambiguity failures need a helper to be reachable at all.
  /// A back-office import, a bad sync payload or a hand-edited database can produce
  /// this state, and §14 says a distribution must then refuse rather than guess which
  /// location the goods moved through. Returns the new row's id.
  Future<String> insertDuplicateLocation({
    required String id,
    required String type,
    required String name,
    String? branchId,
    String? roomId,
  }) async {
    await database.customStatement(
      'INSERT INTO stock_locations (id, created_at, updated_at, sync_status, '
      'type, branch_id, room_id, name) VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        DateTime.utc(2026, 7, 30).toIso8601String(),
        DateTime.utc(2026, 7, 30).toIso8601String(),
        'pending',
        type,
        branchId,
        roomId,
        name,
      ],
    );
    return id;
  }

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

  // --- Delivery Order raw reads, for rollback and atomicity assertions -------
  //
  // All of these read the columns directly, so an assertion about a rolled-back
  // transaction cannot be fooled by a cached repository read.

  /// The stored status of one Delivery Order.
  Future<String> deliveryOrderStatusOf(String doId) async {
    final row = await database
        .customSelect(
          'SELECT status FROM delivery_orders WHERE id = ?;',
          variables: [Variable<String>(doId)],
        )
        .getSingle();
    return row.read<String>('status');
  }

  /// One raw column of a Delivery Order, for assertions about audit metadata.
  Future<String?> deliveryOrderColumn(String doId, String column) async {
    final row = await database
        .customSelect(
          'SELECT $column AS value FROM delivery_orders WHERE id = ?;',
          variables: [Variable<String>(doId)],
        )
        .getSingle();
    return row.read<String?>('value');
  }

  /// Live allocation count of one shipment, read without any join.
  Future<int> deliveryLineCount(String doId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM delivery_order_lines '
          'WHERE do_id = ? AND deleted_at IS NULL;',
          variables: [Variable<String>(doId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Ledger rows written against one Delivery Order.
  ///
  /// The assertion behind every rollback test: a failed shipment must leave
  /// **zero** of these, whichever line it failed on.
  Future<int> shipmentMovementCount(String doId) async {
    final row = await database
        .customSelect(
          "SELECT COUNT(*) AS c FROM stock_movements WHERE ref_doc_type = 'DO' "
          'AND ref_doc_id = ?;',
          variables: [Variable<String>(doId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Every `shipment` movement of one document, as raw column values.
  Future<List<Map<String, Object?>>> shipmentMovements(String doId) async {
    final rows = await database
        .customSelect(
          'SELECT item_id, batch_id, from_location_id, to_location_id, qty, '
          'movement_type, ref_doc_type, ref_doc_id, actor_user_id '
          "FROM stock_movements WHERE ref_doc_type = 'DO' AND ref_doc_id = ? "
          'ORDER BY created_at, id;',
          variables: [Variable<String>(doId)],
        )
        .get();
    return rows
        .map(
          (row) => <String, Object?>{
            'item_id': row.read<String>('item_id'),
            'batch_id': row.read<String?>('batch_id'),
            'from_location_id': row.read<String?>('from_location_id'),
            'to_location_id': row.read<String?>('to_location_id'),
            'qty': row.read<int>('qty'),
            'movement_type': row.read<String>('movement_type'),
            'ref_doc_type': row.read<String?>('ref_doc_type'),
            'ref_doc_id': row.read<String?>('ref_doc_id'),
            'actor_user_id': row.read<String>('actor_user_id'),
          },
        )
        .toList(growable: false);
  }

  /// Balance rows at one location, keyed `item|batch`, read straight from SQL.
  Future<Map<String, int>> balancesAt(String locationId) async {
    final rows = await database
        .customSelect(
          'SELECT item_id, batch_id, qty_on_hand FROM stock_balances '
          'WHERE location_id = ? AND deleted_at IS NULL;',
          variables: [Variable<String>(locationId)],
        )
        .get();
    return {
      for (final row in rows)
        '${row.read<String>('item_id')}|${row.read<String?>('batch_id') ?? ''}':
            row.read<int>('qty_on_hand'),
    };
  }

  // --- Good Receipt raw reads, for rollback and atomicity assertions ---------
  //
  // All of these read the columns directly, so an assertion about a rolled-back
  // transaction cannot be fooled by a cached repository read.

  /// The stored status of one Good Receipt.
  Future<String> goodReceiptStatusOf(String grId) async {
    final row = await database
        .customSelect(
          'SELECT status FROM good_receipts WHERE id = ?;',
          variables: [Variable<String>(grId)],
        )
        .getSingle();
    return row.read<String>('status');
  }

  /// One raw column of a Good Receipt, for assertions about audit metadata.
  Future<String?> goodReceiptColumn(String grId, String column) async {
    final row = await database
        .customSelect(
          'SELECT $column AS value FROM good_receipts WHERE id = ?;',
          variables: [Variable<String>(grId)],
        )
        .getSingle();
    return row.read<String?>('value');
  }

  /// How many live receipts exist for one shipment.
  ///
  /// Counted in SQL rather than through the repository, because the assertion this
  /// serves — "a concurrent create produced exactly one receipt" — is about what the
  /// database contains, not about what a query object chose to return.
  Future<int> goodReceiptCountFor(String doId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM good_receipts WHERE do_id = ?;',
          variables: [Variable<String>(doId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Live line count of one receipt, read without any join.
  Future<int> goodReceiptLineCount(String grId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM good_receipt_lines '
          'WHERE gr_id = ? AND deleted_at IS NULL;',
          variables: [Variable<String>(grId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Raw decision rows of one receipt, keyed by line id.
  Future<Map<String, Map<String, Object?>>> goodReceiptLineRows(
    String grId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT id, do_line_id, item_id, batch_id, shipped_qty, '
          'received_qty, line_status, reject_reason FROM good_receipt_lines '
          'WHERE gr_id = ? AND deleted_at IS NULL;',
          variables: [Variable<String>(grId)],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): <String, Object?>{
          'do_line_id': row.read<String>('do_line_id'),
          'item_id': row.read<String>('item_id'),
          'batch_id': row.read<String?>('batch_id'),
          'shipped_qty': row.read<int>('shipped_qty'),
          'received_qty': row.read<int>('received_qty'),
          'line_status': row.read<String>('line_status'),
          'reject_reason': row.read<String?>('reject_reason'),
        },
    };
  }

  /// Ledger rows written against one Good Receipt.
  ///
  /// The assertion behind every rollback test: a failed posting must leave **zero**
  /// of these, whichever line it failed on.
  Future<int> goodReceiptMovementCount(String grId) async {
    final row = await database
        .customSelect(
          "SELECT COUNT(*) AS c FROM stock_movements WHERE ref_doc_type = 'GR' "
          'AND ref_doc_id = ?;',
          variables: [Variable<String>(grId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Every `good_receipt` movement of one receipt, as raw column values.
  Future<List<Map<String, Object?>>> goodReceiptMovements(String grId) async {
    final rows = await database
        .customSelect(
          'SELECT item_id, batch_id, from_location_id, to_location_id, qty, '
          'movement_type, ref_doc_type, ref_doc_id, actor_user_id '
          "FROM stock_movements WHERE ref_doc_type = 'GR' AND ref_doc_id = ? "
          'ORDER BY created_at, id;',
          variables: [Variable<String>(grId)],
        )
        .get();
    return rows
        .map(
          (row) => <String, Object?>{
            'item_id': row.read<String>('item_id'),
            'batch_id': row.read<String?>('batch_id'),
            'from_location_id': row.read<String?>('from_location_id'),
            'to_location_id': row.read<String?>('to_location_id'),
            'qty': row.read<int>('qty'),
            'movement_type': row.read<String>('movement_type'),
            'ref_doc_type': row.read<String?>('ref_doc_type'),
            'ref_doc_id': row.read<String?>('ref_doc_id'),
            'actor_user_id': row.read<String>('actor_user_id'),
          },
        )
        .toList(growable: false);
  }

  // --- Distribusi raw reads, for rollback and atomicity assertions -----------
  //
  // All of these read the columns directly, so an assertion about a rolled-back
  // transaction cannot be fooled by a cached repository read.

  /// The stored status of one Distribusi.
  Future<String> distributionStatusOf(String distributionId) async {
    final row = await database
        .customSelect(
          'SELECT status FROM distributions WHERE id = ?;',
          variables: [Variable<String>(distributionId)],
        )
        .getSingle();
    return row.read<String>('status');
  }

  /// One raw column of a Distribusi, for assertions about audit metadata.
  Future<String?> distributionColumn(
    String distributionId,
    String column,
  ) async {
    final row = await database
        .customSelect(
          'SELECT $column AS value FROM distributions WHERE id = ?;',
          variables: [Variable<String>(distributionId)],
        )
        .getSingle();
    return row.read<String?>('value');
  }

  /// Live line count of one distribution, read without any join.
  Future<int> distributionLineCount(String distributionId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM distribution_lines '
          'WHERE distribution_id = ? AND deleted_at IS NULL;',
          variables: [Variable<String>(distributionId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Raw line rows of one distribution, keyed by line id.
  Future<Map<String, Map<String, Object?>>> distributionLineRows(
    String distributionId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT id, room_id, item_id, batch_id, qty, fefo_override_reason '
          'FROM distribution_lines '
          'WHERE distribution_id = ? AND deleted_at IS NULL;',
          variables: [Variable<String>(distributionId)],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): <String, Object?>{
          'room_id': row.read<String>('room_id'),
          'item_id': row.read<String>('item_id'),
          'batch_id': row.read<String?>('batch_id'),
          'qty': row.read<int>('qty'),
          'fefo_override_reason': row.read<String?>('fefo_override_reason'),
        },
    };
  }

  /// Ledger rows written against one Distribusi.
  ///
  /// The assertion behind every rollback test: a failed posting must leave **zero** of
  /// these, whichever line it failed on (G-T4).
  Future<int> distributionMovementCount(String distributionId) async {
    final row = await database
        .customSelect(
          "SELECT COUNT(*) AS c FROM stock_movements "
          "WHERE ref_doc_type = 'DIST' AND ref_doc_id = ?;",
          variables: [Variable<String>(distributionId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// Every `distribution` movement of one document, as raw column values.
  Future<List<Map<String, Object?>>> distributionMovements(
    String distributionId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT item_id, batch_id, from_location_id, to_location_id, qty, '
          'movement_type, ref_doc_type, ref_doc_id, actor_user_id '
          "FROM stock_movements WHERE ref_doc_type = 'DIST' AND ref_doc_id = ? "
          'ORDER BY created_at, id;',
          variables: [Variable<String>(distributionId)],
        )
        .get();
    return rows
        .map(
          (row) => <String, Object?>{
            'item_id': row.read<String>('item_id'),
            'batch_id': row.read<String?>('batch_id'),
            'from_location_id': row.read<String?>('from_location_id'),
            'to_location_id': row.read<String?>('to_location_id'),
            'qty': row.read<int>('qty'),
            'movement_type': row.read<String>('movement_type'),
            'ref_doc_type': row.read<String?>('ref_doc_type'),
            'ref_doc_id': row.read<String?>('ref_doc_id'),
            'actor_user_id': row.read<String>('actor_user_id'),
          },
        )
        .toList(growable: false);
  }

  /// Total movement count across every document type, so a rollback test can assert
  /// that a failed posting wrote nothing **anywhere** rather than only nothing under
  /// its own reference.
  Future<int> totalMovementCount() async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM stock_movements;')
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

/// The operational (GMT+8) calendar date of a UTC instant.
///
/// A one-line wrapper so expiry tests read as dates rather than as timezone
/// arithmetic, and so they go through the same [AppTimeZone] the production code does
/// (T-5) rather than subtracting eight hours by hand.
DateTime operationalToday(DateTime utc) => AppTimeZone.operationalDate(utc);

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

/// A branch, a warehouse with stock, and a `processing` Purchase Request — the
/// state every Delivery Order test starts from.
///
/// The quantities are the interesting part, and each one exists to make a specific
/// rule reachable:
///
/// | item          | expiry | requested | warehouse stock                     |
/// |---------------|--------|-----------|-------------------------------------|
/// | `simpleItem`  | no     | `3`       | `2.5` — forces a **partial** shipment |
/// | `batchItem`   | yes    | `4`       | `1.5` near + `2` soon + `6` safe + `3` expired |
/// | `scarceItem`  | no     | `2`       | `0` — nothing to send at all          |
///
/// * `simpleItem` cannot be shipped in full, so G-D2's partial path and G-D5's
///   "stays `processing`" path are both reachable without touching anything else.
/// * `batchItem` has four batches covering every expiry case: `nearBatch` inside
///   the alert window (needs a confirmation, G-E4), `soonBatch` and `safeBatch`
///   further out, and `expiredBatch` holding real stock that must never ship. The
///   FEFO order is deliberately *not* the batch-number order, so an allocator that
///   sorted by name would fail.
/// * `tieBatchA`/`tieBatchB` share an expiry date, which is the case a naive
///   "diff against the canonical allocation" FEFO check gets wrong.
class DeliveryFixture {
  const DeliveryFixture({
    required this.branch,
    required this.otherBranch,
    required this.warehouse,
    required this.branchStore,
    required this.warehouseUser,
    required this.secondWarehouseUser,
    required this.branchHead,
    required this.otherBranchHead,
    required this.nurse,
    required this.simpleItem,
    required this.batchItem,
    required this.scarceItem,
    required this.tieItem,
    required this.nearBatch,
    required this.soonBatch,
    required this.safeBatch,
    required this.expiredBatch,
    required this.tieBatchA,
    required this.tieBatchB,
    required this.purchaseRequestId,
    required this.simpleLineId,
    required this.batchLineId,
    required this.scarceLineId,
    required this.tieLineId,
  });

  final MasterBranch branch;
  final MasterBranch otherBranch;
  final MasterLocation warehouse;
  final MasterLocation branchStore;
  final MasterUser warehouseUser;
  final MasterUser secondWarehouseUser;
  final MasterUser branchHead;
  final MasterUser otherBranchHead;
  final MasterUser nurse;

  final MasterItem simpleItem;
  final MasterItem batchItem;
  final MasterItem scarceItem;
  final MasterItem tieItem;

  final MasterBatch nearBatch;
  final MasterBatch soonBatch;
  final MasterBatch safeBatch;
  final MasterBatch expiredBatch;
  final MasterBatch tieBatchA;
  final MasterBatch tieBatchB;

  /// A Purchase Request in `processing`, with one line per item above.
  final String purchaseRequestId;

  final String simpleLineId;
  final String batchLineId;
  final String scarceLineId;
  final String tieLineId;
}

/// Builds [DeliveryFixture] against the injected [nowUtc].
///
/// Warehouse stock is placed **through the ledger** — inbound movements posted with
/// a clock at which every batch is still valid — never by writing `stock_balances`
/// directly, which is the same rule the production code follows (G-A1). The expired
/// batch is stocked while it was still in date, because inbound refuses an expired
/// batch (G-E4); that is precisely the situation a shipment then has to block.
///
/// The Purchase Request is written with raw SQL rather than through the create use
/// case, and deliberately so: `CreatePurchaseRequestUseCase` derives its lines from
/// stock opnames (G-P1), and going through it would make every delivery test depend
/// on the suggestion arithmetic of the previous milestone. What these tests need is
/// a request with exact requested quantities, which is what this writes.
Future<DeliveryFixture> buildDeliveryFixture(
  TestContext context, {
  required DateTime nowUtc,
}) async {
  final master = context.master;
  final today = AppTimeZone.operationalDate(nowUtc);

  final branch = await master.ensureBranch(
    code: 'CAB-01',
    name: 'Cabang Uji',
    address: 'Jl. Uji No. 1',
  );
  final otherBranch = await master.ensureBranch(
    code: 'CAB-02',
    name: 'Cabang Lain',
  );
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
  await master.ensureLocation(
    type: StockLocationType.room,
    name: room.name,
    branchId: branch.id,
    roomId: room.id,
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
  final nurse = await master.ensureUser(
    email: 'perawat@test.local',
    fullName: 'Perawat Uji',
    role: UserRole.perawat,
    branchId: branch.id,
  );

  final category = await master.ensureCategory('Alat Sekali Pakai');
  final simpleItem = await master.ensureItem(
    sku: 'DO-0001',
    name: 'Masker Bedah',
    categoryId: category.id,
    unit: 'box',
    minStockRoom: 5,
    minStockBranch: 20,
    hasExpiry: false,
  );
  final batchItem = await master.ensureItem(
    sku: 'DO-0002',
    name: 'Anestesi Lokal',
    categoryId: category.id,
    unit: 'ampul',
    minStockRoom: 10,
    minStockBranch: 40,
    hasExpiry: true,
  );
  final scarceItem = await master.ensureItem(
    sku: 'DO-0003',
    name: 'Bonding Agent',
    categoryId: category.id,
    unit: 'botol',
    minStockRoom: 3,
    minStockBranch: 9,
    hasExpiry: false,
  );
  final tieItem = await master.ensureItem(
    sku: 'DO-0004',
    name: 'Kasa Steril',
    categoryId: category.id,
    unit: 'roll',
    minStockRoom: 4,
    minStockBranch: 12,
    hasExpiry: true,
  );

  // `expiry_alert_days` defaults to 30, so 12 days is inside the window and 25 is
  // too; 300 is comfortably outside it.
  final nearBatch = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'B-NEAR',
    expiryDate: DateOnly.addDays(today, 12),
  );
  final soonBatch = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'A-SOON',
    expiryDate: DateOnly.addDays(today, 25),
  );
  final safeBatch = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'C-SAFE',
    expiryDate: DateOnly.addDays(today, 300),
  );
  final expiredBatch = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'D-EXPIRED',
    expiryDate: DateOnly.addDays(today, -3),
  );
  // Same expiry date, different batch numbers: the tie case.
  final tieBatchA = await master.ensureBatch(
    itemId: tieItem.id,
    batchNo: 'T-A',
    expiryDate: DateOnly.addDays(today, 100),
  );
  final tieBatchB = await master.ensureBatch(
    itemId: tieItem.id,
    batchNo: 'T-B',
    expiryDate: DateOnly.addDays(today, 100),
  );

  // Inbound at a clock well before every expiry date, so the expired batch can be
  // stocked while it was still valid.
  final earlyPosting = context.postingWithClock(
    () => nowUtc.subtract(const Duration(days: 30)),
  );
  Future<void> place(String itemId, String? batchId, String qty) =>
      earlyPosting.postInboundWarehouse(
        itemId: itemId,
        batchId: batchId,
        toLocationId: warehouse.id,
        qty: Quantity.parse(qty),
        actorUserId: warehouseUser.id,
        refDocType: RefDocType.seed,
        refDocId: 'fixture-$itemId-${batchId ?? 'nobatch'}',
        note: 'Saldo awal fixture',
      );

  await place(simpleItem.id, null, '2.5');
  await place(batchItem.id, nearBatch.id, '1.5');
  await place(batchItem.id, soonBatch.id, '2');
  await place(batchItem.id, safeBatch.id, '6');
  await place(batchItem.id, expiredBatch.id, '3');
  await place(tieItem.id, tieBatchA.id, '2');
  await place(tieItem.id, tieBatchB.id, '2');
  // `scarceItem` is deliberately left with no warehouse stock at all.

  final prId = await writeProcessingPurchaseRequest(
    context,
    branchId: branch.id,
    requestedBy: branchHead.id,
    processedBy: warehouseUser.id,
    nowUtc: nowUtc,
    lines: {
      simpleItem.id: '3',
      batchItem.id: '4',
      scarceItem.id: '2',
      tieItem.id: '3',
    },
  );

  final lineIds = await purchaseRequestLineIdsByItem(context, prId);

  return DeliveryFixture(
    branch: branch,
    otherBranch: otherBranch,
    warehouse: warehouse,
    branchStore: branchStore,
    warehouseUser: warehouseUser,
    secondWarehouseUser: secondWarehouseUser,
    branchHead: branchHead,
    otherBranchHead: otherBranchHead,
    nurse: nurse,
    simpleItem: simpleItem,
    batchItem: batchItem,
    scarceItem: scarceItem,
    tieItem: tieItem,
    nearBatch: nearBatch,
    soonBatch: soonBatch,
    safeBatch: safeBatch,
    expiredBatch: expiredBatch,
    tieBatchA: tieBatchA,
    tieBatchB: tieBatchB,
    purchaseRequestId: prId,
    simpleLineId: lineIds[simpleItem.id]!,
    batchLineId: lineIds[batchItem.id]!,
    scarceLineId: lineIds[scarceItem.id]!,
    tieLineId: lineIds[tieItem.id]!,
  );
}

/// Writes one Purchase Request directly, in [status], with the exact requested
/// quantities [lines] names (`itemId → "2.5"`).
///
/// Raw SQL on purpose. The production create path derives its lines from stock
/// opnames (G-P1) and its quantities from the suggestion arithmetic (§14); a
/// delivery test that went through it would be asserting the previous milestone's
/// behaviour before it got to its own. What it does **not** bypass is any
/// constraint: the CHECKs on `purchase_requests` still apply, which is why the
/// audit timestamps below are filled in exactly as a real transition would leave
/// them.
Future<String> writeProcessingPurchaseRequest(
  TestContext context, {
  required String branchId,
  required String requestedBy,
  required String processedBy,
  required DateTime nowUtc,
  required Map<String, String> lines,
  String status = 'processing',
  String? prId,
}) async {
  final id = prId ?? 'pr-${branchId.hashCode.abs()}-${lines.length}-$status';
  final submittedAt = nowUtc
      .subtract(const Duration(hours: 2))
      .toIso8601String();
  final processingAt = nowUtc
      .subtract(const Duration(hours: 1))
      .toIso8601String();

  await context.database.customStatement(
    'INSERT INTO purchase_requests (id, created_at, updated_at, sync_status, '
    'doc_number, branch_id, requested_by, status, submitted_at, processing_at, '
    'processed_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
    [
      id,
      nowUtc.subtract(const Duration(hours: 3)).toIso8601String(),
      processingAt,
      'pending',
      'TMP-PR-$id',
      branchId,
      requestedBy,
      status,
      submittedAt,
      // A `submitted` request has not been through the warehouse yet, so its
      // processing pair must be NULL — the table's CHECK says so.
      status == 'submitted' || status == 'draft' ? null : processingAt,
      status == 'submitted' || status == 'draft' ? null : processedBy,
    ],
  );

  var index = 0;
  for (final entry in lines.entries) {
    index += 1;
    await context.database.customStatement(
      'INSERT INTO purchase_request_lines (id, created_at, updated_at, '
      'sync_status, pr_id, item_id, suggested_qty, requested_qty) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
      [
        '$id-line-$index',
        processingAt,
        processingAt,
        'pending',
        id,
        entry.key,
        0,
        Quantity.parse(entry.value).milliUnits,
      ],
    );
  }
  return id;
}

/// `itemId → purchase_request_lines.id` for one request.
Future<Map<String, String>> purchaseRequestLineIdsByItem(
  TestContext context,
  String prId,
) async {
  final rows = await context.database
      .customSelect(
        'SELECT id, item_id FROM purchase_request_lines '
        'WHERE pr_id = ? AND deleted_at IS NULL;',
        variables: [Variable<String>(prId)],
      )
      .get();
  return {
    for (final row in rows) row.read<String>('item_id'): row.read<String>('id'),
  };
}

/// `prLineId|batchId → delivery_order_lines.id` for one shipment.
Future<Map<String, String>> deliveryLineIdsByAllocation(
  TestContext context,
  String doId,
) async {
  final rows = await context.database
      .customSelect(
        'SELECT id, pr_line_id, batch_id FROM delivery_order_lines '
        'WHERE do_id = ? AND deleted_at IS NULL;',
        variables: [Variable<String>(doId)],
      )
      .get();
  return {
    for (final row in rows)
      '${row.read<String>('pr_line_id')}|${row.read<String?>('batch_id') ?? ''}':
          row.read<String>('id'),
  };
}

/// Creates a `preparing` shipment and allocates exactly [allocations] onto it.
///
/// `prLineId → (batchId, qty)`, written through the repository so the partial
/// unique indexes and the CHECKs all apply. Used by the tests that care about what
/// happens at *ship* time and need a document in a precise shape to get there.
Future<String> prepareDeliveryOrder(
  TestContext context,
  DeliveryFixture fixture, {
  required DateTime nowUtc,
  required List<DeliveryAllocation> allocations,
  String? actorUserId,
}) async {
  final order = await context
      .createDeliveryOrder(clock: () => nowUtc)
      .call(
        actorUserId: actorUserId ?? fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );
  if (allocations.isNotEmpty) {
    await context.deliveries.replacePreparingLines(
      doId: order.id,
      allocations: allocations,
    );
  }
  return order.id;
}

/// One allocation of the fixture's expiry-tracked item.
DeliveryAllocation batchAllocation(
  DeliveryFixture fixture, {
  required String batchId,
  required String qty,
  String? fefoOverrideReason,
  bool nearExpiryConfirmed = false,
  String? nearExpiryNote,
}) => DeliveryAllocation(
  prLineId: fixture.batchLineId,
  itemId: fixture.batchItem.id,
  batchId: batchId,
  qty: Quantity.parse(qty),
  fefoOverrideReason: fefoOverrideReason,
  nearExpiryConfirmed: nearExpiryConfirmed,
  nearExpiryNote: nearExpiryNote,
);

/// One allocation of the fixture's item without expiry.
DeliveryAllocation simpleAllocation(
  DeliveryFixture fixture, {
  required String qty,
}) => DeliveryAllocation(
  prLineId: fixture.simpleLineId,
  itemId: fixture.simpleItem.id,
  qty: Quantity.parse(qty),
);

/// The fixture's safely dated batch, with the FEFO override reason shipping it needs.
///
/// `C-SAFE` expires in 300 days and `B-NEAR` in 12, so choosing the safe one skips a
/// nearer-expiry batch that still holds stock — which G-E3 requires a written reason
/// for. Good Receipt tests want a shipment whose expiry verdict is *valid*, and they
/// should not each have to rediscover that the shipment side demands a justification
/// for it.
DeliveryAllocation safeBatchAllocation(
  DeliveryFixture fixture, {
  required String qty,
}) => batchAllocation(
  fixture,
  batchId: fixture.safeBatch.id,
  qty: qty,
  fefoOverrideReason: 'Cabang meminta batch dengan sisa umur panjang',
);

/// One allocation of the fixture's tie-expiry item.
///
/// `T-A` and `T-B` share an expiry date 100 days out, so either is *valid* for a Good
/// Receipt and neither skips a nearer batch — which makes this the cheapest way for a
/// receipt test to reach a third position without arguing with FEFO.
DeliveryAllocation tieAllocation(
  DeliveryFixture fixture, {
  required String qty,
  String? batchId,
}) => DeliveryAllocation(
  prLineId: fixture.tieLineId,
  itemId: fixture.tieItem.id,
  batchId: batchId ?? fixture.tieBatchA.id,
  qty: Quantity.parse(qty),
);

/// One allocation of the fixture's deliberately unstocked item.
///
/// Call [stockForFullShipment] first. The fixture leaves `scarceItem` with no warehouse
/// balance because the delivery tests use it to prove "nothing to send"; a Good Receipt
/// test that needs *every* requested position shipped has to stock it.
DeliveryAllocation scarceAllocation(
  DeliveryFixture fixture, {
  required String qty,
}) => DeliveryAllocation(
  prLineId: fixture.scarceLineId,
  itemId: fixture.scarceItem.id,
  qty: Quantity.parse(qty),
);

/// Tops the central warehouse up so **every** requested position of the fixture's
/// Purchase Request can ship in full.
///
/// The fixture is built for the delivery tests, where two positions are deliberately
/// short: `simpleItem` has `2.5` against a request for `3` (forcing a partial
/// shipment) and `scarceItem` has nothing at all. A Good Receipt closure test needs the
/// opposite — a request that *can* be completed — so this places the difference.
///
/// Posted through the ledger with a clock well before [nowUtc], exactly as the
/// fixture's own opening balances are, so the inbound movement predates the shipment
/// that consumes it.
Future<void> stockForFullShipment(
  TestContext context,
  DeliveryFixture fixture, {
  required DateTime nowUtc,
}) async {
  final posting = context.postingWithClock(
    () => nowUtc.subtract(const Duration(days: 30)),
  );
  Future<void> place(String itemId, String qty, String key) =>
      posting.postInboundWarehouse(
        itemId: itemId,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.parse(qty),
        actorUserId: fixture.warehouseUser.id,
        refDocType: RefDocType.seed,
        refDocId: 'fixture-topup-$key',
        note: 'Saldo tambahan agar seluruh permintaan dapat dikirim',
      );

  await place(fixture.simpleItem.id, '1', 'simple');
  await place(fixture.scarceItem.id, '2', 'scarce');
}

/// Allocations that ship the fixture's request **completely** — the state G-D5 moves
/// the Purchase Request to `shipped` for, and therefore the only state from which a
/// Good Receipt can close it.
///
/// The tie item is split across both of its batches because neither holds the full `3`
/// on its own, and they share an expiry date so taking `T-A` before `T-B` is the FEFO
/// order rather than an override.
///
/// Call [stockForFullShipment] first.
List<DeliveryAllocation> fullRequestAllocations(DeliveryFixture fixture) => [
  simpleAllocation(fixture, qty: '3'),
  safeBatchAllocation(fixture, qty: '4'),
  tieAllocation(fixture, qty: '2'),
  tieAllocation(fixture, qty: '1', batchId: fixture.tieBatchB.id),
  scarceAllocation(fixture, qty: '2'),
];

// --- Good Receipt helpers (Milestone 5) -------------------------------------

/// Prepares a Delivery Order with [allocations] and **ships** it, so a Good Receipt
/// has something to check in.
///
/// Everything is stamped from [nowUtc] — creation and shipment both — because the
/// timestamp policy refuses a shipment that predates its own document (§36), and a
/// fixture that mixed the injected clock with the wall clock could not pin the
/// ordering. [shippedAtUtc] moves only the shipment, which is what a G-G6 deadline
/// test needs: a shipment that left 60 hours ago is overdue, and one that left an hour
/// ago is not.
Future<String> shipDeliveryOrderFor(
  TestContext context,
  DeliveryFixture fixture, {
  required DateTime nowUtc,
  required List<DeliveryAllocation> allocations,
  DateTime? shippedAtUtc,
  String? actorUserId,
}) async {
  final doId = await prepareDeliveryOrder(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: allocations,
    actorUserId: actorUserId,
  );
  final shippedAt = shippedAtUtc ?? nowUtc;
  await context
      .shipDeliveryOrder(clock: () => shippedAt)
      .call(
        actorUserId: actorUserId ?? fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );
  return doId;
}

/// Creates the `checking` Good Receipt of one shipment and returns its id.
Future<String> startGoodReceiptFor(
  TestContext context,
  DeliveryFixture fixture, {
  required String deliveryOrderId,
  required DateTime nowUtc,
  String? actorUserId,
}) async {
  final receipt = await context
      .createGoodReceipt(clock: () => nowUtc)
      .call(
        actorUserId: actorUserId ?? fixture.branchHead.id,
        deliveryOrderId: deliveryOrderId,
      );
  return receipt.id;
}

/// `doLineId → good_receipt_lines.id` for one receipt.
Future<Map<String, String>> goodReceiptLineIdsByDoLine(
  TestContext context,
  String grId,
) async {
  final rows = await context.database
      .customSelect(
        'SELECT id, do_line_id FROM good_receipt_lines '
        'WHERE gr_id = ? AND deleted_at IS NULL;',
        variables: [Variable<String>(grId)],
      )
      .get();
  return {
    for (final row in rows)
      row.read<String>('do_line_id'): row.read<String>('id'),
  };
}

/// The receipt's lines keyed by item id, which is what most assertions address them
/// by. Throws when the receipt cannot be read at all, so a test fails on the missing
/// document rather than on a null dereference three lines later.
Future<Map<String, GoodReceiptLine>> goodReceiptLinesByItem(
  TestContext context,
  String grId,
) async {
  final detail = await context.receipts.getDetail(grId);
  if (detail == null) {
    throw StateError('Good Receipt $grId tidak dapat dimuat.');
  }
  return {for (final line in detail.lines) line.itemId: line};
}

/// Decides every position of [grId] as accepted in full — the shortest route to a
/// receipt that G-G2 will let post.
Future<void> checkEveryGoodReceiptLine(
  TestContext context,
  DeliveryFixture fixture, {
  required String grId,
  required DateTime nowUtc,
  String? actorUserId,
}) async {
  final detail = await context.receipts.getDetail(grId);
  if (detail == null) {
    throw StateError('Good Receipt $grId tidak dapat dimuat.');
  }
  final check = context.checkGoodReceiptLine(clock: () => nowUtc);
  for (final line in detail.lines) {
    await check.call(
      actorUserId: actorUserId ?? fixture.branchHead.id,
      goodReceiptId: grId,
      goodReceiptLineId: line.id,
      receivedQty: line.shippedQty,
    );
  }
}

// --- Distribusi helpers (Milestone 6) ---------------------------------------

/// A branch whose *Gudang Cabang* is stocked and whose three rooms are ready to
/// receive — the state every Distribusi test starts from.
///
/// The quantities are the interesting part, and each one exists to make a specific
/// rule reachable:
///
/// | item          | expiry | branch store                                        |
/// |---------------|--------|-----------------------------------------------------|
/// | `simpleItem`  | no     | `10.5` — one balance, no batch (G-E2)               |
/// | `batchItem`   | yes    | `2` old + `4` new + `3` expired                     |
/// | `tieItem`     | yes    | `2` + `2`, same expiry date                         |
/// | `emptyItem`   | no     | nothing at all                                      |
///
/// * `simpleItem` is the decimal, non-batch case: `10.5 box` across three rooms with
///   no FEFO involved.
/// * `batchItem` is the FEFO case. `oldBatch` expires in 10 days and holds only `2`,
///   so a request for `3` **must** split across `oldBatch` and `newBatch` — and
///   choosing `newBatch` while `oldBatch` still has stock is the override G-E3 demands
///   a reason for. `expiredBatch` holds real stock that must never be distributable
///   (G-E4) and must stay on the shelf for disposal (G-E7). The FEFO order is
///   deliberately *not* the batch-number order, so an allocator that sorted by name
///   would fail. `oldBatch` is also inside the default 30-day alert window, which is
///   what the near-expiry badge is asserted against — without blocking anything.
/// * `tieBatchA`/`tieBatchB` share an expiry date, which is the case a naive "diff
///   against the canonical allocation" FEFO check gets wrong.
/// * `emptyItem` is what the picker must **not** offer (§15).
/// * `otherBranch` exists with its own room, store and branch head, so every G-T1
///   refusal has something real to be refused against rather than a fabricated id.
class DistributionFixture {
  const DistributionFixture({
    required this.branch,
    required this.otherBranch,
    required this.warehouse,
    required this.branchStore,
    required this.otherBranchStore,
    required this.roomOne,
    required this.roomTwo,
    required this.roomThree,
    required this.otherBranchRoom,
    required this.locationOne,
    required this.locationTwo,
    required this.locationThree,
    required this.otherBranchRoomLocation,
    required this.branchHead,
    required this.otherBranchHead,
    required this.nurse,
    required this.warehouseUser,
    required this.superAdmin,
    required this.category,
    required this.otherCategory,
    required this.simpleItem,
    required this.batchItem,
    required this.tieItem,
    required this.emptyItem,
    required this.oldBatch,
    required this.newBatch,
    required this.expiredBatch,
    required this.tieBatchA,
    required this.tieBatchB,
  });

  final MasterBranch branch;
  final MasterBranch otherBranch;

  final MasterLocation warehouse;
  final MasterLocation branchStore;
  final MasterLocation otherBranchStore;

  final MasterRoom roomOne;
  final MasterRoom roomTwo;
  final MasterRoom roomThree;
  final MasterRoom otherBranchRoom;

  final MasterLocation locationOne;
  final MasterLocation locationTwo;
  final MasterLocation locationThree;
  final MasterLocation otherBranchRoomLocation;

  final MasterUser branchHead;
  final MasterUser otherBranchHead;
  final MasterUser nurse;
  final MasterUser warehouseUser;
  final MasterUser superAdmin;

  final MasterCategory category;
  final MasterCategory otherCategory;

  final MasterItem simpleItem;
  final MasterItem batchItem;
  final MasterItem tieItem;
  final MasterItem emptyItem;

  /// Expires in 10 days and holds `2` — the batch FEFO must consume first, and the
  /// one an override skips.
  final MasterBatch oldBatch;

  /// Expires in 200 days and holds `4`.
  final MasterBatch newBatch;

  /// Expired three days ago and still holds `3`. Never distributable (G-E4).
  final MasterBatch expiredBatch;

  final MasterBatch tieBatchA;
  final MasterBatch tieBatchB;

  /// The room location of one room, for balance assertions.
  MasterLocation locationForRoom(String roomId) {
    if (roomId == roomOne.id) return locationOne;
    if (roomId == roomTwo.id) return locationTwo;
    if (roomId == roomThree.id) return locationThree;
    if (roomId == otherBranchRoom.id) return otherBranchRoomLocation;
    throw StateError('Ruangan $roomId bukan bagian dari fixture.');
  }
}

/// Builds [DistributionFixture] against the injected [nowUtc].
///
/// Branch-store stock is placed **through the ledger** — an inbound movement into the
/// central warehouse, then a `good_receipt` transfer down to the branch store — never
/// by writing `stock_balances` directly, which is the same rule the production code
/// follows (G-A1). Both postings run on a clock 30 days before [nowUtc], so the
/// expired batch can be stocked while it was still in date: a transfer refuses an
/// expired batch (G-E4), and that is precisely the situation a distribution then has to
/// block.
Future<DistributionFixture> buildDistributionFixture(
  TestContext context, {
  required DateTime nowUtc,
}) async {
  final master = context.master;
  final today = AppTimeZone.operationalDate(nowUtc);

  final branch = await master.ensureBranch(
    code: 'CAB-01',
    name: 'Cabang Uji',
    address: 'Jl. Uji No. 1',
  );
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

  final warehouse = await master.ensureLocation(
    type: StockLocationType.warehouse,
    name: 'Warehouse Pusat',
  );
  final branchStore = await master.ensureLocation(
    type: StockLocationType.branchStore,
    name: 'Gudang Cabang Uji',
    branchId: branch.id,
  );
  final otherBranchStore = await master.ensureLocation(
    type: StockLocationType.branchStore,
    name: 'Gudang Cabang Lain',
    branchId: otherBranch.id,
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
  final otherBranchRoomLocation = await master.ensureLocation(
    type: StockLocationType.room,
    name: otherBranchRoom.name,
    branchId: otherBranch.id,
    roomId: otherBranchRoom.id,
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
  final nurse = await master.ensureUser(
    email: 'perawat@test.local',
    fullName: 'Perawat Uji',
    role: UserRole.perawat,
    branchId: branch.id,
  );
  final warehouseUser = await master.ensureUser(
    email: 'warehouse@test.local',
    fullName: 'Petugas Warehouse Uji',
    role: UserRole.warehouse,
  );
  final superAdmin = await master.ensureUser(
    email: 'admin@test.local',
    fullName: 'Super Admin Uji',
    role: UserRole.superAdmin,
  );

  final category = await master.ensureCategory('Alat Sekali Pakai');
  final otherCategory = await master.ensureCategory('Obat');

  final simpleItem = await master.ensureItem(
    sku: 'DIST-0001',
    name: 'Masker Bedah',
    categoryId: category.id,
    unit: 'box',
    minStockRoom: 5,
    minStockBranch: 20,
    hasExpiry: false,
  );
  final batchItem = await master.ensureItem(
    sku: 'DIST-0002',
    name: 'Anestesi Lokal',
    categoryId: otherCategory.id,
    unit: 'ampul',
    minStockRoom: 10,
    minStockBranch: 40,
    hasExpiry: true,
  );
  final tieItem = await master.ensureItem(
    sku: 'DIST-0003',
    name: 'Kasa Steril',
    categoryId: category.id,
    unit: 'roll',
    minStockRoom: 4,
    minStockBranch: 12,
    hasExpiry: true,
  );
  final emptyItem = await master.ensureItem(
    sku: 'DIST-0004',
    name: 'Bonding Agent',
    categoryId: otherCategory.id,
    unit: 'botol',
    minStockRoom: 3,
    minStockBranch: 9,
    hasExpiry: false,
  );

  // `expiry_alert_days` defaults to 30, so 10 days is inside the alert window and 200
  // is comfortably outside it. The batch numbers deliberately run against the expiry
  // order: `A-NEW` expires later than `B-OLD`.
  final oldBatch = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'B-OLD',
    expiryDate: DateOnly.addDays(today, 10),
  );
  final newBatch = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'A-NEW',
    expiryDate: DateOnly.addDays(today, 200),
  );
  final expiredBatch = await master.ensureBatch(
    itemId: batchItem.id,
    batchNo: 'C-EXPIRED',
    expiryDate: DateOnly.addDays(today, -3),
  );
  // Same expiry date, different batch numbers: the tie case.
  final tieBatchA = await master.ensureBatch(
    itemId: tieItem.id,
    batchNo: 'T-A',
    expiryDate: DateOnly.addDays(today, 100),
  );
  final tieBatchB = await master.ensureBatch(
    itemId: tieItem.id,
    batchNo: 'T-B',
    expiryDate: DateOnly.addDays(today, 100),
  );

  // Inbound and transfer on a clock well before every expiry date, so the expired
  // batch can be stocked while it was still valid.
  final earlyPosting = context.postingWithClock(
    () => nowUtc.subtract(const Duration(days: 30)),
  );
  Future<void> place(String itemId, String? batchId, String qty) async {
    final amount = Quantity.parse(qty);
    await earlyPosting.postInboundWarehouse(
      itemId: itemId,
      batchId: batchId,
      toLocationId: warehouse.id,
      qty: amount,
      actorUserId: warehouseUser.id,
      refDocType: RefDocType.seed,
      refDocId: 'fixture-$itemId-${batchId ?? 'nobatch'}',
      note: 'Saldo awal fixture',
    );
    await earlyPosting.postTransfer(
      itemId: itemId,
      batchId: batchId,
      fromLocationId: warehouse.id,
      toLocationId: branchStore.id,
      qty: amount,
      movementType: StockMovementType.goodReceipt,
      actorUserId: warehouseUser.id,
      refDocType: RefDocType.seed,
      refDocId: 'fixture-gr-$itemId-${batchId ?? 'nobatch'}',
      note: 'Penerimaan awal fixture',
    );
  }

  await place(simpleItem.id, null, '10.5');
  await place(batchItem.id, oldBatch.id, '2');
  await place(batchItem.id, newBatch.id, '4');
  await place(batchItem.id, expiredBatch.id, '3');
  await place(tieItem.id, tieBatchA.id, '2');
  await place(tieItem.id, tieBatchB.id, '2');
  // `emptyItem` is deliberately left with no branch-store stock at all.

  return DistributionFixture(
    branch: branch,
    otherBranch: otherBranch,
    warehouse: warehouse,
    branchStore: branchStore,
    otherBranchStore: otherBranchStore,
    roomOne: roomOne,
    roomTwo: roomTwo,
    roomThree: roomThree,
    otherBranchRoom: otherBranchRoom,
    locationOne: locationOne,
    locationTwo: locationTwo,
    locationThree: locationThree,
    otherBranchRoomLocation: otherBranchRoomLocation,
    branchHead: branchHead,
    otherBranchHead: otherBranchHead,
    nurse: nurse,
    warehouseUser: warehouseUser,
    superAdmin: superAdmin,
    category: category,
    otherCategory: otherCategory,
    simpleItem: simpleItem,
    batchItem: batchItem,
    tieItem: tieItem,
    emptyItem: emptyItem,
    oldBatch: oldBatch,
    newBatch: newBatch,
    expiredBatch: expiredBatch,
    tieBatchA: tieBatchA,
    tieBatchB: tieBatchB,
  );
}

/// Creates a `draft` distribution for the fixture's branch head and returns its id.
Future<String> createDistributionDraft(
  TestContext context,
  DistributionFixture fixture, {
  required DateTime nowUtc,
  String? actorUserId,
  String? note,
}) async {
  final distribution = await context
      .createDistribution(clock: () => nowUtc)
      .call(actorUserId: actorUserId ?? fixture.branchHead.id, note: note);
  return distribution.id;
}

/// Adds one item to one room with FEFO choosing the batches.
Future<DistributionAdditionResult> addDistributionItem(
  TestContext context,
  DistributionFixture fixture, {
  required String distributionId,
  required String roomId,
  required String itemId,
  required String qty,
  required DateTime nowUtc,
  String? actorUserId,
}) => context
    .addDistributionItem(clock: () => nowUtc)
    .call(
      actorUserId: actorUserId ?? fixture.branchHead.id,
      distributionId: distributionId,
      roomId: roomId,
      itemId: itemId,
      requestedQty: Quantity.parse(qty),
    );

/// Adds one hand-picked batch allocation.
Future<DistributionAllocation> addManualDistributionAllocation(
  TestContext context,
  DistributionFixture fixture, {
  required String distributionId,
  required String roomId,
  required String itemId,
  String? batchId,
  required String qty,
  required DateTime nowUtc,
  String? fefoOverrideReason,
  String? actorUserId,
}) => context
    .addManualDistributionAllocation(clock: () => nowUtc)
    .call(
      actorUserId: actorUserId ?? fixture.branchHead.id,
      distributionId: distributionId,
      roomId: roomId,
      itemId: itemId,
      batchId: batchId,
      qty: Quantity.parse(qty),
      fefoOverrideReason: fefoOverrideReason,
    );

/// `room|item|batch → distribution_lines.id` for one document.
///
/// The same grain as the two partial unique indexes, so a test addresses a line the
/// way the database identifies it.
Future<Map<String, String>> distributionLineIdsByPosition(
  TestContext context,
  String distributionId,
) async {
  final rows = await context.database
      .customSelect(
        'SELECT id, room_id, item_id, batch_id FROM distribution_lines '
        'WHERE distribution_id = ? AND deleted_at IS NULL;',
        variables: [Variable<String>(distributionId)],
      )
      .get();
  return {
    for (final row in rows)
      '${row.read<String>('room_id')}|${row.read<String>('item_id')}|'
          '${row.read<String?>('batch_id') ?? ''}': row.read<String>(
        'id',
      ),
  };
}

/// The branch store's balance of one position, read through the repository.
Future<Quantity> branchStoreBalance(
  TestContext context,
  DistributionFixture fixture, {
  required String itemId,
  String? batchId,
}) => context.inventory.balanceQty(
  locationId: fixture.branchStore.id,
  itemId: itemId,
  batchId: batchId,
);

/// One room's balance of one position.
Future<Quantity> roomBalance(
  TestContext context,
  DistributionFixture fixture, {
  required String roomId,
  required String itemId,
  String? batchId,
}) => context.inventory.balanceQty(
  locationId: fixture.locationForRoom(roomId).id,
  itemId: itemId,
  batchId: batchId,
);
