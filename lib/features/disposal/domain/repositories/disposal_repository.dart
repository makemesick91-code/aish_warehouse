import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/disposal_models.dart';

/// Pemusnahan persistence, expressed in domain terms (§25).
///
/// The shape of this contract encodes the guardrails:
///
/// * There is no `update(Disposal)` and no `delete`. The only writes are the
///   specific, guarded operations below, so an arbitrary mutation of a posted
///   document is not expressible (G-S2).
/// * There is no writer that reaches `source_location_id`, `item_id` or `batch_id`.
///   The source is fixed when the document is created; a different batch is a
///   *different* position, and changing one is remove-then-add — both validated.
///   Changing either in place would slip past the expiry and balance checks the add
///   path performs.
/// * There is no un-post, no reopen and no cancel. `posted` has no outgoing
///   transition at all.
/// * There is no **destination** anywhere in this contract, and no method that
///   could take one. A disposal removes stock from one location and puts it
///   nowhere (§20).
/// * There is no balance writer. Stock changes only through `StockPostingService`.
/// * There is no reader that returns non-expired stock. [searchExpiredCandidates]
///   is the only candidate query, and its eligibility rule is
///   `DisposalExpiryPolicy`'s — so a screen cannot ask for "everything at this
///   location" and filter afterwards.
/// * Reads come in scoped pairs. `…ForWarehouse` and `…ForBranch` carry their
///   predicate inside the query, so a document outside the scope is never fetched
///   rather than being fetched and then withheld. The single unscoped read,
///   [getDetail], is for use cases only and the architecture test enforces that.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers stay behind
/// the implementation (Q-4).
abstract interface class DisposalRepository {
  /// Runs [action] in a single database transaction.
  ///
  /// The posting owns exactly one of these. Every write it performs — movements,
  /// the source balances, the document status, its timestamp and its posting
  /// actor — happens inside it, so a failure on the last position rolls the first
  /// one back (§21).
  Future<T> runInTransaction<T>(Future<T> Function() action);

  // --- header ---------------------------------------------------------------

  /// Creates an empty `draft` against one already-authorised source location.
  ///
  /// An empty document is a legitimate starting point: the actor opens the form and
  /// then picks expired positions. Nothing about an empty draft can post — the
  /// guarded UPDATE requires at least one live line **and** a non-blank reason — so
  /// there is no state here that needs defending against.
  Future<Disposal> createDraft({
    required String docNumber,
    required String sourceLocationId,
    required String createdBy,
    String? reason,
    DateTime? createdAtUtc,
  });

  Future<Disposal?> getById(String disposalId);

  /// Unscoped detail read, for **use cases only**.
  ///
  /// A use case loads the document and then applies its guards, producing a precise
  /// failure that names it — the right answer for somebody attempting a write.
  /// Presentation code must not use this: by the time a widget could apply that
  /// check, the foreign document has already been handed to the UI layer. Screens
  /// use the scoped reads instead, and the architecture test enforces the split.
  Future<DisposalDetail?> getDetail(String disposalId);

  /// The document, but only if its source is a central-warehouse location.
  Future<DisposalDetail?> getForWarehouse(String disposalId);

  /// The document, but only if its source belongs to [branchId].
  Future<DisposalDetail?> getForBranch({
    required String disposalId,
    required String branchId,
  });

  /// Live version of [getForWarehouse].
  Stream<DisposalDetail?> watchForWarehouse(String disposalId);

  /// Live version of [getForBranch]. A stream opened for one branch can never emit
  /// another branch's document, whatever happens underneath it.
  Stream<DisposalDetail?> watchForBranch({
    required String disposalId,
    required String branchId,
  });

  /// Read authorization, answered without reading the document.
  ///
  /// Returns `null` when [disposalId] does not name a live document within the scope
  /// asked for — one answer for "no such document", for "the other side's", for
  /// "another branch's" and, on the editor, for "already posted", so a caller cannot
  /// probe which ids exist elsewhere.
  Future<DisposalAccessScope?> findAccessScope({
    required String disposalId,
    DisposalLocationScope? scope,
    String? branchId,
    Set<DisposalStatus> statuses = const {},
  });

  /// The warehouse's own disposals, newest first.
  Future<List<DisposalSummary>> listForWarehouse({
    Set<DisposalStatus> statuses = const {},
    String searchQuery = '',
  });

  Stream<List<DisposalSummary>> watchListForWarehouse({
    Set<DisposalStatus> statuses = const {},
    String searchQuery = '',
  });

  /// One branch's disposals, newest first. Always restricted to [branchId].
  ///
  /// [sourceLocationId] narrows *within* that scope — the branch head's location
  /// selector. It can only ever restrict what the branch predicate already allowed,
  /// because the two are ANDed in the query.
  Future<List<DisposalSummary>> listForBranch({
    required String branchId,
    String? sourceLocationId,
    Set<DisposalStatus> statuses = const {},
    String searchQuery = '',
  });

  Stream<List<DisposalSummary>> watchListForBranch({
    required String branchId,
    String? sourceLocationId,
    Set<DisposalStatus> statuses = const {},
    String searchQuery = '',
  });

