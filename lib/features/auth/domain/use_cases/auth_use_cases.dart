import '../models/auth_models.dart';
import '../repositories/auth_repository.dart';

class SignInUseCase {
  const SignInUseCase(this.repository);

  final AuthRepository repository;

  Future<AuthSession> call({required String email, required String password}) =>
      repository.signIn(email: email.trim(), password: password);
}

class SignOutUseCase {
  const SignOutUseCase(this.repository);

  final AuthRepository repository;

  Future<void> call() => repository.signOut();
}

class RestoreSessionUseCase {
  const RestoreSessionUseCase(this.repository);

  final AuthRepository repository;

  Future<AuthSession?> call() => repository.restoreSession();
}

class ResolveDomainProfileUseCase {
  const ResolveDomainProfileUseCase(this.repository);

  final AuthRepository repository;

  Future<DomainUserProfile> call() => repository.resolveDomainProfile();
}

class WatchAuthStateUseCase {
  const WatchAuthStateUseCase(this.repository);

  final AuthRepository repository;

  Stream<AuthSession?> call() => repository.watchAuthState();
}
