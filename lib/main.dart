import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/supabase_config.dart';
import 'core/session/current_user_session.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'core/supabase/supabase_client_provider.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final config = SupabaseConfig.fromEnvironment();
    final client = await const SupabaseBootstrap().initialize(config);

    if (config.enabled) {
      runApp(
        ProviderScope(
          overrides: [
            supabaseConfigProvider.overrideWithValue(config),
            supabaseClientProvider.overrideWithValue(client),
            currentSessionValueProvider.overrideWith(
              (ref) => ref.watch(productionSessionProvider),
            ),
          ],
          child: const AishWarehouseApp(),
        ),
      );
      return;
    }

    runApp(
      ProviderScope(
        overrides: [supabaseConfigProvider.overrideWithValue(config)],
        child: const AishWarehouseApp(),
      ),
    );
  } on SupabaseConfigurationException catch (error) {
    runApp(_ConfigurationFailureApp(message: error.safeMessage));
  } catch (_) {
    runApp(
      const _ConfigurationFailureApp(
        message: 'Layanan masuk tidak dapat disiapkan. Silakan coba lagi.',
      ),
    );
  }
}

class _ConfigurationFailureApp extends StatelessWidget {
  const _ConfigurationFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
