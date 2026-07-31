import '../../../../core/enums/app_enums.dart';
import 'master_models.dart';

/// The six master entities, named from the administration side.
///
/// A **typedef**, not a second enum. [ImportEntity] already answers *which six*,
/// and the master section and the import section must agree about that set down
/// to the natural keys and the archive-column question — a parallel enum would be
/// two lists to keep in step, and the day they drifted the CRUD screen and the
/// importer would disagree about what a room is keyed by.
typedef MasterEntityType = ImportEntity;

/// Where a master row is already referenced, and therefore what may no longer
/// change about it (G-M5, §20).
///
/// Deliberately a *count per source* rather than a bare `bool`. The rule needs
/// the boolean, but the message a Super Admin reads needs to say **why** a field
/// is locked — *"barang ini sudah dipakai di 3 dokumen distribusi dan 12
/// pergerakan stok"* is actionable; *"barang ini sudah dipakai"* invites the
/// operator to go looking.
class MasterHistoricalUsage {
  const MasterHistoricalUsage({
    this.movements = 0,
    this.balances = 0,
    this.opnameLines = 0,
    this.purchaseRequestLines = 0,
    this.deliveryOrderLines = 0,
    this.goodReceiptLines = 0,
    this.distributionLines = 0,
    this.disposalLines = 0,
    this.consumptionLines = 0,
    this.goodsReturnLines = 0,
    this.batches = 0,
    this.items = 0,
    this.rooms = 0,
    this.users = 0,
    this.stockLocations = 0,
  });

  /// A row nothing points at. Named rather than written as
  /// `MasterHistoricalUsage()` at fifteen call sites, so "we checked and found
  /// nothing" reads differently from "we did not check".
  const MasterHistoricalUsage.none()
    : movements = 0,
      balances = 0,
      opnameLines = 0,
      purchaseRequestLines = 0,
      deliveryOrderLines = 0,
      goodReceiptLines = 0,
      distributionLines = 0,
      disposalLines = 0,
      consumptionLines = 0,
      goodsReturnLines = 0,
      batches = 0,
      items = 0,
      rooms = 0,
      users = 0,
      stockLocations = 0;

  /// Ledger rows. The strongest signal there is: a movement is append-only, so a
  /// row it names can never stop having been named (G-A1).
  final int movements;
  final int balances;
  final int opnameLines;
  final int purchaseRequestLines;
  final int deliveryOrderLines;
  final int goodReceiptLines;
  final int distributionLines;
  final int disposalLines;
  final int consumptionLines;
  final int goodsReturnLines;

  /// Master rows that point at this one — batches of an item, items of a
  /// category, rooms of a branch, users of a branch, locations of a branch/room.
  final int batches;
  final int items;
  final int rooms;
  final int users;
  final int stockLocations;

  /// Whether anything in the ledger or any workflow document names this row.
  ///
  /// Master-to-master references (`batches`, `items`, `rooms`, `users`,
  /// `stockLocations`) are deliberately **excluded**: an item that only has a
  /// batch has moved nothing, and locking its `unit` because somebody typed a
  /// batch number would refuse a correction the data still allows. Those counts
  /// drive their own rules — [hasBatches] gates `has_expiry`, [hasDependents]
  /// gates deactivation warnings — rather than this one.
  bool get isUsed =>
      movements > 0 ||
      balances > 0 ||
      opnameLines > 0 ||
      purchaseRequestLines > 0 ||
      deliveryOrderLines > 0 ||
      goodReceiptLines > 0 ||
      distributionLines > 0 ||
      disposalLines > 0 ||
      consumptionLines > 0 ||
      goodsReturnLines > 0;

  bool get hasBatches => batches > 0;

  bool get hasDependents =>
      batches > 0 || items > 0 || rooms > 0 || users > 0 || stockLocations > 0;

  /// How many document lines of any kind name this row.
  int get documentLines =>
      opnameLines +
      purchaseRequestLines +
      deliveryOrderLines +
      goodReceiptLines +
      distributionLines +
      disposalLines +
      consumptionLines +
      goodsReturnLines;

