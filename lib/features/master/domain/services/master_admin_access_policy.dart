import '../../../../core/enums/app_enums.dart';
import '../models/master_models.dart';

/// Which administration surface is being asked for.
enum MasterAdminRouteKind {
  /// `/master` and every entity list and form under it.
  master,

  /// `/imports` — template download, upload, preview, commit.
  imports,

  /// `/imports/:id` — one audit row.
  importDetail,
}

/// Why a request was refused. Never rendered differently — see [denialMessage].
enum MasterAdminDenialReason { noSession, inactive, role }

/// The outcome of one authorization question.
class MasterAdminAccessDecision {
  const MasterAdminAccessDecision.granted() : reason = null;

  const MasterAdminAccessDecision.denied(this.reason);

  final MasterAdminDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// G-M1, in one place: *Master Data & Template Import hanya dapat diakses role
/// `super_admin`*.
///
/// ### One question, asked at four layers
///
/// The route guard, every provider that reads administration data, every write
/// use case and the repository's guarded writers all call this class rather than
/// comparing roles themselves. That is what makes the four layers agree: a role
/// the guard would refuse is a role the use case refuses, so a provider read
/// directly from a widget test — no route involved — is refused too.
///
/// The guard is the *first* line, not the line. §37 says so and §53 tests it.
///
/// ### The actor is always the stored row
///
/// Every method takes a [MasterUser] the caller re-read from the database by id.
/// A session's claim about its own role is not evidence: `is_active` and `role`
/// can both change under a session that is still open, and an administrator
/// demoted five minutes ago must stop being able to rewrite the item master
/// (O-8). §29 and §33 re-read the actor again inside their own flows, and §33
/// re-checks inside the commit transaction.
///
/// ### What server-side validation this does *not* do
///
/// G-M1's parenthetical asks for *"route guard + validasi server"*. There is no
/// server in this build. This class is the whole of the client-and-local half —
/// route, provider, use case, repository — and the interface a Milestone 12 sync
/// client revalidates behind. Nothing here should be read as a claim that a
/// server has checked anything.
abstract final class MasterAdminAccessPolicy {
  /// The only role that reaches any of it (spec §3.1: *"Kelola cabang, ruangan,
  /// pengguna"* and *"Impor master data via template Excel"* are Super Admin
  /// alone).
  static const UserRole requiredRole = UserRole.superAdmin;

  /// Whether [role] may read or write master administration data at all.
  ///
  /// Note what this is **not**: permission to read master data. Every role reads
  /// items and rooms — a nurse cannot count a shelf otherwise — through
  /// `MasterDataRepository`, whose scope is unchanged by this milestone. What is
  /// Super Admin-only is the *administration* surface: the unfiltered lists, the
  /// historical-usage reads, the writers, and the import module.
  static bool canAdminister(UserRole? role) => role == requiredRole;

  /// Whether [role] may read the import audit (G-M6, §36).
  static bool canReadImportHistory(UserRole? role) => canAdminister(role);

  /// Whether [role] may download a template (G-M2).
  static bool canDownloadTemplate(UserRole? role) => canAdminister(role);

  /// Whether [role] may commit an import (G-M3).
  static bool canCommitImport(UserRole? role) => canAdminister(role);

  /// The decision for a whole section, before any id is known.
  ///
  /// [user] is the **stored** row. `null` means no session, or a session naming
  /// somebody the database no longer has.
  static MasterAdminAccessDecision forSection({
    required MasterUser? user,
    required MasterAdminRouteKind kind,
  }) {
    if (user == null) {
      return const MasterAdminAccessDecision.denied(
        MasterAdminDenialReason.noSession,
      );
    }
    if (!user.isActive) {
      return const MasterAdminAccessDecision.denied(
        MasterAdminDenialReason.inactive,
      );
    }
    if (!canAdminister(user.role)) {
      return const MasterAdminAccessDecision.denied(
        MasterAdminDenialReason.role,
      );
    }
    // Every kind is Super Admin-only, so the switch has nothing to narrow. It is
    // written out rather than collapsed so a seventh surface added later has to
    // decide rather than inherit.
    return switch (kind) {
      MasterAdminRouteKind.master ||
      MasterAdminRouteKind.imports ||
      MasterAdminRouteKind.importDetail =>
        const MasterAdminAccessDecision.granted(),
    };
  }

  /// The decision for one write, taken against the re-read actor (§19).
  static MasterAdminAccessDecision forWrite({required MasterUser? user}) =>
      forSection(user: user, kind: MasterAdminRouteKind.master);

  /// The one sentence every refusal shows, whichever reason fired.
  ///
  /// Deliberately identical for all three. "Your account was deactivated", "you
  /// are not a Super Admin" and "there is no session" are different facts, and
  /// telling them apart from the outside is how a screen becomes a way to learn
  /// which accounts exist and what they are.
  static const String denialMessage =
      'Halaman Master Data & Import hanya untuk Super Admin.';
}
