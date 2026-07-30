import 'package:flutter/foundation.dart';

import '../../../features/delivery/domain/models/delivery_models.dart';
import '../../../features/delivery/domain/repositories/delivery_order_repository.dart';
import '../../../features/delivery/domain/services/delivery_expiry_policy.dart';
import '../../../features/delivery/domain/services/delivery_order_state_policy.dart';
import '../../../features/delivery/domain/services/delivery_warehouse_stock_reader.dart';
import '../../../features/delivery/domain/use_cases/build_fefo_delivery_allocation_use_case.dart';
import '../../../features/delivery/domain/use_cases/create_delivery_order_use_case.dart';
import '../../../features/delivery/domain/use_cases/ship_delivery_order_use_case.dart';
import '../../../features/distribution/domain/repositories/distribution_repository.dart';
import '../../../features/distribution/domain/services/distribution_branch_stock_reader.dart';
import '../../../features/distribution/domain/use_cases/add_distribution_item_use_case.dart';
import '../../../features/distribution/domain/use_cases/create_distribution_use_case.dart';
import '../../../features/distribution/domain/use_cases/post_distribution_use_case.dart';
import '../../../features/good_receipt/domain/repositories/good_receipt_repository.dart';
import '../../../features/good_receipt/domain/services/good_receipt_line_decision_policy.dart';
import '../../../features/good_receipt/domain/use_cases/create_good_receipt_use_case.dart';
import '../../../features/good_receipt/domain/use_cases/decide_good_receipt_line_use_cases.dart';
import '../../../features/good_receipt/domain/use_cases/post_good_receipt_use_case.dart';
import '../../../features/inventory/domain/repositories/inventory_repository.dart';
import '../../../features/inventory/domain/services/stock_posting_service.dart';
import '../../../features/master/domain/models/master_models.dart';
import '../../../features/master/domain/repositories/master_data_repository.dart';
import '../../../features/opname/domain/repositories/opname_repository.dart';
import '../../../features/opname/domain/use_cases/create_stock_opname_use_case.dart';
import '../../../features/opname/domain/use_cases/submit_stock_opname_use_case.dart';
import '../../../features/purchase_request/domain/repositories/purchase_request_repository.dart';
import '../../../features/purchase_request/domain/services/purchase_request_opname_eligibility_policy.dart';
import '../../../features/purchase_request/domain/use_cases/create_purchase_request_use_case.dart';
import '../../../features/purchase_request/domain/use_cases/submit_purchase_request_use_case.dart';
import '../../enums/app_enums.dart';
import '../../errors/failures.dart';
import '../../quantity/quantity.dart';
import '../../time/app_time_zone.dart';
import '../../time/date_only.dart';

/// Definition of one seeded item plus its opening warehouse stock.
///
/// Quantities are written the way a user would type them and go through
/// [Quantity.parse], which keeps the decimal seeds (`10.5`, `2.375`, `0.5`)
/// readable and exercises the same parser the UI uses.
class _SeedItem {
  const _SeedItem({
    required this.sku,
    required this.name,
    required this.categoryName,
    required this.unit,
    required this.minStockRoom,
    required this.minStockBranch,
    required this.hasExpiry,
    required this.openingQty,
    this.batches = const <_SeedBatch>[],
  });

  final String sku;
  final String name;
  final String categoryName;
  final String unit;
  final int minStockRoom;
  final int minStockBranch;
  final bool hasExpiry;

  /// Opening quantity for non-expiry items (batched items use [batches]).
  final String openingQty;
  final List<_SeedBatch> batches;
}

class _SeedBatch {
  const _SeedBatch({
    required this.batchNo,
    required this.daysUntilExpiry,
    required this.qty,
  });

  final String batchNo;

  /// Relative to the seed run so the data stays meaningful over time. A
  /// negative value seeds an already expired batch.
  final int daysUntilExpiry;
  final String qty;
}

/// Opening stock placed into one dental room, so a Stok Opname has something to
/// count from the first run (Milestone 2) and a Purchase Request has a real
/// deficiency to propose (Milestone 3).
class _SeedRoomStock {
  const _SeedRoomStock({
    required this.roomCode,
    required this.sku,
    this.batchNo,
    required this.qty,
  });

  /// `R1`, `R2` or `R3`.
  final String roomCode;

  final String sku;

  /// `null` for items without expiry.
  final String? batchNo;

  final String qty;
}

/// One Stok Opname the seed files so a Purchase Request has something to cite.
///
/// [weeksAgo] is what makes the G-P1 window demonstrable on a fresh install: 0 and
/// 1 are eligible, and 3 is deliberately too old to be chosen.
class _SeedOpname {
  const _SeedOpname({required this.roomCode, required this.weeksAgo});

  final String roomCode;
  final int weeksAgo;
}

/// Idempotent development seed.
///
/// Safe to run twice: master rows are created through `ensure*` (natural-key
/// lookup first) and opening balances are posted through
/// [StockPostingService.postInboundWarehouse] with a stable `ref_doc_id`, which
/// is checked before posting. Balances are therefore always backed by a ledger
/// entry — `stock_balances` is never written directly.
class DevelopmentSeed {
  DevelopmentSeed({
    required this._master,
    required this._inventory,
    required this._posting,
    required OpnameRepository opnames,
    required this._requests,
    required this._deliveries,
    required this._receipts,
    required this._distributions,
    bool? isDevelopmentBuild,
  }) : _opnameRepository = opnames,
       _isDevelopmentBuild = isDevelopmentBuild ?? !kReleaseMode;

  final MasterDataRepository _master;
  final InventoryRepository _inventory;
  final StockPostingService _posting;
  final OpnameRepository _opnameRepository;
  final PurchaseRequestRepository _requests;
  final DeliveryOrderRepository _deliveries;
  final GoodReceiptRepository _receipts;
  final DistributionRepository _distributions;
  final bool _isDevelopmentBuild;

  static const _categoryNames = <String>[
    'Bahan Tambal',
    'Alat Sekali Pakai',
    'Obat',
    'APD',
  ];

