import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';

/// Pemusnahan header — expired stock leaving one location for good (schema v9,
/// G-E7).
///
/// ### Why this table exists at all
///
/// The specification defines no Disposal *document*: §2.3 lists none and §3.2
/// gives it no state machine. What it does state is G-E7 — *"Barang kedaluwarsa
/// dikeluarkan dari stok hanya lewat movement `disposal` (pemusnahan) dengan
/// catatan & pelaku — bukan dengan mengedit saldo."* A bare movement can carry a
/// note and an actor, but nothing that groups several batches into one physical
/// act of destruction, and nothing a second person can read afterwards. So
/// Milestone 7 wraps the movement in the smallest auditable document that can:
/// a header carrying the source, the reason, who created it and who posted it,
/// and one line per expired position. That extension is a deliberate decision
/// documented here rather than a rule the specification states.
///
/// ### One source location, and it is stored
///
/// Unlike `distributions`, which stores a *branch* and resolves the store by
/// type (§14), this table stores the source **location id** outright. The two
/// are different problems. A distribution always leaves the one *Gudang Cabang*
/// of its branch, so the location is derivable and storing it would be a second
/// copy of a fact the location table already holds. A disposal may leave the
/// central warehouse, a branch store *or* any one of a branch's rooms — three
/// location types with nothing to derive them from — so the document has to name
/// the row it drew from. Which rows an actor may name is
/// `DisposalLocationPolicy`'s answer, revalidated inside the posting
/// transaction; SQLite can only state that the id resolves.
///
/// There is exactly one of them per document. A single disposal never spans two
/// locations: the balances it reduces belong to specific shelves, and a document
/// covering several would make "who is allowed to post this" a question with
/// more than one answer.
///
/// ### `doc_number` is unique **absolutely**, not partially
///
/// Every other document in this schema carries
/// `UNIQUE(doc_number) WHERE deleted_at IS NULL`, so a soft-deleted draft does
/// not hold a server-assigned number hostage. This one deliberately does not,
/// and G-A3 is why: *"nomor dokumen berurut dan tidak dipakai ulang."* A
/// destruction record is the document an auditor reaches for when stock is
/// missing, and a number that could be reissued after a soft delete would make
/// two rows answer to the same reference. Until the sync backend assigns a real
/// number the local one is `TMP-DSP-{uuid}`, which is unique by construction, so
/// the stricter index costs nothing.
///
/// Two absences are deliberate:
///
/// * **No lexical timestamp CHECK.** Timestamps are ISO-8601 TEXT, so
///   `posted_at >= created_at` in SQL compares characters rather than instants.
///   Ordering is decided by `DocumentTimestampPolicy` on UTC `DateTime`s. What
///   the CHECKs below state is what SQLite can answer without ambiguity: which
///   timestamps and which actor each status must and must not carry.
/// * **No line or quantity totals.** Every one of them is derivable from
///   `disposal_lines`, and a stored copy would be a second version of the same
///   fact that a writer could contradict.
@DataClassName('DisposalRow')
@TableIndex(
  name: 'idx_disposals_source_location_status',
  columns: {#sourceLocationId, #status},
)
@TableIndex(
  name: 'idx_disposals_created_by_status',
  columns: {#createdBy, #status},
)
@TableIndex(
  name: 'idx_disposals_posted_by_status',
  columns: {#postedBy, #status},
)
@TableIndex(name: 'idx_disposals_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_disposals_posted_at', columns: {#postedAt})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_disposals_doc_number
  ON disposals (doc_number);
''')
class Disposals extends Table with BusinessColumns {
  /// Temporary local number `TMP-DSP-{uuid}` until a sync backend assigns the
  /// final `DSP-{lokasi}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number
  /// offline would collide across devices — every branch disposes on its own.
  TextColumn get docNumber => text().withLength(min: 1, max: 64)();

  /// The one location the goods physically leave.
  ///
  /// Warehouse Pusat for a `warehouse` actor; the acting branch head's own
  /// *Gudang Cabang* or one of their rooms otherwise. Which of those an actor may
  /// name is a cross-table question (`users.branch_id` against
  /// `stock_locations.branch_id`) that SQLite cannot express as a foreign key, so
  /// `DisposalLocationPolicy` enforces it and the posting transaction
  /// revalidates it.
  TextColumn get sourceLocationId => text().references(StockLocations, #id)();

  /// Who raised the document (G-A3).
  @ReferenceName('createdDisposals')
  TextColumn get createdBy => text().references(Users, #id)();

  TextColumn get status => text()
      .map(const DisposalStatusConverter())
      .clientDefault(() => DisposalStatus.draft.dbValue)();

  /// G-E7's mandatory note, at document level.
  ///
  /// Nullable while the document is a draft — the form opens before the reason is
  /// typed — and mandatory the moment it posts, which is what the status CHECK
  /// below states. The domain is stricter than the CHECK can be: `String.trim()`
  /// in Dart removes tabs and newlines, and SQLite's `trim()` removes spaces
  /// only, so a reason of `"\n\n"` passes the database and is refused by
  /// `DisposalReasonPolicy`. The CHECK is the floor, not the authority.
  TextColumn get reason => text().nullable()();

  /// UTC instant the disposal was posted and the balance fell (T-1).
  DateTimeColumn get postedAt => dateTime().nullable()();

  /// Who posted it (G-E7's *pelaku*). Null exactly while the document is a draft.
  @ReferenceName('postedDisposals')
  TextColumn get postedBy => text().nullable().references(Users, #id)();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the type converter: a hand-written UPDATE cannot
    // introduce a status the Dart enum does not know.
    "CHECK (status IN ('draft', 'posted'))",
    // The posting instant, the posting actor and the reason all exist exactly
    // when the document has posted. Stated exhaustively over both statuses so a
    // new one cannot quietly land in neither branch.
    //
    // `reason IS NOT NULL AND trim(reason) <> ''` rather than `trim(reason) <>
    // ''` alone, and the difference is load-bearing: SQLite treats a CHECK whose
    // result is **NULL as satisfied**, and `trim(NULL)` is NULL. Written the
    // short way a posted row with no reason at all would pass — which is exactly
    // the row G-E7 exists to prevent.
    "CHECK ((status = 'draft' AND posted_at IS NULL AND posted_by IS NULL) "
        "OR (status = 'posted' AND posted_at IS NOT NULL "
        "AND posted_by IS NOT NULL "
        "AND reason IS NOT NULL AND trim(reason) <> ''))",
    // A *stored* reason must say something, whatever the status. This is the
    // draft half: an empty string is not a reason, and letting one sit in a draft
    // would mean the posting CHECK is the first thing that ever looks at it.
    "CHECK (reason IS NULL OR trim(reason) <> '')",
  ];
}

/// One destroyed position — *one item, one batch* (G-E7).
///
/// The grain is the batch, and it has to be: expiry is a property of the batch,
/// so "which of this product was destroyed" has no answer at item level. The
/// partial unique index below is what stops the same position appearing twice on
/// one document, which would take double the quantity off the shelf while every
/// per-line check still passed. `deleted_at IS NULL` is what lets a line removed
/// from a draft be added back afterwards.
///
/// **`batch_id` is NOT NULL**, unlike every other line table in this schema. This
/// milestone disposes of *expired* stock and nothing else, and only an item with
/// `has_expiry = true` has an expiry date to be past — so a line without a batch
/// would be a line about something that cannot be expired. Disposal of damaged,
/// recalled or rejected goods is a different workflow with different eligibility
/// rules, and it is not opened here; when it is, it will need its own eligibility
/// column rather than a nullable batch on this one.
///
/// **No location column.** The source is the header's, for every line. A per-line
/// location would let one document draw from two shelves, which is the invariant
/// the header exists to state — and a UI that could submit an arbitrary location
/// id is precisely the hole the access policy closes.
///
/// **No expiry-date snapshot.** `item_batches.expiry_date` is master data that is
/// never edited in place, so a stored copy would be a second version of the same
/// fact with nothing to reconcile it against. The posted detail reads it back
/// through the batch, archived rows included.
///
/// `qty` is INTEGER milli-units (Q-3); the repository converts it to `Quantity`
/// and nothing above it knows the scale.
@DataClassName('DisposalLineRow')
@TableIndex(name: 'idx_disposal_lines_disposal', columns: {#disposalId})
@TableIndex(name: 'idx_disposal_lines_item', columns: {#itemId})
@TableIndex(name: 'idx_disposal_lines_batch', columns: {#batchId})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_disposal_lines_position
  ON disposal_lines (disposal_id, item_id, batch_id)
  WHERE deleted_at IS NULL;
''')
class DisposalLines extends Table with BusinessColumns {
  TextColumn get disposalId => text().references(Disposals, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  /// The batch being destroyed. Never NULL — see the class note.
  TextColumn get batchId => text().references(ItemBatches, #id)();

  /// Destroyed quantity in **milli-units** (Q-3). Strictly positive: a disposal
  /// of nothing is not a line, and the ledger records changes rather than
  /// confirmations (G-A1).
  IntColumn get qty => integer()();

  /// Optional per-line detail, e.g. *"kemasan bocor"*. Never a substitute for the
  /// header's `reason`, which G-E7 makes mandatory; this only adds specificity to
  /// one position.
  TextColumn get note => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (qty > 0)',
    // A stored note must say something. The `IS NULL OR` branch is load-bearing
    // in the opposite direction to the header's reason CHECK, and for the same
    // SQLite quirk: a CHECK evaluating to NULL counts as satisfied, so the NULL
    // case has to be accepted *explicitly* rather than by accident — this column
    // is legitimately NULL on most compliant lines.
    "CHECK (note IS NULL OR trim(note) <> '')",
  ];
}
