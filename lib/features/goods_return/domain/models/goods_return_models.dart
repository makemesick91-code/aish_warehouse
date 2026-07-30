import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';

/// A Retur Barang header, in domain terms (§13).
///
/// Immutable, like every other document model in this application: a transition
/// produces a new value read back from the database rather than mutating this one.
/// Nothing here is a drift row — the repository maps them, so no screen and no policy
/// ever sees a generated class.
class GoodsReturn {
  const GoodsReturn({
    required this.id,
    required this.docNumber,
    required this.grId,
    required this.branchId,
    required this.createdBy,
    required this.status,
    this.note,
    this.shippedAt,
    this.shippedBy,
    this.receivedAt,
    this.receivedBy,
    this.warehouseNote,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;

  /// `TMP-RET-{uuid}` until the sync backend assigns the real one (G-Y4).
  final String docNumber;

  /// The Good Receipt whose rejections this document returns. Immutable.
  final String grId;

  /// The branch sending the goods back. Immutable, and the column every scoped read
  /// predicates on.
  final String branchId;

  /// The Kepala Cabang who raised the document (G-A3). Immutable.
  final String createdBy;

  final GoodsReturnStatus status;

  /// The branch's optional remark. The only field a draft may change (§19).
  final String? note;

  /// When the goods physically left the branch. Null exactly while `draft`.
  final DateTime? shippedAt;

  /// Who handed them over — a Kepala Cabang of [branchId].
  final String? shippedBy;

  /// When the Warehouse confirmed arrival and the ledger was posted.
  final DateTime? receivedAt;

  /// The Petugas Warehouse who confirmed. Never [createdBy] and never [shippedBy]
  /// (G-R4).
  final String? receivedBy;

  /// The Warehouse's optional remark, written only by the receive transaction.
  final String? warehouseNote;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  bool get isDraft => status.isDraft;

  bool get isShipped => status.isShipped;

  bool get isReceived => status.isReceived;

  /// Whether the header note may still be changed (§19). Says nothing about the
  /// lines — those are immutable in every status, including this one.
  bool get isEditable => status.isEditable;

  bool get isFinal => status.isFinal;

  /// Whether the state machine still permits the ship transition. Says nothing about
  /// *who* is asking or whether the snapshot is intact — `GoodsReturnDetail.canShip`
  /// asks all three.
  bool get canShip => status.canShip;

  /// Whether the state machine still permits the receive transition.
  bool get canReceive => status.canReceive;

  bool get hasNote => (note ?? '').trim().isNotEmpty;

  bool get hasWarehouseNote => (warehouseNote ?? '').trim().isNotEmpty;

  /// Whether this document belongs to [branchId] — the branch scope, asked as a
  /// question rather than re-spelled at every call site.
  bool belongsToBranch(String branchId) => this.branchId == branchId;

  bool get isPendingSync => syncStatus == SyncStatus.pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoodsReturn &&
          other.id == id &&
          other.status == status &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, status, updatedAt);

  @override
  String toString() => 'GoodsReturn($docNumber, ${status.dbValue})';
}

/// The facts an authorization check needs, and nothing else (§27).
///
/// Deliberately not the detail: deciding whether a return may be shown must not be the
/// reason its number, its items, its quantities or its reject reasons are read.
class GoodsReturnAccessScope {
  const GoodsReturnAccessScope({
    required this.goodsReturnId,
    required this.grId,
    required this.branchId,
    required this.createdBy,
    this.shippedBy,
    this.receivedBy,
    required this.status,
  });