  static const _items = <_SeedItem>[
    _SeedItem(
      sku: 'DEN-0001',
      name: 'Komposit Universal A2',
      categoryName: 'Bahan Tambal',
      unit: 'tube',
      minStockRoom: 4,
      minStockBranch: 12,
      hasExpiry: true,
      openingQty: '0',
      batches: [
        _SeedBatch(batchNo: 'KMP-2401', daysUntilExpiry: 45, qty: '20'),
        _SeedBatch(batchNo: 'KMP-2402', daysUntilExpiry: 210, qty: '30'),
      ],
    ),
    _SeedItem(
      sku: 'DEN-0002',
      name: 'Glass Ionomer Cement',
      categoryName: 'Bahan Tambal',
      unit: 'botol',
      minStockRoom: 3,
      minStockBranch: 9,
      hasExpiry: true,
      openingQty: '0',
      batches: [
        _SeedBatch(batchNo: 'GIC-2311', daysUntilExpiry: 20, qty: '12'),
        _SeedBatch(batchNo: 'GIC-2405', daysUntilExpiry: 365, qty: '24'),
      ],
    ),
    _SeedItem(
      sku: 'DEN-0003',
      name: 'Bonding Agent',
      categoryName: 'Bahan Tambal',
      unit: 'botol',
      minStockRoom: 2,
      minStockBranch: 6,
      hasExpiry: true,
      openingQty: '0',
      // Three-decimal opening stock, so the dashboard shows `2.375 botol`.
      batches: [
        _SeedBatch(batchNo: 'BND-2404', daysUntilExpiry: 150, qty: '2.375'),
      ],
    ),
    _SeedItem(
      sku: 'DEN-0004',
      name: 'Sarung Tangan Latex M',
      categoryName: 'Alat Sekali Pakai',
      unit: 'box',
      minStockRoom: 5,
      minStockBranch: 20,
      hasExpiry: false,
      // Decimal opening stock: `10.5 box` on the development home page.
      openingQty: '10.5',
    ),
    _SeedItem(
      sku: 'DEN-0005',
      name: 'Suction Tip Disposable',
      categoryName: 'Alat Sekali Pakai',
      unit: 'pcs',
      minStockRoom: 50,
      minStockBranch: 200,
      hasExpiry: false,
      openingQty: '800',
    ),
    _SeedItem(
      sku: 'DEN-0006',
      name: 'Jarum Suntik Dental 27G',
      categoryName: 'Alat Sekali Pakai',
      unit: 'box',
      minStockRoom: 3,
      minStockBranch: 10,
      hasExpiry: false,
      openingQty: '60',
    ),
    _SeedItem(
      sku: 'DEN-0007',
      name: 'Anestesi Lokal Lidocaine 2%',
      categoryName: 'Obat',
      unit: 'ampul',
      minStockRoom: 10,
      minStockBranch: 40,
      hasExpiry: true,
      openingQty: '0',
      batches: [
        _SeedBatch(batchNo: 'LID-2403', daysUntilExpiry: 10, qty: '40'),
        _SeedBatch(batchNo: 'LID-2407', daysUntilExpiry: 120, qty: '60'),
        _SeedBatch(batchNo: 'LID-2412', daysUntilExpiry: 400, qty: '100'),
      ],
    ),
    _SeedItem(
      sku: 'DEN-0008',
      name: 'Antiseptik Chlorhexidine 0.2%',
      categoryName: 'Obat',
      unit: 'botol',
      minStockRoom: 4,
      minStockBranch: 12,
      hasExpiry: true,
      openingQty: '0',
      // Half-unit opening stock: `0.5 botol`.
      batches: [
        _SeedBatch(batchNo: 'CHX-2402', daysUntilExpiry: 75, qty: '0.5'),
        // Already expired. It carries no warehouse stock — expired goods may
        // not be received or shipped (G-E4) — but the batch itself must exist
        // so a Stok Opname can report the bottle still sitting in a room
        // (G-E7).
        _SeedBatch(batchNo: 'CHX-2301', daysUntilExpiry: -12, qty: '0'),
      ],
    ),
    _SeedItem(
      sku: 'DEN-0009',
      name: 'Masker Bedah 3 Ply',
      categoryName: 'APD',
      unit: 'box',
      minStockRoom: 4,
      minStockBranch: 16,
      hasExpiry: false,
      openingQty: '150',
    ),
    _SeedItem(
      sku: 'DEN-0010',
      name: 'Face Shield',
      categoryName: 'APD',
      unit: 'pcs',
      minStockRoom: 3,
      minStockBranch: 10,
      hasExpiry: false,
      openingQty: '40',
    ),
    // Milestone 4 demo material. `DEN-0011` is deliberately short in the
    // warehouse relative to what the rooms are missing, so the first Delivery
    // Order raised against a seeded request *has* to be partial (G-D2) — and the
    // second one completes it, which is what makes the automatic
    // `processing → shipped` transition (G-D5) demonstrable on a fresh install.
    _SeedItem(
      sku: 'DEN-0011',
      name: 'Cotton Roll',
      categoryName: 'Alat Sekali Pakai',
      unit: 'box',
      minStockRoom: 8,
      minStockBranch: 24,
      hasExpiry: false,
      // Three decimals, so the decimal shipment path is exercised end to end.
      openingQty: '2.375',
    ),
    // Four batches spanning every expiry case a Delivery Order has to handle:
    // one comfortably safe, one *nearer* expiry that FEFO must pick first, one
    // inside the 30-day alert window that needs an explicit confirmation (G-E4),
    // and one already expired that must never appear as a choice at all.
    _SeedItem(
      sku: 'DEN-0012',
      name: 'Kasa Steril Roll',
      categoryName: 'Alat Sekali Pakai',
      unit: 'roll',
      minStockRoom: 6,
      minStockBranch: 18,
      hasExpiry: true,
      openingQty: '0',
      batches: [
        // FEFO order: KSR-NEAR (12 days) → KSR-SOON (25) → KSR-SAFE (300).
        _SeedBatch(batchNo: 'KSR-SAFE', daysUntilExpiry: 300, qty: '10'),
        _SeedBatch(batchNo: 'KSR-SOON', daysUntilExpiry: 25, qty: '4'),
        _SeedBatch(batchNo: 'KSR-NEAR', daysUntilExpiry: 12, qty: '1.5'),
        // Expired, and holding stock on purpose: G-E4 must block it from a
        // shipment while an opname can still report it on the shelf (G-E7).
        _SeedBatch(batchNo: 'KSR-EXP', daysUntilExpiry: -8, qty: '3'),
      ],
    ),
  ];

