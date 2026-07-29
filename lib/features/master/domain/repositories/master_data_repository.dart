import '../../../../core/enums/app_enums.dart';
import '../models/master_models.dart';

/// Read/write access to master data, expressed in domain terms.
///
/// Business data is never hard deleted (G-A4/G-A5), so this contract offers no
/// delete operation at all — deactivation happens through `is_active`.
abstract interface class MasterDataRepository {
  // Idempotent writers: they return the existing row when the natural key is
  // already present, which is what makes the development seed re-runnable.
  Future<MasterBranch> ensureBranch({
    required String code,
    required String name,
    String? address,
  });

  Future<MasterRoom> ensureRoom({
    required String branchId,
    required String code,
    required String name,
  });

  Future<MasterUser> ensureUser({
    required String email,
    required String fullName,
    required UserRole role,
    String? branchId,
  });

  Future<MasterCategory> ensureCategory(String name);

  Future<MasterItem> ensureItem({
    required String sku,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    int expiryAlertDays,
  });

  Future<MasterBatch> ensureBatch({
    required String itemId,
    required String batchNo,
    required DateTime expiryDate,
  });

  Future<MasterLocation> ensureLocation({
    required StockLocationType type,
    required String name,
    String? branchId,
    String? roomId,
  });

  // Reads.
  Future<List<MasterBranch>> activeBranches();

  Future<List<MasterRoom>> activeRooms({String? branchId});

  Future<List<MasterCategory>> categories();

  Future<List<MasterItem>> activeItems();

  Future<List<MasterLocation>> stockLocations();

  Future<List<MasterUser>> activeUsers();

  Future<List<MasterItem>> searchItems(
    String query, {
    String? categoryId,
    int limit,
  });

  Future<MasterItem?> itemById(String id);

  Future<MasterBatch?> batchById(String id);

  Future<List<MasterBatch>> batchesOfItem(String itemId);

  Future<MasterLocation?> locationById(String id);

  Future<MasterLocation?> warehouseLocation();

  Future<MasterSummary> summary();
}
