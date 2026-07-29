import '../../../../core/quantity/quantity.dart';
import '../models/inventory_models.dart';

/// Ledger and balance access, expressed in domain terms.
///
/// Note the missing `updateMovement` / `deleteMovement`: the ledger is
/// append-only (G-A1) and this contract makes that structurally impossible.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers the
/// database stores never leak past the repository implementation (Q-4).
abstract interface class InventoryRepository {
  /// Runs [action] inside a single database transaction. Every stock posting
  /// must go through this so partial postings can never be committed.
  Future<T> runInTransaction<T>(Future<T> Function() action);

  Future<Quantity> balanceQty({
    required String locationId,
    required String itemId,
    String? batchId,
  });

  Future<void> setBalanceQty({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity qtyOnHand,
  });

  Future<List<StockBalanceView>> balancesAtLocation(
    String locationId, {
    bool positiveOnly,
  });

  Stream<List<StockBalanceView>> watchBalancesAtLocation(
    String locationId, {
    bool positiveOnly,
  });

  /// Positive batch balances at a location ordered by nearest expiry first.
  Future<List<BatchStock>> batchStocksForFefo({
    required String locationId,
    required String itemId,
  });

  /// The single write path into the ledger.
  Future<InventoryMovement> appendMovement(MovementDraft draft);

  Future<InventoryMovement?> movementById(String id);

  Future<List<InventoryMovement>> stockCard({
    required String itemId,
    String? locationId,
    int? limit,
  });

  Future<List<InventoryMovement>> movementsByRef({
    required String refDocType,
    required String refDocId,
  });

  Future<List<InventoryMovement>> reversalsOf(String movementId);
}
