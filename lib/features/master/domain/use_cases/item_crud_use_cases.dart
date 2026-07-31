import '../../../../core/errors/failures.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_historical_integrity_policy.dart';
import '../services/master_import_normalization_policy.dart';
import 'master_admin_guard.dart';

/// Creates an item.
class CreateItemUseCase with MasterAdminGuard {
  CreateItemUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<MasterItem> call({
    required String actorUserId,
    required String sku,
    required String name,
    required String categoryId,
    required String unit,
    int minStockRoom = 0,
    int minStockBranch = 0,
    bool hasExpiry = false,
    int expiryAlertDays = 30,
    bool isActive = true,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedSku = MasterImportNormalizationPolicy.text(sku);
    final normalizedName = MasterImportNormalizationPolicy.text(name);
    final normalizedUnit = MasterImportNormalizationPolicy.text(unit);
    if (normalizedSku.isEmpty) {
      throw const ValidationFailure('SKU wajib diisi.');
    }
    if (normalizedName.isEmpty) {
      throw const ValidationFailure('Nama barang wajib diisi.');
    }
    if (normalizedUnit.isEmpty) {
      throw const ValidationFailure('Satuan wajib diisi.');
    }
    if (minStockRoom < 0 || minStockBranch < 0 || expiryAlertDays < 0) {
      throw const ValidationFailure(
        'Stok minimum dan ambang peringatan tidak boleh negatif.',
      );
    }

    return repository.transaction(() async {
      final existing = await repository.itemsBySku(normalizedSku);
      if (existing.isNotEmpty) {
        throw MasterNaturalKeyConflictFailure(
          'SKU "$normalizedSku" sudah dipakai. Gunakan SKU lain, atau ubah '
          'barang yang sudah ada.',
          entity: MasterEntityType.items,
          naturalKey: normalizedSku,
        );
      }
      final category = await repository.categoryById(categoryId);
      if (category == null) {
        throw const MasterEntityNotFoundFailure(
          'Kategori tidak ditemukan.',
          entity: MasterEntityType.itemCategories,
        );
      }

      return repository.insertItem(
        sku: normalizedSku,
        name: normalizedName,
        categoryId: categoryId,
        unit: normalizedUnit,
        minStockRoom: minStockRoom,
        minStockBranch: minStockBranch,
        hasExpiry: hasExpiry,
        expiryAlertDays: expiryAlertDays,
        isActive: isActive,
      );
    });
  }
}

/// Updates an item, refusing anything G-M5 protects (§20.2).
///
/// ### Three fields whose editability depends on history
///
/// `unit`, `has_expiry` and `category_id` are editable on an item nobody has
/// moved and locked on one with a ledger behind it. The distinction is a query,
/// not a guess, and it is exactly the distinction that makes this rule useful: a
/// typo in a brand-new item's unit is a typo somebody should fix, while the same
/// column on an item with three months of movements is the denominator every one
/// of those quantities was recorded in.
///
/// `sku` is not a parameter at all — it is the identity (§20.1).
///
/// ### `has_expiry = true → false` has a second rule
///
/// Refused whenever the item has batches, used or not. `item_batches` exists only
/// for items that track expiry, and G-E1 makes a batch mandatory on every movement
/// of such an item; an item with orphaned batches would accept movements with a
/// batch and movements without, and no query could tell which were right.
class UpdateItemUseCase with MasterAdminGuard {
  UpdateItemUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<MasterItem> call({
    required String actorUserId,
    required String itemId,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    required int expiryAlertDays,
    required bool isActive,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedName = MasterImportNormalizationPolicy.text(name);
    final normalizedUnit = MasterImportNormalizationPolicy.text(unit);
    if (normalizedName.isEmpty) {
      throw const ValidationFailure('Nama barang wajib diisi.');
    }
    if (normalizedUnit.isEmpty) {
      throw const ValidationFailure('Satuan wajib diisi.');
    }
    if (minStockRoom < 0 || minStockBranch < 0 || expiryAlertDays < 0) {
      throw const ValidationFailure(
        'Stok minimum dan ambang peringatan tidak boleh negatif.',
      );
    }

    return repository.transaction(() async {
      final current = await repository.itemById(itemId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Barang tidak ditemukan.',
          entity: MasterEntityType.items,
        );
      }
      final category = await repository.categoryById(categoryId);
      if (category == null) {
        throw const MasterEntityNotFoundFailure(
          'Kategori tidak ditemukan.',
          entity: MasterEntityType.itemCategories,
        );
      }

      // Read inside the transaction: usage grows, and a check against a count
      // taken before the transaction would let a movement posted a millisecond
      // ago slip past the rule that exists because of it.
      final usage = await repository.usageForItem(itemId);
      MasterHistoricalIntegrityPolicy.ensureItemUpdateAllowed(
        current: current,
        // The stored SKU is passed, not a parameter: identity does not change
        // here, and passing it explicitly is what lets the policy assert it.
        nextSku: current.sku,
        nextCategoryId: categoryId,
        nextUnit: normalizedUnit,
        nextHasExpiry: hasExpiry,
        usage: usage,
      );

      final rows = await repository.updateItem(
        id: itemId,
        name: normalizedName,
        categoryId: categoryId,
        unit: normalizedUnit,
        minStockRoom: minStockRoom,
        minStockBranch: minStockBranch,
        hasExpiry: hasExpiry,
        expiryAlertDays: expiryAlertDays,
        isActive: isActive,
      );
      requireRowsAffected(
        rows,
        'Barang gagal diperbarui karena datanya baru saja berubah. Muat ulang '
        'lalu coba lagi.',
      );
      return (await repository.itemById(itemId))!;
    });
  }
}

/// Deactivates or reactivates an item (G-A4).
///
/// Always allowed, however much history the item has: `is_active` is precisely
/// the field G-A4 designates for retiring master data, and a deactivated item
/// keeps every movement, balance and document line it ever appeared on.
class SetItemActiveUseCase with MasterAdminGuard {
  SetItemActiveUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<void> call({
    required String actorUserId,
    required String itemId,
    required bool isActive,
  }) async {
    await requireSuperAdmin(actorUserId);

    await repository.transaction(() async {
      final current = await repository.itemById(itemId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Barang tidak ditemukan.',
          entity: MasterEntityType.items,
        );
      }
      final rows = await repository.setItemActive(
        id: itemId,
        isActive: isActive,
      );
      requireRowsAffected(
        rows,
        'Status barang gagal diubah. Muat ulang lalu coba lagi.',
      );
    });
  }
}