  /// Opening stock of the three dental rooms, including decimal quantities and one
  /// expired batch, so the first Stok Opname has a realistic sheet to count and
  /// the first Purchase Request has a realistic deficiency to propose.
  ///
  /// The quantities are chosen against the par levels above so the demo exercises
  /// every branch of the suggestion formula (§14):
  ///
  /// * `DEN-0004` (par 5/room): R1 holds `4.5`, R2 holds `3` → deficiencies of
  ///   `0.5` and `2`, summed to a **decimal suggestion of `2.5 box`**.
  /// * `DEN-0005` (par 50/room): R1 holds `120`, comfortably above par → a
  ///   **zero-suggestion** position, which is what a manual request has to be made
  ///   against.
  /// * `DEN-0007` (par 10/room, batch-tracked): R2 holds two batches of `2` each,
  ///   so the batches must be **summed to `4` before** the par comparison, or the
  ///   suggestion would come out as `8 + 8` instead of `6`.
  /// * `DEN-0009` (par 4/room): R3 holds `1`, so the previous week's count of a
  ///   third room contributes as well.
  static const _roomStock = <_SeedRoomStock>[
    // Ruang Dental 1 — the sheet Milestone 2's form demonstrates.
    _SeedRoomStock(roomCode: 'R1', sku: 'DEN-0004', qty: '4.5'),
    _SeedRoomStock(roomCode: 'R1', sku: 'DEN-0005', qty: '120'),
    _SeedRoomStock(roomCode: 'R1', sku: 'DEN-0009', qty: '6'),
    _SeedRoomStock(
      roomCode: 'R1',
      sku: 'DEN-0001',
      batchNo: 'KMP-2402',
      qty: '3',
    ),
    _SeedRoomStock(
      roomCode: 'R1',
      sku: 'DEN-0007',
      batchNo: 'LID-2407',
      qty: '12.5',
    ),
    _SeedRoomStock(
      roomCode: 'R1',
      sku: 'DEN-0008',
      batchNo: 'CHX-2301',
      qty: '0.5',
    ),
    // Ruang Dental 2 — below par on two items, one of them across two batches.
    _SeedRoomStock(roomCode: 'R2', sku: 'DEN-0004', qty: '3'),
    _SeedRoomStock(
      roomCode: 'R2',
      sku: 'DEN-0007',
      batchNo: 'LID-2407',
      qty: '2',
    ),
    _SeedRoomStock(
      roomCode: 'R2',
      sku: 'DEN-0007',
      batchNo: 'LID-2412',
      qty: '2',
    ),
    // Ruang Dental 3 — the room whose count is a week old.
    _SeedRoomStock(roomCode: 'R3', sku: 'DEN-0009', qty: '1'),
    // Milestone 4: both rooms are well below par on the two shipment demo items,
    // so the suggested request asks for more than the warehouse can send at once.
    _SeedRoomStock(roomCode: 'R1', sku: 'DEN-0011', qty: '1'),
    _SeedRoomStock(roomCode: 'R2', sku: 'DEN-0011', qty: '0.5'),
    _SeedRoomStock(
      roomCode: 'R1',
      sku: 'DEN-0012',
      batchNo: 'KSR-SAFE',
      qty: '1',
    ),
  ];

  /// The counts the seed files, so `Buat Purchase Request` has eligible citations
  /// on a fresh install and the two-week window of G-P1 is visible.
  ///
  /// Two current-week counts from **different rooms**, one from the **previous**
  /// week, and one from three weeks ago that must *not* appear in the picker.
  static const _opnames = <_SeedOpname>[
    _SeedOpname(roomCode: 'R1', weeksAgo: 0),
    _SeedOpname(roomCode: 'R2', weeksAgo: 0),
    _SeedOpname(roomCode: 'R3', weeksAgo: 1),
    // Deliberately outside the window: the picker must not offer it.
    _SeedOpname(roomCode: 'R1', weeksAgo: 3),
  ];

  /// True when master data already exists, used by the UI to decide between the
  /// empty state and the data view.
  Future<bool> isSeeded() async {
    final summary = await _master.summary();
    return !summary.isEmpty;
  }

