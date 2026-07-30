import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'good_receipt_tables.dart';
import 'master_tables.dart';

/// Retur Barang header — one branch sending back everything one Good Receipt
/// rejected (schema v11, §10).
///
/// ### Why this table exists at all
///
/// **The specification defines no Return document.** §2.3 lists none and §3.2 gives
/// it no state machine. What it does state is that `stock_movements.movement_type`
/// carries a `return` value (§2.2), that a rejected Good Receipt line *"masuk daftar
/// retur ke Warehouse"* (G-G5), that a rejection stays as an audit record with a
/// mandatory reason (G-G4), and that the Warehouse screen shows *"daftar barang
/// rejected dari GR cabang untuk ditindaklanjuti"* (§4.2). A bare movement can carry
/// an actor and a note, but nothing that groups one shipment's refusals into a box
/// somebody physically hands over, and nothing a Warehouse user can work a queue
/// from. So Milestone 9 wraps the movement in the smallest auditable document that
/// can: a header naming the receipt, the branch, who raised it, who shipped it and
/// who received it, plus one immutable line per rejected position. **That extension
/// is a deliberate decision documented here rather than a rule the specification
/// states.**
///
/// ### One Good Receipt has exactly one Retur
///
/// `gr_id` carries a **fully** unique index rather than the partial
/// `WHERE deleted_at IS NULL` shape the document-number indexes elsewhere use, and
/// the difference is the whole point — it is the same reasoning `good_receipts.do_id`
/// spells out for G-G1. A partial index would let a soft-deleted return be followed
/// by a second one for the same receipt, and receiving that second return would
/// credit the Warehouse twice for goods that came back once. Nothing in this workflow
/// soft-deletes a return — there is no writer for it (§24) — and this index is what
/// makes a hand-written UPDATE unable to open that door either.
///
/// ### `branch_id` is stored, not derived
///
/// A Good Receipt has no branch column of its own: its branch is
/// `good_receipts → delivery_orders → purchase_requests.branch_id`, three joins away.
/// Storing it here is what lets every scoped read predicate on one column of one
/// table — `goods_returns.branch_id = ?` — instead of putting the security boundary
/// three joins from the statement that enforces it. The two must agree, which is a
/// cross-table equality SQLite cannot express as a foreign key, so the create use
/// case establishes it and every later guard revalidates it (§17/§20/§21).
///
/// ### `doc_number` is unique **absolutely**, not partially
///
/// Following `disposals` and `consumptions` rather than the opname / PR / DO / GR
/// shape, and G-A3 is why: *"nomor dokumen berurut dan tidak dipakai ulang."* A
/// return is the document that explains why stock reappeared in the Warehouse, so a
/// number that could be reissued after a soft delete would let two rows answer to the
/// same reference. Until the sync backend assigns a real number the local one is
/// `TMP-RET-{uuid}`, which is unique by construction, so the stricter index costs
/// nothing.
///
/// ### Segregation of duties, in the database (G-R4)
///
/// `received_by <> created_by` and `received_by <> shipped_by` are CHECKs rather than
/// use-case rules alone. G-R4 forbids one person completing both halves of a two-half
/// workflow, and this is the first document in the schema whose two halves belong to
/// *different branches of the organisation* — so the constraint is expressible in
/// SQL and therefore is. Both are written with an explicit `IS NULL` branch: SQLite
/// treats a CHECK evaluating to **NULL as satisfied**, and `received_by <> created_by`
/// is NULL while `received_by` is NULL, so the draft and shipped cases have to be
/// accepted deliberately rather than by accident.
///
/// Two absences are deliberate:
///
/// * **No lexical timestamp CHECK.** Timestamps are ISO-8601 TEXT, so
///   `received_at >= shipped_at` in SQL compares characters rather than instants —
///   the trap schema v4 removed from `stock_opnames`. Ordering is decided by
///   [DocumentTimestampPolicy] on UTC `DateTime`s (§39). What the CHECKs below state
///   is what SQLite can answer without ambiguity: which timestamps and which actors
///   each status must and must not carry.
/// * **No line or quantity totals.** Every one of them is derivable from
///   `goods_return_lines`, and a stored copy would be a second version of the same
///   fact that a writer could contradict.
@DataClassName('GoodsReturnRow')
@TableIndex(
  name: 'idx_goods_returns_branch_status',
  columns: {#branchId, #status},
)
@TableIndex(
  name: 'idx_goods_returns_created_by_status',
  columns: {#createdBy, #status},
)
@TableIndex(
  name: 'idx_goods_returns_shipped_by_status',
  columns: {#shippedBy, #status},
)
@TableIndex(
  name: 'idx_goods_returns_received_by_status',
  columns: {#receivedBy, #status},
)
@TableIndex(name: 'idx_goods_returns_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_goods_returns_shipped_at', columns: {#shippedAt})
@TableIndex(name: 'idx_goods_returns_received_at', columns: {#receivedAt})
// One Good Receipt, one Retur, unconditionally — see the class note.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_goods_returns_gr
  ON goods_returns (gr_id);
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_goods_returns_doc_number
  ON goods_returns (doc_number);
''')
class GoodsReturns extends Table with BusinessColumns {
  /// Temporary local number `TMP-RET-{uuid}` until a sync backend assigns the final
  /// `RET-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number offline
  /// would collide across devices — every branch returns on its own.
  TextColumn get docNumber => text().withLength(min: 1, max: 64)();

  /// The Good Receipt whose rejections this document sends back. Unique: see the
  /// class note. Fixed at creation — there is no statement anywhere that updates it.
  TextColumn get grId => text().references(GoodReceipts, #id)();

  /// The branch sending the goods back. Must be the receipt's branch — a cross-table
  /// equality SQLite cannot express, so the use cases enforce it (see the class note).
  TextColumn get branchId => text().references(Branches, #id)();

  /// The Kepala Cabang who raised the document (G-A3). Immutable.
  @ReferenceName('createdGoodsReturns')
  TextColumn get createdBy => text().references(Users, #id)();

  TextColumn get status => text()
      .map(const GoodsReturnStatusConverter())
      .clientDefault(() => GoodsReturnStatus.draft.dbValue)();

  /// Free-text remark from the branch, e.g. *"dikirim via kurir internal"*.
  ///
  /// **Optional.** Every line already carries the mandatory reason G-G4 demanded when
  /// the position was rejected, snapshotted below, so requiring a second explanation
  /// on the header would be inventing a rule. What the CHECK does refuse is
  /// *whitespace* pretending to be a remark.
  TextColumn get note => text().nullable()();

  /// UTC instant the branch handed the goods to the carrier (T-1).
  ///
  /// Records a *physical* event and nothing else: no balance moves when this is
  /// written (§20). The goods left the branch's care, but they were never in the
  /// branch's stock — G-G5 credits only `checked` lines — so there is no balance to
  /// take them out of.
  DateTimeColumn get shippedAt => dateTime().nullable()();

  /// Who shipped it. Null exactly while the document is a draft.
  @ReferenceName('shippedGoodsReturns')
  TextColumn get shippedBy => text().nullable().references(Users, #id)();

  /// UTC instant the Warehouse confirmed arrival and the ledger was posted (T-1).
  DateTimeColumn get receivedAt => dateTime().nullable()();

  /// The Petugas Warehouse who confirmed arrival. Null until then, and never equal to
  /// [createdBy] or [shippedBy] — see the class note on G-R4.
  @ReferenceName('receivedGoodsReturns')
  TextColumn get receivedBy => text().nullable().references(Users, #id)();

  /// Optional remark the Warehouse adds when confirming, e.g. *"kardus penyok tapi
  /// isi lengkap"*.
  ///
  /// Writable only by the receive transaction (§21). A branch cannot write it and the
  /// Warehouse cannot write the branch's [note]: the two sides of this document each
  /// own their own words, which is what makes either of them evidence.
  TextColumn get warehouseNote => text().nullable()();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the type converter: a hand-written UPDATE cannot
    // introduce a status the Dart enum does not know.
    "CHECK (status IN ('draft', 'shipped', 'received'))",
    // Which timestamps and actors each status must and must not carry, stated
    // exhaustively over all three so a new status cannot quietly land in none of the
    // branches. This is the database half of "no un-ship and no un-receive": a row
    // moved backwards would have to drop an actor the CHECK requires.
    "CHECK ((status = 'draft' AND shipped_at IS NULL AND shipped_by IS NULL "
        'AND received_at IS NULL AND received_by IS NULL) '
        "OR (status = 'shipped' AND shipped_at IS NOT NULL "
        'AND shipped_by IS NOT NULL '
        'AND received_at IS NULL AND received_by IS NULL) '
        "OR (status = 'received' AND shipped_at IS NOT NULL "
        'AND shipped_by IS NOT NULL '
        'AND received_at IS NOT NULL AND received_by IS NOT NULL))',
    // G-R4, both halves. The explicit `IS NULL` branch is load-bearing for the SQLite
    // quirk the class note spells out: `received_by <> created_by` evaluates to NULL
    // while `received_by` is NULL, and a NULL CHECK counts as satisfied — so the
    // draft and shipped cases are accepted deliberately rather than by accident.
    'CHECK (received_by IS NULL OR received_by <> created_by)',
    'CHECK (received_by IS NULL OR shipped_by IS NULL '
        'OR received_by <> shipped_by)',
    // A *stored* note must say something, whatever the status. The `IS NULL OR`
    // branch is load-bearing for the same reason — this column is legitimately NULL
    // on most compliant rows.
    "CHECK (note IS NULL OR trim(note) <> '')",
    "CHECK (warehouse_note IS NULL OR trim(warehouse_note) <> '')",
  ];
}

/// One returned position — an immutable snapshot of one **rejected** Good Receipt
/// line (§11).
///
/// ### Every column here is a snapshot, and nothing may edit any of them
///
/// `item_id`, `batch_id`, `qty` and `reject_reason_snapshot` are copied from the Good
/// Receipt line at creation and are read-only from that instant. There is no writer on
/// [GoodsReturnDao] that reaches them, no use case that takes a quantity, and no
/// screen with an input (§18). The reason is what a return *is*: the branch is sending
/// back exactly what it refused, so a quantity somebody could edit would be a quantity
/// that no longer describes the goods in the box. `qty` therefore always equals the
/// source line's `shipped_qty` — a rejected line accepted nothing, so its
/// `received_qty` is 0 (the Good Receipt's own CHECK) and everything that was sent is
/// coming back.
///
/// `reject_reason_snapshot` is copied rather than joined for the same reason the Good
/// Receipt snapshots `shipped_qty`: it is *evidence*, and evidence that could be
/// re-read from a row somebody might edit later is evidence with a hole in it. It is
/// NOT NULL and non-blank because G-G4 already made it mandatory on the source line;
/// a return line with no reason would mean a rejection with no reason got through.
///
/// ### `gr_line_id` is unique **absolutely**, twice
///
/// Once across the whole table and once within the document. The table-wide index is
/// the load-bearing one: one rejected position may be returned exactly once, ever, and
/// a partial `WHERE deleted_at IS NULL` shape would let a soft-deleted line free the
/// position for a second return that credits the Warehouse again. Nothing soft-deletes
/// a return line — there is no writer — so "live rows only" would be a qualification
/// with nothing behind it (§11).
///
/// ### What is deliberately absent
///
/// * **No line status.** A return is received whole or not at all (§16.16). A
///   per-line status would be the database inviting partial receipt.
/// * **No `received_qty`.** Same reason: there is one quantity, and it is the one that
///   was rejected.
/// * **No location column.** The destination is the Warehouse Pusat, resolved by type
///   at receive time, for every line (§21). A per-line location would let a UI
///   nominate an arbitrary destination — precisely the hole the access policy closes.
/// * **No editable line note.** The branch's words live on the header, the
///   Warehouse's in `warehouse_note`. A per-line free-text field on an immutable
///   snapshot would be a writer on a table that has none.
/// * **No expiry-date snapshot.** `item_batches.expiry_date` is master data that is
///   never edited in place, so a stored copy would be a second version of the same
///   fact. The detail reads it back through the batch, archived rows included (§37).
///
/// `qty` is INTEGER milli-units (Q-3); the repository converts it to `Quantity` and
/// nothing above it knows the scale.
@DataClassName('GoodsReturnLineRow')
@TableIndex(name: 'idx_goods_return_lines_return', columns: {#goodsReturnId})
@TableIndex(name: 'idx_goods_return_lines_gr_line', columns: {#grLineId})
@TableIndex(name: 'idx_goods_return_lines_item', columns: {#itemId})
@TableIndex(name: 'idx_goods_return_lines_batch', columns: {#batchId})
// One rejected Good Receipt position is returned exactly once, ever.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_goods_return_lines_gr_line_unique
  ON goods_return_lines (gr_line_id);
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_goods_return_lines_unique
  ON goods_return_lines (goods_return_id, gr_line_id);
''')
class GoodsReturnLines extends Table with BusinessColumns {
  TextColumn get goodsReturnId => text().references(GoodsReturns, #id)();

  /// The rejected Good Receipt position this line sends back. Unique twice: see the
  /// class note.
  TextColumn get grLineId => text().references(GoodReceiptLines, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  /// The batch that was rejected. NULL, and only NULL, for an item without expiry
  /// (G-E2); the create use case enforces both directions because the rule depends on
  /// `items.has_expiry`, which this table cannot read.
  ///
  /// An **expired** batch is entirely legitimate here, unlike on every outbound
  /// document in this schema. G-E5 says so directly — goods too close to their expiry
  /// date are a reason to reject, and a rejection has to be able to go home (§36).
  TextColumn get batchId => text().nullable().references(ItemBatches, #id)();

  /// Returned quantity in **milli-units** (Q-3), always equal to the source Good
  /// Receipt line's `shipped_qty`. Strictly positive: a return of nothing is not a
  /// line, and the ledger records changes rather than confirmations (G-A1).
  IntColumn get qty => integer()();

  /// The reason the branch head gave when refusing this position (G-G4), copied at
  /// creation. Mandatory and non-blank — see the class note.
  TextColumn get rejectReasonSnapshot => text()();

  @override
  List<String> get customConstraints => [
    'CHECK (qty > 0)',
    // G-G4's half of the snapshot. `IS NOT NULL` is written out rather than left to
    // `trim(...) <> ''`, and that is load-bearing: SQLite treats a CHECK whose result
    // is **NULL as satisfied**, and `trim(NULL) <> ''` is NULL. The column is already
    // NOT NULL, so this is defence in depth against a future migration relaxing it.
    'CHECK (reject_reason_snapshot IS NOT NULL '
        "AND trim(reject_reason_snapshot) <> '')",
  ];
}
