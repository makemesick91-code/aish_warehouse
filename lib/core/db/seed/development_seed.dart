import 'package:flutter/foundation.dart';

import '../../../features/delivery/domain/repositories/delivery_order_repository.dart';
import '../../../features/delivery/domain/services/delivery_order_state_policy.dart';
import '../../../features/delivery/domain/use_cases/create_delivery_order_use_case.dart';
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
    bool? isDevelopmentBuild,
  }) : _opnameRepository = opnames,
       _isDevelopmentBuild = isDevelopmentBuild ?? !kReleaseMode;

  final MasterDataRepository _master;
  final InventoryRepository _inventory;
  final StockPostingService _posting;
  final OpnameRepository _opnameRepository;
  final PurchaseRequestRepository _requests;
  final DeliveryOrderRepository _deliveries;
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
  Future<String?> seedSubmittedPurchaseRequest() async {
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
