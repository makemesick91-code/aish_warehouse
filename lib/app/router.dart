import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/current_user_session.dart';
import 'routes.dart';
import '../features/dashboard/presentation/pages/development_home_page.dart';
import '../features/opname/presentation/pages/opname_form_page.dart';
import '../features/opname/presentation/pages/opname_list_page.dart';
import '../features/opname/presentation/pages/opname_review_detail_page.dart';
import '../features/opname/presentation/pages/opname_review_list_page.dart';

/// Root router.
///
/// Guards read the development session (`CurrentUserSession`). They are an
/// affordance, not the enforcement point: every use case re-checks role and
/// branch against the database, so a route reached by any other means still
/// cannot perform an action the user is not entitled to (G-R1/G-R2).
///
/// When real authentication lands, only [currentSessionProvider] changes; the
/// redirect below keeps working as written.
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

      if (location.startsWith(
        '${AppRoutes.opname}/${AppRoutes.opnameReview}',
      )) {
        return session.canReviewOpname ? null : AppRoutes.opname;
      }
      if (location.startsWith(AppRoutes.opname)) {
        return session.canViewOpname ? null : AppRoutes.home;
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
                builder: (context, state) => OpnameReviewDetailPage(
                  opnameId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.opnameDetail,
            name: AppRoutes.opnameDetailName,
            builder: (context, state) =>
                OpnameFormPage(opnameId: state.pathParameters['id']!),
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
