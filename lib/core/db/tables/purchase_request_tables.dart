import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';
import 'opname_tables.dart';

/// Purchase Request header — one order from a branch to the central warehouse
/// (schema v5, spec §2.3).
///
/// Beyond the business columns the specification lists, the table carries the
/// audit metadata every transition needs: who moved the document and the UTC
/// instant they did it (G-A3). They are separate column pairs per event rather
/// than one `status_changed_by`/`status_changed_at`, because a rejected document
/// must still be able to say who processed it *and* who rejected it — a single
/// pair would overwrite the first answer with the second.
///
/// Two absences are deliberate:
///
/// * **No lexical timestamp CHECK.** Timestamps are stored as ISO-8601 TEXT, so
///   `processing_at >= submitted_at` in SQL compares characters rather than
///   instants — the same defect schema v4 removed from `stock_opnames`.
///   Ordering is decided by `DocumentWorkflowTimestampPolicy` on UTC
///   `DateTime`s. What the CHECKs below *do* state is the question SQLite can
///   answer without ambiguity: which timestamps each status must and must not
///   carry.
/// * **No ledger column of any kind.** A Purchase Request never moves stock
///   (spec §2.5): the first posting happens when the warehouse ships a Delivery
///   Order.
@DataClassName('PurchaseRequestRow')
@TableIndex(
  name: 'idx_purchase_requests_branch_status',
  columns: {#branchId, #status},
)
@TableIndex(
  name: 'idx_purchase_requests_requested_by_status',
  columns: {#requestedBy, #status},
)
@TableIndex(name: 'idx_purchase_requests_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_purchase_requests_needed_date', columns: {#neededDate})
// G-P4, and this index — not the use case — is the guarantee. Only one *live*
// document per branch may sit in `submitted` or `processing`, so two devices
// racing to submit produce one active order and one constraint violation the
// repository turns into `PurchaseRequestAlreadyActiveFailure`. Everything the
// rule deliberately permits follows from the WHERE clause: several drafts do not
// collide because `draft` is outside it, and a cancelled, rejected, shipped or
// closed document releases the slot for the same reason.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_purchase_requests_active_branch
  ON purchase_requests (branch_id)
  WHERE status IN ('submitted', 'processing') AND deleted_at IS NULL;
''')
// Document numbers are unique among live documents only, for the reason the
// opname tables spell out: once the sync backend issues real numbers
// (`PR-{cabang}-{yyyyMMdd}-{seq}`), a soft-deleted row must not hold one hostage.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_purchase_requests_doc_number
  ON purchase_requests (doc_number)
  WHERE deleted_at IS NULL;
''')
class PurchaseRequests extends Table with BusinessColumns {
  /// Temporary local number `TMP-PR-{uuid}` until a sync backend assigns the
  /// final `PR-{cabang}-{yyyyMMdd}-{seq}` on submit (G-Y4). Minting a
  /// server-shaped number offline would collide across devices.
  TextColumn get docNumber => text().withLength(min: 1, max: 64)();

  TextColumn get branchId => text().references(Branches, #id)();

  /// The Kepala Cabang who raised the request.
  TextColumn get requestedBy => text().references(Users, #id)();

  TextColumn get status => text()
      .map(const PurchaseRequestStatusConverter())
      .clientDefault(() => PurchaseRequestStatus.draft.dbValue)();

  /// Target arrival date — a **civil date** (T-8), stored as UTC midnight and
  /// never timezone converted.
  DateTimeColumn get neededDate => dateTime().nullable()();

  TextColumn get note => text().nullable()();

  // --- transition audit; every instant is UTC (T-1) --------------------------

  DateTimeColumn get submittedAt => dateTime().nullable()();

  DateTimeColumn get processingAt => dateTime().nullable()();

  /// The warehouse officer who took the order on.
  @ReferenceName('processedPurchaseRequests')
  TextColumn get processedBy => text().nullable().references(Users, #id)();

  DateTimeColumn get cancelledAt => dateTime().nullable()();

  /// The Kepala Cabang who withdrew the request — normally, and legitimately,
  /// the same person as [requestedBy].
  @ReferenceName('cancelledPurchaseRequests')
  TextColumn get cancelledBy => text().nullable().references(Users, #id)();

  /// Why the request was withdrawn. Mandatory for a cancelled document: the
  /// detail screen shows it (§24.4) and an audit trail that records only
  /// "cancelled" explains nothing.
  TextColumn get cancelReason => text().nullable()();

  DateTimeColumn get rejectedAt => dateTime().nullable()();

  @ReferenceName('rejectedPurchaseRequests')
  TextColumn get rejectedBy => text().nullable().references(Users, #id)();

  /// Mandatory when rejected (spec §3.2: "rejected (oleh warehouse, wajib
  /// alasan)").
  TextColumn get rejectReason => text().nullable()();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the type converter: a hand-written UPDATE cannot
    // introduce a status the Dart enum does not know.
    "CHECK (status IN ('draft', 'submitted', 'processing', 'shipped', "
        "'closed', 'rejected', 'cancelled'))",
    // A draft has not been handed over, so it carries no submission instant…
    "CHECK (status <> 'draft' OR submitted_at IS NULL)",
    // …and every status past draft does, with one exception: a draft that was
    // cancelled before it was ever sent.
    "CHECK (submitted_at IS NOT NULL OR status IN ('draft', 'cancelled'))",
    // The processing pair is written together or not at all.
    'CHECK ((processing_at IS NULL AND processed_by IS NULL) '
        'OR (processing_at IS NOT NULL AND processed_by IS NOT NULL))',
    // Which statuses have been through the warehouse, stated exhaustively so a
    // new status cannot quietly land in neither branch.
    "CHECK ((status IN ('processing', 'shipped', 'closed', 'rejected') "
        'AND processing_at IS NOT NULL) '
        "OR (status IN ('draft', 'submitted', 'cancelled') "
        'AND processing_at IS NULL))',
    // A rejection carries actor, instant and a non-blank reason; anything else
    // carries none of the three. `trim(...) <> ''` is what makes a reason of
    // spaces fail here too, not only in the use case.
    "CHECK ((status = 'rejected' AND rejected_at IS NOT NULL "
        'AND rejected_by IS NOT NULL AND reject_reason IS NOT NULL '
        "AND trim(reject_reason) <> '') "
        "OR (status <> 'rejected' AND rejected_at IS NULL "
        'AND rejected_by IS NULL AND reject_reason IS NULL))',
    // Same shape for cancellation.
    "CHECK ((status = 'cancelled' AND cancelled_at IS NOT NULL "
        'AND cancelled_by IS NOT NULL AND cancel_reason IS NOT NULL '
        "AND trim(cancel_reason) <> '') "
        "OR (status <> 'cancelled' AND cancelled_at IS NULL "
        'AND cancelled_by IS NULL AND cancel_reason IS NULL))',
    // Segregation of duties (G-R4): the branch head who raises an order is not
    // the person who fulfils or refuses it. The role check in the use cases
    // already implies this — `kepala_cabang` and `warehouse` are different rows
    // — and the constraint is what keeps it true if a user's role is ever
    // edited underneath a document.
    'CHECK (processed_by IS NULL OR processed_by <> requested_by)',
    'CHECK (rejected_by IS NULL OR rejected_by <> requested_by)',
  ];
}

/// Tautan PR ⇆ opname acuan (spec §2.3, many-to-many).
///
/// The link is the evidence behind G-P1: a Purchase Request cites the physical
/// counts its quantities were derived from, and those counts must have been
/// `submitted`/`reviewed` in the current or previous operational week when the
/// document was created and again when it was submitted.
///
/// Uniqueness is a *partial* index for the same reason it is on the opname
/// lines: it applies to live rows, so replacing the selection on a draft
/// (soft-deleting a link and adding it back later) must not be blocked by
/// history.
@DataClassName('PurchaseRequestOpnameRow')
@TableIndex(name: 'idx_purchase_request_opnames_pr', columns: {#prId})
@TableIndex(name: 'idx_purchase_request_opnames_opname', columns: {#opnameId})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_purchase_request_opnames_unique
  ON purchase_request_opnames (pr_id, opname_id)
  WHERE deleted_at IS NULL;
''')
class PurchaseRequestOpnames extends Table with BusinessColumns {
  TextColumn get prId => text().references(PurchaseRequests, #id)();

  TextColumn get opnameId => text().references(StockOpnames, #id)();
}

/// One requested item of a Purchase Request.
///
/// Both quantities are INTEGER milli-units (Q-3); the repository converts them
/// to `Quantity` and nothing above it knows the scale.
///
/// There is no `batch_id`, and that is the rule rather than an omission: a
/// branch asks for *an item*, and which batches satisfy the request is the
/// warehouse's FEFO decision at Delivery Order time (G-E3). An expiry-tracked
/// item therefore occupies exactly one line here even though the opname counted
/// it per batch.
///
/// `suggested_qty` is a **snapshot**, taken when the draft is created and
/// recomputed only while the draft's opname selection changes. It is not a live
/// view of stock: once the document is submitted, the number the warehouse sees
/// is the number the branch head saw.
@DataClassName('PurchaseRequestLineRow')
@TableIndex(name: 'idx_purchase_request_lines_pr', columns: {#prId})
@TableIndex(name: 'idx_purchase_request_lines_item', columns: {#itemId})
// G-P2's second half — one line per item per document — as a partial unique
// index. `deleted_at IS NULL` is what lets an item removed from a draft be
// added back afterwards.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_purchase_request_lines_item_unique
  ON purchase_request_lines (pr_id, item_id)
  WHERE deleted_at IS NULL;
''')
class PurchaseRequestLines extends Table with BusinessColumns {
  TextColumn get prId => text().references(PurchaseRequests, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  /// `max(0, min_stock_room − counted_qty)` aggregated over the linked opnames'
  /// rooms. Zero for a line the branch head added by hand.
  IntColumn get suggestedQty => integer()();

  /// What the branch head actually asks for. Strictly positive (G-P2).
  IntColumn get requestedQty => integer()();

  /// Justification. Mandatory when the request exceeds 150 % of the suggestion,
  /// or when there is no suggestion at all to exceed (G-P3) — enforced over the
  /// whole document at submit time rather than by a CHECK, because a draft must
  /// be saveable while the reason is still being typed.
  TextColumn get note => text().nullable()();

  @override
  List<String> get customConstraints => [
    // A suggestion of zero is meaningful ("we have enough, or there is no
    // reference"); a negative one is not.
    'CHECK (suggested_qty >= 0)',
    // G-P2, first half.
    'CHECK (requested_qty > 0)',
  ];
}
