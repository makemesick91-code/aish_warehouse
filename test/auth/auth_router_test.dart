import 'package:aish_warehouse/app/app.dart';
import 'package:aish_warehouse/app/router.dart';
import 'package:aish_warehouse/core/config/app_environment.dart';
import 'package:aish_warehouse/core/config/supabase_config.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/core/supabase/supabase_client_provider.dart';
import 'package:aish_warehouse/features/auth/presentation/pages/login_page.dart';
import 'package:aish_warehouse/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_fakes.dart';

void main() {
  testWidgets('anonymous and direct protected URL both stay at login', (
    tester,
  ) async {
    const config = SupabaseConfig(
      environment: AppEnvironment.development,
      enabled: true,
      url: 'http://127.0.0.1:54321',
      publishableKey: 'sb_publishable_test',
    );
    final repository = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        supabaseConfigProvider.overrideWithValue(config),
        authRepositoryProvider.overrideWithValue(repository),
        supabaseHealthGatewayProvider.overrideWithValue(FakeHealthGateway()),
        currentSessionValueProvider.overrideWith(
          (ref) => ref.watch(productionSessionProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AishWarehouseApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    container.read(appRouterProvider).go('/master/users');
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
