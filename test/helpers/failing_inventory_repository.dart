import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/inventory/domain/models/inventory_models.dart';
import 'package:aish_warehouse/features/inventory/domain/repositories/inventory_repository.dart';

/// An inventory repository that behaves normally until it is asked to append a
/// movement for [failOnItemId], at which point it throws.
///
/// This is how the atomicity of a Stok Opname review is proved: the failure can
/// be made to land *after* earlier lines have already written movements and
/// balances, so if the review were not one unit of work, those earlier writes
/// would survive the rollback.
class FailingInventoryRepository implements InventoryRepository {
  FailingInventoryRepository(this._delegate, {required this.failOnItemId});

  final InventoryRepository _delegate;

  /// Movements for this item are rejected. Pass an id that is not on the
  /// document to get a repository that never fails.
  final String failOnItemId;

  /// How many movements were written before the failure fired.
  int appendedBeforeFailure = 0;

  @override
  Future<InventoryMovement> appendMovement(MovementDraft draft) async {
    if (draft.itemId == failOnItemId) {
      throw const ValidationFailure('Kegagalan buatan pada baris ini.');
    }
    appendedBeforeFailure++;
    return _delegate.appendMovement(draft);
  }

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _delegate.runInTransaction(action);

  @override
  Future<Quantity> balanceQty({
    required String locationId,
    required String itemId,
    String? batchId,
  }) => _delegate.balanceQty(
    locationId: locationId,
    itemId: itemId,
    batchId: batchId,
  );

  @override
  Future<void> setBalanceQty({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity qtyOnHand,
  }) => _delegate.setBalanceQty(
    locationId: locationId,
    itemId: itemId,
    batchId: batchId,
    qtyOnHand: qtyOnHand,
  );

  @override
  Future<List<StockBalanceView>> balancesAtLocation(
    String locationId, {
    bool positiveOnly = true,
  }) => _delegate.balancesAtLocation(locationId, positiveOnly: positiveOnly);

  @override
  Stream<List<StockBalanceView>> watchBalancesAtLocation(
    String locationId, {
    bool positiveOnly = true,
  }) =>
      _delegate.watchBalancesAtLocation(locationId, positiveOnly: positiveOnly);

  @override
  Future<List<BatchStock>> batchStocksForFefo({
    required String locationId,
    required String itemId,
  }) => _delegate.batchStocksForFefo(locationId: locationId, itemId: itemId);

  @override
  Future<InventoryMovement?> movementById(String id) =>
      _delegate.movementById(id);

  @override
  Future<List<InventoryMovement>> stockCard({
    required String itemId,
    String? locationId,
    int? limit,
  }) =>
      _delegate.stockCard(itemId: itemId, locationId: locationId, limit: limit);

  @override
  Future<List<InventoryMovement>> movementsByRef({
    required String refDocType,
    required String refDocId,
  }) => _delegate.movementsByRef(refDocType: refDocType, refDocId: refDocId);

  @override
  Future<List<InventoryMovement>> reversalsOf(String movementId) =>
      _delegate.reversalsOf(movementId);
}
