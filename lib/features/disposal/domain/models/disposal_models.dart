import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';
import '../services/disposal_expiry_policy.dart';

/// Pemusnahan header, in domain terms (schema v9, G-E7).
///
/// Immutable on purpose: a document is never mutated in place. Reads produce a new
/// instance and every write goes through a use case. Quantities are [Quantity],
/// event timestamps are UTC instants (T-1).
class Disposal {
  const Disposal({
    required this.id,
    required this.docNumber,
    required this.sourceLocationId,
    required this.createdBy,
    required this.status,
    this.reason,
    this.postedAt,
    this.postedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;

  /// `TMP-DSP-{uuid}` until the sync backend assigns the final number (G-Y4).
  final String docNumber;

  /// The one location the goods leave. Fixed at creation — see
  /// `CreateDisposalUseCase`.
  final String sourceLocationId;

  final String createdBy;
  final DisposalStatus status;

  /// G-E7's mandatory note. Nullable while the document is a draft, non-blank the
  /// moment it posts.
  final String? reason;

  /// UTC instant; convert through `AppDateTimeFormatter` before displaying.
  final DateTime? postedAt;

  /// G-E7's *pelaku*. Null exactly while the document is a draft.
  final String? postedBy;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  bool get isDraft => status.isDraft;

  bool get isPosted => status.isPosted;

  /// Only a draft may have its lines, quantities or reason changed.
  bool get isEditable => status.isEditable;

  bool get isFinal => status.isFinal;

  /// Whether the *status* still permits posting. Says nothing about the lines or
  /// the reason — [DisposalDetail.canPost] asks all three.
  bool get canPost => status.canPost;

  /// Whether the stored reason is something a reader can act on.
  ///
  /// `String.trim()` rather than SQLite's `trim()`, and the difference is the
  /// point: Dart strips tabs and newlines, SQLite strips spaces only, so a reason
  /// of `"\n"` satisfies the database CHECK and is refused here (§19).
  bool get hasReason => (reason ?? '').trim().isNotEmpty;

  /// Whether the local copy is still waiting to be synchronised (G-Y1).
  bool get isPendingSync => syncStatus == SyncStatus.pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Disposal &&
          other.id == id &&
          other.status == status &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(id, status, updatedAt);

  @override
  String toString() => 'Disposal($docNumber, ${status.dbValue})';
}

/// The smallest fact set that decides whether somebody may open a disposal.
///
/// Deliberately tiny: an authorization check must not be the reason a document's
/// contents are loaded. Nothing here identifies an item, a batch, a quantity or
/// the reason — only the source location, who created it and the status.
class DisposalAccessScope {
  const DisposalAccessScope({
    required this.disposalId,
    required this.sourceLocationId,
    required this.createdBy,
    required this.status,
  });

  final String disposalId;
  final String sourceLocationId;
  final String createdBy;
  final DisposalStatus status;
}

/// One location a disposal may be raised from, as the source selector offers it.
///
/// A domain model rather than `MasterLocation`, because the selector needs two
/// facts the master model has no room for: the human-readable kind of place it is
/// (*Gudang Cabang*, *Ruangan*), and how many expired positions are sitting there
/// right now. Deriving the first from the enum in three screens is how the three
/// come to word it differently.
class DisposalSourceLocation {
  const DisposalSourceLocation({
    required this.locationId,
    required this.type,
    required this.name,
    this.branchId,
    this.roomId,
    this.isArchived = false,
  });

  final String locationId;
  final StockLocationType type;
  final String name;
  final String? branchId;
  final String? roomId;

  /// `deleted_at IS NOT NULL`. Never offered for a *new* document; carried so a
  /// posted one can still name where its goods came from (§34).
  final bool isArchived;

  /// `Warehouse Pusat` · `Gudang Cabang` · `Ruangan` — the words §29 and §32 use.
  String get kindLabel => switch (type) {
    StockLocationType.warehouse => 'Warehouse Pusat',
    StockLocationType.branchStore => 'Gudang Cabang',
    StockLocationType.room => 'Ruangan',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisposalSourceLocation && other.locationId == locationId);

  @override
  int get hashCode => locationId.hashCode;

  @override
  String toString() => 'DisposalSourceLocation($kindLabel, $name)';
}

/// One expired position a disposal may draw on — one item, one batch, one shelf.
///
/// Every candidate the pickers offer is **already expired** (G-E7); a batch that is
/// merely near expiry is not a candidate at all and is never constructed as one.
/// [isExpiredOn] therefore reads as a re-assertion rather than a filter, and that
/// is deliberate: it is asked again when a line is added, when it is edited and
/// inside the posting transaction, because a snapshot taken while a form was open
/// is not evidence about the moment the button is pressed.
///
/// It is a *snapshot*: the picker reads it while the form is open, and the posting
/// reads the balance again inside the transaction — the second read is the
/// authority (§18).
class DisposalCandidate {
  const DisposalCandidate({
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    required this.availableQty,
    required this.sourceLocationId,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;

  /// What the source location holds for this exact position. Strictly positive for
  /// every candidate: a zero balance is not stock anybody can destroy.
  final Quantity availableQty;

  /// The shelf. Carried so a candidate cannot be applied to another document's
  /// source by accident — the add path compares it (§17).
  final String sourceLocationId;

  /// The item was deactivated or archived after this stock arrived. It is still
  /// physically expired on the shelf, so it is still a candidate — the badge only
  /// explains why the row no longer appears in the ordinary pickers (§17/§34).
  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  /// `item|batch` — the grain `stock_balances` holds this position at, and the
  /// grain the unique index on `disposal_lines` uses.
  String get positionKey => '$itemId|$batchId';

  /// Whether this batch is past its expiry date at [referenceUtc], judged against
  /// the **operational** date in GMT+8 (T-10) rather than the device's.
  ///
  /// Delegated to [DisposalExpiryPolicy] rather than re-derived here. The rule has
  /// exactly one definition, and a model that computed its own would be a second
  /// one — which is how a badge comes to disagree with the refusal beside it.
  bool isExpiredOn(DateTime referenceUtc) => DisposalExpiryPolicy.isExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  /// Whole operational days since the batch expired. Zero on the expiry day itself
  /// — when it is not yet disposable — and one on the first day it is.
  ///
  /// An `int`, never a `double`: a count of days has no fractional part, and
  /// introducing one would be the same rounding drift `Quantity` exists to keep
  /// out of the quantity path.
  int daysExpiredOn(DateTime referenceUtc) => DisposalExpiryPolicy.daysExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  /// The same candidate with [taken] already claimed, floored at zero.
  ///
  /// How a document's own existing line is netted out before the picker offers the
  /// position again: the shelf does not hold the batch twice.
  DisposalCandidate minus(Quantity taken) {
    final remaining = availableQty - taken;
    return DisposalCandidate(
      itemId: itemId,
      sku: sku,
      itemName: itemName,
      categoryId: categoryId,
      unit: unit,
      batchId: batchId,
      batchNo: batchNo,
      expiryDate: expiryDate,
      availableQty: remaining.isNegative ? Quantity.zero() : remaining,
      sourceLocationId: sourceLocationId,
      itemIsHistorical: itemIsHistorical,
      batchIsHistorical: batchIsHistorical,
    );
  }

  @override
  String toString() =>
      'DisposalCandidate($sku, $batchNo, ED ${DateOnly.formatIso(expiryDate)}, '
      '${availableQty.format()})';
}

/// An expired position at a location, as the dashboard and the *Stok Kedaluwarsa*
/// tab report it — independently of any document.
///
/// Distinct from [DisposalCandidate] on purpose. A candidate belongs to one
/// document and knows what that document already claims; this is a fact about a
/// shelf, and it is what G-E6's counters are derived from. Merging the two would
/// make a dashboard number depend on which draft happened to be open.
class ExpiredStockPosition {
  const ExpiredStockPosition({
    required this.locationId,
    required this.locationName,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    required this.qtyOnHand,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String locationId;
  final String locationName;

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;

  final Quantity qtyOnHand;

  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  String get positionKey => '$itemId|$batchId';

  bool isExpiredOn(DateTime referenceUtc) => DisposalExpiryPolicy.isExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  int daysExpiredOn(DateTime referenceUtc) => DisposalExpiryPolicy.daysExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  /// The same position as a candidate for one document.
  DisposalCandidate toCandidate() => DisposalCandidate(
    itemId: itemId,
    sku: sku,
    itemName: itemName,
    categoryId: categoryId,
    unit: unit,
    batchId: batchId,
    batchNo: batchNo,
    expiryDate: expiryDate,
    availableQty: qtyOnHand,
    sourceLocationId: locationId,
    itemIsHistorical: itemIsHistorical,
    batchIsHistorical: batchIsHistorical,
  );

  @override
  String toString() =>
      'ExpiredStockPosition($sku, $batchNo, '
      'ED ${DateOnly.formatIso(expiryDate)}, ${qtyOnHand.format()})';
}

/// One destroyed position, enriched with everything the form and the posted detail
/// need.
class DisposalLine {
  const DisposalLine({
    required this.id,
    required this.disposalId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.hasExpiry,
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    required this.qty,
    this.note,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String id;
  final String disposalId;

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;

  /// Always `true` on a compliant line — only an expiry-tracked item can have an
  /// expired batch. Carried rather than assumed so a corrupt row is *visible*
  /// rather than silently rendered as though it were fine.
  final bool hasExpiry;

  /// Never null: `disposal_lines.batch_id` is NOT NULL.
  final String batchId;
  final String batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime expiryDate;

  /// What this line takes off the shelf. Strictly positive.
  final Quantity qty;

  /// Optional detail for this one position. Never a substitute for the header's
  /// reason.
  final String? note;

  /// The item or batch was deactivated or archived after the line was added. A
  /// **posted** line stays visible — the badge only explains why the row no longer
  /// appears in the pickers (§34). Unlike a Distribusi's deactivated room, this is
  /// not a reason to refuse posting: the goods are already unusable and the
  /// document takes them *out* of the system rather than moving them into a place
  /// nobody is working.
  final bool itemIsHistorical;
  final bool batchIsHistorical;

  bool get usesHistoricalMaster => itemIsHistorical || batchIsHistorical;

  bool get hasNote => (note ?? '').trim().isNotEmpty;

  /// `item|batch` — the same grain as the partial unique index, so a duplicate
  /// detected in memory and one refused by the database are the same thing.
  String get positionKey => '$itemId|$batchId';

  bool isExpiredOn(DateTime referenceUtc) => DisposalExpiryPolicy.isExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  /// Whole operational days since expiry, as an `int` (see [DisposalCandidate]).
  int daysExpiredOn(DateTime referenceUtc) => DisposalExpiryPolicy.daysExpired(
    expiryDate: expiryDate,
    nowUtc: referenceUtc,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisposalLine &&
          other.id == id &&
          other.qty == qty &&
          other.note == note);

  @override
  int get hashCode => Object.hash(id, qty, note);

  @override
  String toString() => 'DisposalLine($sku, $batchNo, ${qty.format()} $unit)';
}

/// One line as the integrity checks see it: identifiers and a quantity, no joined
/// master data at all.
///
/// Deliberately not [DisposalLine]: that model's item name, batch number and
/// expiry date come from joins, and a join is exactly what can make a broken
/// reference *disappear* instead of reporting it. The set integrity check compares
/// these ids against the joined read, so a line whose item row is gone shows up as
/// a difference rather than as one fewer line (§23).
class DisposalLineReference {
  const DisposalLineReference({
    required this.id,
    required this.disposalId,
    required this.itemId,
    required this.batchId,
    required this.qty,
    this.note,
  });

  final String id;
  final String disposalId;
  final String itemId;
  final String batchId;
  final Quantity qty;
  final String? note;

  bool get hasNote => (note ?? '').trim().isNotEmpty;

  /// `item|batch` — the grain the source balance is held at, and the grain the
  /// partial unique index uses. They are the same here because a disposal draws
  /// from exactly one location, which is what makes the aggregation in §18
  /// straightforward.
  String get positionKey => '$itemId|$batchId';
}

/// What one disposal document contains, as counters (§32).
///
/// A value object rather than four loose numbers, because *"3 posisi · 2 barang"*
/// and *"posting is allowed"* are questions about the same set of lines, and
/// answering them in two places is how they come to disagree.
class DisposalProgress {
  const DisposalProgress({
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
    required this.stillExpiredCount,
    this.oldestExpiryDate,
  });

  /// Derives the counters from a list of lines.
  ///
  /// [referenceUtc] decides the expiry counter, and it is passed in rather than
  /// read from a clock so a badge and the number beside it are judged against the
  /// same instant (T-7).
  factory DisposalProgress.of(
    Iterable<DisposalLine> lines, {
    required DateTime referenceUtc,
  }) {
    final items = <String>{};
    final batches = <String>{};
    var lineCount = 0;
    var stillExpired = 0;
    DateTime? oldest;
    for (final line in lines) {
      lineCount += 1;
      items.add(line.itemId);
      batches.add(line.batchId);
      if (line.isExpiredOn(referenceUtc)) stillExpired += 1;
      if (oldest == null || DateOnly.isBeforeDate(line.expiryDate, oldest)) {
        oldest = line.expiryDate;
      }
    }
    return DisposalProgress(
      lineCount: lineCount,
      itemCount: items.length,
      batchCount: batches.length,
      stillExpiredCount: stillExpired,
      oldestExpiryDate: oldest,
    );
  }

  final int lineCount;

  /// Distinct items. One item split across two batches is one item and two lines.
  final int itemCount;

  final int batchCount;

  /// Lines whose batch is *still* past its expiry date right now.
  ///
  /// Equal to [lineCount] on every document the use cases produced, and the
  /// inversion is the interesting one: a line that is **not** expired must not be
  /// on a disposal at all, so `stillExpiredCount < lineCount` is a document that
  /// cannot post, and the screen says so rather than letting the posting be the
  /// first thing to notice.
  final int stillExpiredCount;

  /// The earliest expiry date on the document — the risk headline (§32).
  final DateTime? oldestExpiryDate;

  bool get isEmpty => lineCount == 0;

  /// Whether every line still qualifies. False means something drifted, which is a
  /// state the posting refuses.
  bool get allStillExpired => stillExpiredCount == lineCount;

  /// `3 posisi · 2 barang` — the label the list row and the detail header show.
  String get label => '$lineCount posisi · $itemCount barang';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisposalProgress &&
          other.lineCount == lineCount &&
          other.itemCount == itemCount &&
          other.batchCount == batchCount &&
          other.stillExpiredCount == stillExpiredCount &&
          other.oldestExpiryDate == oldestExpiryDate);

  @override
  int get hashCode => Object.hash(
    lineCount,
    itemCount,
    batchCount,
    stillExpiredCount,
    oldestExpiryDate,
  );

  @override
  String toString() => 'DisposalProgress($label)';
}

/// A header plus the names a list row needs, without a second query.
///
/// The `…IsHistorical` flags exist so a screen can *say* that a document rests on
/// master data that has since been deactivated or archived. They are never a reason
/// to hide the row: a disposal whose source room was retired afterwards is exactly
/// the document whose history still has to be readable (§34).
class DisposalSummary {
  const DisposalSummary({
    required this.disposal,
    required this.source,
    this.branchCode,
    this.branchName,
    this.roomCode,
    this.roomName,
    required this.createdByName,
    this.postedByName,
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
    this.sourceIsHistorical = false,
    this.branchIsHistorical = false,
    this.roomIsHistorical = false,
    this.createdByIsHistorical = false,
    this.postedByIsHistorical = false,
  });

  final Disposal disposal;

  final DisposalSourceLocation source;

  /// Null for Warehouse Pusat, which belongs to no branch.
  final String? branchCode;
  final String? branchName;

  /// Null unless the source is a room.
  final String? roomCode;
  final String? roomName;

  final String createdByName;

  /// Null exactly while the document is a draft.
  final String? postedByName;

  final int lineCount;
  final int itemCount;
  final int batchCount;

  final bool sourceIsHistorical;
  final bool branchIsHistorical;
  final bool roomIsHistorical;
  final bool createdByIsHistorical;
  final bool postedByIsHistorical;

  String get id => disposal.id;

  String get docNumber => disposal.docNumber;

  String get sourceLocationId => disposal.sourceLocationId;

  DisposalStatus get status => disposal.status;

  bool get usesHistoricalMaster =>
      sourceIsHistorical ||
      branchIsHistorical ||
      roomIsHistorical ||
      createdByIsHistorical ||
      postedByIsHistorical;

  /// `Gudang Cabang Kemang` or `Ruangan R1 · Cabang Kemang` — where the goods
  /// physically were, in one line.
  String get sourceLabel {
    final branch = branchName;
    if (branch == null) return source.name;
    return '${source.name} · $branch';
  }

  /// `3 posisi · 2 barang`, from the counts SQL aggregated rather than from the
  /// lines, so a list row costs one query.
  String get label => '$lineCount posisi · $itemCount barang';
}

/// Everything the form and the posted detail need about one disposal.
class DisposalDetail {
  const DisposalDetail({required this.summary, required this.lines});

  final DisposalSummary summary;
  final List<DisposalLine> lines;

  Disposal get disposal => summary.disposal;

  String get id => disposal.id;

  String get sourceLocationId => disposal.sourceLocationId;

  DisposalSourceLocation get source => summary.source;

  DisposalStatus get status => disposal.status;

  bool get isDraft => disposal.isDraft;

  bool get isPosted => disposal.isPosted;

  bool get isEditable => disposal.isEditable;

  bool get isFinal => disposal.isFinal;

  bool get isEmpty => lines.isEmpty;

  int get lineCount => lines.length;

  int get itemCount => lines.map((line) => line.itemId).toSet().length;

  /// All three halves of the posting precondition: the document is `draft`, it
  /// carries at least one line, **and** it has a reason G-E7 would accept. The use
  /// case remains the authority; this is what the button asks.
  bool get canPost =>
      disposal.canPost && lines.isNotEmpty && disposal.hasReason;

  /// The lines in risk order — oldest expiry first, then item, then batch.
  ///
  /// The same order the DAO produces, restated here so an in-memory list built by
  /// a test or a form is ordered identically.
  List<DisposalLine> get orderedLines {
    final ordered = [...lines]..sort(_compare);
    return List<DisposalLine>.unmodifiable(ordered);
  }

  /// Total quantity of one exact position — item plus batch. This is what §18
  /// compares against the source balance.
  Quantity totalForPosition({
    required String itemId,
    required String batchId,
  }) => Quantity.sum(
    lines
        .where((line) => line.itemId == itemId && line.batchId == batchId)
        .map((line) => line.qty),
  );

  /// Totals grouped by unit.
  ///
  /// Quantities of different units are never added together: `2 box` and `3 pcs`
  /// are not `5` of anything, and one headline number would mislead.
  Map<String, Quantity> get totalQuantityByUnit {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.unit] = (totals[line.unit] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  DisposalProgress progressOn(DateTime referenceUtc) =>
      DisposalProgress.of(lines, referenceUtc: referenceUtc);

  bool get usesHistoricalMaster =>
      summary.usesHistoricalMaster ||
      lines.any((line) => line.usesHistoricalMaster);

  static int _compare(DisposalLine a, DisposalLine b) {
    final byExpiry = DateOnly.compare(a.expiryDate, b.expiryDate);
    if (byExpiry != 0) return byExpiry;
    final byItem = a.itemName.compareTo(b.itemName);
    if (byItem != 0) return byItem;
    final byBatch = a.batchNo.compareTo(b.batchNo);
    if (byBatch != 0) return byBatch;
    return a.id.compareTo(b.id);
  }
}

/// One position as the form holds it before it is saved — a candidate plus the
/// quantity typed against it.
///
/// A value object rather than a loose `(candidate, qty)` pair, because the two
/// questions the form asks of it — *may this be saved?* and *what is left on the
/// shelf afterwards?* — are the same arithmetic the use case performs, and
/// deriving them in the widget is how the two come to disagree.
class DisposalDraft {
  const DisposalDraft({
    required this.candidate,
    required this.qty,
    this.lineId,
    this.note,
  });

  final DisposalCandidate candidate;

  /// What the user wants destroyed. May be zero while they are still typing, which
  /// is exactly why [isValid] exists.
  final Quantity qty;

  /// Id of the `disposal_lines` row when this position is already stored; `null`
  /// for one the picker has just proposed.
  final String? lineId;

  final String? note;

  bool get isStored => lineId != null;

  String get positionKey => candidate.positionKey;

  String get unit => candidate.unit;

  Quantity get availableQty => candidate.availableQty;

  /// Whether the selected quantity exceeds what the shelf holds — what the form
  /// greys the save button out on, and what the use case refuses (§18).
  bool get exceedsAvailable => qty > candidate.availableQty;

  /// Whether the whole of the position is being destroyed. Legitimate, and common:
  /// an expired batch usually goes in its entirety.
  bool get isFullDisposal => qty == candidate.availableQty;

  /// Whether only part of it is (§9: *"Partial disposal diperbolehkan"*).
  bool get hasPartialDisposal => qty.isPositive && qty < candidate.availableQty;

  /// What stays on the shelf afterwards. Never negative — a request that would
  /// make it so is refused rather than clamped, so the number a screen shows and
  /// the number the ledger would produce are the same.
  Quantity get remainingAfterDisposal {
    final remaining = candidate.availableQty - qty;
    return remaining.isNegative ? Quantity.zero() : remaining;
  }

  /// Whether this draft could be stored as it stands.
  bool get isValid => qty.isPositive && !exceedsAvailable;

  DisposalDraft copyWith({
    Quantity? qty,
    Object? note = _unset,
    Object? lineId = _unset,
  }) => DisposalDraft(
    candidate: candidate,
    qty: qty ?? this.qty,
    lineId: lineId == _unset ? this.lineId : lineId as String?,
    note: note == _unset ? this.note : note as String?,
  );

  /// Sentinel so `copyWith(note: null)` can mean "clear it" rather than "keep the
  /// current value".
  static const Object _unset = Object();

  @override
  String toString() =>
      'DisposalDraft(${candidate.sku}, ${candidate.batchNo}, ${qty.format()})';
}

/// One movement the posting will write — one line, resolved against the source.
///
/// Produced by `DisposalStockPlanBuilder` from the stored lines plus the source
/// location the use case resolved, so the posting service never resolves a location
/// itself and no caller can nominate one.
class DisposalPostingEntry {
  const DisposalPostingEntry({
    required this.lineId,
    required this.itemId,
    required this.batchId,
    required this.qty,
    this.note,
  });

  final String lineId;
  final String itemId;
  final String batchId;
  final Quantity qty;

  /// The deterministic movement note — header reason plus the line's own detail,
  /// composed once by the plan builder so the ledger text cannot differ between
  /// two callers (§19).
  final String? note;

  String get sourceKey => '$itemId|$batchId';

  @override
  String toString() =>
      'DisposalPostingEntry($itemId, $batchId, ${qty.format()})';
}

/// Everything one posting needs, validated and resolved, before the first movement
/// is written (§21).
///
/// Building the whole plan first is what makes the atomicity rule achievable: the
/// source is resolved, every position aggregated and every balance requirement
/// known before anything is written, so a failure cannot land halfway through a
/// document.
///
/// There is deliberately **no destination anywhere in this class.** A disposal has
/// one leg: stock leaves the source and enters nothing. That is the whole shape of
/// G-E7, and a field that could hold a destination would be a field somebody could
/// fill in.
class DisposalPostingPlan {
  const DisposalPostingPlan({
    required this.disposalId,
    required this.sourceLocationId,
    required this.reason,
    required this.entries,
  });

  final String disposalId;

  /// The single location every entry draws from.
  final String sourceLocationId;

  /// The validated header reason every movement note is built from (G-E7).
  final String reason;

  final List<DisposalPostingEntry> entries;

  bool get isEmpty => entries.isEmpty;

  int get lineCount => entries.length;

  int get itemCount => entries.map((entry) => entry.itemId).toSet().length;

  /// How much the shelf must supply per **source position** — item plus batch.
  ///
  /// The aggregation is the point: the partial unique index already stops one
  /// document holding the same position twice, but the index is not the authority
  /// on a document assembled by two racing devices, and summing costs nothing.
  Map<String, Quantity> get sourceRequirements {
    final totals = <String, Quantity>{};
    for (final entry in entries) {
      totals[entry.sourceKey] =
          (totals[entry.sourceKey] ?? Quantity.zero()) + entry.qty;
    }
    return totals;
  }

  /// The distinct source positions, as `(itemId, batchId)` pairs, in a stable
  /// order — what the balance verification iterates.
  List<({String itemId, String batchId})> get sourcePositions {
    final seen = <String>{};
    final positions = <({String itemId, String batchId})>[];
    for (final entry in entries) {
      if (seen.add(entry.sourceKey)) {
        positions.add((itemId: entry.itemId, batchId: entry.batchId));
      }
    }
    return List<({String itemId, String batchId})>.unmodifiable(positions);
  }

  /// Total quantity leaving the system.
  Quantity get totalQty => Quantity.sum(entries.map((entry) => entry.qty));
}

/// Filter state for a disposal list.
class DisposalFilter {
  const DisposalFilter({
    this.sourceLocationId,
    this.statuses = const <DisposalStatus>{},
    this.categoryId,
    this.searchQuery = '',
  });

  /// `null` means every location the caller's *scope* already allows. It never
  /// widens a scope — the DAO ANDs the two — which is why a screen may set it
  /// freely from its own source selector.
  final String? sourceLocationId;

  final Set<DisposalStatus> statuses;

  /// Category chip on the candidate list; `null` means *Semua*.
  final String? categoryId;

  final String searchQuery;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  DisposalFilter copyWith({
    Object? sourceLocationId = _unset,
    Set<DisposalStatus>? statuses,
    Object? categoryId = _unset,
    String? searchQuery,
  }) {
    return DisposalFilter(
      sourceLocationId: sourceLocationId == _unset
          ? this.sourceLocationId
          : sourceLocationId as String?,
      statuses: statuses ?? this.statuses,
      categoryId: categoryId == _unset
          ? this.categoryId
          : categoryId as String?,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisposalFilter &&
          other.sourceLocationId == sourceLocationId &&
          other.categoryId == categoryId &&
          other.searchQuery == searchQuery &&
          other.statuses.length == statuses.length &&
          other.statuses.containsAll(statuses));

  @override
  int get hashCode => Object.hash(
    sourceLocationId,
    categoryId,
    searchQuery,
    Object.hashAllUnordered(statuses),
  );
}

/// Every status a disposal list may show — both of them.
const Set<DisposalStatus> visibleDisposalStatuses = {
  DisposalStatus.draft,
  DisposalStatus.posted,
};
