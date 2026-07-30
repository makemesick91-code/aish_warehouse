/// The single source of "who is acting, and for which branch".
///
/// Before this existed, three layers each worked the answer out for themselves:
/// the router read the session, a route guard re-read the user from the database,
/// and every branch-scoped provider reached into `session?.branchId`. All three
/// happened to agree, which is the dangerous kind of correct — the next
/// branch-scoped screen only has to reach for the session one different way for a
/// document from another branch to become reachable.
///
/// Two providers, with different jobs:
///
/// * [actingUserProvider] is the actor **as the database currently has them**. It
///   is what an authorization decision must rest on, because role, branch and
///   `is_active` can all change under a session that is still open (O-8).
/// * [actingBranchIdProvider] is the synchronous branch key every branch-scoped
///   query and provider uses. It comes from the session's own [MasterUser] — which
///   `DevelopmentSessionController` loaded from the database, never from a
///   hard-coded id — so it is the same fact, available without an `await`.
///
/// Neither is an enforcement point. Every use case re-reads the actor from the
/// repository and re-applies its guards, so a tampered session cannot widen
/// anyone's authority. What these providers buy is that a *read* is scoped
/// correctly the first time, before a foreign document has been fetched.
///
/// **Session switching.** Both watch [currentSessionValueProvider], so changing the
/// acting user rebuilds them, and every provider that depends on them rebuilds in
/// turn. Document providers are additionally `autoDispose`, so a document opened
/// under one session is not still cached under the next one — a stale cache
/// entry is the one way a branch scope can be correct everywhere and still leak.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/master/domain/models/master_models.dart';
import '../../features/master/presentation/providers/master_providers.dart';
import '../enums/app_enums.dart';
import 'current_user_session.dart';

/// The acting user, re-read from the database by id.
///
/// `null` while the session is loading, when master data has not been seeded, or
/// when the session names a user who no longer exists.
final actingUserProvider = FutureProvider<MasterUser?>((ref) async {
  final session = ref.watch(currentSessionValueProvider);
  if (session == null) return null;
  return ref.watch(masterDataRepositoryProvider).userById(session.userId);
});

/// The branch the acting user belongs to, or `null`.
///
/// `null` is a legitimate value, not an error: `warehouse` and `super_admin` are
/// unscoped roles and carry `users.branch_id = NULL` by design (spec §2.1). A
/// branch-scoped provider must therefore treat `null` as "no branch to scope to"
/// and emit nothing, never as "every branch".
final actingBranchIdProvider = Provider<String?>(
  (ref) => ref.watch(currentSessionValueProvider)?.branchId,
);

/// The acting user's role, or `null` while there is no session.
final actingRoleProvider = Provider<UserRole?>(
  (ref) => ref.watch(currentSessionValueProvider)?.role,
);
