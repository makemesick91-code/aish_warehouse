import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_historical_integrity_policy.dart';
import '../services/master_import_normalization_policy.dart';
import '../services/master_user_role_policy.dart';
import 'master_admin_guard.dart';

/// Creates a user account (§3.5, §21).
///
/// ### No password, and none faked
///
/// This schema has no credential column and this build has no authentication
/// backend. The account is a name, an email, a role, a branch and an active flag —
/// which is exactly what every RBAC decision in the application reads. A password
/// field here would be a field that authenticates nothing, and a *"reset akses"*
/// button would be a button that resets nothing; both are deferred to Milestone 12
/// and neither is simulated.
class CreateUserUseCase with MasterAdminGuard {
  CreateUserUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<MasterUser> call({
    required String actorUserId,
    required String fullName,
    required String email,
    required UserRole role,
    String? branchId,
    bool isActive = true,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedName = MasterImportNormalizationPolicy.text(fullName);
    final normalizedEmail = MasterImportNormalizationPolicy.email(email);
    if (normalizedName.isEmpty) {
      throw const ValidationFailure('Nama lengkap wajib diisi.');
    }
    if (normalizedEmail.isEmpty) {
      throw const ValidationFailure('Email wajib diisi.');
    }
    if (!MasterImportNormalizationPolicy.isValidEmail(normalizedEmail)) {
      throw const ValidationFailure(
        'Email tidak valid. Gunakan format nama@domain.',
      );
    }
    // The same policy the import applies (§23) — one rule, not two.
    MasterUserRolePolicy.ensureValidPair(role: role, branchId: branchId);

    return repository.transaction(() async {
      final existing = await repository.usersByEmail(normalizedEmail);
      if (existing.isNotEmpty) {
        throw MasterNaturalKeyConflictFailure(
          'Email "$normalizedEmail" sudah terdaftar. Ubah data pengguna yang '
          'sudah ada, atau gunakan email lain.',
          entity: MasterEntityType.users,
          naturalKey: normalizedEmail,
        );
      }
      if (branchId != null) {
        final branch = await repository.branchById(branchId);
        if (branch == null) {
          throw const MasterEntityNotFoundFailure(
            'Cabang tidak ditemukan.',
            entity: MasterEntityType.branches,
          );
        }
        if (!branch.isActive) {
          throw const MasterDependencyActiveFailure(
            'Cabang ini sedang nonaktif, sehingga pengguna baru tidak dapat '
            'ditempatkan di sana.',
            entity: MasterEntityType.users,
            dependency: 'branch',
          );
        }
      }

      return repository.insertUser(
        fullName: normalizedName,
        // Lower-cased, so the stored value and the natural key are one string and
        // the same person cannot be created twice under two spellings (§16).
        email: normalizedEmail,
        role: role,
        branchId: branchId,
        isActive: isActive,
      );
    });
  }
}

/// Updates a user's role, branch, name and active flag (§20.6, §21).
///
/// `email` is absent from the signature: it is the natural key, and an account
/// whose address changed is a different account. The supported path is a new row
/// and the old one deactivated.
///
/// The three safeguards of §21 are applied **inside** the transaction, and the
/// last-admin count is read there too — a count taken before the transaction is a
/// fact about a moment that has passed, which is exactly what two devices
/// demoting the last two administrators concurrently would exploit.
class UpdateUserUseCase with MasterAdminGuard {
  UpdateUserUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<MasterUser> call({
    required String actorUserId,
    required String userId,
    required String fullName,
    required UserRole role,
    String? branchId,
    required bool isActive,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedName = MasterImportNormalizationPolicy.text(fullName);
    if (normalizedName.isEmpty) {
      throw const ValidationFailure('Nama lengkap wajib diisi.');
    }
    MasterUserRolePolicy.ensureValidPair(role: role, branchId: branchId);

    return repository.transaction(() async {
      final current = await repository.adminUserById(userId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Pengguna tidak ditemukan.',
          entity: MasterEntityType.users,
        );
      }

      if (branchId != null) {
        final branch = await repository.branchById(branchId);
        if (branch == null) {
          throw const MasterEntityNotFoundFailure(
            'Cabang tidak ditemukan.',
            entity: MasterEntityType.branches,
          );
        }
        if (!branch.isActive && branchId != current.branchId) {
          throw const MasterDependencyActiveFailure(
            'Cabang tujuan sedang nonaktif. Aktifkan cabangnya terlebih '
            'dahulu.',
            entity: MasterEntityType.users,
            dependency: 'branch',
          );
        }
      }

      MasterUserRolePolicy.ensureWriteIsSafe(
        actorId: actorUserId,
        target: current,
        nextRole: role,
        nextIsActive: isActive,
        nextBranchId: branchId,
        otherActiveSuperAdmins: await repository.countOtherActiveSuperAdmins(
          userId,
        ),
      );

      final rows = await repository.updateUser(
        id: userId,
        fullName: normalizedName,
        role: role,
        branchId: branchId,
        isActive: isActive,
      );
      requireRowsAffected(
        rows,
        'Pengguna gagal diperbarui karena datanya baru saja berubah. Muat '
        'ulang lalu coba lagi.',
      );

      return (await repository.adminUserById(userId))!;
    });
  }
}

/// Deactivates or reactivates a user (G-A4), with the same three safeguards.
class SetUserActiveUseCase with MasterAdminGuard {
  SetUserActiveUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  Future<void> call({
    required String actorUserId,
    required String userId,
    required bool isActive,
  }) async {
    await requireSuperAdmin(actorUserId);

    await repository.transaction(() async {
      final current = await repository.adminUserById(userId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Pengguna tidak ditemukan.',
          entity: MasterEntityType.users,
        );
      }

      MasterUserRolePolicy.ensureWriteIsSafe(
        actorId: actorUserId,
        target: current,
        // The role is unchanged by this operation; passing the stored one is what
        // makes the last-admin rule see "still a Super Admin, but inactive".
        nextRole: current.role,
        nextIsActive: isActive,
        nextBranchId: current.branchId,
        otherActiveSuperAdmins: await repository.countOtherActiveSuperAdmins(
          userId,
        ),
      );

      final rows = await repository.setUserActive(
        id: userId,
        isActive: isActive,
      );
      requireRowsAffected(
        rows,
        'Status pengguna gagal diubah. Muat ulang lalu coba lagi.',
      );
    });
  }
}

/// The decisions a user form needs (§41).
abstract final class UserFormPolicy {
  static MasterWriteDecision emailDecision({required bool isCreating}) =>
      isCreating
      ? const MasterWriteDecision.allowed()
      : MasterWriteDecision.refused(
          field: 'email',
          reason: MasterHistoricalIntegrityPolicy.naturalKeyImmutableMessage(
            MasterEntityType.users,
            'email',
          ),
        );

  /// Whether the branch field is required, forbidden, or being cleared.
  ///
  /// Read by the form on every role change, so choosing *Petugas Warehouse*
  /// clears and disables the branch picker rather than submitting a pair the use
  /// case would then refuse.
  static bool branchRequiredFor(UserRole role) =>
      MasterUserRolePolicy.requiresBranch(role);

  static String branchHintFor(UserRole role) =>
      MasterUserRolePolicy.branchRequirementLabel(role);

  /// Whether this form may offer to deactivate or demote at all.
  ///
  /// False for the actor's own row: §21 refuses both, and a control that submits
  /// something guaranteed to be refused is a control that should not be there.
  static bool canChangeOwnStatus({
    required String actorId,
    required String targetId,
  }) => actorId != targetId;
}