  /// A sentence naming the sources, in a fixed order so the same usage always
  /// reads the same way.
  String describe() {
    final parts = <String>[
      if (movements > 0) '$movements pergerakan stok',
      if (balances > 0) '$balances saldo stok',
      if (opnameLines > 0) '$opnameLines baris opname',
      if (purchaseRequestLines > 0) '$purchaseRequestLines baris permintaan',
      if (deliveryOrderLines > 0) '$deliveryOrderLines baris pengiriman',
      if (goodReceiptLines > 0) '$goodReceiptLines baris penerimaan',
      if (distributionLines > 0) '$distributionLines baris distribusi',
      if (disposalLines > 0) '$disposalLines baris pemusnahan',
      if (consumptionLines > 0) '$consumptionLines baris pemakaian',
      if (goodsReturnLines > 0) '$goodsReturnLines baris retur',
    ];
    if (parts.isEmpty) return 'Belum dipakai transaksi apa pun.';
    return parts.join(' · ');
  }

  MasterHistoricalUsage merge(MasterHistoricalUsage other) =>
      MasterHistoricalUsage(
        movements: movements + other.movements,
        balances: balances + other.balances,
        opnameLines: opnameLines + other.opnameLines,
        purchaseRequestLines: purchaseRequestLines + other.purchaseRequestLines,
        deliveryOrderLines: deliveryOrderLines + other.deliveryOrderLines,
        goodReceiptLines: goodReceiptLines + other.goodReceiptLines,
        distributionLines: distributionLines + other.distributionLines,
        disposalLines: disposalLines + other.disposalLines,
        consumptionLines: consumptionLines + other.consumptionLines,
        goodsReturnLines: goodsReturnLines + other.goodsReturnLines,
        batches: batches + other.batches,
        items: items + other.items,
        rooms: rooms + other.rooms,
        users: users + other.users,
        stockLocations: stockLocations + other.stockLocations,
      );
}

/// Whether one write may proceed, and why not when it may not (§20).
///
/// A value rather than an exception so the *same* decision can drive three
/// surfaces without being thrown three times: the form disables the field, the
/// preview marks the row, and the use case refuses. Only the last one throws.
class MasterWriteDecision {
  const MasterWriteDecision.allowed()
    : isAllowed = true,
      field = null,
      reason = null,
      usage = null;

  const MasterWriteDecision.refused({
    required this.field,
    required this.reason,
    this.usage,
  }) : isAllowed = false;

  final bool isAllowed;

  /// The column that may not change, e.g. `sku`.
  final String? field;

  /// One Indonesian sentence, written for the person looking at the form.
  final String? reason;

  /// Populated when the refusal is a historical one, so a message can name the
  /// documents rather than assert their existence.
  final MasterHistoricalUsage? usage;

  bool get isRefused => !isAllowed;
}

/// One master row as the administration list shows it.
///
/// Wraps the operational model rather than replacing it: [MasterBranch] and the
/// other five are what every existing workflow already reads, and this adds the
/// three facts only the admin screens need — how many children it has, whether it
/// is historic, and how it sorts.
class MasterBranchAdminView {
  const MasterBranchAdminView({
    required this.branch,
    required this.roomCount,
    required this.activeUserCount,
    required this.syncStatus,
    required this.usage,
    required this.updatedAtUtc,
  });

  final MasterBranch branch;
  final int roomCount;
  final int activeUserCount;
  final SyncStatus syncStatus;
  final MasterHistoricalUsage usage;
  final DateTime updatedAtUtc;
}

class MasterRoomAdminView {
  const MasterRoomAdminView({
    required this.room,
    required this.branchCode,
    required this.branchName,
    required this.stockLocationName,
    required this.syncStatus,
    required this.usage,
    required this.updatedAtUtc,
  });

  final MasterRoom room;
  final String branchCode;
  final String branchName;

  /// The room's stock location, or `null` when it has none — which §22 treats as
  /// an integrity problem to surface rather than to hide.
  final String? stockLocationName;
  final SyncStatus syncStatus;
  final MasterHistoricalUsage usage;
  final DateTime updatedAtUtc;
}

class MasterUserAdminView {
  const MasterUserAdminView({
    required this.user,
    this.branchCode,
    this.branchName,
    required this.isSelf,
    required this.syncStatus,
    required this.usage,
    required this.updatedAtUtc,
  });

  final MasterUser user;
  final String? branchCode;
  final String? branchName;

