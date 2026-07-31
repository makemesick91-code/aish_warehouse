import '../../../../core/errors/failures.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';

/// G-M5, and the rule underneath it: *identity is not an attribute, and a
/// denominator is not a label*.
///
/// ### Two different reasons a field is locked
///
/// **Natural keys** ([naturalKeyFields]) are locked from the moment the row
/// exists, used or not. `items.sku` names the item; changing it does not rename
/// an item, it silently makes every document that said `DEN-0001` refer to
/// something else. The supported way to "rename" is the one G-A4 already
/// established: create the new row, deactivate the old one. Both stay readable,
/// and every historic document still resolves to what it actually meant.
///
/// **Historically protected fields** ([protectedFieldsFor]) are locked only
/// *once the row has been referenced*, and that conditional is the whole design.
/// `items.unit` on an item nobody has moved is a typo somebody should be able to
/// fix; `items.unit` on an item with three months of movements is the unit every
/// one of those quantities was counted in, and rewriting it silently reinterprets
/// the ledger. Same column, opposite answers, and the difference is a query.
///
/// ### Why `category_id` is in the protected list
///
/// It looks like a label and it is not: every report in this application groups
/// and subtotals by category (G-L6). Moving a used item to another category
/// rewrites what last quarter's subtotals meant without touching a single
/// movement row. An unused item may be recategorised freely.
///
/// ### `has_expiry` has a rule of its own
///
/// It is protected once used, like the others, and *additionally* refused
/// whenever the item has batches — used or not (§20.2). `has_expiry = false` on an
/// item with batches is a contradiction the schema cannot express: `item_batches`
/// exists only for items that track expiry, and G-E1 makes a batch mandatory on
/// every movement of such an item. An item with orphaned batches would accept
/// movements with no batch and movements with one, and no query could tell which
/// were correct.
///
/// ### One policy, both paths
///
/// The CRUD use cases and the import validator both come here. §23 requires it:
/// a field a form refuses to change is a field a workbook refuses to change, and
/// two copies of this reasoning would be two things to keep in step.
abstract final class MasterHistoricalIntegrityPolicy {
  // --- natural keys ----------------------------------------------------------

  /// The columns that identify a row and may never be edited (§20.1).
  static const Map<MasterEntityType, List<String>> naturalKeyFields = {
    MasterEntityType.branches: ['code'],
    MasterEntityType.rooms: ['branch_id', 'code'],
    MasterEntityType.users: ['email'],
    MasterEntityType.itemCategories: ['name'],
    MasterEntityType.items: ['sku'],
    MasterEntityType.itemBatches: ['item_id', 'batch_no'],
  };

  static bool isNaturalKeyField(MasterEntityType entity, String field) =>
      naturalKeyFields[entity]!.contains(field);

  /// The sentence a form shows beside a read-only identity field (§41).
  static const String naturalKeyImmutableNotice =
      'Kunci identitas tidak dapat diubah setelah dibuat.';

  static String naturalKeyImmutableMessage(
    MasterEntityType entity,
    String field,
  ) =>
      '$naturalKeyImmutableNotice '
      'Untuk mengganti ${entity.naturalKeyLabel.toLowerCase()}, buat data baru '
      'lalu nonaktifkan yang lama.';

  static MasterWriteDecision decideNaturalKeyChange({
    required MasterEntityType entity,
    required String field,
    required String? current,
    required String? next,
  }) {
    if (current == next) return const MasterWriteDecision.allowed();
    return MasterWriteDecision.refused(
      field: field,
      reason: naturalKeyImmutableMessage(entity, field),
    );
  }

  static void ensureNaturalKeyUnchanged({
    required MasterEntityType entity,
    required String field,
    required String? current,
    required String? next,
  }) {
    if (current == next) return;
    throw MasterNaturalKeyImmutableFailure(
      naturalKeyImmutableMessage(entity, field),
      entity: entity,
      field: field,
    );
  }

  // --- historically protected fields -----------------------------------------

  /// The columns a *used* row may no longer change (§20.2 – §20.6).
  ///
  /// Natural keys are deliberately **not** repeated here: they are refused by
  /// [ensureNaturalKeyUnchanged] whether the row is used or not, and listing them
  /// twice would let a future edit relax one list and think it had relaxed both.
  static const Map<MasterEntityType, List<String>> protectedWhenUsed = {
    MasterEntityType.branches: [],
    MasterEntityType.rooms: [],
    MasterEntityType.users: [],
    MasterEntityType.itemCategories: [],
    MasterEntityType.items: ['unit', 'has_expiry', 'category_id'],
    MasterEntityType.itemBatches: ['expiry_date'],
  };

