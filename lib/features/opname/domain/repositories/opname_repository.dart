import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/opname_models.dart';

/// Stok Opname persistence, expressed in domain terms.
///
/// The shape of this contract encodes the guardrails:
///
/// * There is no `update(StockOpname)` and no `delete`. The only writes are
///   the specific, guarded operations below, so an arbitrary mutation of a
///   submitted or reviewed document is not expressible (G-S2).
/// * There is no way to write `system_qty` after creation (G-O2).
/// * Status changes go through [submit] and [markReviewed], each of which
///   states the transition it expects and fails when the document has moved on.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers stay
/// behind the implementation (Q-4).
abstract interface class OpnameRepository {
  /// Runs [action] in a single database transaction. The review posting uses
  /// this to make "adjust every line and lock the document" one atomic step.
  Future<T> runInTransaction<T>(Future<T> Function() action);

  /// Inserts a header together with its whole snapshot. Atomic: a header
  /// without lines can never be observed.
  Future<StockOpname> createDraft({
    required String docNumber,
    required String branchId,
    required String roomId,
    required int periodYear,
    required int periodWeek,
    required String countedBy,
    required List<StockOpnameLineDraft> lines,
  });

  Future<StockOpname?> getById(String opnameId);

  Future<StockOpnameDetail?> getDetail(String opnameId);

  Stream<StockOpnameDetail?> watchDetail(String opnameId);

  Future<List<StockOpnameSummary>> list(StockOpnameFilter filter);

  Stream<List<StockOpnameSummary>> watchList(StockOpnameFilter filter);

  /// The G-O1 lookup: the document already covering this room and ISO week.
  Future<StockOpname?> findForRoomAndPeriod({
    required String roomId,
    required int periodYear,
    required int periodWeek,
  });

  Future<StockOpnameLine?> lineById(String lineId);

  Future<StockOpnameLine?> findLine({
    required String opnameId,
    required String itemId,
    String? batchId,
  });

  /// Writes a counted quantity and note on a **draft** line.
  ///
  /// Returns `false` when nothing was updated because the document is no longer
  /// a draft or the line is gone — the caller turns that into a state failure.
  Future<bool> updateDraftLine({
    required String lineId,
    required Quantity countedQty,
    String? note,
  });

  /// Appends a position that was found physically but was not in the snapshot.
  /// Returns `null` when the document is no longer a draft.
  Future<StockOpnameLine?> addDraftLine({
    required String opnameId,
    required String itemId,
    String? batchId,
    required Quantity systemQty,
    required Quantity countedQty,
    String? note,
  });

  /// Soft-deletes a line from a draft. `false` when the guard rejected it.
  Future<bool> removeDraftLine(String lineId);

  /// `draft → submitted`. Returns `false` when the document was not a draft
  /// any more at the moment of the write.
  Future<bool> submit({
    required String opnameId,
    required DateTime submittedAtUtc,
  });

  /// `submitted → reviewed`. Must be called inside the same transaction as the
  /// ledger postings, so the lock and the stock adjustment commit together.
  Future<bool> markReviewed({
    required String opnameId,
    required String reviewedBy,
    required DateTime reviewedAtUtc,
  });

  /// Soft-deletes a draft; final documents are refused (G-A5).
  Future<bool> removeDraft(String opnameId);

  /// Local, offline item search for the SearchableDropdown (name or SKU,
  /// case-insensitive, optionally restricted to one category).
  Future<List<MasterItem>> searchAddableItems({
    required String query,
    String? categoryId,
    int limit,
  });

  /// Number of lines whose difference is not zero — used by list badges.
  Future<int> countDifferenceLines(String opnameId);
}

/// Convenience filter for the review inbox of one branch.
StockOpnameFilter submittedForBranch(String branchId) => StockOpnameFilter(
  branchId: branchId,
  statuses: const {StockOpnameStatus.submitted},
);
