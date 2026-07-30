import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';

/// Delivery Order header, in domain terms.
///
/// Immutable on purpose: a document is never mutated in place. Reads produce a
/// new instance and every write goes through a use case. Quantities are
/// [Quantity], event timestamps are UTC instants (T-1).
class DeliveryOrder {
  const DeliveryOrder({
    required this.id,
    required this.docNumber,
    required this.prId,
    required this.preparedBy,
    required this.status,
    this.shippedAt,
    this.shippedBy,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;

  /// `TMP-DO-{uuid}` until the sync backend assigns the final number (G-Y4).
  final String docNumber;

  final String prId;
  final String preparedBy;
  final DeliveryOrderStatus status;

  /// UTC instant; convert through `AppDateTimeFormatter` before displaying.
  final DateTime? shippedAt;
  final String? shippedBy;
  final String? note;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  bool get isPreparing => status.isPreparing;

  bool get isShipped => status.isShipped;

  bool get isReceived => status.isReceived;

  /// Only a document that has not left the warehouse may be edited.
  bool get isEditable => status.isEditable;

  bool get isFinal => status.isFinal;

  bool get canShip => status.canShip;

  /// Whether the local copy is still waiting to be synchronised (G-Y1).
  bool get isPendingSync => syncStatus == SyncStatus.pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeliveryOrder &&
          other.id == id &&
          other.status == status &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(id, status, updatedAt);

  @override
  String toString() => 'DeliveryOrder($docNumber, ${status.dbValue})';
}

/// The smallest fact set that decides whether somebody may open a document.
///
/// Deliberately tiny: an authorization check must not be the reason a document's
/// contents are loaded. Nothing here identifies an item, a batch, a quantity or a
/// note — only the owning branch, the request and the status.
class DeliveryOrderAccessScope {
  const DeliveryOrderAccessScope({
    required this.doId,
    required this.prId,
    required this.branchId,
    required this.status,
  });

  final String doId;
  final String prId;
  final String branchId;
  final DeliveryOrderStatus status;
}

/// One allocated position of a Delivery Order, enriched with everything the form,
/// the detail screen and the Surat Jalan need.
class DeliveryOrderLine {
  const DeliveryOrderLine({
    required this.id,
    required this.doId,
    required this.prLineId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.requestedQty,
    required this.shippedQty,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    this.fefoOverrideReason,
    this.nearExpiryConfirmed = false,
    this.nearExpiryNote,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String id;
  final String doId;
  final String prLineId;
  final String itemId;

  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;

  /// What the branch asked for on the Purchase Request line this allocation
  /// satisfies. Carried so a reader can see the shipment in context without a
  /// second lookup.
  final Quantity requestedQty;

  /// What this allocation sends. Strictly positive.
  final Quantity shippedQty;

  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  final String? fefoOverrideReason;
  final bool nearExpiryConfirmed;
  final String? nearExpiryNote;

  /// The item or batch was deactivated or archived after the allocation was made.
  /// The line stays visible and stays shippable — the badge only explains why it
  /// can no longer be picked for something new.
  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get hasFefoOverride => (fefoOverrideReason ?? '').trim().isNotEmpty;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  /// Whether this batch is past its expiry date at [referenceUtc], judged against
  /// the **operational** date in GMT+8 (T-10) rather than the device's.
  bool isExpiredOn(DateTime referenceUtc) {
    final expiry = expiryDate;
    if (expiry == null) return false;
    return DateOnly.isBeforeDate(
      expiry,
      AppTimeZone.operationalDate(referenceUtc),
    );
  }

  /// Whole operational days until expiry; negative once expired.
  int? remainingDays(DateTime referenceUtc) {
    final expiry = expiryDate;
    if (expiry == null) return null;
    return DateOnly.daysBetween(
      AppTimeZone.operationalDate(referenceUtc),
      expiry,
    );
  }

  /// Whether the batch's shelf life is below the item's alert threshold (G-E4).
  bool isNearExpiryOn(DateTime referenceUtc) {
    final days = remainingDays(referenceUtc);
    return days != null && days < expiryAlertDays;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeliveryOrderLine &&
          other.id == id &&
          other.shippedQty == shippedQty &&
          other.batchId == batchId &&
          other.fefoOverrideReason == fefoOverrideReason &&
          other.nearExpiryConfirmed == nearExpiryConfirmed);

  @override
  int get hashCode => Object.hash(
    id,
    shippedQty,
    batchId,
    fefoOverrideReason,
    nearExpiryConfirmed,
  );

  @override
  String toString() =>
      'DeliveryOrderLine($sku, ${batchNo ?? 'tanpa batch'}, '
      '${shippedQty.format()})';
}

/// A header plus the names a list row needs, without a second query.
///
/// The `…IsHistorical` flags exist so a screen can *say* that a document rests on
/// master data that has since been deactivated or archived. They are never a
/// reason to hide the row: a shipment whose branch was retired afterwards is
/// exactly the document a branch still has to receive.
class DeliveryOrderSummary {
  const DeliveryOrderSummary({
    required this.order,
    required this.prDocNumber,
    required this.prStatus,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    this.branchAddress,
    required this.preparedByName,
    required this.requestedByName,
    this.shippedByName,
    required this.lineCount,
    this.branchIsHistorical = false,
    this.preparedByIsHistorical = false,
  });

  final DeliveryOrder order;
  final String prDocNumber;
  final PurchaseRequestStatus prStatus;
  final String branchId;
  final String branchCode;
  final String branchName;
  final String? branchAddress;
  final String preparedByName;
  final String requestedByName;
  final String? shippedByName;
  final int lineCount;

  final bool branchIsHistorical;
  final bool preparedByIsHistorical;

  String get id => order.id;

  String get docNumber => order.docNumber;

  DeliveryOrderStatus get status => order.status;

  bool get usesHistoricalMaster => branchIsHistorical || preparedByIsHistorical;
}

/// Everything the detail, edit, waybill and branch screens need about one
/// document.
class DeliveryOrderDetail {
  const DeliveryOrderDetail({
    required this.summary,
    required this.lines,
    required this.progress,
  });

  final DeliveryOrderSummary summary;
  final List<DeliveryOrderLine> lines;

  /// Shipment progress of every requested position of the parent request, with
  /// this document's own allocations counted separately (G-D2).
  final List<ShipmentProgress> progress;

  DeliveryOrder get order => summary.order;

  String get id => order.id;

  DeliveryOrderStatus get status => order.status;

  bool get isEditable => order.isEditable;

  bool get isFinal => order.isFinal;

  bool get isEmpty => lines.isEmpty;

  bool get hasFefoOverride => lines.any((line) => line.hasFefoOverride);

  bool get hasNearExpiryConfirmation =>
      lines.any((line) => line.nearExpiryConfirmed);

  /// Whether any batch on the document is inside its alert window at
  /// [referenceUtc] — what the Surat Jalan's near-expiry marker asks.
  bool hasNearExpiryBatch(DateTime referenceUtc) =>
      lines.any((line) => line.isNearExpiryOn(referenceUtc));

  /// Whether the parent request still has quantity outstanding after this
  /// document — i.e. whether this shipment is a partial one (G-D2).
  bool get isPartialShipment =>
      progress.any((entry) => entry.remainingAfterCurrentDo.isPositive);

  /// Whether posting this document would complete every requested position
  /// (G-D5).
  bool get completesPurchaseRequest =>
      progress.isNotEmpty && progress.every((entry) => entry.isFullyShipped);

  bool get usesHistoricalMaster =>
      summary.usesHistoricalMaster ||
      lines.any((line) => line.usesHistoricalMaster);

  /// Shipped totals grouped by unit.
  ///
  /// Quantities of different units are never added together: `2 box` and `3 pcs`
  /// are not `5` of anything, and one headline number would mislead.
  Map<String, Quantity> get shippedByUnit {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.unit] =
          (totals[line.unit] ?? Quantity.zero()) + line.shippedQty;
    }
    return totals;
  }
}

/// How far one requested position of a Purchase Request has been shipped.
///
/// The three quantities are kept apart rather than collapsed into one
/// "remaining", because every rule needs a different pair of them:
/// G-D2 compares `requested` against `previouslyShipped + currentDo`, the
/// allocation form offers `remainingBeforeCurrentDo` as the maximum, and G-D5
/// asks whether `remainingAfterCurrentDo` is zero.
///
/// All arithmetic is exact fixed point (Q-2): a request of `1.5` shipped as
/// `0.5 + 0.5 + 0.5` leaves exactly nothing, with no residue to accumulate.
class ShipmentProgress {
  const ShipmentProgress({
    required this.prLineId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.unit,
    required this.requestedQty,
    required this.previouslyShippedQty,
    required this.currentDoQty,
  });

  final String prLineId;
  final String itemId;
  final String sku;
  final String itemName;
  final String unit;

  /// What the branch asked for (G-P2: strictly positive).
  final Quantity requestedQty;

  /// Cumulative quantity of every **other** `shipped`/`received` Delivery Order
  /// of the same request. A `preparing` document is an intention, not a
  /// shipment, and is deliberately not counted here.
  final Quantity previouslyShippedQty;

  /// What the document in hand allocates, whatever its status.
  final Quantity currentDoQty;

  /// What is still outstanding before this document is taken into account — the
  /// ceiling the allocation form enforces.
  Quantity get remainingBeforeCurrentDo => requestedQty - previouslyShippedQty;

  /// What would still be outstanding once this document ships. Negative only
  /// when the allocation over-ships, which G-D2 refuses.
  Quantity get remainingAfterCurrentDo =>
      requestedQty - previouslyShippedQty - currentDoQty;

  /// Cumulative total including this document.
  Quantity get cumulativeQty => previouslyShippedQty + currentDoQty;

  /// Exactly satisfied — compared in fixed point, so "close enough" cannot
  /// happen (G-D5).
  bool get isFullyShipped => remainingAfterCurrentDo.isZero;

  /// G-D2 violated. Never a legitimate state; the ship path refuses it.
  bool get isOverShipped => remainingAfterCurrentDo.isNegative;

  /// Whether this position has nothing left to send even before this document.
  bool get isAlreadyComplete => remainingBeforeCurrentDo <= Quantity.zero();

  bool get hasCurrentAllocation => currentDoQty.isPositive;

  @override
  String toString() =>
      'ShipmentProgress($sku, requested ${requestedQty.format()}, '
      'shipped ${previouslyShippedQty.format()}, '
      'this DO ${currentDoQty.format()})';
}

/// One batch of an item, with the quantity the central warehouse currently holds.
///
/// The input the FEFO allocator and the manual batch picker both work from. It is
/// a *snapshot*: the allocator reads it while the form is open, and the ship path
/// reads it again inside the transaction — the second read is the authority
/// (G-D3).
class DeliveryBatchCandidate {
  const DeliveryBatchCandidate({
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    required this.availableQty,
    this.isArchived = false,
  });

  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;

  final Quantity availableQty;

  /// The batch row is soft deleted. It still holds real stock, so a document
  /// already allocated against it may ship; it is simply not offered for new
  /// allocations.
  final bool isArchived;

  bool isExpiredOn(DateTime referenceUtc) => DateOnly.isBeforeDate(
    expiryDate,
    AppTimeZone.operationalDate(referenceUtc),
  );

  int remainingDays(DateTime referenceUtc) => DateOnly.daysBetween(
    AppTimeZone.operationalDate(referenceUtc),
    expiryDate,
  );

  @override
  String toString() =>
      'DeliveryBatchCandidate($batchNo, ED ${DateOnly.formatIso(expiryDate)}, '
      '${availableQty.format()})';
}

/// One quantity taken from one batch — the unit the FEFO allocator produces and
/// the form edits.
///
/// `batchId` is null for an item without expiry, which is the only case in which
/// it may be (G-E2).
class DeliveryAllocation {
  const DeliveryAllocation({
    this.lineId,
    required this.prLineId,
    required this.itemId,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    required this.qty,
    this.fefoOverrideReason,
    this.nearExpiryConfirmed = false,
    this.nearExpiryNote,
  });

  /// Id of the `delivery_order_lines` row, when this allocation is already
  /// stored. `null` for one the FEFO allocator has just proposed — which is why
  /// the form addresses a saved allocation by id and a proposed one by position.
  final String? lineId;

  final String prLineId;
  final String itemId;
  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  final Quantity qty;
  final String? fefoOverrideReason;
  final bool nearExpiryConfirmed;
  final String? nearExpiryNote;

  bool get hasFefoOverride => (fefoOverrideReason ?? '').trim().isNotEmpty;

  DeliveryAllocation copyWith({
    Object? batchId = _unset,
    Object? batchNo = _unset,
    Object? expiryDate = _unset,
    Quantity? qty,
    Object? fefoOverrideReason = _unset,
    bool? nearExpiryConfirmed,
    Object? nearExpiryNote = _unset,
  }) {
    return DeliveryAllocation(
      lineId: lineId,
      prLineId: prLineId,
      itemId: itemId,
      batchId: batchId == _unset ? this.batchId : batchId as String?,
      batchNo: batchNo == _unset ? this.batchNo : batchNo as String?,
      expiryDate: expiryDate == _unset
          ? this.expiryDate
          : expiryDate as DateTime?,
      qty: qty ?? this.qty,
      fefoOverrideReason: fefoOverrideReason == _unset
          ? this.fefoOverrideReason
          : fefoOverrideReason as String?,
      nearExpiryConfirmed: nearExpiryConfirmed ?? this.nearExpiryConfirmed,
      nearExpiryNote: nearExpiryNote == _unset
          ? this.nearExpiryNote
          : nearExpiryNote as String?,
    );
  }

  /// Sentinel so `copyWith(batchId: null)` can mean "clear it" rather than "keep
  /// the current value".
  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeliveryAllocation &&
          other.prLineId == prLineId &&
          other.batchId == batchId &&
          other.qty == qty &&
          other.fefoOverrideReason == fefoOverrideReason &&
          other.nearExpiryConfirmed == nearExpiryConfirmed &&
          other.nearExpiryNote == nearExpiryNote);

  @override
  int get hashCode => Object.hash(
    prLineId,
    batchId,
    qty,
    fefoOverrideReason,
    nearExpiryConfirmed,
    nearExpiryNote,
  );

  @override
  String toString() =>
      'DeliveryAllocation($prLineId, ${batchNo ?? 'tanpa batch'}, '
      '${qty.format()})';
}

/// The allocations of one requested position, as the form holds them before they
/// are saved.
///
/// A draft is per **PR line** rather than per DO line because a single requested
/// position may split across batches, and the rules that matter — the remaining
/// quantity (G-D2) and the FEFO order (G-E3) — are evaluated over the whole
/// group rather than over one row of it.
class DeliveryLineDraft {
  const DeliveryLineDraft({
    required this.prLineId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.progress,
    required this.allocations,
    required this.availableQty,
    this.candidates = const <DeliveryBatchCandidate>[],
  });