  /// The columns that stay editable however much history a row has.
  ///
  /// A branch that has shipped for a year can still be renamed and re-addressed:
  /// `branches.name` is a label, and no document's meaning depends on which
  /// spelling of *Cabang Kelapa Gading* was current when it was raised. The
  /// document's own `branch_id` is what it means, and that is exactly the column
  /// nothing here can touch.
  static const Map<MasterEntityType, List<String>> alwaysEditable = {
    MasterEntityType.branches: ['name', 'address', 'is_active'],
    MasterEntityType.rooms: ['name', 'is_active'],
    MasterEntityType.users: ['full_name', 'role', 'branch_id', 'is_active'],
    MasterEntityType.itemCategories: [],
    MasterEntityType.items: [
      'name',
      'min_stock_room',
      'min_stock_branch',
      'expiry_alert_days',
      'is_active',
    ],
    MasterEntityType.itemBatches: [],
  };

  static List<String> protectedFieldsFor(MasterEntityType entity) =>
      protectedWhenUsed[entity]!;

  /// Whether [field] on [entity] is locked given [usage].
  static bool isLocked({
    required MasterEntityType entity,
    required String field,
    required MasterHistoricalUsage usage,
  }) {
    if (isNaturalKeyField(entity, field)) return true;
    if (!usage.isUsed) return false;
    return protectedFieldsFor(entity).contains(field);
  }

  static String protectedFieldMessage({
    required MasterEntityType entity,
    required String field,
    required MasterHistoricalUsage usage,
  }) =>
      'Kolom "$field" tidak dapat diubah karena ${entity.label.toLowerCase()} '
      'ini sudah dipakai transaksi (${usage.describe()}). Nonaktifkan data ini '
      'lalu buat data baru bila perlu.';

  static MasterWriteDecision decideProtectedChange({
    required MasterEntityType entity,
    required String field,
    required Object? current,
    required Object? next,
    required MasterHistoricalUsage usage,
  }) {
    if (current == next) return const MasterWriteDecision.allowed();
    if (isNaturalKeyField(entity, field)) {
      return MasterWriteDecision.refused(
        field: field,
        reason: naturalKeyImmutableMessage(entity, field),
        usage: usage,
      );
    }
    if (!usage.isUsed) return const MasterWriteDecision.allowed();
    if (!protectedFieldsFor(entity).contains(field)) {
      return const MasterWriteDecision.allowed();
    }
    return MasterWriteDecision.refused(
      field: field,
      reason: protectedFieldMessage(entity: entity, field: field, usage: usage),
      usage: usage,
    );
  }

  static void ensureProtectedFieldUnchanged({
    required MasterEntityType entity,
    required String field,
    required Object? current,
    required Object? next,
    required MasterHistoricalUsage usage,
  }) {
    final decision = decideProtectedChange(
      entity: entity,
      field: field,
      current: current,
      next: next,
      usage: usage,
    );
    if (decision.isAllowed) return;
    if (isNaturalKeyField(entity, field)) {
      throw MasterNaturalKeyImmutableFailure(
        decision.reason!,
        entity: entity,
        field: field,
      );
    }
    throw MasterHistoricalFieldImmutableFailure(
      decision.reason!,
      entity: entity,
      field: field,
      usage: usage.describe(),
    );
  }

  // --- the whole-row checks --------------------------------------------------

  /// Every refusal an item update would raise, in header order.
  ///
  /// A *list* rather than the first failure, so a form can disable four fields at
  /// once and a preview row can report four reasons rather than making the
  /// operator fix them one upload at a time (§29).
  static List<MasterWriteDecision> decideItemUpdate({
    required MasterItem current,
    required String nextSku,
    required String nextCategoryId,
    required String nextUnit,
    required bool nextHasExpiry,
    required MasterHistoricalUsage usage,
  }) {
    final decisions = <MasterWriteDecision>[
      decideProtectedChange(
        entity: MasterEntityType.items,
        field: 'sku',
        current: current.sku,
        next: nextSku,
        usage: usage,
      ),
      decideProtectedChange(
        entity: MasterEntityType.items,
        field: 'category_id',
        current: current.categoryId,
        next: nextCategoryId,
        usage: usage,
      ),
      decideProtectedChange(
        entity: MasterEntityType.items,
        field: 'unit',
        current: current.unit,
        next: nextUnit,
        usage: usage,
      ),
      decideProtectedChange(
        entity: MasterEntityType.items,
        field: 'has_expiry',
        current: current.hasExpiry,
        next: nextHasExpiry,
        usage: usage,
      ),
    ];

    // The batch rule, which is not about usage at all. An item with batches may
    // not stop tracking expiry however little it has moved: `item_batches` rows
    // for a non-expiry item are rows the rest of the application cannot
    // interpret, and G-E1 would then have no way to say whether a movement
    // needed one.
    if (current.hasExpiry && !nextHasExpiry && usage.hasBatches) {
      decisions.add(
        MasterWriteDecision.refused(
          field: 'has_expiry',
          reason:
              'Barang ini memiliki ${usage.batches} batch, sehingga pelacakan '
              'kedaluwarsa tidak dapat dimatikan. Arsipkan batch-nya terlebih '
              'dahulu bila memang tidak lagi dipakai.',
          usage: usage,
        ),
      );
    }

    return decisions.where((decision) => decision.isRefused).toList();
  }

