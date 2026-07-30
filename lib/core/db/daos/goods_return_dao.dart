import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/delivery_tables.dart';
import '../tables/good_receipt_tables.dart';
import '../tables/goods_return_tables.dart';
import '../tables/inventory_tables.dart';
import '../tables/master_tables.dart';
import '../tables/purchase_request_tables.dart';

part 'goods_return_dao.g.dart';

/// A Retur header joined with everything a list row or a detail header needs, plus
/// the per-document counts a summary shows.
///
/// None of the joins filter `is_active` or `deleted_at`, which is what keeps a
/// received return readable after its branch, the items on it, or any of its three
/// actors are retired. The repository turns that into `…IsHistorical` flags the
/// screens can label rather than into a row that quietly disappears (§37).
class GoodsReturnWithContext {
  const GoodsReturnWithContext({
    required this.goodsReturn,
    required this.receipt,
    required this.order,
    required this.request,
    required this.branch,
    required this.createdBy,
    this.shippedBy,
    this.receivedBy,
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
    required this.totalQtyMilliUnits,
  });

  final GoodsReturnRow goodsReturn;

  /// The Good Receipt whose rejections this document returns. Always present — the
  /// foreign key guarantees the row exists and the join filters nothing.
  final GoodReceiptRow receipt;

  /// The shipment the receipt checked in, and the request behind it. Both reached
  /// through the receipt so the branch screens can show the whole chain — GR, Surat
  /// Jalan, PR — without a second round trip (§29).
  final DeliveryOrderRow order;
  final PurchaseRequestRow request;

  final Branch branch;

  final AppUser createdBy;

  /// `null` exactly while the document is a draft.
  final AppUser? shippedBy;

  /// `null` until the Warehouse confirms arrival.
  final AppUser? receivedBy;

  final int lineCount;
  final int itemCount;

  /// Distinct batches. An item without expiry contributes none, so this can be lower
  /// than [lineCount] on a compliant document.
  final int batchCount;

  /// Sum of every live line's `qty`, in **milli-units** (Q-3). Aggregated in SQL
  /// rather than in Dart so a list of fifty documents is one query; the repository
  /// converts it to `Quantity`.
  ///
  /// A single total across units is deliberately *not* what the screens show — §29
  /// asks for totals **per unit**, which needs the lines. This is the cheap
  /// cross-check the detail's per-unit breakdown must add back up to.
  final int totalQtyMilliUnits;
}

/// The five facts an authorization check needs, and nothing else.
///
/// Deliberately not the joined summary: deciding whether a return may be shown must
/// not be the reason its number, its receipt, its items, its batches, its quantities
/// or its reject reasons are read (§27).
class GoodsReturnAccessRow {
  const GoodsReturnAccessRow({
    required this.goodsReturnId,
    required this.grId,
    required this.branchId,
    required this.createdBy,
    this.shippedBy,
    this.receivedBy,
    required this.status,
  });

  final String goodsReturnId;
  final String grId;
  final String branchId;
  final String createdBy;
  final String? shippedBy;
  final String? receivedBy;
  final GoodsReturnStatus status;
}

/// One return line joined with its item and, when it has one, its batch.
///
/// `batch` is nullable because `goods_return_lines.batch_id` is: an item without an
/// expiry date is returned without one (G-E2).
class GoodsReturnLineWithDetails {
  const GoodsReturnLineWithDetails({
    required this.line,
    required this.item,
    this.batch,
  });

  final GoodsReturnLineRow line;
  final Item item;
  final ItemBatch? batch;
}

/// One posted Good Receipt that still owes the Warehouse a return, joined with its
/// chain and its rejected-line aggregate (§16).
///
/// [existingReturn] is `null` exactly while the receipt is still eligible. It is
/// carried rather than filtered out because the *Perlu Dibuat* queue and the Good
/// Receipt discrepancy page ask the same query two different questions: "which
/// receipts still need one" and "what happened to this receipt's return" (§33).
class RejectedGoodReceiptRow {
  const RejectedGoodReceiptRow({
    required this.receipt,
    required this.order,
    required this.request,
    required this.branch,
    this.existingReturn,
    required this.rejectedLineCount,
    required this.rejectedQtyMilliUnits,
  });

  final GoodReceiptRow receipt;
  final DeliveryOrderRow order;
  final PurchaseRequestRow request;
  final Branch branch;

  /// The return already raised for this receipt, or `null`.
  final GoodsReturnRow? existingReturn;

  /// How many `rejected` lines the receipt carries. Always ≥ 1 — the query requires
  /// it, because a receipt with none has nothing to return (§16).
  final int rejectedLineCount;

  /// Their total `shipped_qty`, in **milli-units** (Q-3).
  final int rejectedQtyMilliUnits;
}

/// One rejected Good Receipt line joined with its item and batch — the raw material
/// the snapshot is cut from (§17).
class RejectedGoodReceiptLineRow {
  const RejectedGoodReceiptLineRow({
    required this.line,
    required this.item,
    this.batch,
  });

  final GoodReceiptLineRow line;
  final Item item;
  final ItemBatch? batch;
}