  /// `draft → posted`, with the timestamp and the actor the caller validated.
  ///
  /// Returns `false` when the guarded update matched no rows — the document was
  /// posted by somebody else between the read and the write, its last line was
  /// removed, or its reason was cleared — which the caller turns into a concurrency
  /// failure and a full rollback.
  Future<bool> markPosted({
    required String disposalId,
    required DateTime postedAtUtc,
    required String postedBy,
  });

  /// Updates the reason of a draft. `false` when the guard fired.
  Future<bool> updateDraftReason({
    required String disposalId,
    required String? reason,
  });

  // --- lines ----------------------------------------------------------------

  /// Live lines of one document, read **without joining** items or batches.
  ///
  /// The joined read can hide a row whose item or batch is physically gone; this
  /// cannot. It is the honest inventory the posting path checks the joined read
  /// against, so a corrupt reference is reported rather than silently reducing the
  /// document by one line (§23).
  Future<List<DisposalLineReference>> lineReferences(String disposalId);

  /// One line by id, again without any join.
  ///
  /// Returns the identifiers and quantity only — including the `disposal_id` the
  /// caller then uses to load and authorise the document. A read that returned the
  /// joined line would hand a screen the item name of a document it has not been
  /// cleared for.
  Future<DisposalLineReference?> lineReferenceById(String lineId);

  /// The plain id sets the integrity checks compare against the joined read (§23).
  ///
  /// Three separate reads rather than one joined query, and that is the point: a
  /// join is exactly what can make a broken reference disappear instead of
  /// reporting it.
  Future<List<String>> lineIds(String disposalId);

  Future<List<String>> lineItemIds(String disposalId);

  Future<List<String>> lineBatchIds(String disposalId);

  /// Stores one expired position.
  ///
  /// Throws `DuplicateDisposalLineFailure` when the partial unique index refuses —
  /// which is what makes two devices adding the same position produce exactly one
  /// line.
  Future<DisposalLineReference> addLine({
    required String disposalId,
    required String itemId,
    required String batchId,
    required Quantity qty,
    String? note,
  });

  /// Changes the quantity and note of one draft line.
  ///
  /// `false` when the guarded update matched no rows: the document is no longer a
  /// draft, the line is not on it, or the quantity was not positive.
  Future<bool> updateDraftLine({
    required String disposalId,
    required String lineId,
    required Quantity qty,
    String? note,
  });

  /// Soft-deletes one draft line (G-A5). `false` when the guard fired.
  Future<bool> removeDraftLine({
    required String disposalId,
    required String lineId,
  });

  // --- expired stock --------------------------------------------------------

  /// The expired positions one location currently holds (§17).
  ///
  /// Every row is already past its expiry date: [nowUtc] decides that, and it is
  /// passed in rather than read from a clock so the picker, the badges and the use
  /// case's refusal are all judged against the same instant (T-7). A batch that is
  /// merely near expiry is **absent**, not greyed out — this method has no way to
  /// return one, which is what stops a screen offering it by mistake.
  ///
  /// Items and batches that have since been deactivated or archived are **kept**:
  /// the stock is physically on the shelf and refusing to list it would leave stock
  /// nobody can ever remove.
  ///
  /// [limit] caps the number of rows the picker shows.
  Future<List<ExpiredStockPosition>> searchExpiredCandidates({
    required String sourceLocationId,
    required DateTime nowUtc,
    String searchQuery = '',
    String? categoryId,
    int limit = 8,
  });

  /// Every expired position at one location, uncapped — what the *Stok Kedaluwarsa*
  /// tab lists and what the dashboard counts (G-E6).
  Future<List<ExpiredStockPosition>> expiredPositions({
    required String sourceLocationId,
    required DateTime nowUtc,
    String? categoryId,
  });

  Stream<List<ExpiredStockPosition>> watchExpiredPositions({
    required String sourceLocationId,
    required DateTime nowUtc,
    String? categoryId,
  });

  /// One exact position, re-read. `null` when the location holds nothing for it, or
  /// when what it holds is not expired.
  ///
  /// Used by the add and update paths, which need the candidate a form was working
  /// from — re-read, never trusted.
  Future<ExpiredStockPosition?> expiredPositionFor({
    required String sourceLocationId,
    required String itemId,
    required String batchId,
    required DateTime nowUtc,
  });

  // --- locations ------------------------------------------------------------

  /// The central-warehouse locations a disposal may be raised against.
  Future<List<MasterLocation>> warehouseSourceLocations();

  /// The branch store and rooms of one branch — the selector the branch head sees
  /// (§29).
  ///
  /// Dynamic rather than a hard-coded `Gudang Cabang / R1 / R2 / R3`: spec §2.1
  /// makes rooms master data managed by the Super Admin, and a branch with four
  /// rooms must show five choices.
  Future<List<MasterLocation>> branchSourceLocations(String branchId);

  Stream<List<MasterLocation>> watchBranchSourceLocations(String branchId);

  /// One location by id, **soft-deleted rows included** — for reading a posted
  /// document whose source was archived afterwards (§34).
  Future<MasterLocation?> historicalLocationById(String locationId);
}
