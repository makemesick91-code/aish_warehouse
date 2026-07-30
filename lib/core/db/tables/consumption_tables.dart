import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';

/// Pemakaian header — goods consumed in one treatment room, leaving the system
/// (schema v10, §8).
///
/// ### Why this table exists at all
///
/// The specification defines no Consumption *document*: §2.3 lists none and §3.2
/// gives it no state machine. What it does state is that `stock_movements` carries a
/// `consumption` movement type and that `to_location_id` is *"NULL jika barang
/// keluar sistem (pemakaian/buang)"* (§2.2). A bare movement can carry an actor and
/// a note, but nothing that groups several positions into one shift's usage, and
/// nothing a branch head can read afterwards. So Milestone 8 wraps the movement in
/// the smallest auditable document that can: a header carrying the room, who
/// recorded it and who posted it, and one line per position used. **That extension
/// is a deliberate decision documented here rather than a rule the specification
/// states.**
///
/// ### One source room, stored as `branch_id` + `room_id`
///
/// Unlike `disposals`, which stores a source **location id** because a disposal may
/// leave a warehouse, a branch store or a room, this table stores the *room*. The
/// difference is that a consumption has exactly one possible shape of source: §2.5
/// puts room stock at the end of the chain, and the only person who consumes it is
/// the nurse working in it. The stock location is therefore derivable — the one
/// `room` location of `room_id` — and resolved by type at posting time (the same
/// rule `distributions` follows, §14 of that milestone), so no caller and no screen
/// can nominate an arbitrary location id.
///
/// `branch_id` is stored alongside it rather than derived from `rooms.branch_id`,
/// because it is the column every scoped read predicates on: a Kepala Cabang's
/// history query is `consumptions.branch_id = ?`, and resolving it through a join on
/// every read would put the branch scope one join away from the statement that
/// enforces it. The two must agree — `rooms.branch_id = consumptions.branch_id` — and
/// that is a cross-table equality SQLite cannot express as a foreign key, so it is
/// enforced at create, in the read queries, inside the posting transaction, and by
/// the security tests.
///
/// There is exactly one room per document. A single consumption never spans two
/// rooms: the balances it reduces belong to specific rooms, and a document covering
/// several would make *"whose stock was this"* a question with more than one answer.
/// The invariant is structural rather than checked — there is no line-level room
/// column and no statement that updates `room_id`.
///
/// ### `doc_number` is unique **absolutely**, not partially
///
/// The opname, Purchase Request, Delivery Order, Good Receipt and Distribusi tables
/// carry `UNIQUE(doc_number) WHERE deleted_at IS NULL`, so a soft-deleted draft does
/// not hold a server-assigned number hostage. This one follows `disposals` instead,
/// and G-A3 is why: *"nomor dokumen berurut dan tidak dipakai ulang."* A consumption
/// is the document that explains where room stock went, so a number that could be
/// reissued after a soft delete would let two rows answer to the same reference.
/// Until the sync backend assigns a real number the local one is `TMP-CNS-{uuid}`,
/// which is unique by construction, so the stricter index costs nothing.
///
/// Two absences are deliberate:
///
/// * **No lexical timestamp CHECK.** Timestamps are ISO-8601 TEXT, so
///   `posted_at >= created_at` in SQL compares characters rather than instants.
///   Ordering is decided by `DocumentTimestampPolicy` on UTC `DateTime`s. What the
///   CHECKs below state is what SQLite can answer without ambiguity: which
///   timestamps and which actor each status must and must not carry.
/// * **No line or quantity totals.** Every one of them is derivable from
///   `consumption_lines`, and a stored copy would be a second version of the same
///   fact that a writer could contradict.
///
/// ### No patient data, ever
///
/// There is no `patient_id`, no `patient_name`, no medical-record number, no
/// diagnosis and no procedure column, and none may be added here. This is an
/// *inventory* document: it records that three ampoules left a room, not who they
/// were used on. Personal health information has a wholly different retention,
/// access and consent story than a stock ledger, and a column that could hold it
/// would put it inside a table every branch head can read.
@DataClassName('ConsumptionRow')
@TableIndex(
  name: 'idx_consumptions_branch_status',
  columns: {#branchId, #status},
)
@TableIndex(name: 'idx_consumptions_room_status', columns: {#roomId, #status})
@TableIndex(
  name: 'idx_consumptions_created_by_status',
  columns: {#createdBy, #status},
)
@TableIndex(
  name: 'idx_consumptions_posted_by_status',
  columns: {#postedBy, #status},
)
@TableIndex(name: 'idx_consumptions_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_consumptions_posted_at', columns: {#postedAt})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_consumptions_doc_number
  ON consumptions (doc_number);
''')
class Consumptions extends Table with BusinessColumns {
  /// Temporary local number `TMP-CNS-{uuid}` until a sync backend assigns the final
  /// `CNS-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number offline
  /// would collide across devices — every room records its own usage.
  TextColumn get docNumber => text().withLength(min: 1, max: 64)();

  /// The branch whose room the goods leave. Must be the room's branch and the
  /// nurse's branch — cross-table equalities SQLite cannot express, so the use cases
  /// enforce them and the posting transaction revalidates them.
  TextColumn get branchId => text().references(Branches, #id)();

  /// The one room the goods are used in. Fixed at creation: there is no statement
  /// anywhere that updates this column.
  TextColumn get roomId => text().references(Rooms, #id)();

  /// The Perawat who recorded the usage (G-A3).
  @ReferenceName('createdConsumptions')
  TextColumn get createdBy => text().references(Users, #id)();

  TextColumn get status => text()
      .map(const ConsumptionStatusConverter())
      .clientDefault(() => ConsumptionStatus.draft.dbValue)();

  /// Free-text remark about the usage as a whole, e.g. *"pemakaian shift pagi"*.
  ///
  /// **Optional**, unlike `disposals.reason`. G-E7 makes a note mandatory on a
  /// disposal because destruction has to be explained; nothing in the specification
  /// asks a nurse to justify ordinary consumption, and inventing that requirement
  /// would be inventing a rule. What the CHECK below does refuse is *whitespace*
  /// pretending to be a remark.
  ///
  /// Never a place for patient information — see the class note.
  TextColumn get note => text().nullable()();

  /// UTC instant the consumption was posted and the room balance fell (T-1).
  DateTimeColumn get postedAt => dateTime().nullable()();

  /// Who posted it. Null exactly while the document is a draft.
  @ReferenceName('postedConsumptions')
  TextColumn get postedBy => text().nullable().references(Users, #id)();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the type converter: a hand-written UPDATE cannot
    // introduce a status the Dart enum does not know.
    "CHECK (status IN ('draft', 'posted'))",
    // The posting instant and the posting actor both exist exactly when the
    // document has posted. Stated exhaustively over both statuses so a new one
    // cannot quietly land in neither branch.
    //
    // Deliberately *not* extended with a note requirement the way the disposal's
    // equivalent is: a consumption note is optional, so a posted row with no note
    // is a compliant row rather than the one the CHECK exists to prevent.
    "CHECK ((status = 'draft' AND posted_at IS NULL AND posted_by IS NULL) "
        "OR (status = 'posted' AND posted_at IS NOT NULL "
        'AND posted_by IS NOT NULL))',
    // A *stored* note must say something, whatever the status. The `IS NULL OR`
    // branch is load-bearing: SQLite treats a CHECK whose result is **NULL as
    // satisfied**, and `trim(NULL) <> ''` is NULL — so the NULL case has to be
    // accepted explicitly rather than by accident, because this column is
    // legitimately NULL on most compliant rows.
    "CHECK (note IS NULL OR trim(note) <> '')",
  ];
}

/// One consumed position — *one item, one batch* (§9).
///
/// The two partial unique indexes below are what stop the same position appearing
/// twice on one document, which would take double the quantity off the room's shelf
/// while every per-line check still passed. `deleted_at IS NULL` is what lets a line
/// removed from a draft be added back afterwards, and the split between the batched
/// and unbatched shapes exists because SQLite treats every NULL as distinct — one
/// index over `(…, batch_id)` would let an item without expiry be added to the same
/// document any number of times.
///
/// **`batch_id` is nullable**, unlike `disposal_lines`. That table exists to destroy
/// *expired* stock, and only an item with `has_expiry = true` has an expiry date to
/// be past. A consumption is ordinary usage: gauze without an expiry date is
/// consumed exactly as an anaesthetic with one is, so the rule here is G-E2's —
/// batch-tracked items move per batch, items without expiry never carry a batch. Both
/// directions depend on `items.has_expiry`, which this table cannot read, so the use
/// cases enforce them and revalidate them inside the posting transaction.
///
/// **No location column.** The source is the header's room, for every line. A
/// per-line location would let one document draw from two rooms, which is the
/// invariant the header exists to state — and a UI that could submit an arbitrary
/// location id is precisely the hole the access policy closes.
///
/// **No expiry-date snapshot.** `item_batches.expiry_date` is master data that is
/// never edited in place, so a stored copy would be a second version of the same fact
/// with nothing to reconcile it against. The posted detail reads it back through the
/// batch, archived rows included.
///
/// **No FEFO override reason**, unlike `distribution_lines`. G-E3 names FEFO for
/// *"saat warehouse membuat DO dan saat Kepala Cabang membuat distribusi"* and
/// nothing else; a nurse records the batch they physically took out of the drawer, and
/// demanding a written justification for that would be inventing a rule. The picker
/// still offers nearest-expiry first as operational help.
///
/// `qty` is INTEGER milli-units (Q-3); the repository converts it to `Quantity` and
/// nothing above it knows the scale.
///
/// **No patient data**, for the reason the header states. There is no procedure,
/// diagnosis or patient column here either, and `note` is for stock detail — *"dipakai
/// untuk tindakan pagi"* — never for identifying a person.
@DataClassName('ConsumptionLineRow')
@TableIndex(
  name: 'idx_consumption_lines_consumption',
  columns: {#consumptionId},
)
@TableIndex(name: 'idx_consumption_lines_item', columns: {#itemId})
@TableIndex(name: 'idx_consumption_lines_batch', columns: {#batchId})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_consumption_lines_batched
  ON consumption_lines (consumption_id, item_id, batch_id)
  WHERE batch_id IS NOT NULL AND deleted_at IS NULL;
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_consumption_lines_unbatched
  ON consumption_lines (consumption_id, item_id)
  WHERE batch_id IS NULL AND deleted_at IS NULL;
''')
class ConsumptionLines extends Table with BusinessColumns {
  TextColumn get consumptionId => text().references(Consumptions, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  /// The batch used. NULL, and only NULL, for an item without expiry (G-E2); the use
  /// case enforces both directions because the rule depends on `items.has_expiry`,
  /// which this table cannot read.
  TextColumn get batchId => text().nullable().references(ItemBatches, #id)();

  /// Consumed quantity in **milli-units** (Q-3). Strictly positive: a consumption of
  /// nothing is not a line, and the ledger records changes rather than confirmations
  /// (G-A1).
  IntColumn get qty => integer()();

  /// Optional per-line detail, e.g. *"1 ampul pecah saat dibuka"*. Adds specificity
  /// to one position; never patient information.
  TextColumn get note => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (qty > 0)',
    // A stored note must say something. The `IS NULL OR` branch is load-bearing for
    // the SQLite quirk the header's note CHECK spells out: a CHECK evaluating to
    // NULL counts as satisfied, so the NULL case has to be accepted *explicitly*
    // rather than by accident — this column is legitimately NULL on most lines.
    "CHECK (note IS NULL OR trim(note) <> '')",
  ];
}