  Future<void> run() async {
    if (!_isDevelopmentBuild) {
      throw StateError(
        'Seed pengembangan tidak boleh dijalankan pada build produksi.',
      );
    }

    final branch = await _master.ensureBranch(
      code: 'CAB-01',
      name: 'Cabang Utama',
      address: 'Jl. Contoh No. 1',
    );

    final warehouse = await _master.ensureLocation(
      type: StockLocationType.warehouse,
      name: 'Warehouse Pusat',
    );
    await _master.ensureLocation(
      type: StockLocationType.branchStore,
      name: 'Gudang ${branch.name}',
      branchId: branch.id,
    );

    for (final roomSpec in const [
      ('R1', 'Ruang Dental 1'),
      ('R2', 'Ruang Dental 2'),
      ('R3', 'Ruang Dental 3'),
    ]) {
      final room = await _master.ensureRoom(
        branchId: branch.id,
        code: roomSpec.$1,
        name: roomSpec.$2,
      );
      await _master.ensureLocation(
        type: StockLocationType.room,
        name: room.name,
        branchId: branch.id,
        roomId: room.id,
      );
    }

    await _master.ensureUser(
      email: 'perawat@dev.local',
      fullName: 'Perawat Dev',
      role: UserRole.perawat,
      branchId: branch.id,
    );
    await _master.ensureUser(
      email: 'kacab@dev.local',
      fullName: 'Kepala Cabang Dev',
      role: UserRole.kepalaCabang,
      branchId: branch.id,
    );
    final warehouseUser = await _master.ensureUser(
      email: 'warehouse@dev.local',
      fullName: 'Petugas Warehouse Dev',
      role: UserRole.warehouse,
    );
    await _master.ensureUser(
      email: 'admin@dev.local',
      fullName: 'Super Admin Dev',
      role: UserRole.superAdmin,
    );

    final categories = <String, MasterCategory>{};
    for (final name in _categoryNames) {
      categories[name] = await _master.ensureCategory(name);
    }

    for (final spec in _items) {
      final item = await _master.ensureItem(
        sku: spec.sku,
        name: spec.name,
        categoryId: categories[spec.categoryName]!.id,
        unit: spec.unit,
        minStockRoom: spec.minStockRoom,
        minStockBranch: spec.minStockBranch,
        hasExpiry: spec.hasExpiry,
      );

      if (!spec.hasExpiry) {
        await _postOpeningStock(
          refDocId: 'seed-opening-${spec.sku}',
          itemId: item.id,
          locationId: warehouse.id,
          qty: Quantity.parse(spec.openingQty),
          actorUserId: warehouseUser.id,
        );
        continue;
      }

      // Expiry dates are civil dates counted from the operational day, so a
      // seed run close to midnight cannot land on yesterday's date (T-3/T-8).
      final today = AppTimeZone.operationalDate(DateTime.now().toUtc());
      for (final batchSpec in spec.batches) {
        final batch = await _master.ensureBatch(
          itemId: item.id,
          batchNo: batchSpec.batchNo,
          expiryDate: DateOnly.addDays(today, batchSpec.daysUntilExpiry),
        );
        await _postOpeningStock(
          refDocId: 'seed-opening-${spec.sku}-${batchSpec.batchNo}',
          itemId: item.id,
          batchId: batch.id,
          locationId: warehouse.id,
          qty: Quantity.parse(batchSpec.qty),
          actorUserId: warehouseUser.id,
          // An already-expired batch cannot be *received* — inbound refuses it
          // (G-E4) — but it can perfectly well be sitting on the warehouse shelf,
          // because it was in date when it arrived. The seed has one clock, so it
          // cannot replay that history; it states the resulting balance through an
          // adjustment instead, which is the path G-E4 does not block and O-7
          // exists for. The point of the position is that a Delivery Order must
          // refuse it while it is still visibly there.
          alreadyExpired: batchSpec.daysUntilExpiry < 0,
        );
      }
    }

    await _seedRoomStock(actorUserId: warehouseUser.id);
    await _seedOpnames();
  }

  /// Places opening stock in the three dental rooms so Stok Opname has something
  /// to count on a fresh install, and Purchase Request has a deficiency to
  /// propose.
  ///
  /// Posted through [StockPostingService.postOpnameAdjustment] rather than a
  /// transfer from the warehouse: a transfer refuses expired batches (G-E4),
  /// and one of the seeded positions is deliberately expired — that is exactly
  /// the case an opname has to be able to surface (G-E7). The adjustment path
  /// is the one that accepts it, and it writes a real ledger movement either
  /// way, so `stock_balances` is still never touched directly.
  Future<void> _seedRoomStock({required String actorUserId}) async {
    for (final spec in _roomStock) {
      final refDocId =
          'seed-room-${spec.roomCode}-${spec.sku}-${spec.batchNo ?? 'nobatch'}';
      final existing = await _inventory.movementsByRef(
        refDocType: RefDocType.seed,
        refDocId: refDocId,
      );
      if (existing.isNotEmpty) continue;

      final item = await _findItemBySku(spec.sku);
      if (item == null) continue;

      final roomLocation = await _roomLocationByCode(spec.roomCode);
      if (roomLocation == null) continue;

      String? batchId;
      if (spec.batchNo != null) {
        final batches = await _master.batchesOfItem(item.id);
        final match = batches.where((b) => b.batchNo == spec.batchNo);
        if (match.isEmpty) continue;
        batchId = match.first.id;
      }

      await _posting.postOpnameAdjustment(
        locationId: roomLocation.id,
        itemId: item.id,
        batchId: batchId,
        countedQty: Quantity.parse(spec.qty),
        actorUserId: actorUserId,
        refDocType: RefDocType.seed,
        refDocId: refDocId,
        note: 'Saldo awal ruangan seed pengembangan',
      );
    }
  }

  /// The stock location of one dental room, by room code.
  Future<MasterLocation?> _roomLocationByCode(String roomCode) async {
    final rooms = await _master.activeRooms();
    final match = rooms.where((room) => room.code == roomCode);
    if (match.isEmpty) return null;
    return _master.activeRoomLocation(match.first.id);
  }

  /// Files the Stok Opname documents a Purchase Request can cite (§28).
  ///
  /// Each count is created through the real use case with an **injected clock**, so
  /// the ISO period it lands in is the operational week [_SeedOpname.weeksAgo] weeks
  /// back rather than whatever week the seed happens to run in. That is what makes
  /// the G-P1 window demonstrable: two counts inside it, one at its edge, and one
  /// outside it that the picker must refuse to offer.
  ///
  /// Idempotent by the same mechanism the rest of the seed uses — G-O1 already
  /// permits one live count per room per week, so a second run is refused by
  /// [StockOpnameAlreadyExistsFailure] and skipped rather than duplicated.
  ///
  /// `counted_qty` is left equal to the snapshotted `system_qty`, which is what the
  /// create use case fills in. That keeps every line difference-free, so G-O3 asks
  /// for no explanatory notes and the submit goes through unattended — and it is
  /// also the honest reading of a seeded count: nobody physically walked the shelf.
  Future<void> _seedOpnames() async {
    final users = await _master.activeUsers();
    final nurses = users.where((user) => user.role == UserRole.perawat);
    if (nurses.isEmpty) return;
    final nurse = nurses.first;

    final rooms = await _master.activeRooms();

    for (final spec in _opnames) {
      final match = rooms.where((room) => room.code == spec.roomCode);
      if (match.isEmpty) continue;

      // A clock pinned [weeksAgo] operational weeks back. `AppTimeZone` resolves
      // the ISO week from it, so the document is filed under the right period
      // without the seed doing any week arithmetic of its own (T-3).
      DateTime clock() => DateOnly.addDays(
        AppTimeZone.operationalDate(DateTime.now().toUtc()),
        -7 * spec.weeksAgo,
      ).add(const Duration(hours: 4));

      try {
        final opname = await CreateStockOpnameUseCase(
          opnames: _opnameRepository,
          master: _master,
          inventory: _inventory,
          clock: clock,
        ).call(actorUserId: nurse.id, roomId: match.first.id);

        await SubmitStockOpnameUseCase(
          opnames: _opnameRepository,
          master: _master,
          clock: clock,
        ).call(actorUserId: nurse.id, opnameId: opname.id);
      } on StockOpnameAlreadyExistsFailure {
        // Already seeded, or the room was genuinely counted this week. Either way
        // there is nothing to add.
        continue;
      } on EmptyStockOpnameFailure {
        // The room holds no stock at all, so there is no sheet to submit. Not an
        // error: it just means this room has nothing to cite yet.
        continue;
      }
    }
  }