/// The decisions an item form needs, so a disabled field and a refused write
/// always agree (§41).
abstract final class ItemFormPolicy {
  /// Every field decision for one item, keyed by column.
  ///
  /// A form asks once and disables what it must; the use case still enforces
  /// every one of them, because a disabled field is a courtesy and not a
  /// boundary (§37).
  static Map<String, MasterWriteDecision> decisionsFor({
    required bool isCreating,
    MasterItem? current,
    MasterHistoricalUsage usage = const MasterHistoricalUsage.none(),
    int batchCount = 0,
  }) {
    if (isCreating) {
      return const <String, MasterWriteDecision>{};
    }
    final decisions = <String, MasterWriteDecision>{
      'sku': MasterWriteDecision.refused(
        field: 'sku',
        reason: MasterHistoricalIntegrityPolicy.naturalKeyImmutableMessage(
          MasterEntityType.items,
          'sku',
        ),
      ),
    };
    if (!usage.isUsed) {
      if (current != null &&
          current.hasExpiry &&
          MasterHistoricalIntegrityPolicy.blocksExpiryFlagRemoval(
            currentHasExpiry: true,
            nextHasExpiry: false,
            batchCount: batchCount,
          )) {
        decisions['has_expiry'] = MasterWriteDecision.refused(
          field: 'has_expiry',
          reason:
              'Barang ini memiliki $batchCount batch, sehingga pelacakan '
              'kedaluwarsa tidak dapat dimatikan.',
        );
      }
      return decisions;
    }
    for (final field in MasterHistoricalIntegrityPolicy.protectedFieldsFor(
      MasterEntityType.items,
    )) {
      decisions[field] = MasterWriteDecision.refused(
        field: field,
        reason: MasterHistoricalIntegrityPolicy.protectedFieldMessage(
          entity: MasterEntityType.items,
          field: field,
          usage: usage,
        ),
        usage: usage,
      );
    }
    return decisions;
  }
}
