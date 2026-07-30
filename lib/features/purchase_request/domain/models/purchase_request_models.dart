import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/operational_iso_week.dart';
import '../services/purchase_request_quantity_policy.dart';

/// Purchase Request header, in domain terms.
///
/// Immutable on purpose: a document is never mutated in place. Reads produce a
/// new instance and every write goes through a use case. Quantities are
/// [Quantity], event timestamps are UTC instants (T-1), and `neededDate` is a
/// civil date that is never timezone converted (T-8).
class PurchaseRequest {
  const PurchaseRequest({
    required this.id,
    required this.docNumber,
    required this.branchId,
    required this.requestedBy,
    required this.status,
    this.neededDate,
    this.note,
    this.submittedAt,
    this.processingAt,
    this.processedBy,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.rejectedAt,
    this.rejectedBy,
    this.rejectReason,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;

  /// `TMP-PR-{uuid}` until the sync backend assigns the final number (G-Y4).
  final String docNumber;

  final String branchId;
  final String requestedBy;
  final PurchaseRequestStatus status;

  /// Civil date — never timezone converted (T-8/T-9).
  final DateTime? neededDate;

  final String? note;

  /// UTC instants; convert through `AppDateTimeFormatter` before displaying.
  final DateTime? submittedAt;
  final DateTime? processingAt;
  final String? processedBy;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;
  final DateTime? rejectedAt;
  final String? rejectedBy;
  final String? rejectReason;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  bool get isDraft => status.isDraft;

  bool get isSubmitted => status.isSubmitted;

  bool get isProcessing => status.isProcessing;

  bool get isShipped => status.isShipped;

  bool get isClosed => status.isClosed;

  bool get isRejected => status.isRejected;

  bool get isCancelled => status.isCancelled;

  /// G-P5 — only a draft may be edited.
  bool get isEditable => status.isEditable;

  /// G-P4 — whether this document occupies the branch's active order slot.
  bool get isActiveOrder => status.isActiveOrder;

  bool get isFinal => status.isFinal;

  /// Whether the local copy is still waiting to be synchronised (G-Y1).
  bool get isPendingSync => syncStatus == SyncStatus.pending;

  /// The ISO week the request was raised in, read in operational time.
  OperationalIsoWeek get createdWeek =>
      OperationalIsoWeek.ofUtcInstant(createdAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseRequest &&
          other.id == id &&
          other.status == status &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(id, status, updatedAt);

  @override
  String toString() => 'PurchaseRequest($docNumber, ${status.dbValue})';
}

/// The smallest fact set that decides whether somebody may open a document.
///
/// Deliberately tiny: an authorization check must not be the reason a document's
/// contents are loaded. Nothing here identifies an item, a quantity, a note or a
/// cited count — only the owning branch, the status, and who raised it.
class PurchaseRequestAccessScope {
  const PurchaseRequestAccessScope({
    required this.prId,
    required this.branchId,
    required this.status,
    required this.requestedBy,
  });

  final String prId;
  final String branchId;
  final PurchaseRequestStatus status;
  final String requestedBy;
}

/// One requested item, enriched with the item data the form and the queue need.
class PurchaseRequestLine {
  const PurchaseRequestLine({
    required this.id,
    required this.prId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.suggestedQty,
    required this.requestedQty,
    this.note,
    this.itemIsHistorical = false,
  });

  final String id;
  final String prId;
  final String itemId;

  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  /// The item was deactivated or archived after this line was created. The line
  /// stays visible and stays processable — the badge only explains why the item
  /// can no longer be picked for a new request.
  final bool itemIsHistorical;

  /// System suggestion, snapshotted when the draft was created (or when its
  /// opname selection last changed). Never edited by hand.
  final Quantity suggestedQty;

  /// What the branch head asks for. Strictly positive (G-P2).
  final Quantity requestedQty;

  final String? note;

  /// `requested − suggested`; negative when the branch head asks for less than
  /// the system proposed (Q-7 allows a negative difference).
  Quantity get difference => requestedQty - suggestedQty;

  /// G-P3 — a request with no suggestion behind it at all.
  bool get isManualRequest =>
      PurchaseRequestQuantityPolicy.isManualRequest(suggestedQty);

  /// G-P3 — strictly more than 150 % of the suggestion.
  bool get isAboveSuggestionThreshold =>
      PurchaseRequestQuantityPolicy.isAboveSuggestionThreshold(
        suggested: suggestedQty,
        requested: requestedQty,
      );

  /// Whether this line needs a written reason before the document can be sent.
  bool get requiresJustification =>
      PurchaseRequestQuantityPolicy.requiresJustification(
        suggested: suggestedQty,
        requested: requestedQty,
      );

  bool get hasNote => PurchaseRequestQuantityPolicy.hasJustification(note);

  /// Whether this line would block a submit as it stands.
  bool get isSubmittable =>
      requestedQty.isPositive && (!requiresJustification || hasNote);

  String get displayName => itemName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseRequestLine &&
          other.id == id &&
          other.requestedQty == requestedQty &&
          other.suggestedQty == suggestedQty &&
          other.note == note);

  @override
  int get hashCode => Object.hash(id, requestedQty, suggestedQty, note);

  @override
  String toString() =>
      'PurchaseRequestLine($sku, suggested: ${suggestedQty.format()}, '
      'requested: ${requestedQty.format()})';
}

/// One stock opname a request cites, with the context both the picker and the
/// read-only detail screen show.
///
/// The same model serves "an opname you may choose" and "an opname this document
/// already rests on", because the facts a reader needs are identical and keeping
/// two classes in step by hand is how they stop agreeing.
class PurchaseRequestOpnameReference {
  const PurchaseRequestOpnameReference({
    this.linkId,
    required this.opnameId,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.periodYear,
    required this.periodWeek,
    required this.status,
    required this.countedByName,
    this.submittedAt,
    this.reviewedAt,
    required this.differenceLineCount,
    this.roomIsHistorical = false,
    this.countedByIsHistorical = false,
  });

  /// Id of the `purchase_request_opnames` row. `null` for a candidate that has
  /// not been cited yet.
  final String? linkId;

  final String opnameId;
  final String docNumber;
  final String branchId;
  final String roomId;
  final String roomCode;
  final String roomName;
  final int periodYear;
  final int periodWeek;
  final StockOpnameStatus status;
  final String countedByName;

  /// UTC instants (T-1).
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  final int differenceLineCount;

  final bool roomIsHistorical;
  final bool countedByIsHistorical;

  OperationalIsoWeek get period =>
      OperationalIsoWeek(year: periodYear, week: periodWeek);

  /// `2026-W31`.
  String get periodLabel => period.label;

  /// The instant this count became citable — reviewed if it has been, otherwise
  /// submitted.
  DateTime? get handedOverAt => reviewedAt ?? submittedAt;

  bool get hasDifference => differenceLineCount > 0;

  bool get usesHistoricalMaster => roomIsHistorical || countedByIsHistorical;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseRequestOpnameReference &&
          other.opnameId == opnameId &&
          other.linkId == linkId);

  @override
  int get hashCode => Object.hash(opnameId, linkId);

  @override
  String toString() =>
      'PurchaseRequestOpnameReference($docNumber, $roomCode, $periodLabel)';
}

/// A header plus the names a list row needs, without a second query.
///
/// The `…IsHistorical` flags exist so a screen can *say* that a document rests
/// on master data that has since been deactivated or archived. They are never a
/// reason to hide the row: a submitted request whose branch was retired is
/// exactly the document the warehouse still has to act on.
class PurchaseRequestSummary {
  const PurchaseRequestSummary({
    required this.request,
    required this.branchCode,
    required this.branchName,
    required this.requestedByName,
    this.processedByName,
    this.cancelledByName,
    this.rejectedByName,
    required this.lineCount,
    required this.linkedOpnameCount,
    this.branchIsHistorical = false,
    this.requestedByIsHistorical = false,
  });

