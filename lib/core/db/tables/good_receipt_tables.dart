import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'delivery_tables.dart';
import 'master_tables.dart';

/// Good Receipt / Penerimaan Barang header — the branch head checking one
/// shipment in (schema v7, spec §2.3).
///
/// **One Delivery Order has exactly one Good Receipt.** Spec §2.4 draws it as
/// `delivery_orders 1─1 good_receipts` and G-G1 says it in words, so `do_id`
/// carries a *fully* unique index rather than the partial
/// `WHERE deleted_at IS NULL` shape the document-number indexes use. The
/// difference is the whole point: a partial index would let a soft-deleted
/// receipt be followed by a second one for the same shipment, and posting that
/// second receipt would add the branch's stock twice from one delivery. Nothing
/// in the workflow soft-deletes a receipt — there is no writer for it — and this
/// index is what makes a hand-written UPDATE unable to open that door either.
///
/// `doc_number` keeps the partial shape the opname, Purchase Request and
/// Delivery Order tables use, for the reason those spell out: once the sync
/// backend issues real numbers (`GR-{cabang}-{yyyyMMdd}-{seq}`), a soft-deleted
/// row must not hold one hostage.
///
/// Two absences are deliberate:
///
/// * **No lexical timestamp CHECK.** Timestamps are ISO-8601 TEXT, so
///   `posted_at >= created_at` in SQL compares characters rather than instants.
///   Ordering is decided by [DocumentTimestampPolicy] on UTC `DateTime`s. What
///   the CHECKs below state is what SQLite can answer without ambiguity: which
///   timestamps each status must and must not carry.
/// * **No `discrepancy_qty` anywhere.** The shortage of a line is exactly
///   `shipped_qty - received_qty`, which every reader can derive and no writer
///   can then contradict. A stored copy would be a second version of the same
///   fact.
@DataClassName('GoodReceiptRow')
@TableIndex(
  name: 'idx_good_receipts_received_by_status',
  columns: {#receivedBy, #status},
)
@TableIndex(
  name: 'idx_good_receipts_status_created',
  columns: {#status, #createdAt},
)
@TableIndex(name: 'idx_good_receipts_posted_at', columns: {#postedAt})
// G-G1's database half: one Delivery Order, one Good Receipt, unconditionally.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_good_receipts_do
  ON good_receipts (do_id);
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_good_receipts_doc_number
  ON good_receipts (doc_number)
  WHERE deleted_at IS NULL;
''')
class GoodReceipts extends Table with BusinessColumns {
  /// Temporary local number `TMP-GR-{uuid}` until a sync backend assigns the
  /// final `GR-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number
  /// offline would collide across devices — and every branch receives on its
  /// own.
  TextColumn get docNumber => text().withLength(min: 1, max: 64)();

  /// The shipment being checked in. Unique: see the class note.
  TextColumn get doId => text().references(DeliveryOrders, #id)();

  /// The Kepala Cabang who checked the goods (G-G1). Their branch must be the
  /// shipment's destination, which is a cross-table question and therefore the
  /// use case's to enforce.
  @ReferenceName('receivedGoodReceipts')
  TextColumn get receivedBy => text().references(Users, #id)();

  TextColumn get status => text()
      .map(const GoodReceiptStatusConverter())
      .clientDefault(() => GoodReceiptStatus.checking.dbValue)();

  /// UTC instant the receipt was posted and the branch store credited (T-1).
  DateTimeColumn get postedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the type converter: a hand-written UPDATE cannot
    // introduce a status the Dart enum does not know.
    "CHECK (status IN ('checking', 'posted'))",
    // The posting instant exists exactly when the receipt has posted. Stated
    // exhaustively over both statuses so a new one cannot quietly land in
    // neither branch.
    "CHECK ((status = 'checking' AND posted_at IS NULL) "
        "OR (status = 'posted' AND posted_at IS NOT NULL))",
  ];
}

/// One checked position of a Good Receipt — the ceklis per barang of spec §2.3.
///
/// Every line points at a **Delivery Order line** (`do_line_id`), and the unique
/// index below is what makes the snapshot faithful: one receipt line per shipped
/// allocation, no more and no fewer. Unlike the Delivery Order's own allocation
/// indexes this one is *not* partial — there is no writer that removes a receipt
/// line (G-G4: rejecting is a decision, not a deletion), so "live rows only"
/// would be a qualification with nothing behind it and a soft-delete could
/// otherwise let one allocation be checked in twice.
///
/// `item_id`, `batch_id` and `shipped_qty` are **snapshots** of the Delivery
/// Order line, carried here on purpose:
///
/// * the ledger posting and the discrepancy report read them without a second
///   join, and
/// * `shipped_qty` is what `received_qty` is bounded against (G-G3), so it must
///   be the quantity that was actually shipped rather than whatever the source
///   row says later.
///
/// Nothing may edit them — the DAO offers no writer that reaches those columns,
/// which is the same shape G-D4 gave `pr_line_id` on the shipment.
///
/// Both quantities are INTEGER milli-units (Q-3); the repository converts them
/// to `Quantity` and nothing above it knows the scale.
@DataClassName('GoodReceiptLineRow')
@TableIndex(name: 'idx_good_receipt_lines_gr', columns: {#grId})
@TableIndex(name: 'idx_good_receipt_lines_do_line', columns: {#doLineId})
@TableIndex(name: 'idx_good_receipt_lines_item', columns: {#itemId})
@TableIndex(name: 'idx_good_receipt_lines_batch', columns: {#batchId})
@TableIndex(name: 'idx_good_receipt_lines_status', columns: {#lineStatus})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_good_receipt_lines_unique
  ON good_receipt_lines (gr_id, do_line_id);
''')
class GoodReceiptLines extends Table with BusinessColumns {
  TextColumn get grId => text().references(GoodReceipts, #id)();

  /// The shipped allocation this decision answers.
  TextColumn get doLineId => text().references(DeliveryOrderLines, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  /// The batch the warehouse shipped, verified by the branch head against the
  /// packaging (spec §2.3). NULL, and only NULL, for an item without expiry
  /// (G-E2); the use case enforces both directions because the rule depends on
  /// `items.has_expiry`.
  TextColumn get batchId => text().nullable().references(ItemBatches, #id)();

  /// Snapshot of the Delivery Order line's quantity, in **milli-units** (Q-3).
  /// Strictly positive, because a shipment never allocates zero.
  IntColumn get shippedQty => integer()();

  /// What the branch actually accepted, in **milli-units**. Bounded by
  /// `0 ≤ received_qty ≤ shipped_qty` (G-G3) in SQL as well as in the domain.
  IntColumn get receivedQty => integer()();

  TextColumn get lineStatus => text()
      .map(const GoodReceiptLineStatusConverter())
      .clientDefault(() => GoodReceiptLineStatus.pending.dbValue)();

  /// Why the position was refused (G-G4). Mandatory for `rejected`, forbidden
  /// otherwise — a reason on an accepted line would be an audit trail for a
  /// decision nobody made.
  TextColumn get rejectReason => text().nullable()();

  @override
  List<String> get customConstraints => [
    "CHECK (line_status IN ('pending', 'checked', 'rejected'))",
    'CHECK (shipped_qty > 0)',
    // G-G3, both halves, in the database as well as in the policy. The upper
    // bound is what stops a hand-written UPDATE receiving more than was sent.
    'CHECK (received_qty >= 0)',
    'CHECK (received_qty <= shipped_qty)',
    // The three legal shapes of a decision, stated exhaustively:
    //
    // * pending  — nothing decided, so no reason;
    // * checked  — accepted, so no reason; the quantity may be anything from 0
    //              to shipped_qty and a shortfall is the discrepancy (G-G3);
    // * rejected — nothing accepted, so received_qty is 0, and a non-blank
    //              reason is mandatory (G-G4).
    //
    // `reject_reason IS NOT NULL` is written out rather than left to
    // `trim(reject_reason) <> ''`, and that is load-bearing: SQLite treats a CHECK
    // whose result is **NULL as satisfied**, and `trim(NULL) <> ''` is NULL. Without
    // the explicit null test, `rejected` with no reason at all would pass the
    // constraint — the one case G-G4 most needs it to catch. With it, the conjunct is
    // `false AND NULL`, which SQLite evaluates to false.
    "CHECK ((line_status = 'pending' AND reject_reason IS NULL) "
        "OR (line_status = 'checked' AND reject_reason IS NULL) "
        "OR (line_status = 'rejected' AND received_qty = 0 "
        "AND reject_reason IS NOT NULL AND trim(reject_reason) <> ''))",
  ];
}
