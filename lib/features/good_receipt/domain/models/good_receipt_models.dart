import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../services/good_receipt_reminder_policy.dart';

/// Good Receipt header, in domain terms.
///
/// Immutable on purpose: a document is never mutated in place. Reads produce a
/// new instance and every write goes through a use case. Quantities are
/// [Quantity], event timestamps are UTC instants (T-1).
class GoodReceipt {
  const GoodReceipt({
    required this.id,
    required this.docNumber,
    required this.doId,
    required this.receivedBy,
    required this.status,
    this.postedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;

  /// `TMP-GR-{uuid}` until the sync backend assigns the final number (G-Y4).
  final String docNumber;

  final String doId;
  final String receivedBy;
  final GoodReceiptStatus status;

  /// UTC instant; convert through `AppDateTimeFormatter` before displaying.
  final DateTime? postedAt;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  bool get isChecking => status.isChecking;

  bool get isPosted => status.isPosted;

  /// Only a receipt still being checked may have its decisions revised.
  bool get isEditable => status.isEditable;

  bool get isFinal => status.isFinal;

  /// Whether the *status* still permits posting. Says nothing about the lines —
  /// [GoodReceiptDetail.canPost] asks both halves (G-G2).
  bool get canPost => status.canPost;

  /// Whether the local copy is still waiting to be synchronised (G-Y1).
  bool get isPendingSync => syncStatus == SyncStatus.pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoodReceipt &&
          other.id == id &&
          other.status == status &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(id, status, updatedAt);

  @override
  String toString() => 'GoodReceipt($docNumber, ${status.dbValue})';
}

/// The smallest fact set that decides whether somebody may open a receipt.
///
/// Deliberately tiny: an authorization check must not be the reason a document's
/// contents are loaded. Nothing here identifies an item, a batch, a quantity or a
/// reject reason — only the owning branch, the shipment, the request and the
/// status.
class GoodReceiptAccessScope {
  const GoodReceiptAccessScope({
    required this.grId,
    required this.doId,
    required this.prId,
    required this.branchId,
    required this.status,
  });

  final String grId;
  final String doId;
  final String prId;
  final String branchId;
  final GoodReceiptStatus status;
}

/// One checked position of a Good Receipt, enriched with everything the checklist
/// and the posted detail need.
class GoodReceiptLine {
  const GoodReceiptLine({
    required this.id,
    required this.grId,
    required this.doLineId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.shippedQty,
    required this.receivedQty,
    required this.lineStatus,
    this.rejectReason,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String id;
  final String grId;

  /// The shipped allocation this decision answers. Immutable — the snapshot is
  /// what `received_qty` is bounded against (G-G3).
  final String doLineId;

  final String itemId;

  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;

  /// What the warehouse sent, snapshotted when the receipt was created.
  final Quantity shippedQty;

  /// What the branch accepted. `0 ≤ receivedQty ≤ shippedQty` (G-G3).
  final Quantity receivedQty;

  final GoodReceiptLineStatus lineStatus;

  /// Why the position was refused (G-G4). Non-null exactly when [isRejected].
  final String? rejectReason;

  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  /// The item or batch was deactivated or archived after the shipment was sent.
  /// The line stays visible and stays postable — the badge only explains why the
  /// row no longer appears in the pickers.
  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get isPending => lineStatus.isPending;

  bool get isChecked => lineStatus.isChecked;

  bool get isRejected => lineStatus.isRejected;

  bool get isDecided => lineStatus.isDecided;

  bool get requiresRejectReason => lineStatus.requiresRejectReason;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  /// What did not arrive. Zero on a complete line, the full shipped quantity on a
  /// rejected one (G-G3).
  ///
  /// Derived rather than stored, so there is exactly one version of the fact and
  /// no writer that can contradict it. Exact fixed-point arithmetic (Q-2): a
  /// shipment of `2.375` received as `1.5` is short by exactly `0.875`.
  Quantity get discrepancyQty => shippedQty - receivedQty;

  /// An accepted position that arrived short — the *shortage* half of the
  /// warehouse's selisih report.
  bool get hasShortage => isChecked && discrepancyQty.isPositive;

  /// Whether this line will move stock when the receipt is posted (G-G5). A
  /// `checked` line of zero moves nothing: there is nothing to record.
  bool get addsStock => lineStatus.addsStock && receivedQty.isPositive;

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

  /// Whether the batch's shelf life is below the item's alert threshold (G-E5).
  ///
  /// Already-expired batches answer `false` here: they are a different, stricter
  /// case and [isExpiredOn] is what reports them. Keeping the two apart is what
  /// lets a badge say *kedaluwarsa* rather than *terlalu dekat ED*.
  bool isNearExpiryOn(DateTime referenceUtc) {
    if (isExpiredOn(referenceUtc)) return false;
    final days = remainingDays(referenceUtc);
    return days != null && days < expiryAlertDays;
  }

  /// G-E5 — whether this position may not be accepted at all.
  bool mustBeRejectedOn(DateTime referenceUtc) =>
      isExpiredOn(referenceUtc) || isNearExpiryOn(referenceUtc);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoodReceiptLine &&
          other.id == id &&
          other.lineStatus == lineStatus &&
          other.receivedQty == receivedQty &&
          other.rejectReason == rejectReason);

  @override
  int get hashCode => Object.hash(id, lineStatus, receivedQty, rejectReason);

  @override
  String toString() =>
      'GoodReceiptLine($sku, ${lineStatus.dbValue}, '
      '${receivedQty.format()}/${shippedQty.format()})';
}

/// How far the checklist has got (G-G2), and what it has decided.
///
/// A value object rather than four loose counters, because *"8/12 diperiksa"* and
/// *"posting is allowed"* are the same question asked twice and answering them in
/// two places is how they come to disagree.
class GoodReceiptProgress {
  const GoodReceiptProgress({
    required this.total,
    required this.pending,
    required this.checked,
    required this.rejected,
    required this.shortage,
  });

  /// Derives the progress from a list of decisions.
  factory GoodReceiptProgress.of(Iterable<GoodReceiptLine> lines) {
    var total = 0;
    var pending = 0;
    var checked = 0;
    var rejected = 0;
    var shortage = 0;
    for (final line in lines) {
      total += 1;
      if (line.isPending) pending += 1;
      if (line.isChecked) checked += 1;
      if (line.isRejected) rejected += 1;
      if (line.hasShortage) shortage += 1;
    }
    return GoodReceiptProgress(
      total: total,
      pending: pending,
      checked: checked,
      rejected: rejected,
      shortage: shortage,
    );
  }

  final int total;
  final int pending;
  final int checked;
  final int rejected;

  /// `checked` positions that accepted less than was shipped.
  final int shortage;

  int get decided => total - pending;

  /// G-G2. An empty receipt answers `false`: there is nothing to have decided,
  /// and treating "no lines" as "all decided" would let a corrupt document post.
  bool get allDecided => total > 0 && pending == 0;

  /// `8/12` — the label spec §4.2 asks for.
  String get label => '$decided/$total';

  /// `0 … 1000`, for a progress bar.
  ///
  /// Integer arithmetic — `~/`, not `/` — for the reason [Quantity] offers no `double`
  /// conversion at all: the moment a ratio becomes a `double` somewhere in the middle,
  /// somebody eventually compares two of them. The widget divides by 1000 at the last
  /// moment, which is the only place a fraction appears.
  int get permille => total == 0 ? 0 : decided * 1000 ~/ total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoodReceiptProgress &&
          other.total == total &&
          other.pending == pending &&
          other.checked == checked &&
          other.rejected == rejected &&
          other.shortage == shortage);

  @override
  int get hashCode => Object.hash(total, pending, checked, rejected, shortage);

  @override
  String toString() =>
      'GoodReceiptProgress($label, checked $checked, rejected $rejected)';
}

/// A header plus the names a list row needs, without a second query.
///
/// The `…IsHistorical` flags exist so a screen can *say* that a receipt rests on
/// master data that has since been deactivated or archived. They are never a
/// reason to hide the row: a shipment whose branch was retired afterwards is
/// exactly the receipt that still has to be posted.
class GoodReceiptSummary {
  const GoodReceiptSummary({
    required this.receipt,
    required this.doDocNumber,
    required this.doStatus,
    this.doShippedAt,
    this.shippedByName,
    required this.prDocNumber,
    required this.prStatus,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    this.branchAddress,
    required this.receivedByName,
    required this.progress,
    this.branchIsHistorical = false,
    this.receivedByIsHistorical = false,
  });

  final GoodReceipt receipt;

  final String doDocNumber;
  final DeliveryOrderStatus doStatus;

  /// UTC instant the goods left the warehouse — the anchor of the 2×24 hour
  /// deadline (G-G6).
  final DateTime? doShippedAt;
  final String? shippedByName;

  final String prDocNumber;
  final PurchaseRequestStatus prStatus;

  final String branchId;
  final String branchCode;
  final String branchName;
  final String? branchAddress;
  final String receivedByName;

  final GoodReceiptProgress progress;

  final bool branchIsHistorical;
  final bool receivedByIsHistorical;

  String get id => receipt.id;

  String get docNumber => receipt.docNumber;

  GoodReceiptStatus get status => receipt.status;

  bool get usesHistoricalMaster => branchIsHistorical || receivedByIsHistorical;

  /// The 2×24 hour deadline (G-G6), or `null` when the shipment carries no
  /// `shipped_at` — which cannot happen for a `shipped`/`received` document,
  /// because the table's CHECK requires it.
  DateTime? get deadlineUtc {
    final shipped = doShippedAt;
    return shipped == null
        ? null
        : GoodReceiptReminderPolicy.deadlineFor(shipped);
  }

  /// Whether the receipt is past its deadline **and** still unposted (G-G6). A
  /// posted receipt is never overdue — the work is done.
  bool isOverdueOn(DateTime nowUtc) {
    if (receipt.isPosted) return false;
    final shipped = doShippedAt;
    if (shipped == null) return false;
    return GoodReceiptReminderPolicy.isOverdue(
      shippedAtUtc: shipped,
      nowUtc: nowUtc,
    );
  }
}

/// Everything the checklist and the posted detail need about one receipt.
class GoodReceiptDetail {
  const GoodReceiptDetail({required this.summary, required this.lines});

  final GoodReceiptSummary summary;
  final List<GoodReceiptLine> lines;

  GoodReceipt get receipt => summary.receipt;

  String get id => receipt.id;

  GoodReceiptStatus get status => receipt.status;

  bool get isChecking => receipt.isChecking;

  bool get isPosted => receipt.isPosted;

  bool get isEditable => receipt.isEditable;

  bool get isFinal => receipt.isFinal;

  bool get isEmpty => lines.isEmpty;

  GoodReceiptProgress get progress => GoodReceiptProgress.of(lines);

  int get pendingCount => progress.pending;

  int get checkedCount => progress.checked;

  int get rejectedCount => progress.rejected;

  bool get allLinesDecided => progress.allDecided;

  /// Both halves of G-G2: the receipt is `checking` **and** every position has
  /// been decided. The use case remains the authority; this is what the button
  /// asks.
  bool get canPost => receipt.canPost && allLinesDecided;

  bool get hasRejectedLines => lines.any((line) => line.isRejected);

  bool get hasDiscrepancy =>
      lines.any((line) => line.discrepancyQty.isPositive);

  /// Positions that will not fully enter the branch store — the rows that reach
  /// the warehouse's selisih/retur queue once this receipt is posted.
  List<GoodReceiptLine> get discrepancyLines => lines
      .where((line) => line.isRejected || line.hasShortage)
      .toList(growable: false);

  List<String> get pendingLineIds => lines
      .where((line) => line.isPending)
      .map((line) => line.id)
      .toList(growable: false);

  bool get usesHistoricalMaster =>
      summary.usesHistoricalMaster ||
      lines.any((line) => line.usesHistoricalMaster);

  /// Shipped, received and short totals grouped by unit.
  ///
  /// Quantities of different units are never added together: `2 box` and `3 pcs`
  /// are not `5` of anything, and one headline number would mislead.
  Map<String, Quantity> get shippedByUnit => _totals((line) => line.shippedQty);

  Map<String, Quantity> get receivedByUnit =>
      _totals((line) => line.receivedQty);

  Map<String, Quantity> get discrepancyByUnit =>
      _totals((line) => line.discrepancyQty);

  Map<String, Quantity> _totals(Quantity Function(GoodReceiptLine) pick) {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.unit] = (totals[line.unit] ?? Quantity.zero()) + pick(line);
    }
    return totals;
  }
}

