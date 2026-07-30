import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/purchase_request_models.dart';
import '../services/suggested_purchase_request_calculator.dart';

/// Purchase Request persistence, expressed in domain terms.
///
/// The shape of this contract encodes the guardrails:
///
/// * There is no `update(PurchaseRequest)` and no `delete`. The only writes are
///   the specific, guarded operations below, so an arbitrary mutation of a
///   submitted or later document is not expressible (G-P5, G-S2).
/// * There is no writer for `suggested_qty` that a branch head's editor could
///   reach: [updateDraftLine] takes only the requested quantity and the note. The
///   snapshot moves through [replaceOpnameLinksAndSuggestions], which is the one
///   operation that is allowed to recompute it.
/// * Status changes go through [submit], [cancel], [markProcessing] and [reject],
///   each of which states the transition it expects and reports `false` when the
///   document has moved on. There is no `shipped` or `closed` writer at all —
///   those belong to Delivery Order and Good Receipt.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers stay
/// behind the implementation (Q-4).
abstract interface class PurchaseRequestRepository {
  /// Runs [action] in a single database transaction. Creating a draft and
  /// replacing its citations both use this, so a document is never observable
  /// half-built.
  Future<T> runInTransaction<T>(Future<T> Function() action);

  /// Inserts a header together with its citations and its suggested lines.
  /// Atomic: a request without the opnames it rests on can never be observed.
  ///
  /// Throws [PurchaseRequestAlreadyActiveFailure] if the branch's active-order
  /// index rejects the insert — which cannot happen for a `draft`, and is here
  /// because the same method shape is used by [submit].
  Future<PurchaseRequest> createDraft({
    required String docNumber,
    required String branchId,
    required String requestedBy,
    DateTime? neededDate,
    String? note,
    required List<String> opnameIds,
    required List<PurchaseRequestLineDraft> lines,
  });

  Future<PurchaseRequest?> getById(String prId);

  /// Unscoped detail read, for **use cases only**.
  ///
  /// A use case loads the document and then applies its branch guard, producing a
  /// precise failure that names the document — the right answer for somebody
  /// attempting a write. Presentation code must not use this: by the time a widget
  /// could apply that check, the foreign document has already been fetched and
  /// handed to the UI layer. Screens use [getDetailForBranch] /
  /// [watchDetailForBranch] instead, and the architecture test enforces the split.
  Future<PurchaseRequestDetail?> getDetail(String prId);

  /// The document, but only if it belongs to [branchId].
  ///
  /// The branch predicate is part of the query, so a foreign document is never
  /// loaded rather than being loaded and then withheld.
  Future<PurchaseRequestDetail?> getDetailForBranch({
    required String prId,
    required String branchId,
  });

  /// Live version of [getDetailForBranch]. A stream opened for one branch can
  /// never emit another branch's document, whatever happens underneath it.
  Stream<PurchaseRequestDetail?> watchDetailForBranch({
    required String prId,
    required String branchId,
  });

  /// The document for a warehouse reader, which is not branch-scoped by design:
  /// the central warehouse's queue spans every branch (spec §4.2).
  ///
  /// Separate from [getDetail] so the unscoped read a *screen* performs is a named,
  /// searchable decision rather than the same method the use cases use.
  Stream<PurchaseRequestDetail?> watchDetailForWarehouse(String prId);

  Future<PurchaseRequestDetail?> getDetailForWarehouse(String prId);

  /// Read authorization, answered without reading the document.
  ///
  /// Returns `null` when [prId] does not name a live document **of [branchId]** —
  /// one answer for "no such document" and for "another branch's", so a caller
  /// cannot probe which ids exist elsewhere. [branchId] is `null` for the
  /// warehouse, whose scope is every branch.
  Future<PurchaseRequestAccessScope?> findAccessScope({
    required String prId,
    String? branchId,
  });

  Future<List<PurchaseRequestSummary>> list(PurchaseRequestFilter filter);

  Stream<List<PurchaseRequestSummary>> watchList(PurchaseRequestFilter filter);

  /// Every request of one branch, newest first — the Kepala Cabang list.
  Stream<List<PurchaseRequestSummary>> watchForBranch({
    required String branchId,
    Set<PurchaseRequestStatus> statuses,
  });

  /// The warehouse inbox: `submitted` and `processing` across every branch, plus
  /// whatever else [statuses] asks for.
  Stream<List<PurchaseRequestSummary>> watchWarehouseQueue({
    Set<PurchaseRequestStatus> statuses,
    String? branchId,
    String? searchQuery,
  });

  /// G-P4: the branch's live `submitted`/`processing` request, if any.
  Future<PurchaseRequest?> activeRequestForBranch(String branchId);

  /// G-P1: the counts [branchId] may cite right now, already filtered to
  /// `submitted`/`reviewed` and to the operational weeks [periods] names.
  Future<List<PurchaseRequestOpnameReference>> eligibleOpnames({
    required String branchId,
    required List<({int year, int week})> periods,
  });

  /// One opname by id, **unscoped and unfiltered by status**.
  ///
  /// The create and submit validation loads the row and then applies G-P1 itself,
  /// which is what lets it say *why* a citation was refused. A query that already
  /// filtered the ineligible cases away could only ever answer "not found", and a
  /// branch head told that about their own branch's draft count learns nothing.
  Future<PurchaseRequestOpnameReference?> opnameReferenceById(String opnameId);

  /// The counts this document already cites.
  Future<List<PurchaseRequestOpnameReference>> linkedOpnames(String prId);

