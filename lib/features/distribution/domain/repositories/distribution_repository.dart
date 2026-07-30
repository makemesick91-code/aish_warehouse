import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/distribution_models.dart';

/// Distribusi persistence, expressed in domain terms.
///
/// The shape of this contract encodes the guardrails:
///
/// * There is no `update(Distribution)` and no `delete`. The only writes are the
///   specific, guarded operations below, so an arbitrary mutation of a posted
///   document is not expressible (G-S2).
/// * There is no writer that reaches `room_id` or `item_id` on an existing line. A
///   position for another room or another item is a *different* position, and moving
///   one is remove-then-add — both validated. Changing it in place would slip past
///   the room/branch check that G-T1 depends on.
/// * There is no un-post, no reopen and no cancel. `posted` has no outgoing
///   transition at all.
/// * There is no source or destination **location** anywhere in this contract. Both
///   are resolved from the branch and the room by type (§14), so no caller — screen
///   included — can nominate one. The only location id that appears is the branch
///   store the *reads* are scoped to, and the caller resolves that through
///   `MasterDataRepository`.
/// * There is no balance writer. Stock changes only through `StockPostingService`.
/// * Reads come in scoped pairs. `…ForBranch` carries the branch predicate inside
///   the query, so a document that is not this branch's is never fetched rather than
///   being fetched and then withheld. The single unscoped read, [getDetail], is for
///   use cases only and the architecture test enforces that.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers stay behind
/// the implementation (Q-4).
abstract interface class DistributionRepository {
  /// Runs [action] in a single database transaction.
  ///
  /// The posting owns exactly one of these. Every write it performs — movements, the
  /// source and destination balances, the document status and its timestamp — happens
  /// inside it, so a failure on the last room rolls the first one back (G-T4).
  Future<T> runInTransaction<T>(Future<T> Function() action);

  // --- header ---------------------------------------------------------------

  /// Creates an empty `draft`.
  ///
  /// An empty document is a legitimate starting point: the branch head opens the form
  /// and then chooses rooms and items. Nothing about an empty draft can post — the
  /// guarded UPDATE requires at least one live line — so there is no state here that
  /// needs defending against.
  Future<Distribution> createDraft({
    required String docNumber,
    required String branchId,
    required String distributedBy,
    String? note,
    DateTime? createdAtUtc,
  });

  Future<Distribution?> getById(String distributionId);

  /// Unscoped detail read, for **use cases only**.
  ///
  /// A use case loads the document and then applies its guards, producing a precise
  /// failure that names it — the right answer for somebody attempting a write.
  /// Presentation code must not use this: by the time a widget could apply that
  /// check, the foreign document has already been handed to the UI layer. Screens use
  /// [getForBranch] / [watchForBranch] instead, and the architecture test enforces
  /// the split.
  Future<DistributionDetail?> getDetail(String distributionId);

  /// The document, but only if it belongs to [branchId]. The predicate is part of the
  /// query.
  Future<DistributionDetail?> getForBranch({
    required String distributionId,
    required String branchId,
  });

  /// Live version of [getForBranch]. A stream opened for one branch can never emit
  /// another branch's document, whatever happens underneath it.
  Stream<DistributionDetail?> watchForBranch({
    required String distributionId,
    required String branchId,
  });

  /// Read authorization, answered without reading the document.
  ///
  /// Returns `null` when [distributionId] does not name a live document within the
  /// scope asked for — one answer for "no such document", for "another branch's" and,
  /// on the editor, for "already posted", so a caller cannot probe which ids exist
  /// elsewhere.
  Future<DistributionAccessScope?> findAccessScope({
    required String distributionId,
    String? branchId,
    Set<DistributionStatus> statuses = const {},
  });

  /// The branch's own distributions, newest first. Always restricted to [branchId].
  Future<List<DistributionSummary>> listForBranch({
    required String branchId,
    Set<DistributionStatus> statuses = const {},
    String searchQuery = '',
  });

  Stream<List<DistributionSummary>> watchListForBranch({
    required String branchId,
    Set<DistributionStatus> statuses = const {},
    String searchQuery = '',
  });

  /// `draft → posted`, with the timestamp the caller validated.
  ///
  /// Returns `false` when the guarded update matched no rows — the document was posted
  /// by somebody else between the read and the write, or its last line was removed —
  /// which the caller turns into a concurrency failure and a full rollback.
  Future<bool> markPosted({
    required String distributionId,
    required DateTime postedAtUtc,
  });

  /// Updates the header note of a draft. `false` when the guard fired.
  Future<bool> updateDraftNote({required String distributionId, String? note});

