import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';
import 'purchase_request_tables.dart';

/// Delivery Order / Surat Jalan header — one shipment from the central warehouse
/// towards the branch that raised a Purchase Request (schema v6, spec §2.3).
///
/// **One PR may have many DOs.** Spec §2.3 says so in as many words — *"1 PR bisa
/// >1 DO untuk pengiriman parsial"* — so there is deliberately no unique index on
/// `pr_id`. The rule that bounds a partial shipment is G-D2, and it is about
/// quantities per PR line rather than about how many documents carry them.
///
/// Beyond the columns the specification lists, the table carries the audit
/// metadata the posting needs (G-A3): who shipped it and the UTC instant they did
/// (`shipped_by`, `shipped_at`), plus a free-text note the Surat Jalan prints.
/// `prepared_by` and `shipped_by` are separate columns rather than one
/// `actor`, because a document prepared in the morning and shipped by the
/// afternoon shift must be able to name both.
///
/// Two absences are deliberate, and both repeat decisions schema v4 and v5 made:
///
/// * **No lexical timestamp CHECK.** Timestamps are stored as ISO-8601 TEXT, so
///   `shipped_at >= created_at` in SQL compares characters rather than instants.
///   Ordering is decided by `DocumentTimestampPolicy` on UTC `DateTime`s. What
///   the CHECKs below state is what SQLite can answer without ambiguity: which
///   timestamps each status must and must not carry.
/// * **No `received_at` / `received_by`.** Good Receipt owns that transition and
///   the columns it needs; inventing them now would be a schema promise the next
///   milestone might have to break.
@DataClassName('DeliveryOrderRow')
@TableIndex(name: 'idx_delivery_orders_pr_status', columns: {#prId, #status})
@TableIndex(
  name: 'idx_delivery_orders_status_created',
  columns: {#status, #createdAt},
)
@TableIndex(
  name: 'idx_delivery_orders_prepared_by_status',
  columns: {#preparedBy, #status},
)
@TableIndex(name: 'idx_delivery_orders_shipped_at', columns: {#shippedAt})
// Document numbers are unique among **live** documents only, for the reason the
// opname and Purchase Request tables spell out: once the sync backend issues real
// numbers (`DO-{yyyyMMdd}-{seq}`), a soft-deleted row must not hold one hostage.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_delivery_orders_doc_number
  ON delivery_orders (doc_number)
  WHERE deleted_at IS NULL;
''')
class DeliveryOrders extends Table with BusinessColumns {
  /// Temporary local number `TMP-DO-{uuid}` until a sync backend assigns the
  /// final `DO-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number offline
  /// would collide across devices — and a warehouse ships from several of them.
  TextColumn get docNumber => text().withLength(min: 1, max: 64)();

  TextColumn get prId => text().references(PurchaseRequests, #id)();

  /// The warehouse officer who assembled the shipment.
  @ReferenceName('preparedDeliveryOrders')
  TextColumn get preparedBy => text().references(Users, #id)();

  TextColumn get status => text()
      .map(const DeliveryOrderStatusConverter())
      .clientDefault(() => DeliveryOrderStatus.preparing.dbValue)();

  /// UTC instant the goods left the warehouse (T-1).
  DateTimeColumn get shippedAt => dateTime().nullable()();

  /// The warehouse officer who posted the shipment.
  @ReferenceName('shippedDeliveryOrders')
  TextColumn get shippedBy => text().nullable().references(Users, #id)();

  /// Free text printed on the Surat Jalan — courier, vehicle, handover notes.
  TextColumn get note => text().nullable()();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the type converter: a hand-written UPDATE cannot
    // introduce a status the Dart enum does not know.
    "CHECK (status IN ('preparing', 'shipped', 'received'))",
    // The shipping pair is written together or not at all, and only for a
    // document that has actually shipped. Stated exhaustively over both sides so
    // a new status cannot quietly land in neither branch.
    "CHECK ((status = 'preparing' AND shipped_at IS NULL "
        'AND shipped_by IS NULL) '
        "OR (status IN ('shipped', 'received') AND shipped_at IS NOT NULL "
        'AND shipped_by IS NOT NULL))',
  ];
}

/// One allocated position of a Delivery Order.
///
/// Every line points at a **Purchase Request line** (`pr_line_id`), and that is
/// G-D4 expressed in the schema rather than in a validation: there is no path to
/// a line that does not descend from something the branch asked for. `item_id` is
/// carried as well — denormalised on purpose — so the ledger posting and the
/// Surat Jalan can read the item without a second join, and so the use case can
/// assert that it still equals the PR line's item.
///
/// A single PR line may produce **several** lines here, in two independent ways:
///
/// * within one DO, when FEFO splits a quantity across batches;
/// * across several DOs, when the order ships in parts (G-D2).
///
/// Uniqueness is therefore per `(do_id, pr_line_id, batch_id)` — two partial
/// unique indexes, because SQLite treats every NULL as distinct and a plain
/// UNIQUE would let an item without expiry occupy the same position twice.
///
/// `shipped_qty` is INTEGER milli-units (Q-3); the repository converts it to
/// `Quantity` and nothing above it knows the scale.
@DataClassName('DeliveryOrderLineRow')
@TableIndex(name: 'idx_delivery_order_lines_do', columns: {#doId})
@TableIndex(name: 'idx_delivery_order_lines_pr_line', columns: {#prLineId})
@TableIndex(name: 'idx_delivery_order_lines_item', columns: {#itemId})
@TableIndex(name: 'idx_delivery_order_lines_batch', columns: {#batchId})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_delivery_order_lines_batched
  ON delivery_order_lines (do_id, pr_line_id, batch_id)
  WHERE batch_id IS NOT NULL AND deleted_at IS NULL;
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_delivery_order_lines_unbatched
  ON delivery_order_lines (do_id, pr_line_id)
  WHERE batch_id IS NULL AND deleted_at IS NULL;
''')
class DeliveryOrderLines extends Table with BusinessColumns {
  TextColumn get doId => text().references(DeliveryOrders, #id)();

  /// The requested position this allocation satisfies. Mandatory (spec §2.3:
  /// *"Wajib merujuk baris PR"*).
  TextColumn get prLineId => text().references(PurchaseRequestLines, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  /// The batch the warehouse picked — FEFO by default (G-E3). NULL, and only
  /// NULL, for an item without expiry (G-E2); the use case enforces both
  /// directions because the rule depends on `items.has_expiry`.
  TextColumn get batchId => text().nullable().references(ItemBatches, #id)();

  /// Quantity in **milli-units**, matching `stock_balances.qty_on_hand` (Q-3).
  /// Strictly positive: a zero allocation is not a shipment, it is an absent
  /// line.
  IntColumn get shippedQty => integer()();

  /// Why the officer picked a batch that is not the FEFO suggestion (G-E3).
  ///
  /// Mandatory *when the selection violates FEFO*, which is a cross-table
  /// question — it depends on the expiry dates and the current warehouse
  /// balances of every other batch of the item — and is therefore enforced by
  /// `ShipDeliveryOrderUseCase` and re-checked at ship time rather than by a
  /// CHECK. What the constraint below can state is that a stored reason is never
  /// blank.
  TextColumn get fefoOverrideReason => text().nullable()();

  /// Explicit acknowledgement that the batch has less than `expiry_alert_days`
  /// of shelf life left (G-E4). Never defaulted to true anywhere.
  BoolColumn get nearExpiryConfirmed =>
      boolean().withDefault(const Constant(false))();

  /// Optional context for the confirmation, printed on the Surat Jalan.
  TextColumn get nearExpiryNote => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (shipped_qty > 0)',
    // Whitespace is not a reason. `trim(...) <> ''` is what makes a reason of
    // spaces fail here too, not only in the use case.
    "CHECK (fefo_override_reason IS NULL OR trim(fefo_override_reason) <> '')",
    "CHECK (near_expiry_note IS NULL OR trim(near_expiry_note) <> '')",
    // A note without a confirmation would be an audit trail explaining a
    // decision nobody made.
    'CHECK (near_expiry_note IS NULL OR near_expiry_confirmed = 1)',
    // An item without expiry has no batch, and therefore no expiry audit to
    // carry: no FEFO to override and no shelf life to confirm.
    'CHECK (batch_id IS NOT NULL OR (fefo_override_reason IS NULL '
        'AND near_expiry_confirmed = 0 AND near_expiry_note IS NULL))',
  ];
}
