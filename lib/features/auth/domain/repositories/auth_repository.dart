import '../models/auth_models.dart';

abstract interface class AuthRepository {
  Future<AuthSession> signIn({required String email, required String password});

  Future<void> signOut();

  Future<AuthSession?> restoreSession();

  Future<DomainUserProfile> resolveDomainProfile();

  Stream<AuthSession?> watchAuthState();
}
