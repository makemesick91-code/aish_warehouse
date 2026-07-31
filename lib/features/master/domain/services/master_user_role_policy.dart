import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../models/master_models.dart';

/// The role/branch invariant, and the three ways an administrator can lock
/// everybody — including themselves — out (§21).
///
/// ### One invariant, stated once
///
/// Spec §2.1: `branch_id` is *"wajib untuk `perawat` & `kepala_cabang`, NULL
/// untuk `warehouse`/`super_admin`"*. [UserRole.requiresBranch] already encodes
/// which side a role is on; this class is what turns that into a decision the CRUD
/// form, the import validator and the write use cases all take the same way. §23
/// requires exactly that: no rule may differ between the two paths.
///
/// A `warehouse` account with a branch is not a harmless extra field. Every
/// branch-scoped provider in the application reads `users.branch_id`, and one on
/// an unscoped role is a row that makes "which branch is this user in" answerable
/// when the answer is meant to be *none*.
///
/// ### The three safeguards, and why they are separate rules
///
/// * **Last Super Admin.** Deactivating or demoting the only remaining active
///   Super Admin leaves an application nobody can administer, and this build has
///   no backend to recover it from. Refused.
/// * **Self-deactivation.** Refused separately, because it is a different
///   mistake: the system stays administrable, but the person doing the work loses
///   the session they are in the middle of. Two Super Admins exist, so the "last
///   admin" rule would not fire, and the operator would simply vanish from their
///   own screen.
/// * **Self-demotion.** The same mistake by another name — dropping your own
///   `super_admin` role — and it is checked against the *role being written*
///   rather than against the stored one, because a form submits both at once.
///
/// None of the three is about passwords. This schema stores no credential and
/// this build has no authentication backend, so there is no reset to perform and
/// none is faked (§3.5).
abstract final class MasterUserRolePolicy {
  /// Whether [role] requires `users.branch_id` to be set.
  static bool requiresBranch(UserRole role) => role.requiresBranch;

  /// Whether [role] requires `users.branch_id` to be NULL.
  static bool forbidsBranch(UserRole role) => !role.requiresBranch;

  /// Whether a `(role, branchId)` pair is a shape the schema allows.
  static bool isValidPair({
    required UserRole role,
    required String? branchId,
  }) => role.requiresBranch ? branchId != null : branchId == null;

  /// One Indonesian sentence explaining what the role needs.
  static String branchRequirementLabel(UserRole role) => role.requiresBranch
      ? 'Peran ${role.label} wajib memiliki cabang.'
      : 'Peran ${role.label} tidak boleh memiliki cabang.';

  /// Throws when the pair is invalid.
  ///
  /// The one place the rule becomes an exception, so the CRUD use case and the
  /// import commit raise the identical failure with the identical wording.
  static void ensureValidPair({
    required UserRole role,
    required String? branchId,
  }) {
    if (isValidPair(role: role, branchId: branchId)) return;
    throw MasterRoleBranchMismatchFailure(
      branchRequirementLabel(role),
      role: role,
      hasBranch: branchId != null,
    );
  }

  // --- the three safeguards --------------------------------------------------

  /// Whether writing [nextRole]/[nextIsActive] onto [target] would remove the
  /// last active Super Admin.
  ///
  /// [otherActiveSuperAdmins] counts active, non-archived Super Admins **other
  /// than** [target]. Counting is the caller's job because it is a query, and it
  /// has to be run inside the same transaction as the write — a count taken
  /// before the transaction is a fact about a moment that has passed, and two
  /// devices demoting the last two admins concurrently is precisely the race this
  /// rule exists for (§21).
  static bool wouldRemoveLastSuperAdmin({
    required MasterUser target,
    required UserRole nextRole,
    required bool nextIsActive,
    required int otherActiveSuperAdmins,
  }) {
    final wasActiveSuperAdmin =
        target.role == UserRole.superAdmin && target.isActive;
    if (!wasActiveSuperAdmin) return false;
    final staysActiveSuperAdmin =
        nextRole == UserRole.superAdmin && nextIsActive;
    if (staysActiveSuperAdmin) return false;
    return otherActiveSuperAdmins == 0;
  }

  static void ensureNotLastSuperAdmin({
    required MasterUser target,
    required UserRole nextRole,
    required bool nextIsActive,
    required int otherActiveSuperAdmins,
  }) {
    if (!wouldRemoveLastSuperAdmin(
      target: target,
      nextRole: nextRole,
      nextIsActive: nextIsActive,
      otherActiveSuperAdmins: otherActiveSuperAdmins,
    )) {
      return;
    }
    throw const MasterLastSuperAdminFailure(
      'Tidak dapat menonaktifkan atau menurunkan peran Super Admin terakhir. '
      'Buat atau aktifkan Super Admin lain terlebih dahulu.',
    );
  }

  /// Whether the actor is about to deactivate themselves.
  static bool isSelfDeactivation({
    required String actorId,
    required String targetId,
    required bool targetWasActive,
    required bool nextIsActive,
  }) => actorId == targetId && targetWasActive && !nextIsActive;

  /// Whether the actor is about to drop their own Super Admin role.
  static bool isSelfDemotion({
    required String actorId,
    required String targetId,
    required UserRole targetCurrentRole,
    required UserRole nextRole,
  }) =>
      actorId == targetId &&
      targetCurrentRole == UserRole.superAdmin &&
      nextRole != UserRole.superAdmin;

  static void ensureNotSelfLockout({
    required String actorId,
    required MasterUser target,
    required UserRole nextRole,
    required bool nextIsActive,
  }) {
    if (isSelfDeactivation(
      actorId: actorId,
      targetId: target.id,
      targetWasActive: target.isActive,
      nextIsActive: nextIsActive,
    )) {
      throw const MasterSelfDeactivationFailure(
        'Anda tidak dapat menonaktifkan akun Anda sendiri selama sesi ini '
        'aktif. Minta Super Admin lain melakukannya.',
      );
    }
    if (isSelfDemotion(
      actorId: actorId,
      targetId: target.id,
      targetCurrentRole: target.role,
      nextRole: nextRole,
    )) {
      throw const MasterSelfDeactivationFailure(
        'Anda tidak dapat melepas peran Super Admin dari akun Anda sendiri. '
        'Minta Super Admin lain melakukannya.',
      );
    }
  }

  /// Every safeguard at once, in the order a form would hit them.
  ///
  /// Self-lockout is checked before the last-admin rule on purpose: when the
  /// actor *is* the last admin, both fire, and "you cannot do this to your own
  /// account" is the more useful of the two sentences — it names the action they
  /// should take instead.
  static void ensureWriteIsSafe({
    required String actorId,
    required MasterUser target,
    required UserRole nextRole,
    required bool nextIsActive,
    required String? nextBranchId,
    required int otherActiveSuperAdmins,
  }) {
    ensureValidPair(role: nextRole, branchId: nextBranchId);
    ensureNotSelfLockout(
      actorId: actorId,
      target: target,
      nextRole: nextRole,
      nextIsActive: nextIsActive,
    );
    ensureNotLastSuperAdmin(
      target: target,
      nextRole: nextRole,
      nextIsActive: nextIsActive,
      otherActiveSuperAdmins: otherActiveSuperAdmins,
    );
  }
}
