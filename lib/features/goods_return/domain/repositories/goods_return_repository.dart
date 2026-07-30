import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/goods_return_models.dart';

/// One line the create transaction is about to write.
///
/// Deliberately not a `GoodsReturnLine`: the caller has verified the source position
/// and is handing over exactly the four snapshot facts plus the receipt line it came
/// from. There is no id, no status and no note, because the table has no such columns
/// and the repository must not be able to invent them (§18).
class GoodsReturnLineDraft {
  const GoodsReturnLineDraft({
    required this.grLineId,
    required this.itemId,
    this.batchId,
    required this.qty,
    required this.rejectReason,
  });

  final String grLineId;
  final String itemId;
  final String? batchId;
  final Quantity qty;
  final String rejectReason;
}

/// Retur Barang persistence, expressed in domain terms (§25).
///
/// The shape of this contract encodes the guardrails:
///
/// * There is no `update(GoodsReturn)` and no `delete`. The only writes are the four
///   specific, guarded operations below, so an arbitrary mutation of a shipped or
///   received document is not expressible (G-S2).
/// * **There is no line writer at all after [createFromGoodReceipt].** No add, no
///   remove, no quantity setter, no reason setter. This is the strictest contract in
///   the application, and §18 is why: a return says *"here is exactly what you sent
///   that we refused"*, and a line somebody could edit afterwards would be a different
///   claim. The snapshot is written once, in one transaction, and read forever after.
/// * There is no writer that reaches `gr_id`, `branch_id` or `created_by`. All three
///   are established by the create and are the columns every later guard predicates on.
/// * There is no un-ship, no un-receive, no reopen and no cancel. `received` has no
///   outgoing transition at all.
/// * There is no **destination** parameter on any write. The Warehouse Pusat location
///   is resolved by type — [activeWarehouseLocations] — by the caller, so no screen can
///   nominate one (§21/§24).
/// * There is no balance writer. Stock changes only through `StockPostingService`.
/// * Reads come in scoped pairs. `…ForBranch` and `…ForWarehouse` carry their
///   predicate inside the query, so a document outside the scope is never fetched
///   rather than being fetched and then withheld. The single unscoped read,
///   [getDetail], is for use cases only and the architecture test enforces that.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers stay behind
/// the implementation (Q-4).
abstract interface class GoodsReturnRepository {
  /// Runs [action] in a single database transaction.
  ///
  /// The receive owns exactly one of these. Every write it performs — movements, the
  /// Warehouse balances, the document status, its timestamp, its receiving actor and
  /// the Warehouse note — happens inside it, so a failure on the last position rolls
  /// the first one back (§21).
  ///
  /// The create owns one too, for a smaller but equally load-bearing reason: a header
  /// without its lines is a document that claims to return nothing.
  Future<T> runInTransaction<T>(Future<T> Function() action);

  // --- eligibility (§16) -----------------------------------------------------

  /// The posted Good Receipts of one branch that carry rejections.
  ///
  /// Rows whose receipt already has a return are **included**, carrying
  /// `existingReturn…`, because §33 needs them: the discrepancy page shows a status per
  /// receipt rather than an empty space. The *Perlu Dibuat* queue filters on
  /// [GoodsReturnEligibility.canCreateReturn], which is a question about the row rather
  /// than a second query.
  ///
  /// Ordered oldest-posting first, by **parsed UTC instant** rather than by the TEXT
  /// column — the ordering §16 asks for cannot be `ORDER BY posted_at` (§39).
  Future<List<GoodsReturnEligibility>> eligibleGoodReceiptsForBranch({
    required String branchId,
    String searchQuery = '',
  });

  Stream<List<GoodsReturnEligibility>> watchEligibleGoodReceiptsForBranch({
    required String branchId,
    String searchQuery = '',
  });

  /// One Good Receipt's rejected positions, in full — what the create use case
  /// snapshots and what every later integrity check compares against (§17/§26).
  ///
  /// Read through the joined query, so the caller must also ask
  /// [rejectedGoodReceiptLineIds] and compare: a join can hide a position whose item is
  /// physically gone, and a document silently one line short is exactly what §26
  /// exists to catch.
  Future<List<RejectedGoodReceiptPosition>> rejectedPositionsOf(String grId);

  /// The same positions' ids, read as **one column with no join at all**.
  ///
  /// The authority. Everything else about a rejected line can be re-derived; whether
  /// the line *exists* cannot be, and a joined read is exactly what can get that wrong.
  Future<List<String>> rejectedGoodReceiptLineIds(String grId);

