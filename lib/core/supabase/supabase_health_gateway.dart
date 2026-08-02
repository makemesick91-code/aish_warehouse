import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class ServerHealth {
  const ServerHealth({
    required this.status,
    required this.serverTimeUtc,
    required this.schemaRevision,
  });

  final String status;
  final DateTime serverTimeUtc;
  final String schemaRevision;

  bool get isCompatible =>
      schemaRevision == SupabaseConfig.expectedSchemaRevision;
}

abstract interface class SupabaseHealthGateway {
  Future<ServerHealth> check();
}

class ProductionSupabaseHealthGateway implements SupabaseHealthGateway {
  const ProductionSupabaseHealthGateway(this.client);

  final SupabaseClient client;

  @override
  Future<ServerHealth> check() async {
    final response = await client.rpc('get_server_health');
    final rows = response as List<dynamic>;
    if (rows.isEmpty) {
      throw const FormatException('Respons server tidak valid.');
    }
    final row = Map<String, dynamic>.from(rows.single as Map);
    return ServerHealth(
      status: row['status'] as String,
      serverTimeUtc: DateTime.parse(row['server_time_utc'] as String).toUtc(),
      schemaRevision: row['schema_revision'] as String,
    );
  }
}