/// One shipped Delivery Order the branch has not finished checking in.
///
/// Carries the shipment rather than a receipt, because the two rows a branch head
/// acts on are *"nothing started"* and *"started, not finished"* — and only the
/// second has a receipt to name.
class GoodReceiptAwaitingDelivery {
  const GoodReceiptAwaitingDelivery({
    required this.doId,
    required this.doDocNumber,
    required this.prId,
    required this.prDocNumber,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    this.shippedByName,
    required this.shippedAtUtc,
    required this.lineCount,
    required this.decidedCount,
    this.receiptId,
    this.receiptDocNumber,
    this.receiptStatus,
    this.branchIsHistorical = false,
  });

  final String doId;
  final String doDocNumber;
  final String prId;
  final String prDocNumber;
  final String branchId;
  final String branchCode;
  final String branchName;
  final String? shippedByName;

  /// UTC instant the goods left the warehouse.
  final DateTime shippedAtUtc;

  /// Allocations on the shipment — what a receipt snapshots.
  final int lineCount;

  /// Receipt lines already decided, `0` when checking has not started.
  final int decidedCount;

  final String? receiptId;
  final String? receiptDocNumber;
  final GoodReceiptStatus? receiptStatus;

  final bool branchIsHistorical;

  /// Whether the branch head has already started the checklist.
  bool get hasReceipt => receiptId != null;

