import 'package:flutter/foundation.dart';

import '../../../features/inventory/domain/repositories/inventory_repository.dart';
import '../../../features/inventory/domain/services/stock_posting_service.dart';
import '../../../features/master/domain/models/master_models.dart';
import '../../../features/master/domain/repositories/master_data_repository.dart';
import '../../enums/app_enums.dart';

/// Definition of one seeded item plus its opening warehouse stock.
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
  final int openingQty;
  final List<_SeedBatch> batches;
}

class _SeedBatch {
  const _SeedBatch({
    required this.batchNo,
    required this.daysUntilExpiry,
    required this.qty,
  });

  final String batchNo;

  /// Relative to the seed run so the data stays meaningful over time.
  final int daysUntilExpiry;
  final int qty;
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
      openingQty: 0,
      batches: [
        _SeedBatch(batchNo: 'KMP-2401', daysUntilExpiry: 45, qty: 20),
        _SeedBatch(batchNo: 'KMP-2402', daysUntilExpiry: 210, qty: 30),
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
      openingQty: 0,
      batches: [
        _SeedBatch(batchNo: 'GIC-2311', daysUntilExpiry: 20, qty: 12),
        _SeedBatch(batchNo: 'GIC-2405', daysUntilExpiry: 365, qty: 24),
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
      openingQty: 0,
      batches: [_SeedBatch(batchNo: 'BND-2404', daysUntilExpiry: 150, qty: 18)],
    ),
    _SeedItem(
      sku: 'DEN-0004',
      name: 'Sarung Tangan Latex M',
      categoryName: 'Alat Sekali Pakai',
      unit: 'box',
      minStockRoom: 5,
      minStockBranch: 20,
      hasExpiry: false,
      openingQty: 120,
    ),
    _SeedItem(
      sku: 'DEN-0005',
      name: 'Suction Tip Disposable',
      categoryName: 'Alat Sekali Pakai',
      unit: 'pcs',
      minStockRoom: 50,
      minStockBranch: 200,
      hasExpiry: false,
      openingQty: 800,
    ),
    _SeedItem(
      sku: 'DEN-0006',
      name: 'Jarum Suntik Dental 27G',
      categoryName: 'Alat Sekali Pakai',
      unit: 'box',
      minStockRoom: 3,
      minStockBranch: 10,
      hasExpiry: false,
      openingQty: 60,
    ),
    _SeedItem(
      sku: 'DEN-0007',
      name: 'Anestesi Lokal Lidocaine 2%',
      categoryName: 'Obat',
      unit: 'ampul',
      minStockRoom: 10,
      minStockBranch: 40,
      hasExpiry: true,
      openingQty: 0,
      batches: [
        _SeedBatch(batchNo: 'LID-2403', daysUntilExpiry: 10, qty: 40),
        _SeedBatch(batchNo: 'LID-2407', daysUntilExpiry: 120, qty: 60),
        _SeedBatch(batchNo: 'LID-2412', daysUntilExpiry: 400, qty: 100),
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
      openingQty: 0,
      batches: [_SeedBatch(batchNo: 'CHX-2402', daysUntilExpiry: 75, qty: 25)],
    ),
    _SeedItem(
      sku: 'DEN-0009',
      name: 'Masker Bedah 3 Ply',
      categoryName: 'APD',
      unit: 'box',
      minStockRoom: 4,
      minStockBranch: 16,
      hasExpiry: false,
      openingQty: 150,
    ),
    _SeedItem(
      sku: 'DEN-0010',
      name: 'Face Shield',
      categoryName: 'APD',
      unit: 'pcs',
      minStockRoom: 3,
      minStockBranch: 10,
      hasExpiry: false,
      openingQty: 40,
    ),
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
          qty: spec.openingQty,
          actorUserId: warehouseUser.id,
        );
        continue;
      }

      final today = DateTime.now().toUtc();
      for (final batchSpec in spec.batches) {
        final batch = await _master.ensureBatch(
          itemId: item.id,
          batchNo: batchSpec.batchNo,
          expiryDate: DateTime.utc(
            today.year,
            today.month,
            today.day + batchSpec.daysUntilExpiry,
          ),
        );
        await _postOpeningStock(
          refDocId: 'seed-opening-${spec.sku}-${batchSpec.batchNo}',
          itemId: item.id,
          batchId: batch.id,
          locationId: warehouse.id,
          qty: batchSpec.qty,
          actorUserId: warehouseUser.id,
        );
      }
    }
  }

  /// Posts an opening balance exactly once. The stable `ref_doc_id` is what
  /// makes a second seed run a no-op instead of a duplicate.
  Future<void> _postOpeningStock({
    required String refDocId,
    required String itemId,
    String? batchId,
    required String locationId,
    required int qty,
    required String actorUserId,
  }) async {
    if (qty <= 0) return;

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