  /// The Good Receipt itself, unscoped — for use cases, which then apply their guards.
  Future<GoodReceiptStatus?> goodReceiptStatusOf(String grId);

  /// The branch a Good Receipt belongs to, resolved through
  /// `delivery_orders → purchase_requests`. `null` when the receipt does not exist.
  ///
  /// A separate read rather than a field on the receipt, because `good_receipts` has no
  /// branch column — that is precisely why `goods_returns` stores one (§10).
  Future<String?> goodReceiptBranchOf(String grId);

  /// The return already raised for one Good Receipt, or `null`. The *one Good Receipt,
  /// one Retur* question (§17/§33).
  Future<GoodsReturn?> findByGoodReceipt(String grId);

  /// The same question asked of many receipts at once — `grId → its return` (§33).
  ///
  /// What the Warehouse's Good Receipt discrepancy page labels each rejected line with.
  /// Deliberately returns the header only: a status and a number are what that screen
  /// needs, and handing it a branch's document *content* would be a different grant.
  Future<Map<String, GoodsReturn>> returnsByGoodReceipt(Iterable<String> grIds);

  /// The batch expiry dates each document carries — `returnId → [expiry…]` (§35).
  ///
  /// Dates rather than a count: *"expired"* is a question about today, and the caller
  /// answers it against the clock the rest of the screen is using (T-7).
  Future<Map<String, List<DateTime>>> batchExpiriesFor(
    Iterable<String> goodsReturnIds,
  );

  /// How many posted Good Receipts across every branch still carry rejections with no
  /// return at all — the Warehouse dashboard's *"selisih yang belum diretur"* (§35).
  Stream<int> watchOutstandingRejectedGoodReceiptCount();

  // --- header ----------------------------------------------------------------

  /// Writes the header and its whole snapshot as **one** unit of work (§17).
  ///
  /// Takes the lines rather than returning an empty draft for the caller to fill,
  /// and that is the contract: there is no such thing as an empty return, and no
  /// method here that could produce one. The caller has already verified every
  /// position; this writes them.
  ///
  /// Throws when the unique index on `gr_id` refuses — which is what makes two devices
  /// raising a return for the same receipt produce exactly one document (§17).
  Future<GoodsReturn> createFromGoodReceipt({
    required String docNumber,
    required String grId,
    required String branchId,
    required String createdBy,
    required List<GoodsReturnLineDraft> lines,
    String? note,
    DateTime? createdAtUtc,
  });

  Future<GoodsReturn?> getById(String goodsReturnId);

  /// Unscoped detail read, for **use cases only**.
  ///
  /// A use case loads the document and then applies its guards, producing a precise
  /// failure that names it — the right answer for somebody attempting a write.
  /// Presentation code must not use this: by the time a widget could apply that check,
  /// the foreign document has already been handed to the UI layer. Screens use the
  /// scoped reads instead, and the architecture test enforces the split.
  Future<GoodsReturnDetail?> getDetail(String goodsReturnId);

  /// The document, but only if it belongs to [branchId].
  Future<GoodsReturnDetail?> getForBranch({
    required String goodsReturnId,
    required String branchId,
  });

  /// The document, but only if it is `shipped` or `received`.
  ///
  /// Deliberately **not** branch-scoped: a Petugas Warehouse works one queue across
  /// every branch (§15). The status half is in the scope predicate rather than in a
  /// parameter, so a caller cannot ask for a draft (§24).
  Future<GoodsReturnDetail?> getForWarehouse(String goodsReturnId);

  Stream<GoodsReturnDetail?> watchForBranch({
    required String goodsReturnId,
    required String branchId,
  });

  Stream<GoodsReturnDetail?> watchForWarehouse(String goodsReturnId);

  /// Read authorization, answered without reading the document.
  ///
  /// Returns `null` when [goodsReturnId] does not name a live document within the
  /// scope asked for — one answer for "no such return", for "another branch's", for "a
  /// draft, seen from the Warehouse queue" and, on the note editor, for "already
  /// shipped", so a caller cannot probe which ids exist elsewhere (§27).
  Future<GoodsReturnAccessScope?> findAccessScope({
    required String goodsReturnId,
    GoodsReturnQueryScope? scope,
    String? branchId,
    Set<GoodsReturnStatus> statuses = const {},
  });