  /// How many positions are still waiting for a decision, or the whole shipment when the
  /// checklist has not been opened yet.
  ///
  /// Deliberately *not* a [GoodReceiptProgress]: this row knows how many lines were
  /// decided but not how they were decided, and filling `checked` with that number would
  /// be a progress object that reports refusals as acceptances. A screen that needs the
  /// split reads the receipt.
  int get pendingCount => hasReceipt ? lineCount - decidedCount : lineCount;

  DateTime get deadlineUtc =>
      GoodReceiptReminderPolicy.deadlineFor(shippedAtUtc);

  bool isOverdueOn(DateTime nowUtc) => GoodReceiptReminderPolicy.isOverdue(
    shippedAtUtc: shippedAtUtc,
    nowUtc: nowUtc,
  );
}

/// One position of one posted receipt that did not arrive complete — the row the
/// warehouse's selisih/retur queue renders (G-G3/G-G5).
///
/// A derived read rather than a table: the facts are `shipped_qty`,
/// `received_qty`, `line_status` and `reject_reason`, all of which already exist
/// on the receipt line. A `discrepancies` table would be a second copy of them
/// that could disagree, and it would need a writer — which is exactly the phantom
/// stock this milestone must not create.
class GoodReceiptDiscrepancy {
  const GoodReceiptDiscrepancy({
    required this.lineId,
    required this.grId,
    required this.grDocNumber,
    required this.doId,
    required this.doDocNumber,
    required this.prId,
    required this.prDocNumber,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.unit,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    required this.shippedQty,
    required this.receivedQty,
    required this.lineStatus,
    this.rejectReason,
    required this.postedAtUtc,
    this.itemIsHistorical = false,
    this.branchIsHistorical = false,
  });

