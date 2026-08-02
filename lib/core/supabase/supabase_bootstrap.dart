import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

abstract interface class SupabaseInitializer {
  Future<SupabaseClient> initialize(SupabaseConfig config);
}

class ProductionSupabaseInitializer implements SupabaseInitializer {
  const ProductionSupabaseInitializer();

  @override
  Future<SupabaseClient> initialize(SupabaseConfig config) async {
    final result = await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
    );
    return result.client;
  }
}

class SupabaseBootstrap {
  const SupabaseBootstrap({
    this.initializer = const ProductionSupabaseInitializer(),
  });

  final SupabaseInitializer initializer;

  Future<SupabaseClient?> initialize(SupabaseConfig config) async {
    config.validate();
    if (!config.enabled) return null;
    return initializer.initialize(config);
  }
}
