import '../../../../core/errors/failures.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_historical_integrity_policy.dart';
import '../services/master_import_normalization_policy.dart';
import 'master_admin_guard.dart';

/// Creates an item category.
///
/// `name` is the whole row and also the natural key (G-M4), which makes this the
/// simplest of the six — and the one where "update" has the least to do. See
/// [UpdateItemCategoryUseCase] for what that means in practice.
class CreateItemCategoryUseCase with MasterAdminGuard {
  CreateItemCategoryUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<MasterCategory> call({
    required String actorUserId,
    required String name,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalized = MasterImportNormalizationPolicy.text(name);
    if (normalized.isEmpty) {
      throw const ValidationFailure('Nama kategori wajib diisi.');
    }

    return repository.transaction(() async {
      final existing = await repository.categoriesByName(normalized);
      if (existing.isNotEmpty) {
        throw MasterNaturalKeyConflictFailure(
          'Kategori "$normalized" sudah ada. Bila kategori tersebut '
          'diarsipkan, pulihkan dari daftar kategori.',
          entity: MasterEntityType.itemCategories,
          naturalKey: normalized,
        );
      }
      return repository.insertCategory(normalized);
    });
  }
}

/// Refreshes a category row without changing its name (§20.7).
///
/// ### Why there is no rename
///
/// A category's name **is** its identity (G-M4), and every report in this
/// application groups and subtotals by category (G-L6). Renaming one would
/// silently rewrite what last quarter's subtotals were subtotals *of*, and no
/// document stores a category name to fall back on — items point at
/// `category_id`, and the name is read live.
///
/// So the supported path is the one §20.7 states: create the new category,
/// reassign the items that have no history yet, and archive the old one. Nothing
/// mass-reassigns items that *do* have history — those items' movements were
/// filed under the old category and that remains true.
///
/// This use case exists for the one legitimate same-name write: restoring an
/// archived category refreshes `updated_at` and the sync status, and that is a
/// change the server has not seen.
class UpdateItemCategoryUseCase with MasterAdminGuard {
  UpdateItemCategoryUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<MasterCategory> call({
    required String actorUserId,
    required String categoryId,
    required String name,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalized = MasterImportNormalizationPolicy.text(name);
    if (normalized.isEmpty) {
      throw const ValidationFailure('Nama kategori wajib diisi.');
    }

    return repository.transaction(() async {
      final current = await repository.categoryById(categoryId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Kategori tidak ditemukan.',
          entity: MasterEntityType.itemCategories,
        );
      }

      // The natural-key rule, applied through the shared policy so the message a
      // form shows and the message this throws are one string (§23).
      MasterHistoricalIntegrityPolicy.ensureNaturalKeyUnchanged(
        entity: MasterEntityType.itemCategories,
        field: 'name',
        current: current.name,
        next: normalized,
      );

      final rows = await repository.updateCategory(
        id: categoryId,
        name: normalized,
      );
      requireRowsAffected(
        rows,
        'Kategori gagal diperbarui. Muat ulang lalu coba lagi.',
      );
      return (await repository.categoryById(categoryId))!;
    });
  }
}

/// Archives a category — `deleted_at = now`, never a delete (§3.6, G-A5).
///
/// Categories carry no `is_active` column, and one was deliberately **not** added
/// to make all six entities look alike: that would be a schema change to every
/// existing row in service of symmetry. `deleted_at` is their lifecycle, and it
/// hides the row from pickers while every item, report and subtotal that ever
/// referenced it still resolves.
///
/// Refused while live items still point at it: an item whose category is archived
/// would render with a category that no picker offers, and the operator should
/// move those items first.
class ArchiveItemCategoryUseCase with MasterAdminGuard {
  ArchiveItemCategoryUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<void> call({
    required String actorUserId,
    required String categoryId,
  }) async {
    await requireSuperAdmin(actorUserId);

    await repository.transaction(() async {
      final current = await repository.categoryById(categoryId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Kategori tidak ditemukan.',
          entity: MasterEntityType.itemCategories,
        );
      }

      final usage = await repository.usageForCategory(categoryId);
      if (usage.items > 0) {
        throw MasterDependencyActiveFailure(
          'Kategori ini masih dipakai oleh ${usage.items} barang. Pindahkan '
          'barang tersebut ke kategori lain terlebih dahulu.',
          entity: MasterEntityType.itemCategories,
          dependency: 'items',
        );
      }

      final rows = await repository.archiveCategory(categoryId);
      requireRowsAffected(
        rows,
        'Kategori gagal diarsipkan — mungkin sudah diarsipkan sebelumnya. '
        'Muat ulang lalu coba lagi.',
      );
    });
  }
}

/// Restores an archived category — `deleted_at = NULL`.
class RestoreItemCategoryUseCase with MasterAdminGuard {
  RestoreItemCategoryUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<void> call({
    required String actorUserId,
    required String categoryId,
  }) async {
    await requireSuperAdmin(actorUserId);

    await repository.transaction(() async {
      final current = await repository.categoryById(categoryId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Kategori tidak ditemukan.',
          entity: MasterEntityType.itemCategories,
        );
      }
      final rows = await repository.restoreCategory(categoryId);
      requireRowsAffected(
        rows,
        'Kategori gagal dipulihkan — mungkin sudah aktif. Muat ulang lalu coba '
        'lagi.',
      );
    });
  }
}

/// The decisions a category form needs (§41).
abstract final class CategoryFormPolicy {
  static MasterWriteDecision nameDecision({required bool isCreating}) =>
      isCreating
      ? const MasterWriteDecision.allowed()
      : MasterWriteDecision.refused(
          field: 'name',
          reason:
              'Nama kategori adalah kunci identitas dan tidak dapat diubah. '
              'Buat kategori baru lalu pindahkan barang yang belum memiliki '
              'riwayat transaksi.',
        );
}
