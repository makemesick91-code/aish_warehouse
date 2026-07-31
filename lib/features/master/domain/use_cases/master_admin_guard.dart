import '../../../../core/errors/failures.dart';
import '../models/master_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_admin_access_policy.dart';

/// The guard every master and import write runs first (§19).
///
/// ### Reload, always
///
/// The actor is re-read from the database by id on **every** call, and the
/// decision rests on the stored `role` and `is_active` rather than on whatever
/// the session claims. A Super Admin demoted five minutes ago has a session that
/// still says `super_admin`, and this is the layer where that stops mattering
/// (O-8).
///
/// It is a mixin rather than a base class so a use case can also extend whatever
/// else it needs, and so the check is one line at the top of every `call` — which
/// makes an architecture test able to assert that every write use case in this
/// feature has one.
mixin MasterAdminGuard {
  MasterAdminRepository get repository;

  /// Reloads the actor and refuses anyone who is not an **active** Super Admin.
  ///
  /// Returns the stored row, so the caller uses the reloaded actor for the rest
  /// of its work rather than trusting the id it was handed.
  Future<MasterUser> requireSuperAdmin(String actorUserId) async {
    final actor = await repository.adminUserById(actorUserId);
    final decision = MasterAdminAccessPolicy.forWrite(user: actor);
    if (decision.isDenied) {
      // One message for every reason. "Your account was deactivated" and "you are
      // not a Super Admin" are different facts, and telling them apart from the
      // outside turns a form into a way to learn which accounts exist (§37).
      throw const MasterAdminAccessDeniedFailure(
        MasterAdminAccessPolicy.denialMessage,
      );
    }
    return actor!;
  }

  /// Refuses when a guarded write matched no row.
  ///
  /// Every writer in [MasterAdminRepository] returns rows changed, and every
  /// caller checks it here. Zero means the row moved under us — a concurrent
  /// edit, an archive, a status that changed — and treating that as success is
  /// how a screen reports a save that never happened.
  void requireRowsAffected(int rowsAffected, String message) {
    if (rowsAffected > 0) return;
    throw ValidationFailure(message);
  }
}