  final String prLineId;
  final String itemId;
  final String sku;
  final String itemName;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;

  final ShipmentProgress progress;
  final List<DeliveryAllocation> allocations;

  /// Warehouse stock this position may ship from: the sum over usable batches for
  /// an expiry-tracked item, or the single non-batch balance for one without.
  ///
  /// Carried explicitly rather than derived from [candidates], because the two
  /// kinds of item answer the question from different rows and a derived getter
  /// would quietly report zero for every item without expiry.
  final Quantity availableQty;

  /// Batches the warehouse currently holds for this item, nearest expiry first.
  /// **Empty** for an item without expiry — there is no batch picker to draw
  /// (G-E2).
  final List<DeliveryBatchCandidate> candidates;

  Quantity get totalQty =>
      Quantity.sum(allocations.map((allocation) => allocation.qty));

  bool get isEmpty => allocations.isEmpty;

  DeliveryLineDraft copyWith({List<DeliveryAllocation>? allocations}) =>
      DeliveryLineDraft(
        prLineId: prLineId,
        itemId: itemId,
        sku: sku,
        itemName: itemName,
        unit: unit,
        hasExpiry: hasExpiry,
        expiryAlertDays: expiryAlertDays,
        progress: progress,
        allocations: allocations ?? this.allocations,
        availableQty: availableQty,
        candidates: candidates,
      );
}

/// Filter state for the delivery lists.
class DeliveryOrderFilter {
  const DeliveryOrderFilter({
    this.branchId,
    this.statuses = const <DeliveryOrderStatus>{},
    this.searchQuery = '',
  });