  static void ensureItemUpdateAllowed({
    required MasterItem current,
    required String nextSku,
    required String nextCategoryId,
    required String nextUnit,
    required bool nextHasExpiry,
    required MasterHistoricalUsage usage,
  }) {
    final refusals = decideItemUpdate(
      current: current,
      nextSku: nextSku,
      nextCategoryId: nextCategoryId,
      nextUnit: nextUnit,
      nextHasExpiry: nextHasExpiry,
      usage: usage,
    );
    if (refusals.isEmpty) return;
    final first = refusals.first;
    if (first.field == 'sku') {
      throw MasterNaturalKeyImmutableFailure(
        first.reason!,
        entity: MasterEntityType.items,
        field: 'sku',
      );
    }
    throw MasterHistoricalFieldImmutableFailure(
      first.reason!,
      entity: MasterEntityType.items,
      field: first.field!,
      usage: usage.describe(),
    );
  }

  /// Every refusal a batch update would raise (§20.3).
  static List<MasterWriteDecision> decideBatchUpdate({
    required MasterBatch current,
    required String nextItemId,
    required String nextBatchNo,
    required DateTime nextExpiryDate,
    required MasterHistoricalUsage usage,
  }) => <MasterWriteDecision>[
    decideProtectedChange(
      entity: MasterEntityType.itemBatches,
      field: 'item_id',
      current: current.itemId,
      next: nextItemId,
      usage: usage,
    ),
    decideProtectedChange(
      entity: MasterEntityType.itemBatches,
      field: 'batch_no',
      current: current.batchNo,
      next: nextBatchNo,
      usage: usage,
    ),
    decideProtectedChange(
      entity: MasterEntityType.itemBatches,
      field: 'expiry_date',
      current: current.expiryDate,
      next: nextExpiryDate,
      usage: usage,
    ),
  ].where((decision) => decision.isRefused).toList();

  static void ensureBatchUpdateAllowed({
    required MasterBatch current,
    required String nextItemId,
    required String nextBatchNo,
    required DateTime nextExpiryDate,
    required MasterHistoricalUsage usage,
  }) {
    final refusals = decideBatchUpdate(
      current: current,
      nextItemId: nextItemId,
      nextBatchNo: nextBatchNo,
      nextExpiryDate: nextExpiryDate,
      usage: usage,
    );
    if (refusals.isEmpty) return;
    final first = refusals.first;
    if (isNaturalKeyField(MasterEntityType.itemBatches, first.field!)) {
      throw MasterNaturalKeyImmutableFailure(
        first.reason!,
        entity: MasterEntityType.itemBatches,
        field: first.field!,
      );
    }
    throw MasterHistoricalFieldImmutableFailure(
      first.reason!,
      entity: MasterEntityType.itemBatches,
      field: first.field!,
      usage: usage.describe(),
    );
  }

  /// Every refusal a room update would raise (§20.4).
  ///
  /// `branch_id` and `code` are both natural-key columns here, so both are
  /// refused unconditionally — a room cannot be moved to another branch even
  /// before it has held anything, because its stock location is already filed
  /// under the branch it was created in (§22).
  static List<MasterWriteDecision> decideRoomUpdate({
    required MasterRoom current,
    required String nextBranchId,
    required String nextCode,
    required MasterHistoricalUsage usage,
  }) => <MasterWriteDecision>[
    decideProtectedChange(
      entity: MasterEntityType.rooms,
      field: 'branch_id',
      current: current.branchId,
      next: nextBranchId,
      usage: usage,
    ),
    decideProtectedChange(
      entity: MasterEntityType.rooms,
      field: 'code',
      current: current.code,
      next: nextCode,
      usage: usage,
    ),
  ].where((decision) => decision.isRefused).toList();

  static void ensureRoomUpdateAllowed({
    required MasterRoom current,
    required String nextBranchId,
    required String nextCode,
    required MasterHistoricalUsage usage,
  }) {
    final refusals = decideRoomUpdate(
      current: current,
      nextBranchId: nextBranchId,
      nextCode: nextCode,
      usage: usage,
    );
    if (refusals.isEmpty) return;
    throw MasterNaturalKeyImmutableFailure(
      refusals.first.reason!,
      entity: MasterEntityType.rooms,
      field: refusals.first.field!,
    );
  }

  /// Whether the `has_expiry = true → false` transition is blocked by batches.
  ///
  /// Exposed on its own because the import validator reports it as a row issue
  /// rather than throwing, and a form disables the switch with it.
  static bool blocksExpiryFlagRemoval({
    required bool currentHasExpiry,
    required bool nextHasExpiry,
    required int batchCount,
  }) => currentHasExpiry && !nextHasExpiry && batchCount > 0;
}