  // --- lines ----------------------------------------------------------------

  /// Live lines of one document, read **without joining** rooms, items or batches.
  ///
  /// The joined read can hide a row whose room, item or batch is physically gone;
  /// this cannot. It is the honest inventory the posting path checks the joined read
  /// against, so a corrupt reference is reported rather than silently reducing the
  /// document by one line (§22).
  Future<List<DistributionLineReference>> lineReferences(String distributionId);

  /// One line by id, again without any join.
  ///
  /// Returns the identifiers and quantity only — including the `distribution_id` the
  /// caller then uses to load and authorise the document. A read that returned the
  /// joined line would hand a screen the item name of a document it has not been
  /// cleared for.
  Future<DistributionLineReference?> lineReferenceById(String lineId);

  /// The plain id sets the integrity checks compare against the joined read (§22).
  ///
  /// Four separate reads rather than one joined query, and that is the point: a join
  /// is exactly what can make a broken reference disappear instead of reporting it.
  Future<List<String>> lineIds(String distributionId);

  Future<List<String>> lineRoomIds(String distributionId);

  Future<List<String>> lineItemIds(String distributionId);

  Future<List<String>> lineBatchIds(String distributionId);

  /// Stores a whole allocation for one position, in one statement.
  ///
  /// A batch insert rather than a loop, because a FEFO allocation spanning three
  /// batches is one decision: either all three rows land or none does, and a
  /// partially stored allocation would silently distribute less than was asked for.
  ///
  /// Throws [DuplicateDistributionLineFailure] when a partial unique index refuses —
  /// which is what makes two devices adding the same position produce exactly one
  /// line.
  Future<void> addAllocations({
    required String distributionId,
    required List<DistributionAllocation> allocations,
  });

  /// Changes the quantity, the batch and the FEFO reason of one draft line.
  ///
  /// `false` when the guarded update matched no rows: the document is no longer a
  /// draft, the line is not on it, or the quantity was not positive.
  Future<bool> updateDraftLine({
    required String distributionId,
    required String lineId,
    required Quantity qty,
    String? batchId,
    String? fefoOverrideReason,
  });

  /// Soft-deletes one draft line (G-A5). `false` when the guard fired.
  Future<bool> removeDraftLine({
    required String distributionId,
    required String lineId,
  });

  // --- branch-store stock ---------------------------------------------------

  /// The items the branch store can actually distribute (§15).
  ///
  /// Only items with a **usable** balance appear: expired batches are excluded from
  /// the total (G-E4), and an item whose only stock has expired is therefore absent
  /// rather than offered and then refused. [nowUtc] decides that, and it is passed in
  /// rather than read from a clock so the picker, the badges and the use case's
  /// refusal are all judged against the same instant (T-7).
  ///
  /// [limit] caps the number of **items**, applied after the per-item totals are
  /// summed — capping rows would cut a multi-batch item off mid-way and misreport its
  /// total.
  Future<List<DistributionStockItem>> searchBranchStock({
    required String branchStoreLocationId,
    required DateTime nowUtc,
    String searchQuery = '',
    String? categoryId,
    int limit = 8,
  });

  Stream<List<DistributionStockItem>> watchBranchStock({
    required String branchStoreLocationId,
    required DateTime nowUtc,
    String searchQuery = '',
    String? categoryId,
    int limit = 8,
  });

  /// One item's branch-store position, with its usable and expired batches.
  ///
  /// `null` when the store holds nothing distributable for it. Used by the add and
  /// update paths, which need the candidate list a form was working from — re-read,
  /// never trusted.
  ///
  /// [activeItemsOnly] is `false` for the update path: an item deactivated after it
  /// was added to a draft may still have its quantity corrected, while a *new* line
  /// may not name it (G-A4).
  Future<DistributionStockItem?> branchStockFor({
    required String branchStoreLocationId,
    required String itemId,
    required DateTime nowUtc,
    bool activeItemsOnly = true,
  });

  // --- rooms ----------------------------------------------------------------

  /// The active rooms of one branch, ordered by code — the chips the form draws.
  ///
  /// Dynamic rather than a hard-coded `R1 / R2 / R3`: spec §2.1 makes rooms master
  /// data managed by the Super Admin, and a branch with four rooms must show four
  /// chips.
  Future<List<MasterRoom>> branchRooms(String branchId);

  Stream<List<MasterRoom>> watchBranchRooms(String branchId);

  /// One room by id, **soft-deleted rows included** — for reading a posted document
  /// whose room was archived afterwards (§32).
  Future<MasterRoom?> historicalRoomById(String roomId);
}