  /// Sends one Purchase Request, for demonstrating the warehouse queue.
  ///
  /// **Deliberately not part of [run].** A seeded `submitted` request would occupy
  /// the branch's single active-order slot (G-P4), so the very first thing a
  /// developer tries — *Buat Purchase Request* → *Kirim ke Warehouse* — would be
  /// refused on a fresh install. This is opt-in for when the warehouse side is what
  /// needs demonstrating.
  ///
  /// Returns the request id, or `null` when there is nothing eligible to cite or
  /// the branch already has an active order.
  ///
  /// [clock] backdates the whole chain, which the Good Receipt demo needs: a
  /// shipment cannot be stamped before the request it belongs to was submitted, so
  /// demonstrating a 2×24 hour overdue receipt (G-G6) means submitting the request in
  /// the past too.
  Future<String?> seedSubmittedPurchaseRequest({
    DateTime Function()? clock,
  }) async {
    if (!_isDevelopmentBuild) {
      throw StateError(
        'Seed pengembangan tidak boleh dijalankan pada build produksi.',
      );
    }

    final users = await _master.activeUsers();
    final heads = users.where((user) => user.role == UserRole.kepalaCabang);
    if (heads.isEmpty) return null;
    final head = heads.first;
    final branchId = head.branchId;
    if (branchId == null) return null;

    if (await _requests.activeRequestForBranch(branchId) != null) return null;

    final eligible = await _requests.eligibleOpnames(
      branchId: branchId,
      periods:
          PurchaseRequestOpnameEligibilityPolicy.eligiblePeriods(
                DateTime.now().toUtc(),
              )
              .map((week) => (year: week.year, week: week.week))
              .toList(growable: false),
    );
    if (eligible.isEmpty) return null;

    final request =
        await CreatePurchaseRequestUseCase(
          requests: _requests,
          master: _master,
          clock: clock,
        ).call(
          actorUserId: head.id,
          selectedOpnameIds: eligible
              .map((reference) => reference.opnameId)
              .toList(growable: false),
          neededDate: DateOnly.addDays(
            AppTimeZone.operationalDate(DateTime.now().toUtc()),
            7,
          ),
          note: 'Permintaan demo seed pengembangan',
        );

    await SubmitPurchaseRequestUseCase(
      requests: _requests,
      master: _master,
      clock: clock,
    ).call(actorUserId: head.id, prId: request.id);

    return request.id;
  }

  /// Prepares one Delivery Order against the branch's active request, for
  /// demonstrating the shipment screens.
  ///
  /// **Deliberately not part of [run]**, for the same reason
  /// [seedSubmittedPurchaseRequest] is not: creating a document moves the request
  /// to `processing`, and a developer's first walk through *Buat PR → Kirim ke
  /// Warehouse → Mulai Proses* would then find the work already done. This is
  /// opt-in for when the delivery side is what needs demonstrating.
  ///
  /// The document is left in `preparing` **without allocations**, and it is not
  /// shipped. Shipping it here would take stock out of the warehouse before anybody
  /// looked at the FEFO screen, and the batch balances the demo exists to show are
  /// exactly what the shipment would consume.
  ///
  /// Returns the Delivery Order id, or `null` when there is no request in a state a
  /// shipment may be raised against (G-D1).
  Future<String?> seedPreparingDeliveryOrder() async {
    if (!_isDevelopmentBuild) {
      throw StateError(
        'Seed pengembangan tidak boleh dijalankan pada build produksi.',
      );
    }

    final users = await _master.activeUsers();
    final officers = users.where((user) => user.role == UserRole.warehouse);
    final heads = users.where((user) => user.role == UserRole.kepalaCabang);
    if (officers.isEmpty || heads.isEmpty) return null;

    final branchId = heads.first.branchId;
    if (branchId == null) return null;

    final request = await _requests.activeRequestForBranch(branchId);
    if (request == null) return null;
    if (!DeliveryOrderStatePolicy.canCreateFrom(request.status)) return null;

    // Idempotent by the same mechanism the rest of the seed uses: a second run
    // finds the document it created last time and adds nothing.
    final existing = await _deliveries.listByPurchaseRequest(request.id);
    if (existing.isNotEmpty) return existing.first.id;

    final order =
        await CreateDeliveryOrderUseCase(
          deliveries: _deliveries,
          requests: _requests,
          master: _master,
        ).call(
          actorUserId: officers.first.id,
          purchaseRequestId: request.id,
          note: 'Surat Jalan demo seed pengembangan',
        );
    return order.id;
  }

