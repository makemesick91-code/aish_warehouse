import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';

/// Stok Opname document header, in domain terms.
///
/// Immutable on purpose: a document is never mutated in place. Reads produce a
/// new instance, and every write goes through a use case that returns the new
/// state. Quantities are [Quantity], timestamps are UTC instants (T-1), and the
/// period is an ISO week of the GMT+8 operational calendar (T-3).
class StockOpname {
  const StockOpname({
    required this.id,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.periodYear,
    required this.periodWeek,
    required this.countedBy,
    required this.status,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;

  /// `TMP-SO-{uuid}` until the sync backend assigns the final number (G-Y4).
  final String docNumber;

  final String branchId;
  final String roomId;
  final int periodYear;
  final int periodWeek;
  final String countedBy;
  final StockOpnameStatus status;

  /// UTC instants; convert through `AppDateTimeFormatter` before displaying.
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  bool get isDraft => status.isDraft;

  bool get isSubmitted => status.isSubmitted;

  bool get isReviewed => status.isReviewed;

  /// A final document is read-only permanently, lines included (G-S2).
  bool get isFinal => status.isFinal;

  /// Only a draft can be edited at all.
  bool get canEdit => status.isDraft;

  bool get canSubmit => status.canTransitionTo(StockOpnameStatus.submitted);

  bool get canReview => status.canTransitionTo(StockOpnameStatus.reviewed);

  /// G-O4 — whether a Purchase Request may cite this document.
  bool get isPurchaseRequestReference => status.isPurchaseRequestReference;

  /// `2026-W31`, the human form of the weekly key.
  String get periodLabel =>
      '$periodYear-W${periodWeek.toString().padLeft(2, '0')}';

  /// Whether the local copy is still waiting to be synchronised (G-Y1).
  bool get isPendingSync => syncStatus == SyncStatus.pending;

  /// Whether this document is the one covering [utcNow]'s ISO week.
  bool coversOperationalWeekOf(DateTime utcNow) {
    final date = AppTimeZone.operationalDate(utcNow);
    return periodYear == AppTimeZone.isoWeekYear(date) &&
        periodWeek == AppTimeZone.isoWeekNumber(date);
  }

  StockOpname copyWith({
    StockOpnameStatus? status,
    DateTime? submittedAt,
    DateTime? reviewedAt,
    String? reviewedBy,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) {
    return StockOpname(
      id: id,
      docNumber: docNumber,
      branchId: branchId,
      roomId: roomId,
      periodYear: periodYear,
      periodWeek: periodWeek,
      countedBy: countedBy,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockOpname &&
          other.id == id &&
          other.status == status &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(id, status, updatedAt);

  @override
  String toString() => 'StockOpname($docNumber, ${status.dbValue})';
}

/// One counted position, enriched with the item and batch data the form needs.
class StockOpnameLine {
  const StockOpnameLine({
    required this.id,
    required this.opnameId,
    required this.itemId,
    this.batchId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    this.batchNo,
    this.expiryDate,
    required this.systemQty,
    required this.countedQty,
    required this.difference,
    this.note,
  });

  final String id;
  final String opnameId;
  final String itemId;
  final String? batchId;

  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8/T-9).
  final DateTime? expiryDate;

  /// Balance snapshotted when the opname was created; never changes (G-O2).
  final Quantity systemQty;

  /// What the nurse actually found on the shelf.
  final Quantity countedQty;

  /// `counted - system`, as computed by the database. May be negative (Q-7).
  final Quantity difference;

  final String? note;

  bool get hasDifference => !difference.isZero;

  bool get isSurplus => difference.isPositive;

  bool get isShortage => difference.isNegative;

  /// G-O3: a reason is mandatory exactly when the difference is not zero.
  bool get requiresNote => hasDifference;

  bool get hasNote => (note ?? '').trim().isNotEmpty;

  /// Whether this line would block a submit as it stands.
  bool get isSubmittable => !requiresNote || hasNote;

  /// Expiry is judged against the operational date (T-10), so a batch counts as
  /// valid for the whole of its expiry day in GMT+8.
  bool isExpiredOn(DateTime referenceUtc) {
    final expiry = expiryDate;
    if (expiry == null) return false;
    return DateOnly.isBeforeDate(
      expiry,
      AppTimeZone.operationalDate(referenceUtc),
    );
  }

  int? daysUntilExpiry(DateTime referenceUtc) {
    final expiry = expiryDate;
    if (expiry == null) return null;
    return DateOnly.daysBetween(
      AppTimeZone.operationalDate(referenceUtc),
      expiry,
    );
  }

  /// `Masker Bedah` or `Anestesi Lokal · Batch LID-2403`.
  String get displayName =>
      batchNo == null ? itemName : '$itemName · Batch $batchNo';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockOpnameLine &&
          other.id == id &&
          other.countedQty == countedQty &&
          other.systemQty == systemQty &&
          other.note == note);

  @override
  int get hashCode => Object.hash(id, countedQty, systemQty, note);

  @override
  String toString() =>
      'StockOpnameLine($sku${batchNo == null ? '' : '/$batchNo'}, '
      'system: ${systemQty.format()}, counted: ${countedQty.format()})';
}

/// A header plus the names needed to render a list row, without a second query.
class StockOpnameSummary {
  const StockOpnameSummary({
    required this.opname,
    required this.roomCode,
    required this.roomName,
    required this.branchName,
    required this.countedByName,
    this.reviewedByName,
    required this.lineCount,
    required this.differenceLineCount,
  });

  final StockOpname opname;
  final String roomCode;
  final String roomName;
  final String branchName;
  final String countedByName;
  final String? reviewedByName;
  final int lineCount;
  final int differenceLineCount;

  String get id => opname.id;

  StockOpnameStatus get status => opname.status;

  bool get hasDifference => differenceLineCount > 0;
}

/// Everything the detail and review screens need about one document.
class StockOpnameDetail {
  const StockOpnameDetail({required this.summary, required this.lines});

  final StockOpnameSummary summary;
  final List<StockOpnameLine> lines;

  StockOpname get opname => summary.opname;

  String get id => opname.id;

  StockOpnameStatus get status => opname.status;

  bool get canEdit => opname.canEdit;

  bool get isFinal => opname.isFinal;

  bool get isEmpty => lines.isEmpty;

  List<StockOpnameLine> get linesWithDifference =>
      lines.where((line) => line.hasDifference).toList(growable: false);

  /// Lines that still need a reason before the document can be submitted.
  List<StockOpnameLine> get linesMissingNote =>
      lines.where((line) => !line.isSubmittable).toList(growable: false);

  bool get isSubmittable => lines.isNotEmpty && linesMissingNote.isEmpty;

  /// Surplus totals grouped by unit.
  ///
  /// Quantities of different units are never added together: `2 box` and
  /// `3 pcs` are not `5` of anything, and a single headline number would be
  /// actively misleading on a review screen.
  Map<String, Quantity> get surplusByUnit =>
      _totalsByUnit((line) => line.isSurplus);

  Map<String, Quantity> get shortageByUnit =>
      _totalsByUnit((line) => line.isShortage);

  Map<String, Quantity> _totalsByUnit(bool Function(StockOpnameLine) include) {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      if (!include(line)) continue;
      totals[line.unit] =
          (totals[line.unit] ?? Quantity.zero()) + line.difference.absolute;
    }
    return totals;
  }
}

/// Filter state for the opname list and the form's item list.
class StockOpnameFilter {
  const StockOpnameFilter({
    this.branchId,
    this.roomId,
    this.countedBy,
    this.statuses = const <StockOpnameStatus>{},
    this.categoryId,
    this.searchQuery = '',
  });

  final String? branchId;
  final String? roomId;
  final String? countedBy;
  final Set<StockOpnameStatus> statuses;

  /// `null` means "Semua" on the CategoryFilterChips row.
  final String? categoryId;

  final String searchQuery;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  /// Whether a line passes the category and search filters. Applied in memory
  /// on the already-loaded document, so filtering never re-queries and keeps
  /// working offline.
  bool matchesLine(StockOpnameLine line) {
    if (categoryId != null && line.categoryId != categoryId) return false;
    if (!hasSearch) return true;

    final needle = searchQuery.trim().toLowerCase();
    return line.itemName.toLowerCase().contains(needle) ||
        line.sku.toLowerCase().contains(needle) ||
        (line.batchNo?.toLowerCase().contains(needle) ?? false);
  }

  StockOpnameFilter copyWith({
    String? branchId,
    String? roomId,
    String? countedBy,
    Set<StockOpnameStatus>? statuses,
    Object? categoryId = _unset,
    String? searchQuery,
  }) {
    return StockOpnameFilter(
      branchId: branchId ?? this.branchId,
      roomId: roomId ?? this.roomId,
      countedBy: countedBy ?? this.countedBy,
      statuses: statuses ?? this.statuses,
      categoryId: categoryId == _unset
          ? this.categoryId
          : categoryId as String?,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  /// Sentinel so `copyWith(categoryId: null)` can mean "clear the filter"
  /// rather than "keep the current value".
  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockOpnameFilter &&
          other.branchId == branchId &&
          other.roomId == roomId &&
          other.countedBy == countedBy &&
          other.categoryId == categoryId &&
          other.searchQuery == searchQuery &&
          _sameStatuses(other.statuses));

  bool _sameStatuses(Set<StockOpnameStatus> other) =>
      other.length == statuses.length && other.containsAll(statuses);

  @override
  int get hashCode => Object.hash(
    branchId,
    roomId,
    countedBy,
    categoryId,
    searchQuery,
    Object.hashAllUnordered(statuses),
  );
}

/// One position to snapshot when a document is created.
class StockOpnameLineDraft {
  const StockOpnameLineDraft({
    required this.itemId,
    this.batchId,
    required this.systemQty,
    required this.countedQty,
    this.note,
  });

  final String itemId;
  final String? batchId;
  final Quantity systemQty;
  final Quantity countedQty;
  final String? note;
}
