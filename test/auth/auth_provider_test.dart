import 'dart:async';

import 'package:aish_warehouse/core/config/app_environment.dart';
import 'package:aish_warehouse/core/config/supabase_config.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/supabase/supabase_client_provider.dart';
import 'package:aish_warehouse/features/auth/domain/models/auth_models.dart';
import 'package:aish_warehouse/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_fakes.dart';

const _config = SupabaseConfig(
  environment: AppEnvironment.development,
  enabled: true,
  url: 'http://127.0.0.1:54321',
  publishableKey: 'sb_publishable_test',
);
const _sessionA = AuthSession(
  identity: AuthenticatedIdentity(id: 'auth-a', email: 'a@example.test'),
  expiresAtUtc: null,
);
const _sessionB = AuthSession(
  identity: AuthenticatedIdentity(id: 'auth-b', email: 'b@example.test'),
  expiresAtUtc: null,
);
const _profileA = DomainUserProfile(
  id: 'domain-a',
  fullName: 'User A',
  email: 'a@example.test',
  role: UserRole.perawat,
  branchId: 'branch-a',
  isActive: true,
);

void main() {
  ProviderContainer containerFor(
    FakeAuthRepository repository, {
    FakeHealthGateway? health,
  }) => ProviderContainer(
    overrides: [
      supabaseConfigProvider.overrideWithValue(_config),
      authRepositoryProvider.overrideWithValue(repository),
      supabaseHealthGatewayProvider.overrideWithValue(
        health ?? FakeHealthGateway(),
      ),
    ],
  );

  Future<AuthState> readAuth(ProviderContainer container) async {
    final completer = Completer<AuthState>();
    final subscription = container.listen(
      authStateProvider,
      (_, next) => next.whenData((value) {
        if (!completer.isCompleted) completer.complete(value);
      }),
      fireImmediately: true,
    );
    try {
      return await completer.future;
    } finally {
      subscription.close();
    }
  }

  test(
    'restores an active linked session and resolves fresh profile',
    () async {
      final repository = FakeAuthRepository()
        ..restoredSession = _sessionA
        ..profile = _profileA;
      final container = containerFor(repository);
      addTearDown(container.dispose);
      addTearDown(repository.dispose);

      final state = await readAuth(container);
      expect(state, isA<AuthAuthenticated>());
      expect(container.read(currentDomainUserProvider)?.id, 'domain-a');
    },
  );

  test('no stored session stays anonymous', () async {
    final repository = FakeAuthRepository();
    final container = containerFor(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);

    expect(await readAuth(container), isA<AuthAnonymous>());
  });

  test('login success clears old identity while loading', () async {
    final gate = Completer<void>();
    final repository = FakeAuthRepository()
      ..restoredSession = _sessionA
      ..signedInSession = _sessionB
      ..profile = _profileA
      ..signInGate = gate;
    final container = containerFor(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await readAuth(container);
    expect(container.read(currentDomainUserProvider)?.id, 'domain-a');

    final pending = container
        .read(authStateProvider.notifier)
        .signIn(email: 'b@example.test', password: 'secret');
    await container.pump();
    expect(container.read(authStateProvider).isLoading, isTrue);
    expect(container.read(currentDomainUserProvider), isNull);

    repository.profile = const DomainUserProfile(
      id: 'domain-b',
      fullName: 'User B',
      email: 'b@example.test',
      role: UserRole.warehouse,
      branchId: null,
      isActive: true,
    );
    gate.complete();
    await pending;
    expect(container.read(currentDomainUserProvider)?.id, 'domain-b');
  });

  test('invalid credentials become a safe typed failure', () async {
    final repository = FakeAuthRepository()
      ..signInError = const AuthInvalidCredentialsFailure();
    final container = containerFor(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await readAuth(container);

    await container
        .read(authStateProvider.notifier)
        .signIn(email: 'unknown@example.test', password: 'bad');
    final state = container.read(authStateProvider).value as AuthRejected;
    expect(state.failure, isA<AuthInvalidCredentialsFailure>());
    expect(state.failure.safeMessage, 'Email atau kata sandi tidak sesuai.');
  });

  test('network failure becomes a safe typed failure', () async {
    final repository = FakeAuthRepository()
      ..signInError = const AuthNetworkFailure();
    final container = containerFor(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await readAuth(container);

    await container
        .read(authStateProvider.notifier)
        .signIn(email: 'user@example.test', password: 'secret');
    final state = container.read(authStateProvider).value as AuthRejected;
    expect(state.failure, isA<AuthNetworkFailure>());
    expect(
      state.failure.safeMessage,
      'Tidak dapat terhubung ke server. Periksa koneksi Anda.',
    );
  });

  test('unlinked and inactive identities are signed out and denied', () async {
    for (final failure in <AuthFailure>[
      const AuthIdentityNotLinkedFailure(),
      const AuthDomainUserInactiveFailure(),
    ]) {
      final repository = FakeAuthRepository()
        ..restoredSession = _sessionA
        ..profileError = failure;
      final container = containerFor(repository);

      final state = await readAuth(container);
      expect(state, isA<AuthRejected>());
      expect(repository.signOutCalls, 1);

      container.dispose();
      await repository.dispose();
    }
  });

  test('server revision mismatch fails closed', () async {
    final repository = FakeAuthRepository()
      ..restoredSession = _sessionA
      ..profile = _profileA;
    final container = containerFor(
      repository,
      health: FakeHealthGateway(compatible: false),
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);

    final state = await readAuth(container) as AuthRejected;
    expect(state.failure, isA<AuthServerIncompatibleFailure>());
  });

  test('logout drops current profile and returns anonymous', () async {
    final repository = FakeAuthRepository()
      ..restoredSession = _sessionA
      ..profile = _profileA;
    final container = containerFor(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await readAuth(container);

    await container.read(authStateProvider.notifier).signOut();
    expect(container.read(authStateProvider).value, isA<AuthAnonymous>());
    expect(container.read(currentDomainUserProvider), isNull);
    expect(container.read(productionSessionProvider), isNull);
    expect(repository.signOutCalls, 1);
  });

  test('logout failure still clears the in-memory actor', () async {
    final repository = FakeAuthRepository()
      ..restoredSession = _sessionA
      ..profile = _profileA
      ..signOutError = const AuthNetworkFailure();
    final container = containerFor(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await readAuth(container);

    await container.read(authStateProvider.notifier).signOut();
    expect(container.read(authStateProvider).value, isA<AuthAnonymous>());
    expect(container.read(productionSessionProvider), isNull);
    expect(repository.signOutCalls, 1);
  });

  test(
    'a new authorization reads changed role and branch from server profile',
    () async {
      final repository = FakeAuthRepository()
        ..restoredSession = _sessionA
        ..profile = _profileA;
      final container = containerFor(repository);
      addTearDown(container.dispose);
      addTearDown(repository.dispose);
      await readAuth(container);

      expect(container.read(currentDomainUserProvider)?.role, UserRole.perawat);

      repository.profile = const DomainUserProfile(
        id: 'domain-a',
        fullName: 'User A',
        email: 'a@example.test',
        role: UserRole.kepalaCabang,
        branchId: 'branch-b',
        isActive: true,
      );
      await container.read(authStateProvider.notifier).revalidate();
      expect(
        container.read(currentDomainUserProvider)?.role,
        UserRole.kepalaCabang,
      );
      expect(container.read(currentDomainUserProvider)?.branchId, 'branch-b');
    },
  );

  test('revalidation denies a user deactivated after session issue', () async {
    final repository = FakeAuthRepository()
      ..restoredSession = _sessionA
      ..profile = _profileA;
    final container = containerFor(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await readAuth(container);

    repository.profileError = const AuthDomainUserInactiveFailure();
    await container.read(authStateProvider.notifier).revalidate();

    final state = container.read(authStateProvider).value as AuthRejected;
    expect(state.failure, isA<AuthDomainUserInactiveFailure>());
    expect(container.read(productionSessionProvider), isNull);
    expect(repository.signOutCalls, 1);
  });
}