  /// Ships one Delivery Order [age] in the past, so the Good Receipt screens have a
  /// real shipment to check in — and so G-G6's 2×24 hour reminder is demonstrable
  /// without waiting two days.
  ///
  /// **Deliberately not part of [run]**, for the reason
  /// [seedPreparingDeliveryOrder] gives: shipping takes stock out of the warehouse,
  /// and a developer's first walk through *Alokasikan FEFO → Kirim* would otherwise
  /// find the work already done.
  ///
  /// The **whole chain** is stamped at one backdated instant — request created,
  /// submitted, taken on, document raised, shipment posted — because the timestamp
  /// policy refuses a shipment that predates the request it belongs to (§36). Doing
  /// only the last step in the past would fail, which is exactly the check working.
  /// The default of 60 hours puts the shipment past its deadline; pass a smaller
  /// [age] for a receipt that is merely due.
  ///
  /// Idempotent by the same mechanism the rest of the seed uses: a second run finds
  /// the shipment it created last time and adds nothing. Returns the Delivery Order
  /// id, or `null` when there is nothing to raise a shipment against.
  Future<String?> seedShippedDeliveryOrder({
    Duration age = const Duration(hours: 60),
  }) async {
    _requireDevelopmentBuild();

    final users = await _master.activeUsers();
    final officers = users.where((user) => user.role == UserRole.warehouse);
    final heads = users.where((user) => user.role == UserRole.kepalaCabang);
    if (officers.isEmpty || heads.isEmpty) return null;
    final branchId = heads.first.branchId;
    if (branchId == null) return null;

    // Already shipped by an earlier run? Reuse it rather than shipping a second
    // document out of a warehouse the demo has already drawn down.
    final shipped = await _shippedOrderForBranch(branchId);
    if (shipped != null) return shipped;

    final shippedAt = DateTime.now().toUtc().subtract(age);
    // One hour before the shipment, so `shipped_at >= created_at` holds by a real
    // margin rather than by microseconds.
    final preparedAt = shippedAt.subtract(const Duration(hours: 1));
    DateTime prepared() => preparedAt;

    var request = await _requests.activeRequestForBranch(branchId);
    if (request == null) {
      final prId = await seedSubmittedPurchaseRequest(clock: prepared);
      if (prId == null) return null;
      request = await _requests.getById(prId);
      if (request == null) return null;
    }
    if (!DeliveryOrderStatePolicy.canCreateFrom(request.status)) return null;

    final order =
        await CreateDeliveryOrderUseCase(
          deliveries: _deliveries,
          requests: _requests,
          master: _master,
          clock: prepared,
        ).call(
          actorUserId: officers.first.id,
          purchaseRequestId: request.id,
          note: 'Surat Jalan demo Good Receipt',
        );

    final stock = DeliveryWarehouseStockReader(_inventory);
    await BuildFefoDeliveryAllocationUseCase(
      deliveries: _deliveries,
      master: _master,
      stock: stock,
      clock: prepared,
    ).call(actorUserId: officers.first.id, deliveryOrderId: order.id);

    // Nothing to send — every requested position is out of stock — leaves the
    // document `preparing` rather than failing the seed. The screens still have
    // something to show, and a developer sees why.
    final allocations = await _deliveries.lineReferences(order.id);
    if (allocations.isEmpty) return order.id;

    // FEFO consumes the nearest-expiry batch first, and several of the seeded batches
    // are inside their alert window — which G-E4 will not ship without an explicit
    // confirmation. Recording it here is exactly what a warehouse officer does on the
    // allocation screen; skipping it would make the seed fail on a rule that is working.
    // The receipt then has to *reject* those positions under G-E5, which is precisely
    // the case the demo exists to show.
    await _confirmNearExpiryAllocations(
      allocations: allocations,
      nowUtc: shippedAt,
    );

    await ShipDeliveryOrderUseCase(
      deliveries: _deliveries,
      requests: _requests,
      master: _master,
      posting: _postingAt(shippedAt),
      stock: stock,
      clock: () => shippedAt,
    ).call(actorUserId: officers.first.id, deliveryOrderId: order.id);

    return order.id;
  }

  /// Ticks the near-expiry confirmation on every allocation that needs one (G-E4).
  ///
  /// Judged at [nowUtc] rather than at the wall clock, so a backdated shipment is
  /// confirmed against the shelf life it actually had when it left.
  Future<void> _confirmNearExpiryAllocations({
    required List<DeliveryLineReference> allocations,
    required DateTime nowUtc,
  }) async {
    for (final allocation in allocations) {
      final batchId = allocation.batchId;
      if (batchId == null) continue;

      final batch = await _master.batchById(batchId);
      final item = await _master.itemById(allocation.itemId);
      if (batch == null || item == null) continue;
      if (!DeliveryExpiryPolicy.requiresNearExpiryConfirmation(
        expiryDate: batch.expiryDate,
        expiryAlertDays: item.expiryAlertDays,
        nowUtc: nowUtc,
      )) {
        continue;
      }

      await _deliveries.updatePreparingLine(
        lineId: allocation.id,
        shippedQty: allocation.shippedQty,
        batchId: batchId,
        fefoOverrideReason: allocation.fefoOverrideReason,
        nearExpiryConfirmed: true,
        nearExpiryNote: 'Dikonfirmasi pada seed pengembangan',
      );
    }
  }

  /// Creates a `checking` Good Receipt for the seeded shipment, so the checklist has
  /// something to open (§37).
  ///
  /// Opt-in and idempotent: a shipment that already has a receipt returns it. Nothing
  /// about stock happens — the branch is credited when the receipt is *posted*
  /// (spec §2.5). Returns the receipt id, or `null` when there is no shipment to
  /// check in.
  Future<String?> seedCheckingGoodReceipt() async {
    _requireDevelopmentBuild();

    final users = await _master.activeUsers();
    final heads = users.where((user) => user.role == UserRole.kepalaCabang);
    if (heads.isEmpty) return null;
    final head = heads.first;
    final branchId = head.branchId;
    if (branchId == null) return null;

    // A receipt this seed created on an earlier run — whatever status it reached. Looked
    // up before anything is built, because posting one moves its shipment to `received`
    // and the "awaiting" lookup below would then miss it and start a second chain.
    final previous = await _existingReceiptForBranch(branchId);
    if (previous != null) return previous;

    final doId =
        await _shippedOrderForBranch(branchId) ??
        await seedShippedDeliveryOrder();
    if (doId == null) return null;

    final existing = await _receipts.findByDeliveryOrder(doId);
    if (existing != null) return existing.id;

    final receipt = await CreateGoodReceiptUseCase(
      receipts: _receipts,
      deliveries: _deliveries,
      requests: _requests,
      master: _master,
    ).call(actorUserId: head.id, deliveryOrderId: doId);
    return receipt.id;
  }

