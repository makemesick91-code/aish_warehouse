import 'package:aish_warehouse/core/config/app_environment.dart';
import 'package:aish_warehouse/core/config/supabase_config.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/core/supabase/supabase_client_provider.dart';
import 'package:aish_warehouse/features/auth/domain/models/auth_models.dart';
import 'package:aish_warehouse/features/auth/presentation/providers/auth_providers.dart';
import 'package:aish_warehouse/features/dashboard/presentation/pages/development_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_fakes.dart';

void main() {
  testWidgets('logout asks confirmation and clears the production session', (
    tester,
  ) async {
    const config = SupabaseConfig(
      environment: AppEnvironment.development,
      enabled: true,
      url: 'http://127.0.0.1:54321',
      publishableKey: 'sb_publishable_test',
    );
    const session = AuthSession(
      identity: AuthenticatedIdentity(id: 'auth-a', email: 'a@example.test'),
      expiresAtUtc: null,
    );
    const profile = DomainUserProfile(
      id: 'domain-a',
      fullName: 'User A',
      email: 'a@example.test',
      role: UserRole.perawat,
      branchId: 'branch-a',
      isActive: true,
    );
    final repository = FakeAuthRepository()
      ..restoredSession = session
      ..profile = profile;
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
        child: const MaterialApp(home: Scaffold(body: ProductionSessionCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('User A'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('logoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('Keluar dari aplikasi?'), findsOneWidget);
    expect(repository.signOutCalls, 0);

    await tester.tap(find.byKey(const ValueKey('confirmLogout')));
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 1);
    expect(container.read(productionSessionProvider), isNull);
    expect(find.text('User A'), findsNothing);
  });
}
