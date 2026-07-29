import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/inventory_dao.dart';
import '../../domain/models/inventory_models.dart';
import '../../domain/repositories/inventory_repository.dart';

class DriftInventoryRepository implements InventoryRepository {
  DriftInventoryRepository(this._dao);

  final InventoryDao _dao;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _dao.transaction(action);

  @override
  Future<int> balanceQty({
    required String locationId,
    required String itemId,
    String? batchId,
  }) async {
    final row = await _dao.findBalance(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
    );
    return row?.qtyOnHand ?? 0;
  }

  @override
  Future<void> setBalanceQty({
    required String locationId,
    required String itemId,
    String? batchId,
    required int qtyOnHand,
  }) => _dao.setBalanceQty(
    locationId: locationId,
    itemId: itemId,
    batchId: batchId,
    qtyOnHand: qtyOnHand,
  );

  @override
  Future<List<StockBalanceView>> balancesAtLocation(
    String locationId, {
    bool positiveOnly = true,
  }) async {
    final rows = await _dao.balancesAtLocation(
      locationId,
      positiveOnly: positiveOnly,
    );
    return rows.map(_toBalanceView).toList(growable: false);
  }

  @override
  Stream<List<StockBalanceView>> watchBalancesAtLocation(
    String locationId, {
    bool positiveOnly = true,
  }) {
    return _dao
        .watchBalancesAtLocation(locationId, positiveOnly: positiveOnly)
        .map((rows) => rows.map(_toBalanceView).toList(growable: false));
  }

  @override
  Future<List<BatchStock>> batchStocksForFefo({
    required String locationId,
    required String itemId,
  }) async {
    final rows = await _dao.batchBalancesForFefo(
      locationId: locationId,
      itemId: itemId,
    );
    return rows
        .map((row) {
          final batch = row.batch!;
          return BatchStock(
            batchId: batch.id,
            batchNo: batch.batchNo,
            expiryDate: _asUtcDate(batch.expiryDate),
            qtyOnHand: row.balance.qtyOnHand,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<InventoryMovement> appendMovement(MovementDraft draft) async {
    final row = await _dao.insertMovement(
      StockMovementsCompanion.insert(
        id: Value(draft.id),
        itemId: draft.itemId,
        batchId: Value(draft.batchId),
        fromLocationId: Value(draft.fromLocationId),
        toLocationId: Value(draft.toLocationId),
        qty: draft.qty,
        movementType: draft.movementType,
        refDocType: Value(draft.refDocType),
        refDocId: Value(draft.refDocId),
        actorUserId: draft.actorUserId,
        note: Value(draft.note),
        reversalOfMovementId: Value(draft.reversalOfMovementId),
      ),
    );
    return _toMovement(row);
  }

  @override
  Future<InventoryMovement?> movementById(String id) async {
    final row = await _dao.movementById(id);
    return row == null ? null : _toMovement(row);
  }

  @override
  Future<List<InventoryMovement>> stockCard({
    required String itemId,
    String? locationId,
    int? limit,
  }) async {
    final rows = await _dao.stockCard(
      itemId: itemId,
      locationId: locationId,
      limit: limit,
    );
    return rows.map(_toMovement).toList(growable: false);
  }

  @override
  Future<List<InventoryMovement>> movementsByRef({
    required String refDocType,
    required String refDocId,
  }) async {
    final rows = await _dao.movementsByRef(
      refDocType: refDocType,
      refDocId: refDocId,
    );
    return rows.map(_toMovement).toList(growable: false);
  }

  @override
  Future<List<InventoryMovement>> reversalsOf(String movementId) async {
    final rows = await _dao.reversalsOf(movementId);
    return rows.map(_toMovement).toList(growable: false);
  }
}

DateTime _asUtcDate(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

StockBalanceView _toBalanceView(BalanceWithDetails row) => StockBalanceView(
  locationId: row.balance.locationId,
  itemId: row.balance.itemId,
  sku: row.item.sku,
  itemName: row.item.name,
  unit: row.item.unit,
  hasExpiry: row.item.hasExpiry,
  expiryAlertDays: row.item.expiryAlertDays,
  qtyOnHand: row.balance.qtyOnHand,
  batchId: row.batch?.id,
  batchNo: row.batch?.batchNo,
  expiryDate: row.batch == null ? null : _asUtcDate(row.batch!.expiryDate),
);

InventoryMovement _toMovement(StockMovement row) => InventoryMovement(
  id: row.id,
  itemId: row.itemId,
  batchId: row.batchId,
  fromLocationId: row.fromLocationId,
  toLocationId: row.toLocationId,
  qty: row.qty,
  movementType: row.movementType,
  actorUserId: row.actorUserId,
  refDocType: row.refDocType,
  refDocId: row.refDocId,
  note: row.note,
  reversalOfMovementId: row.reversalOfMovementId,
  createdAt: row.createdAt,
);