  /// Decides every position of the seeded receipt and posts it, producing **both**
  /// shapes of discrepancy the warehouse queue reports (§17/§37).
  ///
  /// The pattern is chosen so the queue is never empty and never one-sided:
  ///
  /// * the first position is accepted **short** — a `checked` line whose received
  ///   quantity is below what was shipped, which is a *shortage* (G-G3);
  /// * the second, when there is one, is **refused** — a `rejected` line, which is a
  ///   *return* (G-G4/G-G5);
  /// * everything else is accepted in full.
  ///
  /// The branch's opening balance therefore arrives **through the ledger** — a real
  /// `good_receipt` movement per accepted position — and never by writing
  /// `stock_balances`, which is the rule the production code follows (G-A1).
  ///
  /// A position G-E5 refuses is rejected rather than accepted, whatever its place in
  /// the order: the seed obeys the same rule the screens do.
  ///
  /// Returns the receipt id, or `null` when there is nothing to post.
  Future<String?> seedPostedGoodReceipt() async {
    _requireDevelopmentBuild();

    final users = await _master.activeUsers();
    final heads = users.where((user) => user.role == UserRole.kepalaCabang);
    if (heads.isEmpty) return null;
    final head = heads.first;

    final grId = await seedCheckingGoodReceipt();
    if (grId == null) return null;

    final receipt = await _receipts.getById(grId);
    if (receipt == null) return null;
    // Already posted by an earlier run.
    if (receipt.isPosted) return grId;

    final detail = await _receipts.getDetail(grId);
    if (detail == null || detail.lines.isEmpty) return null;

    final check = CheckGoodReceiptLineUseCase(
      receipts: _receipts,
      master: _master,
    );
    final reject = RejectGoodReceiptLineUseCase(
      receipts: _receipts,
      master: _master,
    );

    final nowUtc = DateTime.now().toUtc();

    // G-E5 comes first and is not negotiable: an expired or nearly expired batch must be
    // refused, and the seed is not exempt from a rule the screens enforce. The demo
    // pattern is then applied to what is *left*, so a delivery that happens to be all
    // near-expiry still produces a valid receipt rather than a shortage that G-E5 would
    // have refused anyway.
    final mustReject = detail.lines
        .where((line) => line.mustBeRejectedOn(nowUtc))
        .toList(growable: false);
    final acceptable = detail.lines
        .where((line) => !line.mustBeRejectedOn(nowUtc))
        .toList(growable: false);

    for (final line in mustReject) {
      await reject.call(
        actorUserId: head.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        reason: GoodReceiptLineDecisionPolicy.composeReason(
          preset: GoodReceiptRejectReasonPreset.expired,
          detail: 'Batch terlalu dekat kedaluwarsa saat diterima',
        ),
      );
    }

    for (var index = 0; index < acceptable.length; index += 1) {
      final line = acceptable[index];
      // The second acceptable position is refused, so the queue has a *return* to show
      // even when nothing was near its expiry date. When there is only one, the expiry
      // refusals above already provide it.
      if (index == 1) {
        await reject.call(
          actorUserId: head.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          reason: GoodReceiptLineDecisionPolicy.composeReason(
            preset: GoodReceiptRejectReasonPreset.damaged,
            detail: 'Kemasan rusak saat diterima (demo seed)',
          ),
        );
        continue;
      }
      // The first accepted position arrives short, so the queue has a shortage to show.
      // Halved in exact fixed point, so a `1` box becomes `0.5` rather than a
      // floating-point approximation of it (Q-2).
      await check.call(
        actorUserId: head.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        receivedQty: index == 0
            ? line.shippedQty.scaledBy(numerator: 1, denominator: 2)
            : line.shippedQty,
      );
    }

    await PostGoodReceiptUseCase(
      receipts: _receipts,
      deliveries: _deliveries,
      requests: _requests,
      master: _master,
      posting: _posting,
    ).call(actorUserId: head.id, goodReceiptId: grId);

    return grId;
  }

  /// Creates a `draft` Distribusi with lines for **two** rooms, so the multi-room form
  /// has something real to open (§35, G-T3).
  ///
  /// Opt-in and idempotent: a branch that already has a distribution returns it,
  /// whatever status it reached, so a second run is a no-op rather than the start of a
  /// second chain.
  ///
  /// The branch store is stocked first by posting the seeded Good Receipt — which is the
  /// only path that credits it (spec §2.5) — so the balances this draft draws on arrive
  /// **through the ledger** and never by writing `stock_balances`. If there is nothing to
  /// receive, there is nothing to distribute either, and this returns `null` rather than
  /// inventing stock.
  ///
  /// Quantities are deliberately modest: the demo must leave stock on the shelf, because
  /// an emptied store makes every other screen look broken. Each room is asked for a
  /// *quarter* of what the store holds of the item, in exact fixed point (Q-2), and any
  /// position that rounds to nothing is skipped.
  ///
  /// Nothing about stock happens here — a draft is an intention, and the balances move
  /// when it is posted (§18).
  Future<String?> seedDraftDistribution() async {
    _requireDevelopmentBuild();

    final users = await _master.activeUsers();
    final heads = users.where((user) => user.role == UserRole.kepalaCabang);
    if (heads.isEmpty) return null;
    final head = heads.first;
    final branchId = head.branchId;
    if (branchId == null) return null;

    final previous = await _existingDistributionForBranch(branchId);
    if (previous != null) return previous;

    // The branch store's only legitimate source of stock (spec §2.5).
    await seedPostedGoodReceipt();

    final stores = await _master.activeBranchStoreLocations(branchId);
    if (stores.length != 1) return null;
    final store = stores.single;

    final rooms = await _distributions.branchRooms(branchId);
    if (rooms.isEmpty) return null;

    final nowUtc = DateTime.now().toUtc();
    final available = await _distributions.searchBranchStock(
      branchStoreLocationId: store.id,
      nowUtc: nowUtc,
      // Enough to cover both a batch-tracked and a plain item when the receipt
      // credited several.
      limit: 4,
    );
    if (available.isEmpty) return null;

    final distribution = await CreateDistributionUseCase(
      distributions: _distributions,
      master: _master,
    ).call(actorUserId: head.id, note: 'Distribusi demo seed pengembangan');

    final add = AddDistributionItemUseCase(
      distributions: _distributions,
      master: _master,
    );
    // Two rooms, so the grouping G-T3 produces is visible on a fresh install. A third
    // would only repeat the point and drain more stock.
    final targets = rooms.take(2).toList(growable: false);
    for (final item in available.take(2)) {
      for (final room in targets) {
        // A quarter each, truncated towards zero — so two rooms take at most half and
        // the store keeps a working balance.
        final share = item.availableQty.scaledBy(numerator: 1, denominator: 4);
        if (!share.isPositive) continue;
        try {
          await add.call(
            actorUserId: head.id,
            distributionId: distribution.id,
            roomId: room.id,
            itemId: item.itemId,
            requestedQty: share,
          );
        } on AppFailure {
          // A seed must never be the reason a fresh install fails to open. Anything the
          // rules refuse — a room without a location, a batch that expired between the
          // read and the write — is simply left off the demo document.
          continue;
        }
      }
    }

    final detail = await _distributions.getDetail(distribution.id);
    if (detail == null || detail.isEmpty) return null;
    return distribution.id;
  }

