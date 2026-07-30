import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/consumption_models.dart';

/// Pemakaian persistence, expressed in domain terms (§24).
///
/// The shape of this contract encodes the guardrails:
///
/// * There is no `update(Consumption)` and no `delete`. The only writes are the
///   specific, guarded operations below, so an arbitrary mutation of a posted document
///   is not expressible (G-S2).
/// * Every write takes an **`actorUserId`** and carries it into the SQL predicate. That
///   is the ownership rule of §14 made structural: there is no way to express *"update
///   this draft"* without saying who is doing it, so a use case cannot forget to check.
/// * There is no writer that reaches `branch_id`, `room_id`, `item_id` or `batch_id`.
///   The room is fixed when the document is created; a different batch is a *different*
///   position, and changing one is remove-then-add — both validated. Changing either in
///   place would slip past the expiry and balance checks the add path performs.
/// * There is no un-post, no reopen and no cancel. `posted` has no outgoing transition
///   at all.
/// * There is no **destination** anywhere in this contract, and no method that could
///   take one. A consumption removes stock from a room and puts it nowhere (§19).
/// * There is no **location** parameter on any write. The room's stock location is
///   resolved by type from `room_id` by the caller, so a screen cannot nominate a
///   warehouse or a branch store as the source.
/// * There is no balance writer. Stock changes only through `StockPostingService`.
/// * There is no reader that returns expired stock. [searchRoomCandidates] and
///   [roomPositions] both apply `ConsumptionExpiryPolicy`, so a screen cannot ask for
///   "everything in this room" and filter afterwards — and cannot accidentally offer a
///   batch that leaves only through a Pemusnahan (G-E7).
/// * Reads come in scoped pairs. `…Own` and `…ForBranch` carry their predicate inside
///   the query, so a document outside the scope is never fetched rather than being
///   fetched and then withheld. The single unscoped read, [getDetail], is for use cases
///   only and the architecture test enforces that.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers stay behind the
/// implementation (Q-4).
abstract interface class ConsumptionRepository {
  /// Runs [action] in a single database transaction.
  ///
  /// The posting owns exactly one of these. Every write it performs — movements, the
  /// room balances, the document status, its timestamp and its posting actor — happens
  /// inside it, so a failure on the last position rolls the first one back (§20).
  Future<T> runInTransaction<T>(Future<T> Function() action);

  // --- header ---------------------------------------------------------------

  /// Creates an empty `draft` against one already-authorised room.
  ///
  /// An empty document is a legitimate starting point: the nurse opens the form and then
  /// picks positions. Nothing about an empty draft can post — the guarded UPDATE
  /// requires at least one live line — so there is no state here that needs defending
  /// against.
  Future<Consumption> createDraft({
    required String docNumber,
    required String branchId,
    required String roomId,
    required String createdBy,
    String? note,
    DateTime? createdAtUtc,
  });

  Future<Consumption?> getById(String consumptionId);

  /// Unscoped detail read, for **use cases only**.
  ///
  /// A use case loads the document and then applies its guards, producing a precise
  /// failure that names it — the right answer for somebody attempting a write.
  /// Presentation code must not use this: by the time a widget could apply that check,
  /// the foreign document has already been handed to the UI layer. Screens use the
  /// scoped reads instead, and the architecture test enforces the split.
  Future<ConsumptionDetail?> getDetail(String consumptionId);

  /// The document, but only if [actorUserId] created it.
  Future<ConsumptionDetail?> getOwn({
    required String consumptionId,
    required String actorUserId,
  });

  /// The document, but only if it is `posted` **and** belongs to [branchId].
  ///
  /// Both halves are in the SQL, and the `posted` half is in the scope predicate rather
  /// than in a status parameter: a branch head reads history, never work in progress
  /// (§14).
  Future<ConsumptionDetail?> getPostedForBranch({
    required String consumptionId,
    required String branchId,
  });

  /// Live version of [getOwn].
  Stream<ConsumptionDetail?> watchOwn({
    required String consumptionId,
    required String actorUserId,
  });

