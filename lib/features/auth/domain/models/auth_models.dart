import '../../../../core/enums/app_enums.dart';

class AuthenticatedIdentity {
  const AuthenticatedIdentity({required this.id, this.email});

  final String id;
  final String? email;
}

class AuthSession {
  const AuthSession({required this.identity, required this.expiresAtUtc});

  final AuthenticatedIdentity identity;
  final DateTime? expiresAtUtc;
}

class DomainUserProfile {
  const DomainUserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.branchId,
    required this.isActive,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final String? branchId;
  final bool isActive;
}

sealed class AuthState {
  const AuthState();
}

class AuthInitializing extends AuthState {
  const AuthInitializing();
}

class AuthAnonymous extends AuthState {
  const AuthAnonymous();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.session, required this.profile});

  final AuthSession session;
  final DomainUserProfile profile;
}

class AuthRejected extends AuthState {
  const AuthRejected(this.failure);

  final AuthFailure failure;
}

sealed class AuthFailure implements Exception {
  const AuthFailure(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => safeMessage;
}

class AuthConfigurationFailure extends AuthFailure {
  const AuthConfigurationFailure()
    : super('Konfigurasi layanan masuk belum tersedia.');
}

class AuthInvalidCredentialsFailure extends AuthFailure {
  const AuthInvalidCredentialsFailure()
    : super('Email atau kata sandi tidak sesuai.');
}

class AuthNetworkFailure extends AuthFailure {
  const AuthNetworkFailure()
    : super('Tidak dapat terhubung ke server. Periksa koneksi Anda.');
}

class AuthSessionExpiredFailure extends AuthFailure {
  const AuthSessionExpiredFailure()
    : super('Sesi telah berakhir. Silakan masuk kembali.');
}

class AuthIdentityNotLinkedFailure extends AuthFailure {
  const AuthIdentityNotLinkedFailure()
    : super('Akun belum memiliki akses ke Aish Warehouse.');
}

class AuthDomainUserInactiveFailure extends AuthFailure {
  const AuthDomainUserInactiveFailure()
    : super('Akun tidak aktif. Hubungi administrator.');
}

class AuthDomainUserMissingFailure extends AuthFailure {
  const AuthDomainUserMissingFailure()
    : super('Profil pengguna tidak tersedia.');
}

class AuthProfileAccessDeniedFailure extends AuthFailure {
  const AuthProfileAccessDeniedFailure()
    : super('Akses profil ditolak. Silakan masuk kembali.');
}

class AuthServerIncompatibleFailure extends AuthFailure {
  const AuthServerIncompatibleFailure()
    : super('Versi server belum kompatibel.');
}

class AuthUnexpectedFailure extends AuthFailure {
  const AuthUnexpectedFailure()
    : super('Terjadi kendala saat memproses sesi. Silakan coba lagi.');
}
