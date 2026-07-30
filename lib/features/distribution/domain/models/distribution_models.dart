import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';

/// Distribusi header, in domain terms.
///
/// Immutable on purpose: a document is never mutated in place. Reads produce a new
/// instance and every write goes through a use case. Quantities are [Quantity],
/// event timestamps are UTC instants (T-1).
class Distribution {
  const Distribution({
    required this.id,
    required this.docNumber,
    required this.branchId,
    required this.distributedBy,
    required this.status,
    this.postedAt,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;

  /// `TMP-DIST-{uuid}` until the sync backend assigns the final number (G-Y4).
  final String docNumber;

  /// The branch whose *Gudang Cabang* the goods leave, and the only branch whose
  /// rooms may receive them (G-T1).
  final String branchId;

  final String distributedBy;
  final DistributionStatus status;

  /// UTC instant; convert through `AppDateTimeFormatter` before displaying.
  final DateTime? postedAt;

  final String? note;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  bool get isDraft => status.isDraft;

  bool get isPosted => status.isPosted;

  /// Only a draft may have its rooms, items, quantities or allocations changed.
  bool get isEditable => status.isEditable;

  bool get isFinal => status.isFinal;

  /// Whether the *status* still permits posting. Says nothing about the lines —
  /// [DistributionDetail.canPost] asks both halves.
  bool get canPost => status.canPost;

  /// Whether the local copy is still waiting to be synchronised (G-Y1).
  bool get isPendingSync => syncStatus == SyncStatus.pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Distribution &&
          other.id == id &&
          other.status == status &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(id, status, updatedAt);

  @override
  String toString() => 'Distribution($docNumber, ${status.dbValue})';
}

/// The smallest fact set that decides whether somebody may open a distribution.
///
/// Deliberately tiny: an authorization check must not be the reason a document's
/// contents are loaded. Nothing here identifies a room, an item, a batch or a
/// quantity — only the owning branch, who distributed and the status.
class DistributionAccessScope {
  const DistributionAccessScope({
    required this.distributionId,
    required this.branchId,
    required this.distributedBy,
    required this.status,
  });

  final String distributionId;
  final String branchId;
  final String distributedBy;
  final DistributionStatus status;
}

/// One distributed position, enriched with everything the form and the posted
/// detail need.
class DistributionLine {
  const DistributionLine({
    required this.id,
    required this.distributionId,
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.qty,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    this.fefoOverrideReason,
    this.roomIsHistorical = false,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
  });

  final String id;
  final String distributionId;

  final String roomId;
  final String roomCode;
  final String roomName;

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;

  /// What this line moves out of the store and into the room. Strictly positive.
  final Quantity qty;

  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  /// Why a batch younger than the FEFO suggestion was chosen (G-E3).
  final String? fefoOverrideReason;

  /// The room, item or batch was deactivated or archived after the line was added.
  /// A **posted** line stays visible — the badge only explains why the row no
  /// longer appears in the pickers (§32). A *draft* line pointing at a
  /// deactivated room is refused at posting, because the physical destination is
  /// not operational.
  final bool roomIsHistorical;
  final bool itemIsHistorical;
  final bool batchIsHistorical;

  /// Whether this position names a batch. True exactly for expiry-tracked items
  /// (G-E2) — the use case enforces both directions.
  bool get isBatched => batchId != null;

  bool get hasFefoOverride => (fefoOverrideReason ?? '').trim().isNotEmpty;

  /// Whether a FEFO reason *could* be required for this position at all.
  ///
  /// Only a batched line can violate FEFO: an item without expiry has no batches
  /// to order. Whether a reason is actually required depends on what the store
  /// holds right now, which no line can see — `DistributionFefoPolicy` decides
  /// that, and the posting re-decides it against fresh balances.
  bool get requiresFefoReason => isBatched;

  bool get usesHistoricalMaster =>
      roomIsHistorical || itemIsHistorical || batchIsHistorical;

  /// The positions this line occupies, as a map key: `room|item|batch`.
  ///
  /// The same grain as the two partial unique indexes, so a duplicate detected in
  /// memory and one refused by the database are the same thing.
  String get positionKey => '$roomId|$itemId|${batchId ?? ''}';

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

  /// Whether the batch's shelf life is below the item's alert threshold (G-E6).
  ///
  /// Already-expired batches answer `false` here: they are a different, stricter
  /// case and [isExpiredOn] is what reports them. Keeping the two apart is what
  /// lets a badge say *kedaluwarsa* rather than *segera kedaluwarsa*.
  bool isNearExpiryOn(DateTime referenceUtc) {
    if (isExpiredOn(referenceUtc)) return false;
    final days = remainingDays(referenceUtc);
    return days != null && days < expiryAlertDays;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DistributionLine &&
          other.id == id &&
          other.qty == qty &&
          other.batchId == batchId &&
          other.fefoOverrideReason == fefoOverrideReason);

  @override
  int get hashCode => Object.hash(id, qty, batchId, fefoOverrideReason);

  @override
  String toString() =>
      'DistributionLine($roomCode, $sku, ${batchNo ?? 'tanpa batch'}, '
      '${qty.format()})';
}

/// Every line of one document that targets the same room (G-T3).
///
/// A value object rather than a loose `Map<String, List<…>>`, because the room
/// header a screen renders — code, name, whether it is historic, the per-unit
/// totals — is the same set of facts in the form, in the posted detail and in the
/// tests, and deriving it three times is how the three come to disagree.
class DistributionRoomGroup {
  const DistributionRoomGroup({
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.lines,
    this.roomIsHistorical = false,
  });

  final String roomId;
  final String roomCode;
  final String roomName;
  final List<DistributionLine> lines;
  final bool roomIsHistorical;

  int get lineCount => lines.length;

  /// Distinct items sent to this room. A single item split across two batches is
  /// one item and two lines.
  int get itemCount => lines.map((line) => line.itemId).toSet().length;

  bool get isEmpty => lines.isEmpty;

  /// Totals grouped by unit.
  ///
  /// Quantities of different units are never added together: `2 box` and `3 pcs`
  /// are not `5` of anything, and one headline number would mislead.
  Map<String, Quantity> get totalsByUnit {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.unit] = (totals[line.unit] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  bool get hasFefoOverride => lines.any((line) => line.hasFefoOverride);
}

/// What one distribution document contains, as counters (§11).
///
/// A value object rather than five loose numbers, because *"3 ruangan · 7 baris"*
/// and *"posting is allowed"* are questions about the same set of lines, and
/// answering them in two places is how they come to disagree.
class DistributionProgress {
  const DistributionProgress({
    required this.roomCount,
    required this.lineCount,
    required this.itemCount,
    required this.overrideCount,
    required this.nearExpiryCount,
    required this.expiredCount,
  });

  /// Derives the counters from a list of lines.
  ///
  /// [referenceUtc] decides the expiry counters, and it is passed in rather than
  /// read from a clock so a badge and the number beside it are judged against the
  /// same instant (T-7).
  factory DistributionProgress.of(
    Iterable<DistributionLine> lines, {
    required DateTime referenceUtc,
  }) {
    final rooms = <String>{};
    final items = <String>{};
    var lineCount = 0;
    var overrideCount = 0;
    var nearExpiry = 0;
    var expired = 0;
    for (final line in lines) {
      lineCount += 1;
      rooms.add(line.roomId);
      items.add(line.itemId);
      if (line.hasFefoOverride) overrideCount += 1;
      if (line.isExpiredOn(referenceUtc)) {
        expired += 1;
      } else if (line.isNearExpiryOn(referenceUtc)) {
        nearExpiry += 1;
      }
    }
    return DistributionProgress(
      roomCount: rooms.length,
      lineCount: lineCount,
      itemCount: items.length,
      overrideCount: overrideCount,
      nearExpiryCount: nearExpiry,
      expiredCount: expired,
    );
  }

  final int roomCount;
  final int lineCount;

  /// Distinct items across every room.
  final int itemCount;

  /// Lines carrying a FEFO override reason (G-E3).
  final int overrideCount;

  /// Lines whose batch is inside its alert window (G-E6).
  final int nearExpiryCount;

  /// Lines whose batch is already expired. Always zero on a document the use
  /// cases produced — G-E4 refuses them on entry and again at posting — so a
  /// non-zero value is a document that must not post, and the screen says so.
  final int expiredCount;

  bool get isEmpty => lineCount == 0;

  bool get hasFefoOverride => overrideCount > 0;

  bool get hasExpiredBatch => expiredCount > 0;

  /// `3 ruangan · 7 baris` — the label the list row and the detail header show.
  String get label => '$roomCount ruangan · $lineCount baris';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DistributionProgress &&
          other.roomCount == roomCount &&
          other.lineCount == lineCount &&
          other.itemCount == itemCount &&
          other.overrideCount == overrideCount &&
          other.nearExpiryCount == nearExpiryCount &&
          other.expiredCount == expiredCount);

  @override
  int get hashCode => Object.hash(
    roomCount,
    lineCount,
    itemCount,
    overrideCount,
    nearExpiryCount,
    expiredCount,
  );

  @override
  String toString() => 'DistributionProgress($label, override $overrideCount)';
}

/// A header plus the names a list row needs, without a second query.
///
/// The `…IsHistorical` flags exist so a screen can *say* that a document rests on
/// master data that has since been deactivated or archived. They are never a
/// reason to hide the row: a distribution whose branch was retired afterwards is
/// exactly the document whose history still has to be readable (§32).
class DistributionSummary {
  const DistributionSummary({
    required this.distribution,
    required this.branchCode,
    required this.branchName,
    this.branchAddress,
    required this.distributedByName,
    required this.lineCount,
    required this.roomCount,
    required this.overrideCount,
    this.branchIsHistorical = false,
    this.distributedByIsHistorical = false,
  });

  final Distribution distribution;

  final String branchCode;
  final String branchName;
  final String? branchAddress;
  final String distributedByName;

  final int lineCount;
  final int roomCount;
  final int overrideCount;

  final bool branchIsHistorical;
  final bool distributedByIsHistorical;

  String get id => distribution.id;

  String get docNumber => distribution.docNumber;

  String get branchId => distribution.branchId;

  DistributionStatus get status => distribution.status;

  bool get usesHistoricalMaster =>
      branchIsHistorical || distributedByIsHistorical;

  /// `3 ruangan · 7 baris`, from the counts SQL aggregated rather than from the
  /// lines, so a list row costs one query.
  String get label => '$roomCount ruangan · $lineCount baris';
}

/// Everything the form and the posted detail need about one distribution.
class DistributionDetail {
  const DistributionDetail({required this.summary, required this.lines});

  final DistributionSummary summary;
  final List<DistributionLine> lines;

  Distribution get distribution => summary.distribution;

  String get id => distribution.id;

  String get branchId => distribution.branchId;

  DistributionStatus get status => distribution.status;

  bool get isDraft => distribution.isDraft;

  bool get isPosted => distribution.isPosted;

  bool get isEditable => distribution.isEditable;

  bool get isFinal => distribution.isFinal;

  bool get isEmpty => lines.isEmpty;

  int get lineCount => lines.length;

  /// Distinct rooms this document targets (G-T3).
  int get roomCount => lines.map((line) => line.roomId).toSet().length;

  /// Both halves of the posting precondition: the document is `draft` **and** it
  /// carries at least one line. The use case remains the authority; this is what
  /// the button asks.
  bool get canPost => distribution.canPost && lines.isNotEmpty;

  /// The lines grouped per room, rooms ordered by code and lines by item name.
  ///
  /// This is the shape both the multi-room form and the posted detail render, and
  /// deriving it here rather than in each screen is what keeps the two showing the
  /// same grouping.
  List<DistributionRoomGroup> get roomGroups {
    final byRoom = <String, List<DistributionLine>>{};
    for (final line in lines) {
      (byRoom[line.roomId] ??= <DistributionLine>[]).add(line);
    }

    final groups = byRoom.entries.map((entry) {
      final roomLines = entry.value
        ..sort((a, b) {
          final byItem = a.itemName.compareTo(b.itemName);
          if (byItem != 0) return byItem;
          return _compareBatches(a, b);
        });
      final first = roomLines.first;
      return DistributionRoomGroup(
        roomId: entry.key,
        roomCode: first.roomCode,
        roomName: first.roomName,
        roomIsHistorical: first.roomIsHistorical,
        lines: List<DistributionLine>.unmodifiable(roomLines),
      );
    }).toList();

    groups.sort((a, b) {
      final byCode = a.roomCode.compareTo(b.roomCode);
      if (byCode != 0) return byCode;
      return a.roomId.compareTo(b.roomId);
    });
    return List<DistributionRoomGroup>.unmodifiable(groups);
  }

  /// Lines of one room, in the same order [roomGroups] produces.
  List<DistributionLine> linesForRoom(String roomId) {
    for (final group in roomGroups) {
      if (group.roomId == roomId) return group.lines;
    }
    return const <DistributionLine>[];
  }

  /// Every line of one item, **across all rooms**.
  ///
  /// This is the grain FEFO compliance is judged at (§16): splitting a younger
  /// batch across two rooms must not make the document look compliant, so the
  /// check is handed the item's whole selection rather than one room's share.
  List<DistributionLine> linesForItem(String itemId) =>
      lines.where((line) => line.itemId == itemId).toList(growable: false);

  /// Every line of one room and item — the positions a batch allocation splits
  /// into.
  List<DistributionLine> linesForPosition({
    required String roomId,
    required String itemId,
  }) => lines
      .where((line) => line.roomId == roomId && line.itemId == itemId)
      .toList(growable: false);

  /// Total quantity of one item across every room.
  Quantity totalForItem(String itemId) =>
      Quantity.sum(linesForItem(itemId).map((line) => line.qty));

  /// Total quantity of one exact source position — item plus batch — across every
  /// room. This is what G-T2 compares against the store's per-batch balance.
  Quantity totalForSourcePosition({
    required String itemId,
    required String? batchId,
  }) => Quantity.sum(
    lines
        .where((line) => line.itemId == itemId && line.batchId == batchId)
        .map((line) => line.qty),
  );

  DistributionProgress progressOn(DateTime referenceUtc) =>
      DistributionProgress.of(lines, referenceUtc: referenceUtc);

  bool get hasFefoOverride => lines.any((line) => line.hasFefoOverride);

  List<DistributionLine> get overrideLines =>
      lines.where((line) => line.hasFefoOverride).toList(growable: false);

  bool get usesHistoricalMaster =>
      summary.usesHistoricalMaster ||
      lines.any((line) => line.usesHistoricalMaster);

  /// Totals grouped by unit, across every room.
  Map<String, Quantity> get totalsByUnit {
    final totals = <String, Quantity>{};
    for (final line in lines) {
      totals[line.unit] = (totals[line.unit] ?? Quantity.zero()) + line.qty;
    }
    return totals;
  }

  static int _compareBatches(DistributionLine a, DistributionLine b) {
    final aExpiry = a.expiryDate;
    final bExpiry = b.expiryDate;
    if (aExpiry != null && bExpiry != null) {
      final byExpiry = DateOnly.compare(aExpiry, bExpiry);
      if (byExpiry != 0) return byExpiry;
    }
    final byBatch = (a.batchNo ?? '').compareTo(b.batchNo ?? '');
    if (byBatch != 0) return byBatch;
    return a.id.compareTo(b.id);
  }
}

/// One batch of an item, with the quantity the branch store currently holds.
///
/// The input the FEFO allocator, the manual batch picker and the posting
/// revalidation all work from. It is a *snapshot*: the allocator reads it while
/// the form is open, and the posting reads it again inside the transaction — the
/// second read is the authority (G-T2).
class DistributionBatchCandidate {
  const DistributionBatchCandidate({
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

  /// The batch row is soft deleted. It still holds real stock, so a draft already
  /// allocated against it may post; it is simply not offered for new allocations.
  final bool isArchived;

  bool isExpiredOn(DateTime referenceUtc) => DateOnly.isBeforeDate(
    expiryDate,
    AppTimeZone.operationalDate(referenceUtc),
  );

  int remainingDays(DateTime referenceUtc) => DateOnly.daysBetween(
    AppTimeZone.operationalDate(referenceUtc),
    expiryDate,
  );

  /// The same candidate with [availableQty] reduced by [taken], floored at zero.
  ///
  /// This is how a document's own earlier allocations are netted out before FEFO
  /// runs again for a second room (§16/§18): the store does not hold the batch
  /// twice, so a second room may only draw what the first left behind.
  DistributionBatchCandidate minus(Quantity taken) {
    final remaining = availableQty - taken;
    return DistributionBatchCandidate(
      batchId: batchId,
      batchNo: batchNo,
      expiryDate: expiryDate,
      availableQty: remaining.isNegative ? Quantity.zero() : remaining,
      isArchived: isArchived,
    );
  }

  @override
  String toString() =>
      'DistributionBatchCandidate($batchNo, '
      'ED ${DateOnly.formatIso(expiryDate)}, ${availableQty.format()})';
}

/// One item the branch store holds, as the picker offers it (§15).
///
/// Only items with something distributable appear: the total below is the sum over
/// **usable** batches for an expiry-tracked item — expired ones excluded (G-E4) —
/// or the single non-batch balance for an item without expiry.
class DistributionStockItem {
  const DistributionStockItem({
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.categoryId,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.availableQty,
    this.candidates = const <DistributionBatchCandidate>[],
    this.expiredCandidates = const <DistributionBatchCandidate>[],
  });

  final String itemId;
  final String sku;
  final String itemName;
  final String categoryId;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;

  /// Distributable stock in the branch store. Strictly positive for every row the
  /// picker shows.
  final Quantity availableQty;

  /// Usable batches, nearest expiry first. **Empty** for an item without expiry —
  /// there is no batch picker to draw (G-E2).
  final List<DistributionBatchCandidate> candidates;

  /// Batches the store holds that may **not** be distributed because they have
  /// expired (G-E4). Carried so the form can explain the difference between "no
  /// stock" and "stock that has to go through disposal" (G-E7) rather than
  /// silently omitting it — and never offered as a choice.
  final List<DistributionBatchCandidate> expiredCandidates;

  int get batchCount => candidates.length;

  bool get hasExpiredStock => expiredCandidates.isNotEmpty;

  /// Nearest usable expiry date, or `null` for an item without expiry.
  DateTime? get nearestExpiryDate =>
      candidates.isEmpty ? null : candidates.first.expiryDate;

  /// Whether any usable batch is inside the item's alert window (G-E6).
  bool hasNearExpiryBatch(DateTime referenceUtc) => candidates.any(
    (candidate) =>
        candidate.remainingDays(referenceUtc) < expiryAlertDays &&
        !candidate.isExpiredOn(referenceUtc),
  );

  @override
  String toString() =>
      'DistributionStockItem($sku, ${availableQty.format()} $unit)';
}

/// One quantity taken from one batch, for one room — the unit the FEFO allocator
/// produces and the form edits.
///
/// `batchId` is null for an item without expiry, which is the only case in which
/// it may be (G-E2).
class DistributionAllocation {
  const DistributionAllocation({
    this.lineId,
    required this.roomId,
    required this.itemId,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    required this.qty,
    this.fefoOverrideReason,
  });

  /// Id of the `distribution_lines` row, when this allocation is already stored.
  /// `null` for one the FEFO allocator has just proposed — which is why the form
  /// addresses a saved allocation by id and a proposed one by position.
  final String? lineId;

  final String roomId;
  final String itemId;
  final String? batchId;
  final String? batchNo;

  /// Civil date — never timezone converted (T-8).
  final DateTime? expiryDate;

  final Quantity qty;
  final String? fefoOverrideReason;

  bool get hasFefoOverride => (fefoOverrideReason ?? '').trim().isNotEmpty;

  bool get isStored => lineId != null;

  /// `room|item|batch` — the same grain as the partial unique indexes.
  String get positionKey => '$roomId|$itemId|${batchId ?? ''}';

  DistributionAllocation copyWith({
    Object? lineId = _unset,
    Object? batchId = _unset,
    Object? batchNo = _unset,
    Object? expiryDate = _unset,
    Quantity? qty,
    Object? fefoOverrideReason = _unset,
  }) {
    return DistributionAllocation(
      lineId: lineId == _unset ? this.lineId : lineId as String?,
      roomId: roomId,
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
    );
  }

  /// Sentinel so `copyWith(batchId: null)` can mean "clear it" rather than "keep
  /// the current value".
  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DistributionAllocation &&
          other.roomId == roomId &&
          other.itemId == itemId &&
          other.batchId == batchId &&
          other.qty == qty &&
          other.fefoOverrideReason == fefoOverrideReason);

  @override
  int get hashCode =>
      Object.hash(roomId, itemId, batchId, qty, fefoOverrideReason);

  @override
  String toString() =>
      'DistributionAllocation($roomId, $itemId, '
      '${batchNo ?? batchId ?? 'tanpa batch'}, ${qty.format()})';
}

/// The allocations of one (room, item) position, as the form holds them before
/// they are saved.
///
/// A draft is per **room and item** rather than per stored line, because a single
/// position may split across batches and the rules that matter — the store balance
/// (G-T2) and the FEFO order (G-E3) — are evaluated over the whole group rather
/// than over one row of it.
class DistributionDraft {
  const DistributionDraft({
    required this.roomId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.unit,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.availableQty,
    required this.allocations,
    this.candidates = const <DistributionBatchCandidate>[],
  });

  final String roomId;
  final String itemId;
  final String sku;
  final String itemName;
  final String unit;
  final bool hasExpiry;
  final int expiryAlertDays;

  /// Branch-store stock this position may draw on, **net of what the rest of the
  /// document already takes** from the same batches (§16/§18). Carried explicitly
  /// rather than derived from [candidates], because the two kinds of item answer
  /// the question from different rows and a derived getter would quietly report
  /// zero for every item without expiry.
  final Quantity availableQty;

  /// Batches still available to this position, nearest expiry first. **Empty** for
  /// an item without expiry — there is no batch picker to draw (G-E2).
  final List<DistributionBatchCandidate> candidates;

  final List<DistributionAllocation> allocations;

  Quantity get totalQty =>
      Quantity.sum(allocations.map((allocation) => allocation.qty));

  bool get isEmpty => allocations.isEmpty;

  bool get hasFefoOverride =>
      allocations.any((allocation) => allocation.hasFefoOverride);

  /// Whether the selected total exceeds what the store can supply — what the form
  /// greys the save button out on, and what the use case refuses (G-T2).
  bool get exceedsAvailable => totalQty > availableQty;

  DistributionDraft copyWith({List<DistributionAllocation>? allocations}) =>
      DistributionDraft(
        roomId: roomId,
        itemId: itemId,
        sku: sku,
        itemName: itemName,
        unit: unit,
        hasExpiry: hasExpiry,
        expiryAlertDays: expiryAlertDays,
        availableQty: availableQty,
        candidates: candidates,
        allocations: allocations ?? this.allocations,
      );
}

/// One line as the integrity checks see it: identifiers and a quantity, no joined
/// master data at all.
///
/// Deliberately not [DistributionLine]: that model's room name, item name and
/// expiry date come from joins, and a join is exactly what can make a broken
/// reference *disappear* instead of reporting it. The set integrity check compares
/// these ids against the joined read, so a line whose room row is gone shows up as
/// a difference rather than as one fewer line (§22).
class DistributionLineReference {
  const DistributionLineReference({
    required this.id,
    required this.distributionId,
    required this.roomId,
    required this.itemId,
    this.batchId,
    required this.qty,
    this.fefoOverrideReason,
  });

  final String id;
  final String distributionId;
  final String roomId;
  final String itemId;
  final String? batchId;
  final Quantity qty;
  final String? fefoOverrideReason;

  bool get isBatched => batchId != null;

  bool get hasFefoOverride => (fefoOverrideReason ?? '').trim().isNotEmpty;

  String get positionKey => '$roomId|$itemId|${batchId ?? ''}';

  /// `item|batch` — the grain the *source* balance is held at. Two rooms drawing
  /// on the same batch share one of these, which is exactly why G-T2 has to
  /// aggregate before it compares.
  String get sourceKey => '$itemId|${batchId ?? ''}';
}

/// One movement the posting will write — one line, resolved to real locations.
///
/// Produced by `DistributionStockPlanBuilder` from the stored lines plus the
/// locations resolved by type, so the posting service never resolves a location
/// itself and no caller can nominate one.
class DistributionPostingEntry {
  const DistributionPostingEntry({
    required this.lineId,
    required this.roomId,
    required this.destinationLocationId,
    required this.itemId,
    this.batchId,
    required this.qty,
  });

  final String lineId;
  final String roomId;

  /// The `room` stock location of [roomId], resolved by type (§14).
  final String destinationLocationId;

  final String itemId;
  final String? batchId;
  final Quantity qty;

  String get sourceKey => '$itemId|${batchId ?? ''}';

  @override
  String toString() =>
      'DistributionPostingEntry($roomId, $itemId, '
      '${batchId ?? 'tanpa batch'}, ${qty.format()})';
}

/// Everything one posting needs, validated and resolved, before the first movement
/// is written (§20).
///
/// Building the whole plan first is what makes G-T4 achievable: every location is
/// resolved, every position aggregated and every balance requirement known before
/// anything is written, so a failure cannot land halfway through a document.
class DistributionPostingPlan {
  const DistributionPostingPlan({
    required this.distributionId,
    required this.branchId,
    required this.sourceLocationId,
    required this.entries,
  });

  final String distributionId;
  final String branchId;

  /// The single *Gudang Cabang* every entry draws from (G-T1).
  final String sourceLocationId;

  final List<DistributionPostingEntry> entries;

  bool get isEmpty => entries.isEmpty;

  int get lineCount => entries.length;

  int get roomCount => entries.map((entry) => entry.roomId).toSet().length;

  /// How much the store must supply per **source position** — item plus batch.
  ///
  /// The aggregation is the whole point of G-T2: two rooms each taking `3` from a
  /// batch holding `5` must fail, and checking them one line at a time would let
  /// both pass.
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

  /// Total quantity leaving the store — the number that must equal the total
  /// arriving in the rooms.
  Quantity get totalQty => Quantity.sum(entries.map((entry) => entry.qty));

  /// The room location each room resolved to, so a caller can verify the
  /// destination balances afterwards without resolving anything again.
  Map<String, String> get destinationLocationsByRoom => {
    for (final entry in entries) entry.roomId: entry.destinationLocationId,
  };
}

/// Filter state for the distribution list.
class DistributionFilter {
  const DistributionFilter({
    this.branchId,
    this.statuses = const <DistributionStatus>{},
    this.searchQuery = '',
  });

  /// `null` means every branch. Nothing in this milestone asks for that — every
  /// distribution screen is branch-scoped (G-R2) — but the field exists because
  /// the later reporting module will.
  final String? branchId;

  final Set<DistributionStatus> statuses;

  final String searchQuery;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  DistributionFilter copyWith({
    Object? branchId = _unset,
    Set<DistributionStatus>? statuses,
    String? searchQuery,
  }) {
    return DistributionFilter(
      branchId: branchId == _unset ? this.branchId : branchId as String?,
      statuses: statuses ?? this.statuses,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DistributionFilter &&
          other.branchId == branchId &&
          other.searchQuery == searchQuery &&
          other.statuses.length == statuses.length &&
          other.statuses.containsAll(statuses));

  @override
  int get hashCode =>
      Object.hash(branchId, searchQuery, Object.hashAllUnordered(statuses));
}

/// Every status a branch head's list may show — both of them.
const Set<DistributionStatus> branchDistributionStatuses = {
  DistributionStatus.draft,
  DistributionStatus.posted,
};