  /// Whether this row is the acting user. Drives the *Anda* badge and the two
  /// self-protection rules of §21.
  final bool isSelf;
  final SyncStatus syncStatus;
  final MasterHistoricalUsage usage;
  final DateTime updatedAtUtc;
}

class MasterCategoryAdminView {
  const MasterCategoryAdminView({
    required this.category,
    required this.isArchived,
    required this.itemCount,
    required this.syncStatus,
    required this.usage,
    required this.updatedAtUtc,
  });

  final MasterCategory category;

  /// `deleted_at IS NOT NULL`. Categories have no `is_active` column, so this is
  /// their only lifecycle signal (§3.6).
  final bool isArchived;
  final int itemCount;
  final SyncStatus syncStatus;
  final MasterHistoricalUsage usage;
  final DateTime updatedAtUtc;
}

class MasterItemAdminView {
  const MasterItemAdminView({
    required this.item,
    required this.categoryName,
    required this.batchCount,
    required this.syncStatus,
    required this.usage,
    required this.updatedAtUtc,
    this.isArchived = false,
  });

  final MasterItem item;
  final String categoryName;
  final int batchCount;
  final SyncStatus syncStatus;
  final MasterHistoricalUsage usage;
  final DateTime updatedAtUtc;
  final bool isArchived;
}

class MasterBatchAdminView {
  const MasterBatchAdminView({
    required this.batch,
    required this.itemSku,
    required this.itemName,
    required this.isArchived,
    required this.syncStatus,
    required this.usage,
    required this.updatedAtUtc,
  });

  final MasterBatch batch;
  final String itemSku;
  final String itemName;

  /// Batches, like categories, have no `is_active` column (§3.6).
  final bool isArchived;
  final SyncStatus syncStatus;
  final MasterHistoricalUsage usage;
  final DateTime updatedAtUtc;
}

/// Counts for one card on the master dashboard (§39).
class MasterEntitySummary {
  const MasterEntitySummary({
    required this.entity,
    required this.activeCount,
    required this.inactiveCount,
    this.lastUpdatedAtUtc,
  });

  final MasterEntityType entity;

  /// Live and usable. For the four entities with `is_active`, that is
  /// `deleted_at IS NULL AND is_active`; for categories and batches it is
  /// `deleted_at IS NULL`.
  final int activeCount;

  /// Deactivated **or** archived — the two "no longer chosen for new work"
  /// states folded into one number, because a card has room for one.
  final int inactiveCount;

  final DateTime? lastUpdatedAtUtc;

  int get totalCount => activeCount + inactiveCount;
}

/// Every card on `/master`, in the order §39 lists them.
class MasterAdminDashboard {
  const MasterAdminDashboard({required this.summaries});

  final List<MasterEntitySummary> summaries;

  MasterEntitySummary? forEntity(MasterEntityType entity) {
    for (final summary in summaries) {
      if (summary.entity == entity) return summary;
    }
    return null;
  }

  int get totalEntities =>
      summaries.fold(0, (sum, summary) => sum + summary.totalCount);
}

/// What a master list is filtered by (§40).
class MasterListFilter {
  const MasterListFilter({
    this.query = '',
    this.includeInactive = false,
    this.categoryId,
    this.branchId,
    this.role,
    this.hasExpiry,
  });

  final String query;

  /// Whether deactivated and archived rows appear. Default false: a list a Super
  /// Admin opens to add something should not be mostly history.
  final bool includeInactive;

  final String? categoryId;
  final String? branchId;
  final UserRole? role;
  final bool? hasExpiry;

  MasterListFilter copyWith({
    String? query,
    bool? includeInactive,
    String? categoryId,
    bool clearCategory = false,
    String? branchId,
    bool clearBranch = false,
    UserRole? role,
    bool clearRole = false,
    bool? hasExpiry,
    bool clearHasExpiry = false,
  }) => MasterListFilter(
    query: query ?? this.query,
    includeInactive: includeInactive ?? this.includeInactive,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    branchId: clearBranch ? null : (branchId ?? this.branchId),
    role: clearRole ? null : (role ?? this.role),
    hasExpiry: clearHasExpiry ? null : (hasExpiry ?? this.hasExpiry),
  );
}
