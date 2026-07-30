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

  // Master lookups come in two flavours, and calling the wrong one is a bug in
  // opposite directions — hence two named methods rather than one with a
  // boolean (§7.4):
  //
  // * `active…` — for **new** work (create a document, add a line). Refuses
  //   soft-deleted rows, and the caller additionally refuses inactive ones.
  //   Loosening these is how a nurse starts a count against a room that no
  //   longer exists.
  // * `historical…` — for **completing** work that already exists (read or
  //   review a `submitted` document). Returns soft-deleted rows too, because
  //   the document cannot go back to `draft` and must not be strandable by an
  //   administrator tidying up master data afterwards (§7.2).

  /// The stock location that holds a room's inventory, for new operations.
  Future<MasterLocation?> activeRoomLocation(String roomId);

  /// The stock location a historic document counted against, archived rows
  /// included.
  Future<MasterLocation?> historicalRoomLocation(String roomId);

  /// Every live `room` stock location of one room.
  ///
  /// The Distribusi path asks for the list rather than for "the" room location,
  /// because it has to be able to tell "there is none" from "there are two". A
  /// distribution posts into exactly one location per room and may not guess which
  /// (G-T1/§14); [activeRoomLocation] cannot express the ambiguity — it throws on
  /// it.
  Future<List<MasterLocation>> activeRoomLocations(String roomId);

  /// The same list including archived rows, for reading a posted document whose
  /// room location was tidied away afterwards (§7.2/§32).
  Future<List<MasterLocation>> historicalRoomLocations(String roomId);

  Future<MasterRoom?> activeRoomById(String id);

  /// The room a historic document names, soft-deleted rows included.
  Future<MasterRoom?> historicalRoomById(String id);

  Future<MasterUser?> userById(String id);

  Future<MasterLocation?> warehouseLocation();

  /// Every live central-warehouse location.
  ///
  /// The Delivery Order path asks for the list rather than for "the" warehouse,
  /// because it has to be able to tell "there is none" from "there are two". A
  /// shipment posts against exactly one location and may not guess which
  /// (G-D3); [warehouseLocation] cannot express the ambiguity — it throws on it.
  Future<List<MasterLocation>> activeWarehouseLocations();

  /// The same list including archived rows, for reading documents that already
  /// posted against one of them (§7.2).
  Future<List<MasterLocation>> historicalWarehouseLocations();

  /// Every live *Gudang Cabang* location of one branch.
  ///
  /// The Good Receipt path asks for the list rather than for "the" branch store,
  /// because it has to be able to tell "there is none" from "there are two". A
  /// receipt posts against exactly one location and may not guess which (G-G5).
  Future<List<MasterLocation>> activeBranchStoreLocations(String branchId);

  /// The same list including archived rows, so a receipt created before an
  /// administrator tidied the location away can still be posted against the exact
  /// row it was raised for (§7.2).
  Future<List<MasterLocation>> historicalBranchStoreLocations(String branchId);

  Future<MasterSummary> summary();
}