  /// `null` means every branch — the warehouse list.
  final String? branchId;

  final Set<DeliveryOrderStatus> statuses;

  final String searchQuery;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  DeliveryOrderFilter copyWith({
    Object? branchId = _unset,
    Set<DeliveryOrderStatus>? statuses,
    String? searchQuery,
  }) {
    return DeliveryOrderFilter(
      branchId: branchId == _unset ? this.branchId : branchId as String?,
      statuses: statuses ?? this.statuses,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeliveryOrderFilter &&
          other.branchId == branchId &&
          other.searchQuery == searchQuery &&
          _sameStatuses(other.statuses));

  bool _sameStatuses(Set<DeliveryOrderStatus> other) =>
      other.length == statuses.length && other.containsAll(statuses);

  @override
  int get hashCode =>
      Object.hash(branchId, searchQuery, Object.hashAllUnordered(statuses));
}

/// Everything the Surat Jalan prints, assembled once so the page is a pure
/// function of it.
///
/// The print instant is passed in rather than read from a clock, so the page is
/// deterministic in tests (T-7) and so the near-expiry markers are judged against
/// the same "now" the rest of the screen used.
class WaybillViewModel {
  const WaybillViewModel({
    required this.detail,
    required this.warehouseName,
    required this.printedAtUtc,
  });

  final DeliveryOrderDetail detail;

  /// Name of the central warehouse the goods left, or a fallback when the
  /// location cannot be resolved — the Surat Jalan must still print.
  final String warehouseName;

  /// UTC instant of printing; the page converts it to GMT+8 (T-2).
  final DateTime printedAtUtc;

  DeliveryOrderSummary get summary => detail.summary;

  List<DeliveryOrderLine> get lines => detail.lines;

  /// A `preparing` document is not a Surat Jalan yet, and the page says so.
  bool get isDraft => detail.order.isPreparing;

  String get title => isDraft ? 'DRAFT — BELUM DIKIRIM' : 'SURAT JALAN';

  int get lineCount => lines.length;

  bool get hasNearExpiryBatch => detail.hasNearExpiryBatch(printedAtUtc);

  bool get hasFefoOverride => detail.hasFefoOverride;
}
