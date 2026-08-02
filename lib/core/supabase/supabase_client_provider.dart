import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

final supabaseConfigProvider = Provider<SupabaseConfig>(
  (ref) => SupabaseConfig.fromEnvironment(),
);

/// The only application-wide Supabase client boundary. Tests override this
/// provider; domain and presentation code never read `Supabase.instance`.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);
