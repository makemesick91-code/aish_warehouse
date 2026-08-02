import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/enums/app_enums.dart';
import '../domain/models/auth_models.dart';
import '../domain/repositories/auth_repository.dart';

class ProductionAuthGateway implements AuthRepository {
  const ProductionAuthGateway(this.client);

  final supabase.SupabaseClient client;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final session = response.session;
      if (session == null) throw const AuthSessionExpiredFailure();
      return _mapSession(session);
    } on supabase.AuthRetryableFetchException {
      throw const AuthNetworkFailure();
    } on supabase.AuthException catch (error) {
      if (error.code == 'invalid_credentials' || error.statusCode == '400') {
        throw const AuthInvalidCredentialsFailure();
      }
      throw const AuthUnexpectedFailure();
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } on supabase.AuthRetryableFetchException {
      await _clearLocalSession();
      throw const AuthNetworkFailure();
    } on supabase.AuthException {
      await _clearLocalSession();
      throw const AuthUnexpectedFailure();
    }
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final session = client.auth.currentSession;
    if (session == null) return null;
    return _mapSession(session);
  }

  @override
  Future<DomainUserProfile> resolveDomainProfile() async {
    try {
      final response = await client.rpc('get_my_domain_profile');
      final rows = response as List<dynamic>;
      if (rows.isEmpty) throw const AuthIdentityNotLinkedFailure();
      final row = Map<String, dynamic>.from(rows.single as Map);
      final profile = DomainUserProfile(
        id: row['id'] as String,
        fullName: row['full_name'] as String,
        email: row['email'] as String,
        role: UserRole.fromDbValue(row['role'] as String),
        branchId: row['branch_id'] as String?,
        isActive: row['is_active'] as bool,
      );
      if (!profile.isActive) throw const AuthDomainUserInactiveFailure();
      if (profile.role.requiresBranch && profile.branchId == null) {
        throw const AuthDomainUserMissingFailure();
      }
      return profile;
    } on AuthFailure {
      rethrow;
    } on supabase.PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const AuthProfileAccessDeniedFailure();
      }
      throw const AuthUnexpectedFailure();
    } on FormatException {
      throw const AuthDomainUserMissingFailure();
    } on ArgumentError {
      throw const AuthDomainUserMissingFailure();
    } on TypeError {
      throw const AuthDomainUserMissingFailure();
    }
  }

  @override
  Stream<AuthSession?> watchAuthState() => client.auth.onAuthStateChange.map(
    (event) => event.session == null ? null : _mapSession(event.session!),
  );

  Future<void> _clearLocalSession() async {
    try {
      await client.auth.signOut(scope: supabase.SignOutScope.local);
    } on supabase.AuthException {
      // Never replace the original server failure with a second exception from
      // best-effort local cleanup. Presentation state still fails closed.
    }
  }

  AuthSession _mapSession(supabase.Session session) => AuthSession(
    identity: AuthenticatedIdentity(
      id: session.user.id,
      email: session.user.email,
    ),
    expiresAtUtc: session.expiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            session.expiresAt! * 1000,
            isUtc: true,
          ),
  );
}