  final String lineId;
  final String grId;
  final String grDocNumber;
  final String doId;
  final String doDocNumber;
  final String prId;
  final String prDocNumber;
  final String branchId;
  final String branchCode;
  final String branchName;

  final String itemId;
  final String sku;
  final String itemName;
  final String unit;
  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  final Quantity shippedQty;
  final Quantity receivedQty;
  final GoodReceiptLineStatus lineStatus;
  final String? rejectReason;

  /// UTC instant the receipt was posted.
  final DateTime postedAtUtc;

  final bool itemIsHistorical;
  final bool branchIsHistorical;

  Quantity get discrepancyQty => shippedQty - receivedQty;

  GoodReceiptDiscrepancyKind get kind => lineStatus.isRejected
      ? GoodReceiptDiscrepancyKind.rejectedReturn
      : GoodReceiptDiscrepancyKind.shortage;

  /// Whether the goods are physically at the branch waiting to go back.
  ///
  /// A shortage never arrived, so there is nothing to return — the quantity was
  /// short in transit and the warehouse investigates it. A rejected position did
  /// arrive and was refused, so it *is* on the branch's counter (G-G5).
  bool get returnRequired => kind == GoodReceiptDiscrepancyKind.rejectedReturn;

  bool get usesHistoricalMaster => itemIsHistorical || branchIsHistorical;
}