  /// Opname ids of every live citation, read without joining `stock_opnames`.
  ///
  /// [linkedOpnames] inner-joins the count and its room so a citation can be
  /// rendered, which means a citation whose opname row is physically missing does
  /// not appear in the result at all. This is how a caller finds out that happened
  /// instead of quietly validating a document against fewer references than it has.
  Future<List<String>> linkedOpnameIds(String prId);

  /// Item ids of every live line, read without joining `items` — the counterpart
  /// of [linkedOpnameIds] for the requested half of the document.
  Future<List<String>> lineItemIds(String prId);

  /// The counted positions of one opname, as the suggestion calculator wants
  /// them. Reads the snapshot (`counted_qty`), never a live balance.
  Future<List<OpnameCountedPosition>> countedPositionsOf(String opnameId);

  Future<PurchaseRequestLine?> lineById(String lineId);

  /// Whether this item already has a live line — the G-P2 duplicate check.
  Future<PurchaseRequestLine?> findLineByItem({
    required String prId,
    required String itemId,
  });

  /// Needed date and note of a **draft** header.
  ///
  /// Both fields are written, so a `null` clears rather than preserves: this is a
  /// "the header now reads like this" operation, not a partial patch. The editor
  /// always sends the whole header state it has on screen, which is what makes that
  /// the simpler contract — a patch semantics would need a sentinel per field to tell
  /// "unchanged" from "cleared".
  ///
  /// Returns `false` when nothing was updated because the document is no longer a
  /// draft — the caller turns that into a state failure.
  Future<bool> updateDraftHeader({
    required String prId,
    DateTime? neededDate,
    String? note,
  });

  /// Requested quantity and note of a **draft** line. Cannot reach
  /// `suggested_qty`.
  Future<bool> updateDraftLine({
    required String lineId,
    required Quantity requestedQty,
    String? note,
  });

  /// Appends a line the branch head asked for by hand. Returns `null` when the
  /// document is no longer a draft.
  Future<PurchaseRequestLine?> addDraftLine({
    required String prId,
    required String itemId,
    required Quantity suggestedQty,
    required Quantity requestedQty,
    String? note,
  });

  /// Soft-deletes a line from a draft. `false` when the guard rejected it.
  Future<bool> removeDraftLine(String lineId);

  /// Replaces a draft's citations and rewrites the suggestions that follow from
  /// them, in one transaction.
  ///
  /// This is the only path that may move `suggested_qty`, and it exists as one
  /// operation rather than as "unlink, link, update each line" because the
  /// intermediate states are all wrong: a document citing nothing, or citing new
  /// counts while its lines still hold the old arithmetic.
  ///
  /// [lines] is the full desired line set. Existing lines are updated in place so
  /// the branch head's requested quantities and notes survive, lines that no
  /// longer have a suggestion keep whatever was requested (they become manual
  /// lines rather than disappearing), and genuinely new items are inserted.
  Future<void> replaceOpnameLinksAndSuggestions({
    required String prId,
    required List<String> opnameIds,
    required List<PurchaseRequestLineReconciliation> lines,
  });

  /// `draft → submitted`. `false` when the document was not a draft any more at
  /// the moment of the write.
  ///
  /// Throws [PurchaseRequestAlreadyActiveFailure] when the branch's partial
  /// unique index refuses the write because another request is already active —
  /// the final guard behind G-P4 when two devices submit at once.
  Future<bool> submit({required String prId, required DateTime submittedAtUtc});

  /// `draft → cancelled` or `submitted → cancelled` (G-S3). The caller states
  /// which, so `processing` can never be cancelled by passing the wrong argument.
  Future<bool> cancel({
    required String prId,
    required PurchaseRequestStatus from,
    required String cancelledBy,
    required DateTime cancelledAtUtc,
    required String reason,
  });

  /// `submitted → processing`.
  Future<bool> markProcessing({
    required String prId,
    required String processedBy,
    required DateTime processingAtUtc,
  });

  /// `processing → rejected`.
  Future<bool> reject({
    required String prId,
    required String rejectedBy,
    required DateTime rejectedAtUtc,
    required String reason,
  });

  /// Soft-deletes a draft; submitted and later documents are refused (G-A5).
  Future<bool> removeDraft(String prId);

  /// Local, offline item search for the SearchableDropdown (name or SKU,
  /// case-insensitive, optionally restricted to one category). Active items only:
  /// this feeds "add an item by hand", which is new work.
  Future<List<MasterItem>> searchAddableItems({
    required String query,
    String? categoryId,
    int limit,
  });
}

/// What one line should look like after a recompute.
///
/// Carries the identity of the line if it already exists, so the repository can
/// update in place instead of deleting and re-inserting — which would lose the
/// row's `created_at`, its id, and with it any note the branch head had written.
class PurchaseRequestLineReconciliation {
  const PurchaseRequestLineReconciliation({
    this.lineId,
    required this.itemId,
    required this.suggestedQty,
    required this.requestedQty,
    this.note,
  });

  /// `null` for an item that has no line yet.
  final String? lineId;

  final String itemId;
  final Quantity suggestedQty;
  final Quantity requestedQty;
  final String? note;

  bool get isExisting => lineId != null;
}

/// Convenience filter for the warehouse inbox — the statuses its queue shows.
const Set<PurchaseRequestStatus> warehouseQueueStatuses = {
  PurchaseRequestStatus.submitted,
  PurchaseRequestStatus.processing,
};
