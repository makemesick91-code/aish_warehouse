import 'dart:async';

import 'package:aish_warehouse/core/config/supabase_config.dart';
import 'package:aish_warehouse/core/supabase/supabase_health_gateway.dart';
import 'package:aish_warehouse/features/auth/domain/models/auth_models.dart';
import 'package:aish_warehouse/features/auth/domain/repositories/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  AuthSession? restoredSession;
  AuthSession? signedInSession;
  DomainUserProfile? profile;
  Object? signInError;
  Object? profileError;
  Object? signOutError;
  Completer<void>? signInGate;
  int signOutCalls = 0;

  final changes = StreamController<AuthSession?>.broadcast();

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    await signInGate?.future;
    if (signInError case final error?) throw error;
    return signedInSession!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (signOutError case final error?) throw error;
    changes.add(null);
  }

  @override
  Future<AuthSession?> restoreSession() async => restoredSession;

  @override
  Future<DomainUserProfile> resolveDomainProfile() async {
    if (profileError case final error?) throw error;
    return profile!;
  }

  @override
  Stream<AuthSession?> watchAuthState() => changes.stream;

  Future<void> dispose() => changes.close();
}

class FakeHealthGateway implements SupabaseHealthGateway {
  FakeHealthGateway({this.compatible = true});

  bool compatible;

  @override
  Future<ServerHealth> check() async => ServerHealth(
    status: 'ok',
    serverTimeUtc: DateTime.utc(2026, 8, 2),
    schemaRevision: compatible
        ? SupabaseConfig.expectedSchemaRevision
        : 'old-revision',
  );
}