/// Retur Barang persistence (schema v11, §24).
///
/// The same absences that shape [OpnameDao], [PurchaseRequestDao],
/// [DeliveryOrderDao], [GoodReceiptDao], [DistributionDao], [DisposalDao] and
/// [ConsumptionDao] shape this one, and this document adds several of its own:
///
/// * **No unrestricted status writer.** There is no `setStatus`. The two transitions
///   this milestone opens each have their own method naming the status it expects to
///   move *from*, so both predicates travel into the same statement as the write and
///   a stale screen or a racing device cannot ship or receive twice (G-S1). Every
///   guarded write returns the number of affected rows; zero means the guard fired.
/// * **No un-ship, no un-receive and no reopen.** `received` has no outgoing
///   transition at all and `shipped` has only the forward one, so there is no method
///   that could express one.
/// * **No line writer of any kind, after the insert.** This is the strictest table in
///   the schema: `insertLines` is the *only* statement that ever touches
///   `goods_return_lines`. There is no update, no soft delete, no quantity setter and
///   no reason setter (§18). A return says "here is exactly what you sent that we
///   refused", and a line somebody could edit afterwards would be a different claim.
/// * **No hard delete.** Nothing here removes a row (G-A5) — and nothing soft-deletes
///   one either, which is why the unique indexes on `gr_id` and `gr_line_id` are
///   unqualified.
/// * **No Good Receipt writer.** A posted receipt is final (G-S2). Raising a return
///   from it changes nothing about it; the link is read from `goods_returns.gr_id`.
/// * **No destination parameter anywhere.** The Warehouse Pusat location is resolved
///   by *type* by the caller (§21), so no screen can nominate an arbitrary location
///   id. That is the database half of *"a return always goes to the Warehouse"*:
///   there is no column to write and no parameter to pass.
/// * **No balance writer.** Stock changes only through `StockPostingService`, and a
///   DAO that could also increment a balance would be a second way into the ledger.
/// * **No cross-scope read.** Every summary and access read takes a
///   [GoodsReturnQueryScope] whose predicate goes into the statement, and the
///   Warehouse scope carries `status IN ('shipped', 'received')` inside it. A
///   Warehouse query cannot return a branch's draft even if a caller passed a status
///   set that asked for one.
///
/// Like the other DAOs this is a milli-unit layer (Q-4): `qty` and `shipped_qty` are
/// INTEGER columns holding `unit * 1000`, and the repository above converts them to
/// `Quantity`.
///
/// ### Nothing here compares a timestamp in SQL
///
/// `created_at`, `shipped_at` and `received_at` are ISO-8601 TEXT (`build.yaml`), so a
/// SQL `>=` between two of them — or against a serialised "now" — compares characters
/// rather than instants. Every ordering and every date window this feature applies is
/// applied in Dart on UTC `DateTime`s (§39). The `ORDER BY` clauses below on those
/// columns are the one permitted use: a *stable* order is all they promise, and the
/// repository re-sorts by instant wherever chronology is the point.
@DriftAccessor(
  tables: [
    GoodsReturns,
    GoodsReturnLines,
    GoodReceipts,
    GoodReceiptLines,
    DeliveryOrders,
    PurchaseRequests,
    StockMovements,
    StockLocations,
    Items,
    ItemBatches,
    Branches,
    Users,
  ],
)
class GoodsReturnDao extends DatabaseAccessor<AppDatabase>
    with _$GoodsReturnDaoMixin {
  GoodsReturnDao(super.db);

  /// Runs [action] in one transaction.
  ///
  /// The receive owns exactly one of these, and every write it performs — the ledger
  /// movements, the Warehouse balance updates, the document status, its timestamp,
  /// its receiving actor and the Warehouse note — happens inside it. Nothing below
  /// opens a transaction of its own for a single line, because a failure on the last
  /// movement must roll the first one back (§23).
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      transaction(action);

  // --- writes ---------------------------------------------------------------

  Future<GoodsReturnRow> insertHeader(GoodsReturnsCompanion header) =>
      into(goodsReturns).insertReturning(header);

  /// The **only** statement in this class that touches `goods_return_lines`.
  ///
  /// A batch insert rather than one call per line, and inside the caller's
  /// transaction: a return whose snapshot is half written is a return that no longer
  /// says what the branch refused (§18).
  Future<void> insertLines(List<GoodsReturnLinesCompanion> lines) async {
    await batch((batch) => batch.insertAll(goodsReturnLines, lines));
  }

  /// Updates the note of a **draft** belonging to the acting branch head's branch.
  ///
  /// Both predicates are in the statement: `status = 'draft'`, so a note cannot be
  /// rewritten once the goods are in transit however stale the screen that tried, and
  /// `branch_id = ?`, so one branch cannot edit another's draft even if a use-case
  /// check were somehow skipped (§19).
  ///
  /// `warehouse_note` is deliberately out of reach here — it is the Warehouse's word,
  /// written only by [markReceived].
  Future<int> updateDraftNote({
    required String goodsReturnId,
    required String branchId,
    required String? note,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE goods_returns '
      'SET note = ?, updated_at = ?, sync_status = ? '
      "WHERE id = ? AND branch_id = ? AND status = 'draft' "
      '  AND deleted_at IS NULL;',
      variables: [
        if (note == null)
          const Variable<String>(null)
        else
          Variable<String>(note),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(goodsReturnId),
        Variable<String>(branchId),
      ],
      updates: {goodsReturns},
      updateKind: UpdateKind.update,
    );
  }

  /// `draft → shipped`.
  ///
  /// Four predicates make a double ship — and an empty one, and one driven from the
  /// wrong branch — impossible at the moment of the write rather than at the moment
  /// of the read:
  ///
  /// * `status = 'draft'`, so a second device cannot ship the same document;
  /// * `branch_id = ?`, so only the owning branch hands the goods over;
  /// * `deleted_at IS NULL`;
  /// * `EXISTS` at least one line, so a snapshot that somehow ended up empty is
  ///   caught here as well as by the guards.
  ///
  /// A return value of 0 means one of them fired, and the caller reports it as a
  /// concurrent update rather than silently succeeding.
  ///
  /// The instant is forced to UTC here rather than trusted from the caller (T-1),
  /// because drift serialises a non-UTC `DateTime` with an offset suffix and a value
  /// that arrived in operational time would be *stored* as a different instant than
  /// the one the domain validated.
  Future<int> markShipped({
    required String goodsReturnId,
    required String branchId,
    required DateTime shippedAtUtc,
    required String shippedBy,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE goods_returns '
      'SET status = ?, shipped_at = ?, shipped_by = ?, updated_at = ?, '
      '    sync_status = ? '
      "WHERE id = ? AND branch_id = ? AND status = 'draft' "
      '  AND deleted_at IS NULL '
      '  AND EXISTS ('
      '    SELECT 1 FROM goods_return_lines '
      '    WHERE goods_return_id = goods_returns.id AND deleted_at IS NULL'
      '  );',
      variables: [
        Variable<String>(GoodsReturnStatus.shipped.dbValue),
        Variable<DateTime>(shippedAtUtc.toUtc()),
        Variable<String>(shippedBy),
        Variable<DateTime>(now),
        // Once the document leaves the device it is the server's to confirm (G-Y2),
        // so every transition queues a sync.
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(goodsReturnId),
        Variable<String>(branchId),
      ],
      updates: {goodsReturns},
      updateKind: UpdateKind.update,
    );
  }

  /// `shipped → received`, with the Warehouse's optional note, in one statement.
  ///
  /// Six predicates, and every one of them is a rule rather than a convenience:
  ///
  /// * `status = 'shipped'`, so a draft cannot be received and a received document
  ///   cannot be received again — the database half of *exactly one* concurrent
  ///   winner;
  /// * `deleted_at IS NULL`;
  /// * `created_by <> ?` and (`shipped_by IS NULL OR shipped_by <> ?`) — G-R4, in the
  ///   same statement as the write. The guards ask this too, and asking twice is the
  ///   point: the guard produces the sentence a user can read, and this makes the rule
  ///   hold even if a role changed between the check and the write (§15/§21);
  /// * `EXISTS` at least one line;
  /// * no branch predicate, deliberately — a Warehouse user works across every branch
  ///   (§15), and the scope that keeps them out of drafts is the status one above.
  ///
  /// There is **no** `branch_id` parameter and no destination parameter: the
  /// Warehouse Pusat location the ledger credits is resolved by type by the caller and
  /// never reaches this statement (§24).
  ///
  /// Note that the note is written *here*, inside the receive transaction, rather than
  /// by a separate call — so a rolled-back receive leaves `warehouse_note` exactly as
  /// it was (§21).
  Future<int> markReceived({
    required String goodsReturnId,
    required DateTime receivedAtUtc,
    required String receivedBy,
    required String? warehouseNote,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE goods_returns '
      'SET status = ?, received_at = ?, received_by = ?, warehouse_note = ?, '
      '    updated_at = ?, sync_status = ? '
      "WHERE id = ? AND status = 'shipped' "
      '  AND deleted_at IS NULL '
      '  AND created_by <> ? '
      '  AND (shipped_by IS NULL OR shipped_by <> ?) '
      '  AND EXISTS ('
      '    SELECT 1 FROM goods_return_lines '
      '    WHERE goods_return_id = goods_returns.id AND deleted_at IS NULL'
      '  );',
      variables: [
        Variable<String>(GoodsReturnStatus.received.dbValue),
        Variable<DateTime>(receivedAtUtc.toUtc()),
        Variable<String>(receivedBy),
        if (warehouseNote == null)
          const Variable<String>(null)
        else
          Variable<String>(warehouseNote),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(goodsReturnId),
        Variable<String>(receivedBy),
        Variable<String>(receivedBy),
      ],
      updates: {goodsReturns},
      updateKind: UpdateKind.update,
    );
  }

  // --- plain reads (no join can hide a row) ----------------------------------

  Future<GoodsReturnRow?> headerById(String id) => (select(
    goodsReturns,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// The return raised for one Good Receipt, if there is one.
  ///
  /// The question *"has this receipt already been returned"*, asked by the create use
  /// case before it writes and by the discrepancy page when it renders a status
  /// (§17/§33). Soft-deleted rows are excluded from the *answer* — but the unique
  /// index behind it is not partial, so a soft-deleted row still blocks a second
  /// insert. That asymmetry is intentional: the screen should not show a withdrawn
  /// document, and the database should still refuse to let its slot be reused.
  Future<GoodsReturnRow?> headerByGoodReceipt(String grId) =>
      (select(goodsReturns)
            ..where((t) => t.grId.equals(grId) & t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<GoodReceiptRow?> goodReceiptById(String grId) => (select(
    goodReceipts,
  )..where((t) => t.id.equals(grId) & t.deletedAt.isNull())).getSingleOrNull();

  /// Live lines of one document, without any join.
  ///
  /// A join can hide a row whose item or batch is physically gone; a plain select
  /// cannot. This is the honest inventory the ship and receive paths check the joined
  /// read against, so a corrupt reference is reported instead of silently reducing the
  /// document by one line (§26).
  Future<List<GoodsReturnLineRow>> linesOf(String goodsReturnId) =>
      (select(goodsReturnLines)..where(
            (t) => t.goodsReturnId.equals(goodsReturnId) & t.deletedAt.isNull(),
          ))
          .get();

  /// The ids of every live line of one document — one column, no join (§26).
  Future<List<String>> lineIdsOf(String goodsReturnId) =>
      _lineColumn(goodsReturnId, goodsReturnLines.id);

  /// The **Good Receipt line** ids this document claims to return.
  ///
  /// The list compared against [rejectedGoodReceiptLineIdsOf] to prove the snapshot is
  /// still exactly the receipt's rejections — no line added, none missing (§26).
  Future<List<String>> lineGrLineIdsOf(String goodsReturnId) =>
      _lineColumn(goodsReturnId, goodsReturnLines.grLineId);

  /// The distinct item ids of one document.
  Future<List<String>> lineItemIdsOf(String goodsReturnId) =>
      _lineColumn(goodsReturnId, goodsReturnLines.itemId, distinct: true);

  /// The distinct **non-null** batch ids of one document.
  ///
  /// A line for an item without expiry contributes none, so this list can be shorter
  /// than [lineIdsOf]'s — which is why the integrity check compares it against the
  /// batched lines only rather than against every line.
  Future<List<String>> lineBatchIdsOf(String goodsReturnId) async {
    final query = selectOnly(goodsReturnLines, distinct: true)
      ..addColumns([goodsReturnLines.batchId])
      ..where(
        goodsReturnLines.goodsReturnId.equals(goodsReturnId) &
            goodsReturnLines.deletedAt.isNull() &
            goodsReturnLines.batchId.isNotNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.read(goodsReturnLines.batchId))
        .whereType<String>()
        .toList(growable: false);
  }

  Future<List<String>> _lineColumn(
    String goodsReturnId,
    GeneratedColumn<String> column, {
    bool distinct = false,
  }) async {
    final query = selectOnly(goodsReturnLines, distinct: distinct)
      ..addColumns([column])
      ..where(
        goodsReturnLines.goodsReturnId.equals(goodsReturnId) &
            goodsReturnLines.deletedAt.isNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.read(column))
        .whereType<String>()
        .toList(growable: false);
  }

  // --- the source: rejected Good Receipt lines -------------------------------

  /// The ids of every live `rejected` line of one Good Receipt — one column, no join.
  ///
  /// The authority the snapshot is verified against (§26). Deliberately *not* derived
  /// from the joined read below: a line whose item row was physically removed would
  /// vanish from an inner join and the document would silently shrink by one position,
  /// which is exactly the failure §26 exists to catch.
  Future<List<String>> rejectedGoodReceiptLineIdsOf(String grId) async {
    final query = selectOnly(goodReceiptLines)
      ..addColumns([goodReceiptLines.id])
      ..where(_rejectedLinePredicate(grId));
    final rows = await query.get();
    return rows
        .map((row) => row.read(goodReceiptLines.id))
        .whereType<String>()
        .toList(growable: false);
  }

  /// Those same lines as plain rows, without any join.
  Future<List<GoodReceiptLineRow>> rejectedGoodReceiptLinesOf(String grId) =>
      (select(goodReceiptLines)..where(
            (t) =>
                t.grId.equals(grId) &
                t.deletedAt.isNull() &
                t.lineStatus.equalsValue(GoodReceiptLineStatus.rejected),
          ))
          .get();

  /// Those same lines joined with item and batch, for the preview the *Perlu Dibuat*
  /// queue and the create flow show.
  ///
  /// Read *in addition to* [rejectedGoodReceiptLineIdsOf] rather than instead of it:
  /// the ids are the authority and this is the presentation, and the create use case
  /// refuses when the two disagree (§17).
  Future<List<RejectedGoodReceiptLineRow>> rejectedGoodReceiptLineDetails(
    String grId,
  ) async {
    final rows =
        await (select(goodReceiptLines)..where(
              (t) =>
                  t.grId.equals(grId) &
                  t.deletedAt.isNull() &
                  t.lineStatus.equalsValue(GoodReceiptLineStatus.rejected),
            ))
            .join([
              // No `is_active` and no `deleted_at` filter on the master joins: a
              // receipt whose item was withdrawn afterwards must stay returnable, and
              // the repository labels it instead of hiding it (§37).
              innerJoin(items, items.id.equalsExp(goodReceiptLines.itemId)),
              // Left join: `batch_id` is nullable, and an inner join would make every
              // line for an item without expiry vanish — exactly the silent data loss
              // §26 is about.
              leftOuterJoin(
                itemBatches,
                itemBatches.id.equalsExp(goodReceiptLines.batchId),
              ),
            ])
            .get();
    return rows
        .map(
          (row) => RejectedGoodReceiptLineRow(
            line: row.readTable(goodReceiptLines),
            item: row.readTable(items),
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Expression<bool> _rejectedLinePredicate(String grId) =>
      goodReceiptLines.grId.equals(grId) &
      goodReceiptLines.deletedAt.isNull() &
      goodReceiptLines.lineStatus.equalsValue(GoodReceiptLineStatus.rejected);

  // --- eligible Good Receipts (§16) ------------------------------------------

  Expression<int> get _rejectedCount => goodReceiptLines.id.count(
    distinct: true,
    filter: goodReceiptLines.deletedAt.isNull(),
  );

  Expression<int> get _rejectedQty => goodReceiptLines.shippedQty.sum(
    filter: goodReceiptLines.deletedAt.isNull(),
  );

  /// Posted Good Receipts of one branch that carry at least one rejected line.
  ///
  /// Three predicates live in the SQL, and each is a rule:
  ///
  /// * `good_receipts.status = 'posted'` — a receipt still being checked is a branch
  ///   head part way through a decision, and returning goods they have not finished
  ///   refusing would raise a document for a rejection that may yet be revised (§16);
  /// * `purchase_requests.branch_id = ?` — the security boundary, and it stays in SQL
  ///   for that reason. A Good Receipt has no branch column of its own; its branch is
  ///   the request's;
  /// * the line join is filtered to `rejected`, so the counts describe the returnable
  ///   positions rather than the whole receipt.
  ///
  /// A receipt that already has a return is **not** filtered out here — see
  /// [RejectedGoodReceiptRow.existingReturn]. The caller decides which of the two
  /// questions it is asking, and the *Perlu Dibuat* queue drops the ones with a
  /// document while the discrepancy page keeps them to show a status (§33).
  ///
  /// There is deliberately **no `posted_at` window**: timestamps are ISO-8601 TEXT, so
  /// a SQL `>=` compares characters rather than instants. The repository applies date
  /// windows in Dart on UTC `DateTime`s. The branch predicate stays here because it is
  /// a *security* boundary and must never be a Dart filter; a display date range is
  /// not (§16).
  JoinedSelectStatement<HasResultSet, dynamic> _eligibleQuery({
    required String branchId,
    String? searchQuery,
  }) {
    var predicate =
        goodReceipts.deletedAt.isNull() &
        goodReceipts.status.equalsValue(GoodReceiptStatus.posted) &
        purchaseRequests.branchId.equals(branchId);

    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      final pattern = '%$needle%';
      predicate =
          predicate &
          (goodReceipts.docNumber.lower().like(pattern) |
              deliveryOrders.docNumber.lower().like(pattern) |
              purchaseRequests.docNumber.lower().like(pattern) |
              _receiptRejectsMatchingItem(pattern));
    }

    final query = (select(goodReceipts)..where((t) => t.deletedAt.isNull())).join([
      innerJoin(deliveryOrders, deliveryOrders.id.equalsExp(goodReceipts.doId)),
      innerJoin(
        purchaseRequests,
        purchaseRequests.id.equalsExp(deliveryOrders.prId),
      ),
      innerJoin(branches, branches.id.equalsExp(purchaseRequests.branchId)),
      // Inner join *filtered to rejected*: a receipt with no rejection produces no
      // row at all, which is the eligibility rule expressed as a join rather than
      // as a HAVING nobody can see.
      innerJoin(
        goodReceiptLines,
        goodReceiptLines.grId.equalsExp(goodReceipts.id) &
            goodReceiptLines.deletedAt.isNull() &
            goodReceiptLines.lineStatus.equalsValue(
              GoodReceiptLineStatus.rejected,
            ),
      ),
      // Left join: the receipts that still owe a return are exactly the rows where
      // this comes back null.
      leftOuterJoin(
        goodsReturns,
        goodsReturns.grId.equalsExp(goodReceipts.id) &
            goodsReturns.deletedAt.isNull(),
      ),
    ]);

    return query
      ..addColumns([_rejectedCount, _rejectedQty])
      ..where(predicate)
      ..groupBy([goodReceipts.id])
      // Oldest posting first: a branch works the backlog from the top (§16). Ordering
      // `posted_at` as TEXT is a *stable* order rather than a chronological claim —
      // the repository re-sorts by parsed UTC instant, which is what §16 asks for.
      ..orderBy([
        OrderingTerm.asc(goodReceipts.postedAt),
        OrderingTerm.asc(branches.code),
        OrderingTerm.asc(goodReceipts.docNumber),
      ]);
  }

  /// Whether a receipt carries a *rejected* line whose item name, SKU or batch number
  /// matches [pattern].
  ///
  /// A subquery rather than a join, because [_eligibleQuery] already joins
  /// `good_receipt_lines` to count them: adding `items` to that join would make the
  /// `WHERE` filter away the very rows the counts are derived from, and a receipt found
  /// by its number would then report only its matching rejections.
  Expression<bool> _receiptRejectsMatchingItem(String pattern) {
    final matchingItems = selectOnly(items)
      ..addColumns([items.id])
      ..where(
        items.name.lower().like(pattern) | items.sku.lower().like(pattern),
      );
    final matchingBatches = selectOnly(itemBatches)
      ..addColumns([itemBatches.id])
      ..where(itemBatches.batchNo.lower().like(pattern));

    final matching = selectOnly(goodReceiptLines)
      ..addColumns([goodReceiptLines.grId])
      ..where(
        goodReceiptLines.deletedAt.isNull() &
            goodReceiptLines.lineStatus.equalsValue(
              GoodReceiptLineStatus.rejected,
            ) &
            (goodReceiptLines.itemId.isInQuery(matchingItems) |
                goodReceiptLines.batchId.isInQuery(matchingBatches)),
      );

    return goodReceipts.id.isInQuery(matching);
  }

  List<RejectedGoodReceiptRow> _mapEligible(List<TypedResult> rows) {
    return rows
        .map(
          (row) => RejectedGoodReceiptRow(
            receipt: row.readTable(goodReceipts),
            order: row.readTable(deliveryOrders),
            request: row.readTable(purchaseRequests),
            branch: row.readTable(branches),
            existingReturn: row.readTableOrNull(goodsReturns),
            rejectedLineCount: row.read(_rejectedCount) ?? 0,
            rejectedQtyMilliUnits: row.read(_rejectedQty) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<RejectedGoodReceiptRow>> rejectedGoodReceipts({
    required String branchId,
    String? searchQuery,
  }) async => _mapEligible(
    await _eligibleQuery(branchId: branchId, searchQuery: searchQuery).get(),
  );

  Stream<List<RejectedGoodReceiptRow>> watchRejectedGoodReceipts({
    required String branchId,
    String? searchQuery,
  }) => _eligibleQuery(
    branchId: branchId,
    searchQuery: searchQuery,
  ).watch().map(_mapEligible);

  /// `grId → the return raised for it`, for a set of Good Receipts (§33).
  ///
  /// The one **cross-branch** read on this class, and it is deliberately narrow: it
  /// returns the header row and nothing joined to it, so the Warehouse discrepancy page
  /// can label each rejected line *Belum dibuat / Draft / Dikirim / Diterima* without
  /// being handed a branch's document. A Warehouse user already sees every branch's
  /// discrepancies on that screen (§4.2); what they must not get from it is the *content*
  /// of a draft, and a status plus a number is not that.
  ///
  /// Unlike every list query here it carries no [GoodsReturnQueryScope], because the
  /// question is not "which returns may I read" but "does this receipt have one" — and
  /// the screen asking it is already scoped to the receipts it is allowed to see.
  Future<Map<String, GoodsReturnRow>> returnsByGoodReceipt(
    Iterable<String> grIds,
  ) async {
    final ids = grIds.toList(growable: false);
    if (ids.isEmpty) return const {};
    final rows = await (select(
      goodsReturns,
    )..where((t) => t.grId.isIn(ids) & t.deletedAt.isNull())).get();
    return {for (final row in rows) row.grId: row};
  }

  /// The batch expiry dates each document carries — `returnId → [expiry…]` (§35).
  ///
  /// Dates rather than a count, and that is the point: *"expired"* is a question about
  /// today, and answering it in SQL would mean comparing `expiry_date` against a
  /// serialised "now". The caller decides in Dart against the clock the rest of the
  /// screen is using (T-7), which is also what keeps the dashboard counter and the red
  /// badges on the detail from disagreeing.
  ///
  /// Lines for items without expiry contribute nothing, so a document of only such
  /// items maps to an empty list rather than being absent.
  Future<Map<String, List<DateTime>>> batchExpiriesFor(
    Iterable<String> goodsReturnIds,
  ) async {
    final ids = goodsReturnIds.toList(growable: false);
    if (ids.isEmpty) return const {};

    final rows =
        await (selectOnly(goodsReturnLines).join([
                innerJoin(
                  itemBatches,
                  itemBatches.id.equalsExp(goodsReturnLines.batchId),
                ),
              ])
              ..addColumns([
                goodsReturnLines.goodsReturnId,
                itemBatches.expiryDate,
              ])
              ..where(
                goodsReturnLines.goodsReturnId.isIn(ids) &
                    goodsReturnLines.deletedAt.isNull(),
              ))
            .get();

    final result = <String, List<DateTime>>{for (final id in ids) id: []};
    for (final row in rows) {
      final id = row.read(goodsReturnLines.goodsReturnId);
      final expiry = row.read(itemBatches.expiryDate);
      if (id == null || expiry == null) continue;
      (result[id] ??= <DateTime>[]).add(expiry);
    }
    return result;
  }

  /// How many **posted** Good Receipts across every branch still carry rejections with
  /// no return document at all (§35).
  ///
  /// A bare count, cross-branch, for the Warehouse dashboard. It returns a number and
  /// nothing else — no branch, no receipt number, no item — because *"how much do the
  /// branches still owe us"* is the whole question, and a Warehouse user reads the
  /// detail of any given one through the discrepancy queue they already have.
  Future<int> outstandingRejectedGoodReceiptCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM good_receipts gr '
      "WHERE gr.deleted_at IS NULL AND gr.status = 'posted' "
      '  AND EXISTS ('
      '    SELECT 1 FROM good_receipt_lines grl '
      '    WHERE grl.gr_id = gr.id AND grl.deleted_at IS NULL '
      "      AND grl.line_status = 'rejected'"
      '  ) '
      '  AND NOT EXISTS ('
      '    SELECT 1 FROM goods_returns ret '
      '    WHERE ret.gr_id = gr.id AND ret.deleted_at IS NULL'
      '  );',
      readsFrom: {goodReceipts, goodReceiptLines, goodsReturns},
    ).getSingle();
    return row.read<int>('c');
  }

  Stream<int> watchOutstandingRejectedGoodReceiptCount() => customSelect(
    'SELECT COUNT(*) AS c FROM good_receipts gr '
    "WHERE gr.deleted_at IS NULL AND gr.status = 'posted' "
    '  AND EXISTS ('
    '    SELECT 1 FROM good_receipt_lines grl '
    '    WHERE grl.gr_id = gr.id AND grl.deleted_at IS NULL '
    "      AND grl.line_status = 'rejected'"
    '  ) '
    '  AND NOT EXISTS ('
    '    SELECT 1 FROM goods_returns ret '
    '    WHERE ret.gr_id = gr.id AND ret.deleted_at IS NULL'
    '  );',
    readsFrom: {goodReceipts, goodReceiptLines, goodsReturns},
  ).watchSingle().map((row) => row.read<int>('c'));

  // --- access ----------------------------------------------------------------

  /// The facts that decide whether somebody may open this return.
  ///
  /// Seven columns and no join at all — the scope predicate needs nothing but
  /// `branch_id` and `status`, both of which live on this table. When [scope] is
  /// supplied it is in the statement, so a document outside it never leaves SQLite and
  /// the caller cannot leak what it never received. [statuses] narrows the same way.
  ///
  /// Returns `null` both for "no such return" and for "not yours", and that ambiguity
  /// is the point: telling them apart would turn the address bar into a way to
  /// enumerate documents across the whole clinic group (§27).
  Future<GoodsReturnAccessRow?> accessScope({
    required String goodsReturnId,
    GoodsReturnQueryScope? scope,
    String? branchId,
    Set<GoodsReturnStatus> statuses = const {},
  }) async {
    final query = selectOnly(goodsReturns)
      ..addColumns([
        goodsReturns.id,
        goodsReturns.grId,
        goodsReturns.branchId,
        goodsReturns.createdBy,
        goodsReturns.shippedBy,
        goodsReturns.receivedBy,
        goodsReturns.status,
      ])
      ..where(
        goodsReturns.id.equals(goodsReturnId) &
            goodsReturns.deletedAt.isNull() &
            _scopePredicate(scope: scope, branchId: branchId) &
            _statusPredicate(statuses),
      );

    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return GoodsReturnAccessRow(
      goodsReturnId: row.read(goodsReturns.id)!,
      grId: row.read(goodsReturns.grId)!,
      branchId: row.read(goodsReturns.branchId)!,
      createdBy: row.read(goodsReturns.createdBy)!,
      shippedBy: row.read(goodsReturns.shippedBy),
      receivedBy: row.read(goodsReturns.receivedBy),
      status: row.readWithConverter(goodsReturns.status)!,
    );
  }

  // --- scope ----------------------------------------------------------------

  /// The document scope, expressed as a predicate on `goods_returns` itself.
  ///
  /// No subquery is needed: both facts the scope turns on — which branch owns the
  /// document and what status it is in — are columns on this table. Written this way
  /// the rule travels into the statement, so a document outside the scope is never
  /// read at all.
  ///
  /// [GoodsReturnQueryScope.warehouseInTransitOrReceived] ANDs
  /// `status IN ('shipped', 'received')` into the predicate *in addition to* whatever
  /// [_statusPredicate] the caller asked for. A Warehouse user sees goods that are on
  /// their way or already counted in, never a branch's unfinished draft (§15), and
  /// expressing that here rather than relying on every call site to pass the right
  /// status set is what makes it a property of the query instead of a convention.
  Expression<bool> _scopePredicate({
    required GoodsReturnQueryScope? scope,
    required String? branchId,
  }) {
    if (scope == null) return const Constant(true);

    switch (scope) {
      case GoodsReturnQueryScope.branch:
        // A branch scope with no branch matches nothing rather than everything: a
        // provider that lost its session must see no documents, not all of them.
        if (branchId == null) return const Constant(false);
        return goodsReturns.branchId.equals(branchId);
      case GoodsReturnQueryScope.warehouseInTransitOrReceived:
        // Deliberately **not** narrowed by branch: the Warehouse works one queue
        // across every branch (§15). A `branchId` passed alongside this scope is a
        // display filter and is applied by [_scope], where it can only ever restrict.
        return goodsReturns.status.isIn([
          GoodsReturnStatus.shipped.dbValue,
          GoodsReturnStatus.received.dbValue,
        ]);
    }
  }

  Expression<bool> _statusPredicate(Set<GoodsReturnStatus> statuses) =>
      statuses.isEmpty
      ? const Constant(true)
      : goodsReturns.status.isIn(
          statuses.map((status) => status.dbValue).toList(growable: false),
        );

  // --- joined line reads ----------------------------------------------------

  JoinedSelectStatement<HasResultSet, dynamic> _detailLinesQuery(
    String goodsReturnId,
  ) {
    return (select(goodsReturnLines)..where(
          (t) => t.goodsReturnId.equals(goodsReturnId) & t.deletedAt.isNull(),
        ))
        .join([
          // No `is_active` and no `deleted_at` filter on the master joins: a received
          // return whose item or batch was withdrawn afterwards must stay readable,
          // and the repository labels it instead of hiding it (§37).
          innerJoin(items, items.id.equalsExp(goodsReturnLines.itemId)),
          // Left join: `batch_id` is nullable here, and an inner join would make every
          // line for an item without expiry vanish — exactly the silent data loss §26
          // is about.
          leftOuterJoin(
            itemBatches,
            itemBatches.id.equalsExp(goodsReturnLines.batchId),
          ),
        ])
      // Item first, then nearest expiry: both sides read the document by product, and
      // within one product the batch closest to expiry is the one the reject reason is
      // most likely about (G-E5).
      ..orderBy([
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(itemBatches.batchNo),
        OrderingTerm.asc(goodsReturnLines.id),
      ]);
  }

  List<GoodsReturnLineWithDetails> _mapLines(List<TypedResult> rows) {
    return rows
        .map(
          (row) => GoodsReturnLineWithDetails(
            line: row.readTable(goodsReturnLines),
            item: row.readTable(items),
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Future<List<GoodsReturnLineWithDetails>> detailLines(
    String goodsReturnId,
  ) async => _mapLines(await _detailLinesQuery(goodsReturnId).get());

  Stream<List<GoodsReturnLineWithDetails>> watchDetailLines(
    String goodsReturnId,
  ) => _detailLinesQuery(goodsReturnId).watch().map(_mapLines);

  // --- summaries ------------------------------------------------------------

  /// Three aliases of `users`, so one query can join the creator, the shipper and the
  /// receiver.
  ///
  /// Without them all three foreign keys would resolve to the same table instance and
  /// each join condition would overwrite the last — a document would then report one
  /// person as all three actors, which is precisely the audit fact G-A3 and G-R4 exist
  /// to keep straight. On this document the three are *required* to differ, which is
  /// exactly why a bug here would be worth catching.
  late final $UsersTable _creators = alias(users, 'created_by_user');
  late final $UsersTable _shippers = alias(users, 'shipped_by_user');
  late final $UsersTable _receivers = alias(users, 'received_by_user');

  Expression<int> get _lineCount => goodsReturnLines.id.count(
    distinct: true,
    filter: goodsReturnLines.deletedAt.isNull(),
  );

  Expression<int> get _itemCount => goodsReturnLines.itemId.count(
    distinct: true,
    filter: goodsReturnLines.deletedAt.isNull(),
  );

  Expression<int> get _batchCount => goodsReturnLines.batchId.count(
    distinct: true,
    filter: goodsReturnLines.deletedAt.isNull(),
  );

  Expression<int> get _totalQty =>
      goodsReturnLines.qty.sum(filter: goodsReturnLines.deletedAt.isNull());

  JoinedSelectStatement<HasResultSet, dynamic> _summaryQuery(
    Expression<bool> predicate,
  ) {
    final query = (select(goodsReturns)..where((t) => t.deletedAt.isNull())).join([
      // Inner joins on the whole document chain: every one is a NOT NULL foreign
      // key, and none of the joins filters `is_active` or `deleted_at`, so a
      // retired branch or a deactivated actor still produces a row (§37).
      innerJoin(goodReceipts, goodReceipts.id.equalsExp(goodsReturns.grId)),
      innerJoin(deliveryOrders, deliveryOrders.id.equalsExp(goodReceipts.doId)),
      innerJoin(
        purchaseRequests,
        purchaseRequests.id.equalsExp(deliveryOrders.prId),
      ),
      innerJoin(branches, branches.id.equalsExp(goodsReturns.branchId)),
      innerJoin(_creators, _creators.id.equalsExp(goodsReturns.createdBy)),
      leftOuterJoin(_shippers, _shippers.id.equalsExp(goodsReturns.shippedBy)),
      leftOuterJoin(
        _receivers,
        _receivers.id.equalsExp(goodsReturns.receivedBy),
      ),
      // Left join so a document whose lines somehow went missing still produces a
      // row — the integrity check must be able to *see* it in order to refuse it.
      leftOuterJoin(
        goodsReturnLines,
        goodsReturnLines.goodsReturnId.equalsExp(goodsReturns.id) &
            goodsReturnLines.deletedAt.isNull(),
      ),
    ]);

    return query
      ..addColumns([_lineCount, _itemCount, _batchCount, _totalQty])
      ..where(predicate)
      ..groupBy([goodsReturns.id])
      // Newest first, and *stable* rather than chronological: `created_at` is TEXT.
      // The repository re-sorts by parsed UTC instant wherever order is the point
      // (§16/§39).
      ..orderBy([OrderingTerm.desc(goodsReturns.createdAt)]);
  }

  List<GoodsReturnWithContext> _mapSummaries(List<TypedResult> rows) {
    return rows
        .map(
          (row) => GoodsReturnWithContext(
            goodsReturn: row.readTable(goodsReturns),
            receipt: row.readTable(goodReceipts),
            order: row.readTable(deliveryOrders),
            request: row.readTable(purchaseRequests),
            branch: row.readTable(branches),
            createdBy: row.readTable(_creators),
            shippedBy: row.readTableOrNull(_shippers),
            receivedBy: row.readTableOrNull(_receivers),
            lineCount: row.read(_lineCount) ?? 0,
            itemCount: row.read(_itemCount) ?? 0,
            batchCount: row.read(_batchCount) ?? 0,
            totalQtyMilliUnits: row.read(_totalQty) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  /// The document predicate, optionally pinned to one scope and one status set.
  ///
  /// Both checks happen **inside the statement**, so a return outside them is never
  /// read, never mapped and never reaches a stream a widget could be listening to.
  /// Filtering the result in Dart would look equivalent and would not be.
  Expression<bool> _document(
    String goodsReturnId,
    GoodsReturnQueryScope? scope,
    String? branchId,
    Set<GoodsReturnStatus> statuses,
  ) =>
      goodsReturns.id.equals(goodsReturnId) &
      _scopePredicate(scope: scope, branchId: branchId) &
      _statusPredicate(statuses);

  Future<GoodsReturnWithContext?> summaryById(
    String goodsReturnId, {
    GoodsReturnQueryScope? scope,
    String? branchId,
    Set<GoodsReturnStatus> statuses = const {},
  }) async {
    final rows = await _summaryQuery(
      _document(goodsReturnId, scope, branchId, statuses),
    ).get();
    return rows.isEmpty ? null : _mapSummaries(rows).single;
  }

  Stream<GoodsReturnWithContext?> watchSummaryById(
    String goodsReturnId, {
    GoodsReturnQueryScope? scope,
    String? branchId,
    Set<GoodsReturnStatus> statuses = const {},
  }) {
    return _summaryQuery(
      _document(goodsReturnId, scope, branchId, statuses),
    ).watch().map((rows) => rows.isEmpty ? null : _mapSummaries(rows).single);
  }

  Expression<bool> _scope({
    GoodsReturnQueryScope? scope,
    String? branchId,
    String? filterBranchId,
    Set<GoodsReturnStatus> statuses = const {},
    String? searchQuery,
  }) {
    var predicate =
        _scopePredicate(scope: scope, branchId: branchId) &
        _statusPredicate(statuses);

    if (filterBranchId != null) {
      // The Warehouse queue's *branch* chip. Narrowing **within** an already-scoped
      // read: both predicates are ANDed, so it can only ever restrict what the scope
      // already allowed — a branch chip can never widen a Warehouse user into a
      // branch's drafts (§31).
      predicate = predicate & goodsReturns.branchId.equals(filterBranchId);
    }

    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      // Return number, the whole document chain, the branch, or a returned item —
      // case-insensitive and entirely local, so the clinic keeps searching offline
      // (G-Y1).
      final pattern = '%$needle%';
      predicate =
          predicate &
          (goodsReturns.docNumber.lower().like(pattern) |
              goodReceipts.docNumber.lower().like(pattern) |
              deliveryOrders.docNumber.lower().like(pattern) |
              purchaseRequests.docNumber.lower().like(pattern) |
              branches.name.lower().like(pattern) |
              branches.code.lower().like(pattern) |
              _returnsMatchingItem(pattern));
    }
    return predicate;
  }

  /// Whether a document carries a line whose item name, SKU or batch number matches
  /// [pattern].
  ///
  /// A subquery rather than a join, for the reason [_receiptRejectsMatchingItem]
  /// spells out: [_summaryQuery] already left-joins `goods_return_lines` to count
  /// them, and adding `items` to that join would make the `WHERE` filter away the very
  /// rows the counts are derived from.
  Expression<bool> _returnsMatchingItem(String pattern) {
    final matchingItems = selectOnly(items)
      ..addColumns([items.id])
      ..where(
        items.name.lower().like(pattern) | items.sku.lower().like(pattern),
      );
    final matchingBatches = selectOnly(itemBatches)
      ..addColumns([itemBatches.id])
      ..where(itemBatches.batchNo.lower().like(pattern));

    final matching = selectOnly(goodsReturnLines)
      ..addColumns([goodsReturnLines.goodsReturnId])
      ..where(
        goodsReturnLines.deletedAt.isNull() &
            (goodsReturnLines.itemId.isInQuery(matchingItems) |
                goodsReturnLines.batchId.isInQuery(matchingBatches)),
      );

    return goodsReturns.id.isInQuery(matching);
  }

  Future<List<GoodsReturnWithContext>> listReturns({
    GoodsReturnQueryScope? scope,
    String? branchId,
    String? filterBranchId,
    Set<GoodsReturnStatus> statuses = const {},
    String? searchQuery,
  }) async {
    final rows = await _summaryQuery(
      _scope(
        scope: scope,
        branchId: branchId,
        filterBranchId: filterBranchId,
        statuses: statuses,
        searchQuery: searchQuery,
      ),
    ).get();
    return _mapSummaries(rows);
  }

  Stream<List<GoodsReturnWithContext>> watchReturns({
    GoodsReturnQueryScope? scope,
    String? branchId,
    String? filterBranchId,
    Set<GoodsReturnStatus> statuses = const {},
    String? searchQuery,
  }) {
    return _summaryQuery(
      _scope(
        scope: scope,
        branchId: branchId,
        filterBranchId: filterBranchId,
        statuses: statuses,
        searchQuery: searchQuery,
      ),
    ).watch().map(_mapSummaries);
  }

  /// Per-unit totals for a set of documents, as `returnId → unit → milli-units`.
  ///
  /// One grouped query for a whole list rather than one per row, and it exists because a
  /// *single* total is the wrong number to show: §29 and §31 both ask for totals per
  /// unit, and adding boxes to ampoules produces a figure that means nothing.
  /// [GoodsReturnWithContext.totalQtyMilliUnits] stays as the cheap cross-check the
  /// per-unit breakdown must add back up to.
  ///
  /// The join on `items` is unfiltered, like every other master join in this class: a
  /// received return whose item was withdrawn afterwards still contributes its unit
  /// (§37).
  Future<Map<String, Map<String, int>>> totalsByUnitFor(
    Iterable<String> goodsReturnIds,
  ) async {
    final ids = goodsReturnIds.toList(growable: false);
    if (ids.isEmpty) return const {};

    final total = goodsReturnLines.qty.sum();
    final query =
        selectOnly(goodsReturnLines).join([
            innerJoin(items, items.id.equalsExp(goodsReturnLines.itemId)),
          ])
          ..addColumns([goodsReturnLines.goodsReturnId, items.unit, total])
          ..where(
            goodsReturnLines.goodsReturnId.isIn(ids) &
                goodsReturnLines.deletedAt.isNull(),
          )
          ..groupBy([goodsReturnLines.goodsReturnId, items.unit]);

    final rows = await query.get();
    final result = <String, Map<String, int>>{};
    for (final row in rows) {
      final id = row.read(goodsReturnLines.goodsReturnId);
      final unit = row.read(items.unit);
      final sum = row.read(total);
      if (id == null || unit == null || sum == null) continue;
      (result[id] ??= <String, int>{})[unit] = sum;
    }
    return result;
  }

  // --- destination ----------------------------------------------------------

  /// Every `warehouse` stock location, soft-deleted rows included.
  ///
  /// Returned as a *list* rather than as "the" warehouse, because the caller has to be
  /// able to tell "there is none" from "there are two": a return credits exactly one
  /// location and may not guess which (§21). [activeOnly] separates the two questions —
  /// receiving goods is new ledger work and needs a live location, whereas reading a
  /// received document must still resolve one that has since been tidied away.
  ///
  /// No seed id is hard-coded anywhere on this path: the location is looked up by type
  /// every time, which is what makes *"the destination is always the Warehouse Pusat"*
  /// a fact about the data rather than a constant somebody could pass around.
  Future<List<StockLocation>> warehouseLocations({bool activeOnly = true}) {
    final query = select(stockLocations)
      ..where(
        (t) =>
            t.type.equals(StockLocationType.warehouse.dbValue) &
            (activeOnly ? t.deletedAt.isNull() : const Constant(true)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return query.get();
  }

  // --- ledger ---------------------------------------------------------------

  /// The `return` movements one document wrote, oldest row first.
  ///
  /// Read back by the detail screen and by the tests that prove one movement per line
  /// and no duplicate on a second receive (§45). Filtered on **both** halves of the
  /// reference — `ref_doc_type = 'RET'` and `ref_doc_id` — because `ref_doc_id` alone
  /// is a bare UUID that another document type could in principle carry.
  Future<List<StockMovement>> movementsOf(String goodsReturnId) =>
      (select(stockMovements)
            ..where(
              (t) =>
                  t.refDocType.equals(RefDocType.goodsReturn) &
                  t.refDocId.equals(goodsReturnId) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
}
