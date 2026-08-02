import 'package:aish_warehouse/core/config/app_environment.dart';
import 'package:aish_warehouse/core/config/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupabaseConfig', () {
    test('disabled development mode is explicit and valid', () {
      const config = SupabaseConfig(
        environment: AppEnvironment.development,
        enabled: false,
        url: '',
        publishableKey: '',
      );
      expect(config.validate, returnsNormally);
    });

    test('production cannot silently disable authentication', () {
      const config = SupabaseConfig(
        environment: AppEnvironment.production,
        enabled: false,
        url: '',
        publishableKey: '',
      );
      expect(config.validate, throwsA(isA<SupabaseConfigurationException>()));
    });

    test('enabled configuration requires URL and publishable key', () {
      const missingUrl = SupabaseConfig(
        environment: AppEnvironment.development,
        enabled: true,
        url: '',
        publishableKey: 'sb_publishable_test',
      );
      const missingKey = SupabaseConfig(
        environment: AppEnvironment.development,
        enabled: true,
        url: 'http://127.0.0.1:54321',
        publishableKey: '',
      );
      expect(
        missingUrl.validate,
        throwsA(isA<SupabaseConfigurationException>()),
      );
      expect(
        missingKey.validate,
        throwsA(isA<SupabaseConfigurationException>()),
      );
    });

    test('malformed and insecure remote URLs fail closed', () {
      const malformed = SupabaseConfig(
        environment: AppEnvironment.development,
        enabled: true,
        url: 'not a url',
        publishableKey: 'sb_publishable_test',
      );
      const insecureRemote = SupabaseConfig(
        environment: AppEnvironment.staging,
        enabled: true,
        url: 'http://example.test',
        publishableKey: 'sb_publishable_test',
      );
      expect(
        malformed.validate,
        throwsA(isA<SupabaseConfigurationException>()),
      );
      expect(
        insecureRemote.validate,
        throwsA(isA<SupabaseConfigurationException>()),
      );
    });

    test('local development accepts HTTP loopback', () {
      const config = SupabaseConfig(
        environment: AppEnvironment.development,
        enabled: true,
        url: 'http://127.0.0.1:54321',
        publishableKey: 'sb_publishable_local_test',
      );
      expect(config.validate, returnsNormally);
    });

    test('secret-like client key is rejected', () {
      const config = SupabaseConfig(
        environment: AppEnvironment.production,
        enabled: true,
        url: 'https://project.example.test',
        publishableKey: 'sb_secret_never_client_side',
      );
      expect(config.validate, throwsA(isA<SupabaseConfigurationException>()));
    });

    test('production requires the current publishable key format', () {
      const config = SupabaseConfig(
        environment: AppEnvironment.production,
        enabled: true,
        url: 'https://project.example.test',
        publishableKey: 'legacy-client-key',
      );
      expect(config.validate, throwsA(isA<SupabaseConfigurationException>()));
    });
  });
}
