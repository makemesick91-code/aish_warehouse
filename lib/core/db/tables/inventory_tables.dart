import 'package:drift/drift.dart';

import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';

/// Cached balance per location / item / batch.
///
/// The ledger ([StockMovements]) is the source of truth; this table only exists
/// so the UI can read a balance without replaying every movement.
///
/// Uniqueness on `(location_id, item_id, batch_id)` cannot be expressed with a
/// plain UNIQUE constraint: SQLite treats every NULL as distinct, so items
/// without expiry (`batch_id IS NULL`) could silently end up with several
/// balance rows for the same location. Two partial unique indexes cover both
/// cases exactly and, unlike a generated `COALESCE` key column, require no
/// SQLite 3.31+ generated-column support and keep `batch_id` a real nullable
/// foreign key.
@DataClassName('StockBalance')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_stock_balances_batched
  ON stock_balances (location_id, item_id, batch_id)
  WHERE batch_id IS NOT NULL;
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_stock_balances_unbatched
  ON stock_balances (location_id, item_id)
  WHERE batch_id IS NULL;
''')
class StockBalances extends Table with BusinessColumns {
  TextColumn get locationId => text().references(StockLocations, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  TextColumn get batchId => text().nullable().references(ItemBatches, #id)();

  /// Balance in **milli-units** — `Quantity.scale` (1000) per whole unit, so
  /// 0.5 on the shelf is stored as 500 (spec Q-3, schema v2).
  ///
  /// INTEGER, never REAL: a REAL balance would accumulate binary rounding error
  /// across postings and could drift away from the ledger it mirrors. The
  /// CHECK below applies to the scaled value, so it still means "never
  /// negative" (G-A2).
  IntColumn get qtyOnHand => integer()();

  @override
  List<String> get customConstraints => ['CHECK (qty_on_hand >= 0)'];
}

/// Append-only stock ledger (G-A1). There is no update and no delete path:
/// corrections are posted as a new `reversal` movement pointing back at the
/// original row.
@DataClassName('StockMovement')
@TableIndex(name: 'idx_stock_movements_item', columns: {#itemId, #createdAt})
@TableIndex(name: 'idx_stock_movements_ref', columns: {#refDocType, #refDocId})
class StockMovements extends Table with BusinessColumns {
  TextColumn get itemId => text().references(Items, #id)();

  TextColumn get batchId => text().nullable().references(ItemBatches, #id)();

  @ReferenceName('outgoingMovements')
  TextColumn get fromLocationId =>
      text().nullable().references(StockLocations, #id)();

  @ReferenceName('incomingMovements')
  TextColumn get toLocationId =>
      text().nullable().references(StockLocations, #id)();

  /// Movement quantity in **milli-units**, matching
  /// [StockBalances.qtyOnHand] (spec Q-3). `CHECK (qty > 0)` below is evaluated
  /// on the scaled value, so the smallest postable movement is 0.001 units.
  IntColumn get qty => integer()();

  TextColumn get movementType =>
      text().map(const StockMovementTypeConverter())();

  TextColumn get refDocType => text().withLength(max: 16).nullable()();

  TextColumn get refDocId => text().nullable()();

  TextColumn get actorUserId => text().references(Users, #id)();

  TextColumn get note => text().nullable()();

  TextColumn get reversalOfMovementId =>
      text().nullable().references(StockMovements, #id)();

  @override
  List<String> get customConstraints => [
    'CHECK (qty > 0)',
    'CHECK (from_location_id IS NOT NULL OR to_location_id IS NOT NULL)',
    'CHECK (from_location_id IS NULL OR to_location_id IS NULL '
        'OR from_location_id <> to_location_id)',
  ];
}