  /// Live version of [getPostedForBranch]. A stream opened for one branch can never
  /// emit another branch's document — or any draft — whatever happens underneath it.
  Stream<ConsumptionDetail?> watchPostedForBranch({
    required String consumptionId,
    required String branchId,
  });

  /// Read authorization, answered without reading the document.
  ///
  /// Returns `null` when [consumptionId] does not name a live document within the scope
  /// asked for — one answer for "no such document", for "another nurse's", for "another
  /// branch's", for "a draft seen from the branch history" and, on the editor, for
  /// "already posted", so a caller cannot probe which ids exist elsewhere.
  Future<ConsumptionAccessScope?> findAccessScope({
    required String consumptionId,
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    Set<ConsumptionStatus> statuses = const {},
  });

  /// One nurse's own consumptions, newest first — drafts and posted history.
  Future<List<ConsumptionSummary>> listOwn({
    required String actorUserId,
    String? roomId,
    Set<ConsumptionStatus> statuses = const {},
    String searchQuery = '',
  });

  Stream<List<ConsumptionSummary>> watchOwnList({
    required String actorUserId,
    String? roomId,
    Set<ConsumptionStatus> statuses = const {},
    String searchQuery = '',
  });

  /// One branch's **posted** consumptions, newest first. Always restricted to
  /// [branchId] and to `posted`.
  ///
  /// [roomId] and [createdBy] narrow *within* that scope — the branch head's room and
  /// Perawat filters. Either can only ever restrict what the branch predicate already
  /// allowed, because they are ANDed in the query.
  ///
  /// There is deliberately **no date-range parameter**. §31 is explicit about why:
  /// `posted_at` is ISO-8601 TEXT, so a SQL range would compare characters — the trap
  /// schema v4 removed from `stock_opnames`. The range lives in `ConsumptionFilter` and
  /// is applied in Dart, on UTC instants.
  Future<List<ConsumptionSummary>> listPostedForBranch({
    required String branchId,
    String? roomId,
    String? createdBy,
    String searchQuery = '',
  });

  Stream<List<ConsumptionSummary>> watchBranchPostedList({
    required String branchId,
    String? roomId,
    String? createdBy,
    String searchQuery = '',
  });

  /// `draft → posted`, with the timestamp and the actor the caller validated.
  ///
  /// Returns `false` when the guarded update matched no rows — the document was posted
  /// by somebody else between the read and the write, its last line was removed, or the
  /// acting user is not its creator — which the caller turns into a concurrency failure
  /// and a full rollback.
  Future<bool> markPosted({
    required String consumptionId,
    required String actorUserId,
    required DateTime postedAtUtc,
    required String postedBy,
  });

  /// Updates the note of a draft the actor created. `false` when the guard fired.
  Future<bool> updateOwnDraftNote({
    required String consumptionId,
    required String actorUserId,
    required String? note,
  });

  // --- lines ----------------------------------------------------------------

  /// Live lines of one document, read **without joining** items or batches.
  ///
  /// The joined read can hide a row whose item or batch is physically gone; this cannot.
  /// It is the honest inventory the posting path checks the joined read against, so a
  /// corrupt reference is reported rather than silently reducing the document by one
  /// line (§22).
  Future<List<ConsumptionLineReference>> lineReferences(String consumptionId);

  /// One line by id, again without any join.
  ///
  /// Returns the identifiers and quantity only — including the `consumption_id` the
  /// caller then uses to load and authorise the document. A read that returned the
  /// joined line would hand a screen the item name of a document it has not been cleared
  /// for.
  Future<ConsumptionLineReference?> lineReferenceById(String lineId);

  /// The plain id sets the integrity checks compare against the joined read (§22).
  ///
  /// Three separate reads rather than one joined query, and that is the point: a join is
  /// exactly what can make a broken reference disappear instead of reporting it.
  Future<List<String>> lineIds(String consumptionId);

  Future<List<String>> lineItemIds(String consumptionId);

  /// The **non-null** batch ids. Shorter than [lineIds] on any document that also
  /// carries items without expiry, which is the normal case.
  Future<List<String>> lineBatchIds(String consumptionId);

