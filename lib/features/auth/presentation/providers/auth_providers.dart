import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client_provider.dart';
import '../../../../core/supabase/supabase_health_gateway.dart';
import '../../../master/domain/models/master_models.dart';
import '../../data/production_auth_gateway.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/use_cases/auth_use_cases.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/sync/sync_providers.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) throw const AuthConfigurationFailure();
  return ProductionAuthGateway(client);
});

final supabaseHealthGatewayProvider = Provider<SupabaseHealthGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) throw const AuthConfigurationFailure();
  return ProductionSupabaseHealthGateway(client);
});

final signInUseCaseProvider = Provider<SignInUseCase>(
  (ref) => SignInUseCase(ref.watch(authRepositoryProvider)),
);
final signOutUseCaseProvider = Provider<SignOutUseCase>(
  (ref) => SignOutUseCase(ref.watch(authRepositoryProvider)),
);
final restoreSessionUseCaseProvider = Provider<RestoreSessionUseCase>(
  (ref) => RestoreSessionUseCase(ref.watch(authRepositoryProvider)),
);
final resolveDomainProfileUseCaseProvider =
    Provider<ResolveDomainProfileUseCase>(
      (ref) => ResolveDomainProfileUseCase(ref.watch(authRepositoryProvider)),
    );
final watchAuthStateUseCaseProvider = Provider<WatchAuthStateUseCase>(
  (ref) => WatchAuthStateUseCase(ref.watch(authRepositoryProvider)),
);

class ProductionAuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final config = ref.watch(supabaseConfigProvider);
    if (!config.enabled) return const AuthAnonymous();

    final authChanges = ref.watch(watchAuthStateUseCaseProvider).call().listen((
      session,
    ) {
      if (session == null) {
        if (state.value is AuthAuthenticated) {
          state = const AsyncData(AuthAnonymous());
        }
        return;
      }
      if (state.value is AuthAuthenticated) {
        unawaited(_revalidateSession(session));
      }
    });
    ref.onDispose(() => unawaited(authChanges.cancel()));
    try {
      final session = await ref.watch(restoreSessionUseCaseProvider).call();
      if (session == null) return const AuthAnonymous();
      return await _authorize(session);
    } on AuthFailure catch (failure) {
      await _signOutRejectedIdentity(failure);
      return AuthRejected(failure);
    } catch (_) {
      return const AuthRejected(AuthUnexpectedFailure());
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        final session = await ref
            .read(signInUseCaseProvider)
            .call(email: email, password: password);
        return await _authorize(session);
      } on AuthFailure catch (failure) {
        await _signOutRejectedIdentity(failure);
        return AuthRejected(failure);
      } catch (_) {
        return const AuthRejected(AuthUnexpectedFailure());
      }
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    try {
      await ref.read(signOutUseCaseProvider).call();
    } on AuthFailure {
      // The gateway clears the device-local session before surfacing a server
      // failure. The UI must still fail closed and forget the old actor.
    } finally {
      state = const AsyncData(AuthAnonymous());
    }
  }

  /// Refreshes role, branch and active status from the server without trusting
  /// the profile already held in memory. Called on foreground resume and SDK
  /// session refreshes.
  Future<void> revalidate() async {
    final current = state.value;
    if (current is! AuthAuthenticated) return;
    await _revalidateSession(current.session);
  }

  Future<void> _revalidateSession(AuthSession session) async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _authorize(session));
    } on AuthFailure catch (failure) {
      await _signOutRejectedIdentity(failure);
      state = AsyncData(AuthRejected(failure));
    } catch (_) {
      state = const AsyncData(AuthRejected(AuthUnexpectedFailure()));
    }
  }

  Future<AuthState> _authorize(AuthSession session) async {
    final profile = await ref.read(resolveDomainProfileUseCaseProvider).call();
    final health = await ref.read(supabaseHealthGatewayProvider).check();
    if (!health.isCompatible || health.status != 'ok') {
      throw const AuthServerIncompatibleFailure();
    }
    // Tests can replace Auth and health without constructing the SDK client.
    // Push bootstrap belongs only to a genuine production-client session.
    if (ref.read(supabaseClientProvider) != null) {
      await ref.read(rebuildPendingOutboxProvider).call();
      unawaited(
        ref.read(pushSyncCoordinatorProvider)?.trigger(actorUserId: profile.id),
      );
    }
    return AuthAuthenticated(session: session, profile: profile);
  }

  Future<void> _signOutRejectedIdentity(AuthFailure failure) async {
    if (failure is! AuthIdentityNotLinkedFailure &&
        failure is! AuthDomainUserInactiveFailure &&
        failure is! AuthDomainUserMissingFailure &&
        failure is! AuthProfileAccessDeniedFailure) {
      return;
    }
    try {
      await ref.read(signOutUseCaseProvider).call();
    } on AuthFailure {
      // Authorization is already rejected. Never replace it with logout detail.
    }
  }
}

final authStateProvider =
    AsyncNotifierProvider<ProductionAuthController, AuthState>(
      ProductionAuthController.new,
    );

final currentDomainUserProvider = Provider<DomainUserProfile?>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth.isLoading || auth.hasError) return null;
  final state = auth.value;
  return state is AuthAuthenticated ? state.profile : null;
});

final productionSessionProvider = Provider<CurrentUserSession?>((ref) {
  final profile = ref.watch(currentDomainUserProvider);
  if (profile == null) return null;
  return CurrentUserSession(
    MasterUser(
      id: profile.id,
      fullName: profile.fullName,
      email: profile.email,
      role: profile.role,
      branchId: profile.branchId,
      isActive: profile.isActive,
    ),
  );
});
