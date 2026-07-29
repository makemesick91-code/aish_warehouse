import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/pages/development_home_page.dart';

/// Route paths and names in one place so feature modules never hard-code
/// strings.
abstract final class AppRoutes {
  static const String home = '/';
  static const String homeName = 'home';
}

/// Root router.
///
/// It is provider-scoped on purpose: once authentication lands, the redirect
/// below can read the session provider to guard routes by role, branch and
/// warehouse scope without restructuring anything.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      // No authentication in this milestone; role/branch guards attach here.
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const DevelopmentHomePage(),
      ),
    ],
  );
});
