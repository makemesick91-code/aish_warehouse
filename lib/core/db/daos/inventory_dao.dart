import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/inventory_tables.dart';
import '../tables/master_tables.dart';

part 'inventory_dao.g.dart';

/// A balance row joined with the item (and batch, when the item has expiry).
class BalanceWithDetails {
  const BalanceWithDetails({
    required this.balance,
    required this.item,
    this.batch,
  });

  final StockBalance balance;
  final Item item;
  final ItemBatch? batch;
}

/// Inventory ledger access.
///
/// Deliberately offers no way to modify or remove a ledger row:
/// `stock_movements` is append-only (G-A1). Corrections go through a reversal
/// movement posted by `StockPostingService`.
///
/// This is the one layer that speaks in raw milli-units (Q-4): `qty_on_hand`
/// and `qty` are INTEGER columns holding `unit * 1000`. All arithmetic and
/// every comparison below is integer arithmetic — no REAL, no `double`, so a
/// balance can never drift. The repository above converts to `Quantity`.
@DriftAccessor(
  tables: [StockBalances, StockMovements, Items, ItemBatches, StockLocations],
)
class InventoryDao extends DatabaseAccessor<AppDatabase>
    with _$InventoryDaoMixin {
  InventoryDao(super.db);

  Expression<bool> _balanceKey(
    $StockBalancesTable t,
    String locationId,
    String itemId,
    String? batchId,
  ) {
    return t.locationId.equals(locationId) &
        t.itemId.equals(itemId) &
        (batchId == null ? t.batchId.isNull() : t.batchId.equals(batchId)) &
        t.deletedAt.isNull();
  }

  Future<StockBalance?> findBalance({
    required String locationId,
    required String itemId,
    String? batchId,
  }) {
    return (select(stockBalances)
          ..where((t) => _balanceKey(t, locationId, itemId, batchId)))
        .getSingleOrNull();
  }

  /// Writes the absolute quantity for one balance key, inserting the row when
  /// it does not exist yet. Callers must run this inside a transaction.
  ///
  /// [qtyOnHandMilliUnits] is already scaled — 0.5 units arrive here as 500.
  Future<void> setBalanceQty({
    required String locationId,
    required String itemId,
    String? batchId,
    required int qtyOnHandMilliUnits,
  }) async {
    final existing = await findBalance(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
    );

    if (existing == null) {
      await into(stockBalances).insert(
        StockBalancesCompanion.insert(
          locationId: locationId,
          itemId: itemId,
          batchId: Value(batchId),
          qtyOnHand: qtyOnHandMilliUnits,
        ),
      );
      return;
    }

    await (update(stockBalances)..where((t) => t.id.equals(existing.id))).write(
      StockBalancesCompanion(
        qtyOnHand: Value(qtyOnHandMilliUnits),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  SimpleSelectStatement<$StockBalancesTable, StockBalance> _balancesAt(
    String locationId, {
    required bool positiveOnly,
  }) {
    return select(stockBalances)..where(
      (t) =>
          t.locationId.equals(locationId) &
          t.deletedAt.isNull() &
          (positiveOnly
              ? t.qtyOnHand.isBiggerThanValue(0)
              : const Constant(true)),
    );
  }

  JoinedSelectStatement<HasResultSet, dynamic> _joinDetails(
    SimpleSelectStatement<$StockBalancesTable, StockBalance> base,
  ) {
    return base.join([
      innerJoin(items, items.id.equalsExp(stockBalances.itemId)),
      leftOuterJoin(
        itemBatches,
        itemBatches.id.equalsExp(stockBalances.batchId),
      ),
    ])..orderBy([
      OrderingTerm.asc(items.name),
      OrderingTerm.asc(itemBatches.expiryDate),
    ]);
  }

  List<BalanceWithDetails> _mapDetails(List<TypedResult> rows) {
    return rows
        .map(
          (row) => BalanceWithDetails(
            balance: row.readTable(stockBalances),
            item: row.readTable(items),
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Future<List<BalanceWithDetails>> balancesAtLocation(
    String locationId, {
    bool positiveOnly = true,
  }) async {
    final rows = await _joinDetails(
      _balancesAt(locationId, positiveOnly: positiveOnly),
    ).get();
    return _mapDetails(rows);
  }

  Stream<List<BalanceWithDetails>> watchBalancesAtLocation(
    String locationId, {
    bool positiveOnly = true,
  }) {
    return _joinDetails(
      _balancesAt(locationId, positiveOnly: positiveOnly),
    ).watch().map(_mapDetails);
  }

  /// Positive batch balances at a location, ordered for FEFO consumption
  /// (nearest expiry first, then batch number for a deterministic tie-break).
  Future<List<BalanceWithDetails>> batchBalancesForFefo({
    required String locationId,
    required String itemId,
  }) async {
    final query =
        select(stockBalances).join([
            innerJoin(items, items.id.equalsExp(stockBalances.itemId)),
            innerJoin(
              itemBatches,
              itemBatches.id.equalsExp(stockBalances.batchId),
            ),
          ])
          ..where(
            stockBalances.locationId.equals(locationId) &
                stockBalances.itemId.equals(itemId) &
                stockBalances.deletedAt.isNull() &
                stockBalances.qtyOnHand.isBiggerThanValue(0),
          )
          ..orderBy([
            OrderingTerm.asc(itemBatches.expiryDate),
            OrderingTerm.asc(itemBatches.batchNo),
            OrderingTerm.asc(itemBatches.id),
          ]);

    return _mapDetails(await query.get());
  }

  /// The only write path into the ledger.
  Future<StockMovement> insertMovement(StockMovementsCompanion movement) =>
      into(stockMovements).insertReturning(movement);

  Future<StockMovement?> movementById(String id) =>
      (select(stockMovements)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Stock card (kartu stok) for one item, optionally scoped to a location.
  Future<List<StockMovement>> stockCard({
    required String itemId,
    String? locationId,
    int? limit,
  }) {
    final query = select(stockMovements)
      ..where(
        (t) =>
            t.itemId.equals(itemId) &
            (locationId == null
                ? const Constant(true)
                : (t.fromLocationId.equals(locationId) |
                      t.toLocationId.equals(locationId))),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  Future<List<StockMovement>> movementsByRef({
    required String refDocType,
    required String refDocId,
  }) {
    return (select(stockMovements)
          ..where(
            (t) =>
                t.refDocType.equals(refDocType) & t.refDocId.equals(refDocId),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<StockMovement>> reversalsOf(String movementId) {
    return (select(
      stockMovements,
    )..where((t) => t.reversalOfMovementId.equals(movementId))).get();
  }
}
