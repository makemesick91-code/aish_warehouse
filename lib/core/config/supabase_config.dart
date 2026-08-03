import 'app_environment.dart';

class SupabaseConfigurationException implements Exception {
  const SupabaseConfigurationException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => safeMessage;
}

class SupabaseConfig {
  const SupabaseConfig({
    required this.environment,
    required this.enabled,
    required this.url,
    required this.publishableKey,
  });

  factory SupabaseConfig.fromEnvironment() {
    const environmentValue = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const enabledValue = String.fromEnvironment(
      'SUPABASE_ENABLED',
      defaultValue: 'false',
    );
    const url = String.fromEnvironment('SUPABASE_URL');
    const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

    final environment = AppEnvironment.parse(environmentValue);
    final enabled = switch (enabledValue.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => throw const SupabaseConfigurationException(
        'SUPABASE_ENABLED harus bernilai true atau false.',
      ),
    };

    final config = SupabaseConfig(
      environment: environment,
      enabled: enabled,
      url: url.trim(),
      publishableKey: publishableKey.trim(),
    );
    config.validate();
    return config;
  }

  final AppEnvironment environment;
  final bool enabled;
  final String url;
  final String publishableKey;

  static const expectedSchemaRevision = 'aish-supabase-003';

  void validate() {
    if (!enabled) {
      if (environment == AppEnvironment.production) {
        throw const SupabaseConfigurationException(
          'Konfigurasi server produksi belum tersedia.',
        );
      }
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const SupabaseConfigurationException(
        'Alamat server Supabase tidak valid.',
      );
    }
    final loopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (uri.scheme != 'https' &&
        !(environment == AppEnvironment.development && loopback)) {
      throw const SupabaseConfigurationException(
        'Alamat server Supabase harus menggunakan HTTPS.',
      );
    }
    if (publishableKey.isEmpty) {
      throw const SupabaseConfigurationException(
        'Publishable key Supabase belum tersedia.',
      );
    }
    if (!publishableKey.startsWith('sb_publishable_')) {
      throw const SupabaseConfigurationException(
        'Aplikasi memerlukan publishable key Supabase.',
      );
    }
  }
}
