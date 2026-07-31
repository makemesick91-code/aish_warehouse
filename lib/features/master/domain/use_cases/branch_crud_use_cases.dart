import '../../../../core/errors/failures.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_historical_integrity_policy.dart';
import '../services/master_import_normalization_policy.dart';
import 'master_admin_guard.dart';

/// Creates a branch **and the one stock location it must have** (§22).
///
/// ### Why the location is created here and not by a caller
///
/// A branch with no `branch_store` location cannot receive a Good Receipt: the
/// receipt posts against exactly one branch store and refuses to guess (G-G5).
/// Creating the branch and its store in one transaction is what makes "a branch
/// exists" and "a branch can hold stock" the same fact — and it is the same path
/// the import takes (§22), so a branch created by workbook is not subtly
/// different from one created by form.
///
/// Exactly one, never two. [MasterAdminRepository.ensureBranchStoreLocation] is
/// idempotent on the branch, so a retried commit cannot produce a second store.
class CreateBranchUseCase with MasterAdminGuard {
  CreateBranchUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<MasterBranch> call({
    required String actorUserId,
    required String code,
    required String name,
    String? address,
    bool isActive = true,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedCode = MasterImportNormalizationPolicy.text(code);
    final normalizedName = MasterImportNormalizationPolicy.text(name);
    if (normalizedCode.isEmpty) {
      throw const ValidationFailure('Kode cabang wajib diisi.');
    }
    if (normalizedName.isEmpty) {
      throw const ValidationFailure('Nama cabang wajib diisi.');
    }

    return repository.transaction(() async {
      // Inside the transaction, because a check outside it is a fact about a
      // moment that has passed — two devices creating `CAB-01` concurrently is
      // exactly the race this serves.
      final existing = await repository.branchesByCode(normalizedCode);
      if (existing.isNotEmpty) {
        throw MasterNaturalKeyConflictFailure(
          'Kode cabang "$normalizedCode" sudah dipakai. Gunakan kode lain, '
          'atau ubah data cabang yang sudah ada.',
          entity: MasterEntityType.branches,
          naturalKey: normalizedCode,
        );
      }

      final branch = await repository.insertBranch(
        code: normalizedCode,
        name: normalizedName,
        address: MasterImportNormalizationPolicy.optionalText(address),
        isActive: isActive,
      );
      await repository.ensureBranchStoreLocation(
        branchId: branch.id,
        branchName: normalizedName,
      );

      final locations = await repository.branchStoreLocationCount(branch.id);
      if (locations != 1) {
        throw MasterStockLocationIntegrityFailure(
          'Gudang cabang gagal disiapkan untuk cabang ini. Perubahan '
          'dibatalkan.',
          entity: MasterEntityType.branches,
          locationCount: locations,
        );
      }
      return branch;
    });
  }
}

/// Updates a branch's safe fields (§20.5).
///
/// `code` is absent from the signature, not merely unwritten: it is the natural
/// key, and a parameter a caller cannot pass is a rule a caller cannot forget.
///
/// The branch store's **name** follows the branch, and its **id** never moves.
/// That is the whole of §22's rename policy: every balance and every movement
/// keeps pointing at the same location row, so a branch renamed after a year of
/// history is still the same shelf.
class UpdateBranchUseCase with MasterAdminGuard {
  UpdateBranchUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<MasterBranch> call({
    required String actorUserId,
    required String branchId,
    required String name,
    String? address,
    required bool isActive,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedName = MasterImportNormalizationPolicy.text(name);
    if (normalizedName.isEmpty) {
      throw const ValidationFailure('Nama cabang wajib diisi.');
    }

    return repository.transaction(() async {
      final current = await repository.branchById(branchId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Cabang tidak ditemukan.',
          entity: MasterEntityType.branches,
        );
      }

      final rows = await repository.updateBranch(
        id: branchId,
        name: normalizedName,
        address: MasterImportNormalizationPolicy.optionalText(address),
        isActive: isActive,
      );
      requireRowsAffected(
        rows,
        'Cabang gagal diperbarui karena datanya baru saja berubah. Muat ulang '
        'lalu coba lagi.',
      );

      // A rename that leaves the store called *Gudang* + the old name is a shelf
      // labelled with a branch that no longer exists by that name. Renamed
      // atomically with the branch, inside this transaction.
      await repository.renameBranchStoreLocation(
        branchId: branchId,
        branchName: normalizedName,
      );

      return (await repository.branchById(branchId))!;
    });
  }
}

/// Deactivates or reactivates a branch (G-A4).
///
/// **Never deletes, and never touches the branch's stock location.** A
/// deactivated branch keeps its store, its balances and every movement that ever
/// went through it: `is_active` decides what a *new* document may choose, and
/// nothing else. Historical reports still read all of it (§49).
class SetBranchActiveUseCase with MasterAdminGuard {
  SetBranchActiveUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<void> call({
    required String actorUserId,
    required String branchId,
    required bool isActive,
  }) async {
    await requireSuperAdmin(actorUserId);

    await repository.transaction(() async {
      final current = await repository.branchById(branchId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Cabang tidak ditemukan.',
          entity: MasterEntityType.branches,
        );
      }
      final rows = await repository.setBranchActive(
        id: branchId,
        isActive: isActive,
      );
      requireRowsAffected(
        rows,
        'Status cabang gagal diubah. Muat ulang lalu coba lagi.',
      );
    });
  }
}

/// The decisions a branch form needs to render itself (§41).
///
/// Asked of the policy rather than duplicated in the widget, so a field the use
/// case would refuse is a field the form disables — and the reason shown is the
/// reason that would have been thrown.
abstract final class BranchFormPolicy {
  static MasterWriteDecision codeDecision({required bool isCreating}) =>
      isCreating
      ? const MasterWriteDecision.allowed()
      : MasterWriteDecision.refused(
          field: 'code',
          reason: MasterHistoricalIntegrityPolicy.naturalKeyImmutableMessage(
            MasterEntityType.branches,
            'code',
          ),
        );
}