  final String goodsReturnId;
  final String grId;
  final String branchId;
  final String createdBy;
  final String? shippedBy;
  final String? receivedBy;
  final GoodsReturnStatus status;
}

/// One returned position, joined with the master data a screen needs (§13).
///
/// Every field except the expiry metadata is a **snapshot** taken at creation and
/// immutable thereafter (§18). The item name, SKU and unit are read back live so a
/// renamed product reads correctly; the *identity* of the item, its batch, the
/// quantity and the reason are not.
class GoodsReturnLine {
  const GoodsReturnLine({
    required this.id,
    required this.goodsReturnId,
    required this.grLineId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    required this.qty,
    required this.rejectReason,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String id;
  final String goodsReturnId;

  /// The rejected Good Receipt position this line answers. The join key every
  /// integrity check compares on (§26).
  final String grLineId;

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  /// Whether the item is batch-tracked (G-E2). [isBatchConsistent] is what checks the
  /// snapshot against it.
  final bool hasExpiry;

  /// Days before expiry at which the item counts as *near* expiry (G-E6).
  final int expiryAlertDays;

  final String? batchId;
  final String? batchNo;

  /// The batch's civil expiry date, read back live. Never timezone-converted (T-9).
  final DateTime? expiryDate;

  /// The returned quantity — always the source line's `shipped_qty` (§18).
  final Quantity qty;

  /// The reason the branch head gave when refusing this position (G-G4), snapshotted.
  /// Never blank: the database CHECK and the create use case both refuse one.
  final String rejectReason;

  /// The item or batch has been withdrawn since the return was raised. The screens
  /// badge these rather than hiding the line (§37).
  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  bool get isBatched => batchId != null;

  /// G-E2, both directions: a batch-tracked item must carry a batch and an item
  /// without expiry must not.
  bool get isBatchConsistent => hasExpiry == isBatched;

  /// Whether the batch is already past its expiry date, as of [nowUtc].
  ///
  /// **A true answer is not a refusal on this document.** G-E5 makes an expired or
  /// near-expiry batch a legitimate reason to reject a delivery, and a rejection has to
  /// be able to go home (§36). This drives a red badge and nothing else.
  bool isExpired(DateTime nowUtc) {
    final date = expiryDate;
    if (date == null) return false;
    return DateOnly.isBeforeDate(date, AppTimeZone.operationalDate(nowUtc));
  }

  /// Whether the batch is within [expiryAlertDays] of expiring, as of [nowUtc]. An
  /// already-expired batch answers `false` — it is past *near*, and [isExpired] is the
  /// badge it gets.
  bool isNearExpiry(DateTime nowUtc) {
    final date = expiryDate;
    if (date == null) return false;
    final today = AppTimeZone.operationalDate(nowUtc);
    if (DateOnly.isBeforeDate(date, today)) return false;
    return DateOnly.daysBetween(today, date) <= expiryAlertDays;
  }

  /// `itemId|batchId` — the key duplicate detection and grouping use.
  String get positionKey => '$itemId|${batchId ?? ''}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoodsReturnLine && other.id == id && other.qty == qty;

  @override
  int get hashCode => Object.hash(id, qty);

  @override
  String toString() => 'GoodsReturnLine($sku, ${qty.format()} $unit)';
}

/// One return line stripped to its identifiers — no join, no master data (§26).
///
/// The honest inventory the integrity checks work from. A joined read can hide a row
/// whose item or batch is physically gone; this cannot.
class GoodsReturnLineReference {
  const GoodsReturnLineReference({
    required this.id,
    required this.goodsReturnId,
    required this.grLineId,
    required this.itemId,
    this.batchId,
    required this.qty,
    required this.rejectReason,
  });

  final String id;
  final String goodsReturnId;
  final String grLineId;
  final String itemId;
  final String? batchId;
  final Quantity qty;
  final String rejectReason;

  bool get isBatched => batchId != null;

  String get positionKey => '$itemId|${batchId ?? ''}';
}

/// One rejected Good Receipt position, as the eligibility reader returns it (§16).
///
/// The *source* the snapshot is cut from, and the value every integrity check compares
/// a stored line against. It carries `shippedQty` and `receivedQty` rather than a
/// single "returnable quantity" so the checks can state both halves of what makes a
/// position returnable: everything that was sent came back, and nothing was accepted.
class RejectedGoodReceiptPosition {
  const RejectedGoodReceiptPosition({
    required this.grLineId,
    required this.grId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    required this.shippedQty,
    required this.receivedQty,
    required this.rejectReason,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String grLineId;
  final String grId;

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;

  final String? batchId;
  final String? batchNo;
  final DateTime? expiryDate;

  /// What the warehouse shipped. **This is the return quantity** — a rejected line
  /// accepted nothing, so everything that was sent is coming back (§18).
  final Quantity shippedQty;

  /// What the branch accepted. Always zero on a rejected line — the Good Receipt's own
  /// CHECK guarantees it, and the create use case verifies it rather than assuming it.
  final Quantity receivedQty;

  /// G-G4's mandatory reason.
  final String rejectReason;

  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  bool get isBatched => batchId != null;

  bool get isBatchConsistent => hasExpiry == isBatched;

  /// The quantity a return line for this position must carry. Named rather than left
  /// as `shippedQty` at every call site, because *why* it is the shipped quantity is
  /// the rule (§18).
  Quantity get returnQty => shippedQty;

  bool isExpired(DateTime nowUtc) {
    final date = expiryDate;
    if (date == null) return false;
    return DateOnly.isBeforeDate(date, AppTimeZone.operationalDate(nowUtc));
  }

  bool isNearExpiry(DateTime nowUtc) {
    final date = expiryDate;
    if (date == null) return false;
    final today = AppTimeZone.operationalDate(nowUtc);
    if (DateOnly.isBeforeDate(date, today)) return false;
    return DateOnly.daysBetween(today, date) <= expiryAlertDays;
  }

  String get positionKey => '$itemId|${batchId ?? ''}';
}

/// One posted Good Receipt with rejections, as the *Perlu Dibuat* queue shows it
/// (§16/§29).
class GoodsReturnEligibility {
  const GoodsReturnEligibility({
    required this.grId,
    required this.grDocNumber,
    required this.grPostedAt,
    required this.doId,
    required this.doDocNumber,
    required this.prId,
    required this.prDocNumber,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.rejectedLineCount,
    required this.rejectedQty,
    required this.positions,
    this.existingReturnId,
    this.existingReturnDocNumber,
    this.existingReturnStatus,
  });

  final String grId;
  final String grDocNumber;

  /// When the receipt was posted. Nullable in the schema but never null on a `posted`
  /// receipt — the Good Receipt's own CHECK pairs them — so the queue sorts on it
  /// safely, in Dart, on UTC instants (§16).
  final DateTime? grPostedAt;

  final String doId;
  final String doDocNumber;
  final String prId;
  final String prDocNumber;

  final String branchId;
  final String branchCode;
  final String branchName;

  final int rejectedLineCount;

  /// The total across every rejected position, for the one-line summary. The screens
  /// show totals **per unit**, derived from [positions] — this is the cheap
  /// cross-check they must add back up to.
  final Quantity rejectedQty;

  /// Every rejected position of the receipt, in full. Carried rather than counted so
  /// the queue can show reject reasons and expiry badges without a second round trip
  /// (§29).
  final List<RejectedGoodReceiptPosition> positions;

  /// The return already raised for this receipt, or `null` while it still owes one.
  final String? existingReturnId;
  final String? existingReturnDocNumber;
  final GoodsReturnStatus? existingReturnStatus;

  /// Whether a Kepala Cabang may still raise a return from this receipt.
  ///
  /// Both halves of *one Good Receipt, one Retur*: there must be something to return,
  /// and nothing may have returned it already. The use case re-asks this inside the
  /// create transaction — this is what the button reads, not what the write trusts
  /// (§16/§17).
  bool get canCreateReturn =>
      existingReturnId == null && rejectedLineCount > 0 && positions.isNotEmpty;

  bool get hasReturn => existingReturnId != null;

  /// Totals per unit — what §29 asks the queue to show. A single grand total across
  /// units would add boxes to ampoules.
  Map<String, Quantity> get totalQuantityByUnit {
    final totals = <String, Quantity>{};
    for (final position in positions) {
      totals[position.unit] =
          (totals[position.unit] ?? Quantity.zero()) + position.returnQty;
    }
    return totals;
  }

  /// The distinct reasons the branch head gave, in first-seen order — the summary line
  /// the queue shows instead of repeating one reason per position.
  List<String> get rejectReasons {
    final seen = <String>{};
    final reasons = <String>[];
    for (final position in positions) {
      final reason = position.rejectReason.trim();
      if (reason.isEmpty || !seen.add(reason)) continue;
      reasons.add(reason);
    }
    return reasons;
  }

  int expiredCount(DateTime nowUtc) =>
      positions.where((position) => position.isExpired(nowUtc)).length;

  int nearExpiryCount(DateTime nowUtc) =>
      positions.where((position) => position.isNearExpiry(nowUtc)).length;
}

/// The per-document aggregate a list row and a detail header show (§13).
class GoodsReturnProgress {
  const GoodsReturnProgress({
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
    required this.totalQty,
    required this.totalQuantityByUnit,
    required this.expiredCount,
    required this.nearExpiryCount,
    this.nearestExpiryDate,
  });

  /// The empty aggregate — a document whose lines could not be read at all. It is a
  /// value rather than a null so a screen renders *"0 posisi"* instead of crashing,
  /// and the guards refuse to ship or receive it (§26).
  const GoodsReturnProgress.empty()
    : lineCount = 0,
      itemCount = 0,
      batchCount = 0,
      totalQty = const Quantity.fromMilliUnits(0),
      totalQuantityByUnit = const {},
      expiredCount = 0,
      nearExpiryCount = 0,
      nearestExpiryDate = null;

  final int lineCount;
  final int itemCount;

  /// Distinct batches. An item without expiry contributes none, so this can be lower
  /// than [lineCount] on a compliant document.
  final int batchCount;

  final Quantity totalQty;

  /// Totals per unit — what the screens actually show (§29/§31).
  final Map<String, Quantity> totalQuantityByUnit;

  /// How many positions are already past their expiry date. **Not a problem on this
  /// document** — G-E5 makes an expired batch a legitimate rejection, and §36 lets it
  /// come home. It is a red badge and a line in the receive confirmation, so the
  /// Warehouse knows what is arriving and can plan the Pemusnahan that follows.
  final int expiredCount;

  final int nearExpiryCount;

  /// The soonest expiry date on the document, for the badge subtitle.
  final DateTime? nearestExpiryDate;

  bool get isEmpty => lineCount == 0;

  bool get hasExpired => expiredCount > 0;

  bool get hasNearExpiry => nearExpiryCount > 0;

  String get label => '$lineCount posisi · $itemCount barang';

  /// The sentence the two workflow screens show under the status chip (§13).
  ///
  /// Written from the *reader's* point of view rather than the document's: a branch
  /// head wants to know what they still owe, and a Warehouse user what is coming.
  static String progressLabelOf(GoodsReturnStatus status) => switch (status) {
    GoodsReturnStatus.draft => 'Menunggu pengiriman cabang',
    GoodsReturnStatus.shipped => 'Menunggu penerimaan Warehouse',
    GoodsReturnStatus.received => 'Selesai',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoodsReturnProgress &&
          other.lineCount == lineCount &&
          other.itemCount == itemCount &&
          other.batchCount == batchCount &&
          other.totalQty == totalQty &&
          other.expiredCount == expiredCount &&
          other.nearExpiryCount == nearExpiryCount;

  @override
  int get hashCode => Object.hash(
    lineCount,
    itemCount,
    batchCount,
    totalQty,
    expiredCount,
    nearExpiryCount,
  );
}

/// One row of a Retur list — the header plus the chain and the counts (§29/§31).
class GoodsReturnSummary {
  const GoodsReturnSummary({
    required this.goodsReturn,
    required this.grDocNumber,
    required this.doDocNumber,
    required this.prDocNumber,
    required this.branchCode,
    required this.branchName,
    required this.createdByName,
    this.shippedByName,
    this.receivedByName,
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
    required this.totalQty,
    this.totalsByUnit = const {},
    this.branchIsHistorical = false,
  });

  final GoodsReturn goodsReturn;

  /// The whole document chain, so a list row can be searched and read without a second
  /// query (§29).
  final String grDocNumber;
  final String doDocNumber;
  final String prDocNumber;

  final String branchCode;
  final String branchName;

  final String createdByName;
  final String? shippedByName;
  final String? receivedByName;

  final int lineCount;
  final int itemCount;
  final int batchCount;

  /// The sum across **every** unit. Useful as a cross-check and as an ordering key; it
  /// is deliberately *not* what a screen shows, because adding boxes to ampoules
  /// produces a number that means nothing (§29/§31).
  final Quantity totalQty;

  /// Totals per unit — what the list rows actually show. Empty only on a document whose
  /// lines could not be read at all, which the guards refuse to ship or receive.
  final Map<String, Quantity> totalsByUnit;

  /// The branch has been deactivated since. The row is still shown, badged (§37).
  final bool branchIsHistorical;

  String get id => goodsReturn.id;

  GoodsReturnStatus get status => goodsReturn.status;

  String get branchLabel => '$branchCode · $branchName';

  String get progressLabel =>
      GoodsReturnProgress.progressLabelOf(goodsReturn.status);

  /// How long the goods have been in transit, as of [nowUtc]. `null` unless the
  /// document is `shipped` — the Warehouse queue's *umur perjalanan* column (§31).
  ///
  /// Computed on UTC instants, never by comparing serialised timestamps.
  Duration? transitAge(DateTime nowUtc) {
    final shippedAt = goodsReturn.shippedAt;
    if (shippedAt == null || !goodsReturn.isShipped) return null;
    final age = nowUtc.toUtc().difference(shippedAt.toUtc());
    return age.isNegative ? Duration.zero : age;
  }
}

/// A Retur with its lines and its aggregate — what a detail screen renders (§13).
class GoodsReturnDetail {
  const GoodsReturnDetail({
    required this.summary,
    required this.lines,
    required this.progress,
  });

  final GoodsReturnSummary summary;

  /// Every line of the document, in item then expiry order.
  final List<GoodsReturnLine> lines;

  final GoodsReturnProgress progress;

  GoodsReturn get goodsReturn => summary.goodsReturn;

  String get id => goodsReturn.id;

  GoodsReturnStatus get status => goodsReturn.status;

  bool get isDraft => goodsReturn.isDraft;

  bool get isShipped => goodsReturn.isShipped;

  bool get isReceived => goodsReturn.isReceived;

  bool get isFinal => goodsReturn.isFinal;

  /// Whether the branch may hand the goods over: the state machine permits it **and**
  /// the document has lines. The second half is a fact about the lines, which the
  /// status enum cannot see (§20).
  ///
  /// Says nothing about *who* is asking or whether the snapshot still matches the
  /// receipt — `ShipGoodsReturnUseCase` re-asks both inside its transaction, and this
  /// is only what the button reads.
  bool get canShip => goodsReturn.canShip && lines.isNotEmpty;

  /// Whether the Warehouse may confirm arrival. Same shape, same caveat (§21).
  bool get canReceive => goodsReturn.canReceive && lines.isNotEmpty;

  int get lineCount => lines.length;

  /// Totals per unit — what §30 and §32 ask both detail screens to show.
  Map<String, Quantity> get totalQuantityByUnit => progress.totalQuantityByUnit;

  /// Whether any line points at master data that has since been withdrawn (§37).
  bool get usesHistoricalMaster =>
      summary.branchIsHistorical ||
      lines.any((line) => line.usesHistoricalMaster);

  /// The Good Receipt line ids this document claims to return — the set every
  /// integrity check compares against the receipt's own rejections (§26).
  Set<String> get grLineIds => lines.map((line) => line.grLineId).toSet();
}

/// The list filter both sections share (§29/§31).
///
/// Every field here is a *display* filter and none is a security boundary: the branch
/// scope and the Warehouse status scope live in the SQL, and this can only ever narrow
/// what they already allowed.
class GoodsReturnFilter {
  const GoodsReturnFilter({
    this.statuses = const {},
    this.branchId,
    this.searchQuery = '',
    this.from,
    this.to,
  });

  /// Empty means every status the caller's scope allows.
  final Set<GoodsReturnStatus> statuses;

  /// The Warehouse queue's branch chip. Ignored by the branch section, which is
  /// already pinned to one branch by its scope — a filter that could change *which*
  /// branch would be a filter that could widen a scope.
  final String? branchId;

  final String searchQuery;

  /// Inclusive operational-day bounds, applied **in Dart on UTC instants** (§29/§39).
  /// A SQL range on these columns would compare ISO-8601 characters.
  final DateTime? from;
  final DateTime? to;

  bool get isEmpty =>
      statuses.isEmpty &&
      branchId == null &&
      searchQuery.trim().isEmpty &&
      from == null &&
      to == null;

  GoodsReturnFilter copyWith({
    Set<GoodsReturnStatus>? statuses,
    String? branchId,
    bool clearBranchId = false,
    String? searchQuery,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
  }) => GoodsReturnFilter(
    statuses: statuses ?? this.statuses,
    branchId: clearBranchId ? null : (branchId ?? this.branchId),
    searchQuery: searchQuery ?? this.searchQuery,
    from: clearFrom ? null : (from ?? this.from),
    to: clearTo ? null : (to ?? this.to),
  );

  /// Whether [summary] survives the *date* half of this filter.
  ///
  /// The status, branch and search halves are already in the SQL; this is the one
  /// that cannot be, because comparing `created_at` as TEXT compares characters rather
  /// than instants (§39). The instant compared is the one that matters to the reader:
  /// when the document was received if it has been, when it was shipped if it is in
  /// transit, and when it was raised otherwise.
  bool matchesDate(GoodsReturnSummary summary) {
    if (from == null && to == null) return true;
    final document = summary.goodsReturn;
    final instant =
        (document.receivedAt ?? document.shippedAt ?? document.createdAt)
            .toUtc();
    if (from != null && instant.isBefore(from!.toUtc())) return false;
    if (to != null && instant.isAfter(to!.toUtc())) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoodsReturnFilter &&
          other.branchId == branchId &&
          other.searchQuery == searchQuery &&
          other.from == from &&
          other.to == to &&
          other.statuses.length == statuses.length &&
          other.statuses.containsAll(statuses);

  @override
  int get hashCode => Object.hash(
    branchId,
    searchQuery,
    from,
    to,
    Object.hashAllUnordered(statuses),
  );
}

/// One position the receive transaction is about to post to the ledger (§22).
///
/// Deliberately *not* the line model: the posting service must not be able to read an
/// item name, a document number or a status, because none of those may influence what
/// it writes. It gets four facts and a reason, and it writes exactly one movement per
/// entry.
class GoodsReturnPostingLine {
  const GoodsReturnPostingLine({
    required this.lineId,
    required this.itemId,
    this.batchId,
    required this.qty,
    required this.rejectReason,
  });

  final String lineId;
  final String itemId;
  final String? batchId;
  final Quantity qty;

  /// Carried into the movement note, which is why it is required here: G-G4 already
  /// made it mandatory upstream, so the ledger note is deterministic and never empty
  /// (§22).
  final String rejectReason;

  bool get isBatched => batchId != null;
}

/// Everything the receive transaction needs, assembled and verified before the first
/// movement is written (§21/§22).
///
/// A value rather than a list of arguments, so *"the destination was resolved by type,
/// once, from a live Warehouse location"* is a fact the plan carries rather than a step
/// somebody might reorder.
class GoodsReturnPostingPlan {
  const GoodsReturnPostingPlan({
    required this.goodsReturnId,
    required this.warehouseLocationId,
    required this.warehouseLocationName,
    required this.lines,
    this.branchNote,
    this.warehouseNote,
  });

  final String goodsReturnId;

  /// The one active `warehouse` location the goods are credited to. Resolved by type
  /// (§21) — never passed in from a screen.
  final String warehouseLocationId;
  final String warehouseLocationName;

  final List<GoodsReturnPostingLine> lines;

  /// The branch's remark and the Warehouse's, both optional, both appended to every
  /// movement note after the position's own reject reason (§22).
  final String? branchNote;
  final String? warehouseNote;

  int get lineCount => lines.length;

  Quantity get totalQty => Quantity.sum(lines.map((line) => line.qty));

  /// The note one movement carries: the position's reject reason first, because that is
  /// what the row is *about*, then whichever remarks exist.
  ///
  /// Deterministic and never empty — the reject reason is mandatory all the way down
  /// (G-G4), which is what lets §22 promise a non-empty note without inventing one.
  String noteFor(GoodsReturnPostingLine line) {
    final parts = <String>[line.rejectReason.trim()];
    final branch = branchNote?.trim() ?? '';
    if (branch.isNotEmpty) parts.add('Catatan cabang: $branch');
    final warehouse = warehouseNote?.trim() ?? '';
    if (warehouse.isNotEmpty) parts.add('Catatan Warehouse: $warehouse');
    return parts.join(' — ');
  }
}