  /// Posts the seeded Distribusi, so a fresh install has a read-only document *and* room
  /// balances that arrived the way real ones do (§35).
  ///
  /// Goes through [PostDistributionUseCase] rather than mutating balances: every rule the
  /// screens enforce applies to the seed too, and the room stock it produces is backed by
  /// real `distribution` movements (G-A1). Returns the document id, or `null` when there
  /// is nothing to post.
  ///
  /// Deliberately **not** called by [run]. A fresh install should show both shapes — a
  /// draft to continue and a posted document to read — and posting the only draft would
  /// leave the form with nothing to open. The two seeds are separate opt-in steps, and
  /// this one creates its own draft when the earlier one has already been posted.
  Future<String?> seedPostedDistribution() async {
    _requireDevelopmentBuild();

    final users = await _master.activeUsers();
    final heads = users.where((user) => user.role == UserRole.kepalaCabang);
    if (heads.isEmpty) return null;
    final head = heads.first;

    final distributionId = await seedDraftDistribution();
    if (distributionId == null) return null;

    final distribution = await _distributions.getById(distributionId);
    if (distribution == null) return null;
    // Already posted by an earlier run.
    if (distribution.isPosted) return distributionId;

    await PostDistributionUseCase(
      distributions: _distributions,
      master: _master,
      posting: _posting,
      stock: DistributionBranchStockReader(_inventory),
    ).call(actorUserId: head.id, distributionId: distributionId);

    return distributionId;
  }

  /// The id of any Distribusi this branch already has, or `null`.
  ///
  /// Read through the branch-scoped list so it cannot report another branch's document,
  /// and status-agnostic so a *posted* one still counts as "already seeded" — which is
  /// what makes a second run a no-op.
  Future<String?> _existingDistributionForBranch(String branchId) async {
    final rows = await _distributions.listForBranch(branchId: branchId);
    return rows.isEmpty ? null : rows.first.id;
  }

  /// The id of any Good Receipt this branch already has, or `null`.
  ///
  /// Read through the branch-scoped list so it cannot report another branch's document,
  /// and status-agnostic so a *posted* receipt still counts as "already seeded" — which is
  /// what makes a second run a no-op rather than the start of a second chain.
  Future<String?> _existingReceiptForBranch(String branchId) async {
    final receipts = await _receipts.listForBranch(branchId: branchId);
    return receipts.isEmpty ? null : receipts.first.id;
  }

  /// The branch's most recent `shipped` Delivery Order, or `null`.
  Future<String?> _shippedOrderForBranch(String branchId) async {
    final orders = await _deliveries.listForWarehouse(
      DeliveryOrderFilter(
        branchId: branchId,
        statuses: const {DeliveryOrderStatus.shipped},
      ),
    );
    return orders.isEmpty ? null : orders.first.id;
  }

  /// A posting service on the same repositories but with a different notion of
  /// "now", so a backdated shipment judges expiry against the day it was sent.
  StockPostingService _postingAt(DateTime instant) => StockPostingService(
    inventory: _inventory,
    master: _master,
    clock: () => instant,
  );

  void _requireDevelopmentBuild() {
    if (_isDevelopmentBuild) return;
    throw StateError(
      'Seed pengembangan tidak boleh dijalankan pada build produksi.',
    );
  }

  Future<MasterItem?> _findItemBySku(String sku) async {
    final items = await _master.activeItems();
    final match = items.where((item) => item.sku == sku);
    return match.isEmpty ? null : match.first;
  }

  /// Posts an opening balance exactly once. The stable `ref_doc_id` is what
  /// makes a second seed run a no-op instead of a duplicate.
  Future<void> _postOpeningStock({
    required String refDocId,
    required String itemId,
    String? batchId,
    required String locationId,
    required Quantity qty,
    required String actorUserId,
    bool alreadyExpired = false,
  }) async {
    if (!qty.isPositive) return;

    final existing = await _inventory.movementsByRef(
      refDocType: RefDocType.seed,
      refDocId: refDocId,
    );
    if (existing.isNotEmpty) return;

    if (alreadyExpired) {
      await _posting.postOpnameAdjustment(
        locationId: locationId,
        itemId: itemId,
        batchId: batchId,
        countedQty: qty,
        actorUserId: actorUserId,
        refDocType: RefDocType.seed,
        refDocId: refDocId,
        note: 'Saldo awal seed pengembangan (batch kedaluwarsa di rak)',
      );
      return;
    }

    await _posting.postInboundWarehouse(
      itemId: itemId,
      batchId: batchId,
      toLocationId: locationId,
      qty: qty,
      actorUserId: actorUserId,
      refDocType: RefDocType.seed,
      refDocId: refDocId,
      note: 'Saldo awal seed pengembangan',
    );
  }
}