/// The two shapes a discrepancy takes (§17).
enum GoodReceiptDiscrepancyKind {
  /// `checked` and `received_qty < shipped_qty` — goods that never arrived.
  shortage,

  /// `rejected` — goods that arrived and were refused, and therefore have to go
  /// back to the warehouse.
  rejectedReturn;

  String get label => switch (this) {
    shortage => 'Kekurangan',
    rejectedReturn => 'Perlu Retur',
  };
}

/// A refused position, as the warehouse's return list reads it.
///
/// Deliberately a *view* of [GoodReceiptDiscrepancy] rather than a second query:
/// the return list is the `rejectedReturn` subset of the same rows, and deriving it
/// keeps the two lists incapable of disagreeing. Nothing here is a workflow step —
/// there is no "mark returned", no movement and no balance change. The physical
/// return is a later milestone's document.
class GoodReceiptReturnCandidate {
  /// Prefer [fromDiscrepancies], which is what selects the refused subset. The
  /// direct constructor exists so a test can build one row without a query.
  const GoodReceiptReturnCandidate(this.discrepancy);

  /// Every refused position among [discrepancies], in the order given.
  static List<GoodReceiptReturnCandidate> fromDiscrepancies(
    Iterable<GoodReceiptDiscrepancy> discrepancies,
  ) => discrepancies
      .where((entry) => entry.returnRequired)
      .map(GoodReceiptReturnCandidate.new)
      .toList(growable: false);

  final GoodReceiptDiscrepancy discrepancy;

  String get lineId => discrepancy.lineId;

  String get grDocNumber => discrepancy.grDocNumber;

  String get doDocNumber => discrepancy.doDocNumber;

  String get branchName => discrepancy.branchName;

  String get sku => discrepancy.sku;

  String get itemName => discrepancy.itemName;

  String? get batchNo => discrepancy.batchNo;

  /// What has to travel back — the whole shipped quantity, because a refused
  /// position accepted nothing.
  Quantity get returnQty => discrepancy.shippedQty;

  String get reason => discrepancy.rejectReason ?? '';

  DateTime get postedAtUtc => discrepancy.postedAtUtc;
}

/// Filter state for the Good Receipt lists and the warehouse discrepancy queue.
class GoodReceiptFilter {
  const GoodReceiptFilter({
    this.branchId,
    this.statuses = const <GoodReceiptStatus>{},
    this.searchQuery = '',
    this.discrepancyKind,
    this.postedFromUtc,
    this.postedToUtc,
  });

