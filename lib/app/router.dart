import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/current_user_session.dart';
import '../features/opname/domain/services/opname_access_policy.dart';
import 'guards/opname_route_guard.dart';
import 'routes.dart';
import '../features/dashboard/presentation/pages/development_home_page.dart';
import '../features/opname/presentation/pages/opname_form_page.dart';
import '../features/opname/presentation/pages/opname_list_page.dart';
import '../features/opname/presentation/pages/opname_review_detail_page.dart';
import '../features/opname/presentation/pages/opname_review_list_page.dart';

/// Root router.
///
/// Access is decided in two passes, and both matter.
///
/// The **redirect** below is synchronous and answers only what a role can be
/// asked without touching the database: which sections exist for this user. It
/// runs on every navigation, so it has to stay cheap.
///
/// A section check cannot decide a *document*, though. `/opname/{id}` names a
/// row, and whether that row belongs to the acting user's branch is a question
/// only the database can answer. Typing another branch's id into the address
/// bar passes every role check there is, which is why the two detail routes are
/// wrapped in [OpnameRouteGuard]: it resolves the actor and a four-column,
/// branch-scoped lookup before the page is built at all. Until it says yes,
/// the page does not exist and no document stream has been subscribed —
/// nothing to hide, because nothing was fetched.
///
/// Neither pass is the enforcement point for *writes*. Every use case still
/// re-reads the actor from the database and re-applies G-R1/G-R2/G-R4, so a
/// route reached by any other means still cannot change anything.
///
/// When real authentication lands, only [currentSessionProvider] changes; both
/// passes keep working as written.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    // Re-evaluate the guards whenever the acting user changes.
    refreshListenable: _SessionRefreshListenable(ref),
    redirect: (context, state) {
      final session = ref.read(currentSessionValueProvider);
      // Still loading, or master data has not been seeded: let the page render
      // its own empty state rather than bouncing the user around.
      if (session == null) return null;

      final location = state.matchedLocation;

      // The role rule is [OpnameAccessPolicy]'s, not the router's. Restating
      // it here as `session.canReviewOpname` would be a second copy that has
      // to agree with the guard's by hand — and the two are reached by the
      // same user on the same navigation. `session.user` is the row the
      // session was built from, so this is the same input the guard re-reads.
      OpnameAccess sectionFor(OpnameRouteKind kind) =>
          OpnameAccessPolicy.forSection(user: session.user, kind: kind);

      if (location.startsWith(
        '${AppRoutes.opname}/${AppRoutes.opnameReview}',
      )) {
        return sectionFor(OpnameRouteKind.reviewList).isGranted
            ? null
            : AppRoutes.opname;
      }
      if (location.startsWith(AppRoutes.opname)) {
        return sectionFor(OpnameRouteKind.list).isGranted
            ? null
            : AppRoutes.home;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const DevelopmentHomePage(),
      ),
      GoRoute(
        path: AppRoutes.opname,
        name: AppRoutes.opnameName,
        builder: (context, state) => const OpnameListPage(),
        routes: [
          // Listed first: a literal segment must win over the `:id` pattern.
          GoRoute(
            path: AppRoutes.opnameReview,
            name: AppRoutes.opnameReviewName,
            builder: (context, state) => const OpnameReviewListPage(),
            routes: [
              GoRoute(
                path: AppRoutes.opnameReviewDetail,
                name: AppRoutes.opnameReviewDetailName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return OpnameRouteGuard(
                    kind: OpnameRouteKind.reviewDocument,
                    opnameId: id,
                    builder: (_) => OpnameReviewDetailPage(opnameId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.opnameDetail,
            name: AppRoutes.opnameDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return OpnameRouteGuard(
                kind: OpnameRouteKind.document,
                opnameId: id,
                builder: (_) => OpnameFormPage(opnameId: id),
              );
            },
          ),
        ],
      ),
    ],
  );
});

/// Bridges the session provider to GoRouter's `refreshListenable`, so switching
/// role re-runs the redirect immediately instead of on the next navigation.
class _SessionRefreshListenable extends ChangeNotifier {
  _SessionRefreshListenable(Ref ref) {
    _subscription = ref.listen<CurrentUserSession?>(
      currentSessionValueProvider,
      (_, _) => notifyListeners(),
    );
    ref.onDispose(dispose);
  }

  late final ProviderSubscription<CurrentUserSession?> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