  /// One branch's returns, newest first, in every status.
  Future<List<GoodsReturnSummary>> listForBranch({
    required String branchId,
    Set<GoodsReturnStatus> statuses = const {},
    String searchQuery = '',
  });

  Stream<List<GoodsReturnSummary>> watchBranchList({
    required String branchId,
    Set<GoodsReturnStatus> statuses = const {},
    String searchQuery = '',
  });

  /// Every branch's `shipped` and `received` returns — the Warehouse queue and history.
  ///
  /// [filterBranchId] is the queue's branch **chip**, not a scope: it narrows within a
  /// read that is already pinned to the two Warehouse-visible statuses, and can never
  /// widen it (§31).
  ///
  /// There is deliberately **no date-range parameter**, for the reason §29 spells out:
  /// `created_at` and `shipped_at` are ISO-8601 TEXT, so a SQL range would compare
  /// characters. The range lives in [GoodsReturnFilter] and is applied in Dart on UTC
  /// instants.
  Future<List<GoodsReturnSummary>> listForWarehouse({
    Set<GoodsReturnStatus> statuses = const {},
    String? filterBranchId,
    String searchQuery = '',
  });

  Stream<List<GoodsReturnSummary>> watchWarehouseList({
    Set<GoodsReturnStatus> statuses = const {},
    String? filterBranchId,
    String searchQuery = '',
  });

  // --- transitions -----------------------------------------------------------

  /// Updates the note of a draft belonging to [branchId]. `false` when the guard fired
  /// (§19).
  Future<bool> updateDraftNote({
    required String goodsReturnId,
    required String branchId,
    required String? note,
  });

  /// `draft → shipped`, with the timestamp and the actor the caller validated (§20).
  ///
  /// Returns `false` when the guarded update matched no rows — the document was shipped
  /// by another device between the read and the write, or it is not this branch's —
  /// which the caller turns into a concurrency failure.
  ///
  /// Posts **nothing**. There is no `posting` parameter on this method and no way to
  /// add one: the goods left the branch, and they were never in the branch's balance to
  /// leave it (§20).
  Future<bool> markShipped({
    required String goodsReturnId,
    required String branchId,
    required DateTime shippedAtUtc,
    required String shippedBy,
  });

  /// `shipped → received`, with the Warehouse's optional note, in one statement (§21).
  ///
  /// [receivedBy] travels into the SQL predicate as well as into the write: the
  /// statement refuses to match a row whose `created_by` or `shipped_by` is this user,
  /// which is G-R4 enforced at the moment of the write rather than at the moment of the
  /// check.
  ///
  /// `false` when the guard fired, which the caller turns into a rollback of the whole
  /// transaction — the ledger movements included.
  Future<bool> markReceived({
    required String goodsReturnId,
    required DateTime receivedAtUtc,
    required String receivedBy,
    String? warehouseNote,
  });

  // --- lines (read-only) ------------------------------------------------------

  /// Live lines of one document, read **without joining** items or batches (§26).
  ///
  /// The joined read can hide a row whose item or batch is physically gone; this
  /// cannot. It is the honest inventory every integrity check works from.
  Future<List<GoodsReturnLineReference>> lineReferences(String goodsReturnId);

  /// The plain id sets the integrity checks compare against each other (§26).
  ///
  /// Four separate single-column reads rather than one joined query, and that is the
  /// point: a join is exactly what can make a broken reference disappear instead of
  /// reporting it.
  Future<List<String>> lineIds(String goodsReturnId);

  /// The **Good Receipt line** ids the document claims to return — compared against
  /// [rejectedGoodReceiptLineIds] to prove the snapshot is still exactly the receipt's
  /// rejections.
  Future<List<String>> lineGrLineIds(String goodsReturnId);

  Future<List<String>> lineItemIds(String goodsReturnId);

  /// The **non-null** batch ids. Shorter than [lineIds] on any document that also
  /// carries items without expiry, which is the normal case.
  Future<List<String>> lineBatchIds(String goodsReturnId);

  // --- destination ------------------------------------------------------------

  /// The `warehouse` stock locations.
  ///
  /// A *list* rather than "the" Warehouse, because the caller has to be able to tell
  /// "there is none" from "there are two": a return credits exactly one location and
  /// may not guess which (§21). [activeOnly] separates the two questions — receiving is
  /// new ledger work and needs a live location, whereas reading a received document
  /// must still resolve one that has since been tidied away.
  Future<List<MasterLocation>> activeWarehouseLocations({
    bool activeOnly = true,
  });
}