  /// `null` means every branch — the warehouse queue.
  final String? branchId;

  final Set<GoodReceiptStatus> statuses;

  final String searchQuery;

  /// `null` shows both shortages and returns.
  final GoodReceiptDiscrepancyKind? discrepancyKind;

  /// Inclusive UTC bounds on `posted_at`.
  final DateTime? postedFromUtc;
  final DateTime? postedToUtc;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  /// `true` for returns only, `false` for shortages only, `null` for both — the
  /// shape the query wants.
  bool? get rejectedOnly => switch (discrepancyKind) {
    null => null,
    GoodReceiptDiscrepancyKind.rejectedReturn => true,
    GoodReceiptDiscrepancyKind.shortage => false,
  };

  GoodReceiptFilter copyWith({
    Object? branchId = _unset,
    Set<GoodReceiptStatus>? statuses,
    String? searchQuery,
    Object? discrepancyKind = _unset,
    Object? postedFromUtc = _unset,
    Object? postedToUtc = _unset,
  }) {
    return GoodReceiptFilter(
      branchId: branchId == _unset ? this.branchId : branchId as String?,
      statuses: statuses ?? this.statuses,
      searchQuery: searchQuery ?? this.searchQuery,
      discrepancyKind: discrepancyKind == _unset
          ? this.discrepancyKind
          : discrepancyKind as GoodReceiptDiscrepancyKind?,
      postedFromUtc: postedFromUtc == _unset
          ? this.postedFromUtc
          : postedFromUtc as DateTime?,
      postedToUtc: postedToUtc == _unset
          ? this.postedToUtc
          : postedToUtc as DateTime?,
    );
  }

  /// Sentinel so `copyWith(branchId: null)` can mean "clear it" rather than "keep
  /// the current value".
  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoodReceiptFilter &&
          other.branchId == branchId &&
          other.searchQuery == searchQuery &&
          other.discrepancyKind == discrepancyKind &&
          other.postedFromUtc == postedFromUtc &&
          other.postedToUtc == postedToUtc &&
          other.statuses.length == statuses.length &&
          other.statuses.containsAll(statuses));

  @override
  int get hashCode => Object.hash(
    branchId,
    searchQuery,
    discrepancyKind,
    postedFromUtc,
    postedToUtc,
    Object.hashAllUnordered(statuses),
  );
}

/// One shipment that is approaching, at, or past its 2×24 hour deadline (G-G6).
///
/// The stage is resolved once, against an injected clock, and stored: a widget
/// that recomputed it from `DateTime.now()` would drift away from the count on the
/// dashboard beside it.
class GoodReceiptReminder {
  const GoodReceiptReminder({
    required this.doId,
    required this.doDocNumber,
    required this.prDocNumber,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.shippedAtUtc,
    required this.deadlineUtc,
    required this.stage,
    required this.hoursLate,
    required this.lineCount,
    required this.decidedCount,
    this.receiptId,
    this.receiptStatus,
  });

  final String doId;
  final String doDocNumber;
  final String prDocNumber;
  final String branchId;
  final String branchCode;
  final String branchName;

  /// UTC instant the goods left the warehouse — the deadline's anchor.
  final DateTime shippedAtUtc;

  /// `shippedAtUtc + 48 h`.
  final DateTime deadlineUtc;

  final GoodReceiptReminderStage stage;

  /// Whole hours past the deadline; `0` when it has not passed.
  final int hoursLate;

  final int lineCount;
  final int decidedCount;

  final String? receiptId;
  final GoodReceiptStatus? receiptStatus;

  bool get isOverdue => stage == GoodReceiptReminderStage.overdue;

  bool get isDueSoon => stage == GoodReceiptReminderStage.dueSoon;

  /// Whether the branch head has started the checklist.
  bool get hasReceipt => receiptId != null;

  int get pendingCount => hasReceipt ? lineCount - decidedCount : lineCount;
}