  /// Stores one consumed position on a draft the actor created.
  ///
  /// Throws `DuplicateConsumptionLineFailure` when a partial unique index refuses —
  /// which is what makes two devices adding the same position produce exactly one line.
  Future<ConsumptionLineReference> addDraftLine({
    required String consumptionId,
    required String actorUserId,
    required String itemId,
    String? batchId,
    required Quantity qty,
    String? note,
  });

  /// Changes the quantity and note of one draft line.
  ///
  /// `false` when the guarded update matched no rows: the document is no longer a draft,
  /// the line is not on it, the actor is not its creator, or the quantity was not
  /// positive.
  Future<bool> updateDraftLine({
    required String consumptionId,
    required String actorUserId,
    required String lineId,
    required Quantity qty,
    String? note,
  });

  /// Soft-deletes one draft line (G-A5). `false` when the guard fired.
  Future<bool> removeDraftLine({
    required String consumptionId,
    required String actorUserId,
    required String lineId,
  });

  // --- room stock -----------------------------------------------------------

  /// The consumable positions one room currently holds (§16).
  ///
  /// Every row is usable: [nowUtc] decides that through `ConsumptionExpiryPolicy`, and
  /// it is passed in rather than read from a clock so the picker, the badges and the use
  /// case's refusal are all judged against the same instant (T-7). An expired batch is
  /// **absent**, not greyed out — this method has no way to return one, which is what
  /// stops a screen offering it by mistake (G-E7).
  ///
  /// A near-expiry batch *is* returned, with the flags a badge needs: it is exactly the
  /// stock that should be used next (§17).
  ///
  /// [activeItemsOnly] is the §16 distinction: a **new** line needs a live, active item,
  /// whereas an existing draft's own positions must stay readable even after an
  /// administrator withdraws the product — the stock is physically on the shelf either
  /// way.
  ///
  /// [limit] caps the number of positions the dropdown shows.
  Future<List<RoomStockPosition>> searchRoomCandidates({
    required String roomId,
    required String roomLocationId,
    required DateTime nowUtc,
    String searchQuery = '',
    String? categoryId,
    bool activeItemsOnly = true,
    int limit = 8,
  });

  /// Every consumable position in one room, uncapped — what the dashboard counts and
  /// what a form's per-line availability is read from.
  Future<List<RoomStockPosition>> roomPositions({
    required String roomId,
    required String roomLocationId,
    required DateTime nowUtc,
    String? categoryId,
    bool activeItemsOnly = false,
  });

  Stream<List<RoomStockPosition>> watchRoomPositions({
    required String roomId,
    required String roomLocationId,
    required DateTime nowUtc,
    String? categoryId,
    bool activeItemsOnly = false,
  });

  /// One exact position, re-read. `null` when the room holds nothing for it, or when
  /// what it holds may not be consumed.
  ///
  /// Used by the add and update paths, which need the candidate a form was working from
  /// — re-read, never trusted.
  Future<RoomStockPosition?> roomPositionFor({
    required String roomId,
    required String roomLocationId,
    required String itemId,
    String? batchId,
    required DateTime nowUtc,
  });

  // --- rooms ----------------------------------------------------------------

  /// The active rooms of one branch — the selector a nurse sees (§27).
  ///
  /// Dynamic rather than a hard-coded `R1 / R2 / R3`: spec §2.1 makes rooms master data
  /// managed by the Super Admin, and a branch with four rooms must show four choices.
  Future<List<ConsumptionRoom>> activeRoomsOfBranch(String branchId);

  Stream<List<ConsumptionRoom>> watchActiveRoomsOfBranch(String branchId);

  /// One room by id, **deactivated and soft-deleted rows included** — for reading a
  /// posted document whose room was retired afterwards (§33).
  Future<ConsumptionRoom?> historicalRoomById(String roomId);

  /// The `room` stock locations of one room.
  ///
  /// A *list* rather than "the" location, because the caller has to be able to tell
  /// "there is none" from "there are two": a consumption reduces exactly one location
  /// per document and may not guess which (§15). [activeOnly] is the §15 distinction —
  /// new work needs a live location, whereas reading a posted document must still
  /// resolve one that has since been tidied away.
  Future<List<MasterLocation>> roomLocations(
    String roomId, {
    bool activeOnly = true,
  });
}
