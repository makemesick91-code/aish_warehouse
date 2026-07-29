import 'package:flutter/foundation.dart';

import '../../../features/inventory/domain/repositories/inventory_repository.dart';
import '../../../features/inventory/domain/services/stock_posting_service.dart';
import '../../../features/master/domain/models/master_models.dart';
import '../../../features/master/domain/repositories/master_data_repository.dart';
import '../../enums/app_enums.dart';
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

/// Opening stock placed into "Ruang Dental 1", so a Stok Opname has something
/// to count from the first run (Milestone 2).
class _SeedRoomStock {
  const _SeedRoomStock({required this.sku, this.batchNo, required this.qty});

  final String sku;

  /// `null` for items without expiry.
  final String? batchNo;

  final String qty;
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
    bool? isDevelopmentBuild,
  }) : _isDevelopmentBuild = isDevelopmentBuild ?? !kReleaseMode;

  final MasterDataRepository _master;
  final InventoryRepository _inventory;
  final StockPostingService _posting;
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
  ];

  /// Opening stock of Ruang Dental 1, including decimal quantities and one
  /// expired batch, so the first Stok Opname has a realistic sheet to count.
  static const _roomStock = <_SeedRoomStock>[
    _SeedRoomStock(sku: 'DEN-0004', qty: '4.5'),
    _SeedRoomStock(sku: 'DEN-0005', qty: '120'),
    _SeedRoomStock(sku: 'DEN-0009', qty: '6'),
    _SeedRoomStock(sku: 'DEN-0001', batchNo: 'KMP-2402', qty: '3'),
    _SeedRoomStock(sku: 'DEN-0007', batchNo: 'LID-2407', qty: '12.5'),
    _SeedRoomStock(sku: 'DEN-0008', batchNo: 'CHX-2301', qty: '0.5'),
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

    MasterLocation? firstRoomLocation;
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
      final location = await _master.ensureLocation(
        type: StockLocationType.room,
        name: room.name,
        branchId: branch.id,
        roomId: room.id,
      );
      firstRoomLocation ??= location;
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
        );
      }
    }

    await _seedRoomStock(
      roomLocation: firstRoomLocation!,
      actorUserId: warehouseUser.id,
    );
  }

  /// Places opening stock in Ruang Dental 1 so Stok Opname has something to
  /// count on a fresh install.
  ///
  /// Posted through [StockPostingService.postOpnameAdjustment] rather than a
  /// transfer from the warehouse: a transfer refuses expired batches (G-E4),
  /// and one of the seeded positions is deliberately expired — that is exactly
  /// the case an opname has to be able to surface (G-E7). The adjustment path
  /// is the one that accepts it, and it writes a real ledger movement either
  /// way, so `stock_balances` is still never touched directly.
  Future<void> _seedRoomStock({
    required MasterLocation roomLocation,
    required String actorUserId,
  }) async {
    for (final spec in _roomStock) {
      final refDocId = 'seed-room-${spec.sku}-${spec.batchNo ?? 'nobatch'}';
      final existing = await _inventory.movementsByRef(
        refDocType: RefDocType.seed,
        refDocId: refDocId,
      );
      if (existing.isNotEmpty) continue;

      final item = await _findItemBySku(spec.sku);
      if (item == null) continue;

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
  }) async {
    if (!qty.isPositive) return;

    final existing = await _inventory.movementsByRef(
      refDocType: RefDocType.seed,
      refDocId: refDocId,
    );
    if (existing.isNotEmpty) return;

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
