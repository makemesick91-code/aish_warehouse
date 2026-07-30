import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../services/consumption_expiry_policy.dart';

/// Pemakaian header, in domain terms (schema v10, §12).
///
/// Immutable on purpose: a document is never mutated in place. Reads produce a new
/// instance and every write goes through a use case. Quantities are [Quantity], event
/// timestamps are UTC instants (T-1).
class Consumption {
  const Consumption({
    required this.id,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.createdBy,
    required this.status,
    this.note,
    this.postedAt,
    this.postedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;

  /// `TMP-CNS-{uuid}` until the sync backend assigns the real number (G-Y4).
  final String docNumber;

  /// The branch the room belongs to. Fixed at creation — see
  /// `CreateConsumptionUseCase`.
  final String branchId;

  /// The one room the goods were used in. Fixed at creation too, and for the same
  /// reason: the answer to *"who may post this"* is a function of it.
  final String roomId;

  /// The Perawat who recorded the usage (G-A3). This is also the ownership key: only
  /// this user may read, edit or post the draft (§14).
  final String createdBy;

  final ConsumptionStatus status;

  /// Optional remark about the usage as a whole. Never patient information (§9).
  final String? note;

  /// UTC instant; convert through `AppDateTimeFormatter` before displaying.
  final DateTime? postedAt;

  /// Who posted it. Null exactly while the document is a draft.
  final String? postedBy;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  bool get isDraft => status.isDraft;

  bool get isPosted => status.isPosted;

  /// Only a draft may have its lines, quantities or note changed.
  bool get isEditable => status.isEditable;

  bool get isFinal => status.isFinal;

  /// Whether the *status* still permits posting. Says nothing about the lines —
  /// [ConsumptionDetail.canPost] asks both.
  bool get canPost => status.canPost;

  /// Whether the stored note is something a reader can act on.
  ///
  /// `String.trim()` rather than SQLite's `trim()`, and the difference is the point:
  /// Dart strips tabs and newlines, SQLite strips spaces only, so a note of `"\n"`
  /// satisfies the database CHECK and reads as absent here.
  bool get hasNote => (note ?? '').trim().isNotEmpty;

  /// Whether the local copy is still waiting to be synchronised (G-Y1).
  bool get isPendingSync => syncStatus == SyncStatus.pending;

  /// Whether [userId] is the nurse who recorded this document (§14).
  ///
  /// A method on the model rather than a comparison at every call site, so
  /// "ownership" has one definition and a screen, a provider and a use case cannot
  /// disagree about it.
  bool isOwnedBy(String userId) => createdBy == userId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Consumption &&
          other.id == id &&
          other.status == status &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(id, status, updatedAt);

  @override
  String toString() => 'Consumption($docNumber, ${status.dbValue})';
}

/// The smallest fact set that decides whether somebody may open a consumption.
///
/// Deliberately tiny: an authorization check must not be the reason a document's
/// contents are loaded. Nothing here identifies an item, a batch, a quantity or the
/// note — only the branch, the room, who created it and the status.
class ConsumptionAccessScope {
  const ConsumptionAccessScope({
    required this.consumptionId,
    required this.branchId,
    required this.roomId,
    required this.createdBy,
    required this.status,
  });

  final String consumptionId;
  final String branchId;
  final String roomId;
  final String createdBy;
  final ConsumptionStatus status;
}

/// One room a consumption may be recorded against, as the room selector offers it.
///
/// A domain model rather than `MasterRoom`, because the selector needs the code and
/// the name together with the historical flag, and deriving the label in three
/// screens is how the three come to word it differently.
class ConsumptionRoom {
  const ConsumptionRoom({
    required this.roomId,
    required this.branchId,
    required this.code,
    required this.name,
    this.isActive = true,
    this.isArchived = false,
  });

  final String roomId;
  final String branchId;
  final String code;
  final String name;

  /// `rooms.is_active`. Never offered for a *new* document; carried so a posted one
  /// can still name where its goods were used (§33).
  final bool isActive;

  /// `deleted_at IS NOT NULL`.
  final bool isArchived;

  bool get isHistorical => !isActive || isArchived;

  /// `R1 · Ruang Dental 1` — the label the selector and the list row show.
  String get label => '$code · $name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsumptionRoom && other.roomId == roomId);

  @override
  int get hashCode => roomId.hashCode;

  @override
  String toString() => 'ConsumptionRoom($label)';
}

/// One position a room currently holds, independently of any document (§16).
///
/// Distinct from [ConsumptionCandidate] on purpose. A candidate belongs to one
/// document and knows what that document already claims; this is a fact about a
/// room's shelf, and it is what the dashboard's counters are derived from. Merging
/// the two would make a dashboard number depend on which draft happened to be open.
///
/// Every position here is **usable**: the repository applies
/// `ConsumptionExpiryPolicy`, so an expired batch is absent rather than present and
/// greyed out (§17).
class RoomStockPosition {
  const RoomStockPosition({
    required this.roomId,
    required this.locationId,
    required this.locationName,
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
    required this.qtyOnHand,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String roomId;
  final String locationId;
  final String locationName;

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  /// `items.has_expiry`. Carried rather than derived from [batchId] being non-null,
  /// because the two answering differently is exactly the corruption §9's rule
  /// exists to make visible.
  final bool hasExpiry;

  /// `items.expiry_alert_days` — what decides the orange badge (G-E6).
  final int expiryAlertDays;

  /// `null` for an item without expiry.
  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8). `null` for an item without expiry.
  final DateTime? expiryDate;

  final Quantity qtyOnHand;

  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  bool get isBatched => batchId != null;

  /// `item|batch`, with an empty batch segment for an item without expiry — the grain
  /// `stock_balances` is keyed at, and the grain the partial unique indexes use.
  String get positionKey => '$itemId|${batchId ?? ''}';

  /// Whether this position is past its expiry date at [referenceUtc] (T-10).
  ///
  /// Always `false` for an item without expiry: there is no date to be past.
  bool isExpiredOn(DateTime referenceUtc) => ConsumptionExpiryPolicy.isExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  /// Whether the batch is inside the item's alert window (G-E6) — *segera
  /// kedaluwarsa*, the orange badge.
  bool isNearExpiryOn(DateTime referenceUtc) =>
      ConsumptionExpiryPolicy.isNearExpiry(
        expiryDate: expiryDate,
        expiryAlertDays: expiryAlertDays,
        nowUtc: referenceUtc,
      );

  /// Whole operational days until expiry; negative once it has passed. `null` for an
  /// item without expiry.
  int? remainingDaysOn(DateTime referenceUtc) =>
      ConsumptionExpiryPolicy.remainingDays(
        expiryDate: expiryDate,
        nowUtc: referenceUtc,
      );

  /// The same position as a candidate for one document.
  ConsumptionCandidate toCandidate() => ConsumptionCandidate(
    itemId: itemId,
    sku: sku,
    itemName: itemName,
    categoryId: categoryId,
    unit: unit,
    hasExpiry: hasExpiry,
    expiryAlertDays: expiryAlertDays,
    batchId: batchId,
    batchNo: batchNo,
    expiryDate: expiryDate,
    availableQty: qtyOnHand,
    roomId: roomId,
    locationId: locationId,
    itemIsHistorical: itemIsHistorical,
    batchIsHistorical: batchIsHistorical,
  );

  @override
  String toString() =>
      'RoomStockPosition($sku${batchNo == null ? '' : ', $batchNo'}, '
      '${qtyOnHand.format()})';
}

/// One position a consumption may draw on — one item, one batch, one room (§16).
///
/// It is a *snapshot*: the picker reads it while the form is open, and the posting
/// reads the balance again inside the transaction — the second read is the authority
/// (§18).
///
/// Every candidate the pickers offer is **usable**: an expired batch is not a
/// candidate at all and is never constructed as one. [isExpiredOn] therefore reads as
/// a re-assertion rather than a filter, and that is deliberate — it is asked again
/// when a line is added, when it is edited and inside the posting transaction,
/// because a snapshot taken while a form was open is not evidence about the moment
/// the button is pressed. A batch that expires *while the draft sits open* becomes
/// ineligible, and the posting is what catches it.
class ConsumptionCandidate {
  const ConsumptionCandidate({
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
    required this.availableQty,
    required this.roomId,
    required this.locationId,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  final bool hasExpiry;
  final int expiryAlertDays;

  /// `null` for an item without expiry (G-E2).
  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  /// What the room holds for this exact position. Strictly positive for every
  /// candidate: a zero balance is not stock anybody can use.
  final Quantity availableQty;

  /// The room. Carried so a candidate cannot be applied to another document's room by
  /// accident — the add path compares it (§16).
  final String roomId;

  /// The `room` stock location the room's balances live at.
  final String locationId;

  /// The item was deactivated or archived after this stock arrived. It is still
  /// physically on the room's shelf, so an *existing* draft can still name it — the
  /// badge only explains why the row no longer appears in the ordinary pickers
  /// (§16/§33). A **new** line may not use one.
  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  bool get isBatched => batchId != null;

  /// `item|batch`, with an empty batch segment for an item without expiry.
  String get positionKey => '$itemId|${batchId ?? ''}';

  /// Whether this batch is past its expiry date at [referenceUtc], judged against the
  /// **operational** date in GMT+8 (T-10) rather than the device's.
  ///
  /// Delegated to [ConsumptionExpiryPolicy] rather than re-derived here. The rule has
  /// exactly one definition, and a model that computed its own would be a second one —
  /// which is how a badge comes to disagree with the refusal beside it.
  bool isExpiredOn(DateTime referenceUtc) => ConsumptionExpiryPolicy.isExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  /// Whether the batch is inside the item's alert window (G-E6). A **warning**, never
  /// a refusal: near-expiry stock is exactly the stock a nurse should be using next
  /// (§17).
  bool isNearExpiryOn(DateTime referenceUtc) =>
      ConsumptionExpiryPolicy.isNearExpiry(
        expiryDate: expiryDate,
        expiryAlertDays: expiryAlertDays,
        nowUtc: referenceUtc,
      );

  /// Whole operational days until expiry, negative once it has passed; `null` for an
  /// item without expiry.
  ///
  /// An `int`, never a `double`: a count of days has no fractional part, and
  /// introducing one would be the same rounding drift `Quantity` exists to keep out of
  /// the quantity path.
  int? remainingDaysOn(DateTime referenceUtc) =>
      ConsumptionExpiryPolicy.remainingDays(
        expiryDate: expiryDate,
        nowUtc: referenceUtc,
      );

  /// The same candidate with [taken] already claimed, floored at zero.
  ///
  /// How a document's own existing line is netted out before the picker offers the
  /// position again: the room does not hold the batch twice.
  ConsumptionCandidate minus(Quantity taken) {
    final remaining = availableQty - taken;
    return ConsumptionCandidate(
      itemId: itemId,
      sku: sku,
      itemName: itemName,
      categoryId: categoryId,
      unit: unit,
      hasExpiry: hasExpiry,
      expiryAlertDays: expiryAlertDays,
      batchId: batchId,
      batchNo: batchNo,
      expiryDate: expiryDate,
      availableQty: remaining.isNegative ? Quantity.zero() : remaining,
      roomId: roomId,
      locationId: locationId,
      itemIsHistorical: itemIsHistorical,
      batchIsHistorical: batchIsHistorical,
    );
  }

  @override
  String toString() {
    final batch = batchNo == null ? '' : ', $batchNo';
    final expiry = expiryDate == null
        ? ''
        : ', ED ${DateOnly.formatIso(expiryDate!)}';
    return 'ConsumptionCandidate($sku$batch$expiry, ${availableQty.format()})';
  }
}

/// One consumed position, enriched with everything the form and the posted detail
/// need.
class ConsumptionLine {
  const ConsumptionLine({
    required this.id,
    required this.consumptionId,
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
    this.note,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String id;
  final String consumptionId;

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  /// `items.has_expiry`. On a compliant line this agrees with `batchId != null`; it is
  /// carried rather than assumed so a corrupt row is *visible* rather than silently
  /// rendered as though it were fine.
  final bool hasExpiry;

  final int expiryAlertDays;

  /// `null` for an item without expiry (G-E2).
  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  /// What this line takes off the room's shelf. Strictly positive.
  final Quantity qty;

  /// Optional detail for this one position. Never patient information (§9).
  final String? note;

  /// The item or batch was deactivated or archived after the line was added. A
  /// **posted** line stays visible — the badge only explains why the row no longer
  /// appears in the pickers (§33).
  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  bool get hasNote => (note ?? '').trim().isNotEmpty;

  bool get isBatched => batchId != null;

  /// Whether the line's batch and its item's `has_expiry` agree (G-E2).
  ///
  /// `false` is a corrupt row rather than a user mistake — the use cases refuse both
  /// directions — and a screen showing it can say so instead of rendering a batch-less
  /// line for a batch-tracked product as though nothing were wrong.
  bool get isBatchConsistent => hasExpiry == isBatched;

  /// `item|batch`, with an empty batch segment for an item without expiry — the same
  /// grain as the partial unique indexes, so a duplicate detected in memory and one
  /// refused by the database are the same thing.
  String get positionKey => '$itemId|${batchId ?? ''}';

  bool isExpiredOn(DateTime referenceUtc) => ConsumptionExpiryPolicy.isExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  bool isNearExpiryOn(DateTime referenceUtc) =>
      ConsumptionExpiryPolicy.isNearExpiry(
        expiryDate: expiryDate,
        expiryAlertDays: expiryAlertDays,
        nowUtc: referenceUtc,
      );

  /// Whole operational days until expiry, as an `int` (see [ConsumptionCandidate]).
  int? remainingDaysOn(DateTime referenceUtc) =>
      ConsumptionExpiryPolicy.remainingDays(
        expiryDate: expiryDate,
        nowUtc: referenceUtc,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsumptionLine &&
          other.id == id &&
          other.qty == qty &&
          other.note == note);

  @override
  int get hashCode => Object.hash(id, qty, note);

  @override
  String toString() =>
      'ConsumptionLine($sku${batchNo == null ? '' : ', $batchNo'}, '
      '${qty.format()} $unit)';
}

/// One line as the integrity checks see it: identifiers and a quantity, no joined
/// master data at all.
///
/// Deliberately not [ConsumptionLine]: that model's item name, batch number and
/// expiry date come from joins, and a join is exactly what can make a broken
/// reference *disappear* instead of reporting it. The set integrity check compares
/// these ids against the joined read, so a line whose item row is gone shows up as a
/// difference rather than as one fewer line (§22).
class ConsumptionLineReference {
  const ConsumptionLineReference({
    required this.id,
    required this.consumptionId,
    required this.itemId,
    this.batchId,
    required this.qty,
    this.note,
  });

  final String id;
  final String consumptionId;
  final String itemId;
  final String? batchId;
  final Quantity qty;
  final String? note;

  bool get hasNote => (note ?? '').trim().isNotEmpty;

  bool get isBatched => batchId != null;

  /// `item|batch`, with an empty batch segment for an item without expiry — the grain
  /// the room balance is held at, and the grain the partial unique indexes use. They
  /// are the same here because a consumption draws from exactly one room, which is
  /// what makes the aggregation in §18 straightforward.
  String get positionKey => '$itemId|${batchId ?? ''}';
}

/// What one consumption document contains, as counters (§30).
///
/// A value object rather than four loose numbers, because *"3 posisi · 2 barang"* and
/// *"posting is allowed"* are questions about the same set of lines, and answering
/// them in two places is how they come to disagree.
class ConsumptionProgress {
  const ConsumptionProgress({
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
    required this.expiredCount,
    required this.nearExpiryCount,
    this.nearestExpiryDate,
  });

  /// Derives the counters from a list of lines.
  ///
  /// [referenceUtc] decides the expiry counters, and it is passed in rather than read
  /// from a clock so a badge and the number beside it are judged against the same
  /// instant (T-7).
  factory ConsumptionProgress.of(
    Iterable<ConsumptionLine> lines, {
    required DateTime referenceUtc,
  }) {
    final items = <String>{};
    final batches = <String>{};
    var lineCount = 0;
    var expired = 0;
    var nearExpiry = 0;
    DateTime? nearest;
    for (final line in lines) {
      lineCount += 1;
      items.add(line.itemId);
      final batchId = line.batchId;
      if (batchId != null) batches.add(batchId);
      if (line.isExpiredOn(referenceUtc)) expired += 1;
      if (line.isNearExpiryOn(referenceUtc)) nearExpiry += 1;
      final expiry = line.expiryDate;
      if (expiry != null &&
          (nearest == null || DateOnly.isBeforeDate(expiry, nearest))) {
        nearest = expiry;
      }
    }
    return ConsumptionProgress(
      lineCount: lineCount,
      itemCount: items.length,
      batchCount: batches.length,
      expiredCount: expired,
      nearExpiryCount: nearExpiry,
      nearestExpiryDate: nearest,
    );
  }

  final int lineCount;

  /// Distinct items. One item split across two batches is one item and two lines.
  final int itemCount;

  /// Distinct batches. Lower than [lineCount] on a document that also carries items
  /// without expiry, which is the normal case.
  final int batchCount;

  /// Lines whose batch is past its expiry date right now.
  ///
  /// Zero on every document the use cases produced, and the inversion is the
  /// interesting one: a batch that expired while the draft sat open must not be
  /// consumed at all (§17), so `expiredCount > 0` is a document that cannot post, and
  /// the screen says so rather than letting the posting be the first thing to notice.
  final int expiredCount;

  /// Lines inside their item's alert window (G-E6). A **warning** count, not a
  /// blocker: near-expiry stock is exactly what should be used next.
  final int nearExpiryCount;

  /// The earliest expiry date on the document, or `null` when nothing on it is
  /// batch-tracked.
  final DateTime? nearestExpiryDate;

  bool get isEmpty => lineCount == 0;

  /// Whether every line may still be consumed. False means something drifted past its
  /// expiry date, which is a state the posting refuses.
  bool get allUsable => expiredCount == 0;

  bool get hasNearExpiry => nearExpiryCount > 0;

  /// `3 posisi · 2 barang` — the label the list row and the detail header show.
  String get label => '$lineCount posisi · $itemCount barang';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsumptionProgress &&
          other.lineCount == lineCount &&
          other.itemCount == itemCount &&
          other.batchCount == batchCount &&
          other.expiredCount == expiredCount &&
          other.nearExpiryCount == nearExpiryCount &&
          other.nearestExpiryDate == nearestExpiryDate);

  @override
  int get hashCode => Object.hash(
    lineCount,
    itemCount,
    batchCount,
    expiredCount,
    nearExpiryCount,
    nearestExpiryDate,
  );

  @override
  String toString() => 'ConsumptionProgress($label)';
}

/// A header plus the names a list row needs, without a second query.
///
/// The `…IsHistorical` flags exist so a screen can *say* that a document rests on
/// master data that has since been deactivated or archived. They are never a reason to
/// hide the row: a consumption whose room was retired afterwards is exactly the
/// document whose history still has to be readable (§33).
class ConsumptionSummary {
  const ConsumptionSummary({
    required this.consumption,
    required this.room,
    required this.branchCode,
    required this.branchName,
    required this.createdByName,
    this.postedByName,
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
    this.branchIsHistorical = false,
    this.roomIsHistorical = false,
    this.createdByIsHistorical = false,
    this.postedByIsHistorical = false,
  });

  final Consumption consumption;

  final ConsumptionRoom room;

  final String branchCode;
  final String branchName;

  final String createdByName;

  /// Null exactly while the document is a draft.
  final String? postedByName;

  final int lineCount;
  final int itemCount;
  final int batchCount;

  final bool branchIsHistorical;
  final bool roomIsHistorical;
  final bool createdByIsHistorical;
  final bool postedByIsHistorical;

  String get id => consumption.id;

  String get docNumber => consumption.docNumber;

  String get branchId => consumption.branchId;

  String get roomId => consumption.roomId;

  ConsumptionStatus get status => consumption.status;

  bool get usesHistoricalMaster =>
      branchIsHistorical ||
      roomIsHistorical ||
      createdByIsHistorical ||
      postedByIsHistorical;

  /// `R1 · Ruang Dental 1` — where the goods were used.
  String get roomLabel => room.label;

  /// `3 posisi · 2 barang`, from the counts SQL aggregated rather than from the lines,
  /// so a list row costs one query.
  String get label => '$lineCount posisi · $itemCount barang';
}

/// Everything the form and the posted detail need about one consumption.
class ConsumptionDetail {
  const ConsumptionDetail({required this.summary, required this.lines});

  final ConsumptionSummary summary;
  final List<ConsumptionLine> lines;

  Consumption get consumption => summary.consumption;

  String get id => consumption.id;

  String get branchId => consumption.branchId;

  String get roomId => consumption.roomId;

  ConsumptionRoom get room => summary.room;

  ConsumptionStatus get status => consumption.status;

  bool get isDraft => consumption.isDraft;

  bool get isPosted => consumption.isPosted;

  bool get isEditable => consumption.isEditable;

  bool get isFinal => consumption.isFinal;

  bool get isEmpty => lines.isEmpty;

  int get lineCount => lines.length;

  int get itemCount => lines.map((line) => line.itemId).toSet().length;

  /// Both halves of the posting precondition: the document is `draft` **and** it
  /// carries at least one line. There is deliberately no note requirement — a
  /// consumption note is optional (§8). The use case remains the authority; this is
  /// what the button asks.
  bool get canPost => consumption.canPost && lines.isNotEmpty;

  bool isOwnedBy(String userId) => consumption.isOwnedBy(userId);

  /// The lines in reading order — item, then nearest expiry, then batch, then id.
  ///
  /// The same order the DAO produces, restated here so an in-memory list built by a
  /// test or a form is ordered identically.
  List<ConsumptionLine> get orderedLines {
    final ordered = [...lines]..sort(_compare);
    return List<ConsumptionLine>.unmodifiable(ordered);
  }

  /// Total quantity of one exact position — item plus batch. This is what §18
  /// compares against the room balance.
  Quantity totalForPosition({required String itemId, String? batchId}) =>
      Quantity.sum(
        lines
            .where((line) => line.itemId == itemId && line.batchId == batchId)
            .map((line) => line.qty),
      );

  /// Totals grouped by unit.
  ///
  /// Quantities of different units are never added together: `2 box` and `3 ampul`
  /// are not `5` of anything, and one headline number would mislead.
  Map<String, Quantity> get totalQuantityByUnit {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.unit] = (totals[line.unit] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  ConsumptionProgress progressOn(DateTime referenceUtc) =>
      ConsumptionProgress.of(lines, referenceUtc: referenceUtc);

  bool get usesHistoricalMaster =>
      summary.usesHistoricalMaster ||
      lines.any((line) => line.usesHistoricalMaster);

  static int _compare(ConsumptionLine a, ConsumptionLine b) {
    final byItem = a.itemName.compareTo(b.itemName);
    if (byItem != 0) return byItem;
    final aExpiry = a.expiryDate;
    final bExpiry = b.expiryDate;
    if (aExpiry != null && bExpiry != null) {
      final byExpiry = DateOnly.compare(aExpiry, bExpiry);
      if (byExpiry != 0) return byExpiry;
    } else if (aExpiry != null) {
      // A batch-tracked position sorts before an unbatched one of the same name, which
      // can only happen on a corrupt document — and putting it first is what makes the
      // inconsistency visible rather than buried at the bottom of the list.
      return -1;
    } else if (bExpiry != null) {
      return 1;
    }
    final byBatch = (a.batchNo ?? '').compareTo(b.batchNo ?? '');
    if (byBatch != 0) return byBatch;
    return a.id.compareTo(b.id);
  }
}

/// One position as the form holds it before it is saved — a candidate plus the
/// quantity typed against it.
///
/// A value object rather than a loose `(candidate, qty)` pair, because the two
/// questions the form asks of it — *may this be saved?* and *what is left in the room
/// afterwards?* — are the same arithmetic the use case performs, and deriving them in
/// the widget is how the two come to disagree.
class ConsumptionDraft {
  const ConsumptionDraft({
    required this.candidate,
    required this.qty,
    this.lineId,
    this.note,
  });

  final ConsumptionCandidate candidate;

  /// What the user says was used. May be zero while they are still typing, which is
  /// exactly why [isValid] exists.
  final Quantity qty;

  /// Id of the `consumption_lines` row when this position is already stored; `null`
  /// for one the picker has just proposed.
  final String? lineId;

  final String? note;

  bool get isStored => lineId != null;

  String get positionKey => candidate.positionKey;

  String get unit => candidate.unit;

  Quantity get availableQty => candidate.availableQty;

  /// Whether the typed quantity exceeds what the room holds — what the form greys the
  /// save button out on, and what the use case refuses (§18).
  bool get exceedsAvailable => qty > candidate.availableQty;

  /// Whether the whole of the position was used. Legitimate, and common.
  bool get isFullPosition => qty == candidate.availableQty;

  /// Whether only part of it was.
  bool get isPartial => qty.isPositive && qty < candidate.availableQty;

  /// What stays in the room afterwards. Never negative — a request that would make it
  /// so is refused rather than clamped, so the number a screen shows and the number
  /// the ledger would produce are the same.
  Quantity get remainingAfterConsumption {
    final remaining = candidate.availableQty - qty;
    return remaining.isNegative ? Quantity.zero() : remaining;
  }

  /// Whether this draft could be stored as it stands.
  bool get isValid => qty.isPositive && !exceedsAvailable;

  ConsumptionDraft copyWith({
    Quantity? qty,
    Object? note = _unset,
    Object? lineId = _unset,
  }) => ConsumptionDraft(
    candidate: candidate,
    qty: qty ?? this.qty,
    lineId: lineId == _unset ? this.lineId : lineId as String?,
    note: note == _unset ? this.note : note as String?,
  );

  /// Sentinel so `copyWith(note: null)` can mean "clear it" rather than "keep the
  /// current value".
  static const Object _unset = Object();

  @override
  String toString() => 'ConsumptionDraft(${candidate.sku}, ${qty.format()})';
}

/// One movement the posting will write — one line, resolved against the room.
///
/// Produced by `ConsumptionStockPlanBuilder` from the stored lines plus the room
/// location the use case resolved, so the posting service never resolves a location
/// itself and no caller can nominate one.
class ConsumptionPostingEntry {
  const ConsumptionPostingEntry({
    required this.lineId,
    required this.itemId,
    this.batchId,
    required this.qty,
    this.note,
  });

  final String lineId;
  final String itemId;
  final String? batchId;
  final Quantity qty;

  /// The deterministic movement note — the document's note plus the line's own
  /// detail, composed once by the plan builder so the ledger text cannot differ
  /// between two callers (§19). `null` when neither carries text.
  final String? note;

  String get sourceKey => '$itemId|${batchId ?? ''}';

  @override
  String toString() =>
      'ConsumptionPostingEntry($itemId, ${batchId ?? '-'}, ${qty.format()})';
}

/// Everything one posting needs, validated and resolved, before the first movement is
/// written (§20).
///
/// Building the whole plan first is what makes the atomicity rule achievable: the room
/// location is resolved, every position aggregated and every balance requirement known
/// before anything is written, so a failure cannot land halfway through a document.
///
/// There is deliberately **no destination anywhere in this class.** A consumption has
/// one leg: stock leaves the room and enters nothing. That is what §2.2 states about
/// `to_location_id`, and a field that could hold a destination would be a field
/// somebody could fill in.
class ConsumptionPostingPlan {
  const ConsumptionPostingPlan({
    required this.consumptionId,
    required this.roomId,
    required this.roomLocationId,
    this.note,
    required this.entries,
  });

  final String consumptionId;

  /// The room the goods left, and the `room` stock location its balances live at. Both
  /// are carried because the ledger writes the location while every message names the
  /// room.
  final String roomId;
  final String roomLocationId;

  /// The document's own note, normalized. Optional (§8).
  final String? note;

  final List<ConsumptionPostingEntry> entries;

  bool get isEmpty => entries.isEmpty;

  int get lineCount => entries.length;

  int get itemCount => entries.map((entry) => entry.itemId).toSet().length;

  /// How much the room must supply per **source position** — item plus batch.
  ///
  /// The aggregation is the point: the partial unique indexes already stop one
  /// document holding the same position twice, but an index is not the authority on a
  /// document two racing devices assembled, and summing costs nothing.
  Map<String, Quantity> get sourceRequirements {
    final totals = <String, Quantity>{};
    for (final entry in entries) {
      totals[entry.sourceKey] =
          (totals[entry.sourceKey] ?? Quantity.zero()) + entry.qty;
    }
    return totals;
  }

  /// The distinct source positions, as `(itemId, batchId)` pairs, in a stable order —
  /// what the balance verification iterates.
  List<({String itemId, String? batchId})> get sourcePositions {
    final seen = <String>{};
    final positions = <({String itemId, String? batchId})>[];
    for (final entry in entries) {
      if (seen.add(entry.sourceKey)) {
        positions.add((itemId: entry.itemId, batchId: entry.batchId));
      }
    }
    return List<({String itemId, String? batchId})>.unmodifiable(positions);
  }

  /// Total quantity leaving the system.
  Quantity get totalQty => Quantity.sum(entries.map((entry) => entry.qty));
}

/// Filter state for a consumption list.
class ConsumptionFilter {
  const ConsumptionFilter({
    this.roomId,
    this.createdBy,
    this.statuses = const <ConsumptionStatus>{},
    this.categoryId,
    this.searchQuery = '',
    this.postedFromUtc,
    this.postedToUtc,
  });

  /// `null` means every room the caller's *scope* already allows. It never widens a
  /// scope — the DAO ANDs the two — which is why a screen may set it freely from its
  /// own room selector.
  final String? roomId;

  /// The Kepala Cabang's *Perawat* filter. Same reasoning: it narrows within the
  /// branch scope and can never widen it.
  final String? createdBy;

  final Set<ConsumptionStatus> statuses;

  /// Category chip on the candidate list; `null` means *Semua*.
  final String? categoryId;

  final String searchQuery;

  /// Posted-date range, as **UTC instants** rather than as a date string.
  ///
  /// §31 is explicit about why: `posted_at` is ISO-8601 TEXT, so a SQL `BETWEEN` on
  /// two serialised dates would compare characters — the trap schema v4 removed from
  /// `stock_opnames`. The range is resolved from an operational day through
  /// `AppTimeZone.startOfOperationalDayUtc` / `endOfOperationalDayUtc` and applied in
  /// Dart, on instants.
  final DateTime? postedFromUtc;
  final DateTime? postedToUtc;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  bool get hasPostedRange => postedFromUtc != null || postedToUtc != null;

  /// Whether [postedAtUtc] falls inside the range, comparing **instants**.
  ///
  /// A method here rather than a predicate at each call site, so the list screen, the
  /// counters beside it and the tests all decide the same way. A draft — `postedAt`
  /// null — is outside every range: it has not been posted, so there is no instant to
  /// compare.
  bool includesPostedAt(DateTime? postedAtUtc) {
    if (!hasPostedRange) return true;
    if (postedAtUtc == null) return false;
    final instant = postedAtUtc.toUtc();
    final from = postedFromUtc;
    final to = postedToUtc;
    if (from != null && instant.isBefore(from.toUtc())) return false;
    if (to != null && instant.isAfter(to.toUtc())) return false;
    return true;
  }

  ConsumptionFilter copyWith({
    Object? roomId = _unset,
    Object? createdBy = _unset,
    Set<ConsumptionStatus>? statuses,
    Object? categoryId = _unset,
    String? searchQuery,
    Object? postedFromUtc = _unset,
    Object? postedToUtc = _unset,
  }) {
    return ConsumptionFilter(
      roomId: roomId == _unset ? this.roomId : roomId as String?,
      createdBy: createdBy == _unset ? this.createdBy : createdBy as String?,
      statuses: statuses ?? this.statuses,
      categoryId: categoryId == _unset
          ? this.categoryId
          : categoryId as String?,
      searchQuery: searchQuery ?? this.searchQuery,
      postedFromUtc: postedFromUtc == _unset
          ? this.postedFromUtc
          : postedFromUtc as DateTime?,
      postedToUtc: postedToUtc == _unset
          ? this.postedToUtc
          : postedToUtc as DateTime?,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsumptionFilter &&
          other.roomId == roomId &&
          other.createdBy == createdBy &&
          other.categoryId == categoryId &&
          other.searchQuery == searchQuery &&
          other.postedFromUtc == postedFromUtc &&
          other.postedToUtc == postedToUtc &&
          other.statuses.length == statuses.length &&
          other.statuses.containsAll(statuses));

  @override
  int get hashCode => Object.hash(
    roomId,
    createdBy,
    categoryId,
    searchQuery,
    postedFromUtc,
    postedToUtc,
    Object.hashAllUnordered(statuses),
  );
}

/// Every status a consumption list may show — both of them.
const Set<ConsumptionStatus> visibleConsumptionStatuses = {
  ConsumptionStatus.draft,
  ConsumptionStatus.posted,
};

/// The only status a Kepala Cabang's history may show (§14).
///
/// A constant rather than an inline set literal, because the repository, the access
/// policy, the providers and the security tests all have to name the same fact — and
/// four copies of `{posted}` is four things to keep in step.
const Set<ConsumptionStatus> branchVisibleConsumptionStatuses = {
  ConsumptionStatus.posted,
};