  final PurchaseRequest request;
  final String branchCode;
  final String branchName;
  final String requestedByName;
  final String? processedByName;
  final String? cancelledByName;
  final String? rejectedByName;
  final int lineCount;
  final int linkedOpnameCount;

  /// Branch deactivated or soft-deleted since the request was raised.
  final bool branchIsHistorical;

  /// The branch head who raised it has been deactivated or removed since.
  final bool requestedByIsHistorical;

  String get id => request.id;

  PurchaseRequestStatus get status => request.status;

  String get docNumber => request.docNumber;

  /// Whether anything on the header points at master data that is out of
  /// service — the trigger for the "Data historis" badge.
  bool get usesHistoricalMaster =>
      branchIsHistorical || requestedByIsHistorical;

  /// How long the request has been waiting for the warehouse, measured from the
  /// submission. `null` while it is still a draft.
  ///
  /// [nowUtc] is passed in rather than read from a clock so the value stays
  /// deterministic in tests (T-7).
  Duration? ageSinceSubmission(DateTime nowUtc) {
    final submitted = request.submittedAt;
    if (submitted == null) return null;
    final age = nowUtc.toUtc().difference(submitted);
    // A device whose clock is behind must not render a negative age.
    return age.isNegative ? Duration.zero : age;
  }
}

/// Everything the detail, edit and warehouse screens need about one document.
class PurchaseRequestDetail {
  const PurchaseRequestDetail({
    required this.summary,
    required this.lines,
    required this.opnames,
  });

  final PurchaseRequestSummary summary;
  final List<PurchaseRequestLine> lines;
  final List<PurchaseRequestOpnameReference> opnames;

  PurchaseRequest get request => summary.request;

  String get id => request.id;

  PurchaseRequestStatus get status => request.status;

  bool get isEditable => request.isEditable;

  bool get isFinal => request.isFinal;

  bool get isEmpty => lines.isEmpty;

  bool get hasOpnameReference => opnames.isNotEmpty;

  /// Lines that still need a reason before the request can be sent (G-P3).
  List<PurchaseRequestLine> get linesMissingJustification =>
      lines.where((line) => !line.isSubmittable).toList(growable: false);

  List<PurchaseRequestLine> get linesAboveThreshold => lines
      .where((line) => line.isAboveSuggestionThreshold)
      .toList(growable: false);

  List<PurchaseRequestLine> get manualLines =>
      lines.where((line) => line.isManualRequest).toList(growable: false);

  bool get isSubmittable =>
      lines.isNotEmpty &&
      hasOpnameReference &&
      linesMissingJustification.isEmpty;

  /// Requested totals grouped by unit.
  ///
  /// Quantities of different units are never added together: `2 box` and `3 pcs`
  /// are not `5` of anything, and one headline number would mislead.
  Map<String, Quantity> get requestedByUnit {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.unit] =
          (totals[line.unit] ?? Quantity.zero()) + line.requestedQty;
    }
    return totals;
  }

  /// Whether any part of the document — header or a line's item — rests on
  /// master data that is out of service.
  bool get usesHistoricalMaster =>
      summary.usesHistoricalMaster ||
      lines.any((line) => line.itemIsHistorical) ||
      opnames.any((reference) => reference.usesHistoricalMaster);
}

/// Filter state for the request lists and the form's item list.
class PurchaseRequestFilter {
  const PurchaseRequestFilter({
    this.branchId,
    this.statuses = const <PurchaseRequestStatus>{},
    this.categoryId,
    this.searchQuery = '',
  });

  /// `null` means every branch — the warehouse queue.
  final String? branchId;

  final Set<PurchaseRequestStatus> statuses;

  /// `null` means "Semua" on the CategoryFilterChips row.
  final String? categoryId;

  final String searchQuery;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  /// Whether a line passes the category and search filters. Applied in memory on
  /// the already-loaded document, so filtering never re-queries and keeps working
  /// offline (G-Y1).
  bool matchesLine(PurchaseRequestLine line) {
    if (categoryId != null && line.categoryId != categoryId) return false;
    if (!hasSearch) return true;

    final needle = searchQuery.trim().toLowerCase();
    return line.itemName.toLowerCase().contains(needle) ||
        line.sku.toLowerCase().contains(needle);
  }

  PurchaseRequestFilter copyWith({
    String? branchId,
    Set<PurchaseRequestStatus>? statuses,
    Object? categoryId = _unset,
    String? searchQuery,
  }) {
    return PurchaseRequestFilter(
      branchId: branchId ?? this.branchId,
      statuses: statuses ?? this.statuses,
      categoryId: categoryId == _unset
          ? this.categoryId
          : categoryId as String?,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  /// Sentinel so `copyWith(categoryId: null)` can mean "clear the filter" rather
  /// than "keep the current value".
  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseRequestFilter &&
          other.branchId == branchId &&
          other.categoryId == categoryId &&
          other.searchQuery == searchQuery &&
          _sameStatuses(other.statuses));

  bool _sameStatuses(Set<PurchaseRequestStatus> other) =>
      other.length == statuses.length && other.containsAll(statuses);

  @override
  int get hashCode => Object.hash(
    branchId,
    categoryId,
    searchQuery,
    Object.hashAllUnordered(statuses),
  );
}

/// One line the system proposes, before anybody has edited it.
///
/// Carries the working shown on the review step — which rooms the deficiency came
/// from, what was counted there in total, and the par level it was measured
/// against — so the branch head can see *why* the suggestion is what it is
/// instead of being handed a bare number.
class SuggestedPurchaseRequestLine {
  const SuggestedPurchaseRequestLine({
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.parLevelPerRoom,
    required this.countedTotal,
    required this.suggestedQty,
    required this.sourceRoomNames,
  });

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  /// `items.min_stock_room`, the par level each room is measured against.
  final Quantity parLevelPerRoom;

  /// Sum of `counted_qty` over every cited room and, for batch-tracked items,
  /// over every batch within them.
  final Quantity countedTotal;

  /// `sum over rooms of max(0, par − counted in that room)`.
  final Quantity suggestedQty;

  /// Rooms whose count contributed a deficiency, in display order.
  final List<String> sourceRoomNames;

  bool get isPositive => suggestedQty.isPositive;

  @override
  String toString() =>
      'SuggestedPurchaseRequestLine($sku, ${suggestedQty.format()})';
}

/// One position to write when a draft is created.
class PurchaseRequestLineDraft {
  const PurchaseRequestLineDraft({
    required this.itemId,
    required this.suggestedQty,
    required this.requestedQty,
    this.note,
  });

  final String itemId;
  final Quantity suggestedQty;
  final Quantity requestedQty;
  final String? note;
}
